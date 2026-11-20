--[[
	MovementClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > MovementClient

	Controles de movimento (PC e celular):
	  CORRER:   segurar SHIFT  |  celular: botão 🏃 (liga/desliga)
	  AGACHAR:  segurar CTRL   |  celular: botão 🧎 (liga/desliga)
	O servidor decide e valida tudo (stamina, água, agachar x correr); aqui só ficam os pedidos e o visual.
	Agachado: velocidade menor, passos bem mais baixos (volume), câmera mais baixa.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sprintRemote = remotes:WaitForChild("SprintRequest")
local crouchRemote = remotes:WaitForChild("CrouchRequest", 15)

local keySprint, touchSprint = false, false
local keyCrouch, touchCrouch = false, false

local function sendSprint()
	sprintRemote:FireServer(keySprint or touchSprint)
end
local function sendCrouch()
	if crouchRemote then crouchRemote:FireServer(keyCrouch or touchCrouch) end
end

local function typing()
	return UserInputService:GetFocusedTextBox() ~= nil
end

UserInputService.InputBegan:Connect(function(input)
	if typing() then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		keySprint = true
		-- correr levanta quem está agachado (o servidor também garante isso)
		keyCrouch = false
		touchCrouch = false
		sendSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		keyCrouch = true
		keySprint = false
		touchSprint = false
		sendCrouch()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		keySprint = false
		sendSprint()
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		keyCrouch = false
		sendCrouch()
	end
end)

-- se a stamina acabar (servidor desliga a corrida), o botão do celular desliga junto
player:GetAttributeChangedSignal("IsSprinting"):Connect(function()
	if not player:GetAttribute("IsSprinting") then
		touchSprint = false
		-- Shift ainda segurado: tenta voltar a correr assim que houver stamina
		if keySprint then
			task.delay(0.6, function()
				if keySprint and not player:GetAttribute("IsSprinting") then sendSprint() end
			end)
		end
	end
end)

----------------------------------------------------------------------
-- Botões do celular
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MovementControls"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function makeButton(name, emoji, position)
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = position
	b.Size = UDim2.fromOffset(54, 54)
	b.BackgroundColor3 = Color3.fromRGB(22, 28, 38)
	b.BackgroundTransparency = 0.15
	b.BorderSizePixel = 0
	b.Text = emoji
	b.TextSize = 26
	b.AutoButtonColor = false
	b.Visible = UserInputService.TouchEnabled
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(150, 175, 200)
	s.Transparency = 0.5
	s.Thickness = 1.5
	s.Parent = b
	return b, s
end

local sprintButton, sprintStroke = makeButton("SprintButton", "🏃", UDim2.new(1, -20, 1, -190))
local crouchButton, crouchStroke = makeButton("CrouchButton", "🧎", UDim2.new(1, -20, 1, -250))

sprintButton.Activated:Connect(function()
	touchSprint = not touchSprint
	if touchSprint then touchCrouch = false end
	sendSprint()
	if touchSprint then sendCrouch() end
end)
crouchButton.Activated:Connect(function()
	touchCrouch = not touchCrouch
	if touchCrouch then touchSprint = false end
	sendCrouch()
	if touchCrouch then sendSprint() end
end)

-- destaque dos botões quando ativos (vem do servidor)
local ACTIVE = Color3.fromRGB(110, 225, 150)
local IDLE = Color3.fromRGB(150, 175, 200)
local function refreshButtons()
	local sprinting = player:GetAttribute("IsSprinting") == true
	local crouching = player:GetAttribute("IsCrouching") == true
	sprintStroke.Color = sprinting and ACTIVE or IDLE
	sprintStroke.Transparency = sprinting and 0 or 0.5
	crouchStroke.Color = crouching and ACTIVE or IDLE
	crouchStroke.Transparency = crouching and 0 or 0.5
end
player:GetAttributeChangedSignal("IsSprinting"):Connect(refreshButtons)
player:GetAttributeChangedSignal("IsCrouching"):Connect(function()
	refreshButtons()
	if not player:GetAttribute("IsCrouching") then touchCrouch = false end
end)
refreshButtons()

----------------------------------------------------------------------
-- Visual do agachar (câmera) e passos mais baixos para TODOS os jogadores
----------------------------------------------------------------------
local cameraTween
player:GetAttributeChangedSignal("IsCrouching"):Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if cameraTween then cameraTween:Cancel() end
	local goal = player:GetAttribute("IsCrouching") and Vector3.new(0, -1.6, 0) or Vector3.zero
	cameraTween = TweenService:Create(hum, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { CameraOffset = goal })
	cameraTween:Play()
end)

local baseVolume = setmetatable({}, { __mode = "k" })
RunService.Heartbeat:Connect(function()
	for _, other in Players:GetPlayers() do
		local char = other.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local running = root and root:FindFirstChild("Running")
		if running and running:IsA("Sound") then
			if not baseVolume[running] then baseVolume[running] = running.Volume end
			-- NoiseLevel vem do servidor: 0.2 agachado, 1 andando, 1.8 correndo
			local noise = other:GetAttribute("NoiseLevel")
			if noise then
				running.Volume = baseVolume[running] * math.clamp(noise, 0, 1.8)
			end
		end
	end
end)

