--[[
	InventoryService (v4)
	Local: ServerScriptService > Services > InventoryService   (SUBSTITUI o atual)

	Mochila, descarte e itens físicos no mundo. O servidor controla tudo.

	Novidades:
	  - Soltar/Descartar com QUANTIDADE:  UpdateInventory:FireServer("Drop" | "Trash", item, quantidade)
	  - Item solto vira UM objeto no chão (pilha com a quantidade), pousado sobre o terreno
	  - Outros jogadores podem recolher; se a mochila não tiver espaço pega só o que cabe
	  - Capacidade por jogador (InventoryService.CapacityProvider, usado pelo BackpackService)
	  - Limite de objetos soltos no servidor (os mais antigos somem primeiro)

	API (igual à anterior): GetCapacity(player), GetUsedCapacity, GetFreeCapacity, GetCount, GetRoom,
	CanAdd, AddItem, RemoveItem, HasItems, RemoveItems, Sync  +  DropItem, TrashItem
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))

local InventoryService = {}
InventoryService.CapacityProvider = nil -- function(player) -> number (definido pelo BackpackService)

local remote
local dirty = {}
local lastRequest = {}
local lastAction = {}

local DROP_LIFETIME = 300
local ACTION_COOLDOWN = 0.3
local LABEL_DISTANCE = 22
local PICKUP_DISTANCE = 10
local MAX_WORLD_DROPS = 250
local DROP_FOLDER_NAME = "WorldDrops"

local dropQueue = {}

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
	if not data then return nil end
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
		if ResourceConfig.Items[item] and type(count) == "number" and count > 0 then
			copy[item] = count
		end
	end
	return copy
end

local function getCapacity(player)
	if InventoryService.CapacityProvider and player then
		local ok, value = pcall(InventoryService.CapacityProvider, player)
		if ok and type(value) == "number" then
			return value
		end
	end
	return ResourceConfig.Inventory.BaseCapacity or 100
end

local function notice(player, text)
	if remote and player.Parent then
		remote:FireClient(player, { Notice = text })
	end
end

local function flush(player)
	dirty[player] = nil
	if not remote or not player.Parent then return end
	local inventory = inventoryOf(player)
	if inventory then
		remote:FireClient(player, {
			Items = snapshot(inventory),
			Capacity = getCapacity(player),
		})
	end
end

local function markDirty(player)
	if dirty[player] then return end
	dirty[player] = true
	task.defer(flush, player)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------
function InventoryService.GetUsedCapacity(player)
	local inventory = inventoryOf(player)
	if not inventory then return 0 end
	local used = 0
	for item, amount in pairs(inventory) do
		if ResourceConfig.Items[item] and type(amount) == "number" then
			used += math.max(0, amount)
		end
	end
	return used
end

function InventoryService.GetCapacity(player)
	return getCapacity(player)
end

function InventoryService.GetFreeCapacity(player)
	return math.max(0, getCapacity(player) - InventoryService.GetUsedCapacity(player))
end

function InventoryService.GetCount(player, item)
	local inventory = inventoryOf(player)
	if not inventory then return 0 end
	local amount = inventory[item]
	return type(amount) == "number" and amount or 0
end

function InventoryService.GetRoom(player, item)
	local inventory = inventoryOf(player)
	local definition = ResourceConfig.Items[item]
	if not inventory or not definition then return 0 end
	local current = inventory[item] or 0
	local stackRoom = math.max(0, (definition.MaxStack or 999) - current)
	return math.min(stackRoom, InventoryService.GetFreeCapacity(player))
end

function InventoryService.CanAdd(player, item, amount)
	if not ResourceConfig.Items[item] or not inventoryOf(player) then return false end
	return InventoryService.GetRoom(player, item) >= (amount or 1)
end

function InventoryService.AddItem(player, item, amount, reason)
	if not ResourceConfig.Items[item] or not validAmount(amount) then return 0 end
	local inventory = inventoryOf(player)
	if not inventory then return 0 end
	local added = math.min(amount, InventoryService.GetRoom(player, item))
	if added <= 0 then return 0 end
	inventory[item] = InventoryService.GetCount(player, item) + added
	markDirty(player)
	return added
end

function InventoryService.RemoveItem(player, item, amount, reason)
	if not ResourceConfig.Items[item] or not validAmount(amount) then return false end
	local inventory = inventoryOf(player)
	if not inventory then return false end
	local current = InventoryService.GetCount(player, item)
	if current < amount then return false end
	inventory[item] = current - amount
	if inventory[item] <= 0 then
		inventory[item] = nil
	end
	markDirty(player)
	return true
end

function InventoryService.HasItems(player, cost)
	if type(cost) ~= "table" then return false end
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
	if not InventoryService.HasItems(player, cost) then return false end
	for item, amount in pairs(cost) do
		InventoryService.RemoveItem(player, item, amount, reason)
	end
	return true
end

function InventoryService.Sync(player)
	markDirty(player)
end

----------------------------------------------------------------------
-- Itens soltos no mundo
----------------------------------------------------------------------
local DROP_STYLES = {
	Wood = { Shape = Enum.PartType.Block, Size = Vector3.new(1.5, 0.55, 0.65), Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(126, 83, 48) },
	Stone = { Shape = Enum.PartType.Block, Size = Vector3.new(1.05, 0.85, 0.95), Material = Enum.Material.Slate, Color = Color3.fromRGB(115, 119, 124) },
	Fiber = { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 1.15, 0.35), Material = Enum.Material.Grass, Color = Color3.fromRGB(78, 145, 73) },
	IronOre = { Shape = Enum.PartType.Ball, Size = Vector3.new(0.95, 0.85, 0.9), Material = Enum.Material.Metal, Color = Color3.fromRGB(105, 116, 129) },
	GoldOre = { Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.85, 0.9), Material = Enum.Material.Metal, Color = Color3.fromRGB(235, 184, 52) },
	Coconut = { Shape = Enum.PartType.Ball, Size = Vector3.new(0.85, 0.85, 0.85), Material = Enum.Material.Wood, Color = Color3.fromRGB(104, 70, 43) },
}

local function iconOf(definition)
	local e = definition.Emoji
	if e and e ~= "" and not e:find("%?%?") then return e .. " " end
	return ""
end

local function updateDropLabel(drop)
	local item = drop:GetAttribute("ItemName")
	local amount = drop:GetAttribute("Amount") or 1
	local definition = ResourceConfig.Items[item]
	local billboard = drop:FindFirstChild("ItemLabel")
	local label = billboard and billboard:FindFirstChild("Label")
	if label and definition then
		label.Text = string.format("%s%s  x%d", iconOf(definition), definition.DisplayName or item, amount)
	end
end

local function trimWorldDrops()
	local alive = {}
	for _, d in ipairs(dropQueue) do
		if d.Parent then table.insert(alive, d) end
	end
	dropQueue = alive
	while #dropQueue > MAX_WORLD_DROPS do
		local oldest = table.remove(dropQueue, 1)
		if oldest and oldest.Parent then oldest:Destroy() end
	end
end

-- Acha o chão (terreno ou parte) para o item pousar sem atravessar
local function groundPosition(player, root, halfHeight)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, getDropFolder() }
	params.IgnoreWater = true

	local jitter = Vector3.new(math.random(-8, 8) / 10, 0, math.random(-8, 8) / 10)
	local origin = root.Position + root.CFrame.LookVector * 3 + jitter + Vector3.new(0, 3, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -40, 0), params)
	if hit then
		return hit.Position + Vector3.new(0, halfHeight, 0)
	end
	return nil
end

local function createDrop(player, item, amount)
	local definition = ResourceConfig.Items[item]
	if not definition then return nil end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local style = DROP_STYLES[item] or {
		Shape = Enum.PartType.Block,
		Size = Vector3.new(0.9, 0.9, 0.9),
		Material = Enum.Material.SmoothPlastic,
		Color = definition.Color or Color3.fromRGB(150, 150, 150),
	}
	local scale = 1 + math.min(0.6, amount / 100)
	local size = style.Size * scale

	local position = groundPosition(player, root, size.Y / 2)
	if not position then return nil end

	local drop = Instance.new("Part")
	drop.Name = "Dropped_" .. item
	drop.Shape = style.Shape
	drop.Size = size
	drop.Material = style.Material
	drop.Color = style.Color
	drop.Anchored = true     -- fica exatamente no chão, não atravessa nem rola
	drop.CanCollide = false  -- não atrapalha quem anda
	drop.TopSurface = Enum.SurfaceType.Smooth
	drop.BottomSurface = Enum.SurfaceType.Smooth
	drop.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	drop:SetAttribute("ItemName", item)
	drop:SetAttribute("Amount", amount)
	drop:SetAttribute("OwnerUserId", player.UserId)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ItemLabel"
	billboard.Adornee = drop
	billboard.Size = UDim2.fromOffset(190, 38)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = LABEL_DISTANCE
	billboard.Parent = drop

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(22, 29, 35)
	label.BackgroundTransparency = 0.15
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
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = label

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ActionText = "Recolher"
	prompt.ObjectText = definition.DisplayName or item
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = drop

	drop.Parent = getDropFolder()
	updateDropLabel(drop)

	prompt.Triggered:Connect(function(otherPlayer)
		if not drop.Parent then return end
		if not otherPlayer or not otherPlayer:IsA("Player") then return end
		if not PlayerDataService.IsLoaded(otherPlayer) then return end

		-- confere a distância no servidor
		local otherRoot = otherPlayer.Character and otherPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not otherRoot or (otherRoot.Position - drop.Position).Magnitude > PICKUP_DISTANCE + 8 then
			return
		end

		local remaining = drop:GetAttribute("Amount") or 0
		if remaining <= 0 then return end

		local room = InventoryService.GetRoom(otherPlayer, item)
		if room <= 0 then
			notice(otherPlayer, "Sua mochila está cheia.")
			return
		end

		local added = InventoryService.AddItem(otherPlayer, item, math.min(room, remaining), "WorldPickup")
		if added <= 0 then return end

		remaining -= added
		if remaining <= 0 then
			drop:SetAttribute("Amount", 0)
			drop:Destroy()
		else
			drop:SetAttribute("Amount", remaining)
			updateDropLabel(drop)
		end
	end)

	table.insert(dropQueue, drop)
	trimWorldDrops()
	Debris:AddItem(drop, DROP_LIFETIME)
	return drop
end

----------------------------------------------------------------------
-- Soltar / descartar
----------------------------------------------------------------------
function InventoryService.DropItem(player, item, amount)
	if not validAmount(amount) then return false, "Quantidade inválida." end
	if InventoryService.GetCount(player, item) < amount then return false, "Você não tem essa quantidade." end
	if player:GetAttribute("InWater") then return false, "Não dá para soltar itens na água." end

	local drop = createDrop(player, item, amount)
	if not drop then return false, "Não foi possível soltar aqui." end

	-- só remove do inventário depois que o objeto existe; se falhar, o objeto some (nada duplica)
	if not InventoryService.RemoveItem(player, item, amount, "Drop") then
		drop:Destroy()
		return false, "Erro ao soltar."
	end
	return true
end

function InventoryService.TrashItem(player, item, amount)
	if not validAmount(amount) then return false, "Quantidade inválida." end
	if not InventoryService.RemoveItem(player, item, amount, "Trash") then
		return false, "Você não tem essa quantidade."
	end
	return true
end

local function handleAction(player, action, item, amount)
	if type(action) ~= "string" or type(item) ~= "string" then return end
	if not ResourceConfig.Items[item] then return end
	if not PlayerDataService.IsLoaded(player) then return end

	if amount == nil then amount = 1 end
	if not validAmount(amount) then return end

	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_COOLDOWN then return end
	lastAction[player] = now

	local count = InventoryService.GetCount(player, item)
	if count < 1 then return end
	amount = math.min(amount, count)

	local ok, reason
	if action == "Drop" then
		ok, reason = InventoryService.DropItem(player, item, amount)
	elseif action == "Trash" then
		ok, reason = InventoryService.TrashItem(player, item, amount)
	end
	if ok == false and reason then
		notice(player, reason)
	end
end

----------------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------------
function InventoryService.Init()
end

function InventoryService.Start()
	remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdateInventory")

	remote.OnServerEvent:Connect(function(player, action, item, amount)
		if action == "Request" then
			local now = os.clock()
			if lastRequest[player] and now - lastRequest[player] < 1 then return end
			lastRequest[player] = now
			if PlayerDataService.IsLoaded(player) then
				markDirty(player)
			end
		elseif action == "Drop" or action == "Trash" then
			handleAction(player, action, item, amount)
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

	print("[InventoryService] Inventário v4 iniciado.")
end

return InventoryService

