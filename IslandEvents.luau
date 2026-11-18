--[[
	IslandEvents
	Local: ServerScriptService > Services > IslandEvents   (ModuleScript, serviço com Init/Start)
	Coloque por ÚLTIMO em GameConfig.ServiceLoadOrder (depois de ResourceService e InventoryService).

	A cada alguns minutos sorteia um evento:
	  SupplyDrop  - caixa de suprimentos cai do céu com fumaça vermelha
	  Meteor      - meteoro cai (dá dano na área) e deixa minérios
	  Storm       - tempestade com chuva e raios
	  FruitBloom  - frutas rendem em dobro por um tempo
	  Drought     - seca: poços secam e a sede aumenta

	Atributos no Workspace para seus outros sistemas lerem:
	  NextEventTime, CurrentEvent, FruitYieldMultiplier, ThirstMultiplier,
	  WellRefillMultiplier, StormActive
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("IslandGenConfig"))
local EC = Cfg.Events
local MapC = Cfg.Map

local Events = {}
Events.Hooks = { GiveItem = nil } -- function(player, itemName, amount)

local Remote = ReplicatedStorage:FindFirstChild("IslandAnnouncement")
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "IslandAnnouncement"
	Remote.Parent = ReplicatedStorage
end

local function announce(title, text, color)
	Remote:FireAllClients(title, text, color or Color3.fromRGB(255, 200, 80))
end

local function giveItem(player, item, amount)
	if Events.Hooks.GiveItem then
		local ok, err = pcall(Events.Hooks.GiveItem, player, item, amount)
		if not ok then warn("[IslandEvents] GiveItem falhou:", err) end
	else
		warn("[IslandEvents] Hooks.GiveItem não configurado (item " .. item .. " x" .. amount .. ")")
	end
end

local function newPart(size, color, material, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	return p
end

local function damageNear(pos, radius, amount)
	for _, plr in Players:GetPlayers() do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and (hrp.Position - pos).Magnitude <= radius then
			hum:TakeDamage(amount)
		end
	end
end

----------------------------------------------------------------------
-- 1) Caixa de suprimentos
----------------------------------------------------------------------
local function supplyDrop(G)
	local C = EC.SupplyDrop
	local pos = G.RandomLandPoint("Lowland")
	if not pos then return end
	announce("📦 Caixa de Suprimentos", "Uma caixa caiu do céu! Siga a fumaça vermelha.", Color3.fromRGB(255, 120, 90))

	local model = Instance.new("Model")
	model.Name = "SupplyCrate"
	local body = newPart(Vector3.new(4, 3, 4), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	body.CanCollide = true
	body.Name = "Body"
	body.Parent = model
	model.PrimaryPart = body
	local bands = {}
	for i, z in { 1.6, -1.6 } do
		local band = newPart(Vector3.new(4.1, 3.1, 0.4), Color3.fromRGB(160, 160, 170), Enum.Material.Metal)
		band.Name = "Band" .. i
		band.Parent = model
		bands[band] = z
	end
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	local canopy = newPart(Vector3.new(11, 11, 11), Color3.fromRGB(255, 140, 60), Enum.Material.Fabric, Enum.PartType.Ball)
	canopy.Parent = chute
	chute.Parent = model

	local startCF = CFrame.new(pos + Vector3.new(0, 160, 0))
	local endCF = CFrame.new(pos + Vector3.new(0, 1.6, 0))
	local function place(cf)
		body.CFrame = cf
		for band, z in bands do
			band.CFrame = cf * CFrame.new(0, 0, z)
		end
		if canopy.Parent then canopy.CFrame = cf * CFrame.new(0, 9, 0) end
	end
	model.Parent = Workspace
	place(startCF)

	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / C.FallTime
		if a >= 1 then break end
		place(startCF:Lerp(endCF, a))
		RunService.Heartbeat:Wait()
	end
	place(endCF)
	chute:Destroy()

	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(255, 60, 40))
	smoke.Rate = 18
	smoke.Lifetime = NumberRange.new(5, 7)
	smoke.Speed = NumberRange.new(6, 9)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = body

	local beacon = newPart(Vector3.new(0.8, 90, 0.8), Color3.fromRGB(255, 70, 50), Enum.Material.Neon)
	beacon.Transparency = 0.55
	beacon.Position = pos + Vector3.new(0, 45, 0)
	beacon.Parent = model

	local opened = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir caixa"
	prompt.ObjectText = "Suprimentos"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		if opened then return end
		opened = true
		for _, l in C.Loot do
			if not l.Chance or math.random() <= l.Chance then
				giveItem(player, l.Item, math.random(l.Min, l.Max))
			end
		end
		announce("📦 Caixa aberta", player.Name .. " pegou os suprimentos!", Color3.fromRGB(120, 220, 120))
		model:Destroy()
	end)

	local t = 0
	while not opened and t < C.Lifetime do
		task.wait(1)
		t += 1
	end
	if model.Parent then model:Destroy() end
end

----------------------------------------------------------------------
-- 2) Meteoro
----------------------------------------------------------------------
local function meteor(G)
	local C = EC.Meteor
	local pos = G.RandomLandPoint("Hills") or G.RandomLandPoint("Lowland")
	if not pos then return end
	announce("☄️ Meteoro!", ("Um meteoro vai cair em %d segundos! Saia da área vermelha."):format(C.Warning), Color3.fromRGB(255, 90, 60))

	local marker = newPart(Vector3.new(0.3, C.DamageRadius * 2, C.DamageRadius * 2), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, Enum.PartType.Cylinder)
	marker.Transparency = 0.5
	marker.CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = Workspace
	for i = 1, C.Warning * 2 do
		marker.Transparency = (i % 2 == 0) and 0.3 or 0.75
		task.wait(0.5)
	end
	marker:Destroy()

	local rock = newPart(Vector3.new(9, 9, 9), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, Enum.PartType.Ball)
	local fire = Instance.new("Fire")
	fire.Size = 20
	fire.Parent = rock
	rock.Parent = Workspace
	local from = pos + Vector3.new(90, 260, 40)
	local to = pos + Vector3.new(0, 4, 0)
	local t0 = os.clock()
	while true do
		local a = (os.clock() - t0) / C.FallTime
		if a >= 1 then break end
		rock.Position = from:Lerp(to, a * a)
		RunService.Heartbeat:Wait()
	end
	rock:Destroy()

	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastRadius = C.DamageRadius
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Parent = Workspace
	damageNear(pos, C.DamageRadius, C.Damage)

	local crater = newPart(Vector3.new(0.4, 22, 22), Color3.fromRGB(40, 34, 32), Enum.Material.Basalt, Enum.PartType.Cylinder)
	crater.CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	crater.Parent = Workspace
	Debris:AddItem(crater, 300)

	local pool = { "OreIron", "OreIron", "OreCoal", "OreCopper", "OreGold", "OreCrystal", "Rock" }
	local spawned = 0
	for i = 1, C.OreCount do
		local a = (i / C.OreCount) * math.pi * 2
		local d = math.random(9, 16)
		local p = G.GroundAt(pos.X + math.cos(a) * d, pos.Z + math.sin(a) * d)
		if p then
			local model, marker = G.SpawnRuntimeNode(pool[math.random(#pool)], p)
			if model then
				spawned += 1
				model:SetAttribute("Temporary", true)
				task.delay(C.OreLifetime or 600, function()
					G.RemoveRuntimeNode(model, marker)
				end)
			end
		end
	end
	if spawned == 0 then
		warn("[IslandEvents] Minérios do meteoro não nasceram: aplique o patch do ResourceService (SpawnAtMarker). Veja PATCHES.md.")
	end
	announce("⛏️ Minérios!", "O meteoro deixou minérios na cratera. Corra para pegar!", Color3.fromRGB(255, 200, 80))
	task.wait(5)
end

----------------------------------------------------------------------
-- 3) Tempestade
----------------------------------------------------------------------
local function storm(G)
	local C = EC.Storm
	announce("⛈️ Tempestade", "Uma tempestade chegou! Cuidado com os raios. Os poços enchem mais rápido.", Color3.fromRGB(140, 160, 200))
	Workspace:SetAttribute("StormActive", true)
	Workspace:SetAttribute("WellRefillMultiplier", 3)

	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local created = false
	if not atmo then
		atmo = Instance.new("Atmosphere")
		atmo.Parent = Lighting
		created = true
	end
	local prev = { Density = atmo.Density, Haze = atmo.Haze, Color = atmo.Color }
	TweenService:Create(atmo, TweenInfo.new(6), { Density = 0.55, Haze = 2.5, Color = Color3.fromRGB(95, 100, 110) }):Play()

	local rain = newPart(Vector3.new(MapC.Size, 1, MapC.Size), Color3.new(1, 1, 1))
	rain.Transparency = 1
	rain.Position = MapC.Center + Vector3.new(0, 140, 0)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 2500
	pe.Lifetime = NumberRange.new(1.8)
	pe.Speed = NumberRange.new(90, 110)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Orientation = Enum.ParticleOrientation.VelocityParallel
	pe.Size = NumberSequence.new(0.18)
	pe.Transparency = NumberSequence.new(0.5)
	pe.Color = ColorSequence.new(Color3.fromRGB(170, 195, 230))
	pe.LightEmission = 0.3
	pe.Parent = rain
	rain.Parent = Workspace

	local t, nextStrike = 0, math.random(C.StrikeMin, C.StrikeMax)
	while t < C.Duration do
		task.wait(1)
		t += 1
		nextStrike -= 1
		if nextStrike <= 0 then
			nextStrike = math.random(C.StrikeMin, C.StrikeMax)
			local players = Players:GetPlayers()
			local plr = players[math.random(#players)]
			local hrp = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local x = hrp.Position.X + math.random(-45, 45)
				local z = hrp.Position.Z + math.random(-45, 45)
				local p = G.GroundAt(x, z) or hrp.Position
				local bolt = newPart(Vector3.new(0.7, 200, 0.7), Color3.fromRGB(230, 235, 255), Enum.Material.Neon)
				bolt.Position = p + Vector3.new(0, 100, 0)
				bolt.Parent = Workspace
				Debris:AddItem(bolt, 0.15)
				damageNear(p, 8, C.StrikeDamage)
			end
		end
	end

	rain:Destroy()
	TweenService:Create(atmo, TweenInfo.new(6), prev):Play()
	task.wait(6)
	if created then atmo:Destroy() end
	Workspace:SetAttribute("StormActive", nil)
	Workspace:SetAttribute("WellRefillMultiplier", nil)
	announce("🌤️ Tempestade acabou", "O céu está limpando.", Color3.fromRGB(180, 220, 255))
end

----------------------------------------------------------------------
-- 4) Floração de frutas
----------------------------------------------------------------------
local FRUIT = { Tree = true, AppleTree = true, BananaTree = true, BerryBush = true }

local function fruitBloom(G)
	local C = EC.FruitBloom
	announce("🌸 Floração!", ("Frutas rendem x%d por %d segundos. Colha agora!"):format(C.Multiplier, C.Duration), Color3.fromRGB(255, 160, 200))
	Workspace:SetAttribute("FruitYieldMultiplier", C.Multiplier)

	local emitters = {}
	for _, m in CollectionService:GetTagged("ResourceNode") do
		if FRUIT[m:GetAttribute("NodeType")] and m.PrimaryPart then
			m:SetAttribute("Bloom", true)
			local pe = Instance.new("ParticleEmitter")
			pe.Rate = 5
			pe.Lifetime = NumberRange.new(3, 4)
			pe.Speed = NumberRange.new(2, 4)
			pe.Size = NumberSequence.new(0.3)
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 180, 210))
			pe.Acceleration = Vector3.new(0, 1, 0)
			pe.EmissionDirection = Enum.NormalId.Top
			pe.Parent = m.PrimaryPart
			table.insert(emitters, { m, pe })
		end
	end

	task.wait(C.Duration)

	for _, e in emitters do
		e[2]:Destroy()
		if e[1].Parent then e[1]:SetAttribute("Bloom", nil) end
	end
	Workspace:SetAttribute("FruitYieldMultiplier", nil)
	announce("🍂 Floração acabou", "As frutas voltaram ao normal.", Color3.fromRGB(200, 170, 120))
end

----------------------------------------------------------------------
-- 5) Seca
----------------------------------------------------------------------
local function drought(G)
	local C = EC.Drought
	announce("☀️ Seca!", ("Os poços secaram por %d segundos e a sede aumenta. Guarde água!"):format(C.Duration), Color3.fromRGB(255, 190, 70))
	Workspace:SetAttribute("ThirstMultiplier", 2)
	for _, w in G.Wells do
		w:SetAttribute("Dry", true)
		w:SetAttribute("Water", 0)
	end

	task.wait(C.Duration)

	for _, w in G.Wells do w:SetAttribute("Dry", false) end
	Workspace:SetAttribute("ThirstMultiplier", nil)
	announce("💧 Seca acabou", "Os poços voltaram a encher aos poucos.", Color3.fromRGB(120, 190, 255))
end

----------------------------------------------------------------------
-- Sorteio e loop
----------------------------------------------------------------------
Events.List = {
	{ Id = "SupplyDrop", Run = supplyDrop },
	{ Id = "Meteor", Run = meteor },
	{ Id = "Storm", Run = storm },
	{ Id = "FruitBloom", Run = fruitBloom },
	{ Id = "Drought", Run = drought },
}

local function pick(last)
	local pool, total = {}, 0
	for _, ev in Events.List do
		if ev.Id ~= last then
			local w = EC.Weights[ev.Id] or 1
			total += w
			table.insert(pool, { ev, w })
		end
	end
	local roll = math.random() * total
	for _, p in pool do
		roll -= p[2]
		if roll <= 0 then return p[1] end
	end
	return pool[1][1]
end

-- Para testar: Events.Trigger("Meteor")
function Events.Trigger(id)
	for _, ev in Events.List do
		if ev.Id == id then
			task.spawn(function()
				local ok, err = pcall(ev.Run, Events._G)
				if not ok then warn("[IslandEvents] erro em " .. id .. ":", err) end
			end)
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

	local Generator = require(script.Parent:WaitForChild("IslandGenerator"))
	Events._G = Generator

	-- entrega de itens: usa a mochila real do jogo
	local Inventory = script.Parent:FindFirstChild("InventoryService") and require(script.Parent.InventoryService)
	if not Events.Hooks.GiveItem and Inventory then
		Events.Hooks.GiveItem = function(player, item, amount)
			return Inventory.AddItem(player, item, amount, "SupplyCrate")
		end
	end

	task.spawn(function()
		local delay, last = EC.FirstDelay, nil
		while true do
			Workspace:SetAttribute("NextEventTime", os.time() + delay)
			task.wait(delay)
			-- sem jogadores não faz sentido sortear evento
			while #Players:GetPlayers() == 0 or not Generator.Ready do task.wait(5) end
			local ev = pick(last)
			last = ev.Id
			Workspace:SetAttribute("CurrentEvent", ev.Id)
			local ok, err = pcall(ev.Run, Generator)
			if not ok then warn("[IslandEvents] erro em " .. ev.Id .. ":", err) end
			Workspace:SetAttribute("CurrentEvent", "")
			delay = math.random(EC.IntervalMin, EC.IntervalMax)
		end
	end)
end

return Events
