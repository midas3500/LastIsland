--[[
	GameConfig
	Local: ReplicatedStorage > Modules > GameConfig

	Configuração central do jogo. Para mudar balanceamento, limites ou nomes,
	altere AQUI em vez de procurar números espalhados pelos scripts.
]]

local GameConfig = {}

GameConfig.GameName = "LAST ISLAND"
GameConfig.Version = "0.1.0"

-- true = mostra mensagens extras no Output. Coloque false ao publicar de verdade.
GameConfig.Debug = true

GameConfig.Server = {
	MaxPlayers = 12, -- informativo. O valor real é definido em Game Settings > Places
}

-- Ordem em que o Main carrega os serviços (Init de todos, depois Start de todos).
GameConfig.ServiceLoadOrder = {
	"PlayerDataService",
	"LightingService",
	"MapService",
	"IslandService",
	"InventoryService",
	"ToolUpgradeService",
	"ResourceService",
	"SurvivalService",
	"BuildingService",
	"EventService",
	"QuestService",
	"MonetizationService",
}
-- Remotes que o Main cria dentro de ReplicatedStorage > Remotes.
GameConfig.Remotes = {
	Events = {
		"CollectResource",
		"BuildRequest",
		"UpdateInventory",
		"ToolUpgradeRequest",
		"ToolUpgradeUpdate",
		"EventNotification",
		"SprintRequest",
		"FoodRequest",
	},
	Functions = {}, -- RemoteFunctions futuras
}

-- Limites anti-abuso (usados a partir da Etapa 3). Valores em segundos.
GameConfig.Security = {
	RemoteCooldowns = {
		CollectResource = 0.25,
		BuildRequest = 0.5,
	},
}

-- Salvamento de dados
GameConfig.Data = {
	StoreName = "LastIsland_PlayerData",
	-- Para "zerar" todos os dados durante os testes, troque "v1" por "v2" (cria um banco novo).
	StoreVersion = "v1",
	-- Aumente quando mudar a ESTRUTURA do perfil e escreva uma migração no PlayerDataService.
	SchemaVersion = 1,

	AutoSaveInterval = 120, -- segundos entre salvamentos automáticos
	MaxRetries = 4,         -- tentativas por operação do DataStore
	RetryBaseDelay = 1,     -- espera entre tentativas: 1s, 2s, 4s...

	-- Trava de sessão: impede o mesmo jogador de ter o perfil aberto em 2 servidores.
	LockTimeout = 300,      -- após 300s sem renovar, a trava é considerada abandonada
	LockWaitAttempts = 5,   -- quantas vezes espera a trava ser liberada ao entrar
	LockWaitDelay = 3,      -- segundos entre essas tentativas

	-- Se o perfil não carregar: true = expulsa o jogador com mensagem (mais seguro).
	-- false = joga em "modo seguro" (nada é salvo naquela sessão).
	KickOnLoadFailure = true,
	KickMessage = "Não foi possível carregar seus dados. Eles estão seguros e NÃO foram alterados. Tente entrar novamente em instantes.",

	-- Ferramentas de TESTE (deixe ambos false em produção)
	ForceMockStore = false, -- true = usa memória em vez do DataStore real
	SimulateFailure = false, -- true = finge que o DataStore está fora do ar
}

-- Perfil de um jogador novo. Para adicionar campos no futuro, basta incluí-los aqui:
-- jogadores antigos recebem os campos novos automaticamente ("reconcile").
GameConfig.DefaultProfile = {
	
	SchemaVersion = GameConfig.Data.SchemaVersion,
	CreatedAt = 0,
	Coins = 0,
	Inventory = {},                         -- ex.: { Wood = 10, Stone = 3 } (Etapa 3)
	Tools = {
		Axe = 1,
		Pickaxe = 1,
		Knife = 1,
		FishingRod = 1,
	},
	Buildings = {},                         -- construções salvas (Etapa 4)
	Quests = { Active = {}, Completed = {} },
	Purchases = { Gamepasses = {} },        -- registro de compras (Etapa 8)
	Stats = { Joins = 0, PlayTime = 0 },
	Island = { PreferredSlot = 0 }, 
	Survival = {
		Hunger = 100,
		AquaticProtection = 1,
	},-- ilha preferida (Etapa 2)

}

-- Monetização. Está VAZIA de propósito: nenhum ID inventado.
-- Na Etapa 8 você cria os itens no site do Roblox (Creator Hub) e cola os IDs reais aqui.
-- Formato previsto (NÃO descomente com IDs falsos):
--   Gamepasses = {
--       VIP = { Id = SEU_ID_REAL, Name = "VIP" },
--   },
--   DeveloperProducts = {
--       Coins500 = { Id = SEU_ID_REAL, Coins = 500 },
--   },
GameConfig.Monetization = {
	Gamepasses = {},
	DeveloperProducts = {},
}
-- Ilhas de jogadores (IslandService, Etapa 2)
GameConfig.Islands = {
	SpawnOnIsland = true,
	ReconnectGraceSeconds = 120,
	MaxBuildHeight = 60,
	FreeText = "Disponível",
	OfflineSuffix = " (offline)",
	TagFormat = "Ilha de %s",
	TagHeight = 30,
	TagMaxDistance = 220,
}

return GameConfig