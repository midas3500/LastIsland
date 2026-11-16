
--[[
    SurvivalHUD
    Local: StarterPlayer > StarterPlayerScripts

    Interface de fome, stamina, horário e alimentação.
    Controles:
    SHIFT = correr
    F = comer coco
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local sprintRemote = remotes:WaitForChild("SprintRequest")
local foodRemote = remotes:WaitForChild("FoodRequest")

local playerGui = player:WaitForChild("PlayerGui")

-- Evita duplicar a interface.
local oldGui = playerGui:FindFirstChild("SurvivalHUD")

if oldGui then
	oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SurvivalHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = playerGui

-- INTERFACE PRINCIPAL -------------------------------------

local panel = Instance.new("Frame")
panel.Name = "SurvivalPanel"
panel.Size = UDim2.fromOffset(285, 150)
panel.Position = UDim2.new(0, 18, 1, -175)
panel.BackgroundColor3 = Color3.fromRGB(20, 25, 32)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 105, 120)
panelStroke.Transparency = 0.55
panelStroke.Thickness = 1
panelStroke.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

-- FUNÇÃO PARA CRIAR TEXTOS -------------------------------

local function createLabel(name, text, height, order)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextSize = 14
	label.Font = Enum.Font.GothamSemibold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.LayoutOrder = order
	label.Parent = panel

	return label
end

-- FUNÇÃO PARA CRIAR BARRAS -------------------------------

local function createBar(name, title, color, order)
	local container = Instance.new("Frame")
	container.Name = name
	container.Size = UDim2.new(1, 0, 0, 28)
	container.BackgroundTransparency = 1
	container.LayoutOrder = order
	container.Parent = panel

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 15)
	label.BackgroundTransparency = 1
	label.Text = title .. " 100/100"
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextSize = 12
	label.Font = Enum.Font.GothamSemibold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = container

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Position = UDim2.fromOffset(0, 18)
	background.Size = UDim2.new(1, 0, 0, 9)
	background.BackgroundColor3 = Color3.fromRGB(55, 60, 68)
	background.BorderSizePixel = 0
	background.Parent = container

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return {
		Fill = fill,
		Label = label,
	}
end

-- HORÁRIO -------------------------------------------------

local clockLabel = createLabel(
	"Clock",
	"DIA 1  |  08:00",
	20,
	1
)

clockLabel.TextSize = 15

-- BARRAS --------------------------------------------------

local hungerBar = createBar(
	"Hunger",
	"FOME",
	Color3.fromRGB(235, 170, 65),
	2
)

local staminaBar = createBar(
	"Stamina",
	"STAMINA",
	Color3.fromRGB(75, 190, 115),
	3
)

-- BOTÕES --------------------------------------------------

local buttonContainer = Instance.new("Frame")
buttonContainer.Name = "Buttons"
buttonContainer.Size = UDim2.new(1, 0, 0, 30)
buttonContainer.BackgroundTransparency = 1
buttonContainer.LayoutOrder = 4
buttonContainer.Parent = panel

local buttonLayout = Instance.new("UIListLayout")
buttonLayout.FillDirection = Enum.FillDirection.Horizontal
buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
buttonLayout.Padding = UDim.new(0, 8)
buttonLayout.Parent = buttonContainer

local function createButton(name, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0.5, -4, 1, 0)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 12
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = buttonContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button

	return button
end

local eatButton = createButton(
	"EatButton",
	"COMER COCO [F]",
	Color3.fromRGB(165, 115, 55)
)

local sprintButton = createButton(
	"SprintButton",
	"CORRER",
	Color3.fromRGB(50, 125, 85)
)

-- CONTROLES -----------------------------------------------

local keyboardSprint = false
local mobileSprint = false

local function refreshSprint()
	sprintRemote:FireServer(keyboardSprint or mobileSprint)
end

local function eat()
	foodRemote:FireServer("EatCoconut")
end

eatButton.Activated:Connect(eat)

sprintButton.Activated:Connect(function()
	mobileSprint = not mobileSprint

	sprintButton.Text = mobileSprint
		and "PARAR"
		or "CORRER"

	refreshSprint()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift then

		keyboardSprint = true
		refreshSprint()

	elseif input.KeyCode == Enum.KeyCode.F then
		eat()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift
		or input.KeyCode == Enum.KeyCode.RightShift then

		keyboardSprint = false
		refreshSprint()
	end
end)

-- ATUALIZAÇÃO DAS BARRAS -------------------------------

local function updateBar(bar, attribute, maxAttribute, title)
	local value = player:GetAttribute(attribute) or 0
	local maximum = player:GetAttribute(maxAttribute) or 100

	local percent = 0

	if maximum > 0 then
		percent = math.clamp(value / maximum, 0, 1)
	end

	bar.Fill.Size = UDim2.fromScale(percent, 1)

	bar.Label.Text = string.format(
		"%s  %d/%d",
		title,
		math.floor(value),
		math.floor(maximum)
	)
end

local function updateHUD()
	updateBar(
		hungerBar,
		"Hunger",
		"MaxHunger",
		"FOME"
	)

	updateBar(
		staminaBar,
		"Stamina",
		"MaxStamina",
		"STAMINA"
	)
end

player:GetAttributeChangedSignal("Hunger"):Connect(updateHUD)
player:GetAttributeChangedSignal("Stamina"):Connect(updateHUD)
player:GetAttributeChangedSignal("MaxHunger"):Connect(updateHUD)
player:GetAttributeChangedSignal("MaxStamina"):Connect(updateHUD)

-- RELÓGIO -------------------------------------------------

local function updateClock()
	local clockTime = Lighting:GetAttribute("WorldClockTime")
		or Lighting.ClockTime

	local day = Lighting:GetAttribute("DayNumber") or 1

	local hours = math.floor(clockTime)
	local minutes = math.floor((clockTime - hours) * 60)

	clockLabel.Text = string.format(
		"DIA %d  |  %02d:%02d",
		day,
		hours,
		minutes
	)
end

Lighting:GetAttributeChangedSignal("WorldClockTime"):Connect(updateClock)
Lighting:GetAttributeChangedSignal("DayNumber"):Connect(updateClock)

-- INICIALIZAÇÃO -------------------------------------------

updateHUD()
updateClock()

log = nil
