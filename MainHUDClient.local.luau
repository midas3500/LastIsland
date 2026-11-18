--[[
	MainHUDClient (v2) - NOVA MOCHILA  (tipo: LocalScript)
	Local: o mesmo LocalScript "MainHUDClient" que você já tem (SUBSTITUA o conteúdo).
	Se ele não estiver dentro de um ScreenGui, este script cria o próprio ScreenGui.

	Recursos: grade de itens com abas e busca, painel de detalhes, soltar/descartar/comer,
	aviso "+3 Madeira" ao coletar, barra de capacidade, MELHORIA DA MOCHILA gastando recursos
	e melhoria de ferramentas (Machado/Picareta).
	Tecla B abre/fecha. ESC fecha.

	Remotes usados (os mesmos do seu jogo):
	  UpdateInventory ("Request" | "Drop", item | "Trash", item)  <- servidor envia {Items, Capacity}
	  ToolUpgradeRequest / ToolUpgradeUpdate (melhoria de ferramentas)
	  BackpackUpgrade (do BackpackService novo)
	  FoodRequest("EatCoconut")
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = script.Parent
if not gui:IsA("ScreenGui") then
	gui = Instance.new("ScreenGui")
	gui.Name = "BackpackGui"
	gui.Parent = playerGui
end
gui.ResetOnSpawn = false
gui.DisplayOrder = 10

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local okBP, BackpackConfig = pcall(function() return require(Modules:WaitForChild("BackpackConfig", 5)) end)
if not okBP then BackpackConfig = nil end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = remotes:WaitForChild("UpdateInventory")
local foodRemote = remotes:FindFirstChild("FoodRequest")
local toolRequest = remotes:FindFirstChild("ToolUpgradeRequest")
local toolUpdate = remotes:FindFirstChild("ToolUpgradeUpdate")
local backpackRemote = remotes:WaitForChild("BackpackUpgrade", 8)

----------------------------------------------------------------------
-- Estado
----------------------------------------------------------------------
local items, capacity = {}, 100
local previousItems = nil
local backpack = nil   -- estado vindo do BackpackService
local tools = {}       -- estado vindo do ToolUpgradeUpdate
local selected = nil
local filter = "Tudo"
local search = ""
local isOpen = false
local statusText = ""

----------------------------------------------------------------------
-- Tema e helpers
----------------------------------------------------------------------
local C = {
	Window = Color3.fromRGB(17, 22, 30),
	Panel = Color3.fromRGB(26, 33, 44),
	Slot = Color3.fromRGB(33, 42, 55),
	Stroke = Color3.fromRGB(150, 175, 200),
	Text = Color3.fromRGB(242, 246, 250),
	Muted = Color3.fromRGB(150, 166, 182),
	Accent = Color3.fromRGB(90, 190, 255),
	Good = Color3.fromRGB(110, 225, 150),
	Bad = Color3.fromRGB(255, 120, 110),
	Warn = Color3.fromRGB(255, 200, 100),
}

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in props do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(parent, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, parent) end
local function stroke(parent, transparency, color)
	return new("UIStroke", { Color = color or C.Stroke, Transparency = transparency or 0.75, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end
local function label(parent, props)
	local l = new("TextLabel", props, parent)
	l.BackgroundTransparency = 1
	if not props.Font then l.Font = Enum.Font.GothamMedium end
	if not props.TextColor3 then l.TextColor3 = C.Text end
	return l
end
local function button(parent, props)
	local b = new("TextButton", props, parent)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	if not props.Font then b.Font = Enum.Font.GothamBold end
	if not props.TextColor3 then b.TextColor3 = Color3.new(1, 1, 1) end
	corner(b, 9)
	return b
end

local ORE = { IronOre = true, GoldOre = true, CopperOre = true, Coal = true, Stone = true, Crystal = true, Obsidian = true, Sulfur = true, Clay = true }

local function defOf(id) return ResourceConfig.Items[id] end
local function nameOf(id) local d = defOf(id) return d and d.DisplayName or id end
local function iconOf(id)
	local d = defOf(id)
	local e = d and d.Emoji
	if e and e ~= "" and not e:find("%?%?") then return e end
	local n = nameOf(id)
	return n:sub(1, 1):upper()
end
local function colorOf(id)
	local d = defOf(id)
	return (d and d.Color) or C.Accent
end
local function categoryOf(id)
	local d = defOf(id)
	if d and d.Food then return "Comida" end
	if ORE[id] then return "Minérios" end
	return "Materiais"
end
local function countOf(id) return items[id] or 0 end
local function usedSpace()
	local n = 0
	for _, c in items do n += c end
	return n
end

----------------------------------------------------------------------
-- Botão de abrir (lado direito)
----------------------------------------------------------------------
local viewScale = math.clamp(Workspace.CurrentCamera.ViewportSize.X / 1000, 0.7, 1)

local toggle = button(gui, {
	Name = "InventoryToggleButton",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -130),
	Size = UDim2.fromOffset(132, 48),
	BackgroundColor3 = C.Window,
	Text = "",
})
toggle.BackgroundTransparency = 0.1
stroke(toggle, 0.6)
new("UIScale", { Scale = viewScale }, toggle).Name = "BaseScale"
label(toggle, { Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(34, 40), Text = "🎒", TextSize = 26, Font = Enum.Font.GothamBold })
label(toggle, { Position = UDim2.fromOffset(46, 5), Size = UDim2.fromOffset(80, 16), Text = "Mochila [B]", TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local toggleCount = label(toggle, { Position = UDim2.fromOffset(46, 22), Size = UDim2.fromOffset(80, 14), Text = "0/100", TextSize = 11, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
local toggleTrack = new("Frame", { Position = UDim2.fromOffset(46, 38), Size = UDim2.fromOffset(78, 4), BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, toggle)
corner(toggleTrack, 2)
local toggleFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, toggleTrack)
corner(toggleFill, 2)

----------------------------------------------------------------------
-- Janela
----------------------------------------------------------------------
local window = new("CanvasGroup", {
	Name = "BackpackWindow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(800, 560),
	BackgroundColor3 = C.Window,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
}, gui)
corner(window, 18)
stroke(window, 0.6)
local windowScale = new("UIScale", { Scale = viewScale * 0.94 }, window)

-- cabeçalho
label(window, { Position = UDim2.fromOffset(22, 12), Size = UDim2.fromOffset(300, 28), Text = "🎒  Mochila", TextSize = 22, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local subtitle = label(window, { Position = UDim2.fromOffset(24, 40), Size = UDim2.fromOffset(340, 16), Text = "", TextSize = 12, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })

local capText = label(window, { Position = UDim2.new(1, -330, 0, 14), Size = UDim2.fromOffset(250, 16), Text = "0 / 100", TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right })
local capTrack = new("Frame", { Position = UDim2.new(1, -330, 0, 36), Size = UDim2.fromOffset(250, 12), BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, window)
corner(capTrack, 6)
local capFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, BorderSizePixel = 0 }, capTrack)
corner(capFill, 6)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)) }, capFill)

local closeButton = button(window, { Position = UDim2.new(1, -56, 0, 14), Size = UDim2.fromOffset(38, 38), BackgroundColor3 = Color3.fromRGB(70, 40, 48), Text = "✕", TextSize = 16 })

-- barra de ferramentas (abas + busca)
local toolbar = new("Frame", { Position = UDim2.fromOffset(20, 70), Size = UDim2.fromOffset(500, 34), BackgroundTransparency = 1 }, window)
local tabButtons = {}
local TABS = { "Tudo", "Materiais", "Comida", "Minérios" }

-- grade
local gridFrame = new("ScrollingFrame", {
	Position = UDim2.fromOffset(20, 112), Size = UDim2.fromOffset(500, 268), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25,
	BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.Muted, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, window)
corner(gridFrame, 12)
new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, gridFrame)
new("UIGridLayout", { CellSize = UDim2.fromOffset(86, 92), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, gridFrame)
local emptyLabel = label(window, { Position = UDim2.fromOffset(20, 200), Size = UDim2.fromOffset(500, 60), Text = "Nada por aqui ainda.\nColete recursos na ilha!", TextSize = 14, TextColor3 = C.Muted, Visible = false })

-- detalhes
local detail = new("Frame", { Position = UDim2.fromOffset(536, 70), Size = UDim2.fromOffset(244, 310), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, window)
corner(detail, 12)
local dIconBg = new("Frame", { Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, detail)
corner(dIconBg, 14)
local dIconStroke = stroke(dIconBg, 0.3, C.Accent)
local dIcon = label(dIconBg, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 36, Font = Enum.Font.GothamBold })
local dName = label(detail, { Position = UDim2.fromOffset(92, 18), Size = UDim2.fromOffset(142, 24), Text = "Selecione um item", TextSize = 16, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
local dCat = label(detail, { Position = UDim2.fromOffset(92, 44), Size = UDim2.fromOffset(142, 14), Text = "", TextSize = 11, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
local dCount = label(detail, { Position = UDim2.fromOffset(92, 60), Size = UDim2.fromOffset(142, 20), Text = "", TextSize = 14, Font = Enum.Font.GothamBold, TextColor3 = C.Accent, TextXAlignment = Enum.TextXAlignment.Left })
local dDesc = label(detail, { Position = UDim2.fromOffset(16, 92), Size = UDim2.fromOffset(212, 90), Text = "", TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
local dTag = label(detail, { Position = UDim2.fromOffset(16, 184), Size = UDim2.fromOffset(212, 18), Text = "", TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Left })
local eatBtn = button(detail, { Position = UDim2.fromOffset(16, 214), Size = UDim2.fromOffset(212, 32), BackgroundColor3 = Color3.fromRGB(176, 120, 58), Text = "🥥  Comer  [F]", TextSize = 13, Visible = false })
local dropBtn = button(detail, { Position = UDim2.fromOffset(16, 256), Size = UDim2.fromOffset(100, 34), BackgroundColor3 = Color3.fromRGB(52, 112, 168), Text = "Soltar 1", TextSize = 13 })
local trashBtn = button(detail, { Position = UDim2.fromOffset(128, 256), Size = UDim2.fromOffset(100, 34), BackgroundColor3 = Color3.fromRGB(160, 62, 70), Text = "Descartar 1", TextSize = 13 })

-- rodapé: melhorias
local footer = new("Frame", { Position = UDim2.fromOffset(20, 392), Size = UDim2.fromOffset(760, 156), BackgroundTransparency = 1 }, window)

local upCard = new("Frame", { Size = UDim2.fromOffset(470, 156), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, footer)
corner(upCard, 12)
local upTitle = label(upCard, { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(300, 20), Text = "⬆️  Melhorar mochila", TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local upInfo = label(upCard, { Position = UDim2.fromOffset(16, 32), Size = UDim2.fromOffset(438, 18), Text = "", TextSize = 12, TextColor3 = C.Muted, TextXAlignment = Enum.TextXAlignment.Left })
local costHolder = new("Frame", { Position = UDim2.fromOffset(16, 56), Size = UDim2.fromOffset(438, 52), BackgroundTransparency = 1 }, upCard)
new("UIGridLayout", { CellSize = UDim2.fromOffset(104, 24), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }, costHolder)
local upgradeBtn = button(upCard, { Position = UDim2.fromOffset(16, 114), Size = UDim2.fromOffset(150, 32), BackgroundColor3 = Color3.fromRGB(46, 128, 92), Text = "Melhorar", TextSize = 14 })
local upStatus = label(upCard, { Position = UDim2.fromOffset(176, 114), Size = UDim2.fromOffset(280, 32), Text = "", TextSize = 12, TextColor3 = C.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })

local toolCard = new("Frame", { Position = UDim2.fromOffset(482, 0), Size = UDim2.fromOffset(278, 156), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, footer)
corner(toolCard, 12)
label(toolCard, { Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(240, 20), Text = "🛠️  Ferramentas", TextSize = 15, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
local toolRows = {}
local TOOLS = { { Id = "Axe", Name = "Machado", Emoji = "🪓" }, { Id = "Pickaxe", Name = "Picareta", Emoji = "⛏️" } }
for i, t in TOOLS do
	local y = 36 + (i - 1) * 56
	local row = new("Frame", { Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(254, 50), BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, toolCard)
	corner(row, 10)
	label(row, { Position = UDim2.fromOffset(8, 4), Size = UDim2.fromOffset(30, 42), Text = t.Emoji, TextSize = 22, Font = Enum.Font.GothamBold })
	local nameL = label(row, { Position = UDim2.fromOffset(42, 5), Size = UDim2.fromOffset(110, 16), Text = t.Name, TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
	local costL = label(row, { Position = UDim2.fromOffset(42, 22), Size = UDim2.fromOffset(110, 24), Text = "", TextSize = 10, TextColor3 = C.Muted, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local btn = button(row, { Position = UDim2.new(1, -92, 0.5, -15), Size = UDim2.fromOffset(84, 30), BackgroundColor3 = Color3.fromRGB(176, 120, 58), Text = "Nv 1", TextSize = 11 })
	toolRows[t.Id] = { Name = nameL, Cost = costL, Button = btn }
	btn.Activated:Connect(function()
		if toolRequest then toolRequest:FireServer("Upgrade", t.Id) end
	end)
end

-- busca
local searchBox = new("TextBox", {
	Position = UDim2.fromOffset(300, 0), Size = UDim2.fromOffset(200, 34), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.25,
	PlaceholderText = "🔍  Buscar item...", PlaceholderColor3 = C.Muted, Text = "", TextColor3 = C.Text, TextSize = 13,
	Font = Enum.Font.GothamMedium, ClearTextOnFocus = false, BorderSizePixel = 0,
}, toolbar)
corner(searchBox, 9)
stroke(searchBox, 0.8)

----------------------------------------------------------------------
-- Avisos "+3 Madeira"
----------------------------------------------------------------------
local toastHolder = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, -20), Size = UDim2.fromOffset(220, 260), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, toastHolder)
local toastOrder = 0

local function toast(text, color)
	toastOrder += 1
	local t = new("TextLabel", {
		LayoutOrder = toastOrder, Size = UDim2.fromOffset(200, 30), BackgroundColor3 = C.Window, BackgroundTransparency = 0.15,
		Text = text, TextColor3 = color or C.Text, TextSize = 13, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
	}, toastHolder)
	corner(t, 9)
	stroke(t, 0.6, color or C.Accent)
	task.delay(2.4, function()
		TweenService:Create(t, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.45)
		t:Destroy()
	end)
end

----------------------------------------------------------------------
-- Atualização da interface
----------------------------------------------------------------------
local slotButtons = {}

local function sortedItems()
	local list = {}
	for id, count in items do
		if count > 0 then
			local passes = (filter == "Tudo" or categoryOf(id) == filter)
			if passes and search ~= "" then
				passes = nameOf(id):lower():find(search:lower(), 1, true) ~= nil
			end
			if passes then table.insert(list, id) end
		end
	end
	table.sort(list, function(a, b)
		local da, db = defOf(a), defOf(b)
		local oa, ob = (da and da.Order) or 999, (db and db.Order) or 999
		if oa ~= ob then return oa < ob end
		return a < b
	end)
	return list
end

local function refreshDetail()
	if selected and countOf(selected) <= 0 then selected = nil end
	if not selected then
		dIcon.Text, dName.Text, dCat.Text, dCount.Text, dDesc.Text, dTag.Text = "", "Selecione um item", "", "", "Toque em um item da mochila para ver detalhes.", ""
		dIconStroke.Color = C.Muted
		eatBtn.Visible = false
		dropBtn.Visible, trashBtn.Visible = false, false
		return
	end
	local d = defOf(selected)
	dIcon.Text = iconOf(selected)
	dName.Text = nameOf(selected)
	dCat.Text = categoryOf(selected)
	dCount.Text = "x" .. countOf(selected)
	dDesc.Text = (d and d.Description) or ""
	dIconStroke.Color = colorOf(selected)
	local tag = ""
	if d and d.HungerRestore then tag = "🍖 +" .. d.HungerRestore .. " de fome" end
	if d and d.HealRestore then tag = "❤️ +" .. d.HealRestore .. " de vida" end
	dTag.Text = tag
	eatBtn.Visible = (selected == "Coconut")
	dropBtn.Visible, trashBtn.Visible = true, true
end

local function rebuildGrid()
	for _, b in slotButtons do b:Destroy() end
	table.clear(slotButtons)
	local list = sortedItems()
	emptyLabel.Visible = #list == 0
	for i, id in list do
		local isSel = (id == selected)
		local slot = new("TextButton", {
			Name = id, LayoutOrder = i, BackgroundColor3 = C.Slot, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
		}, gridFrame)
		corner(slot, 11)
		local st = stroke(slot, isSel and 0 or 0.85, isSel and C.Accent or C.Stroke)
		st.Thickness = isSel and 2 or 1.2
		local accent = new("Frame", { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 0, 3), BackgroundColor3 = colorOf(id), BorderSizePixel = 0 }, slot)
		corner(accent, 2)
		label(slot, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), Text = iconOf(id), TextSize = 30, Font = Enum.Font.GothamBold })
		label(slot, { Position = UDim2.fromOffset(4, 56), Size = UDim2.new(1, -8, 0, 28), Text = nameOf(id), TextSize = 10, TextWrapped = true, TextColor3 = C.Muted })
		local badge = label(slot, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 7), Size = UDim2.fromOffset(34, 16), Text = tostring(countOf(id)), TextSize = 11, Font = Enum.Font.GothamBold })
		badge.BackgroundTransparency = 0.25
		badge.BackgroundColor3 = C.Window
		corner(badge, 8)
		slot.Activated:Connect(function()
			selected = id
			rebuildGrid()
			refreshDetail()
		end)
		slotButtons[id] = slot
	end
end

local function refreshCapacity()
	local used = usedSpace()
	local pct = capacity > 0 and math.clamp(used / capacity, 0, 1) or 0
	local color = pct >= 0.95 and C.Bad or (pct >= 0.75 and C.Warn or C.Accent)
	capText.Text = string.format("%d / %d", used, capacity)
	toggleCount.Text = string.format("%d/%d", used, capacity)
	TweenService:Create(capFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(pct, 1), BackgroundColor3 = color }):Play()
	TweenService:Create(toggleFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(pct, 1), BackgroundColor3 = color }):Play()
end

local function refreshUpgrade()
	for _, c in costHolder:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	if not backpack then
		subtitle.Text = ""
		upInfo.Text = backpackRemote and "Carregando..." or "Instale o BackpackService para melhorar a mochila."
		upgradeBtn.Visible = false
		return
	end
	subtitle.Text = string.format("%s %s  •  Nível %d/%d", backpack.Emoji or "🎒", backpack.Name, backpack.Level, backpack.MaxLevel)
	local nextInfo = backpack.Next
	if not nextInfo then
		upInfo.Text = "Sua mochila está no nível máximo! 🎉"
		upgradeBtn.Visible = false
		return
	end
	upgradeBtn.Visible = true
	upInfo.Text = string.format("%s %s  •  Capacidade %d → %d", nextInfo.Emoji or "🎒", nextInfo.Name, backpack.Capacity, nextInfo.Capacity)

	local affordable = true
	local order = 0
	for item, need in nextInfo.Cost do
		order += 1
		local have = countOf(item)
		local ok = have >= need
		if not ok then affordable = false end
		local chip = new("Frame", { LayoutOrder = order, BackgroundColor3 = C.Slot, BorderSizePixel = 0 }, costHolder)
		corner(chip, 8)
		stroke(chip, 0.4, ok and C.Good or C.Bad)
		label(chip, {
			Size = UDim2.fromScale(1, 1), Text = string.format("%s %d/%d", iconOf(item), math.min(have, 999), need),
			TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = ok and C.Good or C.Bad,
		})
	end
	upgradeBtn.BackgroundColor3 = affordable and Color3.fromRGB(46, 150, 100) or Color3.fromRGB(70, 78, 90)
	upgradeBtn.Text = affordable and "⬆️  Melhorar" or "Faltam recursos"
end

local function refreshTools()
	for _, t in TOOLS do
		local row = toolRows[t.Id]
		local v = tools[t.Id]
		if type(v) == "table" then v = v.Tier or v.Level end
		local tier = type(v) == "number" and v or 1
		row.Button.Text = "Nv " .. tier .. "  ⬆️"
		local costs = ResourceConfig.ToolUpgradeCosts
		local cost = type(costs) == "table" and type(costs[t.Id]) == "table" and costs[t.Id][tier + 1]
		if type(cost) == "table" then
			local parts = {}
			for item, need in cost do
				if type(need) == "number" then
					table.insert(parts, string.format("%s %d/%d", iconOf(item), countOf(item), need))
				end
			end
			row.Cost.Text = #parts > 0 and table.concat(parts, "  ") or ""
		else
			row.Cost.Text = (type(costs) == "table") and "Nível máximo?" or ""
		end
	end
end

local function refreshAll()
	refreshCapacity()
	rebuildGrid()
	refreshDetail()
	refreshUpgrade()
	refreshTools()
end

----------------------------------------------------------------------
-- Abas e busca
----------------------------------------------------------------------
local function refreshTabs()
	for name, b in tabButtons do
		local on = name == filter
		b.BackgroundColor3 = on and C.Accent or C.Panel
		b.TextColor3 = on and Color3.fromRGB(10, 20, 30) or C.Muted
		b.BackgroundTransparency = on and 0 or 0.25
	end
end

for i, name in TABS do
	local b = button(toolbar, { Position = UDim2.fromOffset((i - 1) * 74, 0), Size = UDim2.fromOffset(70, 34), BackgroundColor3 = C.Panel, Text = name, TextSize = 12 })
	tabButtons[name] = b
	b.Activated:Connect(function()
		filter = name
		refreshTabs()
		rebuildGrid()
	end)
end
refreshTabs()

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	search = searchBox.Text
	rebuildGrid()
end)

----------------------------------------------------------------------
-- Ações
----------------------------------------------------------------------
dropBtn.Activated:Connect(function()
	if selected then inventoryRemote:FireServer("Drop", selected) end
end)
trashBtn.Activated:Connect(function()
	if selected then inventoryRemote:FireServer("Trash", selected) end
end)
eatBtn.Activated:Connect(function()
	if foodRemote then foodRemote:FireServer("EatCoconut") end
end)
upgradeBtn.Activated:Connect(function()
	if backpackRemote then backpackRemote:FireServer("Upgrade") end
end)

----------------------------------------------------------------------
-- Abrir / fechar
----------------------------------------------------------------------
local function setOpen(open)
	if open == isOpen then return end
	isOpen = open
	if open then
		window.Visible = true
		windowScale.Scale = viewScale * 0.94
		TweenService:Create(window, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
		TweenService:Create(windowScale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = viewScale }):Play()
		inventoryRemote:FireServer("Request")
		if backpackRemote then backpackRemote:FireServer("Request") end
		if toolRequest then toolRequest:FireServer("Request") end
	else
		local tw = TweenService:Create(window, TweenInfo.new(0.16), { GroupTransparency = 1 })
		TweenService:Create(windowScale, TweenInfo.new(0.16), { Scale = viewScale * 0.96 }):Play()
		tw:Play()
		tw.Completed:Connect(function()
			if not isOpen then window.Visible = false end
		end)
	end
end

toggle.Activated:Connect(function() setOpen(not isOpen) end)
closeButton.Activated:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not isOpen)
	elseif input.KeyCode == Enum.KeyCode.Escape and isOpen then
		setOpen(false)
	end
end)

----------------------------------------------------------------------
-- Dados do servidor
----------------------------------------------------------------------
inventoryRemote.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	local newItems = data.Items or {}
	if previousItems then
		for id, count in newItems do
			local gained = count - (previousItems[id] or 0)
			if gained > 0 then
				toast(string.format("+%d %s %s", gained, iconOf(id), nameOf(id)), C.Good)
			end
		end
	end
	previousItems = table.clone(newItems)
	items = newItems
	if type(data.Capacity) == "number" then capacity = data.Capacity end
	refreshAll()
end)

if backpackRemote then
	backpackRemote.OnClientEvent:Connect(function(kind, a, b)
		if kind == "State" and type(a) == "table" then
			backpack = a
			if type(a.Capacity) == "number" then capacity = a.Capacity end
			refreshAll()
		elseif kind == "Result" then
			upStatus.Text = b or ""
			upStatus.TextColor3 = a and C.Good or C.Bad
			toast(b or "", a and C.Good or C.Bad)
		end
	end)
end

if toolUpdate then
	toolUpdate.OnClientEvent:Connect(function(kind, a, b)
		if kind == "State" and type(a) == "table" then
			tools = a
			refreshTools()
		elseif kind == "Result" then
			toast(b or (a and "Ferramenta melhorada!" or "Não foi possível melhorar."), a and C.Good or C.Bad)
		end
	end)
end

refreshAll()
inventoryRemote:FireServer("Request")
if backpackRemote then backpackRemote:FireServer("Request") end
if toolRequest then toolRequest:FireServer("Request") end
