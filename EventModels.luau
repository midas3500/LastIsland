--[[
	EventModels
	Local: ServerScriptService > Services > EventModels   (ModuleScript, só precisa existir)

	Modelos e animações dos eventos: caixa com paraquedas, meteoro com rastro, impacto com
	cratera, raio com ramificações, bolha de lava, pedregulho, onda gigante, anel de aviso.
	Tudo é montado por código (sem assets externos).
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local Models = {}

local MAT = Enum.Material
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local UP = Vector3.new(0, 1, 0)

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do p[k] = v end
	return p
end
Models.Part = part

local function tween(inst, seconds, props, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end
Models.Tween = tween

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do e[k] = v end
	e.Parent = parent
	return e
end

local function container()
	local f = Workspace:FindFirstChild("EventEffects")
	if not f then
		f = Instance.new("Folder")
		f.Name = "EventEffects"
		f.Parent = Workspace
	end
	return f
end
Models.Container = container

local function flatCFrame(position, lift)
	return CFrame.new(position + Vector3.new(0, lift or 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

----------------------------------------------------------------------
-- Anel de aviso no chão (enche por dentro até a hora do impacto)
----------------------------------------------------------------------
function Models.WarningRing(position, radius, duration, color)
	color = color or Color3.fromRGB(255, 60, 40)
	local cf = flatCFrame(position, 0.6)
	local outer = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, radius * 2, radius * 2), CFrame = cf, Material = MAT.Neon, Color = color, Transparency = 0.72 })
	local inner = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.5, 0.5), CFrame = cf, Material = MAT.Neon, Color = Color3.fromRGB(255, 170, 60), Transparency = 0.45 })
	outer.Parent = container()
	inner.Parent = container()
	tween(inner, duration, { Size = Vector3.new(0.3, radius * 1.92, radius * 1.92) }, Enum.EasingStyle.Linear)
	task.spawn(function()
		local t0 = os.clock()
		while outer.Parent and os.clock() - t0 < duration do
			outer.Transparency = 0.6 + 0.18 * math.sin((os.clock() - t0) * 11)
			task.wait()
		end
	end)
	Debris:AddItem(outer, duration + 0.1)
	Debris:AddItem(inner, duration + 0.1)
	return outer
end

----------------------------------------------------------------------
-- Onda de choque (disco que se expande e some)
----------------------------------------------------------------------
function Models.Shockwave(position, maxRadius, seconds, color)
	local ring = part({
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 2, 2), CFrame = flatCFrame(position, 1.5),
		Material = MAT.Neon, Color = color or Color3.fromRGB(255, 200, 120), Transparency = 0.2,
	})
	ring.Parent = container()
	tween(ring, seconds, { Size = Vector3.new(0.8, maxRadius * 2, maxRadius * 2), Transparency = 1 })
	Debris:AddItem(ring, seconds + 0.1)
end

----------------------------------------------------------------------
-- Raio com ramificações e marca de queimado
----------------------------------------------------------------------
local function segment(parent, a, b, width)
	local length = (b - a).Magnitude
	if length < 0.05 then return nil end
	local p = part({
		Size = Vector3.new(width, width, length), CFrame = CFrame.lookAt((a + b) / 2, b),
		Material = MAT.Neon, Color = Color3.fromRGB(225, 235, 255),
	})
	p.Parent = parent
	return p
end

function Models.Lightning(target)
	local folder = Instance.new("Folder")
	folder.Name = "Lightning"
	folder.Parent = container()

	local top = target + Vector3.new(math.random(-30, 30), 260, math.random(-30, 30))
	local steps = 10
	local points = { top }
	for i = 1, steps - 1 do
		local t = i / steps
		local jitter = (1 - t) * 14 + 3
		local p = top:Lerp(target, t) + Vector3.new(math.random(-100, 100) / 100 * jitter, 0, math.random(-100, 100) / 100 * jitter)
		table.insert(points, p)
	end
	table.insert(points, target)

	local parts = {}
	for i = 1, #points - 1 do
		table.insert(parts, segment(folder, points[i], points[i + 1], 1.1 - 0.4 * (i / steps)))
	end
	-- ramificação
	local startIndex = math.random(3, 6)
	local forkPoint = points[startIndex]
	local sideways = Vector3.new(math.random(-100, 100), 0, math.random(-100, 100)).Unit * 22
	local previous = forkPoint
	for i = 1, 4 do
		local nextPoint = previous + sideways / 4 + Vector3.new(math.random(-4, 4), -22, math.random(-4, 4))
		table.insert(parts, segment(folder, previous, nextPoint, 0.5))
		previous = nextPoint
	end

	-- clarão no chão
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(target + Vector3.new(0, 2, 0)), Material = MAT.Neon, Color = Color3.fromRGB(235, 240, 255), Transparency = 0.3 })
	local light = Instance.new("PointLight")
	light.Range = 70
	light.Brightness = 9
	light.Color = Color3.fromRGB(200, 215, 255)
	light.Parent = glow
	glow.Parent = folder
	tween(glow, 0.5, { Transparency = 1, Size = Vector3.new(16, 16, 16) })
	tween(light, 0.5, { Brightness = 0 })
	for _, p in parts do
		if p then tween(p, 0.4, { Transparency = 1 }) end
	end
	Debris:AddItem(folder, 0.7)

	-- marca de queimado que some devagar
	local scorch = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 7, 7), CFrame = flatCFrame(target, 0.25), Material = MAT.Basalt, Color = Color3.fromRGB(25, 22, 22), Transparency = 0.2 })
	scorch.Parent = container()
	tween(scorch, 18, { Transparency = 1 }, Enum.EasingStyle.Linear)
	Debris:AddItem(scorch, 19)
end

----------------------------------------------------------------------
-- Caixa de suprimentos com paraquedas
----------------------------------------------------------------------
function Models.Crate()
	local model = Instance.new("Model")
	model.Name = "SupplyCrate"

	local body = part({ Name = "Body", Size = Vector3.new(4.4, 3.2, 4.4), Material = MAT.WoodPlanks, Color = Color3.fromRGB(139, 98, 58) })
	body.Parent = model
	model.PrimaryPart = body

	local function attach(size, offset, color, material, name)
		local p = part({ Name = name or "Detail", Size = size, Material = material or MAT.Metal, Color = color })
		p:SetAttribute("Offset", offset)
		p.Parent = model
		return p
	end
	local metal = Color3.fromRGB(150, 155, 165)
	local details = {}
	for _, sx in { -2.1, 2.1 } do
		for _, sz in { -2.1, 2.1 } do
			table.insert(details, attach(Vector3.new(0.5, 3.3, 0.5), Vector3.new(sx, 0, sz), metal))
		end
	end
	for _, y in { -0.9, 0.9 } do
		table.insert(details, attach(Vector3.new(4.6, 0.35, 4.6), Vector3.new(0, y, 0), Color3.fromRGB(120, 125, 135)))
	end
	table.insert(details, attach(Vector3.new(4.7, 0.45, 4.7), Vector3.new(0, 1.8, 0), Color3.fromRGB(110, 78, 46), MAT.Wood, "Lid"))
	-- cruz vermelha na frente
	table.insert(details, attach(Vector3.new(1.8, 0.5, 0.15), Vector3.new(0, 0, 2.25), Color3.fromRGB(230, 50, 50), MAT.SmoothPlastic))
	table.insert(details, attach(Vector3.new(0.5, 1.8, 0.15), Vector3.new(0, 0, 2.25), Color3.fromRGB(230, 50, 50), MAT.SmoothPlastic))
	-- luzes piscando no topo
	local blinkers = {}
	for _, sx in { -1.4, 1.4 } do
		local b = attach(Vector3.new(0.7, 0.7, 0.7), Vector3.new(sx, 2.3, 0), Color3.fromRGB(255, 50, 40), MAT.Neon, "Blinker")
		b.Shape = Enum.PartType.Ball
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 70, 50)
		l.Range = 18
		l.Brightness = 2
		l.Parent = b
		table.insert(details, b)
		table.insert(blinkers, { Part = b, Light = l })
	end

	-- paraquedas
	local chute = Instance.new("Model")
	chute.Name = "Chute"
	local canopy = part({ Name = "Canopy", Shape = Enum.PartType.Ball, Size = Vector3.new(15, 8, 15), Material = MAT.Fabric, Color = Color3.fromRGB(255, 140, 60) })
	canopy.Parent = chute
	chute.PrimaryPart = canopy
	local stripeA = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(15.2, 8.2, 3.2), Material = MAT.Fabric, Color = Color3.fromRGB(250, 245, 240) })
	local stripeB = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 8.2, 15.2), Material = MAT.Fabric, Color = Color3.fromRGB(250, 245, 240) })
	stripeA.Parent, stripeB.Parent = chute, chute
	stripeA:SetAttribute("Offset", Vector3.zero)
	stripeB:SetAttribute("Offset", Vector3.zero)
	local ropes = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local top = Vector3.new(sx * 6.2, -3.2, sz * 6.2) -- na borda do paraquedas (relativo ao paraquedas)
			local bottom = Vector3.new(sx * 2.1, -9.6, sz * 2.1) -- no canto da caixa
			local rope = part({ Size = Vector3.new(0.12, 0.12, (top - bottom).Magnitude), Material = MAT.Fabric, Color = Color3.fromRGB(210, 190, 140) })
			rope:SetAttribute("RopeTop", top)
			rope:SetAttribute("RopeBottom", bottom)
			rope.Parent = chute
			table.insert(ropes, rope)
		end
	end
	chute.Parent = model

	-- posiciona tudo conforme o CFrame da caixa (chamado a cada quadro durante a queda)
	local function place(cf, swayX, swayZ)
		body.CFrame = cf
		for _, d in details do
			d.CFrame = cf * CFrame.new(d:GetAttribute("Offset"))
		end
		local chuteCF = cf * CFrame.new(0, 9.6, 0) * CFrame.Angles(swayX or 0, 0, swayZ or 0)
		canopy.CFrame = chuteCF
		stripeA.CFrame = chuteCF
		stripeB.CFrame = chuteCF
		for _, rope in ropes do
			local top = chuteCF:PointToWorldSpace(rope:GetAttribute("RopeTop") + Vector3.new(0, 9.6, 0) - Vector3.new(0, 9.6, 0))
			local bottom = cf:PointToWorldSpace(rope:GetAttribute("RopeBottom") + Vector3.new(0, 9.6, 0))
			rope.CFrame = CFrame.lookAt((top + bottom) / 2, bottom)
			rope.Size = Vector3.new(0.12, 0.12, (top - bottom).Magnitude)
		end
	end

	return model, { Body = body, Chute = chute, Place = place, Blinkers = blinkers, Details = details }
end

-- paraquedas murcha e some
function Models.CollapseChute(chute)
	for _, d in chute:GetDescendants() do
		if d:IsA("BasePart") then
			tween(d, 1.2, { Transparency = 1 })
		end
	end
	local canopy = chute.PrimaryPart
	if canopy then
		tween(canopy, 1.2, { Size = Vector3.new(15, 1, 15), Position = canopy.Position - Vector3.new(0, 6, 0) })
	end
	Debris:AddItem(chute, 1.4)
end

function Models.DustBurst(position, amount, size)
	local holder = part({ Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = CFrame.new(position + Vector3.new(0, 1.5, 0)) })
	holder.Parent = container()
	local e = emitter(holder, {
		Texture = SMOKE, Rate = 0, Lifetime = NumberRange.new(1.6, 3.2), Speed = NumberRange.new(14, 38),
		SpreadAngle = Vector2.new(75, 75), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, (size or 8) * 0.5), NumberSequenceKeypoint.new(1, size or 8) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(150, 135, 118)), Rotation = NumberRange.new(0, 360),
		Drag = 3,
	})
	e:Emit(amount or 50)
	Debris:AddItem(holder, 4)
end

-- marcador de fumaça/luz que fica no ponto onde a caixa caiu
function Models.Flare(position)
	local holder = part({ Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) })
	emitter(holder, {
		Texture = SMOKE, Rate = 16, Lifetime = NumberRange.new(5, 7), Speed = NumberRange.new(8, 12),
		SpreadAngle = Vector2.new(8, 8), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 70, 50)), LightEmission = 0.6,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 80, 60)
	light.Range = 35
	light.Brightness = 3
	light.Parent = holder
	local beacon = part({ Size = Vector3.new(0.9, 120, 0.9), CFrame = CFrame.new(position + Vector3.new(0, 60, 0)), Material = MAT.Neon, Color = Color3.fromRGB(255, 70, 50), Transparency = 0.55 })
	holder.Parent = container()
	beacon.Parent = container()
	task.spawn(function()
		while beacon.Parent do
			beacon.Transparency = 0.5 + 0.25 * math.sin(os.clock() * 3)
			light.Brightness = 2.5 + math.sin(os.clock() * 6)
			task.wait()
		end
	end)
	return { holder, beacon }
end

----------------------------------------------------------------------
-- Meteoro com núcleo incandescente, rastro e fumaça
----------------------------------------------------------------------
function Models.Meteor(size)
	local m = Instance.new("Model")
	m.Name = "Meteor"
	local core = part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Material = MAT.Neon, Color = Color3.fromRGB(255, 140, 40) })
	core.Parent = m
	m.PrimaryPart = core
	local shell = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size * 1.12, size * 1.04, size * 1.12), Material = MAT.Slate, Color = Color3.fromRGB(58, 46, 44), Transparency = 0.12 })
	shell:SetAttribute("Offset", Vector3.zero)
	shell.Parent = m
	local lumps = {}
	for i = 1, 3 do
		local lump = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(size * 0.55, size * 0.5, size * 0.55), Material = MAT.Basalt, Color = Color3.fromRGB(40, 34, 34) })
		local a = i * 2.1
		lump:SetAttribute("Offset", Vector3.new(math.cos(a) * size * 0.42, math.sin(a * 1.7) * size * 0.3, math.sin(a) * size * 0.42))
		lump.Parent = m
		table.insert(lumps, lump)
	end

	local fire = Instance.new("Fire")
	fire.Size = size * 2.2
	fire.Heat = 25
	fire.Color = Color3.fromRGB(255, 150, 40)
	fire.SecondaryColor = Color3.fromRGB(190, 40, 20)
	fire.Parent = core

	local light = Instance.new("PointLight")
	light.Range = size * 9
	light.Brightness = 4
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Parent = core

	emitter(core, {
		Texture = SMOKE, Rate = 70, Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(0, 2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.7), NumberSequenceKeypoint.new(1, size * 2.6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(70, 62, 60)),
	})
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.4, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.4, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = 0.8
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(120, 30, 10))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = core

	-- move o meteoro inteiro (a cada quadro)
	local function place(cf)
		core.CFrame = cf
		shell.CFrame = cf
		for _, l in lumps do
			l.CFrame = cf * CFrame.new(l:GetAttribute("Offset"))
		end
	end
	return m, place
end

----------------------------------------------------------------------
-- Impacto: clarão, onda de choque, poeira, estilhaços, cratera que esfria
----------------------------------------------------------------------
function Models.Impact(position, radius)
	Models.Shockwave(position, radius * 1.8, 0.7, Color3.fromRGB(255, 200, 120))

	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = Workspace

	Models.DustBurst(position, 70, radius * 1.3)

	-- estilhaços (físicos, somem rápido)
	for _ = 1, 10 do
		local s = math.random(10, 22) / 10
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(s, s * 0.8, s)
		chunk.Material = MAT.Slate
		chunk.Color = Color3.fromRGB(70, 60, 58)
		chunk.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
		chunk.CanCollide = true
		chunk.CanTouch = false
		chunk.CanQuery = false
		chunk.Parent = container()
		chunk.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(30, 60), math.random(-30, 30))
		Debris:AddItem(chunk, 4)
	end

	-- cratera
	local folder = Instance.new("Folder")
	folder.Name = "Crater"
	folder.Parent = container()
	local scorch = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, radius * 1.9, radius * 1.9), CFrame = flatCFrame(position, 0.3), Material = MAT.Basalt, Color = Color3.fromRGB(32, 26, 26) })
	scorch.Parent = folder
	local hot = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, radius * 1.1, radius * 1.1), CFrame = flatCFrame(position, 0.4), Material = MAT.Neon, Color = Color3.fromRGB(255, 110, 30), Transparency = 0.15 })
	hot.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 50)
	light.Range = radius * 3
	light.Brightness = 3
	light.Parent = hot
	local embers = emitter(hot, {
		Texture = SPARK, Rate = 10, Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Right,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(Color3.fromRGB(255, 180, 70), Color3.fromRGB(255, 70, 20)), LightEmission = 1,
	})
	-- esfria devagar
	tween(hot, 24, { Color = Color3.fromRGB(70, 30, 20), Transparency = 0.9 }, Enum.EasingStyle.Linear)
	tween(light, 24, { Brightness = 0 }, Enum.EasingStyle.Linear)
	task.delay(18, function() embers.Rate = 0 end)
	tween(scorch, 40, { Transparency = 1 }, Enum.EasingStyle.Linear)
	Debris:AddItem(folder, 42)
	return folder
end

----------------------------------------------------------------------
-- Lava
----------------------------------------------------------------------
function Models.LavaBlob(position, size)
	local p = part({
		Shape = Enum.PartType.Ball, Size = Vector3.new(size, size * 0.3, size),
		CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, math.random() * 6.28, 0),
		Material = MAT.Neon, Color = Color3.fromRGB(255, 100 + math.random(0, 40), 28),
	})
	p.Parent = container()
	p.Size = Vector3.new(size * 0.3, size * 0.08, size * 0.3)
	tween(p, 0.5, { Size = Vector3.new(size, size * 0.3, size) }, Enum.EasingStyle.Back)
	return p
end

function Models.CoolLava(blob, seconds)
	if not blob or not blob.Parent then return end
	tween(blob, seconds, { Color = Color3.fromRGB(72, 36, 28) }, Enum.EasingStyle.Linear)
	task.delay(seconds, function()
		if blob.Parent then
			blob.Material = MAT.Basalt
		end
	end)
	Debris:AddItem(blob, seconds + 25)
end

-- bomba de lava (meteoro menor, avermelhado)
function Models.LavaBomb(size)
	local m, place = Models.Meteor(size)
	m:FindFirstChild("Core").Color = Color3.fromRGB(255, 90, 25)
	return m, place
end

----------------------------------------------------------------------
-- Pedregulho (físico, rola ladeira abaixo)
----------------------------------------------------------------------
function Models.Boulder(size)
	local core = Instance.new("Part")
	core.Name = "Boulder"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(size, size, size)
	core.Material = MAT.Slate
	core.Color = Color3.fromRGB(105, 108, 114)
	core.CustomPhysicalProperties = PhysicalProperties.new(2.2, 0.6, 0.2)
	core.TopSurface = Enum.SurfaceType.Smooth
	core.BottomSurface = Enum.SurfaceType.Smooth
	for i = 1, 3 do
		local lump = Instance.new("Part")
		lump.Shape = Enum.PartType.Ball
		lump.Size = Vector3.new(size * 0.6, size * 0.55, size * 0.6)
		lump.Material = MAT.Basalt
		lump.Color = Color3.fromRGB(80, 82, 88)
		lump.CanCollide = false
		lump.CanTouch = false
		lump.Massless = true
		local a = i * 2.1
		lump.CFrame = core.CFrame * CFrame.new(math.cos(a) * size * 0.38, math.sin(a * 1.4) * size * 0.25, math.sin(a) * size * 0.38)
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = core, lump
		weld.Parent = lump
		lump.Parent = core
	end
	return core
end

----------------------------------------------------------------------
-- Onda gigante
----------------------------------------------------------------------
function Models.TidalWave(width, height, depth)
	local model = Instance.new("Model")
	model.Name = "TidalWave"
	local body = part({ Name = "Body", Size = Vector3.new(width, height, depth), Material = MAT.Glass, Color = Color3.fromRGB(60, 140, 205), Transparency = 0.4, Reflectance = 0.2 })
	body.Parent = model
	model.PrimaryPart = body
	local crest = part({ Name = "Crest", Size = Vector3.new(width, 3, depth * 1.2), Material = MAT.SmoothPlastic, Color = Color3.fromRGB(235, 245, 250), Transparency = 0.15 })
	crest:SetAttribute("Height", height / 2)
	crest.Parent = model
	emitter(crest, {
		Texture = SMOKE, Rate = 220, Lifetime = NumberRange.new(1.2, 2.4), Speed = NumberRange.new(10, 26),
		SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(240, 248, 252)),
	})
	local base = part({ Name = "Foam", Size = Vector3.new(width, 1.5, depth * 2.6), Material = MAT.SmoothPlastic, Color = Color3.fromRGB(220, 238, 245), Transparency = 0.35 })
	base:SetAttribute("Height", -height / 2 + 0.7)
	base.Parent = model
	return model, body
end

function Models.PlaceWave(model, cf)
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			local h = d:GetAttribute("Height") or 0
			d.CFrame = cf * CFrame.new(0, h, 0)
		end
	end
end

return Models

