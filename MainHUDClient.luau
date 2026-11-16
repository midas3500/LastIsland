
--[[
    InventoryClient v2
    Mochila com seleção, scroll, drop, lixeira e upgrades.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local gui = script.Parent

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))

local events = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = events:WaitForChild("UpdateInventory")
local upgradeRequest = events:WaitForChild("ToolUpgradeRequest")
local upgradeUpdate = events:WaitForChild("ToolUpgradeUpdate")

gui.ResetOnSpawn = false

local inventory = {}
local tools = {
	Axe = 1,
	Pickaxe = 1,
}

local selectedItem
local itemButtons = {}

local function create(className, properties, parent)
	local object = Instance.new(className)

	for property, value in pairs(properties) do
		object[property] = value
	end

	object.Parent = parent
	return object
end

local function corner(parent, radius)
	create("UICorner", {
		CornerRadius = UDim.new(0, radius or 10),
	}, parent)
end

local function stroke(parent, color, transparency)
	create("UIStroke", {
		Color = color or Color3.fromRGB(75, 90, 105),
		Transparency = transparency or 0.25,
		Thickness = 1,
	}, parent)
end

local function tween(object, properties, duration)
	TweenService:Create(
		object,
		TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		properties
	):Play()
end

-- BOTÃO PARA ABRIR
local toggle = create("TextButton", {
	Name = "InventoryToggleButton",
	Size = UDim2.fromOffset(132, 46),
	Position = UDim2.new(1, -150, 1, -65),
	BackgroundColor3 = Color3.fromRGB(43, 119, 79),
	Text = "??  MOCHILA",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 15,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
	ZIndex = 20,
}, gui)

corner(toggle, 12)

-- PAINEL PRINCIPAL
local main = create("Frame", {
	Name = "InventoryPanel",
	Size = UDim2.fromOffset(570, 430),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(24, 31, 39),
	BorderSizePixel = 0,
	Visible = false,
	ClipsDescendants = true,
}, gui)

corner(main, 16)
stroke(main, Color3.fromRGB(85, 110, 125), 0.15)

-- CABEÇALHO
local header = create("Frame", {
	Size = UDim2.new(1, 0, 0, 62),
	BackgroundColor3 = Color3.fromRGB(34, 45, 54),
	BorderSizePixel = 0,
}, main)

local title = create("TextLabel", {
	Size = UDim2.new(1, -75, 1, 0),
	Position = UDim2.fromOffset(20, 0),
	BackgroundTransparency = 1,
	Text = "??  SUA MOCHILA",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 21,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local close = create("TextButton", {
	Size = UDim2.fromOffset(36, 36),
	Position = UDim2.new(1, -48, 0.5, -18),
	BackgroundColor3 = Color3.fromRGB(170, 67, 67),
	Text = "?",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	AutoButtonColor = false,
}, header)

corner(close, 9)

-- CAPACIDADE
local capacity = create("TextLabel", {
	Size = UDim2.new(1, -30, 0, 28),
	Position = UDim2.fromOffset(15, 70),
	BackgroundTransparency = 1,
	Text = "Capacidade: 0 / 100",
	TextColor3 = Color3.fromRGB(180, 220, 190),
	TextSize = 14,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
}, main)

-- LISTA COM SCROLL
local list = create("ScrollingFrame", {
	Name = "ItemList",
	Size = UDim2.fromOffset(255, 235),
	Position = UDim2.fromOffset(15, 105),
	BackgroundColor3 = Color3.fromRGB(31, 40, 49),
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = Color3.fromRGB(100, 160, 125),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, main)

corner(list, 10)

local listLayout = create("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

create("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, list)

-- DETALHES DO ITEM
local details = create("Frame", {
	Size = UDim2.fromOffset(270, 235),
	Position = UDim2.fromOffset(285, 105),
	BackgroundColor3 = Color3.fromRGB(31, 40, 49),
	BorderSizePixel = 0,
}, main)

corner(details, 10)

local itemIcon = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 55),
	Position = UDim2.fromOffset(10, 10),
	BackgroundTransparency = 1,
	Text = "??",
	TextSize = 38,
	Font = Enum.Font.Gotham,
}, details)

local itemName = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 30),
	Position = UDim2.fromOffset(10, 65),
	BackgroundTransparency = 1,
	Text = "Selecione um item",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	TextWrapped = true,
}, details)

local itemAmount = create("TextLabel", {
	Size = UDim2.new(1, -20, 0, 24),
	Position = UDim2.fromOffset(10, 97),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(180, 205, 190),
	TextSize = 13,
	Font = Enum.Font.Gotham,
}, details)

local itemDescription = create("TextLabel", {
	Size = UDim2.new(1, -24, 0, 55),
	Position = UDim2.fromOffset(12, 125),
	BackgroundTransparency = 1,
	Text = "Escolha um item na lista para ver os detalhes.",
	TextColor3 = Color3.fromRGB(190, 195, 205),
	TextSize = 12,
	Font = Enum.Font.Gotham,
	TextWrapped = true,
	TextYAlignment = Enum.TextYAlignment.Top,
}, details)

local function actionButton(name, text, x, color)
	local button = create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(112, 34),
		Position = UDim2.fromOffset(x, 190),
		BackgroundColor3 = color,
		Text = text,
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
	}, details)

	corner(button, 8)
	return button
end

local dropButton = actionButton(
	"DropButton",
	"?? DROPAR 1",
	12,
	Color3.fromRGB(62, 115, 155)
)

local trashButton = actionButton(
	"TrashButton",
	"??? LIXEIRA",
	140,
	Color3.fromRGB(155, 72, 72)
)

-- UPGRADES
local upgradeTitle = create("TextLabel", {
	Size = UDim2.new(1, -30, 0, 25),
	Position = UDim2.fromOffset(15, 350),
	BackgroundTransparency = 1,
	Text = "??  MELHORIAS DE FERRAMENTAS",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 14,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local function makeUpgradeButton(name, x)
	local button = create("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(260, 42),
		Position = UDim2.fromOffset(x, 380),
		BackgroundColor3 = Color3.fromRGB(65, 105, 75),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextWrapped = true,
		AutoButtonColor = false,
	}, main)

	corner(button, 9)
	return button
end

local axeButton = makeUpgradeButton("AxeUpgrade", 15)
local pickaxeButton = makeUpgradeButton("PickaxeUpgrade", 295)

axeButton.MouseButton1Click:Connect(function()
	upgradeRequest:FireServer("Upgrade", "Axe")
end)

pickaxeButton.MouseButton1Click:Connect(function()
	upgradeRequest:FireServer("Upgrade", "Pickaxe")
end)

local function getCostText(toolName, nextTier)
	local costs = ResourceConfig.ToolUpgradeCosts[toolName]
	local cost = costs and costs[nextTier]

	if not cost then
		return "NÍVEL MÁXIMO"
	end

	local parts = {}

	for item, amount in pairs(cost) do
		local definition = ResourceConfig.Items[item]
		local emoji = definition and definition.Emoji or "??"
		table.insert(parts, emoji .. " " .. amount)
	end

	table.sort(parts)
	return table.concat(parts, "  ")
end

local function updateTools()
	local axeTier = tools.Axe or 1
	local pickTier = tools.Pickaxe or 1

	local axeNext = axeTier + 1
	local pickNext = pickTier + 1

	if axeTier >= 3 then
		axeButton.Text = "?? MACHADO • NÍVEL MÁXIMO"
		axeButton.BackgroundColor3 = Color3.fromRGB(75, 85, 75)
	else
		axeButton.Text = "?? MACHADO • NÍVEL " .. axeTier
			.. " ? " .. axeNext .. "\n" .. getCostText("Axe", axeNext)
		axeButton.BackgroundColor3 = Color3.fromRGB(65, 105, 75)
	end

	if pickTier >= 3 then
		pickaxeButton.Text = "?? PICARETA • NÍVEL MÁXIMO"
		pickaxeButton.BackgroundColor3 = Color3.fromRGB(75, 85, 75)
	else
		pickaxeButton.Text = "?? PICARETA • NÍVEL " .. pickTier
			.. " ? " .. pickNext .. "\n" .. getCostText("Pickaxe", pickNext)
		pickaxeButton.BackgroundColor3 = Color3.fromRGB(65, 105, 75)
	end
end

local function selectItem(item)
	selectedItem = item

	local definition = ResourceConfig.Items[item]
	local amount = inventory[item] or 0

	if not definition or amount <= 0 then
		selectedItem = nil
		itemIcon.Text = "??"
		itemName.Text = "Selecione um item"
		itemAmount.Text = ""
		itemDescription.Text = "Escolha um item na lista para ver os detalhes."
		return
	end

	itemIcon.Text = definition.Emoji or "??"
	itemName.Text = definition.DisplayName or item
	itemAmount.Text = "Quantidade: " .. amount
	itemDescription.Text = definition.Description or "Recurso coletado na ilha."

	if definition.Food then
		itemDescription.Text ..= "\n??? Recupera " .. (definition.HungerRestore or 0) .. " de fome."
	end

	for itemNameKey, button in pairs(itemButtons) do
		local active = itemNameKey == item
		button.BackgroundColor3 = active
			and Color3.fromRGB(58, 105, 83)
			or Color3.fromRGB(42, 52, 62)
	end
end

local function clearList()
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end

	table.clear(itemButtons)
end

local function updateInventory()
	clearList()

	local used = 0
	local items = {}

	for item, amount in pairs(inventory) do
		local definition = ResourceConfig.Items[item]

		if definition and type(amount) == "number" and amount > 0 then
			used += amount

			table.insert(items, {
				Name = item,
				Amount = amount,
				Order = definition.Order or 999,
			})
		end
	end

	table.sort(items, function(a, b)
		return a.Order < b.Order
	end)

	for index, entry in ipairs(items) do
		local definition = ResourceConfig.Items[entry.Name]

		local button = create("TextButton", {
			Name = entry.Name,
			Size = UDim2.new(1, -4, 0, 42),
			BackgroundColor3 = Color3.fromRGB(42, 52, 62),
			Text = (definition.Emoji or "??")
				.. "  " .. definition.DisplayName
				.. "     x" .. entry.Amount,
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			LayoutOrder = index,
		}, list)

		corner(button, 8)

		create("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
		}, button)

		button.MouseButton1Click:Connect(function()
			selectItem(entry.Name)
		end)

		itemButtons[entry.Name] = button
	end

	local maxCapacity = ResourceConfig.Inventory.BaseCapacity or 100
	capacity.Text = "?? Capacidade: " .. used .. " / " .. maxCapacity

	capacity.TextColor3 = used >= maxCapacity
		and Color3.fromRGB(255, 110, 110)
		or Color3.fromRGB(180, 220, 190)

	if selectedItem and (inventory[selectedItem] or 0) > 0 then
		selectItem(selectedItem)
	else
		selectItem(nil)
	end
end

dropButton.MouseButton1Click:Connect(function()
	if selectedItem then
		inventoryRemote:FireServer("Drop", selectedItem)
	end
end)

trashButton.MouseButton1Click:Connect(function()
	if selectedItem then
		inventoryRemote:FireServer("Trash", selectedItem)
	end
end)

local function setOpen(open)
	if open then
		main.Visible = true
		main.Size = UDim2.fromOffset(545, 410)

		tween(main, {
			Size = UDim2.fromOffset(570, 430),
		}, 0.2)

		toggle.Text = "?  FECHAR"
		inventoryRemote:FireServer("Request")
		upgradeRequest:FireServer("Request")
	else
		toggle.Text = "??  MOCHILA"

		tween(main, {
			Size = UDim2.fromOffset(545, 410),
		}, 0.15)

		task.delay(0.15, function()
			if main and main.Parent then
				main.Visible = false
			end
		end)
	end
end

toggle.MouseButton1Click:Connect(function()
	setOpen(not main.Visible)
end)

close.MouseButton1Click:Connect(function()
	setOpen(false)
end)

inventoryRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then
		return
	end

	inventory = data.Items or data
	updateInventory()
end)

upgradeUpdate.OnClientEvent:Connect(function(action, first, second)
	if action == "State" and type(first) == "table" then
		tools = first
		updateTools()

	elseif action == "Result" then
		local success = first
		local message = second

		if message then
			warn("[Mochila] " .. tostring(message))
		end

		if success then
			inventoryRemote:FireServer("Request")
		end
	end
end)

main.Visible = false
updateInventory()
updateTools()

inventoryRemote:FireServer("Request")
upgradeRequest:FireServer("Request")
