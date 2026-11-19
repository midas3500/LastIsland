--[[
	SurvivalService (v3)
	Local: ServerScriptService > Services > SurvivalService   (SUBSTITUI o atual)

	Controla (tudo no servidor):
	  - Fome, SEDE e SACIEDADE
	  - Stamina, corrida e NATAÇÃO (gasta stamina na água)
	  - Comer / beber itens da mochila (FoodRequest "Consume", item)
	  - Efeitos: Energia, Náusea, Envenenamento (cogumelos e afins)
	  - Dano por fome e por desidratação
	  - Ciclo de dia e noite

	Mantém tudo que o SurvivalService antigo fazia (SprintRequest, FoodRequest "EatCoconut",
	atributos Hunger/Stamina, relógio WorldClockTime/DayNumber).

	Atributos no Player (o HUD lê):
	  Hunger/MaxHunger, Stamina/MaxStamina, Thirst/MaxThirst, Saturation/MaxSaturation,
	  IsSprinting, InWater, FxEnergyEnd / FxNauseaEnd / FxPoisonEnd (Workspace:GetServerTimeNow())
	Atributos no Workspace que outros sistemas podem usar: ThirstMultiplier (ex: evento de seca)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Config = require(Modules:WaitForChild("SurvivalConfig"))
local NC = require(Modules:WaitForChild("NutritionConfig"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local WaterService = require(script.Parent:WaitForChild("WaterService"))

local SurvivalService = {}

local sprintRemote
local foodRemote
local states = {}
local lastSprintRequest = {}
local lastFoodRequest = {}
local running = false

local function log(...)
	if GameConfig.Debug then
		print("[SurvivalService]", ...)
	end
end

local function getState(player)
	return states[player]
end

----------------------------------------------------------------------
-- Velocidade (andar / correr / nadar / efeitos)
----------------------------------------------------------------------
local function currentSpeed(state)
	local swim = NC.Swim
	local speed
	if state.InWater then
		if state.Stamina <= 0 then
			speed = swim.ExhaustedSpeed
		elseif state.Sprinting then
			speed = swim.SprintSpeed
		else
			speed = swim.Speed
		end
	elseif state.Sprinting then
		speed = Config.Stamina.SprintSpeed
	else
		speed = Config.Stamina.WalkSpeed
	end

	local now = os.clock()
	local fx = state.Effects
	if fx.Energy and fx.Energy > now then
		speed *= NC.Effects.Energy.SpeedMultiplier
	end
	if fx.Nausea and fx.Nausea > now then
		speed *= NC.Effects.Nausea.SpeedMultiplier
	end
	return speed
end

local function applySpeed(player, state)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local target = currentSpeed(state)
	if humanoid.WalkSpeed ~= target then
		humanoid.WalkSpeed = target
	end
end

local function setSprint(player, enabled)
	local state = getState(player)
	if not state then return end
	if enabled and state.Stamina < Config.Stamina.MinimumToSprint then
		enabled = false
	end
	state.Sprinting = enabled
	player:SetAttribute("IsSprinting", enabled)
	applySpeed(player, state)
end

local function updateCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local state = getState(player)
	if state then
		state.Sprinting = false
		state.InWater = false
		state.OutCount = 0
		player:SetAttribute("IsSprinting", false)
		player:SetAttribute("InWater", false)
		humanoid.WalkSpeed = currentSpeed(state)
	else
		humanoid.WalkSpeed = Config.Stamina.WalkSpeed
	end
end

----------------------------------------------------------------------
-- Inicialização do jogador
----------------------------------------------------------------------
local function initializePlayer(player, data)
	if states[player] then return end
	data.Survival = data.Survival or {}
	local saved = data.Survival

	local hunger = math.clamp(tonumber(saved.Hunger) or Config.Hunger.Max, 0, Config.Hunger.Max)
	local thirst = math.clamp(tonumber(saved.Thirst) or NC.Thirst.Max, 0, NC.Thirst.Max)
	local saturation = math.clamp(tonumber(saved.Saturation) or 0, 0, NC.Saturation.Max)

	states[player] = {
		Hunger = hunger,
		Thirst = thirst,
		Saturation = saturation,
		Stamina = Config.Stamina.Max,
		Sprinting = false,
		LastSprint = 0,
		DamageTimer = 0,
		ThirstDamageTimer = 0,
		SaveTimer = 0,
		InWater = false,
		OutCount = 0,
		WaterTimer = 0,
		Effects = {}, -- [nome] = os.clock() em que acaba
	}

	player:SetAttribute("MaxHunger", Config.Hunger.Max)
	player:SetAttribute("MaxStamina", Config.Stamina.Max)
	player:SetAttribute("MaxThirst", NC.Thirst.Max)
	player:SetAttribute("MaxSaturation", NC.Saturation.Max)
	player:SetAttribute("Hunger", hunger)
	player:SetAttribute("Stamina", Config.Stamina.Max)
	player:SetAttribute("Thirst", thirst)
	player:SetAttribute("Saturation", saturation)
	player:SetAttribute("IsSprinting", false)
	player:SetAttribute("InWater", false)
	player:SetAttribute("SurvivalReady", true)

	if player.Character then
		task.spawn(updateCharacter, player, player.Character)
	end
	log("Sobrevivência inicializada:", player.Name)
end

local function removePlayer(player)
	states[player] = nil
	lastSprintRequest[player] = nil
	lastFoodRequest[player] = nil
end

----------------------------------------------------------------------
-- Corrida
----------------------------------------------------------------------
local function onSprintRequest(player, enabled)
	if typeof(enabled) ~= "boolean" then return end
	local now = os.clock()
	if lastSprintRequest[player] and now - lastSprintRequest[player] < 0.1 then return end
	lastSprintRequest[player] = now

	local state = getState(player)
	if not state then return end
	if enabled then
		if not PlayerDataService.IsLoaded(player) then return end
		if state.Stamina < Config.Stamina.MinimumToSprint then return end
	end
	setSprint(player, enabled)
end

----------------------------------------------------------------------
-- Efeitos
----------------------------------------------------------------------
local EFFECT_ATTRIBUTE = { Energy = "FxEnergyEnd", Nausea = "FxNauseaEnd", Poison = "FxPoisonEnd" }

local function applyEffect(player, state, effectId)
	local def = NC.Effects[effectId]
	if not def then return end
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()

	if effectId == "Energy" then
		state.Stamina = math.min(Config.Stamina.Max, state.Stamina + (def.StaminaRestore or 0))
	end
	state.Effects[effectId] = now + def.Duration
	player:SetAttribute(EFFECT_ATTRIBUTE[effectId], serverNow + def.Duration)
	applySpeed(player, state)
end

local function expireEffects(player, state)
	local now = os.clock()
	for effectId, untilTime in state.Effects do
		if untilTime <= now then
			state.Effects[effectId] = nil
			player:SetAttribute(EFFECT_ATTRIBUTE[effectId], nil)
		end
	end
end

local function rollEffect(def)
	local list = def.RandomEffects
	if type(list) ~= "table" then return nil end
	local total = 0
	for _, entry in list do
		total += math.max(0, entry.Chance or 0)
	end
	if total <= 0 then return nil end
	local roll = math.random() * total
	for _, entry in list do
		roll -= math.max(0, entry.Chance or 0)
		if roll <= 0 then
			return entry.Effect
		end
	end
	return "None"
end

----------------------------------------------------------------------
-- Comer / beber
----------------------------------------------------------------------
local function deny(player, itemId, reason)
	if foodRemote and player.Parent then
		foodRemote:FireClient(player, "Denied", itemId, reason)
	end
end

local function isUseful(state, humanoid, def)
	if (def.Hunger or 0) > 0 and state.Hunger < Config.Hunger.Max then return true end
	if (def.Saturation or 0) > 0 and state.Saturation < NC.Saturation.Max then return true end
	if (def.Water or 0) > 0 and state.Thirst < NC.Thirst.Max then return true end
	if (def.Stamina or 0) > 0 and state.Stamina < Config.Stamina.Max then return true end
	if (def.Health or 0) > 0 and humanoid and humanoid.Health < humanoid.MaxHealth then return true end
	return def.RandomEffects ~= nil
end

local function onFoodRequest(player, action, itemId)
	-- compatibilidade com o botão antigo
	if action == "EatCoconut" then
		action, itemId = "Consume", "Coconut"
	end
	if action ~= "Consume" or type(itemId) ~= "string" then return end

	local now = os.clock()
	if lastFoodRequest[player] and now - lastFoodRequest[player] < 0.5 then return end
	lastFoodRequest[player] = now

	local state = getState(player)
	if not state or not PlayerDataService.IsLoaded(player) then return end

	local def = NC.Consumables[itemId]
	if not def then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	if not isUseful(state, humanoid, def) then
		return deny(player, itemId, "Você não precisa disso agora.")
	end

	-- remove do inventário NO SERVIDOR; se não tiver, não acontece nada (sem duplicar)
	if not InventoryService.RemoveItem(player, itemId, 1, "Consume") then
		return deny(player, itemId, "Você não tem esse item.")
	end

	state.Hunger = math.clamp(state.Hunger + (def.Hunger or 0), 0, Config.Hunger.Max)
	state.Saturation = math.clamp(state.Saturation + (def.Saturation or 0), 0, NC.Saturation.Max)
	state.Thirst = math.clamp(state.Thirst + (def.Water or 0), 0, NC.Thirst.Max)
	state.Stamina = math.clamp(state.Stamina + (def.Stamina or 0), 0, Config.Stamina.Max)
	if (def.Health or 0) > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + def.Health)
	end

	local effectId = rollEffect(def)
	if effectId and effectId ~= "None" then
		applyEffect(player, state, effectId)
	end

	player:SetAttribute("Hunger", state.Hunger)
	player:SetAttribute("Thirst", state.Thirst)
	player:SetAttribute("Saturation", state.Saturation)
	player:SetAttribute("Stamina", state.Stamina)

	foodRemote:FireClient(player, "Consumed", itemId, def.Action or "Eat", effectId or "None")
	log(player.Name, "consumiu", itemId, "efeito:", effectId or "nenhum")
end

----------------------------------------------------------------------
-- API para outros serviços
----------------------------------------------------------------------
function SurvivalService.AddWater(player, amount)
	local state = getState(player)
	if not state or type(amount) ~= "number" or amount <= 0 then return false end
	state.Thirst = math.clamp(state.Thirst + amount, 0, NC.Thirst.Max)
	player:SetAttribute("Thirst", state.Thirst)
	if foodRemote then
		foodRemote:FireClient(player, "Consumed", "WellWater", "Drink", "None")
	end
	return true
end

function SurvivalService.AddHunger(player, amount)
	local state = getState(player)
	if not state or type(amount) ~= "number" then return false end
	state.Hunger = math.clamp(state.Hunger + amount, 0, Config.Hunger.Max)
	player:SetAttribute("Hunger", state.Hunger)
	return true
end

function SurvivalService.ApplyEffect(player, effectId)
	local state = getState(player)
	if not state then return false end
	applyEffect(player, state, effectId)
	return true
end

function SurvivalService.Get(player)
	local state = getState(player)
	if not state then return nil end
	return {
		Hunger = state.Hunger, Thirst = state.Thirst, Saturation = state.Saturation,
		Stamina = state.Stamina, InWater = state.InWater, Sprinting = state.Sprinting,
	}
end

----------------------------------------------------------------------
-- Atualização contínua
----------------------------------------------------------------------
local function setInWater(player, state, inWater)
	state.InWater = inWater
	player:SetAttribute("InWater", inWater)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position or Vector3.zero
	if inWater then
		WaterService.PlayerEnteredWater:Fire(player, position)
	else
		WaterService.PlayerLeftWater:Fire(player, position)
	end
	applySpeed(player, state)
end

local function updatePlayer(player, dt)
	local state = getState(player)
	if not state or not PlayerDataService.IsLoaded(player) then return end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local alive = humanoid ~= nil and humanoid.Health > 0
	local moving = alive and humanoid.MoveDirection.Magnitude > 0.05

	-- ÁGUA (natação): entra na hora, sai depois de 2 leituras seguidas fora d'água
	state.WaterTimer += dt
	if root and alive and state.WaterTimer >= 0.2 then
		state.WaterTimer = 0
		if WaterService.IsInWater(root.Position) then
			state.OutCount = 0
			if not state.InWater then
				setInWater(player, state, true)
			end
		else
			state.OutCount += 1
			if state.InWater and state.OutCount >= 2 then
				setInWater(player, state, false)
			end
		end
	end

	-- SACIEDADE / FOME: a saciedade se esgota primeiro; só depois a fome cai
	if state.Saturation > 0 then
		state.Saturation = math.max(0, state.Saturation - NC.Saturation.DrainPerSecond * dt)
	else
		state.Hunger = math.clamp(state.Hunger - Config.Hunger.DrainPerSecond * dt, 0, Config.Hunger.Max)
	end

	-- SEDE: cai com o tempo e mais rápido correndo/nadando (seca: ThirstMultiplier no Workspace)
	local thirstMultiplier = Workspace:GetAttribute("ThirstMultiplier") or 1
	if moving and state.InWater then
		thirstMultiplier *= NC.Thirst.SwimMultiplier
	elseif moving and state.Sprinting then
		thirstMultiplier *= NC.Thirst.SprintMultiplier
	end
	state.Thirst = math.clamp(state.Thirst - NC.Thirst.DrainPerSecond * thirstMultiplier * dt, 0, NC.Thirst.Max)

	-- STAMINA
	local nauseaActive = state.Effects.Nausea ~= nil and state.Effects.Nausea > os.clock()
	if state.InWater then
		if moving then
			local drain = state.Sprinting and NC.Swim.SprintDrainPerSecond or NC.Swim.DrainPerSecond
			state.Stamina = math.max(0, state.Stamina - drain * dt)
			state.LastSprint = os.clock()
			if state.Stamina <= 0 and state.Sprinting then
				setSprint(player, false)
			end
		end
		-- na água a stamina não regenera
	elseif state.Sprinting and moving then
		state.Stamina = math.max(0, state.Stamina - Config.Stamina.DrainPerSecond * dt)
		state.LastSprint = os.clock()
		if state.Stamina <= 0 then
			setSprint(player, false)
		end
	else
		if os.clock() - state.LastSprint >= Config.Stamina.RegenDelay then
			local regen = Config.Stamina.RegenPerSecond * dt
			if nauseaActive then
				regen *= NC.Effects.Nausea.StaminaRegenMultiplier
			end
			state.Stamina = math.min(Config.Stamina.Max, state.Stamina + regen)
		end
	end

	-- EFEITOS
	expireEffects(player, state)
	local poisonUntil = state.Effects.Poison
	if poisonUntil and poisonUntil > os.clock() and alive then
		local def = NC.Effects.Poison
		local damage = def.DamagePerSecond * dt
		if not def.CanKill then
			damage = math.min(damage, math.max(0, humanoid.Health - 1))
		end
		if damage > 0 then
			humanoid:TakeDamage(damage)
		end
	end

	-- DANO POR FOME
	if state.Hunger <= 0 and alive then
		state.DamageTimer += dt
		if state.DamageTimer >= Config.Hunger.DamageInterval then
			state.DamageTimer = 0
			humanoid:TakeDamage(Config.Hunger.StarvationDamage)
		end
	else
		state.DamageTimer = 0
	end

	-- DANO POR DESIDRATAÇÃO
	if state.Thirst <= 0 and alive then
		state.ThirstDamageTimer += dt
		if state.ThirstDamageTimer >= NC.Thirst.DamageInterval then
			state.ThirstDamageTimer = 0
			humanoid:TakeDamage(NC.Thirst.DehydrationDamage)
		end
	else
		state.ThirstDamageTimer = 0
	end

	-- velocidade (efeitos que acabaram, stamina zerada na água...)
	applySpeed(player, state)

	-- SALVAR no perfil (o autosave do PlayerDataService grava de verdade)
	if not PlayerDataService.IsReadOnly(player) then
		state.SaveTimer += dt
		if state.SaveTimer >= Config.ProfileSaveInterval then
			state.SaveTimer = 0
			local data = PlayerDataService.GetData(player)
			if data then
				data.Survival = data.Survival or {}
				data.Survival.Hunger = state.Hunger
				data.Survival.Thirst = state.Thirst
				data.Survival.Saturation = state.Saturation
			end
		end
	end

	player:SetAttribute("Hunger", state.Hunger)
	player:SetAttribute("Thirst", state.Thirst)
	player:SetAttribute("Saturation", state.Saturation)
	player:SetAttribute("Stamina", state.Stamina)
end

----------------------------------------------------------------------
-- Dia e noite
----------------------------------------------------------------------
local function updateDayNight(elapsed)
	local dayConfig = Config.DayNight
	local totalHours = dayConfig.StartClockTime + (elapsed / dayConfig.FullDaySeconds) * 24
	local clockTime = totalHours % 24
	local dayNumber = dayConfig.StartDay + math.floor(totalHours / 24)
	Lighting.ClockTime = clockTime
	Lighting:SetAttribute("DayNumber", dayNumber)
	Lighting:SetAttribute("WorldClockTime", clockTime)
end

----------------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------------
function SurvivalService.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	sprintRemote = remotes:WaitForChild("SprintRequest")
	foodRemote = remotes:WaitForChild("FoodRequest")
	log("Init concluído.")
end

function SurvivalService.Start()
	if running then return end
	running = true

	sprintRemote.OnServerEvent:Connect(onSprintRequest)
	foodRemote.OnServerEvent:Connect(onFoodRequest)

	PlayerDataService.OnLoaded(initializePlayer)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			updateCharacter(player, character)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function(character)
			updateCharacter(player, character)
		end)
	end
	Players.PlayerRemoving:Connect(removePlayer)

	-- beber nos poços da ilha (IslandGenerator.WellDrank)
	local generatorModule = script.Parent:FindFirstChild("IslandGenerator")
	if generatorModule then
		local ok, Generator = pcall(require, generatorModule)
		if ok and Generator.WellDrank then
			Generator.WellDrank.Event:Connect(function(player, _, amount)
				SurvivalService.AddWater(player, (amount or 0) * NC.Thirst.WellMultiplier)
			end)
		end
	end

	local elapsed = 0
	updateDayNight(elapsed)

	task.spawn(function()
		while running do
			local dt = task.wait(Config.UpdateInterval)
			elapsed += dt
			updateDayNight(elapsed)
			for player in pairs(states) do
				updatePlayer(player, dt)
			end
		end
	end)

	log("Sistema de sobrevivência iniciado.")
end

return SurvivalService

