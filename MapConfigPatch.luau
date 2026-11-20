--[[
	MapConfigPatch (v5)
	Local: ReplicatedStorage > Modules > MapConfigPatch   (ModuleScript, ao lado do MapConfig)

	No FINAL do MapConfig.luau, ANTES do "return MapConfig":

		require(script.Parent.MapConfigPatch)(MapConfig)

	O que faz (sem precisar conhecer os valores atuais do seu MapConfig):
	  - ilhas dos jogadores DINÂMICAS (criadas uma por jogador; nada de 12 ilhas esperando)
	  - lobby REMOVIDO
	  - ilha central gigante (IslandGenConfig.Map.Radius) e ilhas dos jogadores maiores
	  - círculo das ilhas dos jogadores afastado da ilha central (IslandGenConfig.World.BridgeGap)
	  - mar mais fundo e oceano grande o bastante para tudo
	  - sem pontes, sem ilha low-poly e sem o farol de torre vermelha do MapService
]]

return function(MapConfig)
	local G = require(script.Parent:WaitForChild("IslandGenConfig"))

	local main = MapConfig.MainIsland
	local pl = MapConfig.PlayerIslands
	local ocean = MapConfig.Ocean

	local function outer(cfg)
		local first = cfg.Tiers and cfg.Tiers[1]
		return cfg.Radius * ((first and first.Scale) or 1)
	end

	-- Ilhas dos jogadores: dinâmicas e maiores
	pl.Dynamic = true
	local k = G.World.PlayerIslandScale or 1
	if k ~= 1 then
		pl.Radius = pl.Radius * k
		if type(pl.BuildRadius) == "number" then pl.BuildRadius = pl.BuildRadius * k end
		local counts = MapConfig.ResourceMarkers and MapConfig.ResourceMarkers.Counts
		if type(counts) == "table" then
			for name, value in counts do
				if type(value) == "number" then
					counts[name] = math.ceil(value * k * k * 0.7)
				end
			end
		end
	end

	-- Lobby removido
	if MapConfig.Lobby then MapConfig.Lobby.Enabled = false end

	-- Ilha central (a costa irregular chega a ~1.3x o raio)
	main.Radius = G.Map.Radius
	main.Enabled = false -- o MapService não constrói mais a ilha low-poly (veja INSTALAR.md)
	local mainOuter = G.Map.Radius * 1.3

	-- Círculo onde as ilhas dos jogadores nascem
	local plOuter = outer(pl)
	pl.Center = main.Position
	pl.RingRadius = mainOuter + plOuter + G.World.BridgeGap
	pl.AngleOffsetDeg = -90 -- ângulo da 1ª ilha; as seguintes vão para o lado oposto

	-- Mar mais fundo (só aumenta) e oceano que cobre o círculo das ilhas + margem
	ocean.Depth = math.max(ocean.Depth, G.World.OceanDepth)
	local needed = pl.RingRadius + plOuter + G.World.OceanMargin
	ocean.Size = math.max(ocean.Size, math.ceil(needed * 2 / 256) * 256)

	-- Sem pontes
	MapConfig.Bridges.PlayerIslandsToMain = false
	MapConfig.Bridges.LobbyToMain = false
end

