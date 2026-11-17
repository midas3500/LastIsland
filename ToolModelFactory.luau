
--[[
    ToolModelFactory
    Local: ReplicatedStorage > Modules > ToolModelFactory

    Cria os modelos de:
    Machado, Picareta, Faca e Vara de Pesca.
    Suporta os níveis Pedra, Ferro e Ouro.
]]

local ResourceConfig = require(script.Parent:WaitForChild("ResourceConfig"))

local ToolModelFactory = {}

local TIER_COLORS = {
	[1] = Color3.fromRGB(125, 125, 125), -- Pedra
	[2] = Color3.fromRGB(190, 195, 205), -- Ferro
	[3] = Color3.fromRGB(255, 190, 35),  -- Ouro
}

local WOOD_COLOR = Color3.fromRGB(115, 72, 38)
local WOOD_MATERIAL = Enum.Material.Wood
local METAL_MATERIAL = Enum.Material.Metal

local function getToolDefinition(toolName, tier)
	local definition = ResourceConfig.Tools[toolName]

	assert(definition, "Ferramenta inexistente: " .. tostring(toolName))
	assert(definition.Tiers, "Tiers não encontrados: " .. tostring(toolName))

	local tierData = definition.Tiers[tier]

	assert(tierData, "Nível de ferramenta inexistente: " .. tostring(tier))

	return definition, tierData
end

local function createPart(name, size, color, material, parent)
	local part = Instance.new("Part")

	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent

	return part
end

local function weld(handle, part, offset)
	part.CFrame = handle.CFrame * offset

	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = handle
	constraint.Part1 = part
	constraint.Parent = part
end

local function getMetalAppearance(tierData, tier)
	local color = tierData.HeadColor

	if typeof(color) ~= "Color3" then
		color = TIER_COLORS[tier] or TIER_COLORS[1]
	end

	local material = tierData.HeadMaterial

	if typeof(material) ~= "EnumItem" then
		material = METAL_MATERIAL
	end

	return color, material
end

local function createHandle(tool, length)
	local handle = createPart(
		"Handle",
		Vector3.new(0.22, 0.22, length),
		WOOD_COLOR,
		WOOD_MATERIAL,
		tool
	)

	handle.Reflectance = 0

	return handle
end

-- MACHADO

local function createAxe(tool, handle, color, material, length)
	local head = createPart(
		"AxeHead",
		Vector3.new(0.22, 1.15, 0.85),
		color,
		material,
		tool
	)

	weld(
		handle,
		head,
		CFrame.new(0, 0.15, -length * 0.32)
	)

	local edge = createPart(
		"AxeEdge",
		Vector3.new(0.12, 0.95, 0.95),
		color,
		Enum.Material.Metal,
		tool
	)

	weld(
		handle,
		edge,
		CFrame.new(0, 0.15, -length * 0.32)
			* CFrame.new(-0.08, 0, 0)
	)
end

-- PICARETA

local function createPickaxe(tool, handle, color, material, length)
	local bar = createPart(
		"PickaxeHead",
		Vector3.new(1.35, 0.22, 0.25),
		color,
		material,
		tool
	)

	weld(
		handle,
		bar,
		CFrame.new(0, 0.05, -length * 0.38)
	)

	local leftTip = createPart(
		"LeftTip",
		Vector3.new(0.65, 0.18, 0.2),
		color,
		material,
		tool
	)

	weld(
		handle,
		leftTip,
		CFrame.new(-0.85, -0.04, -length * 0.38)
			* CFrame.Angles(0, 0, math.rad(-20))
	)

	local rightTip = createPart(
		"RightTip",
		Vector3.new(0.65, 0.18, 0.2),
		color,
		material,
		tool
	)

	weld(
		handle,
		rightTip,
		CFrame.new(0.85, -0.04, -length * 0.38)
			* CFrame.Angles(0, 0, math.rad(20))
	)
end

-- FACA

local function createKnife(tool, handle, color, material, length)
	local blade = createPart(
		"KnifeBlade",
		Vector3.new(0.12, 0.16, 0.85),
		color,
		material,
		tool
	)

	weld(
		handle,
		blade,
		CFrame.new(0, 0.02, -length * 0.42)
	)

	local guard = createPart(
		"KnifeGuard",
		Vector3.new(0.42, 0.12, 0.13),
		WOOD_COLOR,
		WOOD_MATERIAL,
		tool
	)

	weld(
		handle,
		guard,
		CFrame.new(0, 0, -length * 0.13)
	)
end

-- VARA DE PESCA

local function createFishingRod(tool, handle, color, material, length)
	local reel = createPart(
		"FishingReel",
		Vector3.new(0.35, 0.35, 0.25),
		Color3.fromRGB(45, 45, 45),
		Enum.Material.Metal,
		tool
	)

	weld(
		handle,
		reel,
		CFrame.new(0.2, -0.15, length * 0.05)
	)

	local ring = createPart(
		"RodRing",
		Vector3.new(0.12, 0.12, 0.12),
		color,
		material,
		tool
	)

	weld(
		handle,
		ring,
		CFrame.new(0, 0, -length * 0.48)
	)

	local tip = createPart(
		"RodTip",
		Vector3.new(0.09, 0.09, length * 0.35),
		WOOD_COLOR,
		WOOD_MATERIAL,
		tool
	)

	weld(
		handle,
		tip,
		CFrame.new(0, 0, -length * 0.65)
	)
end

-- FUNÇÃO PRINCIPAL

function ToolModelFactory.CreateTool(toolName, tier)
	tier = math.max(1, math.floor(tonumber(tier) or 1))

	local definition, tierData = getToolDefinition(toolName, tier)

	local tool = Instance.new("Tool")

	tool.Name = tierData.Name or definition.DisplayName or toolName
	tool.ToolTip = definition.DisplayName or toolName
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ManualActivationOnly = true

	tool:SetAttribute("ToolType", toolName)
	tool:SetAttribute("ToolTier", tier)

	local visualConfig = ResourceConfig.ToolVisuals
		and ResourceConfig.ToolVisuals[toolName]

	local length = 3

	if visualConfig and type(visualConfig.HandleLength) == "number" then
		length = visualConfig.HandleLength
	end

	local handle = createHandle(tool, length)

	local metalColor, metalMaterial = getMetalAppearance(tierData, tier)

	if toolName == "Axe" then
		createAxe(tool, handle, metalColor, metalMaterial, length)

	elseif toolName == "Pickaxe" then
		createPickaxe(tool, handle, metalColor, metalMaterial, length)

	elseif toolName == "Knife" then
		createKnife(tool, handle, metalColor, metalMaterial, length)

	elseif toolName == "FishingRod" then
		createFishingRod(tool, handle, metalColor, metalMaterial, length)

	else
		tool:Destroy()
		error("Tipo de ferramenta não implementado: " .. tostring(toolName))
	end

	-- Ajuste básico de posição na mão.
	if visualConfig and typeof(visualConfig.GripPos) == "Vector3" then
		tool.GripPos = visualConfig.GripPos
	else
		tool.GripPos = Vector3.new(0, -0.5, 0)
	end

	return tool
end

return ToolModelFactory
