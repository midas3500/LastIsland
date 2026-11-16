
local SurvivalConfig = {}

-- FOME
SurvivalConfig.Hunger = {
	Max = 100,

	-- Tempo aproximado para zerar a fome.
	DrainPerSecond = 100 / 5400,

	-- Dano quando a fome chega a zero.
	StarvationDamage = 4,
	DamageInterval = 3,

	-- Alimentação
	CoconutRestore = 25,
}

-- STAMINA
SurvivalConfig.Stamina = {
	Max = 100,

	DrainPerSecond = 22,
	RegenPerSecond = 16,
	RegenDelay = 1,

	WalkSpeed = 16,
	SprintSpeed = 24,

	MinimumToSprint = 5,
}

-- DIA E NOITE
SurvivalConfig.DayNight = {
	StartClockTime = 8,

	-- 20 minutos reais para completar 24 horas.
	FullDaySeconds = 1200,

	StartDay = 1,
}

-- ATUALIZAÇÃO
SurvivalConfig.UpdateInterval = 0.2
SurvivalConfig.ProfileSaveInterval = 5

return SurvivalConfig
