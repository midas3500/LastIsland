--[[
	IslandService (v2 — ilhas DINÂMICAS)
	Local: ServerScriptService > Services > IslandService   (SUBSTITUI o atual)

	Uma ilha individual para cada jogador conectado, criada na hora:
	  - 1 jogador = 1 ilha, 2 jogadores = 2 ilhas, 5 jogadores = 5 ilhas
	  - as ilhas ficam o mais longe possível umas das outras (extremidades opostas do círculo)
	  - quando alguém sai, a ilha é reservada pelo tempo de reconexão e depois DESTRUÍDA
	  - reconectou dentro do prazo: volta para a MESMA ilha (nunca duplica)
	  - não existe mais fila de espera nem lobby

	ESTADOS: Occupied (dono online) | Reserved (dono saiu; guardada por Islands.ReconnectGraceSeconds)

	SIMULTANEIDADE: a escolha da posição/índice (claim) não tem pausas, então duas entradas ao mesmo
	tempo nunca escolhem o mesmo lugar. A construção da ilha roda depois, em outra thread.

	API (a mesma de antes):
	  GetIslandOf(player) / GetIslandByIndex(i) / GetIslandAt(pos) / IsOwner(player, i)
	  CanBuildAt(player, pos) / CanBuildBox(player, cframe, size) / TeleportToIsland(player)
	  OnAssigned(function(player, info, motivo)) / OnReleased(function(info, donoAnterior, motivo))
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local Cfg = GameConfig.Islands
if not Cfg then
	error("[IslandService] GameConfig.Islands não existe.")
end

local MapService = require(script.Parent:WaitForChild("MapService"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local IslandService = {}

local states = {}         -- [indice] = estado da ilha
local ownerByUserId = {}  -- [UserId] = indice (inclui ilhas reservadas)
local assignedCallbacks = {}
local releasedCallbacks = {}

local MAX_ISLANDS = Cfg.MaxDynamicIslands or 48
local BUILD_RETRIES = 3

----------------------------------------------------------------------
-- Utilitários
----------------------------------------------------------------------
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

local function angleDiff(a, b)
	return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

local function tierByName(tiers, name)
	for _, tier in ipairs(tiers) do
		if tier.Name == name then return tier end
	end
	error("Tier não encontrado no MapConfig: " .. tostring(name))
end

-- Cópia somente-leitura das informações da ilha
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

-- Dados da ilha calculados ANTES de ela existir (iguais aos que o MapService vai gerar)
local function placeholderSlot(index, center)
	local pcfg = MapConfig.PlayerIslands
	local ground = tierByName(pcfg.Tiers, pcfg.GroundTier)
	local groundY = ground.Top
	local apothem = pcfg.Radius * ground.Scale * math.cos(math.pi / MapConfig.Style.PrismSides)
	return {
		Index = index,
		Name = string.format("Island_%02d", index),
		Model = nil,
		Center = Vector3.new(center.X, groundY, center.Z),
		SpawnCFrame = CFrame.new(center.X, groundY + 3, center.Z),
		Radius = pcfg.Radius,
		BuildRadius = apothem * 0.95,
		GroundY = groundY,
	}
end

----------------------------------------------------------------------
-- Visual (placa, etiqueta e atributos)
----------------------------------------------------------------------
local function createTag(slot)
	local anchor = slot.Model and slot.Model:FindFirstChild("SpawnPoint")
	if not anchor then return nil, nil end

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
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	padding.Parent = label

	gui.Parent = anchor
	return gui, label
end

local function refreshVisuals(state)
	local model = state.Slot.Model
	if not model then return end
	model:SetAttribute("OwnerUserId", state.OwnerUserId)
	model:SetAttribute("OwnerName", state.OwnerName)
	model:SetAttribute("IslandState", state.State)

	local text
	if state.State == "Reserved" then
		text = state.OwnerName .. Cfg.OfflineSuffix
	else
		text = state.OwnerName
	end
	if state.SubtitleLabel then
		state.SubtitleLabel.Text = text
	end
	if state.TagGui then
		state.TagGui.Enabled = true
		if state.TagLabel then
			state.TagLabel.Text = string.format(Cfg.TagFormat, text)
		end
	end
end

----------------------------------------------------------------------
-- Construção e destruição das ilhas
----------------------------------------------------------------------
local function getResourceService()
	local module = script.Parent:FindFirstChild("ResourceService")
	if not module then return nil end
	local ok, service = pcall(require, module) -- só em tempo de execução (evita require circular)
	return ok and service or nil
end

local warnedNodes = false
local function spawnNodes(state)
	local resourceService = getResourceService()
	if not resourceService or not resourceService.SpawnAtMarker then
		if not warnedNodes then
			warnedNodes = true
			warn("[IslandService] ResourceService sem SpawnAtMarker: aplique o patch do ResourceService. As ilhas ficam sem recursos.")
		end
		return
	end
	local map = Workspace:FindFirstChild(MapConfig.Folders.Map)
	local spawnsRoot = map and map:FindFirstChild(MapConfig.Folders.ResourceSpawns)
	local folder = spawnsRoot and spawnsRoot:FindFirstChild(state.Slot.Name)
	if not folder then return end
	for _, marker in ipairs(folder:GetChildren()) do
		if marker:IsA("BasePart") and marker:GetAttribute("ResourceType") then
			local model = resourceService.SpawnAtMarker(marker)
			if model then
				table.insert(state.Nodes, model)
			end
		end
	end
end

-- Coluna de areia do fundo do mar até a ilha (o mar é fundo, a ilha não pode ficar "flutuando")
local function buildPedestal(slot)
	local sea = MapConfig.WaterLevel
	local bottom = sea - MapConfig.Ocean.Depth
	local top = sea - 2
	local diameter = slot.Radius * 1.5
	local pedestal = Instance.new("Part")
	pedestal.Name = "Pedestal"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(top - bottom, diameter, diameter)
	pedestal.CFrame = CFrame.new(slot.Center.X, (top + bottom) / 2, slot.Center.Z) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Anchored = true
	pedestal.CanCollide = false
	pedestal.CanQuery = false
	pedestal.CanTouch = false
	pedestal.Material = Enum.Material.Sand
	pedestal.Color = Color3.fromRGB(205, 182, 135)
	pedestal.Parent = slot.Model
end

local function buildState(state)
	local ok, slot = pcall(MapService.BuildIslandAt, state.Index, state.Center)
	if not ok or not slot then
		warn("[IslandService] Falha ao construir a ilha " .. state.Index .. ": " .. tostring(slot))
		return false
	end
	state.Slot = slot
	buildPedestal(slot)
	state.SubtitleLabel = slot.Sign and slot.Sign:FindFirstChild("Subtitle", true) or nil
	state.TagGui, state.TagLabel = createTag(slot)
	spawnNodes(state)
	state.Ready = true
	return true
end

local function destroyState(state)
	if states[state.Index] ~= state then return end
	state.Destroyed = true
	local resourceService = getResourceService()
	for _, model in ipairs(state.Nodes) do
		if model.Parent and resourceService and resourceService.RemoveNode then
			pcall(resourceService.RemoveNode, model)
		end
	end
	state.Nodes = {}
	pcall(MapService.RemoveIsland, state.Index)
	states[state.Index] = nil
end

----------------------------------------------------------------------
-- Posse da ilha
----------------------------------------------------------------------
local function releaseSlot(state, reason)
	if states[state.Index] ~= state then return end
	local previousUserId = state.OwnerUserId
	local previousName = state.OwnerName
	if previousUserId ~= 0 and ownerByUserId[previousUserId] == state.Index then
		ownerByUserId[previousUserId] = nil
	end
	state.ReserveToken = nil
	local info = publicInfo(state)
	info.State = "Free"
	log(string.format("Ilha %02d REMOVIDA (%s). Dono anterior: %s", state.Index, reason, previousName ~= "" and previousName or "-"))
	fire(releasedCallbacks, info, previousUserId, reason)
	destroyState(state)
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
	task.delay(grace, function()
		if state.ReserveToken == token and state.State == "Reserved" then
			releaseSlot(state, "expired")
		end
	end)
end

-- Escolhe o ângulo mais distante das ilhas existentes (1ª ilha: ângulo base; 2ª: oposta; 3ª/4ª: a 90°...)
local function pickAngle()
	local base = math.rad(MapConfig.PlayerIslands.AngleOffsetDeg or -90)
	local used = {}
	for _, state in pairs(states) do
		table.insert(used, state.Angle)
	end
	if #used == 0 then return base end
	local best, bestScore = base, -1
	local steps = 72
	for i = 0, steps - 1 do
		local angle = base + i * (2 * math.pi / steps)
		local score = math.huge
		for _, other in ipairs(used) do
			score = math.min(score, angleDiff(angle, other))
		end
		if score > bestScore + 1e-6 then
			best, bestScore = angle, score
		end
	end
	return best
end

-- NÃO PODE TER PAUSAS (yields) aqui dentro.
local function claim(player)
	local userId = player.UserId

	-- já é dono de uma ilha neste servidor (reconexão ou chamada repetida)
	local ownedIndex = ownerByUserId[userId]
	if ownedIndex and states[ownedIndex] then
		local state = states[ownedIndex]
		state.State = "Occupied"
		state.Player = player
		state.OwnerName = displayNameOf(player)
		state.ReserveToken = nil
		state.ReservedUntil = 0
		return state, "reconnected"
	end

	local count = 0
	for _ in pairs(states) do count += 1 end
	if count >= MAX_ISLANDS then
		return nil
	end

	local index = 1
	while states[index] do index += 1 end

	local angle = pickAngle()
	local pcfg = MapConfig.PlayerIslands
	local ringCenter = pcfg.Center or MapConfig.MainIsland.Position
	local center = ringCenter + Vector3.new(math.cos(angle) * pcfg.RingRadius, 0, math.sin(angle) * pcfg.RingRadius)

	local state = {
		Index = index,
		Angle = angle,
		Center = center,
		Slot = placeholderSlot(index, center),
		State = "Occupied",
		Player = player,
		OwnerUserId = userId,
		OwnerName = displayNameOf(player),
		ReserveToken = nil,
		ReservedUntil = 0,
		Ready = false,
		Destroyed = false,
		Nodes = {},
	}
	states[index] = state
	ownerByUserId[userId] = index
	return state, "new"
end

----------------------------------------------------------------------
-- Spawn na ilha
----------------------------------------------------------------------
local function teleportToIsland(player)
	if not Cfg.SpawnOnIsland then return end
	local index = ownerByUserId[player.UserId]
	local state = index and states[index]
	if not state or not state.Ready or state.State ~= "Occupied" or state.Player ~= player then return end

	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not root or not character.Parent then return end
	character:PivotTo(state.Slot.SpawnCFrame)
end

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

local function assignPlayer(player, data, attempt)
	attempt = attempt or 1
	if player.Parent == nil then return end

	local state, how = claim(player)
	if not state then
		warn(string.format("[IslandService] Limite de %d ilhas atingido; %s tentará de novo em 5s.", MAX_ISLANDS, player.Name))
		player:SetAttribute("IslandIndex", 0)
		task.delay(5, function() assignPlayer(player, data, attempt) end)
		return
	end

	if state.Ready then
		finishAssign(player, data, state, how)
		return
	end

	-- constrói a ilha (fora do claim, pode demorar um pouco)
	task.spawn(function()
		if not buildState(state) then
			-- falhou: remove o que sobrou e tenta de novo
			if state.OwnerUserId ~= 0 and ownerByUserId[state.OwnerUserId] == state.Index then
				ownerByUserId[state.OwnerUserId] = nil
			end
			destroyState(state)
			if attempt < BUILD_RETRIES and player.Parent then
				task.wait(2)
				assignPlayer(player, data, attempt + 1)
			else
				warn("[IslandService] Não foi possível criar a ilha de " .. player.Name)
			end
			return
		end
		if state.Destroyed or player.Parent == nil or state.Player ~= player then
			return -- o jogador saiu durante a construção (a reserva/expiração cuida da ilha)
		end
		finishAssign(player, data, state, how)
	end)
end

local function onPlayerRemoving(player)
	player:SetAttribute("IslandIndex", 0)
	local index = ownerByUserId[player.UserId]
	if not index then return end
	local state = states[index]
	if not state or state.Player ~= player then
		return -- esta ilha já pertence a uma nova conexão do mesmo jogador
	end
	reserveSlot(state)
end

local function hookCharacter(player)
	player.CharacterAdded:Connect(function()
		task.spawn(teleportToIsland, player)
	end)
end

----------------------------------------------------------------------
-- API pública
----------------------------------------------------------------------
function IslandService.GetIslandOf(player)
	local index = ownerByUserId[player.UserId]
	local state = index and states[index]
	if state and state.Ready and state.State == "Occupied" and state.Player == player then
		return publicInfo(state)
	end
	return nil
end

function IslandService.GetIslandByIndex(index)
	local state = states[index]
	return state and publicInfo(state) or nil
end

function IslandService.GetIslandAt(position)
	if typeof(position) ~= "Vector3" then return nil end
	for _, state in pairs(states) do
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

function IslandService.CanBuildBox(player, cframe, size)
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return false, "Dados inválidos"
	end
	local hx, hz = size.X / 2, size.Z / 2
	local offsets = { Vector3.new(0, 0, 0), Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz), Vector3.new(hx, 0, -hz), Vector3.new(-hx, 0, -hz) }
	for _, offset in ipairs(offsets) do
		local ok, reason = IslandService.CanBuildAt(player, (cframe * CFrame.new(offset)).Position)
		if not ok then return false, reason end
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

function IslandService.PrintStatus()
	print("[IslandService] ===== STATUS DAS ILHAS =====")
	local list = {}
	for index in pairs(states) do table.insert(list, index) end
	table.sort(list)
	for _, index in ipairs(list) do
		local state = states[index]
		print(string.format(" Ilha %02d | %-8s | %-20s | ângulo %4d° | %s", index, state.State, state.OwnerName,
			math.floor(math.deg(state.Angle) % 360), state.Ready and "pronta" or "construindo"))
	end
	print(string.format(" Total: %d ilha(s)", #list))
end

-- Funções de TESTE (só com GameConfig.Debug = true)
function IslandService.Debug_SimulateLeave(player)
	if not GameConfig.Debug then return false end
	onPlayerRemoving(player)
	return true
end

function IslandService.Debug_SimulateRejoin(player)
	if not GameConfig.Debug then return false end
	assignPlayer(player, PlayerDataService.GetData(player))
	return true
end

----------------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------------
-- Plataforma invisível, alta no céu, onde o jogador espera os dados carregarem (não cai no mar nem na ilha central)
local function createArrivalSpawn()
	local old = Workspace:FindFirstChild("ArrivalSpawn")
	if old then old:Destroy() end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArrivalSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(40, 2, 40)
	local p = MapConfig.MainIsland.Position
	spawn.Position = Vector3.new(p.X, 900, p.Z)
	for _, child in ipairs(spawn:GetChildren()) do
		if child:IsA("Decal") then child:Destroy() end
	end
	spawn.Parent = Workspace
end

function IslandService.Init()
end

function IslandService.Start()
	if not MapService.IsReady() then
		warn("[IslandService] MapService não está pronto. IslandService DESATIVADO.")
		return
	end
	if not MapService.BuildIslandAt or not MapService.RemoveIsland then
		warn("[IslandService] O MapService ainda não tem BuildIslandAt/RemoveIsland. Aplique o patch do MapService (INSTALAR.md). Ilhas dinâmicas DESATIVADAS.")
		return
	end

	createArrivalSpawn()

	Players.PlayerAdded:Connect(hookCharacter)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		hookCharacter(player)
	end

	-- a ilha só é criada depois que os dados do jogador carregam
	PlayerDataService.OnLoaded(function(player, data)
		assignPlayer(player, data)
	end)

	log("Pronto. Ilhas dinâmicas ativas (uma por jogador).")
end

return IslandService

