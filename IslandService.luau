--[[
	IslandService
	Local: ServerScriptService > Services > IslandService

	Atribui uma das 12 ilhas a cada jogador, protege a posse da ilha, mostra o dono,
	reserva a ilha para reconexão e a libera quando a reserva expira.

	ESTADOS DE UMA ILHA
		Free      : sem dono
		Occupied  : dono online
		Reserved  : dono saiu; ilha guardada por Islands.ReconnectGraceSeconds

	SIMULTANEIDADE
		A função claim() NÃO tem pausas (task.wait, WaitForChild, DataStore...). Em Luau, código sem
		pausas nunca é interrompido por outro script, então duas entradas nunca escolhem a mesma ilha.

	API PARA OUTROS SERVIÇOS
		IslandService.GetIslandOf(player)            -> info da ilha do jogador (ou nil)
		IslandService.GetIslandByIndex(index)        -> info
		IslandService.GetIslandAt(position)          -> info da ilha que contém a posição (ou nil)
		IslandService.IsOwner(player, index)         -> boolean
		IslandService.CanBuildAt(player, position)   -> ok, motivo
		IslandService.CanBuildBox(player, cframe, size) -> ok, motivo
		IslandService.TeleportToIsland(player)
		IslandService.OnAssigned(function(player, info, motivo) end)
		IslandService.OnReleased(function(info, ownerUserIdAnterior, motivo) end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))

local Cfg = GameConfig.Islands
if not Cfg then
	error("[IslandService] GameConfig.Islands não existe. Faça o passo 1.2 da Etapa 2 (editar o GameConfig).")
end

local MapService = require(script.Parent:WaitForChild("MapService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local IslandService = {}

-- ===========================================================================
-- ESTADO (somente o servidor altera)
-- ===========================================================================

local states = {}          -- [indice] = estado da ilha
local ownerByUserId = {}   -- [UserId] = indice (inclui ilhas reservadas)
local waiting = {}         -- fila de jogadores sem ilha: { Player, Data }
local assignedCallbacks = {}
local releasedCallbacks = {}

local processWaiting -- declarada aqui, definida mais abaixo

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function log(...)
	if GameConfig.Debug then
		print("[IslandService]", ...)
	end
end

local function fire(list, ...)
	local args = table.pack(...)
	for _, callback in ipairs(list) do
		task.defer(function()
			local ok, err = pcall(callback, table.unpack(args, 1, args.n))
			if not ok then
				warn("[IslandService] Erro em callback:", tostring(err))
			end
		end)
	end
end

local function displayNameOf(player)
	if player.DisplayName ~= "" then
		return player.DisplayName
	end
	return player.Name
end

-- Cópia somente-leitura das informações da ilha (os outros serviços nunca recebem o estado interno)
local function publicInfo(state)
	local slot = state.Slot
	return {
		Index = state.Index,
		Name = slot.Name,
		Model = slot.Model,
		Center = slot.Center,
		SpawnCFrame = slot.SpawnCFrame,
		Radius = slot.Radius,
		BuildRadius = slot.BuildRadius,
		GroundY = slot.GroundY,
		State = state.State,
		OwnerUserId = state.OwnerUserId,
		OwnerName = state.OwnerName,
	}
end

-- ===========================================================================
-- VISUAL (placa, etiqueta e atributos)
-- ===========================================================================

local function createTag(slot)
	local anchor = slot.Model:FindFirstChild("SpawnPoint")
	if not anchor then
		return nil, nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerTag"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Cfg.TagHeight, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = Cfg.TagMaxDistance
	gui.LightInfluence = 0
	gui.Enabled = false

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = label

	gui.Parent = anchor
	return gui, label
end

local function refreshVisuals(state)
	local model = state.Slot.Model
	model:SetAttribute("OwnerUserId", state.OwnerUserId)
	model:SetAttribute("OwnerName", state.OwnerName)
	model:SetAttribute("IslandState", state.State)

	local text
	if state.State == "Free" then
		text = Cfg.FreeText
	elseif state.State == "Reserved" then
		text = state.OwnerName .. Cfg.OfflineSuffix
	else
		text = state.OwnerName
	end

	if state.SubtitleLabel then
		state.SubtitleLabel.Text = text
	end

	if state.TagGui then
		state.TagGui.Enabled = state.State ~= "Free"
		if state.TagLabel then
			state.TagLabel.Text = string.format(Cfg.TagFormat, text)
		end
	end
end

-- ===========================================================================
-- POSSE DA ILHA
-- ===========================================================================

local function releaseSlot(state, reason)
	local previousUserId = state.OwnerUserId
	local previousName = state.OwnerName

	if previousUserId ~= 0 then
		ownerByUserId[previousUserId] = nil
	end

	state.State = "Free"
	state.Player = nil
	state.OwnerUserId = 0
	state.OwnerName = ""
	state.ReserveToken = nil
	state.ReservedUntil = 0

	refreshVisuals(state)
	log(string.format("Ilha %02d LIBERADA (%s). Dono anterior: %s", state.Index, reason, previousName ~= "" and previousName or "-"))
	fire(releasedCallbacks, publicInfo(state), previousUserId, reason)
end

local function reserveSlot(state)
	local grace = Cfg.ReconnectGraceSeconds
	if grace <= 0 then
		releaseSlot(state, "left")
		return
	end

	local token = {}
	state.State = "Reserved"
	state.Player = nil
	state.ReserveToken = token
	state.ReservedUntil = os.time() + grace
	refreshVisuals(state)
	log(string.format("Ilha %02d RESERVADA para %s por %ds", state.Index, state.OwnerName, grace))

	-- Sem loop: um único timer por reserva. Se o dono voltar, o token muda e este timer não faz nada.
	task.delay(grace, function()
		if state.ReserveToken == token and state.State == "Reserved" then
			releaseSlot(state, "expired")
			processWaiting()
		end
	end)
end

-- Escolhe a ilha do jogador. NÃO PODE TER PAUSAS (yields) aqui dentro.
-- Retorna (estado, motivo) ou nil se não houver ilha.
local function claim(player, preferredIndex)
	local userId = player.UserId

	-- 1) Já é dono de uma ilha neste servidor (reconexão ou chamada repetida)
	local ownedIndex = ownerByUserId[userId]
	if ownedIndex then
		local state = states[ownedIndex]
		state.State = "Occupied"
		state.Player = player
		state.OwnerName = displayNameOf(player)
		state.ReserveToken = nil
		state.ReservedUntil = 0
		return state, "reconnected"
	end

	local chosen, how

	-- 2) Ilha preferida (salva no perfil), se estiver livre
	if type(preferredIndex) == "number" then
		local candidate = states[preferredIndex]
		if candidate and candidate.State == "Free" then
			chosen = candidate
			how = "preferred"
		end
	end

	-- 3) Primeira ilha livre
	if not chosen then
		for index = 1, #states do
			local candidate = states[index]
			if candidate.State == "Free" then
				chosen = candidate
				how = "new"
				break
			end
		end
	end

	-- 4) Sem ilhas livres: toma a reserva que expira primeiro
	if not chosen then
		local oldest = nil
		for index = 1, #states do
			local candidate = states[index]
			if candidate.State == "Reserved" and (oldest == nil or candidate.ReservedUntil < oldest.ReservedUntil) then
				oldest = candidate
			end
		end
		if oldest then
			releaseSlot(oldest, "evicted")
			chosen = oldest
			how = "evicted"
		end
	end

	if not chosen then
		return nil
	end

	chosen.State = "Occupied"
	chosen.Player = player
	chosen.OwnerUserId = userId
	chosen.OwnerName = displayNameOf(player)
	chosen.ReserveToken = nil
	chosen.ReservedUntil = 0
	ownerByUserId[userId] = chosen.Index

	return chosen, how
end

-- ===========================================================================
-- SPAWN NA ILHA
-- ===========================================================================

local function teleportToIsland(player)
	if not Cfg.SpawnOnIsland then
		return
	end

	local index = ownerByUserId[player.UserId]
	local state = index and states[index]
	if not state or state.State ~= "Occupied" or state.Player ~= player then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not root or not character.Parent then
		return
	end

	character:PivotTo(state.Slot.SpawnCFrame)
end

-- ===========================================================================
-- ATRIBUIÇÃO
-- ===========================================================================

-- Também NÃO tem pausas (o teleporte roda em outra thread)
local function finishAssign(player, data, state, how)
	if data then
		data.Island = data.Island or {}
		data.Island.PreferredSlot = state.Index
	end

	refreshVisuals(state)
	player:SetAttribute("IslandIndex", state.Index)
	log(string.format("Ilha %02d -> %s (%d) [%s]", state.Index, state.OwnerName, state.OwnerUserId, how))

	fire(assignedCallbacks, player, publicInfo(state), how)
	task.spawn(teleportToIsland, player)
end

local function isWaiting(player)
	for _, entry in ipairs(waiting) do
		if entry.Player == player then
			return true
		end
	end
	return false
end

local function assignPlayer(player, data)
	if player.Parent == nil then
		return
	end

	local preferred = data and data.Island and data.Island.PreferredSlot
	local state, how = claim(player, preferred)

	if not state then
		if not isWaiting(player) then
			table.insert(waiting, { Player = player, Data = data })
		end
		player:SetAttribute("IslandIndex", 0)
		warn(string.format("[IslandService] Sem ilha disponível para %s. Entrou na fila (posição %d).", player.Name, #waiting))
		return
	end

	finishAssign(player, data, state, how)
end

processWaiting = function()
	while #waiting > 0 do
		local entry = waiting[1]
		if entry.Player.Parent == nil then
			table.remove(waiting, 1)
		else
			local preferred = entry.Data and entry.Data.Island and entry.Data.Island.PreferredSlot
			local state, how = claim(entry.Player, preferred)
			if not state then
				return
			end
			table.remove(waiting, 1)
			finishAssign(entry.Player, entry.Data, state, how)
		end
	end
end

local function onPlayerRemoving(player)
	for index, entry in ipairs(waiting) do
		if entry.Player == player then
			table.remove(waiting, index)
			break
		end
	end

	player:SetAttribute("IslandIndex", 0)

	local index = ownerByUserId[player.UserId]
	if not index then
		return
	end

	local state = states[index]
	if state.Player ~= player then
		return -- esta ilha já pertence a uma nova conexão do mesmo jogador
	end

	reserveSlot(state)
	processWaiting()
end

local function hookCharacter(player)
	player.CharacterAdded:Connect(function()
		task.spawn(teleportToIsland, player)
	end)
end

-- ===========================================================================
-- API PÚBLICA
-- ===========================================================================

function IslandService.GetIslandOf(player)
	local index = ownerByUserId[player.UserId]
	local state = index and states[index]
	if state and state.State == "Occupied" and state.Player == player then
		return publicInfo(state)
	end
	return nil
end

function IslandService.GetIslandByIndex(index)
	local state = states[index]
	return state and publicInfo(state) or nil
end

function IslandService.GetIslandAt(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end
	for index = 1, #states do
		local state = states[index]
		local slot = state.Slot
		local dx = position.X - slot.Center.X
		local dz = position.Z - slot.Center.Z
		if dx * dx + dz * dz <= slot.Radius * slot.Radius then
			return publicInfo(state)
		end
	end
	return nil
end

function IslandService.IsOwner(player, index)
	local info = IslandService.GetIslandOf(player)
	return info ~= nil and info.Index == index
end

-- Validação de construção. SEMPRE chame no servidor, com a posição que o SERVIDOR calculou.
-- Retorna true, ou false + motivo.
function IslandService.CanBuildAt(player, position)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Jogador inválido"
	end
	if typeof(position) ~= "Vector3" or position.X ~= position.X or position.Y ~= position.Y or position.Z ~= position.Z then
		return false, "Posição inválida"
	end

	local own = IslandService.GetIslandOf(player)
	if not own then
		return false, "Você ainda não tem uma ilha"
	end

	local dx = position.X - own.Center.X
	local dz = position.Z - own.Center.Z
	if dx * dx + dz * dz > own.BuildRadius * own.BuildRadius then
		local other = IslandService.GetIslandAt(position)
		if other and other.Index ~= own.Index then
			return false, "Esta ilha pertence a outro jogador"
		end
		return false, "Fora da área de construção da sua ilha"
	end

	if position.Y < own.GroundY - 2 or position.Y > own.GroundY + Cfg.MaxBuildHeight then
		return false, "Altura inválida"
	end

	return true
end

-- Valida o "pé" (4 cantos + centro) de uma peça. Use para construções.
function IslandService.CanBuildBox(player, cframe, size)
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return false, "Dados inválidos"
	end

	local hx, hz = size.X / 2, size.Z / 2
	local offsets = {
		Vector3.new(0, 0, 0),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(-hx, 0, -hz),
	}

	for _, offset in ipairs(offsets) do
		local ok, reason = IslandService.CanBuildAt(player, (cframe * CFrame.new(offset)).Position)
		if not ok then
			return false, reason
		end
	end
	return true
end

function IslandService.TeleportToIsland(player)
	task.spawn(teleportToIsland, player)
end

function IslandService.OnAssigned(callback)
	table.insert(assignedCallbacks, callback)
end

function IslandService.OnReleased(callback)
	table.insert(releasedCallbacks, callback)
end

-- Mostra o estado das 12 ilhas no Output (útil nos testes)
function IslandService.PrintStatus()
	print("[IslandService] ===== STATUS DAS ILHAS =====")
	for index = 1, #states do
		local state = states[index]
		print(string.format("  Ilha %02d | %-8s | %s", index, state.State, state.OwnerName ~= "" and state.OwnerName or "-"))
	end
	print(string.format("  Fila de espera: %d", #waiting))
end

-- Funções de TESTE (só funcionam com GameConfig.Debug = true)
function IslandService.Debug_SimulateLeave(player)
	if not GameConfig.Debug then
		return false
	end
	onPlayerRemoving(player)
	return true
end

function IslandService.Debug_SimulateRejoin(player)
	if not GameConfig.Debug then
		return false
	end
	assignPlayer(player, PlayerDataService.GetData(player))
	return true
end

-- ===========================================================================
-- CICLO DE VIDA
-- ===========================================================================

function IslandService.Init()
end

function IslandService.Start()
	if not MapService.IsReady() then
		warn("[IslandService] MapService não está pronto. IslandService DESATIVADO.")
		return
	end

	for _, slot in ipairs(MapService.GetIslandSlots()) do
		local state = {
			Index = slot.Index,
			Slot = slot,
			State = "Free",
			Player = nil,
			OwnerUserId = 0,
			OwnerName = "",
			ReserveToken = nil,
			ReservedUntil = 0,
		}
		state.SubtitleLabel = slot.Sign and slot.Sign:FindFirstChild("Subtitle", true) or nil
		state.TagGui, state.TagLabel = createTag(slot)
		states[slot.Index] = state
		refreshVisuals(state)
	end

	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		hookCharacter(player)
	end

	-- A ilha só é atribuída depois que os dados do jogador carregam
	PlayerDataService.OnLoaded(function(player, data)
		assignPlayer(player, data)
	end)

	log(string.format("Pronto. %d ilhas gerenciadas.", #states))
end

return IslandService