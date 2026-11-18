--[[
	EventBannerClient (v2)  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > EventBannerClient   (SUBSTITUI o anterior)

	  - Faixa de aviso no topo (eventos, preparação, ponte liberada)
	  - "Próximo evento em mm:ss"
	  - Contador grande dos 30 segundos de preparo (Player attribute PrepEndsAt)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remote = ReplicatedStorage:WaitForChild("IslandAnnouncement")

local gui = Instance.new("ScreenGui")
gui.Name = "IslandEventsGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(p, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r) c.Parent = p return c end

-- Faixa de aviso -------------------------------------------------------
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Size = UDim2.fromOffset(440, 80)
banner.Position = UDim2.new(0.5, 0, 0, -120)
banner.BackgroundColor3 = Color3.fromRGB(16, 21, 28)
banner.BackgroundTransparency = 0.1
banner.BorderSizePixel = 0
banner.Parent = gui
corner(banner, 14)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Parent = banner

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 30)
title.Position = UDim2.fromOffset(12, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 21
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = banner

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, -24, 0, 36)
body.Position = UDim2.fromOffset(12, 38)
body.Font = Enum.Font.Gotham
body.TextSize = 14
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextColor3 = Color3.fromRGB(225, 230, 238)
body.Parent = banner

local shownId = 0
Remote.OnClientEvent:Connect(function(t, text, color)
	shownId += 1
	local myId = shownId
	title.Text = t
	title.TextColor3 = color
	stroke.Color = color
	body.Text = text
	TweenService:Create(banner, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 22) }):Play()
	task.delay(7, function()
		if shownId == myId then
			TweenService:Create(banner, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
		end
	end)
end)

-- Contador do próximo evento ------------------------------------------
local timer = Instance.new("TextLabel")
timer.AnchorPoint = Vector2.new(0.5, 0)
timer.Position = UDim2.new(0.5, 0, 0, 4)
timer.Size = UDim2.fromOffset(260, 20)
timer.BackgroundTransparency = 1
timer.Font = Enum.Font.GothamMedium
timer.TextSize = 13
timer.TextColor3 = Color3.new(1, 1, 1)
timer.TextStrokeTransparency = 0.6
timer.Parent = gui

task.spawn(function()
	while true do
		local current = Workspace:GetAttribute("CurrentEvent")
		local nextT = Workspace:GetAttribute("NextEventTime")
		if current and current ~= "" then
			timer.Text = "⚠️ Evento em andamento"
		elseif nextT then
			local left = math.max(0, nextT - os.time())
			timer.Text = ("Próximo evento em %02d:%02d"):format(left // 60, left % 60)
		else
			timer.Text = ""
		end
		task.wait(1)
	end
end)

-- Preparação (30s) -----------------------------------------------------
local prep = Instance.new("Frame")
prep.AnchorPoint = Vector2.new(0.5, 0)
prep.Position = UDim2.new(0.5, 0, 0, 120)
prep.Size = UDim2.fromOffset(360, 74)
prep.BackgroundColor3 = Color3.fromRGB(14, 24, 34)
prep.BackgroundTransparency = 0.1
prep.BorderSizePixel = 0
prep.Visible = false
prep.Parent = gui
corner(prep, 14)
local prepStroke = Instance.new("UIStroke")
prepStroke.Color = Color3.fromRGB(110, 200, 255)
prepStroke.Thickness = 2
prepStroke.Transparency = 0.2
prepStroke.Parent = prep

local prepTitle = Instance.new("TextLabel")
prepTitle.BackgroundTransparency = 1
prepTitle.Position = UDim2.fromOffset(14, 6)
prepTitle.Size = UDim2.new(1, -28, 0, 26)
prepTitle.Font = Enum.Font.GothamBold
prepTitle.TextSize = 17
prepTitle.TextColor3 = Color3.fromRGB(190, 240, 255)
prepTitle.TextXAlignment = Enum.TextXAlignment.Left
prepTitle.Parent = prep

local prepTrack = Instance.new("Frame")
prepTrack.Position = UDim2.fromOffset(14, 44)
prepTrack.Size = UDim2.new(1, -28, 0, 14)
prepTrack.BackgroundColor3 = Color3.fromRGB(34, 44, 58)
prepTrack.BorderSizePixel = 0
prepTrack.Parent = prep
corner(prepTrack, 7)

local prepFill = Instance.new("Frame")
prepFill.Size = UDim2.fromScale(1, 1)
prepFill.BackgroundColor3 = Color3.new(1, 1, 1)
prepFill.BorderSizePixel = 0
prepFill.Parent = prepTrack
corner(prepFill, 7)
local prepGradient = Instance.new("UIGradient")
prepGradient.Color = ColorSequence.new(Color3.fromRGB(120, 220, 255), Color3.fromRGB(80, 150, 255))
prepGradient.Parent = prepFill

local PREP_TOTAL = 30
local shown = false

RunService.RenderStepped:Connect(function()
	local endsAt = player:GetAttribute("PrepEndsAt")
	if endsAt then
		local left = math.max(0, endsAt - Workspace:GetServerTimeNow())
		if not shown then
			shown = true
			prep.Visible = true
		end
		prepTitle.Text = ("⏳ Prepare-se!  Ponte libera em %ds"):format(math.ceil(left))
		prepFill.Size = UDim2.fromScale(math.clamp(left / PREP_TOTAL, 0, 1), 1)
	elseif shown then
		shown = false
		prep.Visible = false
	end
end)

