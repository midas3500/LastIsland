--[[
	EventFxClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > EventFxClient

	Desenha os efeitos dos eventos no cliente (o servidor só liga/desliga):
	  - Clima: Storm (chuva + céu escurecendo), Ash (cinzas), Fog (névoa), Heat (calor), Bloom (floração)
	    Tudo entra e sai de forma GRADUAL e volta exatamente ao normal quando o evento termina.
	  - Tremor de câmera (com alcance por distância), clarão de tela, empurrão, trovão, sons
	Mensagens do servidor (RemoteEvent ReplicatedStorage.EventFx):
	  "Weather" {Kind, On, Intensity} | "WeatherState" {kind=intensidade} | "ResetWeather"
	  "Shake"/"Rumble" {Intensity, Duration, Position?, Radius?} | "Flash" {Color, Duration, Position?, Radius?}
	  "Knock" Vector3 | "Thunder" {Position} | "Sfx" {Name, Position?}
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local fxRemote = ReplicatedStorage:WaitForChild("EventFx")

local function sfx(name, position)
	local event = ReplicatedStorage:FindFirstChild("PlaySfx")
	if event then event:Fire(name, position) end
end

----------------------------------------------------------------------
-- Clima
----------------------------------------------------------------------
local PRESETS = {
	Storm = { Tint = Color3.fromRGB(150, 165, 192), Brightness = -0.1, Saturation = -0.25, Contrast = 0.05,
		Exposure = -0.9, Density = 0.42, Haze = 2.2, FogEnd = 1100, Rain = true },
	Ash   = { Tint = Color3.fromRGB(160, 140, 128), Brightness = -0.14, Saturation = -0.3, Contrast = 0.04,
		Exposure = -0.7, Density = 0.5, Haze = 2.6, FogEnd = 900, Ash = true },
	Fog   = { Tint = Color3.fromRGB(205, 213, 222), Brightness = -0.02, Saturation = -0.15, Contrast = 0,
		Exposure = -0.2, Density = 0.62, Haze = 3, FogEnd = 450 },
	Heat  = { Tint = Color3.fromRGB(255, 226, 190), Brightness = 0.03, Saturation = 0.15, Contrast = 0.03,
		Exposure = 0.1, Density = 0.3, Haze = 1.6, FogEnd = 1500, Wobble = true },
	Bloom = { Tint = Color3.fromRGB(255, 236, 246), Brightness = 0, Saturation = 0.12, Contrast = 0,
		Exposure = 0, Density = 0, Haze = 0, FogEnd = 99999 },
}

local target, weight = {}, {}
for kind in PRESETS do
	target[kind], weight[kind] = 0, 0
end

local colorFx = Instance.new("ColorCorrectionEffect")
colorFx.Name = "EventFxColor"
colorFx.Parent = Lighting

local base -- valores normais do céu, capturados na primeira vez

local rainPart = Instance.new("Part")
rainPart.Name = "EventWeatherEmitterHolder"
rainPart.Anchored = true
rainPart.CanCollide = false
rainPart.CanQuery = false
rainPart.CanTouch = false
rainPart.Transparency = 1
rainPart.Size = Vector3.new(90, 1, 90)

local rain = Instance.new("ParticleEmitter")
rain.Name = "Rain"
rain.Rate = 0
rain.Lifetime = NumberRange.new(0.9, 1.1)
rain.Speed = NumberRange.new(95, 115)
rain.EmissionDirection = Enum.NormalId.Bottom
rain.Orientation = Enum.ParticleOrientation.VelocityParallel
rain.Squash = NumberSequence.new(-5)
rain.Size = NumberSequence.new(0.35)
rain.Transparency = NumberSequence.new(0.45)
rain.Color = ColorSequence.new(Color3.fromRGB(190, 210, 235))
rain.LightEmission = 0.25
rain.Parent = rainPart

local ash = Instance.new("ParticleEmitter")
ash.Name = "Ash"
ash.Rate = 0
ash.Lifetime = NumberRange.new(6, 8)
ash.Speed = NumberRange.new(4, 9)
ash.SpreadAngle = Vector2.new(35, 35)
ash.EmissionDirection = Enum.NormalId.Bottom
ash.Acceleration = Vector3.new(6, -3, 2)
ash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.9) })
ash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
ash.Color = ColorSequence.new(Color3.fromRGB(120, 112, 108))
ash.Rotation = NumberRange.new(0, 360)
ash.RotSpeed = NumberRange.new(-40, 40)
ash.Parent = rainPart

local function setWeather(kind, on, intensity)
	if PRESETS[kind] then
		target[kind] = on and (intensity or 1) or 0
	end
end

----------------------------------------------------------------------
-- Tremor de câmera
----------------------------------------------------------------------
local shakes = {}
local function addShake(data, scaleFactor)
	table.insert(shakes, {
		Start = os.clock(),
		Duration = data.Duration or 1,
		Intensity = (data.Intensity or 0.5) * (scaleFactor or 1),
		Position = data.Position,
		Radius = data.Radius,
	})
end

RunService:BindToRenderStep("EventShake", Enum.RenderPriority.Camera.Value + 3, function()
	local camera = Workspace.CurrentCamera
	if not camera or #shakes == 0 then return end
	local now = os.clock()
	local total = 0
	for i = #shakes, 1, -1 do
		local s = shakes[i]
		local age = now - s.Start
		if age >= s.Duration then
			table.remove(shakes, i)
		else
			local falloff = 1 - age / s.Duration
			local distanceFactor = 1
			if s.Position and s.Radius then
				distanceFactor = math.clamp(1 - (camera.CFrame.Position - s.Position).Magnitude / s.Radius, 0, 1)
			end
			total += s.Intensity * falloff * distanceFactor
		end
	end
	total = math.min(total, 1.5)
	if total <= 0.001 then return end
	local function noise(seed) return math.noise(now * 18, seed, 0) * 2 end
	camera.CFrame = camera.CFrame
		* CFrame.new(noise(1) * 0.22 * total, noise(2) * 0.22 * total, 0)
		* CFrame.Angles(noise(3) * 0.012 * total, noise(4) * 0.012 * total, noise(5) * 0.02 * total)
end)

----------------------------------------------------------------------
-- Clarão de tela
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "EventFxGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local flashFrame = Instance.new("Frame")
flashFrame.Size = UDim2.fromScale(1, 1)
flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
flashFrame.BackgroundTransparency = 1
flashFrame.BorderSizePixel = 0
flashFrame.Active = false
flashFrame.Parent = gui

local function flash(data)
	local alpha = 0.8
	local camera = Workspace.CurrentCamera
	if data.Position and data.Radius and camera then
		alpha = 0.85 * math.clamp(1 - (camera.CFrame.Position - data.Position).Magnitude / data.Radius, 0, 1)
	end
	if alpha <= 0.02 then return end
	flashFrame.BackgroundColor3 = data.Color or Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1 - alpha
	TweenService:Create(flashFrame, TweenInfo.new(data.Duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

----------------------------------------------------------------------
-- Mensagens do servidor
----------------------------------------------------------------------
fxRemote.OnClientEvent:Connect(function(kind, data)
	if kind == "Weather" and type(data) == "table" then
		setWeather(data.Kind, data.On, data.Intensity)
	elseif kind == "WeatherState" and type(data) == "table" then
		for k in PRESETS do target[k] = 0 end
		for k, v in data do setWeather(k, true, v) end
	elseif kind == "ResetWeather" then
		for k in PRESETS do target[k] = 0 end
	elseif (kind == "Shake" or kind == "Rumble") and type(data) == "table" then
		addShake(data, kind == "Rumble" and 0.5 or 1)
	elseif kind == "Flash" and type(data) == "table" then
		flash(data)
	elseif kind == "Knock" and typeof(data) == "Vector3" then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			root.AssemblyLinearVelocity = data
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	elseif kind == "Thunder" and type(data) == "table" and data.Position then
		local camera = Workspace.CurrentCamera
		local distance = camera and (camera.CFrame.Position - data.Position).Magnitude or 0
		task.delay(math.min(distance / 300, 3.5), function()
			sfx("Thunder")
		end)
	elseif kind == "Sfx" and type(data) == "table" and data.Name then
		sfx(data.Name, data.Position)
	end
end)

----------------------------------------------------------------------
-- Atualização gradual (todo quadro)
----------------------------------------------------------------------
local RATE = 0.45 -- ~2 a 3 segundos para entrar/sair do clima

RunService.RenderStepped:Connect(function(dt)
	local camera = Workspace.CurrentCamera
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

	if not base then
		base = {
			Density = atmosphere and atmosphere.Density or 0,
			Haze = atmosphere and atmosphere.Haze or 0,
			FogEnd = Lighting.FogEnd,
			Exposure = Lighting.ExposureCompensation,
			FOV = camera and camera.FieldOfView or 70,
		}
	end

	local anyActive = false
	local tint, brightness, saturation, contrast = Color3.new(1, 1, 1), 0, 0, 0
	local exposure, density, haze = 0, 0, 0
	local fogEnd = base.FogEnd
	local rainRate, ashRate, wobble = 0, 0, 0

	for kind, preset in PRESETS do
		local w = weight[kind]
		local goal = target[kind]
		if w ~= goal then
			w += math.clamp(goal - w, -RATE * dt, RATE * dt)
			weight[kind] = w
		end
		if w > 0.001 then
			anyActive = true
			tint = tint:Lerp(preset.Tint, w * 0.6)
			brightness += preset.Brightness * w
			saturation += preset.Saturation * w
			contrast += preset.Contrast * w
			exposure += preset.Exposure * w
			density = math.max(density, (preset.Density - base.Density) * w)
			haze = math.max(haze, (preset.Haze - base.Haze) * w)
			fogEnd = math.min(fogEnd, base.FogEnd + (preset.FogEnd - base.FogEnd) * w)
			if preset.Rain then rainRate += 950 * w end
			if preset.Ash then ashRate += 230 * w end
			if preset.Wobble then wobble += w end
		end
	end

	colorFx.Enabled = anyActive
	colorFx.TintColor = tint
	colorFx.Brightness = brightness
	colorFx.Saturation = saturation
	colorFx.Contrast = contrast
	Lighting.ExposureCompensation = base.Exposure + exposure
	Lighting.FogEnd = fogEnd
	if atmosphere then
		atmosphere.Density = math.clamp(base.Density + density, 0, 1)
		atmosphere.Haze = math.clamp(base.Haze + haze, 0, 10)
	end

	-- partículas seguem a câmera
	if camera then
		rainPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 45, 0))
		if rainPart.Parent ~= camera then rainPart.Parent = camera end
		if wobble > 0.01 then
			camera.FieldOfView = base.FOV + math.sin(os.clock() * 1.3) * 1.6 * wobble
		elseif camera.FieldOfView ~= base.FOV and not anyActive then
			camera.FieldOfView = base.FOV
		end
	end
	rain.Rate = rainRate
	ash.Rate = ashRate
end)
