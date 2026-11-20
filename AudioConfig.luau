--[[
	AudioConfig
	Local: ReplicatedStorage > Modules > AudioConfig   (ModuleScript)

	Todos os efeitos sonoros. Cada som tem uma lista de IDs (um é sorteado a cada vez, para variar).
	Ids = {}  significa "PENDENTE": o jogo fica em silêncio nessa ação até você colocar um ID.

	IMPORTANTE: eu não consigo verificar daqui se os IDs existem ou se o seu jogo tem permissão de uso.
	O AudioClient testa cada ID ao iniciar e avisa no Output ("[AudioClient] Áudio com falha: ...")
	para os que não carregarem. Esses IDs são ignorados automaticamente.
]]

local AudioConfig = {}

AudioConfig.DefaultVolume = 0.8     -- volume geral inicial (0 a 1). O jogador ajusta no botão 🔊.
AudioConfig.MaxSimultaneous = 6     -- sons ao mesmo tempo (evita barulheira)
AudioConfig.HitInterval = 0.6       -- intervalo entre pancadas enquanto coleta

-- Volume = volume do som | Pitch = {mín, máx} variação de tom | Cooldown = tempo mínimo entre repetições
AudioConfig.Sounds = {
	-- ⛏️ Mineração
	StoneHit      = { Ids = { 8666678762, 8666682639 }, Volume = 0.7, Pitch = { 0.92, 1.1 } },
	OreHit        = { Ids = { 8666678762 }, Volume = 0.7, Pitch = { 0.9, 1.05 } },
	StoneCollect  = { Ids = { 9119642306 }, Volume = 0.6, Pitch = { 0.95, 1.08 } },
	CrystalHit    = { Ids = {}, Volume = 0.7 }, -- PENDENTE: procurar som de cristal quebrando

	-- 🌴 Madeira e coleta
	WoodChop      = { Ids = { 159798328 }, Volume = 0.7, Pitch = { 0.92, 1.08 } },
	WoodImpact    = { Ids = { 9120907256, 9120904883 }, Volume = 0.6, Pitch = { 0.95, 1.1 } },
	WoodBreak     = { Ids = { 6700552345 }, Volume = 0.7 },
	WoodDrop      = { Ids = { 9126259915 }, Volume = 0.6 },
	FiberCollect  = { Ids = {}, Volume = 0.5 }, -- PENDENTE
	LeafRip       = { Ids = {}, Volume = 0.5 }, -- PENDENTE (arrancar folhas)
	CoconutCollect = { Ids = {}, Volume = 0.6 }, -- PENDENTE
	FruitCollect  = { Ids = { 9113723284 }, Volume = 0.6, Pitch = { 0.95, 1.1 } },
	HoneyCollect  = { Ids = {}, Volume = 0.6 }, -- PENDENTE

	-- 🍎 Comer e beber
	Eat           = { Ids = { 18787611572 }, Volume = 0.7 },
	Bite          = { Ids = { 9113723284 }, Volume = 0.6, Pitch = { 0.9, 1.05 } },
	Drink         = { Ids = { 8260212770 }, Volume = 0.7 },
	Gulp          = { Ids = { 9114171957, 9114172114 }, Volume = 0.6 },

	-- 🛠️ Crafting e construção (todos PENDENTES; use um som diferente para cada ação)
	CraftTool     = { Ids = {}, Volume = 0.7 }, -- marteladas e ferramentas
	CraftPickaxe  = { Ids = {}, Volume = 0.7 }, -- metal sendo trabalhado
	CraftAxe      = { Ids = {}, Volume = 0.7 }, -- pancadas metálicas
	BuildWall     = { Ids = {}, Volume = 0.7 }, -- madeira sendo encaixada
	BuildStructure = { Ids = {}, Volume = 0.7 }, -- martelo e madeira
	CraftDone     = { Ids = {}, Volume = 0.6 }, -- pequeno som de confirmação
	ToolUpgrade   = { Ids = {}, Volume = 0.7 }, -- som metálico de upgrade
	BackpackUpgrade = { Ids = {}, Volume = 0.7 },

	-- 🌩️ Eventos (todos PENDENTES: coloque IDs para ouvir)
	Thunder       = { Ids = {}, Volume = 0.9, Pitch = { 0.9, 1.05 } },
	Rain          = { Ids = {}, Volume = 0.4 },
	Explosion     = { Ids = {}, Volume = 0.9 },
	MeteorWhoosh  = { Ids = {}, Volume = 0.8 },
	VolcanoRoar   = { Ids = {}, Volume = 0.9 },
	LavaBomb      = { Ids = {}, Volume = 0.8 },
	Quake         = { Ids = {}, Volume = 0.9 },
	Alarm         = { Ids = {}, Volume = 0.7 },

	-- 🌊 Água e natação
	WaterEnter    = { Ids = { 444742380, 18756308263, 9120589946 }, Volume = 0.8, Pitch = { 0.95, 1.05 }, Cooldown = 1.0 },
	WaterExit     = { Ids = { 9120590107 }, Volume = 0.7, Cooldown = 1.0 },
	Swim          = { Ids = { 9117940443, 9117941991 }, Volume = 0.35, Pitch = { 0.95, 1.1 }, Cooldown = 0.8 },
}

-- Sons de pancada enquanto coleta, por ferramenta e por recurso (nomes de AudioConfig.Sounds)
AudioConfig.Gather = {
	ByTool = {
		Axe = { Hit = { "WoodChop", "WoodImpact" }, Done = { "WoodBreak", "WoodDrop" } },
		Pickaxe = { Hit = { "StoneHit" }, Done = { "StoneCollect" } },
	},
	ByNode = {
		OreCrystal   = { Hit = { "CrystalHit" }, Done = { "StoneCollect" } },
		OreIron      = { Hit = { "OreHit" }, Done = { "StoneCollect" } },
		OreGold      = { Hit = { "OreHit" }, Done = { "StoneCollect" } },
		OreCoal      = { Hit = { "OreHit" }, Done = { "StoneCollect" } },
		OreCopper    = { Hit = { "OreHit" }, Done = { "StoneCollect" } },
		Bush         = { Hit = { "LeafRip" }, Done = { "FiberCollect" } },
		BerryBush    = { Hit = { "LeafRip" }, Done = { "FruitCollect" } },
		HerbBush     = { Hit = { "LeafRip" }, Done = { "FiberCollect" } },
		Mushroom     = { Hit = {}, Done = { "FruitCollect" } },
		MushroomRed  = { Hit = {}, Done = { "FruitCollect" } },
		MushroomBlue = { Hit = {}, Done = { "FruitCollect" } },
		AppleTree    = { Hit = { "WoodImpact" }, Done = { "FruitCollect" } },
		BananaTree   = { Hit = { "WoodImpact" }, Done = { "FruitCollect" } },
		Beehive      = { Hit = { "HoneyCollect" }, Done = { "HoneyCollect" } },
		ShellPile    = { Hit = {}, Done = { "StoneCollect" } },
		Driftwood    = { Hit = {}, Done = { "WoodDrop" } },
	},
}

-- Som ao receber um item (quando não veio de uma coleta em andamento, ex: recolher do chão)
AudioConfig.ItemPickup = {
	Wood = "WoodDrop", Hardwood = "WoodDrop", Resin = "FiberCollect", Fiber = "FiberCollect",
	Stone = "StoneCollect", IronOre = "StoneCollect", GoldOre = "StoneCollect", CopperOre = "StoneCollect",
	Coal = "StoneCollect", Crystal = "StoneCollect", Obsidian = "StoneCollect", Sulfur = "StoneCollect", Clay = "StoneCollect",
	Coconut = "CoconutCollect", Apple = "FruitCollect", Banana = "FruitCollect", Berry = "FruitCollect",
	Mushroom = "FruitCollect", MushroomRed = "FruitCollect", MushroomBlue = "FruitCollect",
	Herb = "FiberCollect", Honey = "HoneyCollect", Shell = "StoneCollect",
}

-- Itens "de morder" (tocam Bite junto com Eat)
AudioConfig.Crunchy = { Apple = true, Banana = true, Coconut = true, Berry = true }

return AudioConfig

