--[[
	EventsConfig
	Local: ReplicatedStorage > Modules > EventsConfig   (ModuleScript)

	Tudo dos eventos da ilha: frequência, dificuldade, alcance, dano e duração.
	O IslandEvents lê este arquivo (a seção Events do IslandGenConfig não é mais usada).
]]

local EventsConfig = {}

-- Um evento a cada X segundos (sorteado entre Min e Max)
EventsConfig.FirstDelay = 150
EventsConfig.IntervalMin = 200
EventsConfig.IntervalMax = 320

----------------------------------------------------------------------
-- Dificuldade progressiva
-- Scale = 1 + DayRamp*(dia-1) + PlayerRamp*(jogadores-1), limitado a Max.
-- O Scale multiplica dano, quantidade de projéteis e alcance dos eventos,
-- e encurta o intervalo entre eventos.
----------------------------------------------------------------------
EventsConfig.Difficulty = {
	DayRamp = 0.12,        -- +12% por dia de jogo
	PlayerRamp = 0.03,     -- +3% por jogador extra
	Max = 2.6,
	IntervalShrink = 0.2,  -- intervalo / (1 + 0.2*(Scale-1))
	RangeGrowth = 0.35,    -- alcance (raios) cresce 35% do que o Scale cresce
}

-- Peso de sorteio de cada evento
EventsConfig.Weights = {
	SupplyDrop = 3,
	Meteor = 2,
	MeteorShower = 2,
	Storm = 2,
	FruitBloom = 2,
	Drought = 1.5,
	VolcanoEruption = 2.5,
	Earthquake = 2,
	TidalWave = 1.5,
	ThickFog = 1,
}

-- Só pode ser sorteado a partir deste dia de jogo
EventsConfig.MinDay = {
	VolcanoEruption = 2,
	Earthquake = 2,
	MeteorShower = 3,
	TidalWave = 3,
}

----------------------------------------------------------------------
-- 📦 Caixa de suprimentos
----------------------------------------------------------------------
EventsConfig.SupplyDrop = {
	FallTime = 11,
	Lifetime = 300,
	HoldDuration = 2.5,    -- segundos segurando para abrir (dá tempo de disputa)
	SecondCrateScale = 1.5, -- com Scale >= isto cai uma 2ª caixa
	ThirdCrateScale = 2.2,
	Loot = {
		{ Item = "Wood",       Min = 10, Max = 20 },
		{ Item = "Stone",      Min = 10, Max = 20 },
		{ Item = "Fiber",      Min = 6,  Max = 12 },
		{ Item = "IronOre",    Min = 5,  Max = 10 },
		{ Item = "Apple",      Min = 3,  Max = 6 },
		{ Item = "Coconut",    Min = 2,  Max = 5 },
		{ Item = "Honey",      Min = 1,  Max = 3, Chance = 0.5 },
		{ Item = "CopperOre",  Min = 3,  Max = 6, Chance = 0.6 },
		{ Item = "GoldOre",    Min = 1,  Max = 3, Chance = 0.4 },
		{ Item = "Crystal",    Min = 1,  Max = 2, Chance = 0.15 },
	},
}

----------------------------------------------------------------------
-- ☄️ Meteoro (um grande) e chuva de meteoros (vários menores)
----------------------------------------------------------------------
EventsConfig.Meteor = {
	Warning = 10, FallTime = 2.2, Size = 14, Radius = 24, Damage = 55, Knock = 70,
	OreCount = 7, OreLifetime = 600,
}

EventsConfig.MeteorShower = {
	Count = 8,                 -- x Scale
	Interval = { 0.9, 2.2 },   -- segundos entre meteoros
	Warning = 3.5, FallTime = 1.6, Size = 7, Radius = 14, Damage = 32, Knock = 45,
	TargetPlayerChance = 0.45, -- chance de um meteoro ser mirado perto de um jogador
	TargetSpread = 55,
	OreEvery = 2,              -- a cada 2 impactos nasce um minério
	OreLifetime = 600,
}

----------------------------------------------------------------------
-- ⛈️ Tempestade
----------------------------------------------------------------------
EventsConfig.Storm = {
	Duration = 110,
	StrikeMin = 3.0, StrikeMax = 7.5,
	Warning = 1.3,              -- aviso no chão antes do raio cair
	StrikeRadius = 11, StrikeDamage = 42,
	TargetPlayerChance = 0.55, TargetSpread = 45,
	SpeedMultiplier = 0.92,     -- chão molhado
	WellRefillMultiplier = 3,
}

----------------------------------------------------------------------
-- 🌸 Floração e ☀️ onda de calor (seca)
----------------------------------------------------------------------
EventsConfig.FruitBloom = { Duration = 150, Multiplier = 2 }
EventsConfig.Drought = { Duration = 110, ThirstMultiplier = 2.2 }

----------------------------------------------------------------------
-- 🌋 Erupção do vulcão
----------------------------------------------------------------------
EventsConfig.Volcano = {
	WarningTime = 25,        -- tremores antes de entrar em erupção
	EruptionTime = 55,       -- duração da erupção
	VolleyInterval = 3.2,    -- segundos entre rajadas de bombas
	BombsPerVolley = 3,      -- x Scale
	BombFlight = 3.4,        -- tempo de voo da bomba
	BombRange = 2.3,         -- alcance das bombas (x raio do vulcão)
	BombRadius = 15, BombDamage = 42, BombKnock = 55,
	PoolTime = 8, PoolDps = 14,   -- poça de lava que fica onde a bomba cai
	Flows = 2,               -- rios de lava (x Scale, máx MaxFlows)
	MaxFlows = 5,
	FlowSegments = 48,       -- comprimento do rio (x7 studs); cresce com a dificuldade
	FlowStep = 7,
	FlowStepTime = 0.4,      -- velocidade com que o rio avança
	FlowLife = 40,           -- tempo que a lava fica quente
	LavaDps = 30,            -- dano por segundo andando na lava
	ShockDamage = 30,        -- onda de choque no início da erupção (perto da cratera)
	AshStaminaRegen = 0.5,   -- cinzas: stamina regenera pela metade
	AshSpeed = 0.95,
	RewardNodes = 6,         -- obsidiana/enxofre/cristal que ficam depois
	RewardLifetime = 900,
}

----------------------------------------------------------------------
-- 🌍 Terremoto
----------------------------------------------------------------------
EventsConfig.Earthquake = {
	Duration = 14,
	Rockslides = 4,          -- x Scale
	BouldersPerSlide = 4,
	BoulderDamage = 38,
	BoulderLifetime = 28,
	WellWaterLoss = 0.5,     -- poços perdem metade da água
	RewardNodes = 4,
	RewardLifetime = 900,
}

----------------------------------------------------------------------
-- 🌊 Onda gigante (vem do oceano e bate na costa; pega quem está na praia ou nadando)
----------------------------------------------------------------------
EventsConfig.TidalWave = {
	Warning = 22,
	Speed = 58,
	Width = 900, Height = 24, Depth = 16,
	Damage = 38, Push = 75, Lift = 38,
}

----------------------------------------------------------------------
-- 🌫️ Névoa densa
----------------------------------------------------------------------
EventsConfig.ThickFog = { Duration = 100 }

return EventsConfig

