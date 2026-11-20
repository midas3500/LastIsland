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

-- Balanceamento (multiplicadores do NutritionConfig.Balance sobre o SurvivalConfig)
local Balance = NC.Balance
local ST = table.clone(Config.Stamina)
ST.Max = ST.Max * Balance.StaminaMax
ST.DrainPerSecond = ST.DrainPerSecond * Balance.StaminaDrain
ST.RegenPerSecond = ST.RegenPerSecond * Balance.StaminaRegen
local HG = table.clone(Config.Hunger)
HG.DrainPerSecond = HG.DrainPerSecond * Balance.HungerDrain

local SurvivalService = {}

local sprintRemote
local foodRemote
local crouchRemote
local lastCrouchRequest = setmetatable({}, { __mode = "k" })
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
	elseif state.Crouching then
		speed = ST.WalkSpeed * Balance.CrouchSpeed
	elseif state.Sprinting then
		speed = ST.SprintSpeed
	else
		speed = ST.WalkSpeed
	end

	local now = os.clock()
	local fx = state.Effects
	if fx.Energy and fx.Energy > now then
		speed *= NC.Effects.Energy.SpeedMultiplier
	end
	if fx.Nausea and fx.Nausea > now then
		speed *= NC.Effects.Nausea.SpeedMultiplier
	end
	speed *= (Workspace:GetAttribute("WorldSpeedMultiplier") or 1)
	if state.Player then
		-- futuro: equipamentos
		speed *= (state.Player:GetAttribute("SpeedMultiplier") or 1)
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
	if enabled and state.Stamina < ST.MinimumToSprint then
		enabled = false
	end
	if enabled and state.Crouching then
		state.Crouching = false
		player:SetAttribute("IsCrouching", false)
	end
	state.Sprinting = enabled
	player:SetAttribute("IsSprinting", enabled)
	applySpeed(player, state)
end

local function setCrouch(player, enabled)
	local state = getState(player)
	if not state then return end
	if enabled and state.InWater then enabled = false end
	if enabled and state.Sprinting then
		state.Sprinting = false
		player:SetAttribute("IsSprinting", false)
	end
	state.Crouching = enabled
	player:SetAttribute("IsCrouching", enabled)
	applySpeed(player, state)
end

local function updateCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	-- montanhas íngremes: acima desta inclinação não dá para subir andando
	humanoid.MaxSlopeAngle = Balance.MaxSlopeAngle + (player:GetAttribute("ClimbBonus") or 0)
	local state = getState(player)
	if state then
		state.Sprinting = false
		state.Crouching = false
		state.InWater = false
		state.Submerged = false
		state.OutCount = 0
		state.Oxygen = NC.Oxygen.Max
		player:SetAttribute("IsSprinting", false)
		player:SetAttribute("IsCrouching", false)
		player:SetAttribute("InWater", false)
		player:SetAttribute("Submerged", false)
		player:SetAttribute("Oxygen", NC.Oxygen.Max)
		humanoid.WalkSpeed = currentSpeed(state)
	else
		humanoid.WalkSpeed = ST.WalkSpeed
	end
end

----------------------------------------------------------------------
-- Inicialização do jogador
----------------------------------------------------------------------
local function initializePlayer(player, data)
	if states[player] then return end
	data.Survival = data.Survival or {}
	local saved = data.Survival

	local hunger = math.clamp(tonumber(saved.Hunger) or HG.Max, 0, HG.Max)
	local thirst = math.clamp(tonumber(saved.Thirst) or NC.Thirst.Max, 0, NC.Thirst.Max)
	local saturation = math.clamp(tonumber(saved.Saturation) or 0, 0, NC.Saturation.Max)

	states[player] = {
		Hunger = hunger,
		Thirst = thirst,
		Saturation = saturation,
		Stamina = ST.Max,
		Sprinting = false,
		LastSprint = 0,
		DamageTimer = 0,
		ThirstDamageTimer = 0,
		SaveTimer = 0,
		InWater = false,
		OutCount = 0,
		WaterTimer = 0,
		Effects = {}, -- [nome] = os.clock() em que acaba
		Player = player,
		Crouching = false,
		Submerged = false,
		Oxygen = NC.Oxygen.Max,
		OxygenDamageTimer = 0,
	}

	player:SetAttribute("MaxHunger", HG.Max)
	player:SetAttribute("MaxStamina", ST.Max)
	player:SetAttribute("MaxThirst", NC.Thirst.Max)
	player:SetAttribute("MaxSaturation", NC.Saturation.Max)
	player:SetAttribute("Hunger", hunger)
	player:SetAttribute("Stamina", ST.Max)
	player:SetAttribute("Thirst", thirst)
	player:SetAttribute("Saturation", saturation)
	player:SetAttribute("IsSprinting", false)
	player:SetAttribute("InWater", false)
	player:SetAttribute("MaxOxygen", NC.Oxygen.Max)
	player:SetAttribute("Oxygen", NC.Oxygen.Max)
	player:SetAttribute("Submerged", false)
	player:SetAttribute("IsCrouching", false)
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
		if state.Stamina < ST.MinimumToSprint then return end
	end
	setSprint(player, enabled)
end

----------------------------------------------------------------------
-- Efeitos
----------------------------------------------------------------------
local function onCrouchRequest(player, enabled)
	if typeof(enabled) ~= "boolean" then return end
	local now = os.clock()
	if lastCrouchRequest[player] and now - lastCrouchRequest[player] < 0.1 then return end
	lastCrouchRequest[player] = now
	if not getState(player) or not PlayerDataService.IsLoaded(player) then return end
	setCrouch(player, enabled)
end

local EFFECT_ATTRIBUTE = { Energy = "FxEnergyEnd", Nausea = "FxNauseaEnd", Poison = "FxPoisonEnd" }

local function applyEffect(player, state, effectId)
	local def = NC.Effects[effectId]
	if not def then return end
	local now = os.clock()
	local serverNow = Workspace:GetServerTimeNow()

	if effectId == "Energy" then
		state.Stamina = math.min(ST.Max, state.Stamina + (def.StaminaRestore or 0))
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
	if (def.Hunger or 0) > 0 and state.Hunger < HG.Max then return true end
	if (def.Saturation or 0) > 0 and state.Saturation < NC.Saturation.Max then return true end
	if (def.Water or 0) > 0 and state.Thirst < NC.Thirst.Max then return true end
	if (def.Stamina or 0) > 0 and state.Stamina < ST.Max then return true end
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

	state.Hunger = math.clamp(state.Hunger + (def.Hunger or 0), 0, HG.Max)
	state.Saturation = math.clamp(state.Saturation + (def.Saturation or 0), 0, NC.Saturation.Max)
	state.Thirst = math.clamp(state.Thirst + (def.Water or 0), 0, NC.Thirst.Max)
	state.Stamina = math.clamp(state.Stamina + (def.Stamina or 0), 0, ST.Max)
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
	state.Hunger = math.clamp(state.Hunger + amount, 0, HG.Max)
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
	if inWater and state.Crouching then
		setCrouch(player, false)
	end
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

	-- OXIGÊNIO: só a CABEÇA debaixo d'água conta como submerso (nadar na superfície não gasta)
	local head = character and character:FindFirstChild("Head")
	local submerged = false
	if head and alive then
		submerged = WaterService.IsInWater(head.Position + Vector3.new(0, 0.2, 0))
	end
	if submerged ~= state.Submerged then
		state.Submerged = submerged
		player:SetAttribute("Submerged", submerged)
	end
	local OX = NC.Oxygen
	if submerged then
		state.Oxygen = math.max(0, state.Oxygen - OX.DrainPerSecond * dt)
		if state.Oxygen <= 0 and alive then
			state.OxygenDamageTimer += dt
			if state.OxygenDamageTimer >= OX.DamageInterval then
				state.OxygenDamageTimer = 0
				humanoid:TakeDamage(OX.Damage)
			end
		end
	else
		state.OxygenDamageTimer = 0
		state.Oxygen = math.min(OX.Max, state.Oxygen + OX.RegenPerSecond * dt)
	end
	player:SetAttribute("Oxygen", state.Oxygen)

	-- SACIEDADE / FOME: a saciedade se esgota primeiro; só depois a fome cai
	if state.Saturation > 0 then
		state.Saturation = math.max(0, state.Saturation - NC.Saturation.DrainPerSecond * dt)
	else
		state.Hunger = math.clamp(state.Hunger - HG.DrainPerSecond * dt, 0, HG.Max)
	end

	-- SEDE: cai com o tempo e mais rápido correndo/nadando (seca: ThirstMultiplier no Workspace)
	local thirstMultiplier = (Workspace:GetAttribute("ThirstMultiplier") or 1) * (player:GetAttribute("TempThirstMult") or 1)
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
		state.Stamina = math.max(0, state.Stamina - ST.DrainPerSecond * (player:GetAttribute("TempStaminaDrainMult") or 1) * dt)
		state.LastSprint = os.clock()
		if state.Stamina <= 0 then
			setSprint(player, false)
		end
	else
		if os.clock() - state.LastSprint >= ST.RegenDelay then
			local regen = ST.RegenPerSecond * dt * (Workspace:GetAttribute("WorldStaminaRegenMultiplier") or 1) * (player:GetAttribute("TempStaminaRegenMult") or 1)
			if nauseaActive then
				regen *= NC.Effects.Nausea.StaminaRegenMultiplier
			end
			state.Stamina = math.min(ST.Max, state.Stamina + regen)
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
		if state.DamageTimer >= HG.DamageInterval then
			state.DamageTimer = 0
			humanoid:TakeDamage(HG.StarvationDamage)
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

	-- ruído dos passos (para ameaças futuras: 0 parado, 0.2 agachado, 1 andando, 1.8 correndo)
	local noise = 0
	if moving and alive then
		if state.InWater then
			noise = 0.5
		elseif state.Crouching then
			noise = Balance.CrouchNoise
		elseif state.Sprinting then
			noise = 1.8
		else
			noise = 1
		end
	end
	player:SetAttribute("NoiseLevel", noise)

	if humanoid then
		local slope = Balance.MaxSlopeAngle + (player:GetAttribute("ClimbBonus") or 0)
		if humanoid.MaxSlopeAngle ~= slope then humanoid.MaxSlopeAngle = slope end
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
	crouchRemote = remotes:FindFirstChild("CrouchRequest")
	if not crouchRemote then
		crouchRemote = Instance.new("RemoteEvent")
		crouchRemote.Name = "CrouchRequest"
		crouchRemote.Parent = remotes
	end
	log("Init concluído.")
end

function SurvivalService.Start()
	if running then return end
	running = true

	sprintRemote.OnServerEvent:Connect(onSprintRequest)
	crouchRemote.OnServerEvent:Connect(onCrouchRequest)
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

