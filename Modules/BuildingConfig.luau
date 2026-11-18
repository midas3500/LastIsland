--[[
	BuildingConfig
	Local: ReplicatedStorage > Modules > BuildingConfig

	Dados iniciais de construções. Usados a partir da Etapa 4.
]]

local BuildingConfig = {}

BuildingConfig.Version = 1
BuildingConfig.GridSize = 4            -- tamanho do "encaixe" de construção (studs)
BuildingConfig.MaxBuildingsPerIsland = 150

BuildingConfig.Buildings = {
	Floor    = { DisplayName = "Piso",        Cost = { Wood = 4 },             Size = Vector3.new(4, 1, 4) },
	Wall     = { DisplayName = "Parede",      Cost = { Wood = 6 },             Size = Vector3.new(4, 4, 1) },
	Campfire = { DisplayName = "Fogueira",    Cost = { Wood = 5, Stone = 3 },  Size = Vector3.new(3, 2, 3) },
	Storage  = { DisplayName = "Baú",         Cost = { Wood = 10, Fiber = 4 }, Size = Vector3.new(3, 3, 3) },
}

return BuildingConfig