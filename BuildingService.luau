--[[
	BuildingService (v3)  -  ServerScriptService > Services > BuildingService  (SUBSTITUI)

	Constrói em QUALQUER lugar do mapa, exceto: nadando, no ar, na água (barco é o contrário: só na água),
	em terreno inclinado/irregular, sobre outros objetos ou com jogador dentro. O servidor decide tudo.
	Remote BuildRequest:  cliente -> "Place", tipo, Vector3, giro | "Remove", modelo
	                      servidor -> "Placed", tipo | "Removed", tipo | "Denied", texto | "Info", texto
	Salva em data.Buildings = { Id, Type, X, Y, Z, Yaw, Items? }. As peças do jogador aparecem quando ele entra
	e somem quando sai. Barco: VehicleSeat + flutuação simulada (controles padrão do Roblox, PC e celular).
	API: BuildingService.IsProtected(posição) | BuildingService.GetBuildings(player)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local Config = require(Modules:WaitForChild("BuildingConfig"))
local Rules = require(Modules:WaitForChild("BuildingRules"))
local Models = require(Modules:WaitForChild("BuildingModels"))

local Services = script.Parent
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))

local BuildingService = {}

local owned = {}   -- [Player] = { Records, Models, Count, ByType }
local boats = {}   -- [Model] = { Hull, Seat, Velocity, Aim, Yaw, TargetY, Record }
local lastRequest = {}
local remote, folder

local function log(...)
	if GameConfig.Debug then print("[BuildingService]", ...) end
end

local function send(player, action, payload)
	if remote and player.Parent then remote:FireClient(player, action, payload) end
end

local function deny(player, reason)
	send(player, "Denied", reason)
	return false, reason
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < 1e6
end

local function characters()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

-- ===========================================================================
-- BAÚ (ProximityPrompt: funciona no PC e no celular)
-- ===========================================================================
local function chestTotal(rec)
	local t = 0
	for _, n in pairs(rec.Items or {}) do
		if type(n) == "number" then t += n end
	end
	return t
end

local function refreshChest(model, rec)
	local total = chestTotal(rec)
	model:SetAttribute("Stored", total)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.ObjectText = string.format("Baú (%d/%d)", total, Config.Chest.Capacity)
		end
	end
end

local function chestOwner(player, model)
	if model:GetAttribute("OwnerUserId") ~= player.UserId then
		send(player, "Denied", "Este baú é de outro jogador.")
		return false
	end
	return PlayerDataService.GetData(player) ~= nil and not PlayerDataService.IsReadOnly(player)
end

local function chestDeposit(player, rec, model)
	if not chestOwner(player, model) then return end
	rec.Items = rec.Items or {}
	local room, moved = Config.Chest.Capacity - chestTotal(rec), 0
	for item in pairs(ResourceConfig.Items) do
		local n = math.min(InventoryService.GetCount(player, item), room)
		if n >= 1 and InventoryService.RemoveItem(player, item, n, "ChestDeposit") then
			rec.Items[item] = (rec.Items[item] or 0) + n
			room -= n
			moved += n
		end
	end
	refreshChest(model, rec)
	send(player, moved > 0 and "Info" or "Denied", moved > 0 and ("Guardado: " .. moved) or (room <= 0 and "Baú cheio." or "Nada para guardar."))
end

local function chestWithdraw(player, rec, model)
	if not chestOwner(player, model) then return end
	rec.Items = rec.Items or {}
	local moved = 0
	for item, n in pairs(rec.Items) do
		if type(n) == "number" and n >= 1 and ResourceConfig.Items[item] then
			local added = InventoryService.AddItem(player, item, math.min(n, InventoryService.GetRoom(player, item)), "ChestWithdraw")
			if added > 0 then
				rec.Items[item] = (n - added > 0) and (n - added) or nil
				moved += added
			end
		end
	end
	refreshChest(model, rec)
	send(player, moved > 0 and "Info" or "Denied", moved > 0 and ("Pegou: " .. moved) or (chestTotal(rec) <= 0 and "Baú vazio." or "Mochila cheia."))
end

local function setupChest(rec, model)
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 2.4, 0)
	att.Parent = model.PrimaryPart
	local function prompt(text, key, offset, fn)
		local p = Instance.new("ProximityPrompt")
		p.ActionText, p.ObjectText, p.KeyboardKeyCode = text, "Baú", key
		p.HoldDuration, p.MaxActivationDistance, p.RequiresLineOfSight = 0, 10, false
		p.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		p.UIOffset = Vector2.new(0, offset)
		p.Parent = att
		p.Triggered:Connect(function(player)
			local ok, err = pcall(fn, player, rec, model)
			if not ok then warn("[BuildingService] baú: " .. tostring(err)) end
		end)
	end
	prompt("Guardar tudo", Enum.KeyCode.E, 0, chestDeposit)
	prompt("Pegar tudo", Enum.KeyCode.F, -60, chestWithdraw)
	refreshChest(model, rec)
end

-- ===========================================================================
-- BARCO
-- ===========================================================================
local function setupBoat(model, rec)
	local hull = model:FindFirstChild("Hull")
	local seat = model:FindFirstChild("Seat")
	if not hull or not seat then return end

	local att = Instance.new("Attachment")
	att.Parent = hull
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Parent = hull
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e8
	ao.Responsiveness = 25
	ao.Parent = hull

	local _, yaw = hull.CFrame:ToEulerAnglesYXZ()
	local offset = hull.Position.Y - model:GetPivot().Position.Y
	boats[model] = { Hull = hull, Seat = seat, Velocity = lv, Aim = ao, Yaw = yaw, TargetY = rec.Y + offset - 0.45, Record = rec }
	pcall(function() hull:SetNetworkOwner(nil) end)
end

local function stepBoats(dt)
	local speed, turn = Config.Boat.Speed, Config.Boat.TurnRate
	for model, b in pairs(boats) do
		if not model.Parent then
			boats[model] = nil
		else
			local throttle = b.Seat.Occupant and b.Seat.Throttle or 0
			local steer = b.Seat.Occupant and b.Seat.Steer or 0
			b.Yaw -= steer * turn * dt * (throttle >= 0 and 1 or -1)
			local look = CFrame.Angles(0, b.Yaw, 0).LookVector
			b.Aim.CFrame = CFrame.Angles(0, b.Yaw, 0)
			b.Velocity.VectorVelocity = Vector3.new(look.X * throttle * speed, (b.TargetY - b.Hull.Position.Y) * 8, look.Z * throttle * speed)
		end
	end
end

local function saveBoats()
	for model, b in pairs(boats) do
		if model.Parent then
			local p = b.Hull.Position
			b.Record.X, b.Record.Z, b.Record.Yaw = p.X, p.Z, math.deg(b.Yaw) % 360
		end
	end
end

-- ===========================================================================
-- PEÇAS
-- ===========================================================================
local function spawnBuilding(player, state, rec)
	local def = Config.Buildings[rec.Type]
	local model = Models.Build(rec.Type, false)
	model.Name = rec.Type .. "_" .. string.sub(rec.Id, 1, 6)
	model:PivotTo(Rules.CFrameFor(rec.X, rec.Y, rec.Z, rec.Yaw))
	model:SetAttribute("BuildingId", rec.Id)
	model:SetAttribute("BuildingLayer", def.Layer)
	model:SetAttribute("OwnerUserId", player.UserId)
	if def.ProtectionRadius then model:SetAttribute("ProtectionRadius", def.ProtectionRadius) end
	model.Parent = folder
	CollectionService:AddTag(model, "Building")
	if def.Storage then setupChest(rec, model) end
	if def.Dynamic then setupBoat(model, rec) end
	state.Records[rec.Id], state.Models[rec.Id] = rec, model
	state.Count += 1
	state.ByType[rec.Type] = (state.ByType[rec.Type] or 0) + 1
end

local function despawn(state, id)
	local model, rec = state.Models[id], state.Records[id]
	if model then
		boats[model] = nil
		model:Destroy()
	end
	state.Models[id], state.Records[id] = nil, nil
	if rec then
		state.Count = math.max(0, state.Count - 1)
		state.ByType[rec.Type] = math.max(0, (state.ByType[rec.Type] or 1) - 1)
	end
end

local function loadPlayer(player, data)
	local state = { Records = {}, Models = {}, Count = 0, ByType = {} }
	owned[player] = state
	if type(data.Buildings) ~= "table" then data.Buildings = {} end
	for _, rec in ipairs(data.Buildings) do
		if type(rec) == "table" and Config.Buildings[rec.Type] and finite(rec.X) and finite(rec.Y) and finite(rec.Z) and finite(rec.Yaw) then
			rec.Id = type(rec.Id) == "string" and rec.Id or HttpService:GenerateGUID(false)
			local ok, err = pcall(spawnBuilding, player, state, rec)
			if not ok then warn("[BuildingService] peça salva falhou: " .. tostring(err)) end
		end
	end
end

-- ===========================================================================
-- VALIDAÇÃO
-- ===========================================================================
local function validate(player, typeName, rawPos, rawYaw)
	local def = type(typeName) == "string" and Config.Buildings[typeName]
	if not def then return false, "Peça inválida." end
	if typeof(rawPos) ~= "Vector3" or not finite(rawPos.X) or not finite(rawPos.Z) then return false, "Posição inválida." end

	local data, state = PlayerDataService.GetData(player), owned[player]
	if not data or not state then return false, "Seus dados estão carregando." end
	if PlayerDataService.IsReadOnly(player) then return false, "Dados em modo somente leitura." end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then return false, "Você não pode construir agora." end
	if hum:GetState() == Enum.HumanoidStateType.Swimming then return false, "Não dá para construir nadando." end
	if hum.FloorMaterial == Enum.Material.Air and not hum.SeatPart then return false, "Não dá para construir no ar." end

	local x, z, yaw = Rules.Snap(rawPos.X), Rules.Snap(rawPos.Z), Rules.SnapYaw(rawYaw)
	if (Vector3.new(x, 0, z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude > Config.PlaceDistance then
		return false, "Muito longe."
	end

	if state.Count >= Config.MaxPerPlayer then return false, "Limite de construções atingido." end
	if def.Max and (state.ByType[typeName] or 0) >= def.Max then
		return false, string.format("Limite de %s atingido (%d).", def.DisplayName, def.Max)
	end

	-- chão: raio para baixo a partir de pouco acima do jogador (detecta água)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = characters()
	local originY = root.Position.Y + 6
	local function ground(px, pz)
		return Workspace:Raycast(Vector3.new(px, originY, pz), Vector3.new(0, -150, 0), params)
	end

	local center = ground(x, z)
	if not center then return false, "Sem chão aqui." end
	local isWater = center.Material == Enum.Material.Water
	if def.Water then
		if not isWater then return false, "O barco precisa ser colocado na água." end
	else
		if isWater then return false, "Não dá para construir na água." end
		if center.Normal.Y < Config.MaxSlopeNormalY then return false, "Terreno muito inclinado." end
	end

	local y = center.Position.Y
	local flat = Rules.CFrameFor(x, y, z, yaw)
	for _, point in ipairs(Rules.FootprintPoints(flat, def.Size)) do
		local hit = ground(point.X, point.Z)
		local water = hit and hit.Material == Enum.Material.Water
		if not hit or (water ~= (def.Water == true)) or math.abs(hit.Position.Y - y) > Config.GroundTolerance then
			return false, def.Water and "Precisa de água em volta." or "Terreno irregular."
		end
	end

	for _, rec in pairs(state.Records) do
		if rec.Type == typeName and rec.X == x and rec.Z == z and rec.Yaw == yaw and math.abs(rec.Y - y) < 0.1 then
			return false, "Já existe uma peça igual aqui."
		end
	end

	local conflict = Rules.FindConflict(def, flat, characters())
	if conflict then return false, conflict end

	if def.Layer ~= "Floor" then
		for _, other in ipairs(Players:GetPlayers()) do
			local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local rel = flat:PointToObjectSpace(r.Position)
				if math.abs(rel.X) <= def.Size.X / 2 + 1 and math.abs(rel.Z) <= def.Size.Z / 2 + 1 and rel.Y >= -1 and rel.Y <= def.Size.Y then
					return false, "Há um jogador no local."
				end
			end
		end
	end

	if not InventoryService.HasItems(player, def.Cost) then return false, "Materiais insuficientes." end
	return true, { Def = def, State = state, Data = data, X = x, Y = y, Z = z, Yaw = yaw }
end

local function place(player, typeName, rawPos, rawYaw)
	local ok, r = validate(player, typeName, rawPos, rawYaw)
	if not ok then return deny(player, r) end
	if not InventoryService.RemoveItems(player, r.Def.Cost, "Build:" .. typeName) then return deny(player, "Materiais insuficientes.") end

	local rec = { Id = HttpService:GenerateGUID(false), Type = typeName, X = r.X, Y = r.Y, Z = r.Z, Yaw = r.Yaw }
	if r.Def.Storage then rec.Items = {} end
	local created, err = pcall(spawnBuilding, player, r.State, rec)
	if not created then
		warn("[BuildingService] erro ao criar: " .. tostring(err))
		for item, n in pairs(r.Def.Cost) do InventoryService.AddItem(player, item, n, "BuildRefund") end
		return deny(player, "Erro interno ao construir.")
	end
	table.insert(r.Data.Buildings, rec)
	send(player, "Placed", typeName)
	return true
end

local function remove(player, model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(folder) then return deny(player, "Peça inválida.") end
	local state, id = owned[player], model:GetAttribute("BuildingId")
	local rec = state and type(id) == "string" and state.Records[id]
	if not rec or state.Models[id] ~= model or model:GetAttribute("OwnerUserId") ~= player.UserId then
		return deny(player, "Esta construção não é sua.")
	end
	local data = PlayerDataService.GetData(player)
	if not data or PlayerDataService.IsReadOnly(player) then return deny(player, "Dados indisponíveis.") end
	if chestTotal(rec) > 0 then return deny(player, "Esvazie o baú antes.") end
	local boat = boats[model]
	if boat and boat.Seat.Occupant then return deny(player, "Há alguém no barco.") end

	for item, n in pairs(Config.Buildings[rec.Type].Cost) do
		local back = math.floor(n * Config.RefundRatio)
		if back >= 1 then InventoryService.AddItem(player, item, back, "BuildRefund") end
	end
	for i, saved in ipairs(data.Buildings) do
		if saved == rec then table.remove(data.Buildings, i) break end
	end
	local typeName = rec.Type
	despawn(state, id)
	send(player, "Removed", typeName)
	return true
end

-- ===========================================================================
-- API / CICLO DE VIDA
-- ===========================================================================
function BuildingService.GetBuildings(player)
	local list, state = {}, owned[player]
	if state then
		for id, rec in pairs(state.Records) do table.insert(list, { Id = id, Type = rec.Type, Model = state.Models[id] }) end
	end
	return list
end

function BuildingService.IsProtected(position)
	for _, state in pairs(owned) do
		for id, rec in pairs(state.Records) do
			local def, model = Config.Buildings[rec.Type], state.Models[id]
			if def and def.ProtectionRadius and model and (model:GetPivot().Position - position).Magnitude <= def.ProtectionRadius then
				return true
			end
		end
	end
	return false
end

function BuildingService.Init() end

function BuildingService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuildRequest")
	folder = Workspace:FindFirstChild(Config.FolderName) or Instance.new("Folder")
	folder.Name = Config.FolderName
	folder.Parent = Workspace

	PlayerDataService.OnLoaded(function(player, data)
		local ok, err = pcall(loadPlayer, player, data)
		if not ok then warn("[BuildingService] erro ao carregar: " .. tostring(err)) end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataService.GetData(player)
		if data and not owned[player] then pcall(loadPlayer, player, data) end
	end

	remote.OnServerEvent:Connect(function(player, action, a, b, c)
		local now, cd = os.clock(), GameConfig.Security.RemoteCooldowns.BuildRequest or 0.5
		if lastRequest[player] and now - lastRequest[player] < cd then return end
		lastRequest[player] = now
		local ok, err = pcall(function()
			if action == "Place" then place(player, a, b, c) elseif action == "Remove" then remove(player, a) end
		end)
		if not ok then
			warn("[BuildingService] " .. tostring(err))
			send(player, "Denied", "Erro interno.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
		saveBoats()
		local state = owned[player]
		if state then
			for id in pairs(table.clone(state.Models)) do despawn(state, id) end
			owned[player] = nil
		end
	end)

	task.spawn(function()
		local acc = 0
		while true do
			local dt = task.wait(0.05)
			stepBoats(dt)
			acc += dt
			if acc >= 3 then acc = 0 saveBoats() end
		end
	end)
	log("Pronto.")
end

return BuildingService

