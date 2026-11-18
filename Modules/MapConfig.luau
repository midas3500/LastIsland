--[[
	MapConfig
	Local: ReplicatedStorage > Modules > MapConfig

	Todas as medidas, cores e quantidades do mapa. Unidades em "studs".
	Mapa: Eixo X = leste/oeste, eixo Z = norte/sul, Y = altura. O nível da água é Y = 0.
]]

local MapConfig = {}

MapConfig.Seed = 20260115 -- mesma semente = mesmo mapa. Mude para variar a decoração.

-- Objetos do template padrão que o gerador remove se ainda existirem
MapConfig.RemoveDefaultObjects = { "Baseplate", "SpawnLocation" }

-- Nomes das pastas criadas no Workspace
MapConfig.Folders = {
	Map = "Map",
	Ocean = "Ocean",
	MainIsland = "MainIsland",
	PlayerIslands = "PlayerIslands",
	ResourceSpawns = "ResourceSpawns",
	EventAreas = "EventAreas",
	Lobby = "Lobby",
}

-- Estilo low poly: ilhas são prismas de N lados (N precisa ser PAR)
MapConfig.Style = {
	PrismSides = 10,
	Material = Enum.Material.SmoothPlastic, -- cor chapada = visual low poly
	ColorJitter = 0.04,                     -- variação leve de cor entre peças
}

MapConfig.Palette = {
	Sand = Color3.fromRGB(244, 222, 160),
	Shelf = Color3.fromRGB(214, 200, 150),
	Grass = Color3.fromRGB(112, 184, 80),
	GrassDark = Color3.fromRGB(88, 160, 66),
	Rock = Color3.fromRGB(128, 133, 142),
	RockDark = Color3.fromRGB(98, 103, 114),
	Trunk = Color3.fromRGB(146, 104, 62),
	Leaf = Color3.fromRGB(74, 170, 84),
	LeafDark = Color3.fromRGB(52, 140, 70),
	Wood = Color3.fromRGB(176, 128, 78),
	WoodDark = Color3.fromRGB(120, 84, 50),
	White = Color3.fromRGB(240, 240, 240),
	Red = Color3.fromRGB(205, 60, 55),
	LampGlow = Color3.fromRGB(255, 220, 130),
	SpawnPad = Color3.fromRGB(90, 170, 230),
}
-- MATERIAIS (texturas nativas do Roblox). A chave é o INÍCIO do nome da peça
-- (ex.: "Beach_3" usa a chave "Beach"). Para trocar o visual, mude só aqui.
MapConfig.Materials = {
	Default = Enum.Material.Plastic,
	ByName = {
		ShelfDeep = Enum.Material.Sand,
		ShelfShallow = Enum.Material.Sand,
		Beach = Enum.Material.Sand,
		SeaFloor = Enum.Material.Sand,
		Grass = Enum.Material.Grass,
		Hill1 = Enum.Material.Grass,
		Hill2 = Enum.Material.Grass,
		Hill3 = Enum.Material.Grass,
		Summit = Enum.Material.Slate,
		Plaza = Enum.Material.WoodPlanks,
		Trunk = Enum.Material.Wood,
		Leaf = Enum.Material.LeafyGrass,
		Rock = Enum.Material.Slate,
		Pole = Enum.Material.Wood,
		Post = Enum.Material.Wood,
		Board = Enum.Material.WoodPlanks,
		Tower = Enum.Material.Concrete,
		Balcony = Enum.Material.Wood,
		Roof = Enum.Material.Metal,
		Deck = Enum.Material.WoodPlanks,
		Rail = Enum.Material.Wood,
		Pillar = Enum.Material.Wood,
	},
}

-- OCEANO (água física do Terrain, nada de modelos externos)
MapConfig.WaterLevel = 0 -- não altere sem ajustar as ilhas (múltiplo de 4)
MapConfig.Ocean = {
	Size = 1320,   -- lado do quadrado do oceano (múltiplo de 8)
	Depth = 20,    -- profundidade da água (múltiplo de 4)
	WallHeight = 300,
	FloorColor = Color3.fromRGB(26, 72, 120),
	Water = {
		Color = Color3.fromRGB(28, 140, 214),
		Transparency = 0.55,
		Reflectance = 0.25,
		WaveSize = 0.12,
		WaveSpeed = 8,
	},
}

-- Camadas (tiers) de uma ilha: de baixo para cima.
-- Scale = raio relativo ao raio da ilha | Bottom/Top = altura | Color = chave da Palette
local function islandTiers(extra)
	local tiers = {
		{ Name = "ShelfDeep",    Scale = 1.16, Bottom = -20.5, Top = -1.5, Color = "Shelf" },
		{ Name = "ShelfShallow", Scale = 1.08, Bottom = -3.0,  Top = -0.5, Color = "Shelf" },
		{ Name = "Beach",        Scale = 1.00, Bottom = -3.0,  Top = 0.6,  Color = "Sand" },
	}
	for _, tier in ipairs(extra) do
		table.insert(tiers, tier)
	end
	return tiers
end

-- 12 ILHAS DE JOGADORES (em anel ao redor da ilha central)
MapConfig.PlayerIslands = {
	Count = 12,
	RingRadius = 340,
	Radius = 60,
	AngleOffsetDeg = 15, -- deixa um corredor livre para a ponte do lobby
	Center = Vector3.new(0, 0, 0),
	GroundTier = "Grass",
	Tiers = islandTiers({
		{ Name = "Grass", Scale = 0.82, Bottom = 0.0, Top = 1.6, Color = "Grass" },
	}),
	Sign = { Title = "ILHA", Subtitle = "Disponível" },
}

-- ILHA CENTRAL (decorativa, com colina e farol)
MapConfig.MainIsland = {
	Position = Vector3.new(0, 0, 0),
	Radius = 100,
	GroundTier = "Grass",
	SummitTier = "Summit",
	Tiers = islandTiers({
		{ Name = "Grass",  Scale = 0.86, Bottom = 0.0, Top = 1.6, Color = "Grass" },
		{ Name = "Hill1",  Scale = 0.62, Bottom = 1.0, Top = 2.6, Color = "GrassDark" },
		{ Name = "Hill2",  Scale = 0.44, Bottom = 2.0, Top = 3.6, Color = "GrassDark" },
		{ Name = "Hill3",  Scale = 0.30, Bottom = 3.0, Top = 4.6, Color = "GrassDark" },
		{ Name = "Summit", Scale = 0.18, Bottom = 4.0, Top = 5.4, Color = "Rock" },
	}),
}

-- LOBBY (ao sul, fora do anel de ilhas)
MapConfig.Lobby = {
	Position = Vector3.new(0, 0, -560),
	Radius = 48,
	GroundTier = "Plaza",
	SpawnPads = 4,
	SpawnRadius = 12,
	Lamps = 4,
	Tiers = islandTiers({
		{ Name = "Plaza", Scale = 0.78, Bottom = 0.0, Top = 1.6, Color = "Wood" },
	}),
	Sign = { Title = "LAST ISLAND", Subtitle = "Bem-vindo! Atravesse a ponte" },
}

-- PONTES
MapConfig.Bridges = {
	Width = 12,
	DeckThickness = 0.6,
	DeckTop = 1.05,
	PostSpacing = 16,
	PillarSpacing = 28,
	LobbyToMain = true,
	-- false = ilhas de jogadores ficam isoladas (ideal para proteger construções).
	-- true  = cada ilha ganha uma ponte até a ilha central.
	PlayerIslandsToMain = false,
}

-- DECORAÇÃO (valores de PalmMin/Max/RockMin/Max são frações do raio da ilha)
MapConfig.Decor = {
	MinSpacing = 7,
	PlayerIsland = { Palms = 7,  Rocks = 5,  PalmMin = 0.66, PalmMax = 0.90, RockMin = 0.84, RockMax = 0.92 },
	MainIsland   = { Palms = 26, Rocks = 14, PalmMin = 0.68, PalmMax = 0.93, RockMin = 0.87, RockMax = 0.93 },
	Lobby        = { Palms = 7,  Rocks = 4,  PalmMin = 0.62, PalmMax = 0.90, RockMin = 0.80, RockMax = 0.92 },
}

MapConfig.Palm = {
	Segments = 3,
	SegmentHeight = 3.6,
	TrunkBaseWidth = 1.5,
	TrunkTopWidth = 0.9,
	LeanDegrees = 7,
	Leaves = 5,
	LeafWidth1 = 2.6, LeafLength1 = 4.6, LeafDroop1 = 12,
	LeafWidth2 = 1.6, LeafLength2 = 3.6, LeafDroop2 = 28,
	MinScale = 0.85,
	MaxScale = 1.25,
}

-- Marcadores invisíveis onde o ResourceService (Etapa 3) criará árvores, pedras e arbustos.
-- As chaves combinam com ResourceConfig.Nodes.
MapConfig.ResourceMarkers = {
	Counts = { Tree = 5, Rock = 4, Bush = 3, OreIron = 2, OreGold = 1 },
	Spacing = 8,
	MinRadiusScale = 0.30,
	MaxRadiusScale = 0.62,
}

-- Verificação automática de sobreposição
MapConfig.Validation = {
	MinGap = 20, -- espaço mínimo (água) entre as bordas de duas ilhas
}

-- ILUMINAÇÃO: presets aplicados pelo LightingService
MapConfig.Lighting = {
	DefaultPreset = "Day",
	Presets = {
		Day = {
			Lighting = {
				ClockTime = 14, Brightness = 3, ExposureCompensation = 0.1,
				Ambient = Color3.fromRGB(110, 120, 140),
				OutdoorAmbient = Color3.fromRGB(140, 150, 170),
				GlobalShadows = true,
			},
			Atmosphere = {
				Density = 0.28, Offset = 0.25, Glare = 0.2, Haze = 0.6,
				Color = Color3.fromRGB(199, 220, 245), Decay = Color3.fromRGB(106, 140, 190),
			},
			ColorCorrection = { Brightness = 0, Contrast = 0.08, Saturation = 0.2, TintColor = Color3.fromRGB(255, 255, 255) },
			Bloom = { Intensity = 0.35, Size = 22, Threshold = 1.6 },
			SunRays = { Intensity = 0.12, Spread = 0.8 },
		},
		Sunset = {
			Lighting = {
				ClockTime = 17.8, Brightness = 2.4, ExposureCompensation = 0,
				Ambient = Color3.fromRGB(120, 95, 110),
				OutdoorAmbient = Color3.fromRGB(150, 110, 110),
				GlobalShadows = true,
			},
			Atmosphere = {
				Density = 0.35, Offset = 0.3, Glare = 0.6, Haze = 1.2,
				Color = Color3.fromRGB(255, 190, 150), Decay = Color3.fromRGB(230, 120, 90),
			},
			ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.25, TintColor = Color3.fromRGB(255, 235, 220) },
			Bloom = { Intensity = 0.5, Size = 26, Threshold = 1.4 },
			SunRays = { Intensity = 0.2, Spread = 0.9 },
		},
		Storm = {
			Lighting = {
				ClockTime = 13, Brightness = 1.2, ExposureCompensation = -0.3,
				Ambient = Color3.fromRGB(70, 75, 85),
				OutdoorAmbient = Color3.fromRGB(85, 90, 100),
				GlobalShadows = true,
			},
			Atmosphere = {
				Density = 0.55, Offset = 0, Glare = 0, Haze = 2,
				Color = Color3.fromRGB(120, 130, 145), Decay = Color3.fromRGB(70, 80, 95),
			},
			ColorCorrection = { Brightness = -0.03, Contrast = 0.12, Saturation = -0.15, TintColor = Color3.fromRGB(215, 225, 240) },
			Bloom = { Intensity = 0.15, Size = 18, Threshold = 2 },
			SunRays = { Intensity = 0, Spread = 0.5 },
		},
		Night = {
			Lighting = {
				ClockTime = 23, Brightness = 1, ExposureCompensation = 0.2,
				Ambient = Color3.fromRGB(40, 50, 80),
				OutdoorAmbient = Color3.fromRGB(55, 65, 100),
				GlobalShadows = true,
			},
			Atmosphere = {
				Density = 0.3, Offset = 0, Glare = 0, Haze = 0.8,
				Color = Color3.fromRGB(40, 55, 95), Decay = Color3.fromRGB(20, 30, 60),
			},
			ColorCorrection = { Brightness = 0, Contrast = 0.1, Saturation = 0.05, TintColor = Color3.fromRGB(200, 215, 255) },
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.2 },
			SunRays = { Intensity = 0, Spread = 0.5 },
		},
	},
}

require(script.Parent.MapConfigPatch)(MapConfig)

return MapConfig