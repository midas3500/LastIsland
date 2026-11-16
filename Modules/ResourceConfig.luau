--[[
	ResourceConfig (v2)
	Local: ReplicatedStorage > Modules > ResourceConfig
	(SUBSTITUI a versão da Etapa 1: apague tudo e cole este arquivo)

	TUDO que é recurso fica aqui: itens, ferramentas, tempos, recompensas, respawn e visual.
	Para criar um recurso novo, veja a seção "Como adicionar um recurso novo" no guia.
]]

local ResourceConfig = {}

ResourceConfig.Version = 2

-- Multiplicador global de recompensas (eventos e gamepasses poderão alterar no futuro)
ResourceConfig.GlobalYieldMultiplier = 1

-- Regras gerais da coleta (todas validadas no SERVIDOR)
ResourceConfig.Gathering = {
	DefaultMaxDistance = 12, -- distância máxima (studs) para iniciar a coleta
	DistanceTolerance = 3,   -- folga extra durante a coleta (lag / movimento leve)
	StartCooldown = 0.4,     -- segundos entre o fim de uma coleta e o início da próxima
	SwingInterval = 0.8,     -- tempo entre uma batida e outra
	HitDelay = 0.3,          -- atraso do efeito de impacto após o início da batida
	MinGatherTime = 0.6,     -- tempo mínimo de coleta (mesmo com ferramenta rápida)
	RespawnJitter = 0.2,     -- variação aleatória do respawn (0.2 = +-20%)
	OwnerOnly = true,        -- true = só o dono da ilha coleta os recursos dela
	PromptKey = Enum.KeyCode.E,
}

-- Itens que existem no inventário
ResourceConfig.Items = {
	Coconut = {
		DisplayName = "Coco",
		MaxStack = 999,
		Order = 6,
		Color = Color3.fromRGB(150, 110, 65),
	},
	Wood    = { DisplayName = "Madeira",          MaxStack = 999, Order = 1, Color = Color3.fromRGB(176, 128, 78) },
	Stone   = { DisplayName = "Pedra",            MaxStack = 999, Order = 2, Color = Color3.fromRGB(140, 145, 155) },
	Fiber   = { DisplayName = "Fibra",            MaxStack = 999, Order = 3, Color = Color3.fromRGB(120, 180, 90) },
	IronOre = { DisplayName = "Minério de Ferro", MaxStack = 999, Order = 4, Color = Color3.fromRGB(190, 120, 85) },
	GoldOre = { DisplayName = "Minério de Ouro",  MaxStack = 999, Order = 5, Color = Color3.fromRGB(240, 200, 70) },
}

-- Ferramentas e níveis (tiers). O nível atual de cada jogador fica em data.Tools (ex.: Axe = 1).
-- Speed divide o tempo de coleta. Yield multiplica a quantidade recebida.
ResourceConfig.Tools = {
	Axe = {
		DisplayName = "Machado",
		Tiers = {
			[1] = { Name = "Machado de Pedra", Speed = 1.0, Yield = 1.0,  HeadColor = Color3.fromRGB(125, 130, 138), HeadMaterial = Enum.Material.Slate },
			[2] = { Name = "Machado de Ferro", Speed = 1.4, Yield = 1.25, HeadColor = Color3.fromRGB(175, 180, 190), HeadMaterial = Enum.Material.Metal },
			[3] = { Name = "Machado Dourado",  Speed = 1.9, Yield = 1.6,  HeadColor = Color3.fromRGB(235, 195, 70),  HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.1 },
		},
	},
	Pickaxe = {
		DisplayName = "Picareta",
		Tiers = {
			[1] = { Name = "Picareta de Pedra", Speed = 1.0, Yield = 1.0,  HeadColor = Color3.fromRGB(125, 130, 138), HeadMaterial = Enum.Material.Slate },
			[2] = { Name = "Picareta de Ferro", Speed = 1.4, Yield = 1.25, HeadColor = Color3.fromRGB(175, 180, 190), HeadMaterial = Enum.Material.Metal },
			[3] = { Name = "Picareta Dourada",  Speed = 1.9, Yield = 1.6,  HeadColor = Color3.fromRGB(235, 195, 70),  HeadMaterial = Enum.Material.Metal, HeadReflectance = 0.1 },
		},
	},
}

-- Ferramenta na mão. Se ela ficar torta no seu personagem, ajuste GripPos.
ResourceConfig.ToolVisual = {
	GripPos = Vector3.new(0, 0, 1.1),
	HandleLength = 3.2,
}

-- Aparência (cores + materiais com textura nativa do Roblox). Usado pelo ResourceModelBuilder.
ResourceConfig.Visuals = {
	Trunk    = { Color = Color3.fromRGB(128, 92, 58),   Material = Enum.Material.Wood },
	Leaf     = { Color = Color3.fromRGB(70, 150, 72),   Material = Enum.Material.LeafyGrass },
	LeafDark = { Color = Color3.fromRGB(48, 118, 60),   Material = Enum.Material.LeafyGrass },
	Coconut  = { Color = Color3.fromRGB(96, 66, 40),    Material = Enum.Material.Wood },
	Rock     = { Color = Color3.fromRGB(122, 126, 134), Material = Enum.Material.Slate },
	RockDark = { Color = Color3.fromRGB(92, 96, 106),   Material = Enum.Material.Basalt },
	OreIron  = { Color = Color3.fromRGB(178, 106, 74),  Material = Enum.Material.CorrodedMetal },
	OreGold  = { Color = Color3.fromRGB(236, 190, 70),  Material = Enum.Material.Metal, Reflectance = 0.12 },
	Bush     = { Color = Color3.fromRGB(80, 150, 70),   Material = Enum.Material.LeafyGrass },
	BushDark = { Color = Color3.fromRGB(56, 120, 58),   Material = Enum.Material.LeafyGrass },
	Berry    = { Color = Color3.fromRGB(200, 60, 80),   Material = Enum.Material.SmoothPlastic },
}

--[[
	RECURSOS COLETÁVEIS
	A chave (Tree, Rock...) precisa ser igual à chave em MapConfig.ResourceMarkers.Counts.

	Template     : nome do modelo em ServerStorage > ResourceModels
	Tool/MinTier : ferramenta exigida e nível mínimo (Tool = nil -> coleta com as mãos)
	GatherTime   : segundos base (dividido por Tool.Speed)
	Rewards      : lista de drops { Item, Min, Max, Chance (opcional, padrão 1) }
	RespawnTime  : segundos para reaparecer
]]
ResourceConfig.Nodes = {
	Tree = {
		DisplayName = "Palmeira", Template = "Tree", ActionText = "Cortar", ActionLabel = "Cortando palmeira...",
		Tool = "Axe", MinTier = 1, GatherTime = 3.5, RespawnTime = 60, MaxDistance = 12,
		Rewards = {
			{ Item = "Wood", Min = 3, Max = 5 },
			{ Item = "Fiber", Min = 1, Max = 2, Chance = 0.3 },
			{ Item = "Coconut", Min = 1, Max = 2, Chance = 0.3 },
		},
		ShakeDegrees = 2.5, HitHeight = 3, PromptHeight = 2.5,
		Particle = { Color = Color3.fromRGB(150, 105, 60), Count = 8, Size = 0.5, Speed = 9 },
	},
	Rock = {
		DisplayName = "Pedra", Template = "Rock", ActionText = "Quebrar", ActionLabel = "Quebrando pedra...",
		Tool = "Pickaxe", MinTier = 1, GatherTime = 4, RespawnTime = 75, MaxDistance = 12,
		Rewards = {
			{ Item = "Stone", Min = 2, Max = 4 },
		},
		ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2,
		Particle = { Color = Color3.fromRGB(150, 155, 165), Count = 8, Size = 0.4, Speed = 10 },
	},
	OreIron = {
		DisplayName = "Minério de Ferro", Template = "OreIron", ActionText = "Minerar", ActionLabel = "Minerando ferro...",
		Tool = "Pickaxe", MinTier = 1, GatherTime = 5, RespawnTime = 120, MaxDistance = 12,
		Rewards = {
			{ Item = "IronOre", Min = 1, Max = 3 },
			{ Item = "Stone", Min = 1, Max = 2, Chance = 0.5 },
		},
		ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2,
		Particle = { Color = Color3.fromRGB(200, 120, 80), Count = 10, Size = 0.35, Speed = 11 },
	},
	OreGold = {
		DisplayName = "Minério de Ouro", Template = "OreGold", ActionText = "Minerar", ActionLabel = "Minerando ouro...",
		Tool = "Pickaxe", MinTier = 2, GatherTime = 7, RespawnTime = 180, MaxDistance = 12,
		Rewards = {
			{ Item = "GoldOre", Min = 1, Max = 2 },
		},
		ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2,
		Particle = { Color = Color3.fromRGB(250, 215, 90), Count = 12, Size = 0.35, Speed = 12 },
	},
	Bush = {
		DisplayName = "Arbusto", Template = "Bush", ActionText = "Colher", ActionLabel = "Colhendo fibras...",
		Tool = nil, MinTier = 1, GatherTime = 1.5, RespawnTime = 40, MaxDistance = 10,
		Rewards = {
			{ Item = "Fiber", Min = 2, Max = 3 },
		},
		ShakeDegrees = 3, HitHeight = 1.2, PromptHeight = 1.5,
		Particle = { Color = Color3.fromRGB(100, 170, 80), Count = 6, Size = 0.4, Speed = 7 },
	},
}

ResourceConfig.Inventory = {
	BaseCapacity = 100,
}

ResourceConfig.ToolUpgradeCosts = {
	Axe = {
		[2] = { Wood = 30, Stone = 20, IronOre = 10 },
		[3] = { Wood = 60, Stone = 40, IronOre = 25, GoldOre = 5 },
	},

	Pickaxe = {
		[2] = { Wood = 25, Stone = 30, IronOre = 15 },
		[3] = { Wood = 50, Stone = 50, IronOre = 30, GoldOre = 8 },
	},
}


return ResourceConfig