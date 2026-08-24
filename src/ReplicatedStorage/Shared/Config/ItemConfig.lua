local ItemConfig = {}

ItemConfig.Tiers = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
}

ItemConfig.Items = {
	{
		Id = "common_spark",
		Name = "Common Spark",
		Tier = "Common",
		BaseValue = 10,
		CashPerSecond = 1,
	},
	{
		Id = "rare_ember",
		Name = "Rare Ember",
		Tier = "Rare",
		BaseValue = 50,
		CashPerSecond = 5,
	},
	{
		Id = "epic_flare",
		Name = "Epic Flare",
		Tier = "Epic",
		BaseValue = 250,
		CashPerSecond = 25,
	},
	{
		Id = "legendary_core",
		Name = "Legendary Core",
		Tier = "Legendary",
		BaseValue = 1000,
		CashPerSecond = 100,
	},
	{
		Id = "mythic_singularity",
		Name = "Mythic Singularity",
		Tier = "Mythic",
		BaseValue = 5000,
		CashPerSecond = 500,
	},
}

function ItemConfig.GetItemById(id: string)
	for _, item in ItemConfig.Items do
		if item.Id == id then
			return item
		end
	end
	return nil
end

function ItemConfig.GetItemsByTier(tier: string)
	local results = {}
	for _, item in ItemConfig.Items do
		if item.Tier == tier then
			table.insert(results, item)
		end
	end
	return results
end

return ItemConfig
