--[[
	PrepService
	Local: ServerScriptService > Services > PrepService   (ModuleScript, serviço com Init/Start)

	Quando o jogador recebe a ilha dele, ficam 30s (IslandGenConfig.Prep.Seconds) de preparo:
	  - uma barreira de energia fecha a ponte da ilha dele
	  - se ele cair na água e tentar nadar para fora, volta para o spawn da ilha
	  - passados os 30s a barreira some e ele pode atravessar a ponte até a ilha central

	Atributos no Player (para outros sistemas / HUD):
	  PrepEndsAt (Workspace:GetServerTimeNow() em que libera) e PrepLocked (bool)

	Coloque DEPOIS de IslandService e IslandGenerator em GameConfig.ServiceLoadOrder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("IslandGenConfig")).Prep
local IslandService = require(script.Parent:WaitForChild("IslandService"))
local Generator = require(script.Parent:WaitForChild("IslandGenerator"))

local PrepService = {}

local gates = {}  -- [indiceDaIlha] = { Part, Label, Visible }
local locked = {} -- [Player] = { Token, EndsAt, Index }
local processed = {} -- [Player] = true quando a preparação desse jogador já foi decidida
local howAssigned = {} -- [Player] = motivo informado pelo IslandService

local announce = ReplicatedStorage:FindFirstChild("IslandAnnouncement")
if not announce then
	announce = Instance.new("RemoteEvent")
	announce.Name = "IslandAnnouncement"
	announce.Parent = ReplicatedStorage
end

local function tell(player, title, text, color)
	if player.Parent then
		announce:FireClient(player, title, text, color)
	end
end

local function createGate(index, bridge)
	local part = Instance.new("Part")
	part.Name = "PrepGate_" .. index
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = Vector3.new(bridge.Width + 3, Cfg.GateHeight, 1)
	part.CFrame = bridge.GateCFrame
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(80, 200, 255)
	part.Transparency = 1
	part.Parent = bridge.Model

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(190, 44)
	gui.StudsOffset = Vector3.new(0, Cfg.GateHeight / 2 + 2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Enabled = false
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(14, 24, 34)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(190, 240, 255)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = ""
	label.Parent = gui
	Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)
	local pad = Instance.new("UIPadding", label)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)

	gates[index] = { Part = part, Gui = gui, Label = label }
end

local function setGate(index, on)
	local g = gates[index]
	if not g then return end
	g.Gui.Enabled = on
	if on then
		g.Part.CanCollide = true
		TweenService:Create(g.Part, TweenInfo.new(0.4), { Transparency = 0.45 }):Play()
	else
		g.Part.CanCollide = false
		TweenService:Create(g.Part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	end
end

local function islandStillLocked(index)
	for _, st in locked do
		if st.Index == index then return true end
	end
	return false
end

local function unlock(player, silent)
	local st = locked[player]
	if not st then return end
	locked[player] = nil
	if player.Parent then
		player:SetAttribute("PrepEndsAt", nil)
		player:SetAttribute("PrepLocked", false)
	end
	if not islandStillLocked(st.Index) then
		setGate(st.Index, false)
	end
	if not silent then
		tell(player, "✅ Ponte liberada!", "Atravesse a ponte e explore a ilha central. Boa sorte!", Color3.fromRGB(120, 230, 140))
	end
end

local function lock(player, info)
	local token = {}
	local endsAt = Workspace:GetServerTimeNow() + Cfg.Seconds
	locked[player] = { Token = token, EndsAt = endsAt, Index = info.Index }
	player:SetAttribute("PrepEndsAt", endsAt)
	player:SetAttribute("PrepLocked", true)
	setGate(info.Index, true)
	print(("[PrepService] %s preso na ilha %d por %ds"):format(player.Name, info.Index, Cfg.Seconds))
	tell(player, "⏳ Hora de se preparar", ("Colete recursos na sua ilha. A ponte para a ilha central libera em %d segundos."):format(Cfg.Seconds), Color3.fromRGB(110, 200, 255))
	task.delay(Cfg.Seconds, function()
		local st = locked[player]
		if st and st.Token == token then
			unlock(player, false)
		end
	end)
end

-- Pula a preparação (útil para testar): PrepService.Skip(player)
function PrepService.Skip(player)
	unlock(player, false)
end

function PrepService.IsLocked(player)
	return locked[player] ~= nil
end

function PrepService.Init()
end

-- Decide (uma única vez por jogador) se ele entra em preparação
local function consider(player)
	if processed[player] or player.Parent == nil then return end
	local info = IslandService.GetIslandOf(player)
	if not info then return end -- ainda sem ilha; tenta de novo no próximo ciclo
	processed[player] = true
	if howAssigned[player] == "reconnected" and not Cfg.RelockOnReconnect then
		return
	end
	lock(player, info)
end

function PrepService.Start()
	-- barreiras nas pontes
	local gateCount = 0
	for index, bridge in Generator.Bridges do
		createGate(index, bridge)
		gateCount += 1
	end
	print(("[PrepService] pronto. Barreiras criadas: %d"):format(gateCount))

	IslandService.OnAssigned(function(player, info, how)
		howAssigned[player] = how
		consider(player)
	end)

	IslandService.OnReleased(function(info)
		for player, st in locked do
			if st.Index == info.Index then
				unlock(player, true)
			end
		end
		setGate(info.Index, false)
	end)

	Players.PlayerRemoving:Connect(function(player)
		unlock(player, true)
		processed[player] = nil
		howAssigned[player] = nil
	end)

	-- Um único loop:
	--  1) pega jogadores que receberam ilha ANTES deste serviço começar a escutar (evita perder o aviso)
	--  2) mantém os presos na ilha e atualiza o texto das barreiras
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in Players:GetPlayers() do
				consider(player)
			end
			local now = Workspace:GetServerTimeNow()
			for player, st in locked do
				local info = IslandService.GetIslandOf(player)
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if info and root then
					local dx, dz = root.Position.X - info.Center.X, root.Position.Z - info.Center.Z
					local limit = info.Radius + Cfg.ConfineMargin
					if dx * dx + dz * dz > limit * limit then
						char:PivotTo(info.SpawnCFrame)
						root.AssemblyLinearVelocity = Vector3.zero
						tell(player, "🚧 Ainda não!", "Você só pode sair da sua ilha quando o tempo de preparo acabar.", Color3.fromRGB(255, 170, 90))
					end
				end
				local g = gates[st.Index]
				if g then
					local left = math.max(0, math.ceil(st.EndsAt - now))
					g.Label.Text = ("🔒 Libera em %ds"):format(left)
				end
			end
		end
	end)
end

return PrepService

