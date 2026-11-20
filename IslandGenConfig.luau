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
	Radius = 1240,       -- raio médio da ilha central (era 620: 4x a ÁREA). Se a geração demorar demais, diminua.
	TopRel = 520,        -- altura máxima gerada acima do nível do mar (múltiplo de 4)
	Chunk = 32,          -- voxels por pedaço escrito (yield entre pedaços)
	MountainHeight = 160,-- altura das cordilheiras
	PeakBonus = 120,     -- pico principal extra
	BeachMaxHeight = 4.5,-- até aqui é areia
	RockLine = 110,      -- acima disso vira pedra
	SnowLine = 260,      -- picos nevados
}

-- Distâncias do mundo (aplicadas ao MapConfig pelo MapConfigPatch)
IslandGenConfig.World = {
	BridgeGap = 100,   -- mar entre a costa da ilha central e as ilhas dos jogadores (mais longe que o original, mas não tanto)
	LobbyGap = 80,     -- espaço entre a ilha central e o lobby
	OceanMargin = 1100, -- sobra de oceano além da ilha mais distante (deve ser maior que a distância da neblina)
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
	FogStart = 250,
	FogEnd = 1500,   -- a neblina esconde o outro lado da ilha e o limite do oceano
	TileColor = nil, -- nil = automático (cor da água do terreno). Se vir diferença de tom, ajuste aqui.
}

-- Vulcão (aparece sozinho na geração; o script de erupção você coloca depois)
IslandGenConfig.Volcano = {
	Enabled = true,
	RadiusScale = 0.30,   -- raio da base = 30% do raio da ilha
	Height = 420,         -- altura do cone acima do terreno (vulcão imponente)
	CraterScale = 0.22,   -- raio da cratera em relação à base
	CraterDepth = 60,
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
	Hills    = { 20, 90 },
	Highland = { 60, 260 },
	Mountain = { 90, 520 },
	Summit   = { 180, 520 },   -- cumes: as melhores recompensas
	Land     = { 1.8, 520 },
	Volcano  = { 0, 999 }, -- especial: ao redor do vulcão (ignora a altura)
}

-- Quantidades para ilha de raio 235. O gerador multiplica pela área real da ilha.
IslandGenConfig.CountMultiplier = 0.06 -- bem menos recursos: a exploração importa
IslandGenConfig.BaseRadius = 235

-- Node = chave de ResourceConfig.Nodes | Zone = faixa acima | Clump = nasce em "florestas"
IslandGenConfig.Scatter = {
	-- vegetação (abundante, bem distribuída)
	{ Node = "Tree",         Count = 55, Zone = "Shore",    MinDist = 12, Clump = true },
	{ Node = "OakTree",      Count = 40, Zone = "Lowland",  MinDist = 15, Clump = true },
	{ Node = "PineTree",     Count = 50, Zone = "Hills",    MinDist = 11, Clump = true },
	{ Node = "IronwoodTree", Count = 4,  Zone = "Highland", MinDist = 30 },
	{ Node = "Bush",         Count = 60, Zone = "Land",     MinDist = 7 },
	{ Node = "Rock",         Count = 55, Zone = "Land",     MinDist = 9,  MinNormalY = 0.6 },
	{ Node = "Driftwood",    Count = 14, Zone = "Beach",    MinDist = 8 },
	{ Node = "ShellPile",    Count = 12, Zone = "Beach",    MinDist = 9 },
	{ Node = "ClayDeposit",  Count = 6,  Zone = "Shore",    MinDist = 14 },
	-- comida (ESCASSA)
	{ Node = "BananaTree",   Count = 6,  Zone = "Lowland",  MinDist = 18, Clump = true },
	{ Node = "AppleTree",    Count = 6,  Zone = "Lowland",  MinDist = 18 },
	{ Node = "BerryBush",    Count = 8,  Zone = "Lowland",  MinDist = 14 },
	{ Node = "HerbBush",     Count = 6,  Zone = "Lowland",  MinDist = 16 },
	{ Node = "Mushroom",     Count = 8,  Zone = "Lowland",  MinDist = 10, Clump = true },
	{ Node = "MushroomRed",  Count = 4,  Zone = "Lowland",  MinDist = 12, Clump = true },
	{ Node = "MushroomBlue", Count = 3,  Zone = "Hills",    MinDist = 14, Clump = true },
	{ Node = "Beehive",      Count = 3,  Zone = "Lowland",  MinDist = 30 },
	-- minérios na superfície (POUCOS; o resto fica em cavernas e nos cumes)
	{ Node = "OreIron",      Count = 8,  Zone = "Hills",    MinDist = 22, MinNormalY = 0.55 },
	{ Node = "OreCoal",      Count = 6,  Zone = "Hills",    MinDist = 22, MinNormalY = 0.55 },
	{ Node = "OreCopper",    Count = 5,  Zone = "Highland", MinDist = 24, MinNormalY = 0.55 },
	{ Node = "OreGold",      Count = 3,  Zone = "Summit",   MinDist = 40, MinNormalY = 0.5 },
	{ Node = "OreCrystal",   Count = 2,  Zone = "Summit",   MinDist = 50, MinNormalY = 0.45 },
	-- ao redor do vulcão (quantidade fixa)
	{ Node = "SulfurVent",   Count = 8,  Zone = "Volcano",  MinDist = 16, MinNormalY = 0.4 },
	{ Node = "ObsidianRock", Count = 6,  Zone = "Volcano",  MinDist = 16, MinNormalY = 0.4 },
}

-- Cavernas: entrada natural numa encosta, túnel descendo, câmaras com minérios raros
IslandGenConfig.Caves = {
	Count = 6,
	Length = 36,             -- passos do túnel
	Step = 9,                -- studs por passo
	TunnelRadius = 7,
	ChamberEvery = 12,       -- uma câmara a cada N passos (e uma no fim)
	ChamberRadius = { 18, 28 },
	Descent = 0.9,           -- quanto o túnel desce por passo
	MinEntranceHeight = 24,
	MaxEntranceHeight = 80,
	-- minérios por câmara (cavernas concentram os recursos raros)
	OrePerChamber = { OreCrystal = 2, OreGold = 2, OreCopper = 3, OreIron = 2, ObsidianRock = 1 },
}

-- Trilhas: caminhos de inclinação suave em espiral até o cume do pico e à borda da cratera.
-- O resto das encostas é íngreme demais para subir andando (Humanoid.MaxSlopeAngle no SurvivalService).
IslandGenConfig.Trails = {
	Enabled = true,
	Width = 13,
	Turns = 1.3,
}

IslandGenConfig.Wells = {
	Count = 4,
	MinSpacing = 380,
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

