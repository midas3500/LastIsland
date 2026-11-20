--[[
	TemperatureService
	Local: ServerScriptService > Services > TemperatureService   (ModuleScript, serviço com Init/Start)

	Temperatura corporal calculada no servidor a partir do ambiente: horário, altitude, vulcão (e erupção),
	água (e quanto tempo está encharcado), caverna, neve, praia e clima (tempestade, névoa, onda de calor).

	Atributos no Player (o HUD lê): BodyTemp, TempTarget, TempState ("Frio"/"Normal"/"Calor"),
	TempLevel (0 a 3), TempKind ("Cold"/"Heat"/"None"), InCave, Wetness
	Multiplicadores que o SurvivalService já usa: TempThirstMult, TempStaminaRegenMult, TempStaminaDrainMult
	Proteções futuras: atributos ColdResist / HeatResist (0 a 1) ou SetResistance().

	Coloque DEPOIS do SurvivalService e do IslandGenerator em GameConfig.ServiceLoadOrder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local TC = require(Modules:WaitForChild("TemperatureConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local GenCfg = require(Modules:WaitForChild("IslandGenConfig"))

local E = TC.Environment
local SEA = MapConfig.WaterLevel

local TemperatureService = {}

local states = {}
local generator

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function TemperatureService.SetResistance(player, cold, heat)
	if cold ~= nil then player:SetAttribute("ColdResist", clamp(cold, 0, 1)) end
	if heat ~= nil then player:SetAttribute("HeatResist", clamp(heat, 0, 1)) end
end

function TemperatureService.GetTemperature(player)
	local st = states[player]
	return st and st.Temp or nil
end

-- soma de tudo que esquenta (warm) e esfria (chill) na posição atual
local function environment(player, st, root, dt)
	local warm, chill = 0, 0

	-- horário
	local hour = Lighting:GetAttribute("WorldClockTime") or Lighting.ClockTime
	local daylight = math.sin((hour - 6) / 12 * math.pi)
	if daylight >= 0 then
		warm += E.DayWarm * daylight
	else
		chill += E.NightChill * -daylight
	end

	-- altitude e neve
	local altitude = root.Position.Y - SEA
	if altitude > E.AltitudeStart then
		chill += math.min((altitude - E.AltitudeStart) * E.AltitudeChillPerStud, E.AltitudeChillMax)
	end
	if altitude > GenCfg.Map.SnowLine then chill += E.SnowChill end
	if altitude > 0 and altitude < 6 then warm += E.BeachWarm end

	-- vulcão
	local volcano = generator and generator.Volcano
	if volcano then
		local dx, dz = root.Position.X - volcano.Center.X, root.Position.Z - volcano.Center.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local range = volcano.Radius * E.VolcanoRangeScale
		if distance < range then
			local k = (1 - distance / range) ^ 1.5
			if volcano.State == "Erupting" then k *= E.VolcanoEruptingMult end
			warm += E.VolcanoHeat * k
		end
	end

	-- água (nadar esfria cada vez mais: a roupa/corpo encharca)
	if player:GetAttribute("InWater") then
		chill += E.WaterChill
		st.Wet = math.min(1, st.Wet + E.WetGainPerSecond * dt)
	else
		st.Wet = math.max(0, st.Wet - E.WetLossPerSecond * dt)
	end
	chill += E.WetChill * st.Wet

	-- caverna
	local inCave = generator and generator.IsInCave and generator.IsInCave(root.Position) or false
	if inCave then chill += E.CaveChill end
	if player:GetAttribute("InCave") ~= inCave then player:SetAttribute("InCave", inCave) end

	-- clima
	if Workspace:GetAttribute("StormActive") then chill += E.StormChill end
	if Workspace:GetAttribute("FogActive") then chill += E.FogChill end
	if Workspace:GetAttribute("HeatActive") then warm += E.HeatWaveWarm end
	if Workspace:GetAttribute("AshActive") then warm += E.AshWarm end

	return warm, chill
end

local function levelOf(temp)
	local B = TC.Bands
	if temp < B.ColdSevere then return "Cold", 3 end
	if temp < B.ColdModerate then return "Cold", 2 end
	if temp < B.ColdMild then return "Cold", 1 end
	if temp > B.HeatSevere then return "Heat", 3 end
	if temp > B.HeatModerate then return "Heat", 2 end
	if temp > B.HeatMild then return "Heat", 1 end
	return "None", 0
end

local function updatePlayer(player, dt)
	local st = states[player]
	if not st or not player:GetAttribute("SurvivalReady") then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local warm, chill = environment(player, st, root, dt)
	local coldResist = clamp(player:GetAttribute("ColdResist") or 0, 0, 1)
	local heatResist = clamp(player:GetAttribute("HeatResist") or 0, 0, 1)
	local target = TC.Ideal + warm * (1 - heatResist) - chill * (1 - coldResist)
	target = clamp(target, 0, 100)

	st.Temp = clamp(st.Temp + (target - st.Temp) * (1 - math.exp(-dt / TC.Tau)), 0, 100)

	local kind, level = levelOf(st.Temp)
	local thirst, regen, drain, damage = 1, 1, 1, 0
	if kind ~= "None" then
		local fx = TC.Effects[kind][level]
		thirst = fx.Thirst or fx.ThirstRate or 1
		regen = fx.StaminaRegen or 1
		drain = fx.StaminaDrain or 1
		damage = fx.Damage or 0
	end

	-- dano só no nível severo, e cresce aos poucos (nunca é instantâneo)
	if damage > 0 then
		st.Severe += dt
		local ramp = math.min(1, st.Severe / TC.Effects.RampSeconds)
		humanoid:TakeDamage(damage * ramp * dt)
	else
		st.Severe = math.max(0, st.Severe - dt * 2)
	end

	player:SetAttribute("BodyTemp", st.Temp)
	player:SetAttribute("TempTarget", target)
	player:SetAttribute("Wetness", st.Wet)
	player:SetAttribute("TempKind", kind)
	player:SetAttribute("TempLevel", level)
	player:SetAttribute("TempState", kind == "Cold" and "Frio" or (kind == "Heat" and "Calor" or "Normal"))
	player:SetAttribute("TempThirstMult", thirst)
	player:SetAttribute("TempStaminaRegenMult", regen)
	player:SetAttribute("TempStaminaDrainMult", drain)
end

local function addPlayer(player)
	states[player] = { Temp = TC.Ideal, Wet = 0, Severe = 0 }
	player:SetAttribute("BodyTemp", TC.Ideal)
	player:SetAttribute("TempState", "Normal")
	player:SetAttribute("TempLevel", 0)
	player:SetAttribute("TempKind", "None")
	player:SetAttribute("InCave", false)
	-- ao renascer volta à temperatura ideal
	player.CharacterAdded:Connect(function()
		local st = states[player]
		if st then st.Temp, st.Wet, st.Severe = TC.Ideal, 0, 0 end
	end)
end

function TemperatureService.Init()
end

function TemperatureService.Start()
	local module = script.Parent:FindFirstChild("IslandGenerator")
	if module then
		local ok, result = pcall(require, module)
		if ok then generator = result end
	end

	Players.PlayerAdded:Connect(addPlayer)
	for _, player in Players:GetPlayers() do addPlayer(player) end
	Players.PlayerRemoving:Connect(function(player) states[player] = nil end)

	task.spawn(function()
		while true do
			local dt = task.wait(TC.UpdateInterval)
			for player in pairs(states) do
				updatePlayer(player, dt)
			end
		end
	end)
end

return TemperatureService

