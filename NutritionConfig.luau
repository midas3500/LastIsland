--[[
	NutritionConfig
	Local: ReplicatedStorage > Modules > NutritionConfig   (ModuleScript)

	Tudo de sede, saciedade, alimentos, bebidas, cogumelos e natação.
	Servidor e cliente leem este arquivo (o servidor valida, o cliente só mostra).
	Chaves de item = as mesmas de ResourceConfig.Items.
]]

local NutritionConfig = {}

----------------------------------------------------------------------
-- Sede (barra independente)
----------------------------------------------------------------------
NutritionConfig.Thirst = {
	Max = 100,
	DrainPerSecond = 0.07,   -- parado (partida mais longa)
	SprintMultiplier = 2.0,  -- correndo
	SwimMultiplier = 1.8,    -- nadando
	DamageInterval = 2,      -- desidratado (sede 0): dano a cada X segundos
	DehydrationDamage = 3,
	WellMultiplier = 1.0,    -- quanto de água o poço dá (x o valor que o poço informa)
}

----------------------------------------------------------------------
-- Saciedade: "colchão" que se esgota ANTES da fome começar a cair.
-- Quanto maior a saciedade do alimento, mais tempo o jogador fica sem sentir fome.
----------------------------------------------------------------------
NutritionConfig.Saturation = {
	Max = 100,
	DrainPerSecond = 0.35,
}

----------------------------------------------------------------------
-- Natação (consome stamina)
----------------------------------------------------------------------
NutritionConfig.Swim = {
	Speed = 13,             -- velocidade nadando normal
	SprintSpeed = 18,       -- nadando com Shift
	ExhaustedSpeed = 5,     -- sem stamina: só boia devagar
	DrainPerSecond = 2.5,   -- stamina por segundo nadando
	SprintDrainPerSecond = 6,
	-- sem regeneração de stamina enquanto estiver na água
}

----------------------------------------------------------------------
-- Efeitos (usados pelos cogumelos e por qualquer alimento)
----------------------------------------------------------------------
NutritionConfig.Effects = {
	Energy = {
		Name = "Energia", Emoji = "⚡",
		Duration = 20, StaminaRestore = 40, SpeedMultiplier = 1.25,
	},
	Nausea = {
		Name = "Náusea", Emoji = "🤢",
		Duration = 15, StaminaRegenMultiplier = 0.4, SpeedMultiplier = 0.85,
	},
	Poison = {
		Name = "Envenenamento", Emoji = "☠️",
		Duration = 12, DamagePerSecond = 2.0,
		CanKill = false, -- false = o veneno nunca deixa a vida abaixo de 1
	},
}

----------------------------------------------------------------------
-- Alimentos e bebidas
--   Action     = "Eat" (botão COMER) ou "Drink" (botão BEBER)
--   Hunger     = fome recuperada na hora
--   Saturation = saciedade (quanto tempo segura a fome)
--   Water      = sede recuperada
--   Health / Stamina = opcionais
--   RandomEffects = lista de { Effect = "Energy"|"Nausea"|"Poison"|"None", Chance = peso }
--                   (os pesos são normalizados; cada cogumelo tem os seus)
----------------------------------------------------------------------
NutritionConfig.Consumables = {
	Coconut = { Action = "Eat", Hunger = 9, Saturation = 6, Water = 9 },
	Apple   = { Action = "Eat", Hunger = 10, Saturation = 8, Water = 4 },
	Banana  = { Action = "Eat", Hunger = 14, Saturation = 14, Water = 2 },
	Berry   = { Action = "Eat", Hunger = 4, Saturation = 2, Water = 4 },
	Honey   = { Action = "Eat", Hunger = 8, Saturation = 26, Water = 0, Stamina = 15 },
	Herb    = { Action = "Eat", Hunger = 2, Saturation = 0, Water = 0, Health = 15 },

	-- Cogumelos: cada espécie tem as suas probabilidades
	Mushroom = { -- Cogumelo Marrom (comum, quase sempre seguro)
		Action = "Eat", Hunger = 6, Saturation = 4, Water = 1,
		RandomEffects = {
			{ Effect = "None", Chance = 60 },
			{ Effect = "Energy", Chance = 25 },
			{ Effect = "Nausea", Chance = 10 },
			{ Effect = "Poison", Chance = 5 },
		},
	},
	MushroomRed = { -- Cogumelo Vermelho (perigoso)
		Action = "Eat", Hunger = 4, Saturation = 2, Water = 1,
		RandomEffects = {
			{ Effect = "None", Chance = 25 },
			{ Effect = "Energy", Chance = 10 },
			{ Effect = "Nausea", Chance = 25 },
			{ Effect = "Poison", Chance = 40 },
		},
	},
	MushroomBlue = { -- Cogumelo Azul (energético, quase nunca faz mal)
		Action = "Eat", Hunger = 5, Saturation = 3, Water = 2,
		RandomEffects = {
			{ Effect = "None", Chance = 40 },
			{ Effect = "Energy", Chance = 55 },
			{ Effect = "Nausea", Chance = 5 },
			{ Effect = "Poison", Chance = 0 },
		},
	},

	-- Exemplo de bebida para o futuro (crie o item "WaterBottle" no ResourceConfig):
	-- WaterBottle = { Action = "Drink", Hunger = 0, Saturation = 0, Water = 30 },
}


----------------------------------------------------------------------
-- Oxigênio (debaixo d'água; nadar na superfície NÃO gasta oxigênio)
----------------------------------------------------------------------
NutritionConfig.Oxygen = {
	Max = 35,             -- segundos de fôlego
	DrainPerSecond = 1,
	RegenPerSecond = 9,   -- recupera rápido ao voltar à superfície
	Damage = 8,           -- vida perdida a cada DamageInterval com o oxigênio em zero
	DamageInterval = 1,
}

----------------------------------------------------------------------
-- Balanceamento (multiplicadores sobre o SurvivalConfig, sem precisar editá-lo)
----------------------------------------------------------------------
NutritionConfig.Balance = {
	StaminaMax = 1.8,     -- mais stamina para explorar distâncias maiores
	StaminaDrain = 0.7,   -- corrida gasta menos
	StaminaRegen = 1.5,   -- regenera mais rápido
	HungerDrain = 0.55,   -- fome cai mais devagar (a comida em si rende menos e há menos comida)
	CrouchSpeed = 0.5,    -- velocidade agachado = metade da andando
	CrouchNoise = 0.2,    -- ruído de passos agachado (1 = andando normal)
	MaxSlopeAngle = 48,   -- inclinação máxima que dá para subir andando (montanhas íngremes exigem trilhas/equipamento)
}

return NutritionConfig

