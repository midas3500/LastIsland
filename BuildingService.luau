--[[
	BuildingService (v2)
	Local: ServerScriptService > Services > BuildingService   (SUBSTITUI o arquivo vazio)

	Construção 100% validada no SERVIDOR. O cliente só manda "quero construir X aqui, girado Y".
	O servidor recalcula a posição, confere tudo e só então gasta os materiais e cria a peça.

	REGRAS (todas no servidor)
		- o jogador precisa ter ilha e ser o dono; só constrói dentro da PRÓPRIA ilha
		  (IslandService.CanBuildBox testa o centro e os 4 cantos da peça)
		- terreno: o solo sob a peça precisa ser firme e estar no nível da ilha (raycast)
		- espaço livre: sem sobrepor recursos, decoração, placa ou outras construções (BuildingRules)
		- longe do ponto de nascimento da ilha e sem jogador dentro da peça
		- limites: total por ilha (BuildingConfig.MaxBuildingsPerIsland) e por tipo (Max)
		- materiais: tudo ou nada (InventoryService.RemoveItems)

	PERSISTÊNCIA: data.Buildings = lista de { Id, Type, X, Z, Yaw, Items? }.
	X e Z são RELATIVOS ao centro da ilha; se o jogador cair em outra ilha, a base vai junto.

	COMUNICAÇÃO (remote BuildRequest)
		Cliente -> Servidor:  "Place", tipo, posição(Vector3), rotação(graus)  |  "Remove", modelo
		Servidor -> Cliente:  "Placed", tipo  |  "Removed", tipo  |  "Denied", texto  |  "Info", texto

	API
		BuildingService.GetBuildings(islandIndex)             -> lista de { Id, Type, Model }
		BuildingService.IsProtected(position)                 -> true se há Torre de Proteção cobrindo
		BuildingService.Debug_TryPlace(player, tipo, pos, yaw)-> ok, motivo (só com GameConfig.Debug = true)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local BuildingConfig = require(Modules:WaitForChild("BuildingConfig"))
local BuildingRules = require(Modules:WaitForChild("BuildingRules"))
local BuildingModels = require(Modules:WaitForChild("BuildingModels"))

local Services = script.Parent
local MapService = require(Services:WaitForChild("MapService"))
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local IslandService = require(Services:WaitForChild("IslandService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))

local BuildingService = {}

-- ===========================================================================
-- ESTADO (só o servidor altera)
-- ===========================================================================

local islands = {}        -- [indice] = { Index, Folder, OwnerUserId, Models, Records, Count, ByType }
local lastRequest = {}    -- [Player] = os.clock() do último pedido
local remote = nil
local buildingsFolder = nil

local function log(...)
	if GameConfig.Debug then
		print("[BuildingService]", ...)
	end
end

local function send(player, action, payload)
	if remote and player.Parent then
		remote:FireClient(player, action, payload)
	end
end

local function deny(player, reason)
	send(player, "Denied", reason)
	log(string.format("Construção negada para %s: %s", player.Name, reason))
	return false, reason
end

local function getState(index)
	local state = islands[index]
	if state then
		return state
	end
	local folder = Instance.new("Folder")
	folder.Name = string.format("Buildings_%02d", index)
	folder.Parent = buildingsFolder
	state = {
		Index = index,
		Folder = folder,
		OwnerUserId = 0,
		Models = {},
		Records = {},
		Count = 0,
		ByType = {},
	}
	islands[index] = state
	return state
end

local function clearIsland(state)
	state.Folder:ClearAllChildren()
	state.Models = {}
	state.Records = {}
	state.Count = 0
	state.ByType = {}
	state.OwnerUserId = 0
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e6
end

-- ===========================================================================
-- BAÚ (interação por ProximityPrompt: funciona igual no PC e no celular)
-- ===========================================================================

local function chestTotal(record)
	local total = 0
	for _, amount in pairs(record.Items or {}) do
		if type(amount) == "number" then
			total += amount
		end
	end
	return total
end

local function refreshChestPrompts(model, record)
	local total = chestTotal(record)
	model:SetAttribute("Stored", total)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.ObjectText = string.format("Baú (%d/%d)", total, BuildingConfig.Chest.Capacity)
		end
	end
end

local function chestAllowed(player, state)
	if state.OwnerUserId ~= player.UserId then
		return false, "Este baú pertence a outro jogador."
	end
	if not PlayerDataService.GetData(player) or PlayerDataService.IsReadOnly(player) then
		return false, "Seus dados não estão disponíveis."
	end
	return true
end

local function chestDeposit(player, state, record, model)
	local ok, reason = chestAllowed(player, state)
	if not ok then
		return send(player, "Denied", reason)
	end
	record.Items = record.Items or {}

	local room = BuildingConfig.Chest.Capacity - chestTotal(record)
	local moved = 0
	for itemName in pairs(ResourceConfig.Items) do
		if room <= 0 then
			break
		end
		local have = InventoryService.GetCount(player, itemName)
		local amount = math.min(have, room)
		if amount >= 1 and InventoryService.RemoveItem(player, itemName, amount, "ChestDeposit") then
			record.Items[itemName] = (record.Items[itemName] or 0) + amount
			room -= amount
			moved += amount
		end
	end

	refreshChestPrompts(model, record)
	if moved > 0 then
		send(player, "Info", string.format("Você guardou %d itens no baú.", moved))
	elseif room <= 0 then
		send(player, "Denied", "O baú está cheio.")
	else
		send(player, "Denied", "Você não tem nada para guardar.")
	end
end

local function chestWithdraw(player, state, record, model)
	local ok, reason = chestAllowed(player, state)
	if not ok then
		return send(player, "Denied", reason)
	end
	record.Items = record.Items or {}

	local moved = 0
	for itemName, amount in pairs(record.Items) do
		if type(amount) == "number" and amount >= 1 and ResourceConfig.Items[itemName] then
			local fits = math.min(amount, InventoryService.GetRoom(player, itemName))
			if fits >= 1 then
				local added = InventoryService.AddItem(player, itemName, fits, "ChestWithdraw")
				if added > 0 then
					record.Items[itemName] = amount - added
					if record.Items[itemName] <= 0 then
						record.Items[itemName] = nil
					end
					moved += added
				end
			end
		end
	end

	refreshChestPrompts(model, record)
	if moved > 0 then
		send(player, "Info", string.format("Você pegou %d itens do baú.", moved))
	elseif chestTotal(record) <= 0 then
		send(player, "Denied", "O baú está vazio.")
	else
		send(player, "Denied", "Sua mochila está cheia.")
	end
end

local function setupChest(state, record, model)
	local root = model.PrimaryPart
	local point = Instance.new("Attachment")
	point.Name = "PromptPoint"
	point.Position = Vector3.new(0, 2.4, 0)
	point.Parent = root

	local function makePrompt(actionText, key, offsetY, callback)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = actionText
		prompt.ObjectText = "Baú"
		prompt.KeyboardKeyCode = key
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		prompt.UIOffset = Vector2.new(0, offsetY)
		prompt.Parent = point
		prompt.Triggered:Connect(function(player)
			local ok, err = pcall(callback, player, state, record, model)
			if not ok then
				warn("[BuildingService] Erro no baú: " .. tostring(err))
			end
		end)
	end

	makePrompt("Guardar tudo", Enum.KeyCode.E, 0, chestDeposit)
	makePrompt("Pegar tudo", Enum.KeyCode.F, -60, chestWithdraw)
	refreshChestPrompts(model, record)
end

-- ===========================================================================
-- CRIAR / REMOVER PEÇAS NO MUNDO
-- ===========================================================================

local function spawnBuilding(state, info, record)
	local def = BuildingConfig.Buildings[record.Type]
	local cf = BuildingRules.CFrameFor(info.Center, info.GroundY, record.X, record.Z, record.Yaw)

	local model = BuildingModels.Build(record.Type, false)
	model.Name = record.Type .. "_" .. string.sub(record.Id, 1, 6)
	model:PivotTo(cf)
	model:SetAttribute("BuildingId", record.Id)
	model:SetAttribute("BuildingLayer", def.Layer)
	model:SetAttribute("OwnerUserId", state.OwnerUserId)
	model:SetAttribute("IslandIndex", state.Index)
	if def.ProtectionRadius then
		model:SetAttribute("ProtectionRadius", def.ProtectionRadius)
	end
	model.Parent = state.Folder
	CollectionService:AddTag(model, "Building")

	if def.Storage then
		setupChest(state, record, model)
	end

	state.Models[record.Id] = model
	state.Records[record.Id] = record
	state.Count += 1
	state.ByType[record.Type] = (state.ByType[record.Type] or 0) + 1
	return model
end

local function despawnBuilding(state, id)
	local model = state.Models[id]
	local record = state.Records[id]
	if model then
		model:Destroy()
	end
	state.Models[id] = nil
	state.Records[id] = nil
	if record then
		state.Count = math.max(0, state.Count - 1)
		state.ByType[record.Type] = math.max(0, (state.ByType[record.Type] or 1) - 1)
	end
end

local function recordIsValid(record, info)
	if type(record) ~= "table" or not BuildingConfig.Buildings[record.Type] then
		return false
	end
	if not finite(record.X) or not finite(record.Z) or not finite(record.Yaw) then
		return false
	end
	local limit = info.BuildRadius + 0.5
	return record.X * record.X + record.Z * record.Z <= limit * limit
end

-- Reconstrói a base do jogador na ilha dele
local function loadIsland(player, info, data)
	local state = getState(info.Index)

	-- reconexão dentro do tempo de reserva: a base ainda está lá
	if state.OwnerUserId == player.UserId and state.Count > 0 then
		return
	end

	clearIsland(state)
	state.OwnerUserId = player.UserId

	if type(data.Buildings) ~= "table" then
		data.Buildings = {}
	end

	local loaded, skipped = 0, 0
	for _, record in ipairs(data.Buildings) do
		if recordIsValid(record, info) and state.Count < BuildingConfig.MaxBuildingsPerIsland then
			record.Id = type(record.Id) == "string" and record.Id or HttpService:GenerateGUID(false)
			local ok, err = pcall(spawnBuilding, state, info, record)
			if ok then
				loaded += 1
			else
				skipped += 1
				warn("[BuildingService] Falha ao criar peça salva: " .. tostring(err))
			end
		else
			skipped += 1 -- o registro NÃO é apagado do perfil, só deixa de aparecer
		end
	end
	log(string.format("Ilha %02d: %d peça(s) carregada(s), %d ignorada(s).", info.Index, loaded, skipped))
end

-- ===========================================================================
-- VALIDAÇÃO
-- ===========================================================================

local function groundIsSolid(info, cf, size)
	local base = info.Model and info.Model:FindFirstChild("Base")
	if not base then
		return true
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { base }

	local hx, hz = math.max(size.X / 2 - 0.1, 0), math.max(size.Z / 2 - 0.1, 0)
	for _, offset in ipairs({
		Vector3.new(0, 0, 0),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(-hx, 0, -hz),
		}) do
		local origin = (cf * CFrame.new(offset)).Position + Vector3.new(0, 8, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -24, 0), params)
		if not hit or math.abs(hit.Position.Y - info.GroundY) > BuildingConfig.GroundTolerance then
			return false
		end
	end
	return true
end

local function playerInside(cf, size)
	for _, other in ipairs(Players:GetPlayers()) do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local rel = cf:PointToObjectSpace(root.Position)
			if math.abs(rel.X) <= size.X / 2 + 1 and math.abs(rel.Z) <= size.Z / 2 + 1 and rel.Y >= -1 and rel.Y <= size.Y then
				return true
			end
		end
	end
	return false
end

-- Retorna true, dados  |  false, motivo
local function validate(player, typeName, rawPosition, rawYaw)
	if type(typeName) ~= "string" then
		return false, "Peça inválida."
	end
	local def = BuildingConfig.Buildings[typeName]
	if not def or not BuildingModels.Has(typeName) then
		return false, "Peça inválida."
	end
	if typeof(rawPosition) ~= "Vector3" or not finite(rawPosition.X) or not finite(rawPosition.Y) or not finite(rawPosition.Z) then
		return false, "Posição inválida."
	end

	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Seus dados ainda estão carregando."
	end
	if PlayerDataService.IsReadOnly(player) then
		return false, "Seus dados estão em modo somente leitura."
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return false, "Você não pode construir agora."
	end

	local info = IslandService.GetIslandOf(player)
	if not info then
		return false, "Você ainda não tem uma ilha."
	end
	local state = islands[info.Index]
	if not state or state.OwnerUserId ~= player.UserId then
		return false, "Sua ilha ainda está carregando."
	end

	-- posição e rotação recalculadas pelo SERVIDOR
	local rx, rz = BuildingRules.SnapRelative(info.Center, rawPosition)
	local yaw = BuildingRules.SnapYaw(rawYaw)
	local cf = BuildingRules.CFrameFor(info.Center, info.GroundY, rx, rz, yaw)

	if (root.Position - cf.Position).Magnitude > BuildingConfig.PlaceDistance then
		return false, "Muito longe para construir."
	end

	-- PROPRIEDADE: dentro da própria ilha (centro + 4 cantos)
	local inside, reason = IslandService.CanBuildBox(player, cf, def.Size)
	if not inside then
		return false, reason or "Fora da sua ilha."
	end

	-- limites
	if state.Count >= BuildingConfig.MaxBuildingsPerIsland then
		return false, "Limite de construções da ilha atingido."
	end
	if def.Max and (state.ByType[typeName] or 0) >= def.Max then
		return false, string.format("Limite de %s atingido (%d).", def.DisplayName, def.Max)
	end

	-- longe do ponto de nascimento
	local dx, dz = cf.Position.X - info.Center.X, cf.Position.Z - info.Center.Z
	local spawnLimit = BuildingConfig.SpawnClearance + math.max(def.Size.X, def.Size.Z) / 2
	if def.Layer ~= "Floor" and dx * dx + dz * dz < spawnLimit * spawnLimit then
		return false, "Deixe livre a área de nascimento da ilha."
	end

	-- TERRENO
	if not groundIsSolid(info, cf, def.Size) then
		return false, "Terreno inválido: construa sobre a grama da sua ilha."
	end

	-- peça igual no mesmo lugar
	for _, record in pairs(state.Records) do
		if record.Type == typeName and record.X == rx and record.Z == rz and record.Yaw == yaw then
			return false, "Já existe uma peça igual neste local."
		end
	end

	-- espaço livre
	local conflict = BuildingRules.FindConflict(def, cf, BuildingRules.GetScope(info.Model))
	if conflict then
		return false, conflict
	end

	if def.Layer ~= "Floor" and playerInside(cf, def.Size) then
		return false, "Há um jogador no local."
	end

	-- materiais
	if not InventoryService.HasItems(player, def.Cost) then
		return false, "Materiais insuficientes."
	end

	return true, { Def = def, Info = info, State = state, X = rx, Z = rz, Yaw = yaw, Data = data }
end

-- ===========================================================================
-- AÇÕES
-- ===========================================================================

local function place(player, typeName, rawPosition, rawYaw)
	local ok, result = validate(player, typeName, rawPosition, rawYaw)
	if not ok then
		return deny(player, result)
	end

	local def, info, state, data = result.Def, result.Info, result.State, result.Data

	if not InventoryService.RemoveItems(player, def.Cost, "Build:" .. typeName) then
		return deny(player, "Materiais insuficientes.")
	end

	local record = {
		Id = HttpService:GenerateGUID(false),
		Type = typeName,
		X = result.X,
		Z = result.Z,
		Yaw = result.Yaw,
	}
	if def.Storage then
		record.Items = {}
	end

	if type(data.Buildings) ~= "table" then
		data.Buildings = {}
	end

	local created, err = pcall(spawnBuilding, state, info, record)
	if not created then
		warn("[BuildingService] Erro ao criar peça: " .. tostring(err))
		for item, amount in pairs(def.Cost) do
			InventoryService.AddItem(player, item, amount, "BuildRefund")
		end
		return deny(player, "Erro interno ao construir.")
	end

	table.insert(data.Buildings, record)
	send(player, "Placed", typeName)
	log(string.format("%s construiu %s na ilha %02d", player.Name, typeName, info.Index))
	return true
end

local function remove(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(buildingsFolder) then
		return deny(player, "Peça inválida.")
	end

	local id = model:GetAttribute("BuildingId")
	local index = model:GetAttribute("IslandIndex")
	local state = type(index) == "number" and islands[index] or nil
	local record = state and type(id) == "string" and state.Records[id] or nil
	if not record or state.Models[id] ~= model then
		return deny(player, "Peça inválida.")
	end

	if not IslandService.IsOwner(player, state.Index) or state.OwnerUserId ~= player.UserId then
		return deny(player, "Esta construção pertence a outro jogador.")
	end

	local data = PlayerDataService.GetData(player)
	if not data or PlayerDataService.IsReadOnly(player) then
		return deny(player, "Seus dados não estão disponíveis.")
	end

	if chestTotal(record) > 0 then
		return deny(player, "Esvazie o baú antes de demolir.")
	end

	local def = BuildingConfig.Buildings[record.Type]
	local refund = {}
	for item, amount in pairs(def.Cost) do
		local back = math.floor(amount * BuildingConfig.RefundRatio)
		if back >= 1 then
			refund[item] = InventoryService.AddItem(player, item, back, "BuildRefund")
		end
	end

	-- tira do perfil e do mundo
	for index, saved in ipairs(data.Buildings) do
		if saved == record then
			table.remove(data.Buildings, index)
			break
		end
	end
	despawnBuilding(state, id)

	send(player, "Removed", record.Type)
	log(string.format("%s demoliu %s", player.Name, record.Type))
	return true
end

-- ===========================================================================
-- API
-- ===========================================================================

function BuildingService.GetBuildings(islandIndex)
	local list = {}
	local state = islands[islandIndex]
	if state then
		for id, record in pairs(state.Records) do
			table.insert(list, { Id = id, Type = record.Type, Model = state.Models[id] })
		end
	end
	return list
end

-- Há alguma Torre de Proteção cobrindo esta posição? (para o EventService usar nos desastres)
function BuildingService.IsProtected(position)
	for _, state in pairs(islands) do
		for id, record in pairs(state.Records) do
			local def = BuildingConfig.Buildings[record.Type]
			local model = state.Models[id]
			if def and def.ProtectionRadius and model then
				if (model:GetPivot().Position - position).Magnitude <= def.ProtectionRadius then
					return true
				end
			end
		end
	end
	return false
end

function BuildingService.Debug_TryPlace(player, typeName, position, yaw)
	if not GameConfig.Debug then
		return false, "Debug desligado"
	end
	return place(player, typeName, position, yaw or 0)
end

-- ===========================================================================
-- CICLO DE VIDA
-- ===========================================================================

function BuildingService.Init()
end

function BuildingService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuildRequest")

	buildingsFolder = Workspace:FindFirstChild(BuildingConfig.FolderName)
	if not buildingsFolder then
		buildingsFolder = Instance.new("Folder")
		buildingsFolder.Name = BuildingConfig.FolderName
		buildingsFolder.Parent = Workspace
	end

	if not MapService.IsReady() then
		warn("[BuildingService] MapService não está pronto. BuildingService DESATIVADO.")
		return
	end

	-- o cliente precisa saber o centro da ilha para a pré-visualização
	for _, slot in ipairs(MapService.GetIslandSlots()) do
		slot.Model:SetAttribute("CenterX", slot.Center.X)
		slot.Model:SetAttribute("CenterZ", slot.Center.Z)
		getState(slot.Index)
	end

	IslandService.OnAssigned(function(player, info)
		local data = PlayerDataService.GetData(player)
		if not data then
			return
		end
		local ok, err = pcall(loadIsland, player, info, data)
		if not ok then
			warn("[BuildingService] Erro ao carregar a ilha: " .. tostring(err))
		end
	end)

	-- jogadores que já receberam ilha antes deste Start
	for _, player in ipairs(Players:GetPlayers()) do
		local info = IslandService.GetIslandOf(player)
		local data = PlayerDataService.GetData(player)
		if info and data then
			pcall(loadIsland, player, info, data)
		end
	end

	-- ilha liberada (reserva expirou): a base some do mundo; continua salva no perfil do dono
	IslandService.OnReleased(function(info)
		local state = islands[info.Index]
		if state then
			clearIsland(state)
		end
	end)

	remote.OnServerEvent:Connect(function(player, action, a, b, c)
		local cooldown = GameConfig.Security.RemoteCooldowns.BuildRequest or 0.5
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < cooldown then
			return
		end
		lastRequest[player] = now

		local ok, err = pcall(function()
			if action == "Place" then
				place(player, a, b, c)
			elseif action == "Remove" then
				remove(player, a)
			end
		end)
		if not ok then
			warn("[BuildingService] Erro no pedido: " .. tostring(err))
			send(player, "Denied", "Erro interno.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	log("Pronto.")
end

return BuildingService

