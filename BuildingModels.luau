--[[
	BuildingModels (ModuleScript)
	Local: ReplicatedStorage > Modules > BuildingModels   (arquivo NOVO)

	Cria por código os modelos das construções (sem depender de assets externos).
	Usado pelo servidor (modelo real) e pelo cliente (fantasma da pré-visualização).

	BuildingModels.Build(tipo, preview) -> Model
		- PrimaryPart = "Root" (invisível), na BASE da peça. Frente = -Z.
		- preview = true: sem colisão, sem luz e sem fogo (o cliente só quer o "fantasma").

	COMO ADICIONAR UMA CONSTRUÇÃO NOVA: crie uma função em "builders" com o mesmo nome da
	chave em BuildingConfig.Buildings.
]]

local MapConfig = require(script.Parent:WaitForChild("MapConfig"))
local P = MapConfig.Palette

local BuildingModels = {}
local builders = {}

local METAL = Color3.fromRGB(110, 115, 125)
local GOLD = Color3.fromRGB(235, 195, 70)

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function shade(color, factor)
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

-- opts: { Shape, Transparency, CanCollide, Reflectance }
local function add(ctx, name, size, cframe, material, color, opts)
	opts = opts or {}
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = not ctx.dynamic
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if opts.Shape then
		part.Shape = opts.Shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	part.Reflectance = opts.Reflectance or 0
	part.Transparency = opts.Transparency or 0
	if ctx.preview then
		part.CanCollide = false
		part.CanQuery = false
		part.CastShadow = false
	else
		part.CanCollide = opts.CanCollide ~= false
	end
	part.Parent = ctx.model
	return part
end

-- Peça cuja BASE fica em y = bottom (mais fácil de pensar do que o centro)
local function block(ctx, name, size, x, bottom, z, material, color, opts)
	return add(ctx, name, size, CFrame.new(x, bottom + size.Y / 2, z), material, color, opts)
end

-- Cilindro deitado ao longo do eixo X da peça
local function log(ctx, name, length, diameter, cframe, material, color)
	return add(ctx, name, Vector3.new(length, diameter, diameter), cframe, material, color, {
		Shape = Enum.PartType.Cylinder,
	})
end

local function addLight(ctx, parent, color, range, brightness)
	if ctx.preview then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = parent
end

-- ===========================================================================
-- CONSTRUÇÕES
-- ===========================================================================

builders.Floor = function(ctx)
	for i = 1, 4 do
		local z = -1.5 + (i - 1)
		block(ctx, "Plank_" .. i, Vector3.new(4, 0.4, 0.94), 0, 0, z, Enum.Material.WoodPlanks,
			shade(P.Wood, i % 2 == 0 and 0.94 or 1.04))
	end
end

builders.Wall = function(ctx)
	block(ctx, "Board", Vector3.new(4, 3.6, 0.6), 0, 0, 0, Enum.Material.WoodPlanks, P.Wood)
	block(ctx, "TopBeam", Vector3.new(4, 0.4, 0.9), 0, 3.6, 0, Enum.Material.Wood, P.WoodDark)
	for _, x in ipairs({ -1.8, 1.8 }) do
		block(ctx, "Post", Vector3.new(0.4, 4, 0.9), x, 0, 0, Enum.Material.Wood, P.WoodDark)
	end
	for _, y in ipairs({ 0.8, 2.5 }) do
		block(ctx, "Slat", Vector3.new(3.2, 0.3, 0.75), 0, y, 0, Enum.Material.Wood, shade(P.WoodDark, 1.1))
	end
end

builders.Fence = function(ctx)
	block(ctx, "Base", Vector3.new(4, 1.6, 1.2), 0, 0, 0, Enum.Material.Slate, P.Rock)
	block(ctx, "Middle", Vector3.new(3.8, 1.0, 1.0), 0, 1.6, 0, Enum.Material.Slate, P.RockDark)
	block(ctx, "Cap", Vector3.new(4, 0.4, 1.3), 0, 2.6, 0, Enum.Material.Slate, shade(P.Rock, 1.12))
	for _, x in ipairs({ -1.1, 1.1 }) do
		block(ctx, "Stone", Vector3.new(1.2, 0.7, 0.1), x, 0.5, -0.62, Enum.Material.Slate, shade(P.Rock, 0.88))
	end
end

builders.Chest = function(ctx)
	block(ctx, "Body", Vector3.new(3, 1.4, 2), 0, 0, 0, Enum.Material.WoodPlanks, P.Wood)
	block(ctx, "Lid", Vector3.new(3.05, 0.8, 2.05), 0, 1.4, 0, Enum.Material.WoodPlanks, P.WoodDark)
	for _, x in ipairs({ -1, 1 }) do
		block(ctx, "Band", Vector3.new(0.25, 2.0, 2.1), x, 0.1, 0, Enum.Material.Metal, METAL)
	end
	block(ctx, "Lock", Vector3.new(0.45, 0.55, 0.14), 0, 1.0, -1.06, Enum.Material.Metal, GOLD, { Reflectance = 0.1 })
end

builders.Campfire = function(ctx)
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		add(ctx, "Stone_" .. i, Vector3.new(0.6, 0.45, 0.5),
			CFrame.new(math.cos(angle) * 1.15, 0.22, math.sin(angle) * 1.15) * CFrame.Angles(0, -angle, 0),
			Enum.Material.Slate, shade(P.Rock, i % 2 == 0 and 0.9 or 1.05))
	end
	for i = 1, 3 do
		local yaw = (i / 3) * math.pi
		log(ctx, "Log_" .. i, 1.9, 0.3,
			CFrame.new(0, 0.38, 0) * CFrame.Angles(0, yaw, math.rad(14)),
			Enum.Material.Wood, shade(P.WoodDark, 0.85))
	end
	if not ctx.preview then
		local firePoint = add(ctx, "FirePoint", Vector3.new(0.3, 0.3, 0.3), CFrame.new(0, 0.7, 0),
			Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), { Transparency = 1, CanCollide = false })
		firePoint.CanQuery = false
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Heat = 6
		fire.Color = Color3.fromRGB(255, 150, 40)
		fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
		fire.Parent = firePoint
		addLight(ctx, firePoint, Color3.fromRGB(255, 170, 80), 20, 1.6)
	end
end

builders.House = function(ctx)
	local t = 0.6
	local wallBottom, wallTop = 0.5, 6.5

	-- piso
	block(ctx, "Floor", Vector3.new(12, 0.5, 12), 0, 0, 0, Enum.Material.WoodPlanks, P.WoodDark)

	-- paredes laterais (com janela no meio) e vidros
	for _, s in ipairs({ -1, 1 }) do
		local x = s * (6 - t / 2)
		block(ctx, "SideLow", Vector3.new(t, 1.7, 12), x, wallBottom, 0, Enum.Material.WoodPlanks, P.Wood)
		block(ctx, "SideHigh", Vector3.new(t, 2.5, 12), x, 4.0, 0, Enum.Material.WoodPlanks, P.Wood)
		block(ctx, "SideMidA", Vector3.new(t, 1.8, 4.5), x, 2.2, -3.75, Enum.Material.WoodPlanks, P.Wood)
		block(ctx, "SideMidB", Vector3.new(t, 1.8, 4.5), x, 2.2, 3.75, Enum.Material.WoodPlanks, P.Wood)
		add(ctx, "Glass", Vector3.new(0.1, 1.8, 3), CFrame.new(x, 3.1, 0), Enum.Material.Glass,
			Color3.fromRGB(170, 215, 240), { Transparency = 0.55 })
	end

	-- parede dos fundos
	block(ctx, "Back", Vector3.new(12 - 2 * t, 6, t), 0, wallBottom, 6 - t / 2, Enum.Material.WoodPlanks, P.Wood)

	-- parede da frente (porta em -Z)
	for _, s in ipairs({ -1, 1 }) do
		block(ctx, "FrontSide", Vector3.new(3.8, 6, t), s * 3.5, wallBottom, -(6 - t / 2), Enum.Material.WoodPlanks, P.Wood)
	end
	block(ctx, "Lintel", Vector3.new(3.2, 1.6, t), 0, wallBottom + 4.4, -(6 - t / 2), Enum.Material.WoodPlanks, P.WoodDark)

	-- vigas de canto
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			block(ctx, "Corner", Vector3.new(0.8, 6.2, 0.8), sx * 5.6, 0.4, sz * 5.6, Enum.Material.Wood, P.WoodDark)
		end
	end

	-- telhado de duas águas
	local theta = math.rad(28)
	local tanT, cosT = math.tan(theta), math.cos(theta)
	local run, eaveY, thick = 6.6, 6.4, 0.5
	for _, s in ipairs({ -1, 1 }) do
		add(ctx, "Roof", Vector3.new(run / cosT, thick, 12.8),
			CFrame.new(s * run / 2, eaveY + (run / 2) * tanT, 0) * CFrame.Angles(0, 0, -s * theta),
			Enum.Material.Metal, P.Red)
	end
	block(ctx, "Ridge", Vector3.new(0.8, 0.35, 13), 0, eaveY + run * tanT + 0.1, 0, Enum.Material.Wood, P.WoodDark)

	-- empena (triângulo da frente e de trás), em degraus que cabem sob o telhado
	local stepH = 0.85
	for i = 1, 4 do
		local y0 = wallTop + (i - 1) * stepH
		local y1 = y0 + stepH
		local halfW = math.min(5.4, run - (y1 + 0.05 - eaveY - (thick / 2) / cosT) / tanT)
		if halfW > 0.3 then
			for _, sz in ipairs({ -1, 1 }) do
				block(ctx, "Gable", Vector3.new(halfW * 2, stepH, t), 0, y0, sz * (6 - t / 2), Enum.Material.WoodPlanks, P.Wood)
			end
		end
	end

	-- lampião nos fundos
	local lamp = block(ctx, "Lantern", Vector3.new(0.5, 0.6, 0.5), 0, 4.2, 5.1, Enum.Material.Neon, P.LampGlow)
	lamp.CanCollide = false
	addLight(ctx, lamp, P.LampGlow, 16, 0.9)
end

builders.Tower = function(ctx)
	-- 4 postes
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			block(ctx, "Post", Vector3.new(0.7, 10, 0.7), sx * 2.6, 0, sz * 2.6, Enum.Material.Wood, P.WoodDark)
		end
	end
	-- travessas em dois níveis
	for _, y in ipairs({ 3.5, 7 }) do
		for _, s in ipairs({ -1, 1 }) do
			block(ctx, "BraceX", Vector3.new(5.2, 0.4, 0.4), 0, y, s * 2.6, Enum.Material.Wood, P.Wood)
			block(ctx, "BraceZ", Vector3.new(0.4, 0.4, 5.2), s * 2.6, y, 0, Enum.Material.Wood, P.Wood)
		end
	end
	-- plataforma com abertura (alçapão) onde a escada chega: x -1..1, z -3..-1
	block(ctx, "DeckBack", Vector3.new(6.4, 0.5, 4.2), 0, 10, 1.1, Enum.Material.WoodPlanks, P.Wood)
	block(ctx, "DeckFront", Vector3.new(6.4, 0.5, 0.2), 0, 10, -3.1, Enum.Material.WoodPlanks, P.Wood)
	for _, s in ipairs({ -1, 1 }) do
		block(ctx, "DeckSide", Vector3.new(2.2, 0.5, 2.0), s * 2.1, 10, -2.0, Enum.Material.WoodPlanks, P.Wood)
	end

	-- escada (TrussPart é escalável por padrão no Roblox)
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Size = Vector3.new(2, 10.5, 2)
	truss.CFrame = CFrame.new(0, 5.25, -2.0)
	truss.Color = P.WoodDark
	truss.Material = Enum.Material.Wood
	truss.CanTouch = false
	if ctx.preview then
		truss.CanCollide = false
		truss.CanQuery = false
	end
	truss.Parent = ctx.model

	-- guarda-corpo
	block(ctx, "RailBack", Vector3.new(6.4, 1, 0.25), 0, 10.5, 3.075, Enum.Material.Wood, P.WoodDark)
	block(ctx, "RailFront", Vector3.new(6.4, 1, 0.25), 0, 10.5, -3.075, Enum.Material.Wood, P.WoodDark)
	for _, s in ipairs({ -1, 1 }) do
		block(ctx, "RailSide", Vector3.new(0.25, 1, 6.4), s * 3.075, 10.5, 0, Enum.Material.Wood, P.WoodDark)
	end

	-- telhado
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			block(ctx, "RoofPost", Vector3.new(0.3, 3, 0.3), sx * 2.9, 10.5, sz * 2.9, Enum.Material.Wood, P.WoodDark)
		end
	end
	block(ctx, "Roof", Vector3.new(7, 0.4, 7), 0, 13.5, 0, Enum.Material.Metal, P.Red)
	block(ctx, "RoofCap", Vector3.new(4, 0.4, 4), 0, 13.9, 0, Enum.Material.Metal, shade(P.Red, 0.9))

	-- luz de vigia
	local lamp = block(ctx, "Beacon", Vector3.new(0.6, 0.6, 0.6), 0, 12.6, 0, Enum.Material.Neon, P.LampGlow)
	lamp.CanCollide = false
	addLight(ctx, lamp, P.LampGlow, 30, 1.3)
end

builders.Boat = function(ctx)
	-- casco (Hull) + bancos laterais + proa em V + mastro e vela. Tudo soldado ao Hull no servidor.
	add(ctx, "Hull", Vector3.new(3.6, 0.5, 7), CFrame.new(0, 0.45, 0), Enum.Material.WoodPlanks, P.Wood)
	for _, s in ipairs({ -1, 1 }) do
		block(ctx, "Side", Vector3.new(0.3, 1.1, 7), s * 1.65, 0.45, 0, Enum.Material.WoodPlanks, P.WoodDark)
		add(ctx, "Bow", Vector3.new(2.2, 1.1, 0.3), CFrame.new(s * 0.85, 1.0, -3.6) * CFrame.Angles(0, s * math.rad(35), 0), Enum.Material.WoodPlanks, P.WoodDark)
	end
	block(ctx, "Stern", Vector3.new(3.6, 1.1, 0.3), 0, 0.45, 3.35, Enum.Material.WoodPlanks, P.WoodDark)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "Seat"
	seat.Size = Vector3.new(2, 0.6, 2)
	seat.CFrame = CFrame.new(0, 1.0, 1.4)
	seat.Anchored = not ctx.dynamic
	seat.Color = P.WoodDark
	seat.Material = Enum.Material.Wood
	seat.MaxSpeed = 0
	seat.Torque = 0
	if ctx.preview then seat.CanCollide = false seat.CanQuery = false end
	seat.Parent = ctx.model
	block(ctx, "Mast", Vector3.new(0.25, 5, 0.25), 0, 0.7, -1.0, Enum.Material.Wood, P.WoodDark)
	block(ctx, "Sail", Vector3.new(0.1, 3.4, 2.6), 0, 2.4, -1.0, Enum.Material.Fabric, P.White, { CanCollide = false })
end

-- ==========================================================================
-- API
-- ===========================================================================

function BuildingModels.Has(typeName)
	return builders[typeName] ~= nil
end

function BuildingModels.Build(typeName, preview)
	-- modelo do Blender: ReplicatedStorage > BuildingAssets > <Tipo>
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("BuildingAssets")
	local asset = assets and assets:FindFirstChild(typeName)
	if asset and asset:IsA("Model") then
		local clone = asset:Clone()
		clone.Name = typeName
		if not clone.PrimaryPart then
			local r = Instance.new("Part")
			r.Name = "Root" r.Size = Vector3.new(0.2, 0.2, 0.2) r.Transparency = 1 r.CanCollide = false r.CanQuery = false
			r.CFrame = clone:GetPivot() r.Parent = clone
			clone.PrimaryPart = r
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = not (typeName == "Boat" and not preview)
				if preview then d.CanCollide = false d.CanQuery = false d.CastShadow = false end
			elseif preview and (d:IsA("Light") or d:IsA("Fire") or d:IsA("ParticleEmitter")) then
				d:Destroy()
			end
		end
		clone:SetAttribute("BuildingType", typeName)
		return clone
	end

	local builder = builders[typeName]
	if not builder then
		error("[BuildingModels] Sem modelo para: " .. tostring(typeName))
	end
	local dynamic = (typeName == "Boat") and not preview

	local model = Instance.new("Model")
	model.Name = typeName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = model
	model.PrimaryPart = root

	root.Anchored = not dynamic
	builder({ model = model, preview = preview == true, dynamic = dynamic })

	if dynamic then
		local hull = model:FindFirstChild("Hull")
		if hull then
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part ~= hull then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = hull
					weld.Part1 = part
					weld.Parent = part
				end
			end
		end
	end

	model:SetAttribute("BuildingType", typeName)
	return model
end

return BuildingModels

