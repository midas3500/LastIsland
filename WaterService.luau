--[[
	WaterService
	Local: ServerScriptService > Services > WaterService   (ModuleScript)

	Ponto único para tudo que é "água/oceano" no servidor.
	Hoje: detecta se uma posição está na água, mede profundidade e avisa quem entra/sai.
	Amanhã: peixes, animais perigosos, criaturas marinhas e eventos no oceano se registram aqui,
	sem precisar mexer na natação.

	É usado pelo SurvivalService (natação). Não precisa entrar na lista de serviços.

	API:
	  WaterService.IsInWater(position)        -> boolean (a posição está dentro d'água)
	  WaterService.GetDepth(position)         -> studs de profundidade abaixo da superfície (0 se em terra)
	  WaterService.GetZone(position)          -> "Land" | "Shallow" | "Coastal" | "Deep"
	  WaterService.PlayerEnteredWater / PlayerLeftWater   (BindableEvents: player, position)
	  WaterService.RegisterCreature(def)      -> reservado para peixes/tubarões (ainda não spawna nada)
	  WaterService.GetCreatures()
	  WaterService.OceanEvent                 (BindableEvent) -> eventos futuros no oceano
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapConfig"))

local WaterService = {}

local terrain = Workspace.Terrain
local WATER = Enum.Material.Water

WaterService.PlayerEnteredWater = Instance.new("BindableEvent")
WaterService.PlayerLeftWater = Instance.new("BindableEvent")
WaterService.OceanEvent = Instance.new("BindableEvent")

local creatures = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true
rayParams.FilterDescendantsInstances = { terrain }

-- Lê o voxel de terreno (4x4x4) que contém a posição
function WaterService.IsInWater(position, minOccupancy)
	local cell = terrain:WorldToCell(position)
	local center = terrain:CellCenterToWorld(cell.X, cell.Y, cell.Z)
	local half = Vector3.new(2, 2, 2)
	local ok, materials, occupancies = pcall(function()
		return terrain:ReadVoxels(Region3.new(center - half, center + half), 4)
	end)
	if not ok or not materials then
		return false
	end
	return materials[1][1][1] == WATER and occupancies[1][1][1] >= (minOccupancy or 0.5)
end

function WaterService.GetSeaLevel()
	return MapConfig.WaterLevel or 0
end

function WaterService.GetDepth(position)
	local sea = WaterService.GetSeaLevel()
	local hit = Workspace:Raycast(Vector3.new(position.X, sea + 200, position.Z), Vector3.new(0, -600, 0), rayParams)
	if not hit then
		return MapConfig.Ocean and MapConfig.Ocean.Depth or 0
	end
	return math.max(0, sea - hit.Position.Y)
end

function WaterService.GetZone(position)
	local depth = WaterService.GetDepth(position)
	if depth <= 0.5 then return "Land" end
	if depth < 8 then return "Shallow" end
	if depth < 30 then return "Coastal" end
	return "Deep"
end

-- Reservado: criaturas marinhas futuras (peixe, tubarão...)
-- def = { Name, Zones = { "Coastal", "Deep" }, Spawn = function(position) ... end, Dangerous = bool }
function WaterService.RegisterCreature(def)
	if type(def) ~= "table" or type(def.Name) ~= "string" then
		return false
	end
	creatures[def.Name] = def
	return true
end

function WaterService.GetCreatures()
	return creatures
end

function WaterService.Init()
end

function WaterService.Start()
end

return WaterService

