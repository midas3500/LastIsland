--[[
	TemperatureConfig
	Local: ReplicatedStorage > Modules > TemperatureConfig   (ModuleScript)

	Temperatura corporal de 0 a 100 (50 = ideal). Servidor e cliente leem este arquivo.
	Faixas: Frio (<38) | Normal (38 a 62) | Calor (>62), cada uma com níveis de intensidade.

	PROTEÇÕES (para armaduras/roupas futuras): o equipamento só precisa definir atributos no Player
	  ColdResist (0 a 1) = reduz tudo que esfria   |   HeatResist (0 a 1) = reduz tudo que esquenta
	  ex: player:SetAttribute("ColdResist", 0.5)  -> o frio ambiente conta pela metade
	Ou use TemperatureService.SetResistance(player, cold, heat).
]]

local TemperatureConfig = {}

TemperatureConfig.Ideal = 50
TemperatureConfig.Tau = 28              -- segundos para o corpo acompanhar a temperatura do ambiente
TemperatureConfig.UpdateInterval = 0.5

-- limites das faixas (temperatura corporal)
TemperatureConfig.Bands = {
	ColdMild = 38, ColdModerate = 28, ColdSevere = 15,
	HeatMild = 62, HeatModerate = 72, HeatSevere = 85,
}

-- tudo que muda a temperatura-alvo (em "graus"; esfriar e esquentar são somados separadamente)
TemperatureConfig.Environment = {
	DayWarm = 7,            -- ao meio-dia
	NightChill = 13,        -- de madrugada
	AltitudeStart = 25,     -- acima desta altura (studs sobre o mar) começa a esfriar
	AltitudeChillPerStud = 0.06,
	AltitudeChillMax = 34,
	SnowChill = 12,         -- picos nevados
	VolcanoHeat = 48,       -- no pé da cratera
	VolcanoRangeScale = 1.5, -- alcance do calor (x raio do vulcão)
	VolcanoEruptingMult = 1.6,
	WaterChill = 20,        -- dentro d'água
	WetChill = 14,          -- extra quando está encharcado (acumula nadando, seca devagar)
	WetGainPerSecond = 1 / 70,
	WetLossPerSecond = 1 / 160,
	CaveChill = 9,
	BeachWarm = 3,
	StormChill = 10,
	FogChill = 3,
	HeatWaveWarm = 17,
	AshWarm = 4,
}

-- efeitos por nível (1 = leve, 2 = moderado, 3 = severo). Damage = vida por segundo (só no nível 3,
-- e cresce aos poucos: RampSeconds até o dano total)
TemperatureConfig.Effects = {
	RampSeconds = 15,
	Cold = {
		[1] = { StaminaRegen = 0.8 },
		[2] = { StaminaRegen = 0.5, ThirstRate = 0.9 },
		[3] = { StaminaRegen = 0.25, Damage = 1.3 },
	},
	Heat = {
		[1] = { Thirst = 1.25 },
		[2] = { Thirst = 1.6, StaminaDrain = 1.2 },
		[3] = { Thirst = 2.2, StaminaDrain = 1.5, Damage = 1.3 },
	},
}

return TemperatureConfig

