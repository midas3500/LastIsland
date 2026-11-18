--[[
	LightingService
	Local: ServerScriptService > Services > LightingService

	Aplica presets de iluminação (MapConfig.Lighting.Presets).
	Uso futuro (EventService): LightingService.Apply("Storm")

	OBS.: a mudança é instantânea. Transições suaves ficam para o cliente (Etapa 6).
	OBS.: Lighting.Technology não pode ser alterado por script; configure manualmente (seção 2.3-D).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))

local LightingService = {}

local currentPreset = nil

local function getOrCreate(className, name)
	local inst = Lighting:FindFirstChild(name)
	if inst and not inst:IsA(className) then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

local function applyProps(target, props, label)
	if not props then
		return
	end
	for prop, value in pairs(props) do
		local ok, err = pcall(function()
			target[prop] = value
		end)
		if not ok then
			warn(string.format("[LightingService] Não foi possível definir %s.%s: %s", label, prop, tostring(err)))
		end
	end
end

function LightingService.Apply(presetName)
	local preset = MapConfig.Lighting.Presets[presetName]
	if not preset then
		warn("[LightingService] Preset inexistente: " .. tostring(presetName))
		return false
	end

	applyProps(Lighting, preset.Lighting, "Lighting")
	applyProps(getOrCreate("Atmosphere", "Atmosphere"), preset.Atmosphere, "Atmosphere")
	applyProps(getOrCreate("ColorCorrectionEffect", "ColorCorrection"), preset.ColorCorrection, "ColorCorrection")
	applyProps(getOrCreate("BloomEffect", "Bloom"), preset.Bloom, "Bloom")
	applyProps(getOrCreate("SunRaysEffect", "SunRays"), preset.SunRays, "SunRays")

	currentPreset = presetName
	if GameConfig.Debug then
		print("[LightingService] Preset aplicado: " .. presetName)
	end
	return true
end

function LightingService.GetCurrentPreset()
	return currentPreset
end

function LightingService.Init()
end

function LightingService.Start()
	LightingService.Apply(MapConfig.Lighting.DefaultPreset)
end

return LightingService