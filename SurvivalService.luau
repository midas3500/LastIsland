
--[[
    SurvivalService
    Local: ServerScriptService > Services

    Controla:
    - Fome
    - Stamina
    - Corrida
    - Alimentação
    - Dano por fome
    - Ciclo de dia e noite

    O servidor controla todos os valores.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local GameConfig = require(Modules:WaitForChild("GameConfig"))
local Config = require(Modules:WaitForChild("SurvivalConfig"))

local PlayerDataService = require(
	script.Parent:WaitForChild("PlayerDataService")
)

local InventoryService = require(
	script.Parent:WaitForChild("InventoryService")
)

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

local function setSprint(player, enabled)
	local state = getState(player)

	if not state then
		return
	end

	if enabled then
		if state.Stamina < Config.Stamina.MinimumToSprint then
			enabled = false
		end

		if PlayerDataService.IsReadOnly(player) then
			-- Modo seguro: permite jogar, mas sem salvar.
		end
	end

	state.Sprinting = enabled

	player:SetAttribute("IsSprinting", enabled)

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid.WalkSpeed = enabled
			and Config.Stamina.SprintSpeed
			or Config.Stamina.WalkSpeed
	end
end

local function updateCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)

	if not humanoid then
		return
	end

	humanoid.WalkSpeed = Config.Stamina.WalkSpeed

	local state = getState(player)

	if state then
		state.Sprinting = false
		player:SetAttribute("IsSprinting", false)
	end
end

local function initializePlayer(player, data)
	if states[player] then
		return
	end

	data.Survival = data.Survival or {}

	local savedHunger = tonumber(data.Survival.Hunger) or Config.Hunger.Max

	local hunger = math.clamp(
		savedHunger,
		0,
		Config.Hunger.Max
	)

	states[player] = {
		Hunger = hunger,
		Stamina = Config.Stamina.Max,

		Sprinting = false,
		LastSprint = 0,

		DamageTimer = 0,
		SaveTimer = 0,
	}

	player:SetAttribute("MaxHunger", Config.Hunger.Max)
	player:SetAttribute("MaxStamina", Config.Stamina.Max)

	player:SetAttribute("Hunger", hunger)
	player:SetAttribute("Stamina", Config.Stamina.Max)

	player:SetAttribute("IsSprinting", false)
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

-- CORRIDA ------------------------------------------------

local function onSprintRequest(player, enabled)
	if typeof(enabled) ~= "boolean" then
		return
	end

	local now = os.clock()

	if lastSprintRequest[player]
		and now - lastSprintRequest[player] < 0.1 then
		return
	end

	lastSprintRequest[player] = now

	local state = getState(player)

	if not state then
		return
	end

	if enabled then
		if not PlayerDataService.IsLoaded(player) then
			return
		end

		if state.Stamina < Config.Stamina.MinimumToSprint then
			return
		end
	end

	setSprint(player, enabled)
end

-- ALIMENTAÇÃO --------------------------------------------

local function onFoodRequest(player, action)
	if action ~= "EatCoconut" then
		return
	end

	local now = os.clock()

	if lastFoodRequest[player]
		and now - lastFoodRequest[player] < 0.5 then
		return
	end

	lastFoodRequest[player] = now

	local state = getState(player)

	if not state then
		return
	end

	if not PlayerDataService.IsLoaded(player) then
		return
	end

	if state.Hunger >= Config.Hunger.Max then
		return
	end

	-- Verifica e remove o alimento no servidor.
	local removed = InventoryService.RemoveItem(
		player,
		"Coconut",
		1,
		"Alimentação"
	)

	if not removed then
		return
	end

	state.Hunger = math.clamp(
		state.Hunger + Config.Hunger.CoconutRestore,
		0,
		Config.Hunger.Max
	)

	player:SetAttribute("Hunger", state.Hunger)

	log(player.Name, "comeu um coco. Fome:", state.Hunger)
end

-- ATUALIZAÇÃO DA SOBREVIVÊNCIA ----------------------------

local function updatePlayer(player, deltaTime)
	local state = getState(player)

	if not state then
		return
	end

	if not PlayerDataService.IsLoaded(player) then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	local moving = humanoid
		and humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.05

	-- FOME
	state.Hunger = math.clamp(
		state.Hunger - Config.Hunger.DrainPerSecond * deltaTime,
		0,
		Config.Hunger.Max
	)

	-- STAMINA
	if state.Sprinting and moving then
		state.Stamina = math.max(
			0,
			state.Stamina - Config.Stamina.DrainPerSecond * deltaTime
		)

		state.LastSprint = os.clock()

		if state.Stamina <= 0 then
			setSprint(player, false)
		end
	else
		local elapsed = os.clock() - state.LastSprint

		if elapsed >= Config.Stamina.RegenDelay then
			state.Stamina = math.min(
				Config.Stamina.Max,
				state.Stamina + Config.Stamina.RegenPerSecond * deltaTime
			)
		end
	end

	-- DANO POR FOME
	if state.Hunger <= 0 and humanoid and humanoid.Health > 0 then
		state.DamageTimer += deltaTime

		if state.DamageTimer >= Config.Hunger.DamageInterval then
			state.DamageTimer = 0

			humanoid:TakeDamage(Config.Hunger.StarvationDamage)
		end
	else
		state.DamageTimer = 0
	end

	-- SALVA A FOME NA TABELA DO PERFIL.
	-- O autosave do PlayerDataService fará o salvamento real.
	if not PlayerDataService.IsReadOnly(player) then
		state.SaveTimer += deltaTime

		if state.SaveTimer >= Config.ProfileSaveInterval then
			state.SaveTimer = 0

			local data = PlayerDataService.GetData(player)

			if data then
				data.Survival = data.Survival or {}
				data.Survival.Hunger = state.Hunger
			end
		end
	end

	player:SetAttribute("Hunger", state.Hunger)
	player:SetAttribute("Stamina", state.Stamina)
end

-- DIA E NOITE ---------------------------------------------

local function updateDayNight(elapsed)
	local dayConfig = Config.DayNight

	local totalHours =
		dayConfig.StartClockTime
		+ (elapsed / dayConfig.FullDaySeconds) * 24

	local clockTime = totalHours % 24

	local dayNumber =
		dayConfig.StartDay
		+ math.floor(totalHours / 24)

	Lighting.ClockTime = clockTime
	Lighting:SetAttribute("DayNumber", dayNumber)
	Lighting:SetAttribute("WorldClockTime", clockTime)
end

-- INICIALIZAÇÃO -------------------------------------------

function SurvivalService.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	sprintRemote = remotes:WaitForChild("SprintRequest")
	foodRemote = remotes:WaitForChild("FoodRequest")

	log("Init concluído.")
end

function SurvivalService.Start()
	if running then
		return
	end

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

	local elapsed = 0
	local updateTimer = 0

	-- Relógio começa às 08:00.
	updateDayNight(elapsed)

	task.spawn(function()
		while running do
			local deltaTime = task.wait(Config.UpdateInterval)

			elapsed += deltaTime
			updateTimer += deltaTime

			updateDayNight(elapsed)

			for player in pairs(states) do
				updatePlayer(player, deltaTime)
			end
		end
	end)

	log("Sistema de sobrevivência iniciado.")
end

return SurvivalService
