--[[
	MapConfigPatch
	Local: ReplicatedStorage > Modules > MapConfigPatch   (ModuleScript, ao lado do MapConfig)

	Como usar: no FINAL do MapConfig.luau, ANTES do "return MapConfig", adicione:

		require(script.Parent.MapConfigPatch)(MapConfig)

	O que faz (sem precisar saber os valores atuais do seu MapConfig):
	  - ilha central maior (IslandGenConfig.Map.Radius)
	  - ilhas dos jogadores mais longe (IslandGenConfig.World.BridgeGap de mar entre as costas)
	  - lobby e oceano reposicionados/aumentados para tudo caber
	  - mar mais fundo (IslandGenConfig.World.OceanDepth)
	  - desliga as pontes, a ilha low-poly e o FAROL de torre vermelha do MapService
	    (o IslandGenerator constrói a ilha nova e as pontes novas, sem torre)
]]

return function(MapConfig)
	local G = require(script.Parent:WaitForChild("IslandGenConfig"))

	local main = MapConfig.MainIsland
	local pl = MapConfig.PlayerIslands
	local lobby = MapConfig.Lobby
	local ocean = MapConfig.Ocean

	-- raio externo de uma ilha em prisma (maior camada)
	local function outer(cfg)
		local first = cfg.Tiers and cfg.Tiers[1]
		return cfg.Radius * ((first and first.Scale) or 1)
	end

	-- Ilha central (a costa irregular chega a ~1.3x o raio)
	main.Radius = G.Map.Radius
	main.Enabled = false -- o MapService não constrói mais a ilha low-poly (veja PATCHES.md)
	local mainOuter = G.Map.Radius * 1.3

	-- Ilhas dos jogadores em círculo, bem mais longe
	local plOuter = outer(pl)
	pl.Center = main.Position
	pl.RingRadius = mainOuter + plOuter + G.World.BridgeGap
	-- deixa um vão exatamente no eixo -Z (é onde fica o lobby)
	pl.AngleOffsetDeg = -90 + 180 / pl.Count

	-- Lobby no eixo -Z, entre a ilha central e o círculo
	local lobbyOuter = outer(lobby)
	local lobbyDist = mainOuter + lobbyOuter + G.World.LobbyGap
	lobby.Position = Vector3.new(main.Position.X, lobby.Position.Y, main.Position.Z - lobbyDist)

	-- Mar mais fundo (só aumenta)
	ocean.Depth = math.max(ocean.Depth, G.World.OceanDepth)

	-- Oceano grande o bastante para tudo
	local needed = math.max(pl.RingRadius + plOuter, lobbyDist + lobbyOuter) + G.World.OceanMargin
	ocean.Size = math.max(ocean.Size, math.ceil(needed * 2 / 256) * 256)

	-- As pontes agora são do IslandGenerator (chegam na praia de verdade)
	MapConfig.Bridges.PlayerIslandsToMain = false
	MapConfig.Bridges.LobbyToMain = false
end

