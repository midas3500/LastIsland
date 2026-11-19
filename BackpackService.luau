--[[
	BackpackService
	Local: ServerScriptService > Services > BackpackService   (ModuleScript, serviço com Init/Start)

	Melhoria da mochila gastando recursos. O servidor decide tudo:
	  - nível guardado em data.BackpackLevel (perfil do PlayerDataService)
	  - capacidade vem de BackpackConfig (via InventoryService.CapacityProvider, veja PATCHES.md)
	  - custo é cobrado com InventoryService.RemoveItems

	Remote: ReplicatedStorage > Remotes > BackpackUpgrade (criado aqui se não existir)
	  Cliente -> Servidor: "Request" | "Upgrade"
	  Servidor -> Cliente: "State", {Level, MaxLevel, Name, Emoji, Capacity, Next = {...}} | "Result", ok, mensagem

	Coloque DEPOIS de PlayerDataService e InventoryService em GameConfig.ServiceLoadOrder.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BackpackConfig = require(Modules:WaitForChild("BackpackConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))

local BackpackService = {}

local remote
local lastRequest = {}

local function baseCapacity()
	return (ResourceConfig.Inventory and ResourceConfig.Inventory.BaseCapacity) or 100
end

function BackpackService.GetLevel(player)
	local data = PlayerDataService.GetData(player)
	if not data then return 1 end
	local level = data.BackpackLevel
	if type(level) ~= "number" or level ~= level then level = 1 end
	return math.clamp(math.floor(level), 1, #BackpackConfig.Levels)
end

function BackpackService.GetCapacity(player)
	return BackpackConfig.GetCapacity(BackpackService.GetLevel(player), baseCapacity())
end

local function buildState(player)
	local level = BackpackService.GetLevel(player)
	local info = BackpackConfig.Levels[level]
	local state = {
		Level = level,
		MaxLevel = #BackpackConfig.Levels,
		Name = info.Name,
		Emoji = info.Emoji,
		Capacity = BackpackService.GetCapacity(player),
	}
	local nextInfo = BackpackConfig.Levels[level + 1]
	if nextInfo then
		state.Next = {
			Name = nextInfo.Name,
			Emoji = nextInfo.Emoji,
			Capacity = BackpackConfig.GetCapacity(level + 1, baseCapacity()),
			Cost = table.clone(nextInfo.Cost or {}),
		}
	end
	return state
end

local function sendState(player)
	if remote and player.Parent and PlayerDataService.IsLoaded(player) then
		remote:FireClient(player, "State", buildState(player))
	end
end

local function result(player, ok, message)
	if remote and player.Parent then
		remote:FireClient(player, "Result", ok, message)
	end
end

local function upgrade(player)
	if not PlayerDataService.IsLoaded(player) then
		return result(player, false, "Seus dados ainda estão carregando.")
	end
	local data = PlayerDataService.GetData(player)
	local level = BackpackService.GetLevel(player)
	local nextInfo = BackpackConfig.Levels[level + 1]
	if not nextInfo then
		return result(player, false, "Sua mochila já está no nível máximo.")
	end
	local cost = nextInfo.Cost or {}
	if not InventoryService.HasItems(player, cost) then
		return result(player, false, "Faltam recursos para esta melhoria.")
	end
	if not InventoryService.RemoveItems(player, cost, "BackpackUpgrade") then
		return result(player, false, "Não foi possível cobrar os recursos.")
	end
	data.BackpackLevel = level + 1
	InventoryService.Sync(player) -- reenvia itens + nova capacidade
	sendState(player)
	result(player, true, "Mochila melhorada: " .. nextInfo.Name .. "!")
end

function BackpackService.Init()
end

function BackpackService.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remote = remotes:FindFirstChild("BackpackUpgrade")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "BackpackUpgrade"
		remote.Parent = remotes
	end

	-- o InventoryService passa a perguntar a capacidade ao nível da mochila de cada jogador
	InventoryService.CapacityProvider = BackpackService.GetCapacity

	remote.OnServerEvent:Connect(function(player, action)
		if action ~= "Request" and action ~= "Upgrade" then return end
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 0.4 then return end
		lastRequest[player] = now
		if action == "Request" then
			sendState(player)
		else
			local ok, err = pcall(upgrade, player)
			if not ok then
				warn("[BackpackService] erro:", err)
				result(player, false, "Erro interno.")
			end
		end
	end)

	PlayerDataService.OnLoaded(function(player)
		sendState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)
end

return BackpackService