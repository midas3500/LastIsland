--[[
	ResourceService
	Local: ServerScriptService > Services > ResourceService
	(SUBSTITUI o arquivo vazio da Etapa 1: Ctrl+A, Delete e cole este)

	Cria os recursos coletáveis nos marcadores de Workspace > Map > ResourceSpawns e controla TODA a coleta.

	O QUE O SERVIDOR DECIDE (o cliente não decide nada):
	- se o jogador pode coletar (vivo, dono da ilha, ferramenta com nível suficiente, mochila com espaço)
	- a distância (na entrada e durante toda a coleta)
	- o tempo de coleta (ResourceConfig + velocidade da ferramenta)
	- a quantidade recebida (sorteio no servidor, com chance e multiplicadores)
	- o respawn do recurso

	COMO A COLETA COMEÇA: cada recurso tem um ProximityPrompt (tecla E no PC, botão na tela no celular).
	COMUNICAÇÃO (remote CollectResource):
		Servidor -> Cliente:  "Start" {Label, Duration} | "Done" {recompensas} | "Cancel" texto | "Denied" texto
		Cliente  -> Servidor: "Cancel"  (qualquer outra coisa é ignorada)

	API:
		ResourceService.GetNodes()                         -> lista de recursos (cópia simples)
		ResourceService.RegisterYieldModifier(function(player, def) return multiplicador end)
		ResourceService.Debug_TryGather(player, nodeModel) -> ok, motivo (só com GameConfig.Debug = true)
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

local Services = script.Parent
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local IslandService = require(Services:WaitForChild("IslandService"))
local InventoryService = require(Services:WaitForChild("InventoryService"))
local ResourceModelBuilder = require(Services:WaitForChild("ResourceModelBuilder"))

local Cfg = ResourceConfig.Gathering

local ResourceService = {}

-- ===========================================================================
-- ESTADO
-- ===========================================================================

local nodes = {}          -- [modelo] = registro
local nodeList = {}
local sessions = {}       -- [Player] = sessão de coleta em andamento
local lastEnd = {}        -- [Player] = quando terminou a última coleta
local lastRemote = {}     -- [Player] = último pedido de cancelamento
local yieldModifiers = {}
local rng = Random.new()
local remote = nil
local nodeCounter = 0

local cancelSession -- declarada aqui, definida mais abaixo

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function log(...)
	if GameConfig.Debug then
		print("[ResourceService]", ...)
	end
end

local function deny(player, reason)
	if remote and player.Parent then
		remote:FireClient(player, "Denied", reason)
	end
	log(string.format("Coleta negada para %s: %s", player.Name, reason))
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

-- ===========================================================================
-- FERRAMENTA NA MÃO (modelo criado por código, com texturas nativas)
-- ===========================================================================

local function createToolInstance(toolName, tierData)
	local visual = ResourceConfig.ToolVisual
	local length = visual.HandleLength

	local tool = Instance.new("Tool")
	tool.Name = tierData.Name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true
	tool.GripPos = visual.GripPos

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 0.35, length)
	handle.Material = ResourceConfig.Visuals.Trunk.Material
	handle.Color = ResourceConfig.Visuals.Trunk.Color
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local function addPiece(name, size, offset)
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.Material = tierData.HeadMaterial
		piece.Color = tierData.HeadColor
		piece.Reflectance = tierData.HeadReflectance or 0
		piece.CanCollide = false
		piece.Massless = true
		piece.CFrame = handle.CFrame * offset
		piece.Parent = tool

		local weld = Instance.new("Weld")
		weld.Part0 = handle
		weld.Part1 = piece
		weld.C0 = offset
		weld.Parent = piece
	end

	local frontZ = -length / 2
	if toolName == "Axe" then
		addPiece("Head", Vector3.new(0.22, 1.2, 0.9), CFrame.new(0, 0.2, frontZ + 0.45))
	else
		addPiece("Bar", Vector3.new(2.2, 0.3, 0.38), CFrame.new(0, 0, frontZ + 0.2))
		addPiece("TipL", Vector3.new(0.7, 0.28, 0.34), CFrame.new(-1.3, -0.18, frontZ + 0.2) * CFrame.Angles(0, 0, math.rad(-25)))
		addPiece("TipR", Vector3.new(0.7, 0.28, 0.34), CFrame.new(1.3, -0.18, frontZ + 0.2) * CFrame.Angles(0, 0, math.rad(25)))
	end

	return tool
end

local function equipTool(player, humanoid, tool)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		tool:Destroy()
		return false
	end
	tool.Parent = backpack
	humanoid:EquipTool(tool)
	return true
end

-- O script padrão "Animate" do Roblox toca a animação de golpe quando aparece um StringValue "toolanim"
local function swing(session)
	local tool = session.Tool
	if tool and tool.Parent then
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
	end
end

-- ===========================================================================
-- EFEITOS DO RECURSO
-- ===========================================================================

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
	emitter.LightEmission = 0
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
		record.Emitter:Emit((record.Def.Particle and record.Def.Particle.Count or 8))
	end
end

local function depleteNode(record)
	record.State = "Depleted"
	record.Prompt.Enabled = false

	-- desfaz o balanço ANTES de trocar os modelos (evita deslocar o visual "esgotado")
	record.Model:PivotTo(record.BasePivot)
	record.Full.Parent = nil
	if record.Depleted then
		record.Depleted.Parent = record.Model
	end

	if record.Emitter then
		record.Emitter:Emit((record.Def.Particle and record.Def.Particle.Count or 8) * 3)
	end

	local jitter = Cfg.RespawnJitter or 0
	local delay = record.Def.RespawnTime * (1 + rng:NextNumber(-jitter, jitter))
	local token = {}
	record.RespawnToken = token

	-- um timer por recurso (sem loops)
	task.delay(delay, function()
		if record.RespawnToken == token then
			respawnNode(record)
		end
	end)
end

-- ===========================================================================
-- SESSÃO DE COLETA
-- ===========================================================================

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

-- Retorna true, ou false + motivo (motivo nil = sessão já encerrada, não avisar)
local function checkSession(session)
	local player, record = session.Player, session.Record
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

	local maxDistance = (record.Def.MaxDistance or Cfg.DefaultMaxDistance) + Cfg.DistanceTolerance
	if (root.Position - record.Root.Position).Magnitude > maxDistance then
		return false, "Você se afastou demais."
	end

	if record.State ~= "Ready" then
		return false, "O recurso não está mais disponível."
	end

	return true
end

local function rollRewards(player, def, toolYield)
	local multiplier = ResourceConfig.GlobalYieldMultiplier * toolYield
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
				table.insert(result, { Item = reward.Item, Amount = amount })
			end
		end
	end
	return result
end

local function completeGather(session)
	local player, record, def = session.Player, session.Record, session.Record.Def

	if not PlayerDataService.GetData(player) then
		cancelSession(session, "Seus dados não estão disponíveis.")
		return
	end

	-- 1) calcula e entrega as recompensas (quantidade decidida AQUI, no servidor)
	local granted = {}
	for _, reward in ipairs(rollRewards(player, def, session.Yield)) do
		local added = InventoryService.AddItem(player, reward.Item, reward.Amount, "Gather:" .. record.Key)
		if added > 0 then
			table.insert(granted, {
				Item = reward.Item,
				Amount = added,
				Name = ResourceConfig.Items[reward.Item].DisplayName,
			})
		end
	end

	if #granted == 0 then
		cancelSession(session, "Mochila cheia.")
		return
	end

	-- 2) consome o recurso e encerra a sessão
	depleteNode(record)
	endSession(session)

	if player.Parent then
		remote:FireClient(player, "Done", granted)
	end
	log(string.format("%s coletou %s (%d tipos de item)", player.Name, record.Model.Name, #granted))
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
		task.delay(Cfg.HitDelay, function()
			if sessions[session.Player] == session then
				hitEffect(session.Record)
			end
		end)
		task.wait(math.min(Cfg.SwingInterval, remaining))
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

-- Todas as regras de entrada. Retorna true, ou false + motivo.
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

	-- posse: só o dono da ilha coleta nela
	if Cfg.OwnerOnly and record.IslandIndex > 0 and not IslandService.IsOwner(player, record.IslandIndex) then
		return deny(player, "Este recurso pertence a outro jogador.")
	end

	-- distância (medida no servidor, com a posição real do personagem)
	local maxDistance = (def.MaxDistance or Cfg.DefaultMaxDistance) + 2
	if (root.Position - record.Root.Position).Magnitude > maxDistance then
		return deny(player, "Você está muito longe.")
	end

	-- ferramenta e nível (lidos do perfil no servidor)
	local toolData = nil
	local speed, yield = 1, 1
	if def.Tool then
		local toolDef = ResourceConfig.Tools[def.Tool]
		local tier = clampTier(data.Tools and data.Tools[def.Tool], toolDef)
		if tier < (def.MinTier or 1) then
			return deny(player, string.format("Requer %s nível %d.", toolDef.DisplayName, def.MinTier))
		end
		toolData = toolDef.Tiers[tier]
		speed = toolData.Speed
		yield = toolData.Yield
	end

	-- espaço na mochila para o item principal
	local primary = def.Rewards[1].Item
	if not InventoryService.CanAdd(player, primary, 1) then
		return deny(player, "Mochila cheia: " .. ResourceConfig.Items[primary].DisplayName .. ".")
	end

	-- tempo de coleta (decidido aqui)
	local duration = math.max(Cfg.MinGatherTime, def.GatherTime / speed)

	local session = {
		Player = player,
		Record = record,
		Duration = duration,
		Yield = yield,
		Tool = nil,
	}
	sessions[player] = session
	record.User = player
	record.Prompt.Enabled = false

	-- vira o personagem para o recurso e equipa a ferramenta
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(record.Root.Position.X, root.Position.Y, record.Root.Position.Z))
	if toolData then
		local tool = createToolInstance(def.Tool, toolData)
		if equipTool(player, humanoid, tool) then
			session.Tool = tool
		end
	end

	remote:FireClient(player, "Start", {
		Label = def.ActionLabel or "Coletando...",
		Duration = duration,
	})

	task.spawn(function()
		local ok, err = pcall(runSession, session)
		if not ok then
			warn("[ResourceService] Erro na coleta: " .. tostring(err))
			cancelSession(session, "Erro interno.")
		end
	end)

	return true
end

-- ===========================================================================
-- CRIAÇÃO DOS RECURSOS NO MAPA
-- ===========================================================================

local function createNode(marker, templates)
	local key = marker:GetAttribute("ResourceType")
	local def = ResourceConfig.Nodes[key]
	if not def or def.Enabled == false then
		return false
	end

	local template = templates:FindFirstChild(def.Template)
	if not template then
		warn(string.format("[ResourceService] Template '%s' não encontrado (recurso %s).", def.Template, key))
		return false
	end

	nodeCounter += 1
	local model = template:Clone()
	model.Name = string.format("%s_%03d", def.Template, nodeCounter)

	-- o marcador fica 1 stud acima do chão
	local groundPosition = marker.Position - Vector3.new(0, 1, 0)
	model:PivotTo(CFrame.new(groundPosition) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0))

	local root = model.PrimaryPart or model:FindFirstChild("Root")
	local full = model:FindFirstChild("Full")
	local depleted = model:FindFirstChild("Depleted")
	if not root or not full then
		warn(string.format("[ResourceService] Template '%s' precisa ter Root e Full.", def.Template))
		model:Destroy()
		return false
	end
	if depleted then
		depleted.Parent = nil -- guardado até o recurso esgotar
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
	local minTierText = (def.Tool and (def.MinTier or 1) > 1) and string.format(" (nível %d)", def.MinTier) or ""

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = def.ActionText or "Coletar"
	prompt.ObjectText = def.DisplayName .. minTierText
	prompt.KeyboardKeyCode = Cfg.PromptKey
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
			warn("[ResourceService] Erro ao iniciar coleta: " .. tostring(err))
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

-- ===========================================================================
-- API
-- ===========================================================================

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
	table.insert(yieldModifiers, callback)
end

-- Simula um pedido de coleta direto no servidor (serve para testar as validações)
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

function ResourceService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectResource")

	-- Modelos-modelo (ServerStorage > ResourceModels)
	local templates = ServerStorage:FindFirstChild("ResourceModels")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "ResourceModels"
		templates.Parent = ServerStorage
	end
	local created = ResourceModelBuilder.EnsureTemplates(templates)
	log(string.format("%d modelo(s) de recurso criado(s).", created))

	-- Recursos nos marcadores do mapa
	local mapFolder = Workspace:FindFirstChild(MapConfig.Folders.Map)
	local spawnsRoot = mapFolder and mapFolder:FindFirstChild(MapConfig.Folders.ResourceSpawns)
	if not spawnsRoot then
		warn("[ResourceService] Pasta ResourceSpawns não encontrada. O MapService rodou?")
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
	log(string.format("%d recursos criados no mapa.", total))

	-- O cliente só pode CANCELAR. Qualquer outro conteúdo é ignorado.
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
