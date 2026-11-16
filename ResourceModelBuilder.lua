--[[
	ResourceModelBuilder (ModuleScript)
	Local: ServerScriptService > Services > ResourceModelBuilder   (arquivo NOVO)

	Cria por código os modelos-modelo (templates) dos recursos em ServerStorage > ResourceModels.
	Se já existir um modelo com o mesmo nome na pasta (feito por você), ele NÃO é sobrescrito.

	FORMATO DE UM TEMPLATE (vale também para modelos feitos à mão):
		Model "Nome"            (PrimaryPart = Root)
		├── Root                Part pequena e invisível, na BASE do recurso (origem 0,0,0)
		├── Full                Model/Folder com as peças do recurso inteiro
		└── Depleted            Model/Folder (opcional) com o visual "esgotado" (toco, cascalho...)
	Todas as peças: Anchored = true.

	COMO ADICIONAR UM MODELO NOVO: crie uma função em "builders" (veja o fim da seção BUILDERS).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResourceConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ResourceConfig"))
local V = ResourceConfig.Visuals

local Builder = {}
local builders = {}
local rng = Random.new(4242)

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function tint(color)
	local f = 1 + rng:NextNumber(-0.05, 0.05)
	return Color3.new(math.clamp(color.R * f, 0, 1), math.clamp(color.G * f, 0, 1), math.clamp(color.B * f, 0, 1))
end

-- options: { Shape = Enum.PartType.X, CanCollide = false }
local function make(parent, name, cframe, size, styleName, options)
	options = options or {}
	local style = V[styleName]
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = options.CanCollide ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if options.Shape then
		part.Shape = options.Shape
	end
	part.Size = size
	part.CFrame = cframe
	part.Material = style.Material
	part.Color = tint(style.Color)
	part.Reflectance = style.Reflectance or 0
	part.Parent = parent
	return part
end

local function newTemplate(name)
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.2, 1)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model

	local full = Instance.new("Model")
	full.Name = "Full"
	full.Parent = model

	local depleted = Instance.new("Model")
	depleted.Name = "Depleted"
	depleted.Parent = model

	model.PrimaryPart = root
	return model, full, depleted
end

local function rad(degrees)
	return math.rad(degrees)
end

local function buildRubble(depleted)
	local pieces = {
		{ CFrame.new(0.4, 0.25, 0.2) * CFrame.Angles(rad(10), rad(30), rad(8)), Vector3.new(1.1, 0.5, 0.9), "Rock" },
		{ CFrame.new(-0.7, 0.2, -0.4) * CFrame.Angles(rad(-8), rad(70), rad(12)), Vector3.new(0.9, 0.4, 0.8), "RockDark" },
		{ CFrame.new(0.1, 0.18, -0.9) * CFrame.Angles(rad(5), rad(10), rad(-9)), Vector3.new(0.7, 0.35, 0.7), "Rock" },
	}
	for i, p in ipairs(pieces) do
		make(depleted, "Rubble_" .. i, p[1], p[2], p[3], { CanCollide = false })
	end
end

-- ===========================================================================
-- BUILDERS (um por Template)
-- ===========================================================================

-- PALMEIRA (tronco de madeira curvo + folhas + cocos). Esgotada: toco com broto.
builders.Tree = function(full, depleted)
	local frame = CFrame.new(0, 0, 0)
	local segments, segHeight = 4, 3.4

	for i = 1, segments do
		local t = (i - 1) / (segments - 1)
		local width = 1.9 - 0.9 * t
		make(full, "Trunk_" .. i, frame * CFrame.new(0, segHeight * 0.56, 0), Vector3.new(width, segHeight * 1.12, width), "Trunk")
		frame = frame * CFrame.new(0, segHeight, 0) * CFrame.Angles(0, 0, rad(5 + (i % 2) * 3))
	end

	local leaves = 7
	for k = 1, leaves do
		local style = (k % 2 == 0) and "Leaf" or "LeafDark"
		local f = frame * CFrame.Angles(0, (k / leaves) * 2 * math.pi, 0) * CFrame.Angles(-rad(14), 0, 0)
		make(full, "Leaf_" .. k .. "_A", f * CFrame.new(0, 0, -2.6), Vector3.new(3.0, 0.35, 5.2), style, { CanCollide = false })
		f = f * CFrame.new(0, 0, -5.2) * CFrame.Angles(-rad(30), 0, 0)
		make(full, "Leaf_" .. k .. "_B", f * CFrame.new(0, 0, -2), Vector3.new(1.8, 0.3, 4), style, { CanCollide = false })
	end

	for k = 1, 3 do
		local a = k * 2.1
		make(full, "Coconut_" .. k, frame * CFrame.new(math.cos(a) * 0.9, -0.4, math.sin(a) * 0.9), Vector3.new(1, 1, 1), "Coconut", { Shape = Enum.PartType.Ball, CanCollide = false })
	end

	-- esgotada
	make(depleted, "Stump", CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, rad(90)), Vector3.new(1.4, 1.9, 1.9), "Trunk", { Shape = Enum.PartType.Cylinder })
	make(depleted, "Sprout", CFrame.new(0, 1.7, 0), Vector3.new(0.8, 0.8, 0.8), "Leaf", { Shape = Enum.PartType.Ball, CanCollide = false })
	make(depleted, "Log_1", CFrame.new(1.7, 0.35, 0.8) * CFrame.Angles(0, 0.6, 0), Vector3.new(2.2, 0.7, 0.7), "Trunk", { Shape = Enum.PartType.Cylinder, CanCollide = false })
	make(depleted, "Log_2", CFrame.new(-1.4, 0.3, -1.0) * CFrame.Angles(0, -0.9, 0), Vector3.new(1.8, 0.6, 0.6), "Trunk", { Shape = Enum.PartType.Cylinder, CanCollide = false })
end

-- PEDRA (blocos de ardósia/basalto girados). Esgotada: cascalho.
builders.Rock = function(full, depleted)
	make(full, "Chunk_1", CFrame.new(0, 1.0, 0) * CFrame.Angles(rad(8), rad(25), rad(-6)), Vector3.new(3.4, 2.4, 3.0), "Rock")
	make(full, "Chunk_2", CFrame.new(1.7, 0.7, 0.8) * CFrame.Angles(rad(-12), rad(60), rad(10)), Vector3.new(2.0, 1.6, 1.8), "RockDark")
	make(full, "Chunk_3", CFrame.new(-1.5, 0.6, -1.0) * CFrame.Angles(rad(10), rad(-30), rad(12)), Vector3.new(1.8, 1.4, 1.7), "Rock")
	make(full, "Chunk_4", CFrame.new(0.3, 2.1, -0.2) * CFrame.Angles(rad(15), rad(40), rad(-18)), Vector3.new(1.6, 1.2, 1.5), "RockDark")
	buildRubble(depleted)
end

-- MINÉRIO: rocha escura com cristais/veios do metal. Reutilizado por ferro e ouro.
local function buildOre(full, depleted, oreStyle)
	make(full, "Base_1", CFrame.new(0, 0.9, 0) * CFrame.Angles(rad(6), rad(20), rad(-5)), Vector3.new(3.4, 2.0, 3.0), "RockDark")
	make(full, "Base_2", CFrame.new(1.6, 0.6, 0.9) * CFrame.Angles(rad(-10), rad(55), rad(8)), Vector3.new(1.9, 1.3, 1.8), "Rock")
	make(full, "Base_3", CFrame.new(-1.4, 0.5, -0.9) * CFrame.Angles(rad(8), rad(-35), rad(10)), Vector3.new(1.7, 1.1, 1.6), "RockDark")

	local veins = {
		{ x = -0.7, z = 0.3, h = 1.7, rx = 12, ry = 20, rz = 14 },
		{ x = 0.6, z = -0.4, h = 2.0, rx = -10, ry = 55, rz = -12 },
		{ x = 0.1, z = 0.9, h = 1.4, rx = 16, ry = 80, rz = 6 },
		{ x = 1.4, z = 0.5, h = 1.2, rx = -14, ry = 30, rz = 18 },
		{ x = -1.3, z = -0.5, h = 1.3, rx = 8, ry = 100, rz = -16 },
	}
	for i, v in ipairs(veins) do
		make(full, "Ore_" .. i, CFrame.new(v.x, 1.7 + v.h * 0.3, v.z) * CFrame.Angles(rad(v.rx), rad(v.ry), rad(v.rz)), Vector3.new(0.75, v.h, 0.75), oreStyle)
	end

	buildRubble(depleted)
end

builders.OreIron = function(full, depleted)
	buildOre(full, depleted, "OreIron")
end

builders.OreGold = function(full, depleted)
	buildOre(full, depleted, "OreGold")
end

-- ARBUSTO DE FIBRA (esferas de folhagem + frutinhas). Esgotado: restinho baixo.
builders.Bush = function(full, depleted)
	local balls = {
		{ 0, 0.9, 0, 2.4, "Bush" },
		{ 1.1, 0.7, 0.5, 1.8, "BushDark" },
		{ -1.0, 0.7, -0.4, 1.9, "BushDark" },
		{ 0.2, 1.3, -0.8, 1.6, "Bush" },
		{ -0.3, 1.5, 0.7, 1.4, "Bush" },
	}
	for i, b in ipairs(balls) do
		make(full, "Foliage_" .. i, CFrame.new(b[1], b[2], b[3]), Vector3.new(b[4], b[4], b[4]), b[5], { Shape = Enum.PartType.Ball })
	end
	local berries = { { 0.9, 1.6, 1.0 }, { -0.8, 1.9, 0.4 }, { 0.3, 2.0, -0.5 }, { -1.4, 1.2, -0.6 } }
	for i, b in ipairs(berries) do
		make(full, "Berry_" .. i, CFrame.new(b[1], b[2], b[3]), Vector3.new(0.4, 0.4, 0.4), "Berry", { Shape = Enum.PartType.Ball, CanCollide = false })
	end

	make(depleted, "Stub_1", CFrame.new(0, 0.3, 0), Vector3.new(1.0, 0.6, 1.0), "BushDark", { Shape = Enum.PartType.Ball })
	make(depleted, "Stub_2", CFrame.new(0.6, 0.2, 0.4), Vector3.new(0.6, 0.4, 0.6), "Bush", { Shape = Enum.PartType.Ball, CanCollide = false })
end

-- ---------------------------------------------------------------------------
-- ADICIONE NOVOS BUILDERS AQUI (a chave precisa ser igual ao campo Template do recurso).
-- Exemplo (cristal):
--
-- builders.Crystal = function(full, depleted)
--     make(full, "Crystal_1", CFrame.new(0, 1.5, 0), Vector3.new(1, 3, 1), "OreGold")
--     buildRubble(depleted)
-- end
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- API
-- ===========================================================================

function Builder.Register(templateName, buildFunction)
	builders[templateName] = buildFunction
end

-- Cria, dentro de "folder", os templates que ainda não existem
function Builder.EnsureTemplates(folder)
	local created = 0
	for key, def in pairs(ResourceConfig.Nodes) do
		local name = def.Template
		if not folder:FindFirstChild(name) then
			local build = builders[name]
			if build then
				local model, full, depleted = newTemplate(name)
				local ok, err = pcall(build, full, depleted)
				if ok then
					model.Parent = folder
					created += 1
				else
					warn(string.format("[ResourceModelBuilder] Erro ao construir '%s': %s", name, tostring(err)))
					model:Destroy()
				end
			else
				warn(string.format("[ResourceModelBuilder] Sem modelo para '%s' (recurso %s). Crie um builder ou coloque um modelo em ServerStorage > ResourceModels.", name, key))
			end
		end
	end
	return created
end

return Builder
