--[[
	OceanAtmosphereClient  (tipo: LocalScript)
	Local: StarterPlayer > StarterPlayerScripts > OceanAtmosphereClient

	Faz o horizonte do mar "sumir" na neblina, sem linha de fim, em qualquer hora do dia:
	a cor da neblina e da atmosfera acompanha o relógio do jogo (Lighting.WorldClockTime).
	Só mexe no Lighting DESTE jogador (nada é replicado para o servidor).
]]

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- hora (0-24) -> cor da neblina no horizonte
local KEYS = {
	{ 0,    Color3.fromRGB(12, 18, 38) },
	{ 4.5,  Color3.fromRGB(28, 36, 70) },
	{ 6,    Color3.fromRGB(235, 160, 130) },
	{ 8,    Color3.fromRGB(175, 210, 235) },
	{ 12,   Color3.fromRGB(165, 205, 240) },
	{ 16.5, Color3.fromRGB(180, 208, 232) },
	{ 18,   Color3.fromRGB(245, 160, 110) },
	{ 19.5, Color3.fromRGB(70, 60, 110) },
	{ 21,   Color3.fromRGB(18, 24, 48) },
	{ 24,   Color3.fromRGB(12, 18, 38) },
}

local function colorAt(hour)
	hour = hour % 24
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if hour >= a[1] and hour <= b[1] then
			local t = (hour - a[1]) / math.max(0.001, b[1] - a[1])
			return a[2]:Lerp(b[2], t)
		end
	end
	return KEYS[1][2]
end

local current = colorAt(Lighting:GetAttribute("WorldClockTime") or Lighting.ClockTime)

RunService.RenderStepped:Connect(function(dt)
	local hour = Lighting:GetAttribute("WorldClockTime") or Lighting.ClockTime
	current = current:Lerp(colorAt(hour), 1 - math.exp(-dt * 2))

	Lighting.FogColor = current
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Color = current
		atmosphere.Decay = current:Lerp(Color3.new(0, 0, 0), 0.35)
	end
end)

