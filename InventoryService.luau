
--[[
    InventoryService v3
    Mochila, descarte e itens físicos no mundo.
    Servidor controla todas as operações.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local InventoryService = {}

local remote
local dirty = {}
local lastRequest = {}
local lastAction = {}

local DROP_LIFETIME = 120
local ACTION_COOLDOWN = 0.35
local LABEL_DISTANCE = 18
local PICKUP_DISTANCE = 10

local DROP_FOLDER_NAME = "WorldDrops"

local function getDropFolder()
	local folder = Workspace:FindFirstChild(DROP_FOLDER_NAME)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = DROP_FOLDER_NAME
		folder.Parent = Workspace
	end

	return folder
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

local function validAmount(amount)
	return type(amount) == "number"
		and amount == amount
		and amount >= 1
		and amount == math.floor(amount)
		and amount <= 1000000
end

local function snapshot(inventory)
	local copy = {}

	for item, count in pairs(inventory) do
		if ResourceConfig.Items[item]
			and type(count) == "number"
			and count > 0 then
			copy[item] = count
		end
	end

	return copy
end

local function flush(player)
	dirty[player] = nil

	if not remote or not player.Parent then
		return
	end

	local inventory = inventoryOf(player)

	if inventory then
		remote:FireClient(player, {
			Items = snapshot(inventory),
			Capacity = InventoryService.GetCapacity(),
		})
	end
end

local function markDirty(player)
	if dirty[player] then
		return
	end

	dirty[player] = true
	task.defer(flush, player)
end

local function getCapacity()
	return ResourceConfig.Inventory.BaseCapacity or 100
end

function InventoryService.GetUsedCapacity(player)
	local inventory = inventoryOf(player)

	if not inventory then
		return 0
	end

	local used = 0

	for item, amount in pairs(inventory) do
		if ResourceConfig.Items[item] and type(amount) == "number" then
			used += math.max(0, amount)
		end
	end

	return used
end

function InventoryService.GetCapacity()
	return getCapacity()
end

function InventoryService.GetFreeCapacity(player)
	return math.max(
		0,
		getCapacity() - InventoryService.GetUsedCapacity(player)
	)
end

function InventoryService.GetCount(player, item)
	local inventory = inventoryOf(player)

	if not inventory then
		return 0
	end

	local amount = inventory[item]
	return type(amount) == "number" and amount or 0
end

function InventoryService.GetRoom(player, item)
	local inventory = inventoryOf(player)
	local definition = ResourceConfig.Items[item]

	if not inventory or not definition then
		return 0
	end

	local current = inventory[item] or 0
	local stackRoom = math.max(0, (definition.MaxStack or 999) - current)

	return math.min(
		stackRoom,
		InventoryService.GetFreeCapacity(player)
	)
end

function InventoryService.CanAdd(player, item, amount)
	if not ResourceConfig.Items[item] or not inventoryOf(player) then
		return false
	end

	return InventoryService.GetRoom(player, item) >= (amount or 1)
end

function InventoryService.AddItem(player, item, amount, reason)
	if not ResourceConfig.Items[item] or not validAmount(amount) then
		return 0
	end

	local inventory = inventoryOf(player)

	if not inventory then
		return 0
	end

	local added = math.min(
		amount,
		InventoryService.GetRoom(player, item)
	)

	if added <= 0 then
		return 0
	end

	inventory[item] = InventoryService.GetCount(player, item) + added
	markDirty(player)

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

	local current = InventoryService.GetCount(player, item)

	if current < amount then
		return false
	end

	inventory[item] = current - amount

	if inventory[item] <= 0 then
		inventory[item] = nil
	end

	markDirty(player)
	return true
end

function InventoryService.HasItems(player, cost)
	if type(cost) ~= "table" then
		return false
	end

	for item, amount in pairs(cost) do
		if not ResourceConfig.Items[item]
			or not validAmount(amount)
			or InventoryService.GetCount(player, item) < amount then
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

-- VISUAL DOS RECURSOS DROPPADOS

local DROP_STYLES = {
	Wood = {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(1.5, 0.55, 0.65),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(126, 83, 48),
	},

	Stone = {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(1.05, 0.85, 0.95),
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(115, 119, 124),
	},

	Fiber = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 1.15, 0.35),
		Material = Enum.Material.Grass,
		Color = Color3.fromRGB(78, 145, 73),
	},

	IronOre = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.95, 0.85, 0.9),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(105, 116, 129),
	},

	GoldOre = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.85, 0.9),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(235, 184, 52),
	},

	Coconut = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.85, 0.85, 0.85),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(104, 70, 43),
	},
}

local function createDrop(player, item)
	local definition = ResourceConfig.Items[item]

	if not definition then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		return false
	end

	local style = DROP_STYLES[item] or {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(0.9, 0.9, 0.9),
		Material = Enum.Material.SmoothPlastic,
		Color = definition.Color or Color3.fromRGB(150, 150, 150),
	}

	local drop = Instance.new("Part")
	drop.Name = "Dropped_" .. item
	drop.Shape = style.Shape
	drop.Size = style.Size
	drop.Material = style.Material
	drop.Color = style.Color
	drop.Anchored = false
	drop.CanCollide = true
	drop.TopSurface = Enum.SurfaceType.Smooth
	drop.BottomSurface = Enum.SurfaceType.Smooth
	drop.Position = root.Position
		+ root.CFrame.LookVector * 3
		+ Vector3.new(0, 2, 0)

	drop.Parent = getDropFolder()

	drop:SetAttribute("ItemName", item)
	drop:SetAttribute("OwnerUserId", player.UserId)

	-- Nome visível somente de perto.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ItemLabel"
	billboard.Adornee = drop
	billboard.Size = UDim2.fromOffset(160, 38)
	billboard.StudsOffset = Vector3.new(0, 1.3, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = LABEL_DISTANCE
	billboard.Enabled = true
	billboard.Parent = drop

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(22, 29, 35)
	label.BackgroundTransparency = 0.15
	label.Text = string.upper(definition.DisplayName or item)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.7
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	local labelCorner = Instance.new("UICorner")
	labelCorner.CornerRadius = UDim.new(0, 8)
	labelCorner.Parent = label

	local labelStroke = Instance.new("UIStroke")
	labelStroke.Color = style.Color
	labelStroke.Thickness = 1.5
	labelStroke.Transparency = 0.1
	labelStroke.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Recolher"
	prompt.ObjectText = definition.DisplayName or item
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = drop

	local claimed = false

	prompt.Triggered:Connect(function(otherPlayer)
		if claimed or not drop.Parent then
			return
		end

		if not otherPlayer or not otherPlayer:IsA("Player") then
			return
		end

		if not PlayerDataService.IsLoaded(otherPlayer) then
			return
		end

		if not InventoryService.CanAdd(otherPlayer, item, 1) then
			return
		end

		claimed = true

		local added = InventoryService.AddItem(
			otherPlayer,
			item,
			1,
			"WorldPickup"
		)

		if added > 0 then
			drop:Destroy()
		else
			claimed = false
		end
	end)

	Debris:AddItem(drop, DROP_LIFETIME)

	return true
end

local function handleAction(player, action, item)
	if type(action) ~= "string" or type(item) ~= "string" then
		return
	end

	if not ResourceConfig.Items[item] then
		return
	end

	if not PlayerDataService.IsLoaded(player) then
		return
	end

	local now = os.clock()

	if lastAction[player]
		and now - lastAction[player] < ACTION_COOLDOWN then
		return
	end

	lastAction[player] = now

	if InventoryService.GetCount(player, item) < 1 then
		return
	end

	if action == "Drop" then
		if createDrop(player, item) then
			InventoryService.RemoveItem(player, item, 1, "Drop")
		end

	elseif action == "Trash" then
		InventoryService.RemoveItem(player, item, 1, "Trash")
	end
end

function InventoryService.Init()
end

function InventoryService.Start()
	remote = ReplicatedStorage
		:WaitForChild("Remotes")
		:WaitForChild("UpdateInventory")

	remote.OnServerEvent:Connect(function(player, action, item)
		if action == "Request" then
			local now = os.clock()

			if lastRequest[player]
				and now - lastRequest[player] < 1 then
				return
			end

			lastRequest[player] = now

			if PlayerDataService.IsLoaded(player) then
				markDirty(player)
			end

		elseif action == "Drop" or action == "Trash" then
			handleAction(player, action, item)
		end
	end)

	PlayerDataService.OnLoaded(function(player)
		markDirty(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
		lastRequest[player] = nil
		lastAction[player] = nil
	end)

	print("[InventoryService] Inventário v3 iniciado.")
end

return InventoryService
