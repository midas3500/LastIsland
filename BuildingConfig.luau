--[[
	BuildingConfig (v3)  -  ReplicatedStorage > Modules > BuildingConfig  (SUBSTITUI)
	Construção em QUALQUER lugar do mapa (menos nadando ou no ar). Origem do modelo = centro da base, frente = -Z.
	MODELOS DO BLENDER: coloque um Model com o MESMO nome da peça (ex.: "House") em
	ReplicatedStorage > BuildingAssets. Ele substitui o modelo feito por script. Origem do pivot = centro da base.
]]
local C = {}

C.GridSize = 4              -- encaixe de GridSize/2 studs
C.RotationStep = 45
C.MaxPerPlayer = 150
C.RefundRatio = 0.5
C.PlaceDistance = 60        -- alcance (studs) entre o jogador e a peça
C.OverlapPadding = 0.15
C.GroundTolerance = 1.0     -- desnível máximo sob a peça
C.MaxSlopeNormalY = 0.75    -- inclinação máxima do chão (1 = plano)
C.FolderName = "Buildings"
C.Chest = { Capacity = 300 }

C.Boat = { Speed = 28, TurnRate = 1.6 }

C.Layers = {
	Floor   = { Barrier = true, Solid = true },
	Barrier = { Barrier = true, Floor = true },
	Solid   = { Floor = true },
}

C.Order = { "House", "Wall", "Fence", "Floor", "Chest", "Campfire", "Tower", "Boat" }

C.Buildings = {
	House    = { Category = "Casas",     DisplayName = "Casa",     Cost = { Wood = 40, Stone = 10, Fiber = 10 }, Size = Vector3.new(12, 10, 12), Layer = "Solid", Max = 3 },
	Wall     = { Category = "Estruturas", DisplayName = "Parede",  Cost = { Wood = 6 },  Size = Vector3.new(4, 4, 1),     Layer = "Barrier" },
	Fence    = { Category = "Estruturas", DisplayName = "Muro",    Cost = { Stone = 8 }, Size = Vector3.new(4, 3, 1.2),   Layer = "Barrier" },
	Floor    = { Category = "Estruturas", DisplayName = "Piso",    Cost = { Wood = 4 },  Size = Vector3.new(4, 0.4, 4),   Layer = "Floor" },
	Chest    = { Category = "Utilidades", DisplayName = "Baú",     Cost = { Wood = 10, Fiber = 4 }, Size = Vector3.new(3, 2.4, 2), Layer = "Solid", Max = 8, Storage = true },
	Campfire = { Category = "Utilidades", DisplayName = "Fogueira", Cost = { Wood = 5, Stone = 3 }, Size = Vector3.new(3, 2, 3), Layer = "Solid", Max = 4 },
	Tower    = { Category = "Defesa",    DisplayName = "Torre",    Cost = { Wood = 30, Stone = 40, IronOre = 6 }, Size = Vector3.new(6, 14, 6), Layer = "Solid", Max = 4, ProtectionRadius = 40 },
	Boat     = { Category = "Barcos",    DisplayName = "Barco",    Cost = { Wood = 40, Fiber = 15 }, Size = Vector3.new(4, 6, 8), Layer = "Solid", Max = 2, Water = true, Dynamic = true },
}

return C

