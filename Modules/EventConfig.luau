--[[
	EventConfig
	Local: ReplicatedStorage > Modules > EventConfig

	Dados iniciais de desastres. Usados a partir da Etapa 6.
	LightingPreset combina com MapConfig.Lighting.Presets.
]]

local EventConfig = {}

EventConfig.Version = 1
EventConfig.FirstEventDelay = 300  -- segundos até o primeiro desastre
EventConfig.MinTimeBetween = 420   -- segundos mínimos entre desastres

EventConfig.Events = {
	Storm = {
		DisplayName = "Tempestade", Enabled = true, Weight = 50,
		WarningTime = 20, Duration = 60, LightingPreset = "Storm",
	},
	Tsunami = {
		DisplayName = "Tsunami", Enabled = true, Weight = 30,
		WarningTime = 30, Duration = 40, LightingPreset = "Storm",
	},
	Meteors = {
		DisplayName = "Chuva de Meteoros", Enabled = true, Weight = 20,
		WarningTime = 25, Duration = 45, LightingPreset = "Sunset",
	},
}

return EventConfig