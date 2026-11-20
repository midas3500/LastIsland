--[[
	AudioClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > AudioClient

	Efeitos sonoros do jogo. Cada som só toca quando a ação REAL acontece:
	  - coleta: pancadas enquanto coleta (por ferramenta/recurso) e som ao receber o item
	  - comer/beber: quando o servidor confirma (FoodRequest "Consumed")
	  - água: entrar/sair/braçadas (atributo InWater, definido pelo servidor)
	  - melhorias de mochila/ferramentas: só quando o servidor confirma

	Outros scripts do cliente podem tocar sons assim (crafting, construção...):
	  ReplicatedStorage:WaitForChild("PlaySfx"):Fire("CraftDone")

	Volume: botão 🔊 no canto superior direito (barra deslizante). Os IDs ficam no AudioConfig.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local cfg = require(Modules:WaitForChild("AudioConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")

----------------------------------------------------------------------
-- Grupo de volume
----------------------------------------------------------------------
local group = Instance.new("SoundGroup")
group.Name = "SFX"
group.Volume = cfg.DefaultVolume
group.Parent = SoundService

local failedIds = {}
local active = 0
local lastPlayed = {}

----------------------------------------------------------------------
-- Tocar sons
----------------------------------------------------------------------
local function pickId(def)
	local usable = {}
	for _, id in def.Ids do
		if not failedIds[id] then table.insert(usable, id) end
	end
	if #usable == 0 then return nil end
	return usable[math.random(#usable)]
end

local function play(name, position, volumeScale)
	local def = cfg.Sounds[name]
	if not def then return end
	local id = pickId(def)
	if not id then return end -- pendente ou falhou: silêncio

	local now = os.clock()
	if def.Cooldown and lastPlayed[name] and now - lastPlayed[name] < def.Cooldown then return end
	if active >= cfg.MaxSimultaneous then return end
	lastPlayed[name] = now

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. id
	sound.Volume = (def.Volume or 0.6) * (volumeScale or 1)
	sound.SoundGroup = group
	if def.Pitch then
		sound.PlaybackSpeed = def.Pitch[1] + math.random() * (def.Pitch[2] - def.Pitch[1])
	end

	local holder
	if position then
		holder = Instance.new("Attachment")
		holder.WorldPosition = position
		holder.Parent = Workspace.Terrain
		sound.RollOffMaxDistance = 90
		sound.Parent = holder
	else
		sound.Parent = SoundService
	end

	active += 1
	local released = false
	local function release()
		if released then return end
		released = true
		active -= 1
		sound:Destroy()
		if holder then holder:Destroy() end
	end
	sound.Ended:Connect(release)
	sound:Play()
	task.delay(8, release) -- garantia contra sons que não terminam
end

-- API para outros scripts do cliente
local playEvent = Instance.new("BindableEvent")
playEvent.Name = "PlaySfx"
playEvent.Parent = ReplicatedStorage
playEvent.Event:Connect(function(name, position)
	play(name, position)
end)

-- Testa os IDs ao iniciar e ignora os que falharem
task.spawn(function()
	local probes = {}
	for _, def in cfg.Sounds do
		for _, id in def.Ids do
			local probe = Instance.new("Sound")
			probe.SoundId = "rbxassetid://" .. id
			table.insert(probes, probe)
		end
	end
	if #probes == 0 then return end
	ContentProvider:PreloadAsync(probes, function(contentId, status)
		if status ~= Enum.AssetFetchStatus.Success then
			local id = tonumber(tostring(contentId):match("%d+"))
			if id then failedIds[id] = true end
			warn("[AudioClient] Áudio com falha ou sem permissão: " .. tostring(contentId))
		end
	end)
	for _, p in probes do p:Destroy() end
end)

----------------------------------------------------------------------
-- Coleta: o SERVIDOR avisa cada golpe real ("Hit") e a conclusão ("Done").
-- Negada ("Denied") ou cancelada ("Cancel") = silêncio.
----------------------------------------------------------------------
local lastGatherKey, lastGatherPosition, lastGatherTime = nil, nil, 0

local function audioForNode(key)
	local def = ResourceConfig.Nodes[key]
	local base = key:gsub("_V%d+$", "")
	return cfg.Gather.ByNode[base] or (def and cfg.Gather.ByTool[def.Tool]) or { Hit = { "LeafRip" }, Done = {} }
end

local collectRemote = remotes:FindFirstChild("CollectResource")
if collectRemote then
	collectRemote.OnClientEvent:Connect(function(kind, data)
		if kind == "Hit" and type(data) == "table" and data.Key then
			lastGatherKey, lastGatherPosition, lastGatherTime = data.Key, data.Position, os.clock()
			local audio = audioForNode(data.Key)
			if #audio.Hit > 0 then
				play(audio.Hit[math.random(#audio.Hit)], data.Position)
			end
		elseif kind == "Done" then
			if lastGatherKey then
				for _, name in audioForNode(lastGatherKey).Done do
					play(name, lastGatherPosition)
				end
			end
			lastGatherTime = os.clock()
			lastGatherKey = nil
		elseif kind == "Cancel" or kind == "Denied" then
			lastGatherKey = nil
		end
	end)
end

----------------------------------------------------------------------
-- Itens recebidos de outras formas (ex: recolher do chão)
----------------------------------------------------------------------
local previousItems = nil
local inventoryRemote = remotes:WaitForChild("UpdateInventory")
inventoryRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or type(data.Items) ~= "table" then return end
	if previousItems and os.clock() - lastGatherTime > 3 then
		for id, count in data.Items do
			if count > (previousItems[id] or 0) then
				local name = cfg.ItemPickup[id]
				if name then play(name) end
				break
			end
		end
	end
	previousItems = table.clone(data.Items)
end)

----------------------------------------------------------------------
-- Comer / beber
----------------------------------------------------------------------
local foodRemote = remotes:FindFirstChild("FoodRequest")
if foodRemote then
	foodRemote.OnClientEvent:Connect(function(kind, itemId, action)
		if kind ~= "Consumed" then return end
		if action == "Drink" then
			play("Drink")
			task.delay(0.4, function() play("Gulp") end)
		else
			if cfg.Crunchy[itemId] then play("Bite") end
			task.delay(0.15, function() play("Eat") end)
		end
	end)
end

----------------------------------------------------------------------
-- Melhorias (só quando o servidor confirma)
----------------------------------------------------------------------
local backpackRemote = remotes:FindFirstChild("BackpackUpgrade")
if backpackRemote then
	backpackRemote.OnClientEvent:Connect(function(kind, success)
		if kind == "Result" and success then play("BackpackUpgrade") end
	end)
end
local toolUpdate = remotes:FindFirstChild("ToolUpgradeUpdate")
if toolUpdate then
	toolUpdate.OnClientEvent:Connect(function(kind, success)
		if kind == "Result" and success then play("ToolUpgrade") end
	end)
end

----------------------------------------------------------------------
-- Água e natação (atributo InWater vem do servidor)
----------------------------------------------------------------------
local function characterPosition()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local wasInWater = player:GetAttribute("InWater") == true
player:GetAttributeChangedSignal("InWater"):Connect(function()
	local nowInWater = player:GetAttribute("InWater") == true
	if nowInWater and not wasInWater then
		play("WaterEnter", characterPosition())
	elseif not nowInWater and wasInWater then
		play("WaterExit", characterPosition())
	end
	wasInWater = nowInWater
end)

task.spawn(function()
	while true do
		task.wait(0.9)
		if player:GetAttribute("InWater") then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum and hum.MoveDirection.Magnitude > 0.1 then
				play("Swim", characterPosition())
			end
		end
	end
end)

----------------------------------------------------------------------
-- Controle de volume (botão 🔊 no canto superior direito)
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "AudioControls"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local speaker = Instance.new("TextButton")
speaker.AnchorPoint = Vector2.new(1, 0)
speaker.Position = UDim2.new(1, -16, 0, 104)
speaker.Size = UDim2.fromOffset(34, 34)
speaker.BackgroundColor3 = Color3.fromRGB(16, 21, 28)
speaker.BackgroundTransparency = 0.12
speaker.BorderSizePixel = 0
speaker.Text = "🔊"
speaker.TextSize = 17
speaker.AutoButtonColor = false
speaker.Parent = gui
corner(speaker, 10)

local popup = Instance.new("Frame")
popup.AnchorPoint = Vector2.new(1, 0)
popup.Position = UDim2.new(1, -56, 0, 104)
popup.Size = UDim2.fromOffset(190, 34)
popup.BackgroundColor3 = Color3.fromRGB(16, 21, 28)
popup.BackgroundTransparency = 0.1
popup.BorderSizePixel = 0
popup.Visible = false
popup.Parent = gui
corner(popup, 10)

local track = Instance.new("Frame")
track.Position = UDim2.fromOffset(14, 13)
track.Size = UDim2.new(1, -64, 0, 8)
track.BackgroundColor3 = Color3.fromRGB(40, 50, 62)
track.BorderSizePixel = 0
track.Parent = popup
corner(track, 4)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(cfg.DefaultVolume, 1)
fill.BackgroundColor3 = Color3.fromRGB(90, 190, 255)
fill.BorderSizePixel = 0
fill.Parent = track
corner(fill, 4)

local knob = Instance.new("Frame")
knob.AnchorPoint = Vector2.new(0.5, 0.5)
knob.Position = UDim2.fromScale(cfg.DefaultVolume, 0.5)
knob.Size = UDim2.fromOffset(16, 16)
knob.BackgroundColor3 = Color3.new(1, 1, 1)
knob.BorderSizePixel = 0
knob.Parent = track
corner(knob, 8)

local percent = Instance.new("TextLabel")
percent.Position = UDim2.new(1, -46, 0, 0)
percent.Size = UDim2.fromOffset(40, 34)
percent.BackgroundTransparency = 1
percent.TextColor3 = Color3.new(1, 1, 1)
percent.TextSize = 12
percent.Font = Enum.Font.GothamBold
percent.Parent = popup

local hit = Instance.new("TextButton")
hit.Position = UDim2.fromOffset(6, 4)
hit.Size = UDim2.new(1, -52, 1, -8)
hit.BackgroundTransparency = 1
hit.Text = ""
hit.AutoButtonColor = false
hit.Parent = popup
hit:SetAttribute("NoFx", true)

local function setVolume(v)
	v = math.clamp(v, 0, 1)
	group.Volume = v
	fill.Size = UDim2.fromScale(v, 1)
	knob.Position = UDim2.fromScale(v, 0.5)
	percent.Text = math.floor(v * 100 + 0.5) .. "%"
	speaker.Text = v <= 0.01 and "🔇" or "🔊"
	player:SetAttribute("SfxVolume", v)
end
setVolume(cfg.DefaultVolume)

local dragging = false
local function fromX(x)
	setVolume((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X))
end
hit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		fromX(input.Position.X)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		fromX(input.Position.X)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
speaker.Activated:Connect(function()
	popup.Visible = not popup.Visible
end)

