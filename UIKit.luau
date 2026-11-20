--[[
	UIKit (ModuleScript)
	Local: ReplicatedStorage > Modules > UIKit   (arquivo NOVO)

	Pequenas ferramentas de interface usadas pelos LocalScripts novos
	(BuildingClient, HungerClient). Não mexe em nada que já existe.
]]

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.White = Color3.fromRGB(255, 255, 255)
UIKit.Panel = Color3.fromRGB(18, 26, 38)
UIKit.Good = Color3.fromRGB(140, 230, 140)
UIKit.Warn = Color3.fromRGB(255, 190, 110)

function UIKit.Create(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

function UIKit.Round(parent, radius)
	return UIKit.Create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

function UIKit.Padding(parent, amount)
	return UIKit.Create("UIPadding", {
		PaddingTop = UDim.new(0, amount), PaddingBottom = UDim.new(0, amount),
		PaddingLeft = UDim.new(0, amount), PaddingRight = UDim.new(0, amount),
	}, parent)
end

-- Botão padrão (44px+ de altura = confortável para o toque)
function UIKit.Button(parent, text, size, color)
	local button = UIKit.Create("TextButton", {
		Size = size,
		BackgroundColor3 = color or Color3.fromRGB(50, 120, 80),
		TextColor3 = UIKit.White,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
		AutoButtonColor = true,
	}, parent)
	UIKit.Round(button, 10)
	UIKit.Padding(button, 8)
	return button
end

local counters = setmetatable({}, { __mode = "k" })

-- Aviso curto no topo da tela. gui = o ScreenGui
function UIKit.Toast(gui, text, color)
	local holder = gui:FindFirstChild("UIKitToasts")
	if not holder then
		holder = UIKit.Create("Frame", {
			Name = "UIKitToasts",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.14),
			Size = UDim2.fromScale(0.5, 0.3),
			BackgroundTransparency = 1,
		}, gui)
		UIKit.Create("UISizeConstraint", { MinSize = Vector2.new(240, 0), MaxSize = Vector2.new(460, 400) }, holder)
		UIKit.Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6),
		}, holder)
	end

	counters[holder] = (counters[holder] or 0) + 1

	local existing = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(existing, child)
		end
	end
	table.sort(existing, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #existing >= 4 do
		existing[1]:Destroy()
		table.remove(existing, 1)
	end

	local label = UIKit.Create("TextLabel", {
		LayoutOrder = counters[holder],
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = UIKit.Panel,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color or UIKit.White,
		Text = text,
	}, holder)
	UIKit.Round(label, 10)
	UIKit.Padding(label, 6)

	task.delay(2.6, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.delay(0.45, function()
				label:Destroy()
			end)
		end
	end)
end

return UIKit

