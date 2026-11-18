--[[
	SurvivalHUD (v2)  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > SurvivalHUD   (SUBSTITUI o atual)

	Interface de vida, fome, stamina (e sede, quando existir), horário e botões.
	Usa os MESMOS dados do seu jogo:
	  Player attributes: Hunger, MaxHunger, Stamina, MaxStamina  (opcional: Thirst, MaxThirst)
	  Lighting attributes: WorldClockTime, DayNumber
	  Remotes: SprintRequest, FoodRequest("EatCoconut")
	Controles: SHIFT = correr | F = comer coco
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sprintRemote = remotes:WaitForChild("SprintRequest")
local foodRemote = remotes:WaitForChild("FoodRequest")
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("SurvivalHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SurvivalHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 5
gui.Parent = playerGui

----------------------------------------------------------------------
-- Tema e helpers
----------------------------------------------------------------------
local C = {
	Card = Color3.fromRGB(16, 21, 28),
	Stroke = Color3.fromRGB(150, 175, 200),
	Text = Color3.fromRGB(242, 246, 250),
	Muted = Color3.fromRGB(150, 166, 182),
	Track = Color3.fromRGB(34, 42, 52),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

local function corner(parent, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent) end

local function card(parent, props)
	local f = new("Frame", props, parent)
	f.BackgroundColor3 = C.Card
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	corner(f, 14)
	new("UIStroke", { Color = C.Stroke, Transparency = 0.7, Thickness = 1.2 }, f)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.25) }),
	}, f)
	return f
end

local function sequence(a, b)
	return ColorSequence.new(a, b)
end

local viewScale = math.clamp(Workspace.CurrentCamera.ViewportSize.X / 1000, 0.72, 1)

----------------------------------------------------------------------
-- Painel de status (canto inferior esquerdo)
----------------------------------------------------------------------
local panel = card(gui, {
	Name = "StatusPanel",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(300, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
})
new("UIScale", { Scale = viewScale }, panel).Parent = panel
new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, panel)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local BAR_DEFS = {
	{ Key = "Health",  Title = "VIDA",    Icon = "❤️", Colors = { Color3.fromRGB(255, 120, 120), Color3.fromRGB(226, 62, 84) } },
	{ Key = "Hunger",  Title = "FOME",    Icon = "🍖", Colors = { Color3.fromRGB(255, 208, 100), Color3.fromRGB(240, 142, 52) }, Attr = "Hunger", MaxAttr = "MaxHunger" },
	{ Key = "Stamina", Title = "STAMINA", Icon = "⚡", Colors = { Color3.fromRGB(120, 240, 170), Color3.fromRGB(52, 188, 132) }, Attr = "Stamina", MaxAttr = "MaxStamina" },
	{ Key = "Thirst",  Title = "SEDE",    Icon = "💧", Colors = { Color3.fromRGB(130, 206, 255), Color3.fromRGB(62, 140, 232) }, Attr = "Thirst", MaxAttr = "MaxThirst", Optional = true },
}
local LOW_COLORS = { Color3.fromRGB(255, 120, 110), Color3.fromRGB(205, 44, 60) }

local bars = {}

local function createBar(def, order)
	local row = new("Frame", { Name = def.Key, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = order }, panel)
	local icon = new("TextLabel", {
		Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(0, 5), BackgroundTransparency = 1,
		Text = def.Icon, TextSize = 21, Font = Enum.Font.GothamBold, TextColor3 = C.Text,
	}, row)
	new("TextLabel", {
		Size = UDim2.new(0.5, -34, 0, 16), Position = UDim2.fromOffset(36, 0), BackgroundTransparency = 1,
		Text = def.Title, TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	local value = new("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, 0, 0, 0), BackgroundTransparency = 1,
		Text = "0/0", TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)

	local track = new("Frame", {
		Position = UDim2.fromOffset(36, 21), Size = UDim2.new(1, -36, 0, 12), BackgroundColor3 = C.Track,
		BorderSizePixel = 0, ClipsDescendants = true,
	}, row)
	corner(track, 6)

	local ghost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, track)
	corner(ghost, 6)

	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
	corner(fill, 6)
	local grad = new("UIGradient", { Color = sequence(def.Colors[1], def.Colors[2]), Rotation = 90 }, fill)
	local shine = new("Frame", { Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8, BorderSizePixel = 0 }, fill)
	corner(shine, 6)

	local bar = {
		Def = def, Row = row, Icon = icon, Value = value, Fill = fill, Ghost = ghost, Grad = grad,
		Disp = 1, GhostDisp = 1, Target = 1, Low = false,
	}
	bars[def.Key] = bar
	return bar
end

for i, def in BAR_DEFS do createBar(def, i) end

----------------------------------------------------------------------
-- Botões (comer / correr)
----------------------------------------------------------------------
local buttonRow = new("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 10 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, buttonRow)

local function createButton(name, text, color, order)
	local b = new("TextButton", {
		Name = name, Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0,
		Text = text, TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Font = Enum.Font.GothamBold,
		AutoButtonColor = false, LayoutOrder = order,
	}, buttonRow)
	corner(b, 10)
	new("UIGradient", { Rotation = 90, Color = sequence(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205)) }, b)
	new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.82, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end

local eatButton = createButton("EatButton", "🥥  Comer  [F]", Color3.fromRGB(176, 120, 58), 1)
local sprintButton = createButton("SprintButton", "🏃  Correr  [Shift]", Color3.fromRGB(46, 128, 92), 2)

local keyboardSprint, mobileSprint = false, false

local function refreshSprint()
	sprintRemote:FireServer(keyboardSprint or mobileSprint)
	local on = keyboardSprint or mobileSprint
	sprintButton.BackgroundColor3 = on and Color3.fromRGB(70, 180, 130) or Color3.fromRGB(46, 128, 92)
	sprintButton.Text = on and "🏃  Correndo..." or "🏃  Correr  [Shift]"
end

local function eat()
	foodRemote:FireServer("EatCoconut")
end

eatButton.Activated:Connect(eat)
sprintButton.Activated:Connect(function()
	mobileSprint = not mobileSprint
	refreshSprint()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		keyboardSprint = true
		refreshSprint()
	elseif input.KeyCode == Enum.KeyCode.F then
		eat()
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		keyboardSprint = false
		refreshSprint()
	end
end)

----------------------------------------------------------------------
-- Relógio (canto superior direito)
----------------------------------------------------------------------
local clock = card(gui, {
	Name = "ClockCard",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 14),
	Size = UDim2.fromOffset(210, 80),
})
new("UIScale", { Scale = viewScale }, clock)

local clockIcon = new("TextLabel", {
	Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1,
	Text = "☀️", TextSize = 30, Font = Enum.Font.GothamBold,
}, clock)
local dayLabel = new("TextLabel", {
	Position = UDim2.fromOffset(58, 8), Size = UDim2.new(1, -66, 0, 14), BackgroundTransparency = 1,
	Text = "DIA 1", TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left,
}, clock)
local timeLabel = new("TextLabel", {
	Position = UDim2.fromOffset(58, 20), Size = UDim2.new(1, -66, 0, 30), BackgroundTransparency = 1,
	Text = "08:00", TextSize = 26, Font = Enum.Font.GothamBold, TextColor3 = C.Text, TextXAlignment = Enum.TextXAlignment.Left,
}, clock)
local phaseLabel = new("TextLabel", {
	Position = UDim2.new(1, -90, 0, 8), Size = UDim2.fromOffset(78, 14), BackgroundTransparency = 1,
	Text = "Manhã", TextSize = 11, Font = Enum.Font.GothamMedium, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Right,
}, clock)

local dayTrack = new("Frame", { Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 7), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, clock)
corner(dayTrack, 4)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(26, 34, 78)),
		ColorSequenceKeypoint.new(0.22, Color3.fromRGB(70, 60, 120)),
		ColorSequenceKeypoint.new(0.30, Color3.fromRGB(255, 160, 90)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(120, 200, 255)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(255, 170, 90)),
		ColorSequenceKeypoint.new(0.82, Color3.fromRGB(80, 62, 130)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(26, 34, 78)),
	}),
}, dayTrack)
local marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.33, 0.5), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, dayTrack)
corner(marker, 7)
new("UIStroke", { Color = Color3.fromRGB(20, 26, 36), Thickness = 2 }, marker)

local function phaseOf(hour)
	if hour >= 5 and hour < 8 then return "Amanhecer", "🌅"
	elseif hour >= 8 and hour < 12 then return "Manhã", "☀️"
	elseif hour >= 12 and hour < 17 then return "Tarde", "🌤️"
	elseif hour >= 17 and hour < 19.5 then return "Entardecer", "🌇"
	end
	return "Noite", "🌙"
end

local function updateClock()
	local t = Lighting:GetAttribute("WorldClockTime") or Lighting.ClockTime
	local day = Lighting:GetAttribute("DayNumber") or 1
	t = t % 24
	local h = math.floor(t)
	local m = math.floor((t - h) * 60)
	local phase, icon = phaseOf(t)
	timeLabel.Text = string.format("%02d:%02d", h, m)
	dayLabel.Text = string.format("DIA %d", day)
	phaseLabel.Text = phase
	clockIcon.Text = icon
	marker.Position = UDim2.fromScale(t / 24, 0.5)
end

Lighting:GetAttributeChangedSignal("WorldClockTime"):Connect(updateClock)
Lighting:GetAttributeChangedSignal("DayNumber"):Connect(updateClock)
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateClock)
updateClock()

----------------------------------------------------------------------
-- Atualização das barras (animação suave)
----------------------------------------------------------------------
local function readStat(key)
	local def = bars[key].Def
	if key == "Health" then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then return hum.Health, hum.MaxHealth end
		return 100, 100
	end
	local value = player:GetAttribute(def.Attr)
	if value == nil then return nil, nil end
	return value, player:GetAttribute(def.MaxAttr) or 100
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for key, bar in bars do
		local value, maximum = readStat(key)
		if bar.Def.Optional then
			bar.Row.Visible = value ~= nil
		end
		if value ~= nil then
			local pct = maximum > 0 and math.clamp(value / maximum, 0, 1) or 0
			bar.Target = pct
			bar.Value.Text = string.format("%d/%d", math.floor(value + 0.5), math.floor(maximum + 0.5))

			bar.Disp += (pct - bar.Disp) * (1 - math.exp(-dt * 9))
			if bar.GhostDisp < bar.Disp then
				bar.GhostDisp = bar.Disp -- o rastro nunca fica atrás ao subir
			else
				-- desce devagar
				bar.GhostDisp += (bar.Disp - bar.GhostDisp) * (1 - math.exp(-dt * 1.6))
			end
			bar.Fill.Size = UDim2.fromScale(bar.Disp, 1)
			bar.Ghost.Size = UDim2.fromScale(bar.GhostDisp, 1)

			local low = pct < 0.2
			if low ~= bar.Low then
				bar.Low = low
				local colors = low and LOW_COLORS or bar.Def.Colors
				bar.Grad.Color = sequence(colors[1], colors[2])
			end
			if low then
				local pulse = 0.5 + 0.5 * math.sin(now * 6)
				bar.Fill.BackgroundTransparency = 0.05 + 0.25 * pulse
				bar.Icon.Rotation = math.sin(now * 14) * 4
			else
				bar.Fill.BackgroundTransparency = 0
				bar.Icon.Rotation = 0
			end
		end
	end
end)

refreshSprint()

