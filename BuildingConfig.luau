--[[
	BuildingConfig (v2)
	Local: ReplicatedStorage > Modules > BuildingConfig   (SUBSTITUI o arquivo antigo)

	Tudo sobre construção fica aqui: custos, tamanhos, limites e regras de sobreposição.
	Convenções de modelo: origem = centro da BASE, frente = -Z (a porta da casa fica em -Z).
]]

local BuildingConfig = {}

BuildingConfig.Version = 2

BuildingConfig.GridSize = 4              -- encaixe: as peças andam de GridSize/2 em GridSize/2 (2 studs)
BuildingConfig.RotationStep = 45         -- graus por giro (45 = 8 posições; use 90 para só 4)
BuildingConfig.MaxBuildingsPerIsland = 150
BuildingConfig.RefundRatio = 0.5         -- fração dos materiais devolvida ao demolir
BuildingConfig.PlaceDistance = 80        -- distância máxima entre o jogador e o ponto de construção
BuildingConfig.SpawnClearance = 7        -- raio livre em volta do ponto de nascimento da ilha
BuildingConfig.OverlapPadding = 0.15     -- folga ao testar sobreposição (peças encostadas podem)
BuildingConfig.GroundTolerance = 0.5     -- diferença máxima entre o solo real e o nível da ilha
BuildingConfig.FolderName = "Buildings"  -- pasta no Workspace

BuildingConfig.Chest = {
	Capacity = 300,                      -- total de itens que cabem em UM baú
}

-- Regras de sobreposição. Para cada camada: com quais camadas ela PODE ocupar o mesmo espaço.
--   Floor   = piso fino (pode ficar sob qualquer coisa)
--   Barrier = paredes e muros (podem se cruzar nos cantos)
--   Solid   = casas, baús, torres, fogueiras (precisam de espaço livre)
BuildingConfig.Layers = {
	Floor   = { Barrier = true, Solid = true },
	Barrier = { Barrier = true, Floor = true },
	Solid   = { Floor = true },
}

-- Ordem exibida no menu de construção
BuildingConfig.Order = { "House", "Wall", "Fence", "Chest", "Tower", "Floor", "Campfire" }

BuildingConfig.Buildings = {
	House = {
		DisplayName = "Casa",
		Description = "Abrigo completo com porta, janelas e telhado.",
		Cost = { Wood = 40, Stone = 10, Fiber = 10 },
		Size = Vector3.new(12, 10, 12),
		Layer = "Solid",
		Max = 2,
	},
	Wall = {
		DisplayName = "Parede",
		Description = "Parede de madeira. Combine várias para montar cômodos.",
		Cost = { Wood = 6 },
		Size = Vector3.new(4, 4, 1),
		Layer = "Barrier",
	},
	Fence = {
		DisplayName = "Muro",
		Description = "Muro baixo de pedra para cercar a sua área.",
		Cost = { Stone = 8 },
		Size = Vector3.new(4, 3, 1.2),
		Layer = "Barrier",
	},
	Chest = {
		DisplayName = "Baú",
		Description = "Guarda itens. Use os botões de interação para guardar e pegar.",
		Cost = { Wood = 10, Fiber = 4 },
		Size = Vector3.new(3, 2.4, 2),
		Layer = "Solid",
		Max = 8,
		Storage = true,
	},
	Tower = {
		DisplayName = "Torre de Proteção",
		Description = "Torre com escada e luz. Protege a área ao redor (raio de proteção).",
		Cost = { Wood = 30, Stone = 40, IronOre = 6 },
		Size = Vector3.new(6, 14, 6),
		Layer = "Solid",
		Max = 4,
		ProtectionRadius = 40,
	},
	Floor = {
		DisplayName = "Piso",
		Description = "Piso de tábuas.",
		Cost = { Wood = 4 },
		Size = Vector3.new(4, 0.4, 4),
		Layer = "Floor",
	},
	Campfire = {
		DisplayName = "Fogueira",
		Description = "Ilumina e aquece o acampamento.",
		Cost = { Wood = 5, Stone = 3 },
		Size = Vector3.new(3, 2, 3),
		Layer = "Solid",
		Max = 4,
	},
}

return BuildingConfig

