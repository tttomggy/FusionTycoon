--!strict
local ItemConfig = {}

ItemConfig.Tiers = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
	Secret = 6,
}

export type ItemDef = {
	Id: string,
	Name: string,
	Tier: string,
}

-- Three items per tier so pulls and fusions have something to collect, not
-- just a colour to climb. The original five ids are kept as the first entry
-- of each tier so existing saves still resolve. A random item of the rolled
-- tier is chosen on every pull/fusion. What an item EARNS on a pedestal is set
-- per tier in TycoonConfig.PedestalCashPerSecond.
ItemConfig.Items = {
	-- Common
	{ Id = "common_spark", Name = "Spark Cell", Tier = "Common" },
	{ Id = "common_bolt", Name = "Copper Bolt", Tier = "Common" },
	{ Id = "common_shard", Name = "Glass Shard", Tier = "Common" },
	-- Rare
	{ Id = "rare_ember", Name = "Ember Core", Tier = "Rare" },
	{ Id = "rare_frost", Name = "Frost Crystal", Tier = "Rare" },
	{ Id = "rare_volt", Name = "Volt Coil", Tier = "Rare" },
	-- Epic
	{ Id = "epic_flare", Name = "Solar Flare", Tier = "Epic" },
	{ Id = "epic_prism", Name = "Void Prism", Tier = "Epic" },
	{ Id = "epic_plasma", Name = "Plasma Orb", Tier = "Epic" },
	-- Legendary
	{ Id = "legendary_core", Name = "Star Core", Tier = "Legendary" },
	{ Id = "legendary_nova", Name = "Nova Heart", Tier = "Legendary" },
	{ Id = "legendary_crown", Name = "Quantum Crown", Tier = "Legendary" },
	-- Mythic
	{ Id = "mythic_singularity", Name = "Singularity", Tier = "Mythic" },
	{ Id = "mythic_rift", Name = "Rift Engine", Tier = "Mythic" },
	{ Id = "mythic_genesis", Name = "Genesis Stone", Tier = "Mythic" },
	-- Secret (gacha 0.002%, or fuse 2 Mythics at 8% after Rebirth 1)
	{ Id = "secret_horizon", Name = "Event Horizon", Tier = "Secret" },
	{ Id = "secret_prism", Name = "Eternity Prism", Tier = "Secret" },
} :: { ItemDef }

function ItemConfig.GetItemById(id: string): ItemDef?
	for _, item in ItemConfig.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function ItemConfig.GetItemsByTier(tier: string): { ItemDef }
	local results = {}
	for _, item in ItemConfig.Items do
		if item.Tier == tier then
			table.insert(results, item)
		end
	end
	return results
end

-- A random item of `tier`, or nil if the tier has no items.
function ItemConfig.PickRandomOfTier(tier: string, rng: Random?): ItemDef?
	local itemsOfTier = ItemConfig.GetItemsByTier(tier)
	if #itemsOfTier == 0 then
		return nil
	end
	local index = if rng then rng:NextInteger(1, #itemsOfTier) else math.random(1, #itemsOfTier)
	return itemsOfTier[index]
end

return ItemConfig
