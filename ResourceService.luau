
--[[
    ResourceService
    Local: ServerScriptService > Services > ResourceService

    Sistema de coleta de recursos com ferramentas por nível.
    Ferramentas criadas pelo ToolModelFactory.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local ToolModelFactory = require(Modules:WaitForChild("ToolModelFactory"))

local Services = script.Parent

local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local IslandService = require(Services:WaitForChild("IslandService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local ResourceModelBuilder = require(Services:WaitForChild("ResourceModelBuilder"))

local Cfg = ResourceConfig.Gathering

local ResourceService = {}

-- ESTADO

local nodes = {}
local nodeList = {}
local sessions = {}
local lastEnd = {}
local lastRemote = {}
local yieldModifiers = {}

local rng = Random.new()
local remote
local nodeCounter = 0

local cancelSession

-- UTILITÁRIOS

local function log(...)
	if GameConfig.Debug then
		print("[ResourceService]", ...)
	end
end

local function deny(player, reason)
	if remote and player.Parent then
		remote:FireClient(player, "Denied", reason)
	end

	log("Coleta negada:", player.Name, reason)

	return false, reason
end

local function getCharacterParts(player)
	local character = player.Character

	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end

	return character, humanoid, root
end

local function clampTier(value, toolDef)
	if type(value) ~= "number" then
		return 1
	end

	return math.clamp(math.floor(value), 1, #toolDef.Tiers)
end

-- FERRAMENTAS

local function createToolInstance(toolName, tier)
	local toolDef = ResourceConfig.Tools[toolName]

	if not toolDef then
		warn("[ResourceService] Ferramenta não encontrada:", toolName)
		return nil
	end

	tier = clampTier(tier, toolDef)

	local success, tool = pcall(function()
		return ToolModelFactory.CreateTool(toolName, tier)
	end)

	if not success then
		warn("[ResourceService] Erro ao criar ferramenta:", tool)
		return nil
	end

	if not tool or not tool:IsA("Tool") then
		warn("[ResourceService] ToolModelFactory não retornou uma Tool válida.")
		return nil
	end

	-- Identificação usada pelos outros sistemas do jogo.
	tool:SetAttribute("ToolType", toolName)
	tool:SetAttribute("ToolTier", tier)

	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true

	return tool
end

local function equipTool(player, humanoid, tool)
	if not tool then
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack")

	if not backpack then
		tool:Destroy()
		return false
	end

	tool.Parent = backpack
	humanoid:EquipTool(tool)

	return true
end

local function swing(session)
	local tool = session.Tool

	if tool and tool.Parent then
		local oldAnim = tool:FindFirstChild("toolanim")

		if oldAnim then
			oldAnim:Destroy()
		end

		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
	end
end

-- EFEITOS

local function createEmitter(attachment, def)
	local p = def.Particle or {}
	local speed = p.Speed or 8

	local emitter = Instance.new("ParticleEmitter")

	emitter.Name = "HitParticles"
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(speed, speed + 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -28, 0)
	emitter.Size = NumberSequence.new(p.Size or 0.5, 0.1)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.Color = ColorSequence.new(p.Color or Color3.new(1, 1, 1))
	emitter.Parent = attachment

	return emitter
end

local function shake(record)
	local degrees = record.Def.ShakeDegrees or 0

	if degrees <= 0 or not record.Model.Parent or record.State ~= "Ready" then
		return
	end

	local base = record.BasePivot

	record.Model:PivotTo(base * CFrame.Angles(0, 0, math.rad(degrees)))

	task.delay(0.07, function()
		if record.Model.Parent and record.State == "Ready" then
			record.Model:PivotTo(base)
		end
	end)
end

local function hitEffect(record)
	shake(record)

	local p = record.Def.Particle or {}

	if record.Emitter then
		record.Emitter:Emit(p.Count or 8)
	end
end

-- RESPAWN

local function respawnNode(record)
	if not record.Model.Parent then
		return
	end

	record.Model:PivotTo(record.BasePivot)

	if record.Depleted then
		record.Depleted.Parent = nil
	end

	record.Full.Parent = record.Model
	record.State = "Ready"
	record.RespawnToken = nil

	if record.User == nil then
		record.Prompt.Enabled = true
	end

	if record.Emitter then
		local p = record.Def.Particle or {}
		record.Emitter:Emit(p.Count or 8)
	end
end

local function depleteNode(record)
	record.State = "Depleted"
	record.Prompt.Enabled = false

	record.Model:PivotTo(record.BasePivot)
	record.Full.Parent = nil

	if record.Depleted then
		record.Depleted.Parent = record.Model
	end

	if record.Emitter then
		local p = record.Def.Particle or {}
		record.Emitter:Emit((p.Count or 8) * 3)
	end

	local jitter = Cfg.RespawnJitter or 0
	local delayTime = record.Def.RespawnTime * (1 + rng:NextNumber(-jitter, jitter))

	local token = {}
	record.RespawnToken = token

	task.delay(delayTime, function()
		if record.RespawnToken == token then
			respawnNode(record)
		end
	end)
end

-- SESSÕES

local function endSession(session)
	local player = session.Player

	sessions[player] = nil
	lastEnd[player] = os.clock()

	local record = session.Record

	if record.User == player then
		record.User = nil

		if record.State == "Ready" then
			record.Prompt.Enabled = true
		end
	end

	if session.Tool then
		session.Tool:Destroy()
		session.Tool = nil
	end
end

cancelSession = function(session, reason)
	if sessions[session.Player] ~= session then
		return
	end

	endSession(session)

	if session.Player.Parent and remote then
		remote:FireClient(session.Player, "Cancel", reason or "Coleta cancelada.")
	end
end

local function checkSession(session)
	local player = session.Player
	local record = session.Record

	if sessions[player] ~= session then
		return false, nil
	end

	if player.Parent == nil then
		return false, nil
	end

	local character, _, root = getCharacterParts(player)

	if not character then
		return false, "Você foi derrotado."
	end

	local maxDistance = (record.Def.MaxDistance or Cfg.DefaultMaxDistance) + (Cfg.DistanceTolerance or 0)

	if (root.Position - record.Root.Position).Magnitude > maxDistance then
		return false, "Você se afastou demais."
	end

	if record.State ~= "Ready" then
		return false, "O recurso não está mais disponível."
	end

	return true
end

-- RECOMPENSAS

local function rollRewards(player, def, toolYield)
	local multiplier = (ResourceConfig.GlobalYieldMultiplier or 1) * toolYield

	for _, modifier in ipairs(yieldModifiers) do
		local ok, value = pcall(modifier, player, def)

		if ok and type(value) == "number" and value > 0 then
			multiplier *= value
		end
	end

	local result = {}

	for _, reward in ipairs(def.Rewards) do
		local chance = reward.Chance or 1

		if chance >= 1 or rng:NextNumber() <= chance then
			local base = rng:NextInteger(reward.Min, reward.Max)
			local amount = math.floor(base * multiplier + 0.5)

			if amount >= 1 then
				table.insert(result, {
					Item = reward.Item,
					Amount = amount,
				})
			end
		end
	end

	return result
end

local function completeGather(session)
	local player = session.Player
	local record = session.Record
	local def = record.Def

	if not PlayerDataService.GetData(player) then
		cancelSession(session, "Seus dados não estão disponíveis.")
		return
	end

	local granted = {}

	for _, reward in ipairs(rollRewards(player, def, session.Yield)) do
		local added = InventoryService.AddItem(
			player,
			reward.Item,
			reward.Amount,
			"Gather:" .. record.Key
		)

		if added and added > 0 then
			local itemDef = ResourceConfig.Items[reward.Item]

			table.insert(granted, {
				Item = reward.Item,
				Amount = added,
				Name = itemDef and itemDef.DisplayName or reward.Item,
			})
		end
	end

	if #granted == 0 then
		cancelSession(session, "Mochila cheia.")
		return
	end

	depleteNode(record)
	endSession(session)

	if player.Parent then
		remote:FireClient(player, "Done", granted)
	end

	log(player.Name, "coletou", record.Model.Name)
end

local function runSession(session)
	local startedAt = os.clock()
	local duration = session.Duration

	while true do
		local ok, reason = checkSession(session)

		if not ok then
			if reason then
				cancelSession(session, reason)
			end

			return
		end

		local remaining = duration - (os.clock() - startedAt)

		if remaining <= 0.05 then
			break
		end

		swing(session)

		task.delay(Cfg.HitDelay or 0.3, function()
			if sessions[session.Player] == session then
				hitEffect(session.Record)
			end
		end)

		task.wait(math.min(Cfg.SwingInterval or 0.8, remaining))
	end

	local ok, reason = checkSession(session)

	if not ok then
		if reason then
			cancelSession(session, reason)
		end

		return
	end

	completeGather(session)
end

-- INICIAR COLETA

local function startGather(player, record)
	local def = record.Def

	if sessions[player] then
		return deny(player, "Você já está coletando.")
	end

	local now = os.clock()

	if lastEnd[player] and now - lastEnd[player] < Cfg.StartCooldown then
		return false, "cooldown"
	end

	if record.State ~= "Ready" or record.User ~= nil then
		return deny(player, "Este recurso não está disponível agora.")
	end

	local data = PlayerDataService.GetData(player)

	if not data then
		return deny(player, "Seus dados ainda estão carregando.")
	end

	local character, humanoid, root = getCharacterParts(player)

	if not character then
		return false, "sem personagem"
	end

	-- PROPRIEDADE DA ILHA

	if Cfg.OwnerOnly and record.IslandIndex > 0 then
		if not IslandService.IsOwner(player, record.IslandIndex) then
			return deny(player, "Este recurso pertence a outro jogador.")
		end
	end

	-- DISTÂNCIA

	local maxDistance = (def.MaxDistance or Cfg.DefaultMaxDistance) + (Cfg.DistanceTolerance or 2)

	if (root.Position - record.Root.Position).Magnitude > maxDistance then
		return deny(player, "Você está muito longe.")
	end

	-- FERRAMENTA E NÍVEL

	local toolData
	local speed = 1
	local toolYield = 1
	local tier = 1

	if def.Tool then
		local toolDef = ResourceConfig.Tools[def.Tool]

		if not toolDef or not toolDef.Tiers then
			return deny(player, "Configuração da ferramenta inválida.")
		end

		tier = clampTier(data.Tools and data.Tools[def.Tool], toolDef)

		if tier < (def.MinTier or 1) then
			return deny(
				player,
				string.format(
					"Requer %s nível %d.",
					toolDef.DisplayName or def.Tool,
					def.MinTier or 1
				)
			)
		end

		toolData = toolDef.Tiers[tier]
		speed = toolData.Speed or 1
		toolYield = toolData.Yield or 1
	end

	-- ESPAÇO NA MOCHILA

	local primary = def.Rewards and def.Rewards[1] and def.Rewards[1].Item

	if not primary then
		return deny(player, "Este recurso não possui recompensa configurada.")
	end

	if not InventoryService.CanAdd(player, primary, 1) then
		local itemDef = ResourceConfig.Items[primary]
		local itemName = itemDef and itemDef.DisplayName or primary

		return deny(player, "Mochila cheia: " .. itemName .. ".")
	end

	-- TEMPO DE COLETA

	local duration = math.max(
		Cfg.MinGatherTime or 0.6,
		def.GatherTime / speed
	)

	local session = {
		Player = player,
		Record = record,
		Duration = duration,
		Yield = toolYield,
		Tier = tier,
		Tool = nil,
	}

	sessions[player] = session
	record.User = player
	record.Prompt.Enabled = false

	-- OLHAR PARA O RECURSO

	root.CFrame = CFrame.lookAt(
		root.Position,
		Vector3.new(
			record.Root.Position.X,
			root.Position.Y,
			record.Root.Position.Z
		)
	)

	-- EQUIPAR FERRAMENTA CORRETA

	if def.Tool then
		local tool = createToolInstance(def.Tool, tier)

		if tool then
			if equipTool(player, humanoid, tool) then
				session.Tool = tool
			else
				tool:Destroy()
			end
		end
	end

	remote:FireClient(player, "Start", {
		Label = def.ActionLabel or "Coletando...",
		Duration = duration,
	})

	task.spawn(function()
		local ok, err = pcall(runSession, session)

		if not ok then
			warn("[ResourceService] Erro na coleta:", err)
			cancelSession(session, "Erro interno.")
		end
	end)

	return true
end

-- CRIAR RECURSOS

local function createNode(marker, templates)
	local key = marker:GetAttribute("ResourceType")
	local def = ResourceConfig.Nodes[key]

	if not def or def.Enabled == false then
		return false
	end

	local template = templates:FindFirstChild(def.Template)

	if not template then
		warn("[ResourceService] Template não encontrado:", def.Template)
		return false
	end

	nodeCounter += 1

	local model = template:Clone()
	model.Name = string.format("%s_%03d", def.Template, nodeCounter)

	local groundPosition = marker.Position - Vector3.new(0, 1, 0)

	model:PivotTo(
		CFrame.new(groundPosition)
			* CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
	)

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local full = model:FindFirstChild("Full")
	local depleted = model:FindFirstChild("Depleted")

	if not root or not full then
		warn("[ResourceService] Template precisa de Root e Full:", def.Template)
		model:Destroy()
		return false
	end

	if depleted then
		depleted.Parent = nil
	end

	local islandIndex = marker:GetAttribute("IslandIndex") or 0

	local promptPoint = Instance.new("Attachment")
	promptPoint.Name = "PromptPoint"
	promptPoint.Position = Vector3.new(0, def.PromptHeight or 2, 0)
	promptPoint.Parent = root

	local effectPoint = Instance.new("Attachment")
	effectPoint.Name = "EffectPoint"
	effectPoint.Position = Vector3.new(0, def.HitHeight or 2, 0)
	effectPoint.Parent = root

	local maxDistance = def.MaxDistance or Cfg.DefaultMaxDistance

	local minTierText = ""

	if def.Tool and (def.MinTier or 1) > 1 then
		minTierText = string.format(" (nível %d)", def.MinTier)
	end

	local prompt = Instance.new("ProximityPrompt")

	prompt.ActionText = def.ActionText or "Coletar"
	prompt.ObjectText = (def.DisplayName or key) .. minTierText
	prompt.KeyboardKeyCode = Cfg.PromptKey or Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = maxDistance
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("IslandIndex", islandIndex)
	prompt:SetAttribute("BaseDistance", maxDistance)
	prompt.Parent = promptPoint

	CollectionService:AddTag(prompt, "ResourcePrompt")

	local record = {
		Model = model,
		Key = key,
		Def = def,
		Root = root,
		Full = full,
		Depleted = depleted,
		Prompt = prompt,
		Emitter = createEmitter(effectPoint, def),
		BasePivot = model:GetPivot(),
		IslandIndex = islandIndex,
		State = "Ready",
		User = nil,
		RespawnToken = nil,
	}

	nodes[model] = record
	table.insert(nodeList, record)

	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(startGather, player, record)

		if not ok then
			warn("[ResourceService] Erro ao iniciar coleta:", err)

			local session = sessions[player]

			if session then
				cancelSession(session, "Erro interno.")
			end
		end
	end)

	model:SetAttribute("ResourceType", key)
	model:SetAttribute("IslandIndex", islandIndex)

	CollectionService:AddTag(model, "ResourceNode")

	model.Parent = marker.Parent

	return true
end

-- API

function ResourceService.GetNodes()
	local list = {}

	for _, record in ipairs(nodeList) do
		table.insert(list, {
			Model = record.Model,
			Key = record.Key,
			IslandIndex = record.IslandIndex,
			State = record.State,
		})
	end

	return list
end

function ResourceService.RegisterYieldModifier(callback)
	if typeof(callback) ~= "function" then
		warn("[ResourceService] Modifier precisa ser uma função.")
		return
	end

	table.insert(yieldModifiers, callback)
end

function ResourceService.Debug_TryGather(player, nodeModel)
	if not GameConfig.Debug then
		return false, "Debug desligado"
	end

	local record = nodes[nodeModel]

	if not record then
		return false, "Recurso inexistente"
	end

	return startGather(player, record)
end

function ResourceService.Init()
end

-- INICIALIZAÇÃO

function ResourceService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectResource")

	-- TEMPLATES

	local templates = ServerStorage:FindFirstChild("ResourceModels")

	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "ResourceModels"
		templates.Parent = ServerStorage
	end

	local created = ResourceModelBuilder.EnsureTemplates(templates)

	log(created, "modelo(s) de recurso criado(s).")

	-- MARCADORES DO MAPA

	local mapFolder = Workspace:FindFirstChild(MapConfig.Folders.Map)

	local spawnsRoot = mapFolder
		and mapFolder:FindFirstChild(MapConfig.Folders.ResourceSpawns)

	if not spawnsRoot then
		warn("[ResourceService] Pasta ResourceSpawns não encontrada. Verifique o MapService.")
		return
	end

	local total = 0

	for _, islandFolder in ipairs(spawnsRoot:GetChildren()) do
		for _, marker in ipairs(islandFolder:GetChildren()) do
			if marker:IsA("BasePart") and marker:GetAttribute("ResourceType") then
				if createNode(marker, templates) then
					total += 1
				end
			end
		end
	end

	log(total, "recursos criados no mapa.")

	-- CANCELAMENTO PELO CLIENTE

	remote.OnServerEvent:Connect(function(player, action)
		if action ~= "Cancel" then
			return
		end

		local cooldown = GameConfig.Security.RemoteCooldowns.CollectResource or 0.25
		local now = os.clock()

		if lastRemote[player] and now - lastRemote[player] < cooldown then
			return
		end

		lastRemote[player] = now

		local session = sessions[player]

		if session then
			cancelSession(session, "Coleta cancelada.")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]

		if session then
			endSession(session)
		end

		lastEnd[player] = nil
		lastRemote[player] = nil
	end)
end

return ResourceService
