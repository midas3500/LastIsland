--[[
	IslandGenerator (v2)
	Local: ServerScriptService > Services > IslandGenerator   (ModuleScript, serviço com Init/Start)

	Roda logo DEPOIS do MapService (veja PATCHES.md, passo da ordem dos serviços) e:
	  - escreve o terreno da ilha central (praia, planície, colinas, montanhas) por cima do oceano
	    do MapService, usando o MESMO nível do mar (MapConfig.WaterLevel)
	  - constrói as pontes das ilhas dos jogadores e do lobby até a praia da ilha central
	  - cria poços de água
	  - cria MARCADORES de recurso em Workspace > Map > ResourceSpawns > CentralIsland
	    (IslandIndex = 0, qualquer jogador coleta) -> o ResourceService cria os prompts de interação

	API para outros serviços:
	  Generator.Ready, Generator.Wells, Generator.Bridges[indiceDaIlha]
	  Generator.WellDrank (BindableEvent: player, poço, quantidade)
	  Generator.RandomLandPoint(zona) / Generator.GroundAt(x, z)
	  Generator.SpawnRuntimeNode(chave, pos) / Generator.RemoveRuntimeNode(model, marker)
	  Generator.EnsureTemplates(pastaServerStorageResourceModels)
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Cfg = require(Modules:WaitForChild("IslandGenConfig"))
local MapConfig = require(Modules:WaitForChild("MapConfig"))
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig"))
local MapService = require(script.Parent:WaitForChild("MapService"))
local MapC = Cfg.Map

local Generator = {}
Generator.WellDrank = Instance.new("BindableEvent")
Generator.Ready = false
Generator.Wells = {}
Generator.Bridges = {}

local MAT = Enum.Material
local STEP = 4
local rng = Random.new()
local seedA, seedB, seedC = 0, 0, 0
local peak = Vector3.zero
local H = {}
local folders = {}

-- geometria (calculada em setup)
local Center, Sea, Depth, R
local N, W, originX, originZ, bottomY, ny, minRel, HALF
local VOL = nil -- dados do vulcão (nil se desligado)
local CAVES = {} -- cavernas planejadas { Spheres, Chambers, Bounds }

----------------------------------------------------------------------
-- Matemática
----------------------------------------------------------------------
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local function smoothstep(a, b, x)
	local t = clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function fbm(x, z, oct, freq, off)
	local amp, sum, norm = 1, 0, 0
	for i = 1, oct do
		sum += math.noise(x * freq + off, z * freq + off * 0.37 + 0.123, i * 3.71 + 0.5) * amp
		norm += amp
		amp *= 0.5
		freq *= 2
	end
	return sum / norm
end

local function setup()
	Center = MapConfig.MainIsland.Position
	Sea = MapConfig.WaterLevel
	Depth = MapConfig.Ocean.Depth
	R = MapC.Radius
	local size = math.ceil(R * 2 * 1.5 / 128) * 128
	HALF = size / 2
	N = size / STEP
	W = N + 2
	originX = math.floor((Center.X - size / 2) / STEP) * STEP
	originZ = math.floor((Center.Z - size / 2) / STEP) * STEP
	bottomY = math.floor((Sea - Depth) / STEP) * STEP
	ny = math.ceil((Sea + MapC.TopRel - bottomY) / STEP)
	minRel = -Depth + 0.5 -- o fundo encosta no "SeaFloor" do MapService
end

local function planVolcano(peakAngle)
	local C = Cfg.Volcano
	if not C or not C.Enabled then VOL = nil return end
	local ang = peakAngle + math.pi + rng:NextNumber(-0.5, 0.5) -- do lado oposto ao pico principal
	local dist = R * C.DistanceScale
	local rv = R * C.RadiusScale
	VOL = {
		X = Center.X + math.cos(ang) * dist,
		Z = Center.Z + math.sin(ang) * dist,
		Radius = rv,
		CraterRadius = rv * C.CraterScale,
		Height = C.Height,
		Depth = C.CraterDepth,
	}
end

-- contribuição do vulcão para a altura (cone + cratera)
local function volcanoHeight(x, z)
	if not VOL then return 0 end
	local dx, dz = x - VOL.X, z - VOL.Z
	local d = math.sqrt(dx * dx + dz * dz)
	if d >= VOL.Radius then return 0 end
	local function cone(dd) return VOL.Height * (1 - dd / VOL.Radius) ^ 1.5 end
	if d < VOL.CraterRadius then
		local t = d / VOL.CraterRadius
		return cone(VOL.CraterRadius) - VOL.Depth * (1 - t * t)
	end
	return cone(d)
end

local function volcanoDistance(x, z)
	if not VOL then return math.huge end
	local dx, dz = x - VOL.X, z - VOL.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- altura relativa ao nível do mar
local function heightAt(x, z)
	local dx, dz = x - Center.X, z - Center.Z
	local dist = math.sqrt(dx * dx + dz * dz)

	-- costa irregular
	local warp = fbm(x, z, 3, 0.0055, seedA) * 0.45 + fbm(x, z, 2, 0.02, seedA + 9) * 0.08
	local e = 1 - dist / (R * (1 + warp)) -- 1 centro, 0 costa, <0 mar

	local base
	if e <= 0 then
		base = math.max(-6 + e * 120, minRel)
	else
		base = -6 + 14 * smoothstep(0, 0.4, e)
	end
	local land = smoothstep(0.12, 0.4, e)

	-- cordilheiras (ridged noise) concentradas em parte da ilha
	local mmask = clamp(fbm(x, z, 2, 0.004, seedB) * 3.2 + 0.35, 0, 1)
	local n = fbm(x, z, 3, 0.011, seedC)
	local ridge = clamp(1 - math.abs(n * 1.8), 0, 1)
	ridge *= ridge
	local mount = ridge * mmask * smoothstep(0.3, 0.6, e)

	-- pico principal
	local sigma = R * 0.23
	local pdx, pdz = x - peak.X, z - peak.Z
	local gauss = math.exp(-(pdx * pdx + pdz * pdz) / (2 * sigma * sigma))

	-- o fundo do mar desce até o fundo do oceano antes da borda da área gerada (sem degrau)
	local edge = math.max(math.abs(dx), math.abs(dz)) / HALF
	base = base + (minRel - base) * smoothstep(0.82, 1.0, edge)

	local h = base + mount * MapC.MountainHeight
	h += gauss * MapC.PeakBonus * smoothstep(0.25, 0.5, e)
	h += volcanoHeight(x, z) * smoothstep(0.3, 0.5, e)
	h += fbm(x, z, 3, 0.05, seedA + 3) * 2.5 * land
	return clamp(h, minRel, MapC.TopRel - 8)
end

local function Hget(i, j) return H[i * W + j + 1] end

local function gridHeight(x, z)
	local fi = (x - originX) / STEP + 0.5
	local fj = (z - originZ) / STEP + 0.5
	local i0, j0 = math.floor(fi), math.floor(fj)
	if i0 < 0 or j0 < 0 or i0 > N or j0 > N then return nil end
	local ti, tj = fi - i0, fj - j0
	local a = Hget(i0, j0) * (1 - ti) + Hget(i0 + 1, j0) * ti
	local b = Hget(i0, j0 + 1) * (1 - ti) + Hget(i0 + 1, j0 + 1) * ti
	return a * (1 - tj) + b * tj
end

local function surfaceMaterial(h, slope, x, z)
	local n = math.noise(x * 0.05 + seedA, z * 0.05 + 0.31, 0.5)
	if VOL then
		local d = volcanoDistance(x, z)
		if d < VOL.CraterRadius * 1.25 then return MAT.CrackedLava end
		if d < VOL.Radius * 0.62 then return MAT.Basalt end
		if d < VOL.Radius * 0.95 and h > 8 then
			return (n > 0.1) and MAT.Basalt or MAT.Slate
		end
	end
	if h < MapC.BeachMaxHeight + n * 0.8 then return MAT.Sand end
	if h > MapC.SnowLine + n * 4 then return MAT.Snow end
	if h > MapC.RockLine + n * 5 or slope > 0.85 then return MAT.Slate end
	if h > 28 and n > 0.12 then return MAT.Ground end
	return MAT.Grass
end

----------------------------------------------------------------------
-- Terreno (escrito por cima da água do MapService)
----------------------------------------------------------------------
local function computeHeights()
	for i = 0, N + 1 do
		for j = 0, N + 1 do
			H[i * W + j + 1] = heightAt(originX + (i - 0.5) * STEP, originZ + (j - 0.5) * STEP)
		end
		if i % 16 == 0 then task.wait() end
	end
end

-- Entalha as cavernas nos voxels do pedaço (esferas sobrepostas, bordas suaves)
local function carveCaves(mats, occs, i0, j0, nx, nz)
	if #CAVES == 0 then return end
	local minX = originX + i0 * STEP
	local minZ = originZ + j0 * STEP
	local maxX, maxZ = minX + nx * STEP, minZ + nz * STEP
	for _, cave in CAVES do
		local b = cave.Bounds
		if b.MaxX > minX and b.MinX < maxX and b.MaxZ > minZ and b.MinZ < maxZ then
			for _, sp in cave.Spheres do
				local sx, sy, sz, sr = sp[1], Sea + sp[2], sp[3], sp[4]
				if sx + sr + STEP > minX and sx - sr - STEP < maxX and sz + sr + STEP > minZ and sz - sr - STEP < maxZ then
					local x0 = math.max(1, math.floor((sx - sr - STEP - minX) / STEP) + 1)
					local x1 = math.min(nx, math.ceil((sx + sr + STEP - minX) / STEP))
					local z0 = math.max(1, math.floor((sz - sr - STEP - minZ) / STEP) + 1)
					local z1 = math.min(nz, math.ceil((sz + sr + STEP - minZ) / STEP))
					local y0 = math.max(1, math.floor((sy - sr - STEP - bottomY) / STEP) + 1)
					local y1 = math.min(ny, math.ceil((sy + sr + STEP - bottomY) / STEP))
					for xi = x0, x1 do
						local wx = minX + (xi - 0.5) * STEP
						for zi = z0, z1 do
							local wz = minZ + (zi - 0.5) * STEP
							for yi = y0, y1 do
								local wy = bottomY + (yi - 0.5) * STEP
								local dx, dy, dz = wx - sx, wy - sy, wz - sz
								local d = math.sqrt(dx * dx + dy * dy + dz * dz)
								local keep = math.clamp((d - sr) / STEP + 0.5, 0, 1) -- 0 dentro da caverna, 1 fora
								if keep < occs[xi][yi][zi] then
									occs[xi][yi][zi] = keep
									if keep <= 0 then mats[xi][yi][zi] = MAT.Air end
								end
							end
						end
					end
				end
			end
		end
	end
end

local function writeChunk(i0, j0, nx, nz)
	local mats, occs = table.create(nx), table.create(nx)
	for xi = 1, nx do
		local mx, ox = table.create(ny), table.create(ny)
		for yi = 1, ny do
			mx[yi] = table.create(nz, MAT.Air)
			ox[yi] = table.create(nz, 0)
		end
		mats[xi], occs[xi] = mx, ox
	end

	for xi = 1, nx do
		for zi = 1, nz do
			local gi, gj = i0 + xi, j0 + zi
			local h = Hget(gi, gj)
			local sx = (Hget(gi + 1, gj) - Hget(gi - 1, gj)) / (2 * STEP)
			local sz = (Hget(gi, gj + 1) - Hget(gi, gj - 1)) / (2 * STEP)
			local slope = math.sqrt(sx * sx + sz * sz)
			local wx = originX + (gi - 0.5) * STEP
			local wz = originZ + (gj - 0.5) * STEP
			local surf = surfaceMaterial(h, slope, wx, wz)

			for yi = 1, ny do
				local r0 = (bottomY + (yi - 1) * STEP) - Sea
				local r1 = r0 + STEP
				if h > r0 then
					mats[xi][yi][zi] = (h - r1 > 6) and MAT.Slate or surf
					occs[xi][yi][zi] = clamp((h - r0) / STEP, 0, 1)
				elseif r1 <= 0 then
					mats[xi][yi][zi] = MAT.Water
					occs[xi][yi][zi] = 1
				elseif r0 < 0 then
					mats[xi][yi][zi] = MAT.Water
					occs[xi][yi][zi] = clamp(-r0 / STEP, 0, 1)
				else
					break
				end
			end
		end
	end

	carveCaves(mats, occs, i0, j0, nx, nz)

	local min = Vector3.new(originX + i0 * STEP, bottomY, originZ + j0 * STEP)
	local max = min + Vector3.new(nx * STEP, ny * STEP, nz * STEP)
	Workspace.Terrain:WriteVoxels(Region3.new(min, max), STEP, mats, occs)
end

local function writeTerrain()
	local chunk = MapC.Chunk
	for i0 = 0, N - 1, chunk do
		for j0 = 0, N - 1, chunk do
			local cnx, cnz = math.min(chunk, N - i0), math.min(chunk, N - j0)
			local maxH = -math.huge
			for ci = i0, i0 + cnx + 1 do
				for cj = j0, j0 + cnz + 1 do
					local h = Hget(ci, cj)
					if h > maxH then maxH = h end
				end
			end
			-- só mar profundo e plano: o oceano do MapService já cobre, não precisa escrever nada
			if maxH > minRel + 0.6 then
				writeChunk(i0, j0, cnx, cnz)
				task.wait()
			end
		end
	end
end

----------------------------------------------------------------------
-- Consulta ao chão + reserva de espaço
----------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.IgnoreWater = true

local function groundAt(x, z)
	local top = Sea + MapC.TopRel + 20
	local res = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -(top - bottomY + 40), 0), rayParams)
	if res then return res.Position, res.Normal end
	return nil, nil
end
Generator.GroundAt = groundAt

local CELL = 24
local grid = {}
local function key(cx, cz) return cx * 100003 + cz end

local function isFree(x, z, r)
	local cx0, cz0 = math.floor(x / CELL), math.floor(z / CELL)
	for dx = -1, 1 do
		for dz = -1, 1 do
			local b = grid[key(cx0 + dx, cz0 + dz)]
			if b then
				for _, p in b do
					local ddx, ddz = p[1] - x, p[2] - z
					local need = p[3] + r
					if ddx * ddx + ddz * ddz < need * need then return false end
				end
			end
		end
	end
	return true
end

local function reserve(x, z, r)
	local k = key(math.floor(x / CELL), math.floor(z / CELL))
	grid[k] = grid[k] or {}
	table.insert(grid[k], { x, z, r })
end

local function randomInDisc(radius)
	local a = rng:NextNumber(0, math.pi * 2)
	local d = radius * math.sqrt(rng:NextNumber())
	return Center.X + math.cos(a) * d, Center.Z + math.sin(a) * d
end

function Generator.RandomLandPoint(zoneName)
	local zone = Cfg.Zones[zoneName] or Cfg.Zones.Land
	for _ = 1, 150 do
		local x, z = randomInDisc(R * 0.95)
		local h = gridHeight(x, z)
		if h and h >= zone[1] and h <= zone[2] then
			local pos, n = groundAt(x, z)
			if pos and n.Y > 0.9 then return pos, n end
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Modelos procedurais (árvores, arbustos, pedras, minérios)
----------------------------------------------------------------------
local COL = {
	Trunk = Color3.fromRGB(128, 92, 58),
	Leaf = Color3.fromRGB(70, 150, 72),
	LeafDark = Color3.fromRGB(48, 118, 60),
	Pine = Color3.fromRGB(30, 95, 58),
	PineLight = Color3.fromRGB(42, 115, 66),
	Coconut = Color3.fromRGB(96, 66, 40),
	Apple = Color3.fromRGB(205, 45, 45),
	BananaTrunk = Color3.fromRGB(125, 155, 75),
	BananaLeaf = Color3.fromRGB(95, 172, 60),
	Banana = Color3.fromRGB(242, 212, 60),
	Ironwood = Color3.fromRGB(58, 54, 62),
	IronwoodLeaf = Color3.fromRGB(52, 88, 98),
	IronBand = Color3.fromRGB(150, 150, 162),
	Bush = Color3.fromRGB(80, 150, 70),
	BushDark = Color3.fromRGB(56, 120, 58),
	Berry = Color3.fromRGB(200, 60, 80),
	Herb = Color3.fromRGB(110, 190, 120),
	Flower = Color3.fromRGB(245, 245, 250),
	Rock = Color3.fromRGB(122, 126, 134),
	RockDark = Color3.fromRGB(92, 96, 106),
	OreIron = Color3.fromRGB(178, 106, 74),
	OreGold = Color3.fromRGB(236, 190, 70),
	OreCoal = Color3.fromRGB(32, 32, 38),
	Drift = Color3.fromRGB(165, 145, 120),
	Stone = Color3.fromRGB(135, 138, 145),
	Water = Color3.fromRGB(60, 140, 220),
}

local function part(model, base, off, size, color, material, shape, collide)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then p.Shape = shape end
	p.CFrame = base * off
	p.Parent = model
	return p
end

local function cyl(model, base, off, height, diameter, color, material, collide)
	return part(model, base, off * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(height, diameter, diameter), color, material, Enum.PartType.Cylinder, collide)
end

local function ball(model, base, off, d, color, material, collide)
	return part(model, base, off, Vector3.new(d, d, d), color, material, Enum.PartType.Ball, collide)
end

local B = {}

-- Palmeira (coqueiro): Madeira + Fibra + Coco
function B.Tree(m, base, r)
	local s = r:NextNumber(0.9, 1.25)
	local segH = 3 * s
	local lean = math.rad(r:NextNumber(-5, 5))
	local cf = CFrame.new(0, -0.6, 0)
	for i = 1, 5 do
		cyl(m, base, cf * CFrame.new(0, segH / 2, 0), segH + 0.2, (1.7 - i * 0.1) * s, COL.Trunk, MAT.Wood)
		cf = cf * CFrame.new(0, segH, 0) * CFrame.Angles(0, 0, lean)
	end
	for i = 1, 8 do
		local ang = (i / 8) * math.pi * 2 + r:NextNumber(-0.2, 0.2)
		local f = cf * CFrame.Angles(0, ang, 0) * CFrame.Angles(0, 0, math.rad(-20 - r:NextNumber(0, 15))) * CFrame.new(3.4 * s, 0, 0)
		part(m, base, f, Vector3.new(7 * s, 0.2, 2.3 * s), i % 2 == 0 and COL.Leaf or COL.LeafDark, MAT.LeafyGrass, nil, false)
	end
	for i = 1, 3 do
		local a = i * 2.1
		ball(m, base, cf * CFrame.new(math.cos(a) * 0.9, -0.7, math.sin(a) * 0.9), 0.85 * s, COL.Coconut, MAT.Wood, false)
	end
end

-- Carvalho: muita madeira + madeira de lei
function B.OakTree(m, base, r)
	local s = r:NextNumber(0.95, 1.35)
	local h = 7 * s
	cyl(m, base, CFrame.new(0, h / 2 - 0.5, 0), h, 2.4 * s, COL.Trunk, MAT.Wood)
	cyl(m, base, CFrame.new(0, 0.3, 0), 1.2, 3.3 * s, COL.Trunk, MAT.Wood)
	local top = h - 0.5
	local blobs = { { 0, 3.2, 0, 9 }, { -3, 2.2, 1.5, 6.5 }, { 3, 2.4, -1.2, 6.8 }, { 0.5, 5.4, 0.5, 6.5 }, { -1, 2, -3, 6 } }
	for i, b in blobs do
		ball(m, base, CFrame.new(b[1] * s, top + b[2] * s, b[3] * s), b[4] * s, i % 2 == 0 and COL.Leaf or COL.LeafDark, MAT.LeafyGrass, false)
	end
end

-- Pinheiro: madeira + resina (camadas de agulhas)
function B.PineTree(m, base, r)
	local s = r:NextNumber(0.9, 1.4)
	cyl(m, base, CFrame.new(0, 5 * s - 0.5, 0), 10 * s, 1.5 * s, COL.Trunk, MAT.Wood)
	for i = 1, 5 do
		cyl(m, base, CFrame.new(0, (2.5 + (i - 1) * 2.6) * s, 0), 2.4 * s, (10 - (i - 1) * 2) * s, i % 2 == 0 and COL.PineLight or COL.Pine, MAT.LeafyGrass, false)
	end
end

-- Macieira: maçãs
function B.AppleTree(m, base, r)
	local s = r:NextNumber(0.9, 1.2)
	cyl(m, base, CFrame.new(0, 2.25 * s - 0.5, 0), 4.5 * s, 1.5 * s, COL.Trunk, MAT.Wood)
	local blobs = { { 0, 7, 0, 8 }, { -2.4, 6, 1, 5.6 }, { 2.4, 6.2, -1, 5.6 } }
	for i, b in blobs do
		ball(m, base, CFrame.new(b[1] * s, b[2] * s, b[3] * s), b[4] * s, i == 1 and COL.Leaf or COL.LeafDark, MAT.LeafyGrass, false)
	end
	for _ = 1, 7 do
		local v = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-0.3, 1), r:NextNumber(-1, 1)).Unit * (4 * s)
		ball(m, base, CFrame.new(v.X, 7 * s + v.Y, v.Z), 0.7 * s, COL.Apple, MAT.SmoothPlastic, false)
	end
end

-- Bananeira: bananas + fibra
function B.BananaTree(m, base, r)
	local s = r:NextNumber(0.9, 1.2)
	cyl(m, base, CFrame.new(0, 3 * s - 0.5, 0), 6 * s, 0.9 * s, COL.BananaTrunk, MAT.Wood)
	for i = 1, 6 do
		local ang = (i / 6) * math.pi * 2
		local f = CFrame.new(0, 5.8 * s, 0) * CFrame.Angles(0, ang, 0) * CFrame.Angles(0, 0, math.rad(22 + r:NextNumber(0, 10))) * CFrame.new(3 * s, 0, 0)
		part(m, base, f, Vector3.new(6 * s, 0.15, 2.2 * s), COL.BananaLeaf, MAT.LeafyGrass, nil, false)
	end
	for k = 1, 5 do
		part(m, base, CFrame.new(0.8 * s + math.cos(k * 1.3) * 0.4, 5 * s, math.sin(k * 1.3) * 0.4) * CFrame.Angles(0, 0, math.rad(8)), Vector3.new(0.35, 1.5, 0.35), COL.Banana, MAT.SmoothPlastic, nil, false)
	end
end

-- Árvore-de-ferro (rara, montanha): madeira de lei + chance de ferro
function B.IronwoodTree(m, base, r)
	local s = r:NextNumber(1.0, 1.4)
	cyl(m, base, CFrame.new(0, 4 * s - 0.5, 0), 8 * s, 2.8 * s, COL.Ironwood, MAT.Wood)
	for _, y in { 2.5, 5 } do
		cyl(m, base, CFrame.new(0, y * s, 0), 0.4, 3 * s, COL.IronBand, MAT.Metal)
	end
	local blobs = { { 0, 9.5, 0, 8 }, { -2.5, 8.2, 1.2, 5.5 }, { 2.5, 8.6, -1, 5.5 } }
	for _, b in blobs do
		ball(m, base, CFrame.new(b[1] * s, b[2] * s, b[3] * s), b[4] * s, COL.IronwoodLeaf, MAT.LeafyGrass, false)
	end
end

local function bushBase(m, base, r)
	local s = r:NextNumber(0.85, 1.3)
	for i = 1, 3 do
		ball(m, base, CFrame.new((i - 2) * 1.1 * s, 0.9 * s, r:NextNumber(-0.6, 0.6)), (2.8 - 0.2 * i) * s, i % 2 == 0 and COL.Bush or COL.BushDark, MAT.LeafyGrass, false)
	end
	return s
end

function B.Bush(m, base, r) bushBase(m, base, r) end

function B.BerryBush(m, base, r)
	local s = bushBase(m, base, r)
	for _ = 1, 8 do
		local v = Vector3.new(r:NextNumber(-1, 1), r:NextNumber(0, 1), r:NextNumber(-1, 1)).Unit * (1.5 * s)
		ball(m, base, CFrame.new(v.X, 0.9 * s + v.Y, v.Z), 0.45, COL.Berry, MAT.SmoothPlastic, false)
	end
end

function B.HerbBush(m, base, r)
	for i = 1, 7 do
		local ang = (i / 7) * math.pi * 2
		part(m, base, CFrame.Angles(0, ang, 0) * CFrame.new(0.8, 0.8, 0) * CFrame.Angles(0, 0, math.rad(50)), Vector3.new(1.8, 0.1, 0.6), COL.Herb, MAT.LeafyGrass, nil, false)
		ball(m, base, CFrame.Angles(0, ang, 0) * CFrame.new(1.5, 1.4, 0), 0.3, COL.Flower, MAT.SmoothPlastic, false)
	end
end

local function rockBase(m, base, r, color, mat)
	local s = r:NextNumber(0.8, 1.5)
	part(m, base, CFrame.new(0, 0.9 * s, 0) * CFrame.Angles(r:NextNumber(-0.2, 0.2), r:NextNumber(0, 6.28), r:NextNumber(-0.2, 0.2)), Vector3.new(4.2, 3.2, 3.8) * s, color, mat)
	part(m, base, CFrame.new(2.2 * s, 0.6 * s, 1 * s) * CFrame.Angles(0, r:NextNumber(0, 6.28), r:NextNumber(-0.3, 0.3)), Vector3.new(2.2, 1.6, 2) * s, COL.RockDark, MAT.Basalt)
	part(m, base, CFrame.new(-1.8 * s, 0.5 * s, -1.2 * s) * CFrame.Angles(0, r:NextNumber(0, 6.28), 0), Vector3.new(1.8, 1.3, 1.6) * s, color, mat)
	return s
end

function B.Rock(m, base, r) rockBase(m, base, r, COL.Rock, MAT.Slate) end

local function ore(m, base, r, color, mat, refl)
	local s = rockBase(m, base, r, COL.RockDark, MAT.Basalt)
	for _ = 1, 5 do
		local a, d = r:NextNumber(0, 6.28), r:NextNumber(0, 1.6) * s
		local p = part(m, base, CFrame.new(math.cos(a) * d, 2.2 * s + r:NextNumber(0, 0.8), math.sin(a) * d) * CFrame.Angles(r:NextNumber(-0.7, 0.7), r:NextNumber(0, 6.28), r:NextNumber(-0.7, 0.7)), Vector3.new(1, 1.4, 1) * (r:NextNumber(0.9, 1.5) * s), color, mat)
		if refl then p.Reflectance = refl end
	end
end

function B.OreIron(m, base, r) ore(m, base, r, COL.OreIron, MAT.CorrodedMetal) end
function B.OreGold(m, base, r) ore(m, base, r, COL.OreGold, MAT.Metal, 0.12) end
function B.OreCoal(m, base, r) ore(m, base, r, COL.OreCoal, MAT.Basalt) end

function B.Driftwood(m, base, r)
	local s = r:NextNumber(0.8, 1.4)
	part(m, base, CFrame.new(0, 0.4, 0) * CFrame.Angles(0, r:NextNumber(0, 3), math.rad(r:NextNumber(-6, 6))), Vector3.new(5 * s, 0.8, 0.8), COL.Drift, MAT.Wood, Enum.PartType.Cylinder)
	part(m, base, CFrame.new(0.6, 0.35, 0.9) * CFrame.Angles(0, r:NextNumber(0.8, 2.2), 0), Vector3.new(3 * s, 0.6, 0.6), COL.Drift, MAT.Wood, Enum.PartType.Cylinder)
end

Generator.Builders = B

----------------------------------------------------------------------
-- Novos recursos
----------------------------------------------------------------------
COL.MushStem = Color3.fromRGB(235, 225, 205)
COL.MushCap = Color3.fromRGB(200, 60, 50)
COL.MushCap2 = Color3.fromRGB(190, 140, 90)
COL.Clay = Color3.fromRGB(176, 112, 82)
COL.Shell = Color3.fromRGB(245, 240, 232)
COL.ShellPink = Color3.fromRGB(240, 190, 190)
COL.OreCopper = Color3.fromRGB(214, 128, 60)
COL.Patina = Color3.fromRGB(70, 170, 150)
COL.Crystal = Color3.fromRGB(150, 110, 255)
COL.Crystal2 = Color3.fromRGB(110, 190, 255)
COL.Sulfur = Color3.fromRGB(232, 208, 62)
COL.SulfurLight = Color3.fromRGB(250, 235, 90)
COL.Obsidian = Color3.fromRGB(24, 20, 32)
COL.Hive = Color3.fromRGB(222, 170, 60)
COL.HiveDark = Color3.fromRGB(150, 105, 40)

local function ellipsoid(model, base, off, size, color, material, collide)
	return part(model, base, off, size, color, material, Enum.PartType.Ball, collide)
end

-- Cogumelos (3 espécies, cada uma com cores próprias; os efeitos estão no NutritionConfig)
local function mushroomPatch(m, base, r, capA, capB, spots, glow)
	for i = 1, 5 do
		local a, d, s = r:NextNumber(0, 6.28), r:NextNumber(0.1, 1.5), r:NextNumber(0.6, 1.2)
		local x, z = math.cos(a) * d, math.sin(a) * d
		cyl(m, base, CFrame.new(x, 0.45 * s, z), 0.9 * s, 0.35 * s, COL.MushStem, MAT.SmoothPlastic, false)
		local capColor = (i % 2 == 0) and capA or capB
		local cap = ellipsoid(m, base, CFrame.new(x, 0.95 * s, z), Vector3.new(1.3, 0.7, 1.3) * s, capColor, glow and MAT.Neon or MAT.SmoothPlastic, false)
		if glow then cap.Transparency = 0.1 end
		if spots then
			for k = 1, 3 do
				local sa = r:NextNumber(0, 6.28)
				ellipsoid(m, base, CFrame.new(x + math.cos(sa) * 0.3 * s, 1.2 * s, z + math.sin(sa) * 0.3 * s), Vector3.new(0.18, 0.1, 0.18) * s, Color3.fromRGB(250, 250, 245), MAT.SmoothPlastic, false)
			end
		end
	end
end

function B.Mushroom(m, base, r) -- Cogumelo Marrom
	mushroomPatch(m, base, r, Color3.fromRGB(160, 110, 70), Color3.fromRGB(190, 140, 90), false, false)
end
function B.MushroomRed(m, base, r) -- Cogumelo Vermelho (com pintinhas)
	mushroomPatch(m, base, r, Color3.fromRGB(215, 50, 50), Color3.fromRGB(190, 40, 60), true, false)
end
function B.MushroomBlue(m, base, r) -- Cogumelo Azul (brilha)
	mushroomPatch(m, base, r, Color3.fromRGB(90, 160, 255), Color3.fromRGB(120, 120, 255), false, true)
end

-- Depósito de argila (praia/margem)
function B.ClayDeposit(m, base, r)
	local s = r:NextNumber(0.9, 1.4)
	ellipsoid(m, base, CFrame.new(0, 0.2 * s, 0), Vector3.new(4.8, 2.2, 4.2) * s, COL.Clay, MAT.Mud)
	ellipsoid(m, base, CFrame.new(1.8 * s, 0.1, 1 * s), Vector3.new(2.4, 1.2, 2) * s, COL.Clay, MAT.Mud, false)
	ellipsoid(m, base, CFrame.new(-1.6 * s, 0.1, -1.2 * s), Vector3.new(2, 1, 1.8) * s, COL.Clay, MAT.Mud, false)
end

-- Conchas (praia)
function B.ShellPile(m, base, r)
	for i = 1, 6 do
		local a, d, s = r:NextNumber(0, 6.28), r:NextNumber(0, 1.2), r:NextNumber(0.8, 1.3)
		ellipsoid(m, base, CFrame.new(math.cos(a) * d, 0.2, math.sin(a) * d) * CFrame.Angles(0, a, 0), Vector3.new(0.9, 0.35, 0.7) * s, (i % 2 == 0) and COL.Shell or COL.ShellPink, MAT.SmoothPlastic, false)
	end
end

function B.OreCopper(m, base, r)
	ore(m, base, r, COL.OreCopper, MAT.Metal, 0.1)
	for _ = 1, 3 do
		local a = r:NextNumber(0, 6.28)
		part(m, base, CFrame.new(math.cos(a) * 1.6, 1.4, math.sin(a) * 1.6) * CFrame.Angles(r:NextNumber(-0.5, 0.5), r:NextNumber(0, 6.28), 0), Vector3.new(0.5, 0.4, 0.5), COL.Patina, MAT.SmoothPlastic, nil, false)
	end
end

-- Cristal (raro, montanha): cacos brilhantes
function B.OreCrystal(m, base, r)
	local s = rockBase(m, base, r, COL.RockDark, MAT.Basalt)
	for i = 1, 6 do
		local a, d = r:NextNumber(0, 6.28), r:NextNumber(0, 1.6) * s
		local h = r:NextNumber(2.2, 4.2) * s
		local p = part(m, base, CFrame.new(math.cos(a) * d, 2.4 * s + h * 0.4, math.sin(a) * d) * CFrame.Angles(r:NextNumber(-0.35, 0.35), r:NextNumber(0, 6.28), r:NextNumber(-0.35, 0.35)), Vector3.new(0.7, h, 0.7), (i % 2 == 0) and COL.Crystal or COL.Crystal2, MAT.Neon)
		p.Transparency = 0.15
	end
end

-- Respiradouro de enxofre (perto do vulcão), solta um pouco de vapor
function B.SulfurVent(m, base, r)
	local s = r:NextNumber(0.9, 1.3)
	local mound = ellipsoid(m, base, CFrame.new(0, 0.7 * s, 0), Vector3.new(4.5, 2.6, 4.5) * s, COL.Sulfur, MAT.Slate)
	for _ = 1, 4 do
		local a = r:NextNumber(0, 6.28)
		part(m, base, CFrame.new(math.cos(a) * 1.4 * s, 1.9 * s, math.sin(a) * 1.4 * s) * CFrame.Angles(r:NextNumber(-0.6, 0.6), r:NextNumber(0, 6.28), r:NextNumber(-0.6, 0.6)), Vector3.new(0.9, 0.9, 0.9) * s, COL.SulfurLight, MAT.SmoothPlastic, nil, false)
	end
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Rate = 3
	pe.Lifetime = NumberRange.new(2, 3)
	pe.Speed = NumberRange.new(2, 4)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(Color3.fromRGB(240, 230, 150))
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = mound
end

-- Rocha de obsidiana (vulcão)
function B.ObsidianRock(m, base, r)
	local s = rockBase(m, base, r, COL.Obsidian, MAT.Basalt)
	for _ = 1, 4 do
		local a, d = r:NextNumber(0, 6.28), r:NextNumber(0, 1.4) * s
		local h = r:NextNumber(1.8, 3.4) * s
		local p = part(m, base, CFrame.new(math.cos(a) * d, 2 * s + h * 0.3, math.sin(a) * d) * CFrame.Angles(r:NextNumber(-0.4, 0.4), r:NextNumber(0, 6.28), r:NextNumber(-0.4, 0.4)), Vector3.new(0.8, h, 0.8), COL.Obsidian, MAT.Glass)
		p.Reflectance = 0.25
	end
end

-- Colmeia (mel) num poste baixo
function B.Beehive(m, base, r)
	local s = r:NextNumber(0.95, 1.25)
	cyl(m, base, CFrame.new(0, 1.6 * s - 0.4, 0), 3.2 * s, 0.9 * s, COL.Trunk, MAT.Wood)
	for i = 1, 4 do
		local w = (2.6 - i * 0.35) * s
		ellipsoid(m, base, CFrame.new(0, (3.1 + (i - 1) * 0.9) * s, 0), Vector3.new(w, 1.1 * s, w), (i % 2 == 0) and COL.HiveDark or COL.Hive, MAT.SmoothPlastic, false)
	end
	ellipsoid(m, base, CFrame.new(0, 3.2 * s, 1.05 * s), Vector3.new(0.5, 0.5, 0.3), COL.Obsidian, MAT.SmoothPlastic, false)
end

----------------------------------------------------------------------
-- Modelos-modelo para o ResourceService (Root + Full + Depleted)
----------------------------------------------------------------------
local TREE_LIKE = { Tree = true, OakTree = true, PineTree = true, AppleTree = true, BananaTree = true, IronwoodTree = true }
local BUSH_LIKE = { Bush = true, BerryBush = true, HerbBush = true, Mushroom = true, MushroomRed = true, MushroomBlue = true }
local NO_STUMP = { Driftwood = true, ShellPile = true }

local function hashName(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 2147483647 end
	return h
end

-- visual do recurso depois de coletado (toco, brotinho, pedrinhas)
local function buildDepleted(m, baseType, r)
	local base = CFrame.new()
	if TREE_LIKE[baseType] then
		cyl(m, base, CFrame.new(0, 0.5, 0), 1.2, 1.9, COL.Trunk, MAT.Wood)
	elseif BUSH_LIKE[baseType] then
		ball(m, base, CFrame.new(0, 0.35, 0), 0.9, COL.BushDark, MAT.LeafyGrass, false)
	elseif baseType == "Beehive" then
		cyl(m, base, CFrame.new(0, 0.9, 0), 1.8, 0.9, COL.Trunk, MAT.Wood)
	elseif not NO_STUMP[baseType] then
		part(m, base, CFrame.new(0, 0.3, 0) * CFrame.Angles(0, r:NextNumber(0, 6), 0), Vector3.new(1.6, 0.6, 1.4), COL.RockDark, MAT.Basalt)
		part(m, base, CFrame.new(1.2, 0.2, 0.6), Vector3.new(0.9, 0.4, 0.8), COL.Rock, MAT.Slate)
	end
end

local function buildTemplate(templateName, baseType)
	local m = Instance.new("Model")
	m.Name = templateName
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(0, 0, 0)
	root.Parent = m
	m.PrimaryPart = root

	local r = Random.new(hashName(templateName))
	local full = Instance.new("Model")
	full.Name = "Full"
	B[baseType](full, CFrame.new(), r)
	full.Parent = m

	local dep = Instance.new("Model")
	dep.Name = "Depleted"
	buildDepleted(dep, baseType, r)
	dep.Parent = m
	return m
end

-- Cria (se faltar) o modelo de cada tipo/variante. Seguro chamar mais de uma vez.
function Generator.EnsureTemplates(folder)
	local made = 0
	for _, entry in Cfg.Scatter do
		for i = 1, Cfg.Variants do
			local k = (i == 1) and entry.Node or (entry.Node .. "_V" .. i)
			local def = ResourceConfig.Nodes[k]
			if def and def.Template and B[entry.Node] and not folder:FindFirstChild(def.Template) then
				buildTemplate(def.Template, entry.Node).Parent = folder
				made += 1
			end
		end
	end
	return made
end

----------------------------------------------------------------------
-- Marcadores de recurso (o ResourceService cria o modelo + prompt em cada um)
----------------------------------------------------------------------
local function pickKey(base)
	local i = rng:NextInteger(1, Cfg.Variants)
	local k = (i == 1) and base or (base .. "_V" .. i)
	if ResourceConfig.Nodes[k] then return k end
	return base
end

local function addMarker(k, pos, parent)
	local marker = Instance.new("Part")
	marker.Name = k .. "Spawn"
	marker.Size = Vector3.new(2, 2, 2)
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) -- o ResourceService desce 1 stud
	marker:SetAttribute("ResourceType", k)
	marker:SetAttribute("IslandIndex", 0) -- 0 = ilha central, qualquer jogador coleta
	marker.Parent = parent
	return marker
end

-- Para eventos (ex: minérios do meteoro). Precisa do patch no ResourceService (PATCHES.md).
local function getResourceService()
	local m = script.Parent:FindFirstChild("ResourceService")
	if not m then return nil end
	local ok, svc = pcall(require, m)
	return ok and svc or nil
end

function Generator.SpawnRuntimeNode(k, pos)
	local RS = getResourceService()
	if not RS or not RS.SpawnAtMarker then return nil end
	local marker = addMarker(k, pos, folders.EventMarkers)
	local model = RS.SpawnAtMarker(marker)
	if not model then marker:Destroy() end
	return model, marker
end

function Generator.RemoveRuntimeNode(model, marker)
	local RS = getResourceService()
	if RS and RS.RemoveNode and model then RS.RemoveNode(model) end
	if marker then marker:Destroy() end
end

----------------------------------------------------------------------
-- Poços de água
----------------------------------------------------------------------
local function buildWell(pos, index)
	local m = Instance.new("Model")
	m.Name = "WaterWell_" .. index
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CFrame = CFrame.new(pos)
	root.Parent = m
	m.PrimaryPart = root

	local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	cyl(m, base, CFrame.new(0, 0.4, 0), 0.8, 5, Color3.fromRGB(70, 60, 55), MAT.Slate)
	for k = 1, 8 do
		local a = (k / 8) * math.pi * 2
		part(m, base, CFrame.new(math.cos(a) * 2.6, 1.1, math.sin(a) * 2.6) * CFrame.Angles(0, -a, 0), Vector3.new(1.6, 1.8, 2.2), COL.Stone, MAT.Cobblestone)
	end
	local water = cyl(m, base, CFrame.new(0, 1.35, 0), 0.4, 4.2, COL.Water, MAT.SmoothPlastic, false)
	water.Name = "Water"
	water.Transparency = 0.25
	-- estrutura de madeira + balde
	for _, sx in { -3, 3 } do
		part(m, base, CFrame.new(sx, 3, 0), Vector3.new(0.5, 6, 0.5), COL.Trunk, MAT.Wood)
	end
	cyl(m, base, CFrame.new(0, 5.8, 0) * CFrame.Angles(0, 0, math.rad(-90)), 6.8, 0.4, COL.Trunk, MAT.Wood)
	part(m, base, CFrame.new(0, 4.6, 0), Vector3.new(0.12, 2.4, 0.12), Color3.fromRGB(190, 170, 120), MAT.Fabric, nil, false)
	cyl(m, base, CFrame.new(0, 3.2, 0), 0.9, 0.9, Color3.fromRGB(110, 80, 50), MAT.Wood, false)

	m:SetAttribute("IsWaterWell", true)
	m:SetAttribute("MaxWater", Cfg.Wells.MaxWater)
	m:SetAttribute("Water", Cfg.Wells.MaxWater)
	m:SetAttribute("Dry", false)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Beber água"
	prompt.ObjectText = "Poço"
	prompt.HoldDuration = 0.8
	prompt.KeyboardKeyCode = Cfg.Wells.PromptKey
	prompt.MaxActivationDistance = Cfg.Wells.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = water

	local function refresh()
		local w = m:GetAttribute("Water")
		local mx = m:GetAttribute("MaxWater")
		water.Transparency = 0.25 + 0.75 * (1 - clamp(w / mx, 0, 1))
		prompt.Enabled = w > 0 and not m:GetAttribute("Dry")
	end
	m:GetAttributeChangedSignal("Water"):Connect(refresh)
	m:GetAttributeChangedSignal("Dry"):Connect(refresh)

	prompt.Triggered:Connect(function(player)
		local w = m:GetAttribute("Water")
		if m:GetAttribute("Dry") or w <= 0 then return end
		local amt = math.min(Cfg.Wells.DrinkAmount, w)
		m:SetAttribute("Water", w - amt)
		Generator.WellDrank:Fire(player, m, amt)
	end)

	CollectionService:AddTag(m, "WaterWell")
	m.Parent = folders.Wells
	table.insert(Generator.Wells, m)
end


----------------------------------------------------------------------
-- Vulcão (adormecido). A erupção de verdade você liga depois pela API:
--   Generator.Volcano                      -> dados (Center, RimY, Radius, CraterRadius, Lava, Vent...)
--   Generator.SetVolcanoState("Dormant" | "Warning" | "Erupting")
--   Generator.VolcanoStateChanged.Event    -> (novoEstado, estadoAnterior)
--   Generator.Volcano.Erupt(duracao)       -> erupção visual simples (exemplo para você substituir)
--   Workspace.CentralIsland.Volcano        -> Model com Attribute "VolcanoState"
----------------------------------------------------------------------
Generator.VolcanoStateChanged = Instance.new("BindableEvent")
Generator.Volcano = nil

local VOLCANO_STATES = {
	Dormant  = { Smoke = 5,  SmokeSize = 14, Light = 1.5, Embers = 0 },
	Warning  = { Smoke = 18, SmokeSize = 22, Light = 3.5, Embers = 4 },
	Erupting = { Smoke = 60, SmokeSize = 42, Light = 7,   Embers = 40 },
}

function Generator.SetVolcanoState(state)
	local v = Generator.Volcano
	local cfg = VOLCANO_STATES[state]
	if not v or not cfg then return false end
	local previous = v.State
	v.State = state
	v.Model:SetAttribute("VolcanoState", state)
	v.Smoke.Rate = cfg.Smoke
	v.Smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, cfg.SmokeSize * 0.4), NumberSequenceKeypoint.new(1, cfg.SmokeSize) })
	v.Embers.Rate = cfg.Embers
	v.Light.Brightness = cfg.Light
	v.Lava.Color = (state == "Dormant") and Color3.fromRGB(255, 110, 30) or Color3.fromRGB(255, 150, 40)
	Generator.VolcanoStateChanged:Fire(state, previous)
	return true
end

local function buildVolcano()
	if not VOL then return end
	local floorPos = groundAt(VOL.X, VOL.Z)
	if not floorPos then return end

	local model = Instance.new("Model")
	model.Name = "Volcano"
	model:SetAttribute("VolcanoState", "Dormant")
	model.Parent = folders.Root

	local lavaY = floorPos.Y + VOL.Depth * 0.5
	local lavaDiameter = VOL.CraterRadius * 1.5

	local lava = Instance.new("Part")
	lava.Name = "Lava"
	lava.Shape = Enum.PartType.Cylinder
	lava.Size = Vector3.new(0.8, lavaDiameter, lavaDiameter)
	lava.CFrame = CFrame.new(VOL.X, lavaY, VOL.Z) * CFrame.Angles(0, 0, math.rad(90))
	lava.Anchored = true
	lava.CanCollide = false
	lava.CanQuery = false
	lava.Material = MAT.Neon
	lava.Color = Color3.fromRGB(255, 110, 30)
	lava.Parent = model

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Range = 80
	light.Brightness = 1.5
	light.Parent = lava

	-- ponto de saída de fumaça/brasas (invisível), pronto para a erupção
	local vent = Instance.new("Part")
	vent.Name = "Vent"
	vent.Size = Vector3.new(2, 2, 2)
	vent.Transparency = 1
	vent.Anchored = true
	vent.CanCollide = false
	vent.CanQuery = false
	vent.CanTouch = false
	vent.CFrame = CFrame.new(VOL.X, lavaY + 4, VOL.Z)
	vent.Parent = model

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 5
	smoke.Lifetime = NumberRange.new(8, 12)
	smoke.Speed = NumberRange.new(10, 16)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-10, 10)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 70))
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = vent

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Rate = 0
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Speed = NumberRange.new(40, 90)
	embers.SpreadAngle = Vector2.new(35, 35)
	embers.Acceleration = Vector3.new(0, -45, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 70, 20))
	embers.LightEmission = 1
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Parent = vent

	Generator.Volcano = {
		Model = model,
		Center = Vector3.new(VOL.X, lavaY, VOL.Z),
		RimY = Sea + volcanoHeight(VOL.X + VOL.CraterRadius, VOL.Z) + 8,
		Radius = VOL.Radius,
		CraterRadius = VOL.CraterRadius,
		Lava = lava,
		Vent = vent,
		Smoke = smoke,
		Embers = embers,
		Light = light,
		State = "Dormant",
	}

	-- Exemplo simples de erupção (só visual). Substitua pelo seu script de erupção.
	function Generator.Volcano.Erupt(duration)
		task.spawn(function()
			Generator.SetVolcanoState("Warning")
			task.wait(6)
			Generator.SetVolcanoState("Erupting")
			task.wait(duration or 25)
			Generator.SetVolcanoState("Dormant")
		end)
	end

	-- Lava machuca quem entra nela
	local damage = Cfg.Volcano.LavaDamage or 0
	if damage > 0 then
		local radius = lavaDiameter / 2
		task.spawn(function()
			while model.Parent do
				task.wait(0.5)
				for _, plr in game:GetService("Players"):GetPlayers() do
					local char = plr.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and hum and hum.Health > 0 then
						local dx, dz = root.Position.X - VOL.X, root.Position.Z - VOL.Z
						if dx * dx + dz * dz < radius * radius and math.abs(root.Position.Y - lavaY) < 8 then
							hum:TakeDamage(damage * 0.5)
						end
					end
				end
			end
		end)
	end

	reserve(VOL.X, VOL.Z, 12)
end

----------------------------------------------------------------------
-- Trilhas (caminhos suaves nas montanhas) aplicadas na malha de alturas
----------------------------------------------------------------------
local function carveTrail(cx, cz, r0, r1, theta0, topRel)
	local T = Cfg.Trails
	local samples = 420
	local rad = math.ceil(T.Width / STEP)
	local startH
	for k = 0, samples do
		local t = k / samples
		local r = r0 + (r1 - r0) * t
		local theta = theta0 + T.Turns * 2 * math.pi * t
		local x, z = cx + math.cos(theta) * r, cz + math.sin(theta) * r
		local natural = gridHeight(x, z)
		if natural then
			if not startH then startH = math.max(6, natural) end
			local targetH = startH + (topRel - startH) * t
			local ci = math.floor((x - originX) / STEP + 0.5)
			local cj = math.floor((z - originZ) / STEP + 0.5)
			for di = -rad, rad do
				for dj = -rad, rad do
					local gi, gj = ci + di, cj + dj
					if gi >= 0 and gj >= 0 and gi <= N + 1 and gj <= N + 1 then
						local d = math.sqrt(di * di + dj * dj) * STEP
						if d <= T.Width then
							local w = 1 - smoothstep(T.Width * 0.45, T.Width, d)
							local idx = gi * W + gj + 1
							H[idx] = H[idx] + (targetH - H[idx]) * w
						end
					end
				end
			end
		end
	end
end

local function applyTrails()
	local T = Cfg.Trails
	if not T or not T.Enabled then return end
	if VOL then
		local rim = volcanoHeight(VOL.X + VOL.CraterRadius * 1.12, VOL.Z) + 8
		carveTrail(VOL.X, VOL.Z, VOL.Radius * 1.02, VOL.CraterRadius * 1.12, rng:NextNumber(0, 6.28), rim)
		carveTrail(VOL.X, VOL.Z, VOL.Radius * 1.02, VOL.CraterRadius * 1.12, rng:NextNumber(0, 6.28), rim)
	end
	local peakH = gridHeight(peak.X, peak.Z) or 120
	local sigma = R * 0.23
	carveTrail(peak.X, peak.Z, sigma * 1.1, sigma * 0.08, rng:NextNumber(0, 6.28), peakH)
	carveTrail(peak.X, peak.Z, sigma * 1.1, sigma * 0.08, rng:NextNumber(0, 6.28), peakH)
end

----------------------------------------------------------------------
-- Cavernas: planejamento, consulta e recursos
----------------------------------------------------------------------
local function planCaves()
	CAVES = {}
	local C = Cfg.Caves
	if not C or C.Count <= 0 then return end
	local tries = 0
	while #CAVES < C.Count and tries < 600 do
		tries += 1
		local x, z = randomInDisc(R * 0.9)
		local h = gridHeight(x, z)
		if h and h >= C.MinEntranceHeight and h <= C.MaxEntranceHeight then
			-- direção "para dentro da montanha": a que sobe mais
			local bestDir, bestH = nil, h
			for k = 0, 7 do
				local a = k * math.pi / 4
				local hh = gridHeight(x + math.cos(a) * 45, z + math.sin(a) * 45)
				if hh and hh > bestH then bestH, bestDir = hh, a end
			end
			if bestDir and bestH > h + 10 then
				local spheres, chambers = {}, {}
				local heading = bestDir
				local px, pz, py = x, z, h - 3
				local ok = true
				for i = 1, C.Length do
					heading += math.noise(i * 0.37, x * 0.01, z * 0.01) * 0.8
					px += math.cos(heading) * C.Step
					pz += math.sin(heading) * C.Step
					local ground = gridHeight(px, pz)
					if not ground then ok = false break end
					py = py - C.Descent + math.noise(i * 0.5, px * 0.02, pz * 0.02) * 1.2
					-- o teto fica sempre 14+ studs abaixo da superfície (menos na entrada, que abre para fora)
					local ceiling = (i <= 2) and (ground - 2) or (ground - 14)
					if py > ceiling then py = ceiling end
					if py < 4 then py = 4 end
					table.insert(spheres, { px, py, pz, C.TunnelRadius })
					if i % C.ChamberEvery == 0 or i == C.Length then
						local cr = rng:NextNumber(C.ChamberRadius[1], C.ChamberRadius[2])
						table.insert(spheres, { px, py, pz, cr })
						table.insert(chambers, { px, py, pz, cr })
					end
				end
				if ok and #chambers >= 2 then
					local b = { MinX = math.huge, MaxX = -math.huge, MinZ = math.huge, MaxZ = -math.huge }
					for _, sp in spheres do
						b.MinX = math.min(b.MinX, sp[1] - sp[4])
						b.MaxX = math.max(b.MaxX, sp[1] + sp[4])
						b.MinZ = math.min(b.MinZ, sp[3] - sp[4])
						b.MaxZ = math.max(b.MaxZ, sp[3] + sp[4])
					end
					table.insert(CAVES, { Spheres = spheres, Chambers = chambers, Bounds = b, Entrance = Vector3.new(x, Sea + h, z) })
				end
			end
		end
	end
end

function Generator.IsInCave(position)
	for _, cave in CAVES do
		local b = cave.Bounds
		if position.X > b.MinX and position.X < b.MaxX and position.Z > b.MinZ and position.Z < b.MaxZ then
			for _, sp in cave.Spheres do
				local dx, dy, dz = position.X - sp[1], position.Y - (Sea + sp[2]), position.Z - sp[3]
				local r = sp[4] + 1
				if dx * dx + dy * dy + dz * dz < r * r then return true end
			end
		end
	end
	return false
end

function Generator.GetCaves()
	return CAVES
end

local function placeCaveResources()
	local C = Cfg.Caves
	if not C then return 0 end
	local placed = 0
	for _, cave in CAVES do
		for _, chamber in cave.Chambers do
			local cx, cy, cz, cr = chamber[1], Sea + chamber[2], chamber[3], chamber[4]
			for key, count in C.OrePerChamber do
				for _ = 1, count do
					for _ = 1, 14 do
						local a = rng:NextNumber(0, math.pi * 2)
						local d = rng:NextNumber(cr * 0.15, cr * 0.7)
						local x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
						local hit = Workspace:Raycast(Vector3.new(x, cy + cr * 0.5, z), Vector3.new(0, -cr * 1.6, 0), rayParams)
						if hit and hit.Normal.Y > 0.55 and hit.Position.Y > cy - cr and isFree(x, z, 4) then
							reserve(x, z, 4)
							addMarker(pickKey(key), hit.Position, folders.Markers)
							placed += 1
							break
						end
					end
				end
			end
		end
	end
	return placed
end

local function placeWells()
	local placed = {}
	local spacing = Cfg.Wells.MinSpacing
	local tries = 0
	local lowland = Cfg.Zones.Lowland
	while #placed < Cfg.Wells.Count and tries < 1200 do
		tries += 1
		if tries % 200 == 0 then spacing *= 0.75 end
		local x, z = randomInDisc(R * 0.85)
		local h = gridHeight(x, z)
		if h and h >= lowland[1] and h <= lowland[2] and isFree(x, z, 6) then
			local ok = true
			for _, p in placed do
				if (p - Vector3.new(x, 0, z)).Magnitude < spacing then ok = false break end
			end
			if ok then
				local pos, n = groundAt(x, z)
				if pos and n.Y > 0.93 then
					table.insert(placed, Vector3.new(x, 0, z))
					reserve(x, z, 9)
					buildWell(pos, #placed)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- Pontes (da ilha de cada jogador e do lobby até a praia da ilha central)
----------------------------------------------------------------------
local function apothemOf(radius)
	return radius * math.cos(math.pi / MapConfig.Style.PrismSides)
end

-- Anda do mar para dentro até achar chão na altura do deck. outDir = do centro da ilha para fora.
local function findLanding(outDir)
	local need = math.max(MapConfig.Bridges.DeckTop - Sea, 1.5)
	for d = R * 1.6, 10, -2 do
		local x, z = Center.X + outDir.X * d, Center.Z + outDir.Z * d
		local h = gridHeight(x, z)
		if h and h >= need then
			local d2 = math.max(d - 6, 0)
			return Vector3.new(Center.X + outDir.X * d2, 0, Center.Z + outDir.Z * d2)
		end
	end
	return nil
end

local function buildBridgeModel(parent, name, a, b)
	local cfg = MapConfig.Bridges
	local pal = MapConfig.Palette
	local a2, b2 = Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z)
	local direction = b2 - a2
	local length = direction.Magnitude
	local middle = (a2 + b2) / 2
	local frame = CFrame.lookAt(middle, middle + direction.Unit)
	local model = Instance.new("Model")
	model.Name = name

	local function bp(n, size, cf, color, material, shape, collide)
		return part(model, CFrame.new(), cf, size, color, material or MAT.WoodPlanks, shape, collide)
	end

	bp("Deck", Vector3.new(cfg.Width, cfg.DeckThickness, length), frame * CFrame.new(0, cfg.DeckTop - cfg.DeckThickness / 2, 0), pal.Wood)
	for _, side in { -1, 1 } do
		bp("Rail", Vector3.new(0.3, 0.3, length), frame * CFrame.new(side * (cfg.Width / 2 - 0.3), cfg.DeckTop + 1.8, 0), pal.WoodDark, MAT.Wood, nil, false)
	end
	local postCount = math.max(math.floor(length / cfg.PostSpacing), 1)
	for i = 0, postCount do
		local z = -length / 2 + length * i / postCount
		for _, side in { -1, 1 } do
			bp("Post", Vector3.new(0.5, 2.2, 0.5), frame * CFrame.new(side * (cfg.Width / 2 - 0.3), cfg.DeckTop + 1.1, z), pal.WoodDark, MAT.Wood, nil, false)
		end
	end
	local floorY = Sea - Depth
	local pillarTop = cfg.DeckTop - cfg.DeckThickness
	local pillarHeight = pillarTop - floorY
	local pillarCount = math.max(math.floor(length / cfg.PillarSpacing), 1)
	for i = 0, pillarCount do
		local z = -length / 2 + length * i / pillarCount
		for _, side in { -1, 1 } do
			cyl(model, CFrame.new(), frame * CFrame.new(side * (cfg.Width / 2 - 1.5), floorY + pillarHeight / 2, z), pillarHeight, 1.2, pal.WoodDark, MAT.Wood, false)
		end
	end
	model.Parent = parent
	return model
end

local function buildBridges()
	local mainPos = MapConfig.MainIsland.Position
	local cfg = MapConfig.Bridges

	for _, slot in MapService.GetIslandSlots() do
		local toMain = Vector3.new(mainPos.X - slot.Center.X, 0, mainPos.Z - slot.Center.Z).Unit
		local a = slot.Center + toMain * (apothemOf(slot.Radius) - 4)
		local b = findLanding(-toMain)
		if b then
			local model = buildBridgeModel(folders.Bridges, string.format("Bridge_Island%02d", slot.Index), a, b)
			local gatePos = Vector3.new(a.X, cfg.DeckTop + Cfg.Prep.GateHeight / 2, a.Z) + toMain * 5
			Generator.Bridges[slot.Index] = {
				Model = model,
				Width = cfg.Width,
				GateCFrame = CFrame.lookAt(gatePos, gatePos + toMain),
			}
			reserve(b.X, b.Z, 10)
		else
			warn("[IslandGenerator] Não achei praia para a ponte da ilha " .. slot.Index)
		end
	end

	-- lobby -> ilha central
	local lobby = MapConfig.Lobby
	local toMain = Vector3.new(mainPos.X - lobby.Position.X, 0, mainPos.Z - lobby.Position.Z).Unit
	local a = lobby.Position + toMain * (apothemOf(lobby.Radius) - 4)
	local b = findLanding(-toMain)
	if b then
		buildBridgeModel(folders.Bridges, "Bridge_LobbyToMain", a, b)
		reserve(b.X, b.Z, 10)
	end
end

----------------------------------------------------------------------
-- Espalhar recursos
----------------------------------------------------------------------
local function scatterEntry(entry, areaScale)
	local zone = Cfg.Zones[entry.Zone]
	local isVolcano = entry.Zone == "Volcano"
	if isVolcano and not VOL then return 0 end
	local target = math.max(1, math.floor(entry.Count * areaScale + 0.5))
	if isVolcano then target = entry.Count end -- vulcão tem tamanho próprio
	local placed, attempts = 0, 0
	local maxAttempts = target * 80
	local minNY = entry.MinNormalY or 0.8
	while placed < target and attempts < maxAttempts do
		attempts += 1
		local x, z
		if isVolcano then
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(VOL.CraterRadius * 1.6, VOL.Radius * 0.85)
			x, z = VOL.X + math.cos(a) * d, VOL.Z + math.sin(a) * d
		else
			x, z = randomInDisc(R * 1.15)
		end
		local h = gridHeight(x, z)
		local zoneOk = h and ((isVolcano and h > 6) or (not isVolcano and h >= zone[1] and h <= zone[2]))
		if zoneOk and isFree(x, z, entry.MinDist / 2) then
			if not entry.Clump or fbm(x, z, 2, 0.012, seedA + 50) > -0.02 then
				local pos, n = groundAt(x, z)
				if pos and n.Y >= minNY and (pos.Y - Sea) >= zone[1] - 0.5 then
					reserve(x, z, entry.MinDist / 2)
					addMarker(pickKey(entry.Node), pos, folders.Markers)
					placed += 1
					if placed % 30 == 0 then task.wait() end
				end
			end
		end
	end
	return placed
end

----------------------------------------------------------------------
-- Pontes: removidas (travessia a nado / de barco no futuro)
----------------------------------------------------------------------
local function removeAllBridges(keepRoot)
	local found = {}
	for _, inst in Workspace:GetDescendants() do
		if (inst:IsA("Model") or inst:IsA("Folder")) and inst.Name:match("^Bridge")
			and inst ~= keepRoot and not inst:IsDescendantOf(keepRoot) then
			table.insert(found, inst)
		end
	end
	for _, inst in found do
		inst:Destroy()
	end
	return #found
end

----------------------------------------------------------------------
-- Mar infinito: planos de água gigantes além da borda do oceano + neblina no horizonte
----------------------------------------------------------------------
local function buildInfiniteSea(parent)
	local C = Cfg.Sea
	if not C or not C.Enabled then return end

	local ocean = MapConfig.Ocean
	local center = ocean.Position or ocean.Center or MapConfig.MainIsland.Position
	local half = ocean.Size / 2
	local extent = C.Extent
	local TILE = 2000
	local top = Sea - 0.05
	local water = C.TileColor or Workspace.Terrain.WaterColor:Lerp(Color3.fromRGB(10, 50, 85), 0.35)

	local folder = Instance.new("Folder")
	folder.Name = "InfiniteSea"
	folder.Parent = parent

	local count = 0
	local function fillRect(x0, x1, z0, z1)
		local nx = math.max(1, math.ceil((x1 - x0) / TILE))
		local nz = math.max(1, math.ceil((z1 - z0) / TILE))
		local w, d = (x1 - x0) / nx, (z1 - z0) / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local p = Instance.new("Part")
				p.Name = "SeaTile"
				p.Anchored = true
				p.CanCollide = false
				p.CanQuery = false
				p.CanTouch = false
				p.CastShadow = false
				p.Material = Enum.Material.SmoothPlastic
				p.Color = water
				p.Reflectance = 0.06
				p.Size = Vector3.new(w + 1, 4, d + 1) -- 1 stud de sobreposição para não abrir frestas
				p.Position = Vector3.new(center.X + x0 + w * (i + 0.5), top - 2, center.Z + z0 + d * (j + 0.5))
				p.Parent = folder
				count += 1
			end
		end
	end

	local outer = half + extent
	fillRect(-outer, outer, -outer, -half) -- norte
	fillRect(-outer, outer, half, outer)   -- sul
	fillRect(-outer, -half, -half, half)   -- oeste
	fillRect(half, outer, -half, half)     -- leste

	-- neblina do horizonte (o cliente ajusta a cor conforme a hora: OceanAtmosphereClient)
	local Lighting = game:GetService("Lighting")
	Lighting.FogStart = C.FogStart
	Lighting.FogEnd = C.FogEnd
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.34
	atmosphere.Offset = 0.1
	atmosphere.Haze = 1.8
	atmosphere.Glare = 0.1
	print(("[IslandGenerator] Mar infinito: %d planos de água."):format(count))
end

----------------------------------------------------------------------
-- Ciclo de vida
----------------------------------------------------------------------
function Generator.Init()
end

function Generator.Start()
	if not MapService.IsReady() then
		warn("[IslandGenerator] MapService não está pronto. Coloque IslandGenerator DEPOIS do MapService em GameConfig.ServiceLoadOrder.")
		return
	end
	local t0 = os.clock()
	setup()

	local seed = Cfg.Seed ~= 0 and Cfg.Seed or math.random(1, 999999)
	Generator.Seed = seed
	rng = Random.new(seed)
	seedA, seedB, seedC = rng:NextNumber(10, 900) + 0.173, rng:NextNumber(10, 900) + 0.291, rng:NextNumber(10, 900) + 0.437
	local pa = rng:NextNumber(0, math.pi * 2)
	peak = Vector3.new(Center.X + math.cos(pa) * R * 0.35, 0, Center.Z + math.sin(pa) * R * 0.35)
	planVolcano(pa)

	-- pastas
	local old = Workspace:FindFirstChild("CentralIsland")
	if old then old:Destroy() end
	local root = Instance.new("Folder")
	root.Name = "CentralIsland"
	root.Parent = Workspace
	folders.Root = root
	for _, n in { "Wells", "Bridges" } do
		local f = Instance.new("Folder")
		f.Name = n
		f.Parent = root
		folders[n] = f
	end
	local spawnsRoot = Workspace:WaitForChild(MapConfig.Folders.Map):WaitForChild(MapConfig.Folders.ResourceSpawns)
	for _, n in { "CentralIsland", "CentralIsland_Events" } do
		local f = spawnsRoot:FindFirstChild(n)
		if f then f:Destroy() end
	end
	folders.Markers = Instance.new("Folder")
	folders.Markers.Name = "CentralIsland"
	folders.Markers.Parent = spawnsRoot
	folders.EventMarkers = Instance.new("Folder")
	folders.EventMarkers.Name = "CentralIsland_Events"
	folders.EventMarkers.Parent = spawnsRoot

	rayParams.FilterDescendantsInstances = { Workspace.Terrain }

	computeHeights()
	applyTrails()
	planCaves()
	writeTerrain()
	task.wait(1)

	-- modelos para o ResourceService (o patch do ResourceService chama de novo, sem problema)
	local templates = ServerStorage:FindFirstChild("ResourceModels")
	if not templates then
		templates = Instance.new("Folder")
		templates.Name = "ResourceModels"
		templates.Parent = ServerStorage
	end
	Generator.EnsureTemplates(templates)

	buildVolcano()
	local removedBridges = removeAllBridges(folders.Root)
	if Cfg.Bridges and Cfg.Bridges.Enabled then
		buildBridges()
	else
		print(("[IslandGenerator] Pontes removidas: %d"):format(removedBridges))
	end
	buildInfiniteSea(folders.Root)
	placeWells()
	local caveNodes = placeCaveResources()

	local areaScale = (R / Cfg.BaseRadius) ^ 2 * Cfg.CountMultiplier
	local total = 0
	for _, entry in Cfg.Scatter do
		total += scatterEntry(entry, areaScale)
		task.wait()
	end

	-- recarga dos poços
	task.spawn(function()
		while true do
			task.wait(1)
			local mult = Workspace:GetAttribute("WellRefillMultiplier") or 1
			for _, w in Generator.Wells do
				if w.Parent and not w:GetAttribute("Dry") then
					local mx = w:GetAttribute("MaxWater")
					w:SetAttribute("Water", math.min(mx, w:GetAttribute("Water") + Cfg.Wells.RefillPerSecond * mult))
				end
			end
		end
	end)

	Generator.Ready = true
	print(("[IslandGenerator] Ilha pronta (seed %d) em %.1fs | raio %d | recursos: %d | poços: %d | pontes: %d | cavernas: %d (%d minérios) | vulcão: %s"):format(
		seed, os.clock() - t0, R, total, #Generator.Wells, #folders.Bridges:GetChildren(), #CAVES, caveNodes, Generator.Volcano and "sim" or "não"))
end

return Generator

