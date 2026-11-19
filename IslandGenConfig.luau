--[[
	IslandGenConfig (v2)
	Local: ReplicatedStorage > Modules > IslandGenConfig

	Tudo que dá pra ajustar fica aqui: tamanho da ilha central, distância das ilhas
	dos jogadores, tempo de preparo (30s), recursos, poços e eventos.
]]

local IslandGenConfig = {}

-- 0 = ilha nova a cada servidor. Coloque um número para ter sempre a mesma ilha.
IslandGenConfig.Seed = 0

IslandGenConfig.Map = {
	Radius = 620,        -- raio médio da ilha central (235 -> 340 -> 480 -> 620). Aumente/diminua à vontade.
	TopRel = 156,        -- altura máxima gerada acima do nível do mar (múltiplo de 4)
	Chunk = 32,          -- voxels por pedaço escrito (yield entre pedaços)
	MountainHeight = 70, -- altura das cordilheiras
	PeakBonus = 34,      -- pico principal extra
	BeachMaxHeight = 4.5,-- até aqui é areia
	RockLine = 46,       -- acima disso vira pedra
	SnowLine = 80,       -- picos nevados
}

-- Distâncias do mundo (aplicadas ao MapConfig pelo MapConfigPatch)
IslandGenConfig.World = {
	BridgeGap = 100,   -- mar entre a costa da ilha central e as ilhas dos jogadores (mais longe que o original, mas não tanto)
	LobbyGap = 80,     -- espaço entre a ilha central e o lobby
	OceanMargin = 160, -- sobra de oceano além da ilha mais distante
	OceanDepth = 70,   -- profundidade do mar (mar mais fundo). O MapConfig só aumenta, nunca diminui.
	PlayerIslandScale = 1.6, -- as 12 ilhas dos jogadores ficam 60% maiores (raio e área de construção)
	LobbyScale = 1.3,
}

-- Pontes: removidas. Os jogadores atravessam o oceano nadando (futuramente de barco).
IslandGenConfig.Bridges = {
	Enabled = false,
}

-- Mar infinito: planos de água gigantes além do oceano + neblina no horizonte
IslandGenConfig.Sea = {
	Enabled = true,
	Extent = 14000,  -- até onde os planos de água se estendem além da borda do oceano
	FogStart = 900,
	FogEnd = 7000,
}

-- Vulcão (aparece sozinho na geração; o script de erupção você coloca depois)
IslandGenConfig.Volcano = {
	Enabled = true,
	RadiusScale = 0.30,   -- raio da base = 30% do raio da ilha
	Height = 118,         -- altura do cone acima do terreno
	CraterScale = 0.22,   -- raio da cratera em relação à base
	CraterDepth = 28,
	LavaDamage = 25,      -- dano por segundo ao tocar na lava (0 = sem dano)
	DistanceScale = 0.42, -- distância do centro da ilha (em frações do raio)
}

-- Fase de preparo: o jogador fica preso na própria ilha antes de poder ir para a central
IslandGenConfig.Prep = {
	Seconds = 30,
	GateHeight = 12,        -- altura da barreira na ponte
	ConfineMargin = 2,      -- tolerância além da borda da ilha (nadar para fora = volta pro spawn)
	RelockOnReconnect = false,
}

IslandGenConfig.Variants = 3 -- quantos visuais diferentes por tipo de árvore/pedra/arbusto

-- Faixas de altura (Y acima do nível do mar) usadas para decidir onde cada coisa nasce
IslandGenConfig.Zones = {
	Beach    = { 1.2, 4.4 },
	Shore    = { 1.5, 9 },
	Lowland  = { 4.5, 20 },
	Hills    = { 20, 46 },
	Highland = { 32, 90 },
	Mountain = { 46, 140 },
	Land     = { 1.8, 140 },
	Volcano  = { 0, 999 }, -- especial: ao redor do vulcão (ignora a altura)
}

-- Quantidades para ilha de raio 235. O gerador multiplica pela área real da ilha.
IslandGenConfig.CountMultiplier = 0.2
IslandGenConfig.BaseRadius = 235

-- Node = chave de ResourceConfig.Nodes | Zone = faixa acima | Clump = nasce em "florestas"
IslandGenConfig.Scatter = {
	{ Node = "Tree",         Count = 55, Zone = "Shore",    MinDist = 12, Clump = true },
	{ Node = "BananaTree",   Count = 20, Zone = "Lowland",  MinDist = 10, Clump = true },
	{ Node = "OakTree",      Count = 40, Zone = "Lowland",  MinDist = 15, Clump = true },
	{ Node = "AppleTree",    Count = 22, Zone = "Lowland",  MinDist = 14 },
	{ Node = "PineTree",     Count = 50, Zone = "Hills",    MinDist = 11, Clump = true },
	{ Node = "IronwoodTree", Count = 8,  Zone = "Highland", MinDist = 25 },
	{ Node = "Bush",         Count = 60, Zone = "Land",     MinDist = 7 },
	{ Node = "BerryBush",    Count = 35, Zone = "Lowland",  MinDist = 9 },
	{ Node = "HerbBush",     Count = 16, Zone = "Lowland",  MinDist = 12 },
	{ Node = "Rock",         Count = 55, Zone = "Land",     MinDist = 9,  MinNormalY = 0.6 },
	{ Node = "OreIron",      Count = 28, Zone = "Hills",    MinDist = 14, MinNormalY = 0.55 },
	{ Node = "OreCoal",      Count = 18, Zone = "Hills",    MinDist = 14, MinNormalY = 0.55 },
	{ Node = "OreGold",      Count = 12, Zone = "Mountain", MinDist = 18, MinNormalY = 0.5 },
	{ Node = "Driftwood",    Count = 22, Zone = "Beach",    MinDist = 8 },
	-- novos recursos
	{ Node = "Mushroom",     Count = 24, Zone = "Lowland",  MinDist = 8,  Clump = true },
	{ Node = "MushroomRed",  Count = 12, Zone = "Lowland",  MinDist = 9,  Clump = true },
	{ Node = "MushroomBlue", Count = 8,  Zone = "Hills",    MinDist = 10, Clump = true },
	{ Node = "ClayDeposit",  Count = 14, Zone = "Shore",    MinDist = 14 },
	{ Node = "ShellPile",    Count = 26, Zone = "Beach",    MinDist = 9 },
	{ Node = "Beehive",      Count = 12, Zone = "Lowland",  MinDist = 22 },
	{ Node = "OreCopper",    Count = 20, Zone = "Hills",    MinDist = 14, MinNormalY = 0.55 },
	{ Node = "OreCrystal",   Count = 7,  Zone = "Mountain", MinDist = 24, MinNormalY = 0.45 },
	{ Node = "SulfurVent",   Count = 12, Zone = "Volcano",  MinDist = 12, MinNormalY = 0.4 },
	{ Node = "ObsidianRock", Count = 12, Zone = "Volcano",  MinDist = 12, MinNormalY = 0.4 },
}

IslandGenConfig.Wells = {
	Count = 9,
	MinSpacing = 130,
	MaxWater = 100,
	DrinkAmount = 25,        -- quanto cada uso tira do poço
	RefillPerSecond = 0.4,   -- recarga natural
	PromptDistance = 10,
	PromptKey = Enum.KeyCode.G, -- (F já é "comer coco")
}

IslandGenConfig.Events = {
	FirstDelay = 150,   -- segundos até o 1º evento
	IntervalMin = 240,  -- entre eventos
	IntervalMax = 360,
	Weights = { SupplyDrop = 3, Meteor = 2, Storm = 2, FruitBloom = 2, Drought = 1 },

	SupplyDrop = {
		FallTime = 9,
		Lifetime = 240,
		Loot = {
			{ Item = "Wood",    Min = 10, Max = 20 },
			{ Item = "Stone",   Min = 10, Max = 20 },
			{ Item = "Fiber",   Min = 6,  Max = 12 },
			{ Item = "IronOre", Min = 5,  Max = 10 },
			{ Item = "Apple",   Min = 3,  Max = 6 },
			{ Item = "Coconut", Min = 2,  Max = 5 },
			{ Item = "GoldOre", Min = 1,  Max = 3, Chance = 0.4 },
		},
	},
	Meteor = { Warning = 12, FallTime = 2.5, Damage = 35, DamageRadius = 14, OreCount = 6, OreLifetime = 600 },
	Storm = { Duration = 90, StrikeMin = 6, StrikeMax = 14, StrikeDamage = 25 },
	FruitBloom = { Duration = 150, Multiplier = 2 },
	Drought = { Duration = 100 },
}

return IslandGenConfig

