--[[ BuildingRules (v3) - ReplicatedStorage > Modules  (SUBSTITUI). Usado pelo servidor e pelo cliente. ]]
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent:WaitForChild("BuildingConfig"))

local Rules = {}

function Rules.Snap(v)
	local step = Config.GridSize / 2
	return math.floor(v / step + 0.5) * step
end

function Rules.SnapYaw(yaw)
	local step = Config.RotationStep
	if type(yaw) ~= "number" or yaw ~= yaw or math.abs(yaw) > 1e6 then
		yaw = 0
	end
	return (math.floor(yaw / step + 0.5) * step) % 360
end

function Rules.CFrameFor(x, y, z, yaw)
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
end

-- centro + 4 cantos da base
function Rules.FootprintPoints(cf, size)
	local hx, hz = size.X / 2, size.Z / 2
	local out = {}
	for _, o in ipairs({ Vector3.new(0, 0, 0), Vector3.new(hx, 0, hz), Vector3.new(-hx, 0, hz), Vector3.new(hx, 0, -hz), Vector3.new(-hx, 0, -hz) }) do
		table.insert(out, (cf * CFrame.new(o)).Position)
	end
	return out
end

local function layerOf(inst)
	local c = inst
	while c and c ~= Workspace do
		local l = c:GetAttribute("BuildingLayer")
		if l then return l end
		c = c.Parent
	end
end

local function isResource(inst)
	local c = inst
	while c and c ~= Workspace do
		if CollectionService:HasTag(c, "ResourceNode") then return true end
		c = c.Parent
	end
	return false
end

-- ignore = instâncias a ignorar (personagens, fantasma). Retorna nil (livre) ou o motivo.
function Rules.FindConflict(def, cf, ignore)
	local allowed = Config.Layers[def.Layer] or {}
	local pad = Config.OverlapPadding
	local y0, y1 = 0.2, math.max(def.Size.Y - 0.1, 0.5)

	local ignoreList = { Workspace.Terrain }
	for _, i in ipairs(ignore or {}) do
		table.insert(ignoreList, i)
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList
	params.MaxParts = 60

	local size = Vector3.new(math.max(def.Size.X - 2 * pad, 0.2), y1 - y0, math.max(def.Size.Z - 2 * pad, 0.2))
	for _, part in ipairs(Workspace:GetPartBoundsInBox(cf * CFrame.new(0, (y0 + y1) / 2, 0), size, params)) do
		local layer = layerOf(part)
		if layer then
			if not allowed[layer] then return "Já existe uma construção aqui" end
		elseif isResource(part) then
			return "Há um recurso aqui"
		elseif part:GetAttribute("ResourceType") ~= nil or (part.Transparency >= 0.95 and not part.CanCollide) then
			-- marcador/peça invisível: ignora
		elseif part.CanCollide then
			return "Há um objeto aqui"
		end
	end
	return nil
end

return Rules

