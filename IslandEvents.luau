--[[
	IslandEvents (v4)
	Local: ServerScriptService > Services > IslandEvents   (SUBSTITUI o atual; serviço com Init/Start)

	10 eventos: SupplyDrop, Meteor, MeteorShower, Storm, FruitBloom, Drought, VolcanoEruption,
	Earthquake, TidalWave, ThickFog. Dificuldade e alcance crescem com os dias e o nº de jogadores
	(EventsConfig.Difficulty).

	CLIMA: o servidor só liga/desliga e manda "EventFx" para os clientes; chuva, escuridão, neblina
	e cinzas são desenhados no cliente (EventFxClient). Todo evento com efeito persistente roda dentro
	de run(body, cleanup): o cleanup SEMPRE executa, mesmo se o evento der erro.

	Atributos no Workspace lidos por outros sistemas:
	  StormActive, WellRefillMultiplier, ThirstMultiplier, FruitYieldMultiplier,
	  WorldSpeedMultiplier, WorldStaminaRegenMultiplier, AshActive, CurrentEvent, NextEventTime
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EC = require(Modules:WaitForChild("EventsConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local GenCfg = require(Modules:WaitForChild("IslandGenConfig"))
local Models = require(script.Parent:WaitForChild("EventModels"))

local Events = {}
Events.Hooks = { GiveItem = nil } -- function(player, item, amount)

local G = nil
local SEA = MapConfig.WaterLevel

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local announceRemote = ensureRemote("IslandAnnouncement")
local fxRemote = ensureRemote("EventFx")

----------------------------------------------------------------------
-- Utilitários
----------------------------------------------------------------------
local function scale()
	local D = EC.Difficulty
	local day = Lighting:GetAttribute("DayNumber") or 1
	local s = 1 + D.DayRamp * (day - 1) + D.PlayerRamp * math.max(0, #Players:GetPlayers() - 1)
	return math.min(s, D.Max)
end
Events.Scale = scale

local function rangeScale(sc)
	return 1 + EC.Difficulty.RangeGrowth * (sc - 1)
end

local function announce(title, text, color)
	announceRemote:FireAllClients(title, text, color or Color3.fromRGB(255, 200, 80))
end

local activeWeather = {}
local function weather(kind, on, intensity)
	activeWeather[kind] = on and (intensity or 1) or nil
	fxRemote:FireAllClients("Weather", { Kind = kind, On = on, Intensity = intensity or 1 })
end

local function fx(kind, data)
	fxRemote:FireAllClients(kind, data)
end

local function alivePlayers()
	local list = {}
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			table.insert(list, { Player = plr, Root = root, Humanoid = hum })
		end
	end
	return list
end

-- empurrão aplicado no cliente do próprio jogador (confiável com a física dele)
local function knockback(entry, velocity)
	fxRemote:FireClient(entry.Player, "Knock", velocity)
end

local function damageNear(position, radius, amount, knockPower)
	for _, entry in alivePlayers() do
		local offset = entry.Root.Position - position
		local distance = offset.Magnitude
		if distance <= radius then
			entry.Humanoid:TakeDamage(amount * (1 - 0.5 * distance / radius))
			if knockPower and knockPower > 0 then
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
				knockback(entry, direction * knockPower * (1 - distance / radius) + Vector3.new(0, knockPower * 0.45, 0))
			end
		end
	end
end

local function giveItem(player, item, amount)
	if Events.Hooks.GiveItem then
		local ok, err = pcall(Events.Hooks.GiveItem, player, item, amount)
		if not ok then warn("[IslandEvents] GiveItem falhou:", err) end
	end
end

-- chão válido (ilha de jogador ou terreno), nunca embaixo d'água
local function groundBelow(position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { Models.Container() }
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 80, 0), Vector3.new(0, -300, 0), params)
	if hit and hit.Position.Y > SEA + 0.2 then
		return hit.Position
	end
	return nil
end

-- roda o corpo do evento e GARANTE a limpeza
local function run(body, cleanup)
	local ok, err = pcall(body)
	local okClean, errClean = pcall(cleanup)
	if not ok then warn("[IslandEvents] erro no evento: " .. tostring(err)) end
	if not okClean then warn("[IslandEvents] erro na limpeza: " .. tostring(errClean)) end
end

local function waitSeconds(seconds)
	local t = 0
	while t < seconds do
		t += task.wait(0.25)
	end
end

local function spawnNodeAt(key, position, lifetime)
	local model, marker = G.SpawnRuntimeNode(key, position)
	if model then
		model:SetAttribute("Temporary", true)
		task.delay(lifetime, function()
			G.RemoveRuntimeNode(model, marker)
		end)
	end
	return model
end

----------------------------------------------------------------------
-- Perigos no chão (lava, poças): um único laço aplica o dano
----------------------------------------------------------------------
local hazards = {}
local function addHazard(position, radius, dps, life)
	table.insert(hazards, { Pos = position, Radius = radius, Dps = dps, Expire = os.clock() + life })
end

local function hazardLoop()
	while true do
		task.wait(0.4)
		local now = os.clock()
		for i = #hazards, 1, -1 do
			if hazards[i].Expire < now then table.remove(hazards, i) end
		end
		if #hazards > 0 then
			for _, entry in alivePlayers() do
				local total = 0
				local p = entry.Root.Position
				for _, h in hazards do
					local dx, dz = p.X - h.Pos.X, p.Z - h.Pos.Z
					if dx * dx + dz * dz < h.Radius * h.Radius and math.abs(p.Y - h.Pos.Y) < 12 then
						total += h.Dps * 0.4
					end
				end
				if total > 0 then entry.Humanoid:TakeDamage(total) end
			end
		end
	end
end

----------------------------------------------------------------------
-- 📦 Caixa de suprimentos
----------------------------------------------------------------------
local function dropCrate(position, announceIt)
	local C = EC.SupplyDrop
	if announceIt then
		announce("📦 Caixa de Suprimentos", "Uma caixa está caindo do céu! Siga a fumaça vermelha antes que outro pegue.", Color3.fromRGB(255, 120, 90))
	end

	local model, handles = Models.Crate()
	model.Parent = Models.Container()
	local landing = position + Vector3.new(0, 2.1, 0)
	local startY = landing.Y + 220
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / C.FallTime
		if a >= 1 then break end
		local t = os.clock()
		handles.Place(CFrame.new(landing.X + math.sin(t * 0.9) * 3, startY + (landing.Y - startY) * a, landing.Z), math.sin(t * 1.8) * 0.09, math.cos(t * 1.4) * 0.07)
		RunService.Heartbeat:Wait()
	end
	handles.Place(CFrame.new(landing), 0, 0)
	Models.CollapseChute(handles.Chute)
	Models.DustBurst(position, 45, 9)
	fx("Shake", { Intensity = 0.35, Duration = 0.7, Position = position, Radius = 70 })
	handles.Body.CanCollide = true
	local flare = Models.Flare(position)

	-- luzes piscando
	task.spawn(function()
		while model.Parent do
			for _, b in handles.Blinkers do
				b.Part.Transparency = (math.floor(os.clock() * 2) % 2 == 0) and 0 or 0.7
				b.Light.Enabled = b.Part.Transparency == 0
			end
			task.wait(0.25)
		end
	end)

	local opened = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir caixa"
	prompt.ObjectText = "Suprimentos"
	prompt.HoldDuration = C.HoldDuration
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = handles.Body
	prompt.Triggered:Connect(function(player)
		if opened then return end
		opened = true
		for _, entry in C.Loot do
			if not entry.Chance or math.random() <= entry.Chance then
				giveItem(player, entry.Item, math.random(entry.Min, entry.Max))
			end
		end
		announce("📦 Caixa aberta", player.Name .. " pegou os suprimentos!", Color3.fromRGB(120, 220, 120))
	end)

	local waited = 0
	while not opened and waited < C.Lifetime and model.Parent do
		waited += task.wait(1)
	end
	model:Destroy()
	for _, f in flare do f:Destroy() end
end

local function supplyDrop()
	local sc = scale()
	local C = EC.SupplyDrop
	local count = 1
	if sc >= C.SecondCrateScale then count = 2 end
	if sc >= C.ThirdCrateScale then count = 3 end
	local threads = 0
	for i = 1, count do
		local position = G.RandomLandPoint("Lowland") or G.RandomLandPoint("Land")
		if position then
			threads += 1
			task.spawn(function()
				dropCrate(position, i == 1)
				threads -= 1
			end)
			task.wait(2.5)
		end
	end
	while threads > 0 do task.wait(1) end
end

----------------------------------------------------------------------
-- ☄️ Meteoro e chuva de meteoros
----------------------------------------------------------------------
local function meteorStrike(target, C, sc)
	local radius = C.Radius * rangeScale(sc)
	Models.WarningRing(target, radius, C.Warning)
	fx("Sfx", { Name = "MeteorWhoosh", Position = target })
	task.wait(C.Warning)

	local meteor, place = Models.Meteor(C.Size)
	meteor.Parent = Models.Container()
	local from = target + Vector3.new(math.random(-1, 1) * 150 + 40, 320, math.random(-1, 1) * 150 + 40)
	local to = target + Vector3.new(0, C.Size * 0.3, 0)
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / C.FallTime
		if a >= 1 then break end
		place(CFrame.new(from:Lerp(to, a * a)) * CFrame.Angles(a * 7, a * 5, 0))
		RunService.Heartbeat:Wait()
	end
	meteor:Destroy()

	Models.Impact(target, radius)
	damageNear(target, radius, C.Damage * sc, C.Knock)
	fx("Shake", { Intensity = 0.95, Duration = 1.5, Position = target, Radius = radius * 10 })
	fx("Flash", { Color = Color3.fromRGB(255, 190, 110), Duration = 0.6, Position = target, Radius = radius * 12 })
	fx("Sfx", { Name = "Explosion", Position = target })
end

local function meteor()
	local sc = scale()
	local C = EC.Meteor
	local target = G.RandomLandPoint("Hills") or G.RandomLandPoint("Lowland")
	if not target then return end
	announce("☄️ Meteoro!", ("Um meteoro gigante cai em %d segundos! Saia da área vermelha."):format(C.Warning), Color3.fromRGB(255, 90, 60))
	meteorStrike(target, C, sc)

	local pool = { "OreIron", "OreIron", "OreCoal", "OreCopper", "OreGold", "OreCrystal", "Rock" }
	local spawned = 0
	for i = 1, math.floor(C.OreCount * (0.8 + 0.2 * sc)) do
		local a = (i / C.OreCount) * math.pi * 2
		local d = math.random(10, 20)
		local p = G.GroundAt(target.X + math.cos(a) * d, target.Z + math.sin(a) * d)
		if p and p.Y > SEA + 0.5 and spawnNodeAt(pool[math.random(#pool)], p, C.OreLifetime) then
			spawned += 1
		end
	end
	if spawned == 0 then
		warn("[IslandEvents] Minérios do meteoro não nasceram: aplique o patch do ResourceService (SpawnAtMarker).")
	end
	announce("⛏️ Minérios!", "O meteoro deixou minérios na cratera.", Color3.fromRGB(255, 200, 80))
	task.wait(4)
end

local function meteorShower()
	local sc = scale()
	local C = EC.MeteorShower
	local count = math.floor(C.Count * sc + 0.5)
	announce("☄️ Chuva de meteoros!", ("%d meteoros vão cair por toda a ilha! Fique atento aos círculos vermelhos."):format(count), Color3.fromRGB(255, 110, 60))
	fx("Rumble", { Intensity = 0.2, Duration = 6 })
	task.wait(3)

	local running, impacts = 0, 0
	for _ = 1, count do
		local target
		local players = alivePlayers()
		if #players > 0 and math.random() < C.TargetPlayerChance then
			local entry = players[math.random(#players)]
			local spread = C.TargetSpread
			target = groundBelow(entry.Root.Position + Vector3.new(math.random(-spread, spread), 0, math.random(-spread, spread)))
		end
		target = target or G.RandomLandPoint("Land")
		if target then
			running += 1
			task.spawn(function()
				meteorStrike(target, C, sc)
				impacts += 1
				if impacts % C.OreEvery == 0 then
					local p = G.GroundAt(target.X + math.random(-8, 8), target.Z + math.random(-8, 8))
					if p and p.Y > SEA + 0.5 then
						spawnNodeAt(({ "OreIron", "OreCoal", "OreCopper" })[math.random(3)], p, C.OreLifetime)
					end
				end
				running -= 1
			end)
		end
		task.wait(C.Interval[1] + math.random() * (C.Interval[2] - C.Interval[1]))
	end
	while running > 0 do task.wait(0.5) end
	announce("☄️ Chuva terminou", "Os meteoros deixaram minérios espalhados.", Color3.fromRGB(200, 200, 220))
end

----------------------------------------------------------------------
-- ⛈️ Tempestade
----------------------------------------------------------------------
local function lightningStrike(sc)
	local C = EC.Storm
	local radius = C.StrikeRadius * rangeScale(sc)
	local target
	local players = alivePlayers()
	if #players > 0 and math.random() < C.TargetPlayerChance then
		local entry = players[math.random(#players)]
		local spread = C.TargetSpread
		target = groundBelow(entry.Root.Position + Vector3.new(math.random(-spread, spread), 0, math.random(-spread, spread)))
	end
	target = target or G.RandomLandPoint("Land")
	if not target then return end

	Models.WarningRing(target, radius, C.Warning, Color3.fromRGB(150, 190, 255))
	task.wait(C.Warning)
	Models.Lightning(target)
	fx("Flash", { Color = Color3.fromRGB(230, 235, 255), Duration = 0.4, Position = target, Radius = 500 })
	fx("Thunder", { Position = target })
	fx("Shake", { Intensity = 0.45, Duration = 0.5, Position = target, Radius = 200 })
	damageNear(target, radius, C.StrikeDamage * sc, 30)
end

local function storm()
	local sc = scale()
	local C = EC.Storm
	announce("⛈️ Tempestade", "O céu escureceu! Raios caem em círculos azuis — saia deles. Os poços enchem mais rápido.", Color3.fromRGB(140, 170, 220))
	run(function()
		Workspace:SetAttribute("StormActive", true)
		Workspace:SetAttribute("WellRefillMultiplier", C.WellRefillMultiplier)
		Workspace:SetAttribute("WorldSpeedMultiplier", C.SpeedMultiplier)
		weather("Storm", true, 1)

		local elapsed = 0
		local nextStrike = (C.StrikeMin + math.random() * (C.StrikeMax - C.StrikeMin)) / sc
		while elapsed < C.Duration do
			local dt = task.wait(0.25)
			elapsed += dt
			nextStrike -= dt
			if nextStrike <= 0 then
				nextStrike = (C.StrikeMin + math.random() * (C.StrikeMax - C.StrikeMin)) / sc
				task.spawn(lightningStrike, sc)
			end
		end
	end, function()
		weather("Storm", false)
		Workspace:SetAttribute("StormActive", nil)
		Workspace:SetAttribute("WellRefillMultiplier", nil)
		Workspace:SetAttribute("WorldSpeedMultiplier", nil)
	end)
	announce("🌤️ Tempestade acabou", "O céu está limpando.", Color3.fromRGB(180, 220, 255))
end

----------------------------------------------------------------------
-- 🌸 Floração
----------------------------------------------------------------------
local FRUIT = { Tree = true, AppleTree = true, BananaTree = true, BerryBush = true }

local function forEachIslandNode(callback)
	local map = Workspace:FindFirstChild(MapConfig.Folders.Map)
	local spawns = map and map:FindFirstChild(MapConfig.Folders.ResourceSpawns)
	local folder = spawns and spawns:FindFirstChild("CentralIsland")
	if not folder then return end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") then
			local base = model.Name:match("^Isl_(%a+)")
			if base then callback(model, base) end
		end
	end
end

local function fruitBloom()
	local C = EC.FruitBloom
	announce("🌸 Floração!", ("Frutas rendem x%d por %d segundos. Colha agora!"):format(C.Multiplier, C.Duration), Color3.fromRGB(255, 160, 200))
	local emitters = {}
	run(function()
		Workspace:SetAttribute("FruitYieldMultiplier", C.Multiplier)
		weather("Bloom", true, 1)
		forEachIslandNode(function(model, base)
			if FRUIT[base] and model.PrimaryPart then
				local pe = Instance.new("ParticleEmitter")
				pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				pe.Rate = 6
				pe.Lifetime = NumberRange.new(3, 4)
				pe.Speed = NumberRange.new(2, 4)
				pe.Size = NumberSequence.new(0.35)
				pe.LightEmission = 0.7
				pe.Color = ColorSequence.new(Color3.fromRGB(255, 180, 215))
				pe.Acceleration = Vector3.new(0, 1.5, 0)
				pe.EmissionDirection = Enum.NormalId.Top
				pe.Parent = model.PrimaryPart
				table.insert(emitters, pe)
			end
		end)
		waitSeconds(C.Duration)
	end, function()
		for _, pe in emitters do pe:Destroy() end
		weather("Bloom", false)
		Workspace:SetAttribute("FruitYieldMultiplier", nil)
	end)
	announce("🍂 Floração acabou", "As frutas voltaram ao normal.", Color3.fromRGB(200, 170, 120))
end

----------------------------------------------------------------------
-- ☀️ Seca / onda de calor
----------------------------------------------------------------------
local function drought()
	local sc = scale()
	local C = EC.Drought
	local duration = C.Duration * (0.85 + 0.2 * sc)
	announce("☀️ Onda de calor!", ("Os poços secaram por %d segundos e a sede aumenta muito. Guarde água!"):format(duration), Color3.fromRGB(255, 190, 70))
	run(function()
		Workspace:SetAttribute("ThirstMultiplier", C.ThirstMultiplier * (0.9 + 0.15 * sc))
		Workspace:SetAttribute("HeatActive", true)
		weather("Heat", true, 1)
		for _, w in G.Wells do
			w:SetAttribute("Dry", true)
			w:SetAttribute("Water", 0)
		end
		waitSeconds(duration)
	end, function()
		weather("Heat", false)
		Workspace:SetAttribute("ThirstMultiplier", nil)
		Workspace:SetAttribute("HeatActive", nil)
		for _, w in G.Wells do w:SetAttribute("Dry", false) end
	end)
	announce("💧 Calor acabou", "Os poços voltaram a encher aos poucos.", Color3.fromRGB(120, 190, 255))
end

----------------------------------------------------------------------
-- 🌫️ Névoa densa
----------------------------------------------------------------------
local function thickFog()
	local C = EC.ThickFog
	announce("🌫️ Névoa densa", "Uma névoa cobriu a ilha. Dá para ver muito pouco.", Color3.fromRGB(200, 210, 225))
	run(function()
		weather("Fog", true, 1)
		Workspace:SetAttribute("FogActive", true)
		waitSeconds(C.Duration)
	end, function()
		weather("Fog", false)
		Workspace:SetAttribute("FogActive", nil)
	end)
	announce("🌤️ Névoa passou", "A visibilidade voltou.", Color3.fromRGB(180, 220, 255))
end

----------------------------------------------------------------------
-- 🌋 Erupção do vulcão
----------------------------------------------------------------------
local function lavaBomb(sc)
	local C = EC.Volcano
	local V = G.Volcano
	local angle = math.random() * math.pi * 2
	local distance = V.CraterRadius * 1.5 + math.random() * (V.Radius * C.BombRange * (0.8 + 0.2 * sc) - V.CraterRadius * 1.5)
	local target = G.GroundAt(V.Center.X + math.cos(angle) * distance, V.Center.Z + math.sin(angle) * distance)
	if not target or target.Y <= SEA + 0.3 then return end

	local radius = C.BombRadius * rangeScale(sc)
	Models.WarningRing(target, radius, C.BombFlight, Color3.fromRGB(255, 120, 30))
	local bomb, place = Models.LavaBomb(math.random(40, 70) / 10)
	bomb.Parent = Models.Container()
	local from = V.Vent.Position
	local peak = 110 + distance * 0.35
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / C.BombFlight
		if a >= 1 then break end
		local p = from:Lerp(target, a) + Vector3.new(0, 4 * peak * a * (1 - a), 0)
		place(CFrame.new(p) * CFrame.Angles(a * 9, a * 6, 0))
		RunService.Heartbeat:Wait()
	end
	bomb:Destroy()

	Models.Impact(target, radius)
	damageNear(target, radius, C.BombDamage * sc, C.BombKnock)
	fx("Shake", { Intensity = 0.7, Duration = 1.1, Position = target, Radius = radius * 9 })
	fx("Sfx", { Name = "LavaBomb", Position = target })
	local pool = Models.LavaBlob(target, radius * 1.3)
	addHazard(target, radius * 0.65, C.PoolDps * sc, C.PoolTime)
	task.delay(C.PoolTime, function() Models.CoolLava(pool, 5) end)
end

-- rio de lava que desce a encosta (pelo ponto mais baixo ao redor) e esfria depois
local function lavaFlow(sc, tracker)
	local C = EC.Volcano
	local V = G.Volcano
	local heading = math.random() * math.pi * 2
	local position = V.Center
	local start = G.GroundAt(V.Center.X + math.cos(heading) * V.CraterRadius * 1.1, V.Center.Z + math.sin(heading) * V.CraterRadius * 1.1)
	if not start then return end
	position = start
	local segments = math.floor(C.FlowSegments * (0.8 + 0.25 * sc))
	local blobs = {}
	for _ = 1, segments do
		local best, bestScore, bestAngle
		for k = -3, 3 do
			local a = heading + k * 0.28
			local candidate = G.GroundAt(position.X + math.cos(a) * C.FlowStep, position.Z + math.sin(a) * C.FlowStep)
			if candidate and candidate.Y > SEA + 0.8 then
				local score = candidate.Y + math.abs(k) * 0.15
				if not bestScore or score < bestScore then
					best, bestScore, bestAngle = candidate, score, a
				end
			end
		end
		if not best then break end
		heading, position = bestAngle, best
		local size = 9 + math.random() * 5
		local blob = Models.LavaBlob(best, size)
		table.insert(blobs, blob)
		addHazard(best, size * 0.55, C.LavaDps * sc, C.FlowLife)
		task.wait(C.FlowStepTime)
	end
	table.insert(tracker, position)
	task.delay(C.FlowLife, function()
		for _, blob in blobs do Models.CoolLava(blob, 8) end
	end)
end

local function volcanoEruption()
	local V = G.Volcano
	if not V then return end
	local sc = scale()
	local C = EC.Volcano

	announce("🌋 Tremores!", "O vulcão está acordando... Afaste-se dele agora!", Color3.fromRGB(255, 150, 60))
	local endpoints = {}
	run(function()
		G.SetVolcanoState("Warning")
		fx("Rumble", { Intensity = 0.3, Duration = C.WarningTime })
		fx("Sfx", { Name = "VolcanoRoar" })
		waitSeconds(C.WarningTime * 0.6)
		announce("🌋 Erupção iminente!", "A fumaça está engrossando. Corram!", Color3.fromRGB(255, 110, 40))
		waitSeconds(C.WarningTime * 0.4)

		announce("🌋 ERUPÇÃO!", "Bombas de lava e rios de lava descendo a montanha! Fuja do vulcão!", Color3.fromRGB(255, 70, 40))
		G.SetVolcanoState("Erupting")
		fx("Shake", { Intensity = 1, Duration = 4 })
		fx("Flash", { Color = Color3.fromRGB(255, 150, 60), Duration = 0.9 })
		fx("Sfx", { Name = "Explosion", Position = V.Center })
		Models.Shockwave(V.Center - Vector3.new(0, 0, 0), V.Radius * 1.1, 2.6, Color3.fromRGB(255, 160, 70))
		damageNear(V.Center, V.CraterRadius * 3, C.ShockDamage * sc, 90)

		Workspace:SetAttribute("AshActive", true)
		Workspace:SetAttribute("WorldStaminaRegenMultiplier", C.AshStaminaRegen)
		Workspace:SetAttribute("WorldSpeedMultiplier", C.AshSpeed)
		weather("Ash", true, 1)

		local flows = math.min(C.MaxFlows, math.floor(C.Flows * sc + 0.5))
		for _ = 1, flows do
			task.spawn(lavaFlow, sc, endpoints)
			task.wait(1.2)
		end

		local endsAt = os.clock() + C.EruptionTime
		while os.clock() < endsAt do
			local bombs = math.floor(C.BombsPerVolley * sc + 0.5)
			for _ = 1, bombs do
				task.spawn(lavaBomb, sc)
				task.wait(0.15 + math.random() * 0.35)
			end
			fx("Shake", { Intensity = 0.25, Duration = 1.5 })
			task.wait(C.VolleyInterval)
		end
	end, function()
		G.SetVolcanoState("Warning")
		task.delay(6, function() G.SetVolcanoState("Dormant") end)
		weather("Ash", false)
		Workspace:SetAttribute("AshActive", nil)
		Workspace:SetAttribute("WorldStaminaRegenMultiplier", nil)
		Workspace:SetAttribute("WorldSpeedMultiplier", nil)
	end)

	-- recompensa: a lava esfriou e expôs minerais raros
	task.wait(C.FlowLife * 0.5)
	local keys = { "ObsidianRock", "SulfurVent", "OreCrystal", "ObsidianRock" }
	local placed = 0
	for _, position in endpoints do
		for _ = 1, 3 do
			local a = math.random() * math.pi * 2
			local p = G.GroundAt(position.X + math.cos(a) * math.random(8, 24), position.Z + math.sin(a) * math.random(8, 24))
			if p and p.Y > SEA + 0.8 and placed < C.RewardNodes and spawnNodeAt(keys[math.random(#keys)], p, C.RewardLifetime) then
				placed += 1
			end
		end
	end
	announce("🌋 Erupção terminou", "A lava está esfriando. Obsidiana e cristais ficaram expostos.", Color3.fromRGB(255, 190, 120))
end

----------------------------------------------------------------------
-- 🌍 Terremoto
----------------------------------------------------------------------
local function rockslide(sc)
	local C = EC.Earthquake
	local point, normal = G.RandomLandPoint("Hills")
	if not point then point, normal = G.RandomLandPoint("Mountain") end
	if not point then return end
	local downhill = Vector3.new(normal.X, 0, normal.Z)
	downhill = downhill.Magnitude > 0.05 and downhill.Unit or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit

	Models.DustBurst(point, 35, 10)
	task.wait(1.2)
	for _ = 1, math.floor(C.BouldersPerSlide * (0.8 + 0.2 * sc)) do
		local size = 4 + math.random() * 5
		local boulder = Models.Boulder(size)
		boulder.CFrame = CFrame.new(point + Vector3.new(math.random(-6, 6), size + 6, math.random(-6, 6)))
		boulder.Parent = Models.Container()
		boulder.AssemblyLinearVelocity = downhill * (18 + math.random() * 14)
		local debounce = {}
		boulder.Touched:Connect(function(hit)
			local char = hit.Parent
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local plr = hum and Players:GetPlayerFromCharacter(char)
			if plr and not debounce[plr] and boulder.AssemblyLinearVelocity.Magnitude > 8 then
				debounce[plr] = true
				hum:TakeDamage(C.BoulderDamage * sc)
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then
					knockback({ Player = plr }, boulder.AssemblyLinearVelocity.Unit * 40 + Vector3.new(0, 25, 0))
				end
				task.delay(1.5, function() debounce[plr] = nil end)
			end
		end)
		Debris:AddItem(boulder, C.BoulderLifetime)
		task.wait(0.3 + math.random() * 0.4)
	end
end

local function earthquake()
	local sc = scale()
	local C = EC.Earthquake
	announce("🌍 Terremoto!", "O chão está tremendo! Cuidado com pedras rolando pelas encostas.", Color3.fromRGB(190, 150, 100))
	run(function()
		fx("Shake", { Intensity = 0.9, Duration = C.Duration })
		fx("Rumble", { Intensity = 0.6, Duration = C.Duration })
		fx("Sfx", { Name = "Quake" })
		for _, w in G.Wells do
			w:SetAttribute("Water", math.floor((w:GetAttribute("Water") or 0) * (1 - C.WellWaterLoss)))
		end
		for _ = 1, math.floor(C.Rockslides * sc + 0.5) do
			task.spawn(rockslide, sc)
			task.wait(0.8)
		end
		waitSeconds(C.Duration)
	end, function() end)

	-- o terremoto expõe minerais
	local keys = { "OreCopper", "OreCrystal", "OreIron", "Rock" }
	for _ = 1, C.RewardNodes do
		local p = G.RandomLandPoint("Hills") or G.RandomLandPoint("Mountain")
		if p then spawnNodeAt(keys[math.random(#keys)], p, C.RewardLifetime) end
	end
	task.wait(6)
	announce("🌍 Tremores pararam", "Algumas rochas se abriram e expuseram minerais nas colinas.", Color3.fromRGB(210, 180, 140))
end

----------------------------------------------------------------------
-- 🌊 Onda gigante
----------------------------------------------------------------------
local function compass(direction)
	if math.abs(direction.Z) > math.abs(direction.X) then
		return direction.Z < 0 and "Norte" or "Sul"
	end
	return direction.X > 0 and "Leste" or "Oeste"
end

local function tidalWave()
	local sc = scale()
	local C = EC.TidalWave
	local center = MapConfig.MainIsland.Position
	local angle = math.random() * math.pi * 2
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local travel = -outward
	local right = travel:Cross(Vector3.yAxis).Unit

	announce("🌊 Onda gigante!", ("Uma onda enorme vem do %s! Suba para terreno alto, longe da praia."):format(compass(outward)), Color3.fromRGB(90, 170, 255))
	fx("Rumble", { Intensity = 0.2, Duration = C.Warning })
	for _ = 1, math.floor(C.Warning / 5) do
		fx("Sfx", { Name = "Alarm" })
		waitSeconds(5)
	end

	local height = C.Height * (0.9 + 0.15 * sc)
	local startDistance = GenCfg.Map.Radius * 1.6 + 250
	local position = Vector3.new(center.X, 0, center.Z) + outward * startDistance
	local wave, body = Models.TidalWave(C.Width, height, C.Depth)
	wave.Parent = Models.Container()
	local hit = {}
	local traveled = 0
	local shoreTimer = 0
	local top = SEA + height

	while traveled < startDistance + GenCfg.Map.Radius do
		local dt = RunService.Heartbeat:Wait()
		local step = C.Speed * dt
		position += travel * step
		traveled += step
		local cf = CFrame.lookAt(Vector3.new(position.X, SEA + height / 2 - 1.5, position.Z), Vector3.new(position.X, SEA + height / 2 - 1.5, position.Z) + travel)
		Models.PlaceWave(wave, cf)

		for _, entry in alivePlayers() do
			if not hit[entry.Player] then
				local rel = entry.Root.Position - position
				local along, across = rel:Dot(travel), math.abs(rel:Dot(right))
				if across < C.Width / 2 and math.abs(along) < C.Depth / 2 + 3 and entry.Root.Position.Y < top then
					hit[entry.Player] = true
					entry.Humanoid:TakeDamage(C.Damage * sc)
					knockback(entry, travel * C.Push + Vector3.new(0, C.Lift, 0))
					fx("Shake", { Intensity = 0.8, Duration = 1.2, Position = entry.Root.Position, Radius = 60 })
				end
			end
		end

		shoreTimer += dt
		if shoreTimer > 0.15 then
			shoreTimer = 0
			local front = position + travel * (C.Depth / 2)
			local ground = G.GroundAt(front.X, front.Z)
			if ground and ground.Y > SEA + 3.5 then
				break
			end
		end
	end

	for _, d in wave:GetDescendants() do
		if d:IsA("BasePart") then Models.Tween(d, 1.4, { Transparency = 1 }) end
	end
	Debris:AddItem(wave, 1.6)
	Models.Shockwave(Vector3.new(position.X, SEA + 1, position.Z), 60, 1.2, Color3.fromRGB(225, 240, 250))
	pcall(function() require(script.Parent:WaitForChild("WaterService")).OceanEvent:Fire("TidalWave", position, travel) end)
	announce("🌊 Onda passou", "A água recuou. Cuidado com o mar agitado.", Color3.fromRGB(150, 200, 240))
end

----------------------------------------------------------------------
-- Sorteio e agendamento
----------------------------------------------------------------------
Events.List = {
	{ Id = "SupplyDrop", Run = supplyDrop },
	{ Id = "Meteor", Run = meteor },
	{ Id = "MeteorShower", Run = meteorShower },
	{ Id = "Storm", Run = storm },
	{ Id = "FruitBloom", Run = fruitBloom },
	{ Id = "Drought", Run = drought },
	{ Id = "VolcanoEruption", Run = volcanoEruption },
	{ Id = "Earthquake", Run = earthquake },
	{ Id = "TidalWave", Run = tidalWave },
	{ Id = "ThickFog", Run = thickFog },
}

local function pick(last)
	local day = Lighting:GetAttribute("DayNumber") or 1
	local pool, total = {}, 0
	for _, ev in Events.List do
		local minDay = EC.MinDay[ev.Id] or 1
		if ev.Id ~= last and day >= minDay and not (ev.Id == "VolcanoEruption" and not (G and G.Volcano)) then
			local w = EC.Weights[ev.Id] or 1
			total += w
			table.insert(pool, { ev, w })
		end
	end
	if #pool == 0 then return Events.List[1] end
	local roll = math.random() * total
	for _, p in pool do
		roll -= p[2]
		if roll <= 0 then return p[1] end
	end
	return pool[1][1]
end

local function execute(ev)
	Workspace:SetAttribute("CurrentEvent", ev.Id)
	local ok, err = pcall(ev.Run)
	if not ok then warn("[IslandEvents] erro em " .. ev.Id .. ": " .. tostring(err)) end
	Workspace:SetAttribute("CurrentEvent", "")
end

-- Para testar: require(...IslandEvents).Trigger("VolcanoEruption")
function Events.Trigger(id)
	for _, ev in Events.List do
		if ev.Id == id then
			task.spawn(execute, ev)
			return true
		end
	end
	return false
end

function Events.Init()
end

function Events.Start()
	if Events._started then return end
	Events._started = true

	G = require(script.Parent:WaitForChild("IslandGenerator"))

	local inventoryModule = script.Parent:FindFirstChild("InventoryService")
	if not Events.Hooks.GiveItem and inventoryModule then
		local Inventory = require(inventoryModule)
		Events.Hooks.GiveItem = function(player, item, amount)
			return Inventory.AddItem(player, item, amount, "SupplyCrate")
		end
	end

	-- limpa qualquer efeito que tenha sobrado e atualiza quem entra no meio de um evento
	fxRemote:FireAllClients("ResetWeather")
	for _, name in { "StormActive", "WellRefillMultiplier", "ThirstMultiplier", "FruitYieldMultiplier", "WorldSpeedMultiplier", "WorldStaminaRegenMultiplier", "AshActive", "HeatActive", "FogActive" } do
		Workspace:SetAttribute(name, nil)
	end
	Players.PlayerAdded:Connect(function(player)
		task.wait(4)
		if player.Parent then
			fxRemote:FireClient(player, "WeatherState", activeWeather)
		end
	end)

	task.spawn(hazardLoop)

	task.spawn(function()
		local delay, last = EC.FirstDelay, nil
		while true do
			Workspace:SetAttribute("NextEventTime", os.time() + delay)
			task.wait(delay)
			while #Players:GetPlayers() == 0 or not G.Ready do task.wait(5) end
			local ev = pick(last)
			last = ev.Id
			execute(ev)
			local D = EC.Difficulty
			local shrink = 1 + D.IntervalShrink * (scale() - 1)
			delay = (EC.IntervalMin + math.random() * (EC.IntervalMax - EC.IntervalMin)) / shrink
		end
	end)
end

return Events

