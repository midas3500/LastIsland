--[[
	InventoryService
	Local: ServerScriptService > Services > InventoryService
	(SUBSTITUI o arquivo vazio da Etapa 1: Ctrl+A, Delete e cole este)

	Versão mínima, mas completa e segura: guarda os itens no perfil (data.Inventory),
	respeita o limite de pilha e sincroniza com o cliente pelo remote UpdateInventory.
	SÓ o servidor altera o inventário. O cliente apenas recebe cópias.

	API:
		InventoryService.GetCount(player, item)               -> number
		InventoryService.GetRoom(player, item)                -> quanto ainda cabe
		InventoryService.CanAdd(player, item, amount)         -> boolean
		InventoryService.AddItem(player, item, amount, why)   -> quantidade realmente adicionada
		InventoryService.RemoveItem(player, item, amount, why)-> boolean (tudo ou nada)
		InventoryService.HasItems(player, cost)               -> boolean   (cost = { Wood = 5, ... })
		InventoryService.RemoveItems(player, cost, why)       -> boolean   (tudo ou nada)
		InventoryService.Sync(player)                         -> reenvia o inventário ao cliente
]]	

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local InventoryService = {}

local remote = nil
local dirty = {}
local lastRequest = {}

local function log(...)
	if GameConfig.Debug then
		print("[InventoryService]", ...)
	end
end

local function inventoryOf(player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil
	end
	if type(data.Inventory) ~= "table" then
		data.Inventory = {}
	end
	return data.Inventory
end
local function getCapacity()
	return ResourceConfig.Inventory.BaseCapacity
end

function InventoryService.GetUsedCapacity(player)
	local inventory = inventoryOf(player)

	if not inventory then
		return 0
	end

	local used = 0

	for itemName, amount in pairs(inventory) do
		if ResourceConfig.Items[itemName] and type(amount) == "number" then
			used += math.max(0, amount)
		end
	end

	return used
end

function InventoryService.GetCapacity(player)
	return getCapacity()
end

function InventoryService.GetFreeCapacity(player)
	return math.max(
		0,
		InventoryService.GetCapacity(player)
		- InventoryService.GetUsedCapacity(player)
	)
end
local function validAmount(amount)
	return type(amount) == "number" and amount == amount and amount >= 1 and amount == math.floor(amount) and amount <= 1000000
end

local function snapshot(inventory)
	local copy = {}
	for item, count in pairs(inventory) do
		if ResourceConfig.Items[item] and type(count) == "number" then
			copy[item] = count
		end
	end
	return copy
end

local function flush(player)
	dirty[player] = nil
	if player.Parent == nil or not remote then
		return
	end
	local inventory = inventoryOf(player)
	if inventory then
		remote:FireClient(player, snapshot(inventory))
	end
end

-- Junta várias mudanças do mesmo instante em UM envio ao cliente
local function markDirty(player)
	if dirty[player] then
		return
	end
	dirty[player] = true
	task.defer(flush, player)
end

function InventoryService.GetCount(player, item)
	local inventory = inventoryOf(player)
	if not inventory then
		return 0
	end
	local count = inventory[item]
	return type(count) == "number" and count or 0
end

function InventoryService.GetRoom(player, itemName)
	local inventory = inventoryOf(player)
	local itemDef = ResourceConfig.Items[itemName]

	if not inventory or not itemDef then
		return 0
	end

	local currentAmount = inventory[itemName] or 0

	local stackRoom = math.max(
		0,
		itemDef.MaxStack - currentAmount
	)

	local backpackRoom = InventoryService.GetFreeCapacity(player)

	return math.min(stackRoom, backpackRoom)
end

function InventoryService.CanAdd(player, item, amount)
	if not ResourceConfig.Items[item] or not inventoryOf(player) then
		return false
	end
	return InventoryService.GetRoom(player, item) >= (amount or 1)
end

function InventoryService.AddItem(player, item, amount, reason)
	if not ResourceConfig.Items[item] or not validAmount(amount) then
		warn("[InventoryService] AddItem inválido:", tostring(item), tostring(amount))
		return 0
	end
	local inventory = inventoryOf(player)
	if not inventory then
		return 0
	end

	local added = math.min(amount, InventoryService.GetRoom(player, item))
	if added <= 0 then
		return 0
	end

	inventory[item] = InventoryService.GetCount(player, item) + added
	markDirty(player)
	log(string.format("%s +%d %s (%s) -> %d", player.Name, added, item, tostring(reason or "?"), inventory[item]))
	return added
end

function InventoryService.RemoveItem(player, item, amount, reason)
	if not ResourceConfig.Items[item] or not validAmount(amount) then
		return false
	end
	local inventory = inventoryOf(player)
	if not inventory then
		return false
	end

	local count = InventoryService.GetCount(player, item)
	if count < amount then
		return false
	end

	inventory[item] = count - amount
	markDirty(player)
	log(string.format("%s -%d %s (%s) -> %d", player.Name, amount, item, tostring(reason or "?"), inventory[item]))
	return true
end

function InventoryService.HasItems(player, cost)
	if type(cost) ~= "table" then
		return false
	end
	for item, amount in pairs(cost) do
		if not ResourceConfig.Items[item] or not validAmount(amount) then
			return false
		end
		if InventoryService.GetCount(player, item) < amount then
			return false
		end
	end
	return true
end

function InventoryService.RemoveItems(player, cost, reason)
	if not InventoryService.HasItems(player, cost) then
		return false
	end
	for item, amount in pairs(cost) do
		InventoryService.RemoveItem(player, item, amount, reason)
	end
	return true
end

function InventoryService.Sync(player)
	markDirty(player)
end

function InventoryService.Init()
end

function InventoryService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdateInventory")

	-- O cliente só pode PEDIR o inventário (nunca alterá-lo)
	remote.OnServerEvent:Connect(function(player, action)
		if action ~= "Request" then
			return
		end
		local now = os.clock()
		if lastRequest[player] and now - lastRequest[player] < 1 then
			return
		end
		lastRequest[player] = now
		markDirty(player)
	end)

	PlayerDataService.OnLoaded(function(player)
		markDirty(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastRequest[player] = nil
	end)

	log("Pronto.")
end

return InventoryService