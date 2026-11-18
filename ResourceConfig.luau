
--[[
    ResourceConfig v3
    ReplicatedStorage > Modules > ResourceConfig
]]

local ResourceConfig = {}

ResourceConfig.Version = 3
ResourceConfig.GlobalYieldMultiplier = 1

ResourceConfig.Gathering = {
	DefaultMaxDistance = 12,
	DistanceTolerance = 3,
	StartCooldown = 0.4,
	SwingInterval = 0.8,
	HitDelay = 0.3,
	MinGatherTime = 0.6,
	RespawnJitter = 0.2,
	OwnerOnly = true,
	PromptKey = Enum.KeyCode.E,
}

-- ITENS DA MOCHILA
ResourceConfig.Items = {
	Wood = {
		DisplayName = "Madeira",
		Emoji = "🪵",
		Description = "Madeira resistente, utilizada para construções e ferramentas.",
		MaxStack = 999,
		Order = 1,
		Color = Color3.fromRGB(176, 128, 78),
	},

	Stone = {
		DisplayName = "Pedra",
		Emoji = "🪨",
		Description = "Pedras coletadas nas rochas da ilha.",
		MaxStack = 999,
		Order = 2,
		Color = Color3.fromRGB(140, 145, 155),
	},

	Fiber = {
		DisplayName = "Fibra",
		Emoji = "🌿",
		Description = "Material natural utilizado na fabricação de objetos.",
		MaxStack = 999,
		Order = 3,
		Color = Color3.fromRGB(120, 180, 90),
	},

	IronOre = {
		DisplayName = "Minério de Ferro",
		Emoji = "⛓️",
		Description = "Minério metálico utilizado para melhorar ferramentas.",
		MaxStack = 999,
		Order = 4,
		Color = Color3.fromRGB(190, 120, 85),
	},

	GoldOre = {
		DisplayName = "Minério de Ouro",
		Emoji = "🪙",
		Description = "Minério raro necessário para melhorias avançadas.",
		MaxStack = 999,
		Order = 5,
		Color = Color3.fromRGB(240, 200, 70),
	},

	Coconut = {
		DisplayName = "Coco",
		Emoji = "🥥",
		Description = "Fruta tropical que recupera 10 pontos de fome.",
		MaxStack = 999,
		Order = 6,
		Color = Color3.fromRGB(150, 110, 65),

		Food = true,
		HungerRestore = 10,
	},
}

-- FERRAMENTAS E NÍVEIS
ResourceConfig.Tools = {
	Axe = {
		DisplayName = "Machado",
		Emoji = "🪓",
		Description = "Utilizado para cortar árvores e coletar madeira.",

		Tiers = {
			[1] = {
				Name = "Machado de Pedra",
				Speed = 1.0,
				Yield = 1.0,
				HeadColor = Color3.fromRGB(125, 130, 138),
				HeadMaterial = Enum.Material.Slate,
			},

			[2] = {
				Name = "Machado de Ferro",
				Speed = 1.4,
				Yield = 1.25,
				HeadColor = Color3.fromRGB(175, 180, 190),
				HeadMaterial = Enum.Material.Metal,
			},

			[3] = {
				Name = "Machado Dourado",
				Speed = 1.9,
				Yield = 1.6,
				HeadColor = Color3.fromRGB(235, 195, 70),
				HeadMaterial = Enum.Material.Metal,
				HeadReflectance = 0.1,
			},
		},
	},

	Pickaxe = {
		DisplayName = "Picareta",
		Emoji = "⛏️",
		Description = "Utilizada para quebrar pedras e minerar minérios.",

		Tiers = {
			[1] = {
				Name = "Picareta de Pedra",
				Speed = 1.0,
				Yield = 1.0,
				HeadColor = Color3.fromRGB(125, 130, 138),
				HeadMaterial = Enum.Material.Slate,
			},

			[2] = {
				Name = "Picareta de Ferro",
				Speed = 1.4,
				Yield = 1.25,
				HeadColor = Color3.fromRGB(175, 180, 190),
				HeadMaterial = Enum.Material.Metal,
			},

			[3] = {
				Name = "Picareta Dourada",
				Speed = 1.9,
				Yield = 1.6,
				HeadColor = Color3.fromRGB(235, 195, 70),
				HeadMaterial = Enum.Material.Metal,
				HeadReflectance = 0.1,
			},
		},
	},
}

ResourceConfig.ToolVisual = {
	GripPos = Vector3.new(0, 0, 1.1),
	HandleLength = 3.2,
}

-- APARÊNCIA DOS RECURSOS
ResourceConfig.Visuals = {
	Trunk = {
		Color = Color3.fromRGB(128, 92, 58),
		Material = Enum.Material.Wood,
	},

	Leaf = {
		Color = Color3.fromRGB(70, 150, 72),
		Material = Enum.Material.LeafyGrass,
	},

	LeafDark = {
		Color = Color3.fromRGB(48, 118, 60),
		Material = Enum.Material.LeafyGrass,
	},

	Coconut = {
		Color = Color3.fromRGB(96, 66, 40),
		Material = Enum.Material.Wood,
	},

	Rock = {
		Color = Color3.fromRGB(122, 126, 134),
		Material = Enum.Material.Slate,
	},

	RockDark = {
		Color = Color3.fromRGB(92, 96, 106),
		Material = Enum.Material.Basalt,
	},

	OreIron = {
		Color = Color3.fromRGB(178, 106, 74),
		Material = Enum.Material.CorrodedMetal,
	},

	OreGold = {
		Color = Color3.fromRGB(236, 190, 70),
		Material = Enum.Material.Metal,
		Reflectance = 0.12,
	},

	Bush = {
		Color = Color3.fromRGB(80, 150, 70),
		Material = Enum.Material.LeafyGrass,
	},

	BushDark = {
		Color = Color3.fromRGB(56, 120, 58),
		Material = Enum.Material.LeafyGrass,
	},

	Berry = {
		Color = Color3.fromRGB(200, 60, 80),
		Material = Enum.Material.SmoothPlastic,
	},
}

-- RECURSOS COLETÁVEIS
ResourceConfig.Nodes = {
	Tree = {
		DisplayName = "Palmeira",
		Template = "Tree",
		ActionText = "Cortar",
		ActionLabel = "Cortando palmeira...",
		Tool = "Axe",
		MinTier = 1,
		GatherTime = 3.5,
		RespawnTime = 60,
		MaxDistance = 12,

		Rewards = {
			{ Item = "Wood", Min = 3, Max = 5 },
			{ Item = "Fiber", Min = 1, Max = 2, Chance = 0.3 },
			{ Item = "Coconut", Min = 1, Max = 2, Chance = 0.3 },
		},

		ShakeDegrees = 2.5,
		HitHeight = 3,
		PromptHeight = 2.5,

		Particle = {
			Color = Color3.fromRGB(150, 105, 60),
			Count = 8,
			Size = 0.5,
			Speed = 9,
		},
	},

	Rock = {
		DisplayName = "Pedra",
		Template = "Rock",
		ActionText = "Quebrar",
		ActionLabel = "Quebrando pedra...",
		Tool = "Pickaxe",
		MinTier = 1,
		GatherTime = 4,
		RespawnTime = 75,
		MaxDistance = 12,

		Rewards = {
			{ Item = "Stone", Min = 2, Max = 4 },
		},

		ShakeDegrees = 0.8,
		HitHeight = 1.8,
		PromptHeight = 2,

		Particle = {
			Color = Color3.fromRGB(150, 155, 165),
			Count = 8,
			Size = 0.4,
			Speed = 10,
		},
	},

	OreIron = {
		DisplayName = "Minério de Ferro",
		Template = "OreIron",
		ActionText = "Minerar",
		ActionLabel = "Minerando ferro...",
		Tool = "Pickaxe",
		MinTier = 1,
		GatherTime = 5,
		RespawnTime = 120,
		MaxDistance = 12,

		Rewards = {
			{ Item = "IronOre", Min = 1, Max = 3 },
			{ Item = "Stone", Min = 1, Max = 2, Chance = 0.5 },
		},

		ShakeDegrees = 0.8,
		HitHeight = 1.8,
		PromptHeight = 2,

		Particle = {
			Color = Color3.fromRGB(200, 120, 80),
			Count = 10,
			Size = 0.35,
			Speed = 11,
		},
	},

	OreGold = {
		DisplayName = "Minério de Ouro",
		Template = "OreGold",
		ActionText = "Minerar",
		ActionLabel = "Minerando ouro...",
		Tool = "Pickaxe",
		MinTier = 2,
		GatherTime = 7,
		RespawnTime = 180,
		MaxDistance = 12,

		Rewards = {
			{ Item = "GoldOre", Min = 1, Max = 2 },
		},

		ShakeDegrees = 0.8,
		HitHeight = 1.8,
		PromptHeight = 2,

		Particle = {
			Color = Color3.fromRGB(250, 215, 90),
			Count = 12,
			Size = 0.35,
			Speed = 12,
		},
	},

	Bush = {
		DisplayName = "Arbusto",
		Template = "Bush",
		ActionText = "Colher",
		ActionLabel = "Colhendo fibras...",
		Tool = nil,
		MinTier = 1,
		GatherTime = 1.5,
		RespawnTime = 40,
		MaxDistance = 10,

		Rewards = {
			{ Item = "Fiber", Min = 2, Max = 3 },
		},

		ShakeDegrees = 3,
		HitHeight = 1.2,
		PromptHeight = 1.5,

		Particle = {
			Color = Color3.fromRGB(100, 170, 80),
			Count = 6,
			Size = 0.4,
			Speed = 7,
		},
	},
}

ResourceConfig.Inventory = {
	BaseCapacity = 100,
}

-- CUSTOS DOS UPGRADES
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

require(script.Parent.ResourceConfigAdditions)(ResourceConfig)

return ResourceConfig
