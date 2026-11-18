--[[
	BackpackConfig
	Local: ReplicatedStorage > Modules > BackpackConfig   (ModuleScript)

	Níveis da mochila. Extra = espaço adicional sobre a capacidade base
	(ResourceConfig.Inventory.BaseCapacity). Cost = itens gastos para chegar NESTE nível.
	Use as mesmas chaves de item do ResourceConfig.Items.
]]

local BackpackConfig = {}

BackpackConfig.Levels = {
	{ Name = "Sacola de Fibra",        Emoji = "👜", Extra = 0,   Cost = nil },
	{ Name = "Mochila de Pano",        Emoji = "🎒", Extra = 60,  Cost = { Fiber = 30, Wood = 20 } },
	{ Name = "Mochila Reforçada",      Emoji = "🎒", Extra = 140, Cost = { Fiber = 50, Wood = 40, Resin = 8, Clay = 10 } },
	{ Name = "Mochila de Explorador",  Emoji = "🧳", Extra = 240, Cost = { Fiber = 60, Hardwood = 15, Resin = 15, CopperOre = 10 } },
	{ Name = "Mochila de Expedição",   Emoji = "🧳", Extra = 380, Cost = { Hardwood = 30, IronOre = 20, CopperOre = 20, Honey = 5 } },
	{ Name = "Mochila Lendária",       Emoji = "💼", Extra = 600, Cost = { Hardwood = 40, GoldOre = 15, Obsidian = 10, Crystal = 5 } },
}

function BackpackConfig.GetCapacity(level, base)
	local data = BackpackConfig.Levels[level] or BackpackConfig.Levels[1]
	return (base or 100) + data.Extra
end

return BackpackConfig

