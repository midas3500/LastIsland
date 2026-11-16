--[[
	MainHUDClient (LocalScript)
	Local: StarterGui > MainHUD (ScreenGui) > MainHUDClient (LocalScript)

	Toda a interface é criada por este script (você não precisa montar nada à mão).
	Mostra:
	- Barra de progresso da coleta (com botão X de cancelar, 44px para toque)
	- Avisos "+3 Madeira" e mensagens de erro
	- Contadores de recursos (lado esquerdo)
	O cliente NÃO decide nada: só exibe o que o servidor manda e pode pedir "Cancel".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local gui = script.Parent

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CollectRemote = Remotes:WaitForChild("CollectResource")
local InventoryRemote = Remotes:WaitForChild("UpdateInventory")

local WHITE = Color3.fromRGB(255, 255, 255)
local PANEL = Color3.fromRGB(18, 26, 38)

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function create(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function rounded(parent, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

-- O inventário padrão do Roblox (hotbar) atrapalha a ferramenta temporária de coleta
task.spawn(function()
	for _ = 1, 10 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

-- ===========================================================================
-- BARRA DE PROGRESSO
-- ===========================================================================

local bar = create("Frame", {
	Name = "GatherBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.86),
	Size = UDim2.fromScale(0.38, 0.08),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.12,
	Visible = false,
}, gui)
rounded(bar, 12)
create("UIStroke", { Color = WHITE, Transparency = 0.8, Thickness = 1.5 }, bar)
create("UISizeConstraint", { MinSize = Vector2.new(260, 56), MaxSize = Vector2.new(480, 76) }, bar)

local barLabel = create("TextLabel", {
	Name = "Label",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 14, 0, 4),
	Size = UDim2.new(1, -72, 0.45, 0),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = WHITE,
	Text = "",
}, bar)

local track = create("Frame", {
	Name = "Track",
	Position = UDim2.new(0, 14, 0.58, 0),
	Size = UDim2.new(1, -72, 0.28, 0),
	BackgroundColor3 = Color3.fromRGB(45, 58, 76),
}, bar)
rounded(track, 999)

local fill = create("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Color3.fromRGB(110, 200, 110),
}, track)
rounded(fill, 999)

local cancelButton = create("TextButton", {
	Name = "Cancel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(44, 44),
	BackgroundColor3 = Color3.fromRGB(190, 70, 70),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = WHITE,
	Text = "X",
}, bar)
rounded(cancelButton, 10)
create("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, cancelButton)

local currentTween = nil

local function hideBar()
	if currentTween then
		currentTween:Cancel()
		currentTween = nil
	end
	bar.Visible = false
	fill.Size = UDim2.fromScale(0, 1)
end

local function showBar(text, duration)
	hideBar()
	barLabel.Text = text
	bar.Visible = true
	currentTween = TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(1, 1),
	})
	currentTween:Play()
end

cancelButton.Activated:Connect(function()
	CollectRemote:FireServer("Cancel")
	hideBar()
end)

-- ===========================================================================
-- AVISOS (toasts)
-- ===========================================================================

local toastHolder = create("Frame", {
	Name = "Toasts",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.78),
	Size = UDim2.fromScale(0.4, 0.3),
	BackgroundTransparency = 1,
}, gui)
create("UISizeConstraint", { MinSize = Vector2.new(240, 0), MaxSize = Vector2.new(420, 400) }, toastHolder)
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, toastHolder)

local toastCounter = 0
local MAX_TOASTS = 5

local function showToast(text, color)
	toastCounter += 1

	-- limita a quantidade na tela
	local existing = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing >= MAX_TOASTS do
		existing[1]:Destroy()
		table.remove(existing, 1)
	end

	local label = create("TextLabel", {
		Name = "Toast",
		LayoutOrder = toastCounter,
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color or WHITE,
		Text = text,
	}, toastHolder)
	rounded(label, 10)
	create("UIPadding", {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
	}, label)

	task.delay(2.4, function()
		if label.Parent then
			local info = TweenInfo.new(0.4)
			TweenService:Create(label, info, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.delay(0.45, function()
				label:Destroy()
			end)
		end
	end)
end

-- ===========================================================================
-- CONTADORES DE RECURSOS
-- ===========================================================================

local panel = create("Frame", {
	Name = "Counters",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.45, 0),
	Size = UDim2.fromOffset(170, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.3,
}, gui)
rounded(panel, 12)
create("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, panel)
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
}, panel)

local countLabels = {}

do
	local ordered = {}
	for key, def in pairs(ResourceConfig.Items) do
		table.insert(ordered, { Key = key, Def = def })
	end
	table.sort(ordered, function(a, b)
		return (a.Def.Order or 99) < (b.Def.Order or 99)
	end)

	for index, entry in ipairs(ordered) do
		local row = create("Frame", {
			Name = entry.Key,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
		}, panel)

		local chip = create("Frame", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			BackgroundColor3 = entry.Def.Color,
		}, row)
		rounded(chip, 4)

		create("TextLabel", {
			Name = "Name",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 22, 0, 0),
			Size = UDim2.new(1, -66, 1, 0),
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = WHITE,
			Text = entry.Def.DisplayName,
		}, row)

		countLabels[entry.Key] = create("TextLabel", {
			Name = "Count",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 40, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = WHITE,
			Text = "0",
		}, row)
	end
end

local receivedInventory = false

InventoryRemote.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	receivedInventory = true
	for key, label in pairs(countLabels) do
		local count = snapshot[key]
		label.Text = tostring(type(count) == "number" and count or 0)
	end
end)

-- Pede o inventário (o servidor pode ter enviado antes desta tela existir)
InventoryRemote:FireServer("Request")
task.delay(3, function()
	if not receivedInventory then
		InventoryRemote:FireServer("Request")
	end
end)

-- ===========================================================================
-- MENSAGENS DO SERVIDOR (coleta)
-- ===========================================================================

CollectRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Start" and type(payload) == "table" then
		showBar(tostring(payload.Label or "Coletando..."), tonumber(payload.Duration) or 1)

	elseif action == "Done" and type(payload) == "table" then
		hideBar()
		for _, reward in ipairs(payload) do
			showToast(string.format("+%d %s", reward.Amount, reward.Name), Color3.fromRGB(140, 230, 140))
		end

	elseif action == "Cancel" then
		hideBar()
		showToast(tostring(payload), Color3.fromRGB(255, 190, 110))

	elseif action == "Denied" then
		showToast(tostring(payload), Color3.fromRGB(255, 190, 110))
	end
end)

-- ===========================================================================
-- RECURSOS DE OUTRAS ILHAS: esconde o botão de coletar (só visual; o servidor valida de verdade)
-- ===========================================================================

local function updatePrompt(prompt)
	local islandIndex = prompt:GetAttribute("IslandIndex") or 0
	local baseDistance = prompt:GetAttribute("BaseDistance") or 10
	local ownIndex = player:GetAttribute("IslandIndex") or 0

	if islandIndex > 0 and islandIndex ~= ownIndex then
		prompt.MaxActivationDistance = 0
	else
		prompt.MaxActivationDistance = baseDistance
	end
end

local function refreshAllPrompts()
	for _, prompt in ipairs(CollectionService:GetTagged("ResourcePrompt")) do
		updatePrompt(prompt)
	end
end

CollectionService:GetInstanceAddedSignal("ResourcePrompt"):Connect(updatePrompt)
player:GetAttributeChangedSignal("IslandIndex"):Connect(refreshAllPrompts)
refreshAllPrompts()