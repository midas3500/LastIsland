--[[
	MapService
	Local: ServerScriptService > Services > MapService

	Gera o mapa inteiro por código (sem modelos externos):
	oceano, ilha central, 12 ilhas de jogadores, lobby, ponte, palmeiras, pedras.

	Técnica low poly: cada "ilha" é um prisma de N lados montado com N/2 blocos girados.
	(Um polígono regular de lados pares = união de retângulos que ligam lados opostos.)

	API para outros serviços:
		MapService.GetIslandSlots()  -> lista de slots {Index, Name, Model, Center, SpawnCFrame, Radius, BuildRadius, GroundY, Angle}
		MapService.GetSlot(index)
		MapService.IsReady()
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))

local MapService = {}

local Palette = MapConfig.Palette
local Style = MapConfig.Style
local rng = Random.new(MapConfig.Seed)

assert(Style.PrismSides % 2 == 0 and Style.PrismSides >= 6, "MapConfig.Style.PrismSides precisa ser PAR e >= 6")

local slots = {}
local ready = false

-- ===========================================================================
-- UTILITÁRIOS
-- ===========================================================================

local function log(...)
	if GameConfig.Debug then
		print("[MapService]", ...)
	end
end

local function jitter(color)
	local factor = 1 + rng:NextNumber(-Style.ColorJitter, Style.ColorJitter)
	return Color3.new(
		math.clamp(color.R * factor, 0, 1),
		math.clamp(color.G * factor, 0, 1),
		math.clamp(color.B * factor, 0, 1)
	)
end

-- Cria uma Part com padrões do jogo. Define as propriedades ANTES do Parent (mais eficiente).
local function newPart(props)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	local materialKey = props.Name and string.match(props.Name, "^[^_]+")
	part.Material = MapConfig.Materials.ByName[materialKey] or MapConfig.Materials.Default
	part.Size = Vector3.new(1, 1, 1)
	for key, value in pairs(props) do
		if key ~= "Parent" then
			part[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

-- Cilindro em pé. props.CFrame = centro | props.Height | props.Diameter
local function newCylinder(props)
	local p = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(props.Height, props.Diameter, props.Diameter),
		CFrame = props.CFrame * CFrame.Angles(0, 0, math.rad(90)),
	}
	for key, value in pairs(props) do
		if key ~= "CFrame" and key ~= "Height" and key ~= "Diameter" then
			p[key] = value
		end
	end
	return newPart(p)
end

local function newFolder(name, parent)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Reaproveita a pasta se já existir (limpando só o que foi gerado antes)
local function getFolder(name, parent)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	else
		for _, child in ipairs(folder:GetChildren()) do
			if child:GetAttribute("Generated") then
				child:Destroy()
			end
		end
	end
	return folder
end

local function addGenerated(instance, parent)
	instance:SetAttribute("Generated", true)
	instance.Parent = parent
end

local function tierByName(tiers, name)
	for _, tier in ipairs(tiers) do
		if tier.Name == name then
			return tier
		end
	end
	error("Tier não encontrado no MapConfig: " .. tostring(name))
end

-- Raio do maior círculo que cabe dentro do polígono (garantidamente coberto)
local function apothemOf(radius)
	return radius * math.cos(math.pi / Style.PrismSides)
end

local function angleDiff(a, b)
	return math.abs((a - b + math.pi) % (2 * math.pi) - math.pi)
end

local function isBlocked(angle, blocked)
	if not blocked then
		return false
	end
	for _, b in ipairs(blocked) do
		if angleDiff(angle, b) < 0.32 then
			return true
		end
	end
	return false
end

local function tryPlace(placed, position, minDistance)
	for _, other in ipairs(placed) do
		if (other - position).Magnitude < minDistance then
			return false
		end
	end
	table.insert(placed, position)
	return true
end

local function slotAngle(index)
	local cfg = MapConfig.PlayerIslands
	return math.rad(cfg.AngleOffsetDeg) + (index - 1) * (2 * math.pi / cfg.Count)
end

-- ===========================================================================
-- FORMAS LOW POLY
-- ===========================================================================

-- Prisma poligonal: raio = distância do centro até os vértices
local function buildPrism(parent, name, center, radius, yBottom, yTop, rotation, color)
	local sides = Style.PrismSides
	local apothem = apothemOf(radius)
	local edge = 2 * radius * math.sin(math.pi / sides)
	local height = yTop - yBottom
	local midY = (yTop + yBottom) / 2

	local model = Instance.new("Model")
	model.Name = name

	for i = 0, math.floor(sides / 2) - 1 do
		local angle = rotation + math.pi / sides + i * (2 * math.pi / sides)
		newPart({
			Name = name .. "_" .. (i + 1),
			Size = Vector3.new(2 * apothem, height, edge),
			-- pequeno desnível por bloco evita "piscar" (z-fighting) nas faces de cima
			CFrame = CFrame.new(center.X, midY - i * 0.012, center.Z) * CFrame.Angles(0, -angle, 0),
			Color = color,
			Parent = model,
		})
	end

	model.Parent = parent
	return model
end

local function buildTiers(parent, center, radius, tiers)
	for _, tier in ipairs(tiers) do
		local rotation = rng:NextNumber(0, 2 * math.pi / Style.PrismSides)
		buildPrism(parent, tier.Name, center, radius * tier.Scale, tier.Bottom, tier.Top, rotation, jitter(Palette[tier.Color]))
	end
end

local function buildPalm(parent, basePosition)
	local cfg = MapConfig.Palm
	local scale = rng:NextNumber(cfg.MinScale, cfg.MaxScale)
	local model = Instance.new("Model")
	model.Name = "Palm"

	local frame = CFrame.new(basePosition) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0)
	local segHeight = cfg.SegmentHeight * scale

	-- Tronco: segmentos que vão se inclinando
	for i = 1, cfg.Segments do
		local t = (i - 1) / math.max(cfg.Segments - 1, 1)
		local width = (cfg.TrunkBaseWidth + (cfg.TrunkTopWidth - cfg.TrunkBaseWidth) * t) * scale
		newPart({
			Name = "Trunk_" .. i,
			Size = Vector3.new(width, segHeight * 1.12, width),
			CFrame = frame * CFrame.new(0, segHeight * 0.56, 0),
			Color = jitter(Palette.Trunk),
			Parent = model,
		})
		frame = frame * CFrame.new(0, segHeight, 0) * CFrame.Angles(0, 0, math.rad(cfg.LeanDegrees + rng:NextNumber(-2, 2)))
	end

	-- Folhas: 5 folhas em volta do topo, cada uma com 2 blocos (base larga + ponta fina)
	local yawStart = rng:NextNumber(0, 2 * math.pi)
	for k = 1, cfg.Leaves do
		local leafColor = jitter((k % 2 == 0) and Palette.Leaf or Palette.LeafDark)
		local f = frame * CFrame.Angles(0, yawStart + (k / cfg.Leaves) * 2 * math.pi, 0)

		f = f * CFrame.Angles(-math.rad(cfg.LeafDroop1), 0, 0)
		newPart({
			Name = "Leaf_" .. k .. "_A",
			Size = Vector3.new(cfg.LeafWidth1 * scale, 0.3, cfg.LeafLength1 * scale),
			CFrame = f * CFrame.new(0, 0, -cfg.LeafLength1 * scale / 2),
			Color = leafColor,
			CanCollide = false,
			Parent = model,
		})

		f = f * CFrame.new(0, 0, -cfg.LeafLength1 * scale) * CFrame.Angles(-math.rad(cfg.LeafDroop2), 0, 0)
		newPart({
			Name = "Leaf_" .. k .. "_B",
			Size = Vector3.new(cfg.LeafWidth2 * scale, 0.3, cfg.LeafLength2 * scale),
			CFrame = f * CFrame.new(0, 0, -cfg.LeafLength2 * scale / 2),
			Color = leafColor,
			CanCollide = false,
			Parent = model,
		})
	end

	model.Parent = parent
	return model
end

local function buildRock(parent, position, size)
	local model = Instance.new("Model")
	model.Name = "Rock"

	for i = 1, rng:NextInteger(2, 3) do
		local s = size * rng:NextNumber(0.55, 1)
		local offset = Vector3.new(rng:NextNumber(-1, 1) * size * 0.5, s * 0.25, rng:NextNumber(-1, 1) * size * 0.5)
		newPart({
			Name = "Rock_" .. i,
			Size = Vector3.new(s * rng:NextNumber(0.9, 1.4), s * rng:NextNumber(0.7, 1.1), s * rng:NextNumber(0.9, 1.3)),
			CFrame = CFrame.new(position + offset)
				* CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), rng:NextNumber(0, 2 * math.pi), math.rad(rng:NextNumber(-20, 20))),
			Color = jitter((i % 2 == 0) and Palette.Rock or Palette.RockDark),
			Parent = model,
		})
	end

	model.Parent = parent
	return model
end

local function buildLamp(parent, position)
	local model = Instance.new("Model")
	model.Name = "Lamp"

	newPart({
		Name = "Pole",
		Size = Vector3.new(0.5, 7, 0.5),
		CFrame = CFrame.new(position + Vector3.new(0, 3.5, 0)),
		Color = Palette.WoodDark,
		Parent = model,
	})
	local bulb = newPart({
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = CFrame.new(position + Vector3.new(0, 7.6, 0)),
		Color = Palette.LampGlow,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Range = 22
	light.Brightness = 1.2
	light.Color = Palette.LampGlow
	light.Parent = bulb

	model.Parent = parent
	return model
end

local function buildSign(parent, position, lookAt, titleText, subtitleText, scale)
	scale = scale or 1
	local model = Instance.new("Model")
	model.Name = "Sign"

	local frame = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))

	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "Post",
			Size = Vector3.new(0.6 * scale, 6 * scale, 0.6 * scale),
			CFrame = frame * CFrame.new(side * 3.5 * scale, 3 * scale, 0),
			Color = Palette.WoodDark,
			Parent = model,
		})
	end

	local board = newPart({
		Name = "Board",
		Size = Vector3.new(8.4 * scale, 3.4 * scale, 0.5 * scale),
		CFrame = frame * CFrame.new(0, 4.3 * scale, 0),
		Color = Palette.Wood,
		Parent = model,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(420, 170)
	gui.LightInfluence = 0
	gui.Parent = board

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, 0.58)
	title.Position = UDim2.fromScale(0, 0.02)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Palette.White
	title.Text = titleText
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.fromScale(0.94, 0.34)
	subtitle.Position = UDim2.fromScale(0.03, 0.62)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.TextColor3 = Palette.LampGlow
	subtitle.Text = subtitleText
	subtitle.Parent = gui

	model.Parent = parent
	return model
end

local function buildLighthouse(parent, baseY, center)
	local model = Instance.new("Model")
	model.Name = "Lighthouse"

	local heights = { 6, 6, 6, 5 }
	local diameters = { 10, 9, 8, 7 }
	local y = baseY

	for i = 1, #heights do
		newCylinder({
			Name = "Tower_" .. i,
			CFrame = CFrame.new(center.X, y + heights[i] / 2, center.Z),
			Height = heights[i],
			Diameter = diameters[i],
			Color = (i % 2 == 1) and Palette.White or Palette.Red,
			Parent = model,
		})
		y += heights[i]
	end

	newCylinder({
		Name = "Balcony",
		CFrame = CFrame.new(center.X, y + 0.3, center.Z),
		Height = 0.6, Diameter = 10,
		Color = Palette.WoodDark,
		Parent = model,
	})
	y += 0.6

	local lantern = newCylinder({
		Name = "Lantern",
		CFrame = CFrame.new(center.X, y + 1.5, center.Z),
		Height = 3, Diameter = 5,
		Color = Palette.LampGlow,
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Range = 70
	light.Brightness = 2
	light.Color = Palette.LampGlow
	light.Parent = lantern
	y += 3

	newCylinder({
		Name = "Roof",
		CFrame = CFrame.new(center.X, y + 0.6, center.Z),
		Height = 1.2, Diameter = 6.4,
		Color = Palette.Red,
		Parent = model,
	})

	model.Parent = parent
	return model
end

-- Espalha palmeiras e pedras sem sobreposição. opts vem do MapConfig.Decor + alturas.
local function scatterDecor(parent, center, radius, opts)
	local placed = {}

	local function sample(minScale, maxScale)
		for _ = 1, 20 do
			local angle = rng:NextNumber(-math.pi, math.pi)
			if not isBlocked(angle, opts.Blocked) then
				return angle, radius * rng:NextNumber(minScale, maxScale)
			end
		end
		return nil, nil
	end

	local palmsPlaced = 0
	for _ = 1, opts.Palms * 6 do
		if palmsPlaced >= opts.Palms then
			break
		end
		local angle, r = sample(opts.PalmMin, opts.PalmMax)
		if angle then
			local y = (r <= opts.GroundRadius) and opts.GroundTop or opts.BeachTop
			local position = Vector3.new(center.X + math.cos(angle) * r, y, center.Z + math.sin(angle) * r)
			if tryPlace(placed, position, MapConfig.Decor.MinSpacing) then
				buildPalm(parent, position)
				palmsPlaced += 1
			end
		end
	end

	local rocksPlaced = 0
	for _ = 1, opts.Rocks * 6 do
		if rocksPlaced >= opts.Rocks then
			break
		end
		local angle, r = sample(opts.RockMin, opts.RockMax)
		if angle then
			local position = Vector3.new(center.X + math.cos(angle) * r, opts.BeachTop, center.Z + math.sin(angle) * r)
			if tryPlace(placed, position, 5) then
				buildRock(parent, position, rng:NextNumber(2.5, 5))
				rocksPlaced += 1
			end
		end
	end
end

-- Marcadores invisíveis para o ResourceService (Etapa 3)
local function buildResourceMarkers(islandIndex, islandName, center, radius, groundY)
	local cfg = MapConfig.ResourceMarkers
	local spawnsRoot = Workspace.Map:FindFirstChild(MapConfig.Folders.ResourceSpawns)
	local folder = newFolder(islandName, nil)
	local placed = {}

	for resourceType, count in pairs(cfg.Counts) do
		local made = 0
		for _ = 1, count * 8 do
			if made >= count then
				break
			end
			local angle = rng:NextNumber(-math.pi, math.pi)
			local r = radius * rng:NextNumber(cfg.MinRadiusScale, cfg.MaxRadiusScale)
			local position = Vector3.new(center.X + math.cos(angle) * r, groundY + 1, center.Z + math.sin(angle) * r)
			if tryPlace(placed, position, cfg.Spacing) then
				local marker = newPart({
					Name = resourceType .. "Spawn",
					Size = Vector3.new(2, 2, 2),
					CFrame = CFrame.new(position),
					Transparency = 1,
					CanCollide = false,
					CanQuery = false,
					Parent = folder,
				})
				marker:SetAttribute("ResourceType", resourceType)
				marker:SetAttribute("IslandIndex", islandIndex)
				made += 1
			end
		end
	end

	addGenerated(folder, spawnsRoot)
end

-- Ponte reta entre dois pontos (apenas X e Z importam)
local function buildBridge(parent, name, pointA, pointB)
	local cfg = MapConfig.Bridges
	local a = Vector3.new(pointA.X, 0, pointA.Z)
	local b = Vector3.new(pointB.X, 0, pointB.Z)
	local direction = b - a
	local length = direction.Magnitude
	local middle = (a + b) / 2
	local frame = CFrame.lookAt(middle, middle + direction.Unit)

	local model = Instance.new("Model")
	model.Name = name

	newPart({
		Name = "Deck",
		Size = Vector3.new(cfg.Width, cfg.DeckThickness, length),
		CFrame = frame * CFrame.new(0, cfg.DeckTop - cfg.DeckThickness / 2, 0),
		Color = Palette.Wood,
		Parent = model,
	})

	-- Corrimãos
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "Rail",
			Size = Vector3.new(0.3, 0.3, length),
			CFrame = frame * CFrame.new(side * (cfg.Width / 2 - 0.3), cfg.DeckTop + 1.8, 0),
			Color = Palette.WoodDark,
			Parent = model,
		})
	end

	-- Postes do corrimão
	local postCount = math.max(math.floor(length / cfg.PostSpacing), 1)
	for i = 0, postCount do
		local z = -length / 2 + length * i / postCount
		for _, side in ipairs({ -1, 1 }) do
			newPart({
				Name = "Post",
				Size = Vector3.new(0.5, 2.2, 0.5),
				CFrame = frame * CFrame.new(side * (cfg.Width / 2 - 0.3), cfg.DeckTop + 1.1, z),
				Color = Palette.WoodDark,
				Parent = model,
			})
		end
	end

	-- Pilares até o fundo do mar
	local floorY = -20
	local pillarTop = cfg.DeckTop - cfg.DeckThickness
	local pillarHeight = pillarTop - floorY
	local pillarCount = math.max(math.floor(length / cfg.PillarSpacing), 1)
	for i = 0, pillarCount do
		local z = -length / 2 + length * i / pillarCount
		for _, side in ipairs({ -1, 1 }) do
			newCylinder({
				Name = "Pillar",
				CFrame = frame * CFrame.new(side * (cfg.Width / 2 - 1.5), floorY + pillarHeight / 2, z),
				Height = pillarHeight,
				Diameter = 1.2,
				Color = Palette.WoodDark,
				CanCollide = false,
				Parent = model,
			})
		end
	end

	addGenerated(model, parent)
	return model
end

-- ===========================================================================
-- OCEANO
-- ===========================================================================

local function buildOcean(folder)
	local cfg = MapConfig.Ocean
	local terrain = Workspace.Terrain

	terrain.WaterColor = cfg.Water.Color
	terrain.WaterTransparency = cfg.Water.Transparency
	terrain.WaterReflectance = cfg.Water.Reflectance
	terrain.WaterWaveSize = cfg.Water.WaveSize
	terrain.WaterWaveSpeed = cfg.Water.WaveSpeed

	-- Água física (dá para nadar). Superfície em Y = WaterLevel.
	local ok, err = pcall(function()
		terrain:FillBlock(
			CFrame.new(0, MapConfig.WaterLevel - cfg.Depth / 2, 0),
			Vector3.new(cfg.Size, cfg.Depth, cfg.Size),
			Enum.Material.Water
		)
	end)
	if not ok then
		warn("[MapService] Falha ao criar a água do Terrain: " .. tostring(err))
	end

	-- Fundo do mar
	local floor = newPart({
		Name = "SeaFloor",
		Size = Vector3.new(cfg.Size, 4, cfg.Size),
		CFrame = CFrame.new(0, MapConfig.WaterLevel - cfg.Depth - 2, 0),
		Color = cfg.FloorColor,
		Parent = nil,
	})
	addGenerated(floor, folder)

	-- Paredes invisíveis nas bordas
	local half = cfg.Size / 2
	local wallY = cfg.WallHeight / 2 - cfg.Depth
	local walls = {
		{ Vector3.new(cfg.Size, cfg.WallHeight, 4), Vector3.new(0, wallY, half + 2) },
		{ Vector3.new(cfg.Size, cfg.WallHeight, 4), Vector3.new(0, wallY, -half - 2) },
		{ Vector3.new(4, cfg.WallHeight, cfg.Size), Vector3.new(half + 2, wallY, 0) },
		{ Vector3.new(4, cfg.WallHeight, cfg.Size), Vector3.new(-half - 2, wallY, 0) },
	}
	for i, wall in ipairs(walls) do
		local part = newPart({
			Name = "Boundary_" .. i,
			Size = wall[1],
			CFrame = CFrame.new(wall[2]),
			Transparency = 1,
			CanQuery = false,
			Parent = nil,
		})
		addGenerated(part, folder)
	end
end

-- ===========================================================================
-- ILHAS
-- ===========================================================================

local function buildMainIsland(folder)
	local cfg = MapConfig.MainIsland
	local center = cfg.Position
	local model = Instance.new("Model")
	model.Name = "CentralIsland"
	local base = newFolder("Base", model)
	local decor = newFolder("Decor", model)

	buildTiers(base, center, cfg.Radius, cfg.Tiers)

	local ground = tierByName(cfg.Tiers, cfg.GroundTier)
	local beach = tierByName(cfg.Tiers, "Beach")
	local summit = tierByName(cfg.Tiers, cfg.SummitTier)

	buildLighthouse(decor, summit.Top, center)

	-- Não plantar palmeiras onde as pontes chegam
	local blocked = {}
	if MapConfig.Bridges.LobbyToMain then
		table.insert(blocked, -math.pi / 2)
	end
	if MapConfig.Bridges.PlayerIslandsToMain then
		for i = 1, MapConfig.PlayerIslands.Count do
			table.insert(blocked, slotAngle(i))
		end
	end

	local d = MapConfig.Decor.MainIsland
	scatterDecor(decor, center, cfg.Radius, {
		Palms = d.Palms, Rocks = d.Rocks,
		PalmMin = d.PalmMin, PalmMax = d.PalmMax, RockMin = d.RockMin, RockMax = d.RockMax,
		GroundTop = ground.Top,
		GroundRadius = apothemOf(cfg.Radius * ground.Scale),
		BeachTop = beach.Top,
		Blocked = blocked,
	})

	addGenerated(model, folder)

	local maxScale = cfg.Tiers[1].Scale
	return { Name = "CentralIsland", Position = center, Radius = cfg.Radius * maxScale }
end

local function buildPlayerIsland(index, folder)
	local function buildPlayerIsland(index, folder, customCenter)
		local cfg = MapConfig.PlayerIslands
		local angle = customCenter and math.atan2(customCenter.Z - cfg.Center.Z, customCenter.X - cfg.Center.X) or slotAngle(index)
		local center = customCenter or (cfg.Center + Vector3.new(math.cos(angle) * cfg.RingRadius, 0, math.sin(angle) * cfg.RingRadius))
		local name = string.format("Island_%02d", index)

		local model = Instance.new("Model")
		model.Name = name
		local base = newFolder("Base", model)
		local decor = newFolder("Decor", model)

		buildTiers(base, center, cfg.Radius, cfg.Tiers)

		local ground = tierByName(cfg.Tiers, cfg.GroundTier)
		local beach = tierByName(cfg.Tiers, "Beach")
		local groundY = ground.Top
		local groundApothem = apothemOf(cfg.Radius * ground.Scale)

		local blocked = nil
		if MapConfig.Bridges.PlayerIslandsToMain then
			blocked = { angle + math.pi }
		end

		local d = MapConfig.Decor.PlayerIsland
		scatterDecor(decor, center, cfg.Radius, {
			Palms = d.Palms, Rocks = d.Rocks,
			PalmMin = d.PalmMin, PalmMax = d.PalmMax, RockMin = d.RockMin, RockMax = d.RockMax,
			GroundTop = groundY,
			GroundRadius = groundApothem,
			BeachTop = beach.Top,
			Blocked = blocked,
		})

		-- Placa (a Etapa 2 atualiza o texto com o nome do dono)
		local toCenter = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local signPosition = Vector3.new(center.X - toCenter.X * cfg.Radius * 0.55, groundY, center.Z - toCenter.Z * cfg.Radius * 0.55)
		local sign = buildSign(model, signPosition, center, string.format("%s %02d", cfg.Sign.Title, index), cfg.Sign.Subtitle, 1)

		-- Ponto de nascimento (invisível). O IslandService usa SpawnCFrame.
		local spawnPoint = newPart({
			Name = "SpawnPoint",
			Size = Vector3.new(4, 1, 4),
			CFrame = CFrame.new(center.X, groundY + 3, center.Z),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = model,
		})

		model:SetAttribute("SlotIndex", index)
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("Radius", cfg.Radius)
		model:SetAttribute("BuildRadius", groundApothem * 0.95)
		model:SetAttribute("GroundY", groundY)

		addGenerated(model, folder)
		buildResourceMarkers(index, name, center, cfg.Radius, groundY)

		slots[index] = {
			Index = index,
			Name = name,
			Model = model,
			Sign = sign,
			Angle = angle,
			Center = Vector3.new(center.X, groundY, center.Z),
			SpawnCFrame = spawnPoint.CFrame,
			Radius = cfg.Radius,
			BuildRadius = groundApothem * 0.95,
			GroundY = groundY,
		}

		return { Name = name, Position = center, Radius = cfg.Radius * cfg.Tiers[1].Scale }
	end

	local function buildLobby(folder)
		local cfg = MapConfig.Lobby
		local center = cfg.Position
		local model = Instance.new("Model")
		model.Name = "LobbyIsland"
		local base = newFolder("Base", model)
		local decor = newFolder("Decor", model)
		local spawns = newFolder("Spawns", model)

		buildTiers(base, center, cfg.Radius, cfg.Tiers)

		local ground = tierByName(cfg.Tiers, cfg.GroundTier)
		local beach = tierByName(cfg.Tiers, "Beach")
		local groundY = ground.Top

		-- Pontos de nascimento do lobby
		for i = 1, cfg.SpawnPads do
			local a = (i - 1) * (2 * math.pi / cfg.SpawnPads) + math.pi / 4
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = "LobbySpawn_" .. i
			spawn.Anchored = true
			spawn.Neutral = true
			spawn.Duration = 0
			spawn.AllowTeamChangeOnTouch = false
			spawn.CanTouch = false
			spawn.TopSurface = Enum.SurfaceType.Smooth
			spawn.Material = Style.Material
			spawn.Color = Palette.SpawnPad
			spawn.Size = Vector3.new(8, 0.4, 8)
			spawn.CFrame = CFrame.new(center.X + math.cos(a) * cfg.SpawnRadius, groundY + 0.2, center.Z + math.sin(a) * cfg.SpawnRadius)
			for _, child in ipairs(spawn:GetChildren()) do
				if child:IsA("Decal") then
					child:Destroy()
				end
			end
			spawn.Parent = spawns
		end

		-- Postes de luz
		for i = 1, cfg.Lamps do
			local a = (i - 1) * (2 * math.pi / cfg.Lamps) + math.pi / 2 + math.pi / cfg.Lamps
			local r = cfg.Radius * 0.55
			buildLamp(decor, Vector3.new(center.X + math.cos(a) * r, groundY, center.Z + math.sin(a) * r))
		end

		-- Placa grande, ao fundo, virada para o lado da ponte (+Z)
		local signPosition = Vector3.new(center.X, groundY, center.Z - cfg.Radius * 0.5)
		buildSign(decor, signPosition, signPosition + Vector3.new(0, 0, 10), cfg.Sign.Title, cfg.Sign.Subtitle, 1.8)

		local d = MapConfig.Decor.Lobby
		scatterDecor(decor, center, cfg.Radius, {
			Palms = d.Palms, Rocks = d.Rocks,
			PalmMin = d.PalmMin, PalmMax = d.PalmMax, RockMin = d.RockMin, RockMax = d.RockMax,
			GroundTop = groundY,
			GroundRadius = apothemOf(cfg.Radius * ground.Scale),
			BeachTop = beach.Top,
			Blocked = { math.pi / 2, -math.pi / 2 },
		})

		addGenerated(model, folder)
		return { Name = "LobbyIsland", Position = center, Radius = cfg.Radius * cfg.Tiers[1].Scale }
	end

	-- ===========================================================================
	-- VALIDAÇÃO E GERAÇÃO
	-- ===========================================================================

	local function validateLayout(circles)
		local ok = true
		local minGap = MapConfig.Validation.MinGap
		local half = MapConfig.Ocean.Size / 2

		for i = 1, #circles - 1 do
			for j = i + 1, #circles do
				local a, b = circles[i], circles[j]
				local dx, dz = a.Position.X - b.Position.X, a.Position.Z - b.Position.Z
				local gap = math.sqrt(dx * dx + dz * dz) - a.Radius - b.Radius
				if gap < minGap then
					warn(string.format("[MapService] SOBREPOSIÇÃO: %s e %s (espaço %.1f < %d)", a.Name, b.Name, gap, minGap))
					ok = false
				end
			end
		end

		for _, c in ipairs(circles) do
			if math.abs(c.Position.X) + c.Radius > half - 10 or math.abs(c.Position.Z) + c.Radius > half - 10 then
				warn(string.format("[MapService] %s ultrapassa o limite do oceano.", c.Name))
				ok = false
			end
		end

		return ok
	end

	local function cleanTemplate()
		for _, name in ipairs(MapConfig.RemoveDefaultObjects) do
			local object = Workspace:FindFirstChild(name)
			if object and object:IsA("BasePart") then
				object:Destroy()
				log("Removido do template: " .. name)
			end
		end
	end

	local function generate()
		local startedAt = os.clock()
		local names = MapConfig.Folders

		cleanTemplate()

		local mapFolder = getFolder(names.Map, Workspace)
		local oceanFolder = getFolder(names.Ocean, mapFolder)
		local mainFolder = getFolder(names.MainIsland, mapFolder)
		local playersFolder = getFolder(names.PlayerIslands, mapFolder)
		getFolder(names.ResourceSpawns, mapFolder)
		getFolder(names.EventAreas, Workspace)
		local lobbyFolder = getFolder(names.Lobby, Workspace)

		buildOcean(oceanFolder)

		local circles = {}
		if MapConfig.MainIsland.Enabled == false then
			local cfg = MapConfig.MainIsland
			table.insert(circles, { Name = "CentralIsland", Position = cfg.Position, Radius = cfg.Radius * 1.3 })
		else
			table.insert(circles, buildMainIsland(mainFolder)) -- (ilha antiga, com o farol de torre vermelha)
		end
		if not MapConfig.PlayerIslands.Dynamic then
			for index = 1, MapConfig.PlayerIslands.Count do
				table.insert(circles, buildPlayerIsland(index, playersFolder))
			end
		end
		if MapConfig.Lobby.Enabled ~= false then
			table.insert(circles, buildLobby(lobbyFolder))
		end
		table.insert(circles, buildLobby(lobbyFolder))

		-- Pontes
		local bridgeCfg = MapConfig.Bridges
		local mainCfg = MapConfig.MainIsland
		local lobbyCfg = MapConfig.Lobby
		local playerCfg = MapConfig.PlayerIslands

		if bridgeCfg.LobbyToMain then
			local lobbyEdge = apothemOf(lobbyCfg.Radius) - 4
			local mainEdge = apothemOf(mainCfg.Radius) - 4
			buildBridge(
				lobbyFolder, "Bridge_LobbyToMain",
				lobbyCfg.Position + Vector3.new(0, 0, lobbyEdge),
				mainCfg.Position - Vector3.new(0, 0, mainEdge)
			)
		end

		if bridgeCfg.PlayerIslandsToMain then
			local islandEdge = apothemOf(playerCfg.Radius) - 4
			local mainEdge = apothemOf(mainCfg.Radius) - 4
			for index, slot in ipairs(slots) do
				local dir = Vector3.new(math.cos(slot.Angle), 0, math.sin(slot.Angle))
				buildBridge(
					slot.Model, string.format("Bridge_Island%02d", index),
					slot.Center - dir * islandEdge,
					mainCfg.Position + dir * mainEdge
				)
			end
		end

		local layoutOk = validateLayout(circles)
		log(layoutOk and "Verificação de sobreposição: OK (nenhuma ilha se sobrepõe)" or "Verificação de sobreposição: FALHOU (veja avisos acima)")
		log(string.format(
			"Mapa gerado em %.2fs | %d peças | %d ilhas de jogadores",
			os.clock() - startedAt, #mapFolder:GetDescendants() + #lobbyFolder:GetDescendants(), #slots
			))
	end

	-- ===========================================================================
	-- API
	-- ===========================================================================

	function MapService.GetIslandSlots()
		return table.clone(slots)
	end

	function MapService.GetSlot(index)
		return slots[index]
	end

	function MapService.IsReady()
		return ready
	end

	function MapService.Init()
	end

	function MapService.Start()
		local ok, err = xpcall(generate, debug.traceback)
		if not ok then
			warn("[MapService] Falha ao gerar o mapa:\n" .. tostring(err))
			return
		end
		ready = true
	end

	return MapService
