--[[
	SurvivalHUD (v3)  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > SurvivalHUD   (SUBSTITUI o anterior)

	Canto inferior esquerdo, compacto: VIDA, FOME (com linha de saciedade), STAMINA e SEDE.
	Ícones de efeitos (energia, náusea, veneno), transições nos níveis críticos e relógio.
	O botão de comer coco FOI REMOVIDO: agora se come/bebe pela mochila (tecla B).
	Corrida (Shift) e agachar (Ctrl) ficam no MovementClient.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sprintRemote = remotes:WaitForChild("SprintRequest")
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

local function sequence(a, b) return ColorSequence.new(a, b) end

local viewScale = math.clamp(Workspace.CurrentCamera.ViewportSize.X / 1100, 0.7, 1)

----------------------------------------------------------------------
-- Vinheta de estados críticos (bordas da tela)
----------------------------------------------------------------------
local vignette = new("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Active = false, ZIndex = 0 }, gui)
local vignetteEdges = {}
local EDGES = {
	{ Pos = UDim2.fromScale(0, 0), Size = UDim2.new(1, 0, 0.22, 0), Rot = 90 },     -- topo
	{ Pos = UDim2.fromScale(0, 0.78), Size = UDim2.new(1, 0, 0.22, 0), Rot = 270 }, -- base
	{ Pos = UDim2.fromScale(0, 0), Size = UDim2.new(0.14, 0, 1, 0), Rot = 0 },      -- esquerda
	{ Pos = UDim2.fromScale(0.86, 0), Size = UDim2.new(0.14, 0, 1, 0), Rot = 180 }, -- direita
}
for _, e in EDGES do
	local f = new("Frame", { Position = e.Pos, Size = e.Size, BackgroundColor3 = Color3.new(1, 0, 0), BackgroundTransparency = 0, BorderSizePixel = 0, Active = false }, vignette)
	new("UIGradient", { Rotation = e.Rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
	table.insert(vignetteEdges, f)
end
local vignetteAlpha, vignetteColor = 1, Color3.new(1, 0, 0)

----------------------------------------------------------------------
-- Painel de status (canto inferior esquerdo, compacto)
----------------------------------------------------------------------
local panel = card(gui, {
	Name = "StatusPanel",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -12),
	Size = UDim2.fromOffset(196, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
})
new("UIScale", { Scale = viewScale }, panel)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, panel)
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local BAR_DEFS = {
	{ Key = "Health",  Icon = "❤️", Colors = { Color3.fromRGB(255, 120, 120), Color3.fromRGB(226, 62, 84) } },
	{ Key = "Hunger",  Icon = "🍖", Colors = { Color3.fromRGB(255, 208, 100), Color3.fromRGB(240, 142, 52) }, Attr = "Hunger", MaxAttr = "MaxHunger", HasSaturation = true },
	{ Key = "Stamina", Icon = "⚡", Colors = { Color3.fromRGB(120, 240, 170), Color3.fromRGB(52, 188, 132) }, Attr = "Stamina", MaxAttr = "MaxStamina" },
	{ Key = "Thirst",  Icon = "💧", Colors = { Color3.fromRGB(130, 206, 255), Color3.fromRGB(62, 140, 232) }, Attr = "Thirst", MaxAttr = "MaxThirst" },
}
local LOW_COLORS = { Color3.fromRGB(255, 120, 110), Color3.fromRGB(205, 44, 60) }

local bars = {}

local function createBar(def, order)
	local row = new("Frame", { Name = def.Key, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = order }, panel)
	local rowScale = new("UIScale", { Scale = 1 }, row)
	local icon = new("TextLabel", {
		Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Text = def.Icon, TextSize = 15,
		Font = Enum.Font.GothamBold, TextColor3 = C.Text,
	}, row)
	local track = new("Frame", {
		Position = UDim2.fromOffset(24, 3), Size = UDim2.new(1, -24, 0, 14), BackgroundColor3 = C.Track,
		BorderSizePixel = 0, ClipsDescendants = true,
	}, row)
	corner(track, 7)
	local ghost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, track)
	corner(ghost, 7)
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, track)
	corner(fill, 7)
	local grad = new("UIGradient", { Color = sequence(def.Colors[1], def.Colors[2]), Rotation = 90 }, fill)
	new("Frame", { Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.82, BorderSizePixel = 0 }, fill)
	local satLine
	if def.HasSaturation then
		satLine = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0, 0, 0, 3), BackgroundColor3 = Color3.fromRGB(255, 232, 130), BorderSizePixel = 0 }, track)
		corner(satLine, 2)
	end
	local value = new("TextLabel", {
		Size = UDim2.new(1, -5, 1, 0), BackgroundTransparency = 1, Text = "", TextSize = 10, Font = Enum.Font.GothamBold,
		TextColor3 = C.Text, TextStrokeTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Right,
	}, track)

	local bar = {
		Def = def, Row = row, RowScale = rowScale, Icon = icon, Value = value, Fill = fill, Ghost = ghost,
		Grad = grad, SatLine = satLine, Disp = 1, GhostDisp = 1, Level = 0, Low = false,
	}
	bars[def.Key] = bar
	return bar
end

for i, def in BAR_DEFS do createBar(def, i) end

-- ícones de efeitos ativos
local effectRow = new("Frame", { Name = "Effects", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 20 }, panel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, effectRow)

local EFFECTS = {
	{ Key = "Energy", Attr = "FxEnergyEnd", Emoji = "⚡", Color = Color3.fromRGB(110, 235, 160) },
	{ Key = "Nausea", Attr = "FxNauseaEnd", Emoji = "🤢", Color = Color3.fromRGB(190, 220, 90) },
	{ Key = "Poison", Attr = "FxPoisonEnd", Emoji = "☠️", Color = Color3.fromRGB(180, 110, 230) },
}
local effectChips = {}
for i, e in EFFECTS do
	local chip = new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(44, 20), BackgroundColor3 = C.Track, BorderSizePixel = 0, Visible = false }, effectRow)
	corner(chip, 8)
	new("UIStroke", { Color = e.Color, Transparency = 0.2, Thickness = 1.2 }, chip)
	new("TextLabel", { Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Text = e.Emoji, TextSize = 13, Font = Enum.Font.GothamBold }, chip)
	local timeLabel = new("TextLabel", { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(22, 20), BackgroundTransparency = 1, Text = "", TextSize = 10, Font = Enum.Font.GothamBold, TextColor3 = e.Color }, chip)
	effectChips[e.Key] = { Chip = chip, Label = timeLabel }
end

local function refreshSprint() end -- corrida e agachar agora ficam no MovementClient

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
-- Atualização das barras, efeitos e vinheta (animação suave)
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

-- efeitos de tela (náusea / veneno)
local colorFx = new("ColorCorrectionEffect", { Name = "SurvivalFx", Enabled = false }, Lighting)
local blurFx = new("BlurEffect", { Name = "SurvivalBlur", Size = 0, Enabled = false }, Lighting)
local nauseaAmount, poisonAmount = 0, 0

RunService:BindToRenderStep("SurvivalNauseaWobble", Enum.RenderPriority.Camera.Value + 1, function()
	if nauseaAmount > 0.02 then
		local camera = Workspace.CurrentCamera
		if camera then
			local t = os.clock()
			camera.CFrame *= CFrame.Angles(0, 0, math.rad(math.sin(t * 1.7) * 1.6 * nauseaAmount))
		end
	end
end)

local function pulseRow(bar, strength)
	bar.RowScale.Scale = 1 + strength
	TweenService:Create(bar.RowScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local pcts = {}

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()

	-- barras
	for key, bar in bars do
		local value, maximum = readStat(key)
		if value ~= nil then
			local pct = maximum > 0 and math.clamp(value / maximum, 0, 1) or 0
			pcts[key] = pct
			bar.Value.Text = tostring(math.floor(value + 0.5))

			bar.Disp += (pct - bar.Disp) * (1 - math.exp(-dt * 9))
			if bar.GhostDisp < bar.Disp then
				bar.GhostDisp = bar.Disp
			else
				bar.GhostDisp += (bar.Disp - bar.GhostDisp) * (1 - math.exp(-dt * 1.6))
			end
			bar.Fill.Size = UDim2.fromScale(bar.Disp, 1)
			bar.Ghost.Size = UDim2.fromScale(bar.GhostDisp, 1)

			if bar.SatLine then
				local sat = player:GetAttribute("Saturation") or 0
				local maxSat = player:GetAttribute("MaxSaturation") or 100
				local target = math.clamp(sat / maxSat, 0, 1)
				local current = bar.SatLine.Size.X.Scale
				bar.SatLine.Size = UDim2.new(current + (target - current) * (1 - math.exp(-dt * 6)), 0, 0, 3)
			end

			-- níveis críticos: 0 normal, 1 baixo (<25%), 2 crítico (<10%)
			local level = pct < 0.10 and 2 or (pct < 0.25 and 1 or 0)
			if level ~= bar.Level then
				if level > bar.Level then pulseRow(bar, 0.14) end
				bar.Level = level
				local colors = (level > 0) and LOW_COLORS or bar.Def.Colors
				bar.Grad.Color = sequence(colors[1], colors[2])
			end
			if bar.Level == 2 then
				local flash = 0.5 + 0.5 * math.sin(now * 9)
				bar.Fill.BackgroundTransparency = 0.05 + 0.4 * flash
				bar.Icon.Rotation = math.sin(now * 16) * 6
			elseif bar.Level == 1 then
				local pulse = 0.5 + 0.5 * math.sin(now * 5)
				bar.Fill.BackgroundTransparency = 0.05 + 0.2 * pulse
				bar.Icon.Rotation = math.sin(now * 10) * 3
			else
				bar.Fill.BackgroundTransparency = 0
				bar.Icon.Rotation = 0
			end
		end
	end

	-- efeitos ativos
	local active = {}
	for _, e in EFFECTS do
		local endsAt = player:GetAttribute(e.Attr)
		local left = endsAt and (endsAt - serverNow) or 0
		local chip = effectChips[e.Key]
		if left > 0 then
			chip.Chip.Visible = true
			chip.Label.Text = tostring(math.ceil(left))
			active[e.Key] = true
		else
			chip.Chip.Visible = false
		end
	end

	-- náusea e veneno na tela
	nauseaAmount += ((active.Nausea and 1 or 0) - nauseaAmount) * (1 - math.exp(-dt * 3))
	poisonAmount += ((active.Poison and 1 or 0) - poisonAmount) * (1 - math.exp(-dt * 3))
	local fxOn = nauseaAmount > 0.02 or poisonAmount > 0.02
	colorFx.Enabled = fxOn
	blurFx.Enabled = nauseaAmount > 0.02
	if fxOn then
		local tint = Color3.new(1, 1, 1)
			:Lerp(Color3.fromRGB(190, 235, 120), nauseaAmount * 0.45)
			:Lerp(Color3.fromRGB(205, 160, 255), poisonAmount * 0.3)
		colorFx.TintColor = tint
		colorFx.Saturation = -0.25 * nauseaAmount
		blurFx.Size = nauseaAmount * (3 + 3 * (0.5 + 0.5 * math.sin(now * 2.2)))
	end

	-- vinheta nas bordas (a condição mais grave manda)
	local intensity, color = 0, vignetteColor
	local function consider(amount, c)
		if amount > intensity then intensity, color = amount, c end
	end
	local health = pcts.Health or 1
	if health < 0.3 then
		consider((1 - health / 0.3) * 0.55 + 0.08 * math.sin(now * 6), Color3.fromRGB(255, 30, 40))
	end
	if (pcts.Thirst or 1) < 0.15 then
		consider((1 - (pcts.Thirst or 0) / 0.15) * 0.3, Color3.fromRGB(255, 190, 70))
	end
	if (pcts.Hunger or 1) < 0.15 then
		consider((1 - (pcts.Hunger or 0) / 0.15) * 0.3, Color3.fromRGB(255, 140, 50))
	end
	if poisonAmount > 0.05 then
		consider(0.28 * poisonAmount, Color3.fromRGB(160, 70, 230))
	end
	vignetteAlpha += ((1 - math.clamp(intensity, 0, 0.9)) - vignetteAlpha) * (1 - math.exp(-dt * 4))
	vignetteColor = vignetteColor:Lerp(color, 1 - math.exp(-dt * 5))
	for _, f in vignetteEdges do
		f.BackgroundTransparency = vignetteAlpha
		f.BackgroundColor3 = vignetteColor
	end
end)

refreshSprint()

