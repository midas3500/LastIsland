
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ResourceConfig = require(ReplicatedStorage.Modules.ResourceConfig)

local events = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = events:WaitForChild("UpdateInventory")
local upgradeRequest = events:WaitForChild("ToolUpgradeRequest")
local upgradeUpdate = events:WaitForChild("ToolUpgradeUpdate")

local gui = script.Parent
gui.ResetOnSpawn = false

local tools = {
	Axe = 1,
	Pickaxe = 1,
}

local inventory = {}

local function create(className, properties, parent)
	local object = Instance.new(className)

	for property, value in pairs(properties) do
		object[property] = value
	end

	object.Parent = parent
	return object
end

local main = create("Frame", {
	Name = "InventoryPanel",
	Size = UDim2.fromOffset(300, 390),
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(28, 34, 42),
	BorderSizePixel = 0,
	Visible = false,
}, gui)

create("UICorner", {
	CornerRadius = UDim.new(0, 12),
}, main)

local toggleButton = create("TextButton", {
	Name = "InventoryToggleButton",
	Size = UDim2.fromOffset(120, 44),
	Position = UDim2.new(1, -140, 1, -60),
	BackgroundColor3 = Color3.fromRGB(50, 120, 80),
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	Text = "MOCHILA",
	AutoButtonColor = true,
	Parent = gui,
}, gui)

create("UICorner", {
	CornerRadius = UDim.new(0, 10),
}, toggleButton)

local closeButton = create("TextButton", {
	Name = "CloseButton",
	Size = UDim2.fromOffset(32, 32),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	BackgroundColor3 = Color3.fromRGB(190, 70, 70),
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	Text = "X",
	AutoButtonColor = true,
}, main)

create("UICorner", {
	CornerRadius = UDim.new(0, 8),
}, closeButton)

local function setPanelVisible(visible)
	main.Visible = visible
	toggleButton.Text = visible and "FECHAR" or "MOCHILA"
end

toggleButton.MouseButton1Click:Connect(function()
	setPanelVisible(not main.Visible)
end)

closeButton.MouseButton1Click:Connect(function()
	setPanelVisible(false)
end)

local title = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 40),
	Position = UDim2.fromOffset(10, 5),
	BackgroundTransparency = 1,
	Text = "MOCHILA",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 22,
	Font = Enum.Font.GothamBold,
}, main)

local capacityLabel = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 28),
	Position = UDim2.fromOffset(10, 45),
	BackgroundTransparency = 1,
	Text = "Capacidade: 0/100",
	TextColor3 = Color3.fromRGB(180, 220, 180),
	TextSize = 15,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local list = create("Frame", {
	Size = UDim2.new(1, -20, 0, 150),
	Position = UDim2.fromOffset(10, 78),
	BackgroundTransparency = 1,
}, main)

local listLayout = create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local toolTitle = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 30),
	Position = UDim2.fromOffset(10, 235),
	BackgroundTransparency = 1,
	Text = "MELHORAR FERRAMENTAS",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 16,
	Font = Enum.Font.GothamBold,
}, main)

local function createToolButton(toolName, y)
	local button = create("TextButton", {
		Size = UDim2.new(1, -20, 0, 42),
		Position = UDim2.fromOffset(10, y),
		BackgroundColor3 = Color3.fromRGB(65, 105, 75),
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		Text = toolName .. " - Nível 1",
		AutoButtonColor = true,
	}, main)

	create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}, button)

	button.MouseButton1Click:Connect(function()
		upgradeRequest:FireServer("Upgrade", toolName)
	end)

	return button
end

local axeButton = createToolButton("Axe", 270)
local pickaxeButton = createToolButton("Pickaxe", 318)

local function updateInventory()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local used = 0
	local capacity = ResourceConfig.Inventory.BaseCapacity
	local items = {}

	for itemName, amount in pairs(inventory) do
		local definition = ResourceConfig.Items[itemName]

		if definition and type(amount) == "number" and amount > 0 then
			used += amount
			table.insert(items, {
				Name = itemName,
				Amount = amount,
				Order = definition.Order or 999,
				DisplayName = definition.DisplayName or itemName,
			})
		end
	end

	table.sort(items, function(a, b)
		return a.Order < b.Order
	end)

	for index, item in ipairs(items) do
		create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = item.DisplayName .. ": " .. item.Amount,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 14,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = index,
		}, list)
	end

	capacityLabel.Text = "Capacidade: " .. used .. "/" .. capacity

	if used >= capacity then
		capacityLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	else
		capacityLabel.TextColor3 = Color3.fromRGB(180, 220, 180)
	end
end

local function updateTools()
	axeButton.Text = "Machado - Nível " .. (tools.Axe or 1)
	pickaxeButton.Text = "Picareta - Nível " .. (tools.Pickaxe or 1)
end

inventoryRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	inventory = snapshot.Items or snapshot
	updateInventory()
end)

upgradeUpdate.OnClientEvent:Connect(function(action, first, second)
	if action == "State" then
		if type(first) == "table" then
			tools = first
			updateTools()
		end

	elseif action == "Result" then
		local success = first
		local message = second

		if message then
			print(message)
		end

		if success then
			upgradeRequest:FireServer("Request")
		end
	end
end)

inventoryRemote:FireServer("Request")
upgradeRequest:FireServer("Request")

updateInventory()
updateTools()
