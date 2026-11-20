--[[
	BuildingRules (ModuleScript)
	Local: ReplicatedStorage > Modules > BuildingRules   (arquivo NOVO)

	Regras de construção usadas pelo SERVIDOR (que decide de verdade) e pelo CLIENTE
	(só para colorir a pré-visualização). Assim os dois calculam a mesma coisa.
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local BuildingConfig = require(script.Parent:WaitForChild("BuildingConfig"))

local Rules = {}

function Rules.Step()
	return BuildingConfig.GridSize / 2
end

-- Encaixa a posição (relativa ao centro da ilha). Retorna rx, rz.
function Rules.SnapRelative(center, raw)
	local step = Rules.Step()
	local rx = math.floor((raw.X - center.X) / step + 0.5) * step
	local rz = math.floor((raw.Z - center.Z) / step + 0.5) * step
	return rx, rz
end

function Rules.SnapYaw(yaw)
	local step = BuildingConfig.RotationStep
	if type(yaw) ~= "number" or yaw ~= yaw or math.abs(yaw) > 1e6 then
		yaw = 0
	end
	return (math.floor(yaw / step + 0.5) * step) % 360
end

function Rules.CFrameFor(center, groundY, rx, rz, yaw)
	return CFrame.new(center.X + rx, groundY, center.Z + rz) * CFrame.Angles(0, math.rad(yaw), 0)
end

-- Centro + 4 cantos da base da peça
function Rules.FootprintPoints(cf, size)
	local hx, hz = size.X / 2, size.Z / 2
	local points = {}
	for _, offset in ipairs({
		Vector3.new(0, 0, 0),
		Vector3.new(hx, 0, hz),
		Vector3.new(-hx, 0, hz),
		Vector3.new(hx, 0, -hz),
		Vector3.new(-hx, 0, -hz),
		}) do
		table.insert(points, (cf * CFrame.new(offset)).Position)
	end
	return points
end

-- Todos os pontos da base precisam estar dentro do raio de construção da ilha
function Rules.InsideBuildArea(center, buildRadius, cf, size)
	for _, point in ipairs(Rules.FootprintPoints(cf, size)) do
		local dx, dz = point.X - center.X, point.Z - center.Z
		if dx * dx + dz * dz > buildRadius * buildRadius then
			return false
		end
	end
	return true
end

local function layerOf(instance)
	local current = instance
	while current and current ~= Workspace do
		local layer = current:GetAttribute("BuildingLayer")
		if layer then
			return layer
		end
		current = current.Parent
	end
	return nil
end

local function isResourceNode(instance)
	local current = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, "ResourceNode") then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Pastas onde procurar obstáculos: o modelo da ilha, as construções e os recursos
function Rules.GetScope(islandModel)
	local scope = {}
	if islandModel then
		table.insert(scope, islandModel)
	end
	local buildings = Workspace:FindFirstChild(BuildingConfig.FolderName)
	if buildings then
		table.insert(scope, buildings)
	end
	local map = Workspace:FindFirstChild("Map")
	local spawns = map and map:FindFirstChild("ResourceSpawns")
	if spawns then
		table.insert(scope, spawns)
	end
	return scope
end

-- Retorna nil (livre) ou o motivo do conflito
function Rules.FindConflict(def, cf, scope)
	local allowed = BuildingConfig.Layers[def.Layer] or {}
	local pad = BuildingConfig.OverlapPadding
	local y0 = 0.2
	local y1 = math.max(def.Size.Y - 0.1, 0.5)

	local boxSize = Vector3.new(
		math.max(def.Size.X - 2 * pad, 0.2),
		y1 - y0,
		math.max(def.Size.Z - 2 * pad, 0.2)
	)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = scope
	params.MaxParts = 60

	local parts = Workspace:GetPartBoundsInBox(cf * CFrame.new(0, (y0 + y1) / 2, 0), boxSize, params)

	for _, part in ipairs(parts) do
		local layer = layerOf(part)
		if layer then
			if not allowed[layer] then
				return "Já existe uma construção neste local"
			end
		elseif isResourceNode(part) then
			return "Há um recurso neste local"
		elseif part:GetAttribute("ResourceType") ~= nil then
			-- marcador invisível de recurso: ignora
		elseif part.Transparency >= 0.95 and not part.CanCollide then
			-- peça auxiliar invisível: ignora
		else
			return "Há um objeto neste local"
		end
	end

	return nil
end

return Rules

