--[[
	ResourceConfigAdditions
	Local: ReplicatedStorage > Modules > ResourceConfigAdditions

	Novos itens + novas árvores/arbustos/minério, no MESMO formato do seu ResourceConfig v3.
	Uso: no final do ResourceConfig.luau, ANTES do "return ResourceConfig", adicione:

		require(script.Parent.ResourceConfigAdditions)(ResourceConfig)   -- (ModuleScript ao lado do ResourceConfig)
]]

local Additions = {}

Additions.Items = {
	Hardwood = {
		DisplayName = "Madeira de Lei", Emoji = "🪵",
		Description = "Madeira dura e rara, vinda do carvalho e da árvore-de-ferro.",
		MaxStack = 999, Order = 7, Color = Color3.fromRGB(110, 75, 50),
	},
	Resin = {
		DisplayName = "Resina", Emoji = "🟠",
		Description = "Seiva grudenta do pinheiro. Útil para cola e tochas.",
		MaxStack = 999, Order = 8, Color = Color3.fromRGB(230, 160, 60),
	},
	Coal = {
		DisplayName = "Carvão", Emoji = "⚫",
		Description = "Combustível para fornalhas e fogueiras.",
		MaxStack = 999, Order = 9, Color = Color3.fromRGB(40, 40, 46),
	},
	Apple = {
		DisplayName = "Maçã", Emoji = "🍎",
		Description = "Fruta doce que recupera 12 pontos de fome.",
		MaxStack = 999, Order = 10, Color = Color3.fromRGB(205, 45, 45),
		Food = true, HungerRestore = 12,
	},
	Banana = {
		DisplayName = "Banana", Emoji = "🍌",
		Description = "Fruta energética que recupera 15 pontos de fome.",
		MaxStack = 999, Order = 11, Color = Color3.fromRGB(242, 212, 60),
		Food = true, HungerRestore = 15,
	},
	Berry = {
		DisplayName = "Frutinha Silvestre", Emoji = "🫐",
		Description = "Frutinhas pequenas que recuperam 6 pontos de fome.",
		MaxStack = 999, Order = 12, Color = Color3.fromRGB(200, 60, 80),
		Food = true, HungerRestore = 6,
	},
	Herb = {
		DisplayName = "Erva Medicinal", Emoji = "🌿",
		Description = "Planta que ajuda a recuperar vida.",
		MaxStack = 999, Order = 13, Color = Color3.fromRGB(110, 190, 120),
		HealRestore = 15,
	},
}

local function particle(color, count, size, speed)
	return { Color = color, Count = count, Size = size, Speed = speed }
end

Additions.Nodes = {
	-- Carvalho: muita madeira, chance de madeira de lei
	OakTree = {
		DisplayName = "Carvalho", Template = "OakTree", ActionText = "Cortar", ActionLabel = "Cortando carvalho...",
		Tool = "Axe", MinTier = 1, GatherTime = 5, RespawnTime = 90, MaxDistance = 12,
		Rewards = {
			{ Item = "Wood", Min = 5, Max = 8 },
			{ Item = "Hardwood", Min = 1, Max = 2, Chance = 0.35 },
			{ Item = "Fiber", Min = 1, Max = 2, Chance = 0.2 },
		},
		ShakeDegrees = 2, HitHeight = 3, PromptHeight = 3,
		Particle = particle(Color3.fromRGB(150, 105, 60), 8, 0.5, 9),
	},
	-- Pinheiro: madeira + resina
	PineTree = {
		DisplayName = "Pinheiro", Template = "PineTree", ActionText = "Cortar", ActionLabel = "Cortando pinheiro...",
		Tool = "Axe", MinTier = 1, GatherTime = 4, RespawnTime = 80, MaxDistance = 12,
		Rewards = {
			{ Item = "Wood", Min = 4, Max = 6 },
			{ Item = "Resin", Min = 1, Max = 2, Chance = 0.5 },
		},
		ShakeDegrees = 1.5, HitHeight = 3, PromptHeight = 3,
		Particle = particle(Color3.fromRGB(150, 105, 60), 8, 0.5, 9),
	},
	-- Macieira: maçãs
	AppleTree = {
		DisplayName = "Macieira", Template = "AppleTree", ActionText = "Colher", ActionLabel = "Colhendo maçãs...",
		Tool = "Axe", MinTier = 1, GatherTime = 3.5, RespawnTime = 75, MaxDistance = 12,
		Rewards = {
			{ Item = "Apple", Min = 2, Max = 4 },
			{ Item = "Wood", Min = 2, Max = 4 },
		},
		ShakeDegrees = 3, HitHeight = 3, PromptHeight = 3,
		Particle = particle(Color3.fromRGB(205, 45, 45), 8, 0.4, 8),
	},
	-- Bananeira: bananas + fibra
	BananaTree = {
		DisplayName = "Bananeira", Template = "BananaTree", ActionText = "Colher", ActionLabel = "Colhendo bananas...",
		Tool = "Axe", MinTier = 1, GatherTime = 3, RespawnTime = 70, MaxDistance = 12,
		Rewards = {
			{ Item = "Banana", Min = 3, Max = 5 },
			{ Item = "Fiber", Min = 2, Max = 4 },
			{ Item = "Wood", Min = 1, Max = 2, Chance = 0.3 },
		},
		ShakeDegrees = 3.5, HitHeight = 2.5, PromptHeight = 2.5,
		Particle = particle(Color3.fromRGB(242, 212, 60), 8, 0.4, 8),
	},
	-- Árvore-de-ferro: rara, só com machado de ferro
	IronwoodTree = {
		DisplayName = "Árvore-de-Ferro", Template = "IronwoodTree", ActionText = "Cortar", ActionLabel = "Cortando árvore-de-ferro...",
		Tool = "Axe", MinTier = 2, GatherTime = 8, RespawnTime = 240, MaxDistance = 12,
		Rewards = {
			{ Item = "Hardwood", Min = 2, Max = 4 },
			{ Item = "Wood", Min = 3, Max = 4 },
			{ Item = "IronOre", Min = 1, Max = 1, Chance = 0.25 },
		},
		ShakeDegrees = 1, HitHeight = 3, PromptHeight = 3.5,
		Particle = particle(Color3.fromRGB(120, 120, 135), 10, 0.45, 10),
	},
	-- Arbustos
	BerryBush = {
		DisplayName = "Arbusto de Frutinhas", Template = "BerryBush", ActionText = "Colher", ActionLabel = "Colhendo frutinhas...",
		Tool = nil, MinTier = 1, GatherTime = 1.8, RespawnTime = 50, MaxDistance = 10,
		Rewards = {
			{ Item = "Berry", Min = 2, Max = 4 },
			{ Item = "Fiber", Min = 1, Max = 1, Chance = 0.3 },
		},
		ShakeDegrees = 3, HitHeight = 1.2, PromptHeight = 1.5,
		Particle = particle(Color3.fromRGB(200, 60, 80), 6, 0.3, 7),
	},
	HerbBush = {
		DisplayName = "Erva Medicinal", Template = "HerbBush", ActionText = "Colher", ActionLabel = "Colhendo ervas...",
		Tool = nil, MinTier = 1, GatherTime = 1.5, RespawnTime = 90, MaxDistance = 10,
		Rewards = { { Item = "Herb", Min = 1, Max = 3 } },
		ShakeDegrees = 2, HitHeight = 1, PromptHeight = 1.3,
		Particle = particle(Color3.fromRGB(110, 190, 120), 6, 0.3, 7),
	},
	-- Mineração
	OreCoal = {
		DisplayName = "Carvão", Template = "OreCoal", ActionText = "Minerar", ActionLabel = "Minerando carvão...",
		Tool = "Pickaxe", MinTier = 1, GatherTime = 4.5, RespawnTime = 100, MaxDistance = 12,
		Rewards = {
			{ Item = "Coal", Min = 2, Max = 4 },
			{ Item = "Stone", Min = 1, Max = 2, Chance = 0.4 },
		},
		ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2,
		Particle = particle(Color3.fromRGB(60, 60, 66), 10, 0.35, 10),
	},
	-- Praia
	Driftwood = {
		DisplayName = "Madeira de Praia", Template = "Driftwood", ActionText = "Pegar", ActionLabel = "Pegando madeira...",
		Tool = nil, MinTier = 1, GatherTime = 1.5, RespawnTime = 60, MaxDistance = 10,
		Rewards = {
			{ Item = "Wood", Min = 1, Max = 2 },
			{ Item = "Fiber", Min = 1, Max = 1, Chance = 0.2 },
		},
		ShakeDegrees = 1, HitHeight = 0.8, PromptHeight = 1.2,
		Particle = particle(Color3.fromRGB(165, 145, 120), 5, 0.3, 6),
	},
}


-- ===== NOVOS RECURSOS (v2) =====
Additions.Items.CopperOre = {
	DisplayName = "Minério de Cobre", Emoji = "🟠",
	Description = "Metal avermelhado, bom para ferramentas e melhorias da mochila.",
	MaxStack = 999, Order = 14, Color = Color3.fromRGB(214, 128, 60),
}
Additions.Items.Crystal = {
	DisplayName = "Cristal", Emoji = "💎",
	Description = "Cristal raro que brilha de dentro para fora. Valioso.",
	MaxStack = 999, Order = 15, Color = Color3.fromRGB(150, 110, 255),
}
Additions.Items.Sulfur = {
	DisplayName = "Enxofre", Emoji = "🟡",
	Description = "Pó amarelo que sai do vulcão. Cheira mal, mas é útil.",
	MaxStack = 999, Order = 16, Color = Color3.fromRGB(232, 208, 62),
}
Additions.Items.Obsidian = {
	DisplayName = "Obsidiana", Emoji = "🖤",
	Description = "Vidro vulcânico negro e afiado.",
	MaxStack = 999, Order = 17, Color = Color3.fromRGB(40, 34, 56),
}
Additions.Items.Mushroom = {
	DisplayName = "Cogumelo Marrom", Emoji = "🍄",
	Description = "Cogumelo comum da floresta. Quase sempre seguro.",
	MaxStack = 999, Order = 18, Color = Color3.fromRGB(200, 60, 50),
	Food = true, HungerRestore = 8,
}
Additions.Items.Clay = {
	DisplayName = "Argila", Emoji = "🧱",
	Description = "Barro úmido, ótimo para construir e fazer tijolos.",
	MaxStack = 999, Order = 19, Color = Color3.fromRGB(176, 112, 82),
}
Additions.Items.Shell = {
	DisplayName = "Concha", Emoji = "🐚",
	Description = "Concha bonita que a maré deixou na areia.",
	MaxStack = 999, Order = 20, Color = Color3.fromRGB(245, 240, 232),
}
Additions.Items.Honey = {
	DisplayName = "Mel", Emoji = "🍯",
	Description = "Mel doce e nutritivo.",
	MaxStack = 999, Order = 21, Color = Color3.fromRGB(222, 170, 60),
	Food = true, HungerRestore = 20,
}

Additions.Items.MushroomRed = {
	DisplayName = "Cogumelo Vermelho", Emoji = "🍄",
	Description = "Chamativo e perigoso. Pode envenenar... ou não.",
	MaxStack = 999, Order = 22, Color = Color3.fromRGB(215, 50, 50),
	Food = true,
}
Additions.Items.MushroomBlue = {
	DisplayName = "Cogumelo Azul", Emoji = "🍄",
	Description = "Brilha no escuro. Costuma dar muita energia.",
	MaxStack = 999, Order = 23, Color = Color3.fromRGB(90, 160, 255),
	Food = true,
}

Additions.Nodes.MushroomRed = {
	DisplayName = "Cogumelos Vermelhos", Template = "MushroomRed", ActionText = "Colher", ActionLabel = "Colhendo cogumelos...",
	Tool = nil, MinTier = 1, GatherTime = 1.6, RespawnTime = 90, MaxDistance = 10,
	Rewards = { { Item = "MushroomRed", Min = 1, Max = 3 } },
	ShakeDegrees = 2, HitHeight = 0.8, PromptHeight = 1.2,
	Particle = particle(Color3.fromRGB(215, 50, 50), 5, 0.3, 6),
}
Additions.Nodes.MushroomBlue = {
	DisplayName = "Cogumelos Azuis", Template = "MushroomBlue", ActionText = "Colher", ActionLabel = "Colhendo cogumelos...",
	Tool = nil, MinTier = 1, GatherTime = 1.8, RespawnTime = 120, MaxDistance = 10,
	Rewards = { { Item = "MushroomBlue", Min = 1, Max = 2 } },
	ShakeDegrees = 2, HitHeight = 0.8, PromptHeight = 1.2,
	Particle = particle(Color3.fromRGB(90, 160, 255), 5, 0.3, 6),
}

Additions.Nodes.Mushroom = {
	DisplayName = "Cogumelos", Template = "Mushroom", ActionText = "Colher", ActionLabel = "Colhendo cogumelos...",
	Tool = nil, MinTier = 1, GatherTime = 1.6, RespawnTime = 70, MaxDistance = 10,
	Rewards = { { Item = "Mushroom", Min = 2, Max = 4 } },
	ShakeDegrees = 2, HitHeight = 0.8, PromptHeight = 1.2,
	Particle = particle(Color3.fromRGB(200, 60, 50), 5, 0.3, 6),
}
Additions.Nodes.ClayDeposit = {
	DisplayName = "Depósito de Argila", Template = "ClayDeposit", ActionText = "Cavar", ActionLabel = "Cavando argila...",
	Tool = "Pickaxe", MinTier = 1, GatherTime = 3, RespawnTime = 100, MaxDistance = 11,
	Rewards = { { Item = "Clay", Min = 3, Max = 6 } },
	ShakeDegrees = 0.5, HitHeight = 1, PromptHeight = 1.8,
	Particle = particle(Color3.fromRGB(176, 112, 82), 8, 0.4, 8),
}
Additions.Nodes.ShellPile = {
	DisplayName = "Conchas", Template = "ShellPile", ActionText = "Pegar", ActionLabel = "Pegando conchas...",
	Tool = nil, MinTier = 1, GatherTime = 1.2, RespawnTime = 80, MaxDistance = 10,
	Rewards = {
		{ Item = "Shell", Min = 2, Max = 4 },
		{ Item = "Fiber", Min = 1, Max = 1, Chance = 0.15 },
	},
	ShakeDegrees = 0, HitHeight = 0.5, PromptHeight = 1,
	Particle = particle(Color3.fromRGB(245, 240, 232), 5, 0.25, 6),
}
Additions.Nodes.Beehive = {
	DisplayName = "Colmeia", Template = "Beehive", ActionText = "Coletar mel", ActionLabel = "Coletando mel...",
	Tool = nil, MinTier = 1, GatherTime = 4.5, RespawnTime = 150, MaxDistance = 11,
	Rewards = { { Item = "Honey", Min = 1, Max = 3 } },
	ShakeDegrees = 1.5, HitHeight = 3.5, PromptHeight = 3.5,
	Particle = particle(Color3.fromRGB(222, 170, 60), 8, 0.3, 8),
}
Additions.Nodes.OreCopper = {
	DisplayName = "Cobre", Template = "OreCopper", ActionText = "Minerar", ActionLabel = "Minerando cobre...",
	Tool = "Pickaxe", MinTier = 2, GatherTime = 5.5, RespawnTime = 130, MaxDistance = 12,
	Rewards = {
		{ Item = "CopperOre", Min = 2, Max = 4 },
		{ Item = "Stone", Min = 1, Max = 2, Chance = 0.4 },
	},
	ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2,
	Particle = particle(Color3.fromRGB(214, 128, 60), 10, 0.35, 10),
}
Additions.Nodes.OreCrystal = {
	DisplayName = "Cristal", Template = "OreCrystal", ActionText = "Minerar", ActionLabel = "Extraindo cristal...",
	Tool = "Pickaxe", MinTier = 3, GatherTime = 9, RespawnTime = 300, MaxDistance = 12,
	Rewards = {
		{ Item = "Crystal", Min = 1, Max = 2 },
		{ Item = "Stone", Min = 1, Max = 2, Chance = 0.3 },
	},
	ShakeDegrees = 0.5, HitHeight = 2.5, PromptHeight = 3,
	Particle = particle(Color3.fromRGB(150, 110, 255), 12, 0.4, 12),
}
Additions.Nodes.SulfurVent = {
	DisplayName = "Enxofre", Template = "SulfurVent", ActionText = "Coletar", ActionLabel = "Coletando enxofre...",
	Tool = "Pickaxe", MinTier = 1, GatherTime = 4, RespawnTime = 110, MaxDistance = 11,
	Rewards = { { Item = "Sulfur", Min = 2, Max = 5 } },
	ShakeDegrees = 0.8, HitHeight = 1.8, PromptHeight = 2.2,
	Particle = particle(Color3.fromRGB(240, 225, 90), 10, 0.35, 9),
}
Additions.Nodes.ObsidianRock = {
	DisplayName = "Obsidiana", Template = "ObsidianRock", ActionText = "Minerar", ActionLabel = "Quebrando obsidiana...",
	Tool = "Pickaxe", MinTier = 2, GatherTime = 6.5, RespawnTime = 200, MaxDistance = 12,
	Rewards = {
		{ Item = "Obsidian", Min = 1, Max = 3 },
		{ Item = "Stone", Min = 1, Max = 2, Chance = 0.3 },
	},
	ShakeDegrees = 0.6, HitHeight = 2, PromptHeight = 2.5,
	Particle = particle(Color3.fromRGB(60, 50, 80), 10, 0.35, 10),
}

-- Tipos que o IslandGenerator espalha pela ilha (cada um ganha modelo próprio e variantes)
local ISLAND_NODES = {
	"Tree", "OakTree", "PineTree", "AppleTree", "BananaTree", "IronwoodTree",
	"Bush", "BerryBush", "HerbBush", "Rock", "OreIron", "OreGold", "OreCoal", "Driftwood",
	"Mushroom", "MushroomRed", "MushroomBlue", "ClayDeposit", "ShellPile", "Beehive", "OreCopper", "OreCrystal", "SulfurVent", "ObsidianRock",
}

return function(ResourceConfig)
	local G = require(script.Parent:WaitForChild("IslandGenConfig"))

	for k, v in Additions.Items do ResourceConfig.Items[k] = v end
	for k, v in Additions.Nodes do ResourceConfig.Nodes[k] = v end

	-- Cada tipo usa o modelo "Isl_<Tipo>" (criado pelo IslandGenerator) e ganha
	-- variantes "<Tipo>_V2", "<Tipo>_V3"... com a mesma coleta e visual diferente.
	for _, base in ISLAND_NODES do
		local def = ResourceConfig.Nodes[base]
		if def then
			def.Template = "Isl_" .. base
			for i = 2, G.Variants do
				local copy = table.clone(def)
				copy.Template = "Isl_" .. base .. "_V" .. i
				ResourceConfig.Nodes[base .. "_V" .. i] = copy
			end
		end
	end
end

