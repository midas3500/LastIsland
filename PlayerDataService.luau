--[[
	PlayerDataService
	Local: ServerScriptService > Services > PlayerDataService

	Salvamento seguro de dados dos jogadores.

	Proteções:
	- UpdateAsync (nunca sobrescreve às cegas) + retry com espera crescente
	- Trava de sessão (o mesmo jogador não abre o perfil em 2 servidores)
	- Se o carregamento FALHAR, o jogador não joga com perfil vazio que depois sobrescreveria
	  o perfil real: ele é expulso (padrão) ou fica em modo seguro sem salvar
	- Dados de versão MAIS NOVA que o servidor entende viram somente-leitura
	- Salvamento automático, ao sair e em BindToClose (desligamento do servidor)
	- Fora do ar/sem permissão no Studio: usa memória (mock) e avisa

	USO POR OUTROS SERVIÇOS:
		local data = PlayerDataService.GetData(player) -- tabela viva do perfil ou nil
		data.Coins += 10                                -- altere direto; o autosave grava
		PlayerDataService.Save(player, false)           -- (opcional) salvar agora
		PlayerDataService.OnLoaded(function(player, data) ... end)
		PlayerDataService.OnLeaving(function(player, data) ... end)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
local Cfg = GameConfig.Data

local PlayerDataService = {}

local SERVER_ID = (game.JobId ~= "") and game.JobId or "studio"

local sessions = {}            -- [Player] = sessão
local store = nil              -- DataStore real ou mock
local usingMock = false
local shuttingDown = false
local loadedCallbacks = {}
local leavingCallbacks = {}

-- Utilitários ------------------------------------------------------------

local function log(...)
	if GameConfig.Debug then
		print("[PlayerDataService]", ...)
	end
end

local function warnLog(...)
	warn("[PlayerDataService]", ...)
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Completa campos que faltam (jogadores antigos recebem campos novos do DefaultProfile)
local function reconcile(target, template)
	for key, templateValue in pairs(template) do
		if target[key] == nil then
			target[key] = deepCopy(templateValue)
		elseif type(templateValue) == "table" and type(target[key]) == "table" then
			reconcile(target[key], templateValue)
		end
	end
end

-- Migrações: Migrations[N] converte dados da versão N para a N+1.
-- Exemplo futuro (quando SchemaVersion virar 2):
--   Migrations[1] = function(data) data.Coins = data.Gold or 0 end
local Migrations = {}

local function dataKey(userId)
	return "Player_" .. tostring(userId)
end

-- DataStore falso, em memória (só para testes quando o real não está disponível)
local MockStore = {}
MockStore.__index = MockStore

function MockStore.new()
	return setmetatable({ data = {} }, MockStore)
end

function MockStore:GetAsync(key)
	return deepCopy(self.data[key])
end

function MockStore:UpdateAsync(key, transform)
	local newValue = transform(deepCopy(self.data[key]))
	if newValue == nil then
		return nil
	end
	self.data[key] = deepCopy(newValue)
	return deepCopy(newValue)
end

local function storeUpdate(key, transform)
	if Cfg.SimulateFailure then
		error("Falha simulada do DataStore (GameConfig.Data.SimulateFailure = true)")
	end
	return store:UpdateAsync(key, transform)
end

-- Tenta uma operação várias vezes, esperando cada vez mais entre as tentativas
local function withRetry(label, fn)
	local lastError
	for attempt = 1, Cfg.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warnLog(string.format("%s falhou (tentativa %d/%d): %s", label, attempt, Cfg.MaxRetries, tostring(result)))
		if attempt < Cfg.MaxRetries then
			task.wait(Cfg.RetryBaseDelay * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

local function isLockedByOther(record)
	local meta = record and record.Meta
	return meta ~= nil
		and meta.JobId ~= nil
		and meta.JobId ~= SERVER_ID
		and (os.time() - (meta.Time or 0)) < Cfg.LockTimeout
end

local function fire(list, player, data)
	for _, callback in ipairs(list) do
		task.spawn(function()
			local ok, err = pcall(callback, player, data)
			if not ok then
				warnLog("Erro em callback:", tostring(err))
			end
		end)
	end
end

-- Carregamento -------------------------------------------------------------

-- Retorna (true, dados|nil) em sucesso (nil = jogador novo) ou (false, motivo)
local function loadProfile(userId)
	local key = dataKey(userId)

	for _ = 1, Cfg.LockWaitAttempts do
		local lockedBy = nil
		local capturedData = nil
		local corrupt = false

		local ok, err = withRetry("Carregar " .. key, function()
			lockedBy = nil
			capturedData = nil
			corrupt = false
			storeUpdate(key, function(old)
				if isLockedByOther(old) then
					lockedBy = old.Meta.JobId
					return nil -- cancela: não altera nada
				end
				old = old or {}
				if old.Data ~= nil and type(old.Data) ~= "table" then
					corrupt = true
					return nil -- dado estranho: não mexe
				end
				capturedData = deepCopy(old.Data)
				old.Meta = { JobId = SERVER_ID, Time = os.time() }
				return old
			end)
		end)

		if not ok then
			return false, "DataStore indisponível: " .. tostring(err)
		end
		if corrupt then
			return false, "Perfil com formato inesperado (preservado sem alterações)"
		end
		if lockedBy then
			warnLog(string.format("Perfil %s em uso pelo servidor %s. Aguardando...", key, tostring(lockedBy)))
			task.wait(Cfg.LockWaitDelay)
		else
			return true, capturedData
		end
	end

	return false, "Perfil em uso por outro servidor"
end

local function prepareData(data)
	if data == nil then
		local fresh = deepCopy(GameConfig.DefaultProfile)
		fresh.CreatedAt = os.time()
		return fresh, false
	end

	data.SchemaVersion = data.SchemaVersion or 1

	if data.SchemaVersion > Cfg.SchemaVersion then
		warnLog("Perfil de versão MAIS NOVA que este servidor. Modo somente-leitura.")
		return data, true
	end

	while data.SchemaVersion < Cfg.SchemaVersion do
		local migrate = Migrations[data.SchemaVersion]
		if migrate then
			local ok, err = pcall(migrate, data)
			if not ok then
				warnLog("Falha na migração:", tostring(err))
				return data, true
			end
		end
		data.SchemaVersion += 1
	end

	reconcile(data, GameConfig.DefaultProfile)
	return data, false
end

-- Salvamento -----------------------------------------------------------------

local function releaseLockOnly(userId)
	local key = dataKey(userId)
	withRetry("Liberar trava " .. key, function()
		storeUpdate(key, function(old)
			if old and old.Meta and old.Meta.JobId == SERVER_ID then
				old.Meta.JobId = nil
				old.Meta.Time = os.time()
				return old
			end
			return nil
		end)
	end)
end

local function saveSession(session, release)
	if session.Released then
		return true
	end

	if session.ReadOnly then
		-- Nunca grava dados em modo seguro; só devolve a trava, se tiver
		if release then
			if session.HasLock then
				releaseLockOnly(session.UserId)
			end
			session.Released = true
		end
		return false
	end

	if session.Saving then
		if not release then
			return false
		end
		local waited = 0
		while session.Saving and waited < 10 do
			task.wait(0.1)
			waited += 0.1
		end
		if session.Released then
			return true
		end
	end

	session.Saving = true

	-- Atualiza tempo de jogo
	local now = os.clock()
	session.Data.Stats.PlayTime += (now - session.ClockMark)
	session.ClockMark = now

	local snapshot = deepCopy(session.Data)
	local key = dataKey(session.UserId)
	local lostLock = false

	local ok, err = withRetry("Salvar " .. key, function()
		lostLock = false
		storeUpdate(key, function(old)
			if isLockedByOther(old) then
				lostLock = true
				return nil
			end
			return {
				Data = snapshot,
				Meta = { JobId = (not release) and SERVER_ID or nil, Time = os.time() },
			}
		end)
	end)

	session.Saving = false

	if ok and lostLock then
		warnLog(string.format("Trava de %s foi tomada por outro servidor. Salvamento cancelado.", key))
		session.ReadOnly = true
		return false
	end

	if ok then
		if release then
			session.Released = true
		end
		log(string.format("Salvo: %s%s", key, release and " (trava liberada)" or ""))
		return true
	end

	warnLog(string.format("FALHA ao salvar %s. Dados ainda na memória: %s", key, tostring(err)))
	return false
end

-- Eventos de jogador ---------------------------------------------------------

local function onPlayerAdded(player)
	if sessions[player] then
		return
	end

	local session = {
		UserId = player.UserId,
		Data = nil,
		Loaded = false,
		ReadOnly = false,
		HasLock = false,
		Saving = false,
		Released = false,
		Abandoned = false,
		ClockMark = os.clock(),
	}
	sessions[player] = session

	local success, result = loadProfile(player.UserId)

	if not success then
		warnLog(string.format("Não foi possível carregar dados de %s: %s", player.Name, tostring(result)))

		if session.Abandoned or player.Parent == nil then
			sessions[player] = nil
			return
		end

		if Cfg.KickOnLoadFailure then
			sessions[player] = nil
			player:Kick(Cfg.KickMessage)
			return
		end

		-- Modo seguro: joga com perfil temporário que NUNCA será salvo
		session.Data = deepCopy(GameConfig.DefaultProfile)
		session.ReadOnly = true
		session.Loaded = true
		session.ClockMark = os.clock()
		player:SetAttribute("DataLoaded", true)
		player:SetAttribute("DataReadOnly", true)
		warnLog(string.format("%s está em MODO SEGURO: nada será salvo nesta sessão.", player.Name))
		fire(loadedCallbacks, player, session.Data)
		return
	end

	session.HasLock = true
	local data, readOnly = prepareData(result)
	session.Data = data
	session.ReadOnly = readOnly
	session.Loaded = true
	session.ClockMark = os.clock()

	-- O jogador saiu enquanto carregava: devolve a trava e encerra
	if session.Abandoned or player.Parent == nil then
		saveSession(session, true)
		sessions[player] = nil
		return
	end

	if not readOnly then
		data.Stats.Joins += 1
	end

	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataReadOnly", readOnly)

	log(string.format(
		"Dados carregados: %s (%d) | Moedas=%d | Entradas=%d | PlayTime=%ds%s",
		player.Name, player.UserId, data.Coins, data.Stats.Joins, math.floor(data.Stats.PlayTime),
		readOnly and " | SOMENTE-LEITURA" or ""
		))

	fire(loadedCallbacks, player, data)
end

local function onPlayerRemoving(player)
	local session = sessions[player]
	if not session then
		return
	end

	if not session.Loaded then
		session.Abandoned = true -- o carregamento em andamento cuida da limpeza
		return
	end

	fire(leavingCallbacks, player, session.Data)

	local saved = saveSession(session, true)
	if not saved and not session.ReadOnly then
		warnLog(string.format("ATENÇÃO: dados de %s podem não ter sido salvos.", player.Name))
	end

	sessions[player] = nil
end

local function autosaveLoop()
	while not shuttingDown do
		task.wait(Cfg.AutoSaveInterval)
		if shuttingDown then
			break
		end

		local list = {}
		for player, session in pairs(sessions) do
			if session.Loaded and not session.ReadOnly then
				table.insert(list, player)
			end
		end

		for _, player in ipairs(list) do
			local session = sessions[player]
			if session then
				saveSession(session, false)
			end
		end
	end
end

-- API pública ------------------------------------------------------------------

function PlayerDataService.GetData(player)
	local session = sessions[player]
	if session and session.Loaded then
		return session.Data
	end
	return nil
end

function PlayerDataService.IsLoaded(player)
	local session = sessions[player]
	return session ~= nil and session.Loaded
end

function PlayerDataService.IsReadOnly(player)
	local session = sessions[player]
	return session ~= nil and session.ReadOnly
end

-- Espera os dados carregarem (use com moderação). Retorna a tabela ou nil.
function PlayerDataService.WaitForData(player, timeout)
	local limit = os.clock() + (timeout or 30)
	while player.Parent ~= nil and os.clock() < limit do
		local data = PlayerDataService.GetData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

function PlayerDataService.Save(player, release)
	local session = sessions[player]
	if not session or not session.Loaded then
		return false
	end
	return saveSession(session, release == true)
end

-- Chamado quando os dados de um jogador ficam prontos (inclusive para quem já estava carregado)
function PlayerDataService.OnLoaded(callback)
	table.insert(loadedCallbacks, callback)
	for player, session in pairs(sessions) do
		if session.Loaded then
			task.spawn(callback, player, session.Data)
		end
	end
end

-- Chamado logo ANTES do salvamento final de um jogador que está saindo
function PlayerDataService.OnLeaving(callback)
	table.insert(leavingCallbacks, callback)
end

-- Ciclo de vida -----------------------------------------------------------------

function PlayerDataService.Init()
	local storeName = Cfg.StoreName .. "_" .. Cfg.StoreVersion

	if Cfg.ForceMockStore then
		store = MockStore.new()
		usingMock = true
		warnLog("ForceMockStore ativo: usando memória. NADA será salvo de verdade.")
		return
	end

	local realStore = DataStoreService:GetDataStore(storeName)

	if RunService:IsStudio() then
		-- Testa se o Studio tem permissão para usar DataStore
		local ok, err = pcall(function()
			return realStore:GetAsync("__probe")
		end)
		if not ok then
			store = MockStore.new()
			usingMock = true
			warnLog("DataStore real indisponível no Studio: " .. tostring(err))
			warnLog("Usando memória (mock): os dados valem só até você apertar Stop.")
			warnLog("Para testar salvamento de verdade, siga a seção 4 do guia.")
			return
		end
	end

	store = realStore
	log("DataStore real em uso: " .. storeName)
end

function PlayerDataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	game:BindToClose(function()
		shuttingDown = true

		local list = {}
		for player in pairs(sessions) do
			table.insert(list, player)
		end

		local pending = 0
		for _, player in ipairs(list) do
			pending += 1
			task.spawn(function()
				local session = sessions[player]
				if session and session.Loaded then
					saveSession(session, true)
				end
				pending -= 1
			end)
		end

		local startedAt = os.clock()
		while pending > 0 and os.clock() - startedAt < 25 do
			task.wait(0.1)
		end
	end)

	task.spawn(autosaveLoop)

	log(usingMock and "Pronto (modo MOCK)." or "Pronto (DataStore real).")
end

return PlayerDataService