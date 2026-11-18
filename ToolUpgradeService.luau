
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ResourceConfig = require(ReplicatedStorage.Modules.ResourceConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)

local ToolUpgradeService = {}

local requestCooldown = {}
local COOLDOWN = 1

local function getRemotes()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")

	return remotes:WaitForChild("ToolUpgradeRequest"),
		remotes:WaitForChild("ToolUpgradeUpdate")
end

local function sendState(player, updateRemote)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end

	updateRemote:FireClient(player, "State", data.Tools or {})
end

local function upgrade(player, toolName, updateRemote)
	if type(toolName) ~= "string"
		or not ResourceConfig.Tools[toolName]
		or not ResourceConfig.ToolUpgradeCosts[toolName] then

		return false, "Ferramenta inválida."
	end
	if not PlayerDataService.IsLoaded(player) then
		return false, "Seus dados ainda estão carregando."
	end

	if PlayerDataService.IsReadOnly(player) then
		return false, "Seus dados estão em modo somente leitura."
	end

	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Dados do jogador indisponíveis."
	end

	data.Tools = data.Tools or {}

	local currentTier = tonumber(data.Tools[toolName]) or 1
	local nextTier = currentTier + 1

	if nextTier > 3 then
		return false, "Essa ferramenta já está no nível máximo."
	end

	local toolCosts = ResourceConfig.ToolUpgradeCosts[toolName]
	local cost = toolCosts and toolCosts[nextTier]

	if not cost then
		return false, "Melhoria não configurada."
	end

	if not InventoryService.HasItems(player, cost) then
		return false, "Você não possui todos os materiais."
	end

	if not InventoryService.RemoveItems(player, cost) then
		return false, "Não foi possível retirar os materiais."
	end

	data.Tools[toolName] = nextTier

	InventoryService.Sync(player)
	sendState(player, updateRemote)

	return true, toolName .. " melhorado para o nível " .. nextTier .. "!"
end

function ToolUpgradeService.Init()
	-- Os remotes são criados pelo Main a partir do GameConfig.
end

function ToolUpgradeService.Start()
	local requestRemote, updateRemote = getRemotes()

	requestRemote.OnServerEvent:Connect(function(player, action, toolName)
		local now = os.clock()
		local lastRequest = requestCooldown[player] or 0

		if now - lastRequest < COOLDOWN then
			return
		end

		requestCooldown[player] = now

		if action == "Request" then
			sendState(player, updateRemote)
			return
		end

		if action ~= "Upgrade" then
			return
		end

		local success, message = upgrade(player, toolName, updateRemote)

		updateRemote:FireClient(player, "Result", success, message)

		if success then
			sendState(player, updateRemote)
		end
	end)

	PlayerDataService.OnLoaded(function(player)
		sendState(player, updateRemote)
	end)

	Players.PlayerRemoving:Connect(function(player)
		requestCooldown[player] = nil
	end)
end

return ToolUpgradeService
