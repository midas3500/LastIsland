--[[
	StatusExtrasClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > StatusExtrasClient

	Parte de baixo, no centro da tela:
	  🌡️ Barra de temperatura (Frio | Normal | Calor) com o nível do efeito
	  🫧 Barra de oxigênio (só aparece debaixo d'água ou enquanto recupera)
	  🏃 / 🧎 Indicadores de corrida e agachamento
	Lê atributos do Player definidos pelo servidor: BodyTemp, TempKind, TempLevel, Oxygen, MaxOxygen,
	Submerged, IsSprinting, IsCrouching.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local TC = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TemperatureConfig"))

local gui = Instance.new("ScreenGui")
gui.Name = "StatusExtras"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r) c.Parent = p return c end
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end

local scaleFactor = math.clamp(Workspace.CurrentCamera.ViewportSize.X / 1100, 0.75, 1)

local root = new("Frame", {
	Name = "Root", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
}, gui)
new("UIScale", { Scale = scaleFactor }, root)
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, root)

----------------------------------------------------------------------
-- Indicadores (corrida / agachar)
----------------------------------------------------------------------
local pills = new("Frame", { Size = UDim2.fromOffset(290, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, root)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }, pills)

local function pill(text, color)
	local f = new("Frame", { Size = UDim2.fromOffset(104, 22), BackgroundColor3 = Color3.fromRGB(16, 21, 28), BackgroundTransparency = 0.12, BorderSizePixel = 0, Visible = false }, pills)
	corner(f, 11)
	new("UIStroke", { Color = color, Thickness = 1.4, Transparency = 0.2 }, f)
	new("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = color }, f)
	return f
end
local sprintPill = pill("🏃 Correndo", Color3.fromRGB(110, 225, 150))
local crouchPill = pill("🧎 Agachado", Color3.fromRGB(130, 200, 255))

----------------------------------------------------------------------
-- Oxigênio
----------------------------------------------------------------------
local oxygen = new("Frame", { Size = UDim2.fromOffset(210, 22), BackgroundTransparency = 1, LayoutOrder = 2, Visible = false }, root)
new("TextLabel", { Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Text = "🫧", TextSize = 16, Font = Enum.Font.GothamBold }, oxygen)
local oxTrack = new("Frame", { Position = UDim2.fromOffset(26, 5), Size = UDim2.new(1, -26, 0, 12), BackgroundColor3 = Color3.fromRGB(34, 42, 52), BorderSizePixel = 0, ClipsDescendants = true }, oxygen)
corner(oxTrack, 6)
local oxFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, oxTrack)
corner(oxFill, 6)
local oxGradient = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), Color3.fromRGB(70, 160, 235)) }, oxFill)
new("Frame", { Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, oxFill)
local oxText = new("TextLabel", { Size = UDim2.new(1, -5, 1, 0), BackgroundTransparency = 1, Text = "", TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right }, oxTrack)

----------------------------------------------------------------------
-- Temperatura
----------------------------------------------------------------------
local tempCard = new("Frame", { Size = UDim2.fromOffset(290, 50), BackgroundColor3 = Color3.fromRGB(16, 21, 28), BackgroundTransparency = 0.12, BorderSizePixel = 0, LayoutOrder = 3 }, root)
corner(tempCard, 12)
new("UIStroke", { Color = Color3.fromRGB(150, 175, 200), Transparency = 0.7, Thickness = 1.2 }, tempCard)

local tempIcon = new("TextLabel", { Position = UDim2.fromOffset(10, 3), Size = UDim2.fromOffset(24, 22), BackgroundTransparency = 1, Text = "🌡️", TextSize = 17, Font = Enum.Font.GothamBold }, tempCard)
local tempState = new("TextLabel", { Position = UDim2.fromOffset(36, 3), Size = UDim2.new(1, -46, 0, 22), BackgroundTransparency = 1, Text = "Normal", TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(240, 244, 248), TextXAlignment = Enum.TextXAlignment.Left }, tempCard)

local tempTrack = new("Frame", { Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -24, 0, 9), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, tempCard)
corner(tempTrack, 5)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(90, 150, 255)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(110, 205, 235)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(120, 225, 150)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(245, 205, 90)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(240, 85, 70)),
	}),
}, tempTrack)
-- marcas das faixas Frio | Normal | Calor
for _, mark in { TC.Bands.ColdMild / 100, TC.Bands.HeatMild / 100 } do
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(mark, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0 }, tempTrack)
end
local marker = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 3 }, tempTrack)
corner(marker, 7)
local markerStroke = new("UIStroke", { Color = Color3.fromRGB(20, 26, 36), Thickness = 2 }, marker)

new("TextLabel", { Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(60, 11), BackgroundTransparency = 1, Text = "FRIO", TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(130, 170, 230), TextXAlignment = Enum.TextXAlignment.Left }, tempCard)
new("TextLabel", { Position = UDim2.new(0.5, -30, 0, 38), Size = UDim2.fromOffset(60, 11), BackgroundTransparency = 1, Text = "NORMAL", TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(140, 215, 160) }, tempCard)
new("TextLabel", { Position = UDim2.new(1, -72, 0, 38), Size = UDim2.fromOffset(60, 11), BackgroundTransparency = 1, Text = "CALOR", TextSize = 8, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(240, 140, 110), TextXAlignment = Enum.TextXAlignment.Right }, tempCard)

local LEVEL_TEXT = {
	Cold = { "", "🥶 Frio leve", "🥶 Frio intenso", "🥶 Hipotermia!" },
	Heat = { "", "🥵 Calor leve", "🥵 Calor intenso", "🥵 Insolação!" },
}

----------------------------------------------------------------------
-- Atualização suave
----------------------------------------------------------------------
local displayTemp = TC.Ideal
local oxDisplay = 1
local oxAlpha = 0

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()

	-- temperatura
	local temp = player:GetAttribute("BodyTemp") or TC.Ideal
	displayTemp += (temp - displayTemp) * (1 - math.exp(-dt * 6))
	marker.Position = UDim2.fromScale(math.clamp(displayTemp / 100, 0, 1), 0.5)

	local kind = player:GetAttribute("TempKind") or "None"
	local level = player:GetAttribute("TempLevel") or 0
	if kind == "None" or level == 0 then
		tempState.Text = "Temperatura normal"
		tempState.TextColor3 = Color3.fromRGB(150, 225, 170)
		tempIcon.Text = "🌡️"
		markerStroke.Color = Color3.fromRGB(20, 26, 36)
	else
		tempState.Text = LEVEL_TEXT[kind][level + 1]
		local color = kind == "Cold" and Color3.fromRGB(130, 190, 255) or Color3.fromRGB(255, 150, 110)
		tempState.TextColor3 = color
		tempIcon.Text = kind == "Cold" and "🥶" or "🥵"
		if level >= 3 then
			markerStroke.Color = color:Lerp(Color3.new(1, 1, 1), 0.5 + 0.5 * math.sin(now * 8))
			tempIcon.Rotation = math.sin(now * 14) * 6
		else
			markerStroke.Color = color
			tempIcon.Rotation = 0
		end
	end
	if level < 3 then tempIcon.Rotation = 0 end

	-- oxigênio (aparece ao mergulhar e some depois de recuperar)
	local ox = player:GetAttribute("Oxygen") or 1
	local maxOx = player:GetAttribute("MaxOxygen") or 1
	local pct = maxOx > 0 and math.clamp(ox / maxOx, 0, 1) or 1
	local show = player:GetAttribute("Submerged") == true or pct < 0.995
	oxAlpha += ((show and 1 or 0) - oxAlpha) * (1 - math.exp(-dt * 8))
	oxygen.Visible = oxAlpha > 0.03
	oxDisplay += (pct - oxDisplay) * (1 - math.exp(-dt * 10))
	oxFill.Size = UDim2.fromScale(oxDisplay, 1)
	oxText.Text = tostring(math.ceil(ox))
	if pct < 0.25 then
		oxGradient.Color = ColorSequence.new(Color3.fromRGB(255, 120, 110), Color3.fromRGB(205, 44, 60))
		oxFill.BackgroundTransparency = 0.05 + 0.3 * (0.5 + 0.5 * math.sin(now * 10))
	else
		oxGradient.Color = ColorSequence.new(Color3.fromRGB(150, 225, 255), Color3.fromRGB(70, 160, 235))
		oxFill.BackgroundTransparency = 0
	end

	-- indicadores
	sprintPill.Visible = player:GetAttribute("IsSprinting") == true
	crouchPill.Visible = player:GetAttribute("IsCrouching") == true
end)
