--!strict
--[[
	ShopConfig
	----------
	Every gamepass and developer product, and every number the shop uses.
	MonetizationService (server) is the only thing that grants; the shop UI
	only shows and asks.

	The rules (CLAUDE.md "Monetization"):
	  * Prices are NEVER typed into the UI. `Price` here is the planned price
	    for docs/SHOP_SETUP.md only; every price shown comes from
	    MarketplaceService:GetProductInfo (ShopPrices, cached 10 min), and
	    every "SAVE %" is computed from those live prices.
	  * An item with Id = 0 is not set up yet: hidden in live games. In
	    Studio it still shows (price "set Id", a test grant on tap).
	  * PolicyRestricted items add cash or luck (or change a random roll):
	    hidden and refused for players whose PolicyService info says
	    ArePaidRandomItemsRestricted (or when that call fails).
	  * A sale is a separate, cheaper product sold only inside a real window
	    (ShopConfig.Sales), never a fake discount.
	  * Nothing sold protects a lab from theft or helps a thief, and nothing
	    raises an item's steal value.

	Harris: create each item in Creator Hub (docs/SHOP_SETUP.md lists the
	exact name, price, description and type) and paste its Id below.
]]
local ShopConfig = {}

export type Kind = "Pass" | "Product"

export type Item = {
	Key: string,
	Kind: Kind,
	Id: number, -- 0 = not set up yet
	Price: number, -- PLANNED Robux price, for SHOP_SETUP.md only (never shown)
	Name: string,
	Description: string, -- the Creator Hub description
	Effect: string, -- the one-line effect on the shop tile
	Icon: string, -- the emoji fallback (the live icon is the store page's)
	PolicyRestricted: boolean, -- adds cash or luck: hidden for restricted players
	OneTime: boolean?, -- a product you can buy once (Starter Pack)
	SaleOf: string?, -- this product is the sale version of that key
	Parts: { string }?, -- a bundle: what's inside (for "Worth N R$" / "SAVE %")
	Deal: boolean?, -- a rotating deal (DealConfig): sold only in its 6-hour slot
	AddedUtcDay: number?, -- RewardConfig.GetUtcDay when it went on sale: "NEW!" for 7 days
}

local function pass(item: { [string]: any }): Item
	item.Kind = "Pass"
	return item :: any
end

local function product(item: { [string]: any }): Item
	item.Kind = "Product"
	return item :: any
end

ShopConfig.Items = {
	--[[ Gamepasses (permanent) ]]
	DoubleCash = pass({
		Key = "DoubleCash",
		Id = 0,
		Price = 199,
		Name = "2x Cash",
		Description = "Double all the cash your lab earns, forever.",
		Effect = "×2 all income, forever",
		Icon = "💵",
		PolicyRestricted = false,
	}),
	ExtraPedestals = pass({
		Key = "ExtraPedestals",
		Id = 0,
		Price = 399,
		Name = "+2 Pedestals",
		Description = "Two more pedestals in your lab: display 6 items instead of 4.",
		Effect = "6 pedestals instead of 4",
		Icon = "🏛",
		PolicyRestricted = false,
	}),
	VIP = pass({
		Key = "VIP",
		Id = 0,
		Price = 349,
		Name = "VIP",
		Description = "+25% income, a gold VIP tag over your head and in chat, and a gold trim on your lab.",
		Effect = "+25% income · gold VIP tag · gold lab trim",
		Icon = "👑",
		PolicyRestricted = false,
	}),
	AutoFuse = pass({
		Key = "AutoFuse",
		Id = 0,
		Price = 149,
		Name = "Auto-Fuse",
		Description = "A toggle in the Fuse panel: automatically Fuse All (pairs, Common to Epic, never mutated items) whenever new items arrive.",
		Effect = "Fuse All by itself when items arrive",
		Icon = "🔁",
		PolicyRestricted = false,
	}),
	LabStyle = pass({
		Key = "LabStyle",
		Id = 0,
		Price = 99,
		Name = "Neon Pink Lab",
		Description = "A Neon Pink theme for your lab's lights, with pink cash balls. Looks only, no power.",
		Effect = "Neon Pink lab + pink cash balls (looks only)",
		Icon = "🎨",
		PolicyRestricted = false,
	}),
	Lucky = pass({
		Key = "Lucky",
		Id = 0,
		Price = 299,
		Name = "Lucky",
		Description = "x1.5 luck forever (stacks with rebirth luck). Every odds display shows it.",
		Effect = "×1.5 luck, forever",
		Icon = "🍀",
		PolicyRestricted = true,
	}),

	--[[ Developer products (repeatable) ]]
	QuickBoost = product({
		Key = "QuickBoost",
		Id = 0,
		Price = 29,
		Name = "Quick Boost",
		Description = "x2 income for 15 minutes. Stacks by adding time (up to 3 hours banked).",
		Effect = "×2 income · 15 min",
		Icon = "⚡",
		PolicyRestricted = true,
	}),
	Boost = product({
		Key = "Boost",
		Id = 0,
		Price = 79,
		Name = "Boost",
		Description = "x2 income for 1 hour. Stacks by adding time (up to 3 hours banked).",
		Effect = "×2 income · 1 hour",
		Icon = "⚡",
		PolicyRestricted = true,
	}),
	BoostSale = product({
		Key = "BoostSale",
		Id = 0,
		Price = 49,
		Name = "Boost (Admin Abuse sale)",
		Description = "x2 income for 1 hour, at the Admin Abuse sale price. Only sold during Admin Abuse.",
		Effect = "×2 income · 1 hour",
		Icon = "⚡",
		PolicyRestricted = true,
		SaleOf = "Boost",
	}),
	PocketCash = product({
		Key = "PocketCash",
		Id = 0,
		Price = 49,
		Name = "Pocket Cash",
		Description = "Cash worth 20 minutes of your lab's income (at least $5,000).",
		Effect = "20 min of your income",
		Icon = "💰",
		PolicyRestricted = true,
	}),
	CashCrate = product({
		Key = "CashCrate",
		Id = 0,
		Price = 199,
		Name = "Cash Crate",
		Description = "Cash worth 2 hours of your lab's income (at least $50,000).",
		Effect = "2 h of your income",
		Icon = "💰",
		PolicyRestricted = true,
	}),
	CashVault = product({
		Key = "CashVault",
		Id = 0,
		Price = 599,
		Name = "Cash Vault",
		Description = "Cash worth 8 hours of your lab's income (at least $250,000).",
		Effect = "8 h of your income",
		Icon = "🏦",
		PolicyRestricted = true,
	}),
	Overclock = product({
		Key = "Overclock",
		Id = 0,
		Price = 149,
		Name = "Server Overclock",
		Description = "Everyone in the server gets x2 income for 15 minutes. More buys add time, up to 60 minutes.",
		Effect = "×2 income for EVERYONE here · 15 min",
		Icon = "🌐",
		PolicyRestricted = true,
	}),
	LuckPotion = product({
		Key = "LuckPotion",
		Id = 0,
		Price = 49,
		Name = "Luck Potion",
		Description = "x2 luck for 15 minutes. Stacks by adding time (up to 3 hours banked).",
		Effect = "×2 luck · 15 min",
		Icon = "🧪",
		PolicyRestricted = true,
	}),
	SafeFusion1 = product({
		Key = "SafeFusion1",
		Id = 0,
		Price = 25,
		Name = "Safe Fusion",
		Description = "One Safe Fusion token: arm it in the Fuse panel, and if that fusion fails you keep every orb.",
		Effect = "1 token · a failed fusion keeps every orb",
		Icon = "🛡",
		PolicyRestricted = true,
	}),
	SafeFusion5 = product({
		Key = "SafeFusion5",
		Id = 0,
		Price = 99,
		Name = "Safe Fusion x5",
		Description = "Five Safe Fusion tokens: arm one in the Fuse panel, and if that fusion fails you keep every orb.",
		Effect = "5 tokens · a failed fusion keeps every orb",
		Icon = "🛡",
		PolicyRestricted = true,
		Parts = { "SafeFusion1", "SafeFusion1", "SafeFusion1", "SafeFusion1", "SafeFusion1" },
	}),
	StarterPack = product({
		Key = "StarterPack",
		Id = 0,
		Price = 99,
		Name = "Starter Pack",
		Description = "One time only: the Neon Pink Lab look, a 1 hour x2 Boost and Pocket Cash.",
		Effect = "Neon Pink Lab + 1 h Boost + Pocket Cash",
		Icon = "🎁",
		PolicyRestricted = true,
		OneTime = true,
		Parts = { "LabStyle", "Boost", "PocketCash" },
	}),
	--[[ Rotating deals (DealConfig): bundles below their parts' price ]]
	DealPowerHour = product({
		Key = "DealPowerHour",
		Id = 0,
		Price = 99,
		Name = "Power Hour Deal",
		Description = "A x2 income Boost for 1 hour plus a x2 Luck Potion for 15 minutes, for less than buying both.",
		Effect = "Boost 1 h + Luck Potion 15 min",
		Icon = "⚡",
		PolicyRestricted = true,
		Deal = true,
		Parts = { "Boost", "LuckPotion" },
	}),
	DealFusionKit = product({
		Key = "DealFusionKit",
		Id = 0,
		Price = 79,
		Name = "Fusion Kit Deal",
		Description = "Three Safe Fusion tokens plus a x2 Luck Potion for 15 minutes, for less than buying them one by one.",
		Effect = "3 Safe Fusion + Luck Potion 15 min",
		Icon = "🛡",
		PolicyRestricted = true,
		Deal = true,
		Parts = { "SafeFusion1", "SafeFusion1", "SafeFusion1", "LuckPotion" },
	}),
	DealRichLab = product({
		Key = "DealRichLab",
		Id = 0,
		Price = 179,
		Name = "Rich Lab Deal",
		Description = "A Cash Crate (2 hours of your lab's income) plus a 15 minute x2 Quick Boost, for less than buying both.",
		Effect = "Cash Crate + Quick Boost 15 min",
		Icon = "💰",
		PolicyRestricted = true,
		Deal = true,
		Parts = { "CashCrate", "QuickBoost" },
	}),
	OfflineDouble = product({
		Key = "OfflineDouble",
		Id = 0,
		Price = 25,
		Name = "Double Offline Cash",
		Description = "Doubles the cash your lab earned while you were away (the welcome-back card's COLLECT x2).",
		Effect = "×2 your welcome-back cash",
		Icon = "🌙",
		PolicyRestricted = true,
	}),
} :: { [string]: Item }

-- Every key the shop knows (HasAnyOffer walks it).
ShopConfig.Order = {
	"DealPowerHour",
	"DealFusionKit",
	"DealRichLab",
	"StarterPack",
	"BoostSale",
	"QuickBoost",
	"Boost",
	"Overclock",
	"PocketCash",
	"CashCrate",
	"CashVault",
	"OfflineDouble",
	"DoubleCash",
	"VIP",
	"ExtraPedestals",
	"AutoFuse",
	"LabStyle",
	"Lucky",
	"LuckPotion",
	"SafeFusion1",
	"SafeFusion5",
}

--[[ The one scrolling shop (UI/ShopPanel): sections in order, each with a
	header row and its chip in the sticky chip bar. Featured is one banner
	(Starter Pack until bought, then a live sale, then the best value); the
	rest list their keys in order. A sale product (BoostSale) takes its
	normal key's place while its window is live. OfflineDouble lives only on
	the welcome-back card; StarterPack only in the banner. ]]
export type Section = { Id: string, Icon: string, Title: string, Chip: string, Gradient: string, Keys: { string } }
ShopConfig.Sections = {
	-- The current rotating deal (DealConfig), one banner; keys from DealState.
	{ Id = "Deal", Icon = "🔥", Title = "Deal", Chip = "🔥 Deal", Gradient = "Pink", Keys = {} },
	{ Id = "Featured", Icon = "⭐", Title = "Featured", Chip = "⭐ Featured", Gradient = "ShopFeatured", Keys = {} },
	{
		Id = "Passes",
		Icon = "🎟",
		Title = "Passes",
		Chip = "🎟 Passes",
		Gradient = "Blue",
		Keys = { "DoubleCash", "VIP", "ExtraPedestals", "AutoFuse", "LabStyle", "Lucky" },
	},
	{ Id = "Boosts", Icon = "⚡", Title = "Boosts", Chip = "⚡ Boosts", Gradient = "Violet", Keys = { "QuickBoost", "Boost", "Overclock" } },
	{ Id = "Cash", Icon = "💰", Title = "Cash", Chip = "💰 Cash", Gradient = "Green", Keys = { "PocketCash", "CashCrate", "CashVault" } },
	{ Id = "Luck", Icon = "🍀", Title = "Luck", Chip = "🍀 Luck", Gradient = "Teal", Keys = { "LuckPotion" } },
	{ Id = "Safe", Icon = "🛡", Title = "Safe Fusion", Chip = "🛡 Safe", Gradient = "Shield", Keys = { "SafeFusion1", "SafeFusion5" } },
} :: { Section }

-- The cash pack giving the most $ per Robux right now: `amountOf(key)` is
-- what it pays this player, `priceOf(key)` its LIVE price. nil unless at
-- least two packs are listed and every one has a live price (no "BEST
-- VALUE" claim without the numbers).
function ShopConfig.GetBestValueKey(keys: { string }, amountOf: (string) -> number, priceOf: (string) -> number?): string?
	if #keys < 2 then
		return nil
	end
	local best: string? = nil
	local bestRatio = -math.huge
	for _, key in keys do
		local price = priceOf(key)
		if not price or price <= 0 then
			return nil
		end
		local ratio = amountOf(key) / price
		if ratio > bestRatio then
			best, bestRatio = key, ratio
		end
	end
	return best
end

--[[ Effects ------------------------------------------------------------------ ]]

ShopConfig.DoubleCashMultiplier = 2
ShopConfig.VipMultiplier = 1.25
ShopConfig.LuckyMultiplier = 1.5

-- Timed boosts (saved as REMAINING seconds: they pause while you're offline
-- and tick only while you're in game).
ShopConfig.BoostMultiplier = 2
ShopConfig.BoostSeconds = {
	QuickBoost = 15 * 60,
	Boost = 60 * 60,
	BoostSale = 60 * 60,
	StarterPack = 60 * 60,
} :: { [string]: number }
ShopConfig.MaxBoostBankSeconds = 3 * 60 * 60

ShopConfig.LuckPotionMultiplier = 2
ShopConfig.LuckPotionSeconds = 15 * 60
ShopConfig.MaxLuckBankSeconds = 3 * 60 * 60

-- Server Overclock: session-only, on the server (workspace attributes
-- OverclockUntil / OverclockBy, read through ShopState).
ShopConfig.OverclockMultiplier = 2
ShopConfig.OverclockSeconds = 15 * 60
ShopConfig.MaxOverclockSeconds = 60 * 60

-- Cash packs: minutes of your BASE passive income (no timed boosts), with
-- a floor.
ShopConfig.CashPacks = {
	PocketCash = { Minutes = 20, Floor = 5000 },
	CashCrate = { Minutes = 120, Floor = 50000 },
	CashVault = { Minutes = 480, Floor = 250000 },
} :: { [string]: { Minutes: number, Floor: number } }
-- Smallest first: the contextual offer picks the first that covers a gap.
ShopConfig.CashPackOrder = { "PocketCash", "CashCrate", "CashVault" }

ShopConfig.SafeFusionTokens = { SafeFusion1 = 1, SafeFusion5 = 5 } :: { [string]: number }

ShopConfig.BasePedestals = 4
ShopConfig.ExtraPedestals = 6

--[[ Plumbing ----------------------------------------------------------------- ]]

ShopConfig.PriceCacheSeconds = 10 * 60
ShopConfig.MaxReceipts = 200

--[[ Contextual offer + Starter Pack (client-side, ShopController) ------------- ]]

ShopConfig.OfferCooldownSeconds = 5 * 60
ShopConfig.FirstSessionQuietSeconds = 10 * 60
ShopConfig.AfterLossQuietSeconds = 60
ShopConfig.StarterOfferSession = 2
ShopConfig.StarterOfferDelaySeconds = 3 * 60

--[[ Real sales ------------------------------------------------------------------
	A sale is a separate developer product at a lower price, sellable ONLY
	while its window is live. "AdminAbuse": EventState.GetAdminAbuseWindowEnd
	(an admin's event or luck from the panel, or the scheduled Admin Abuse
	hour). The server refuses a sale product outside its window, and no sale
	is ever shown outside one.
]]
export type Sale = { Key: string, SaleKey: string, Window: string }
ShopConfig.Sales = {
	{ Key = "Boost", SaleKey = "BoostSale", Window = "AdminAbuse" },
} :: { Sale }

--[[ Helpers ------------------------------------------------------------------ ]]

function ShopConfig.GetItem(key: string): Item?
	return ShopConfig.Items[key]
end

-- The item with this pass / product id (0 never matches).
function ShopConfig.GetItemById(kind: Kind, id: number): Item?
	if id == 0 then
		return nil
	end
	for _, item in ShopConfig.Items do
		if item.Kind == kind and item.Id == id then
			return item
		end
	end
	return nil
end

function ShopConfig.IsPolicyRestricted(key: string): boolean
	local item = ShopConfig.Items[key]
	return item == nil or item.PolicyRestricted
end

-- The sale entry whose SaleKey is `key` (it's a sale product), if any.
function ShopConfig.GetSaleBySaleKey(key: string): Sale?
	for _, sale in ShopConfig.Sales do
		if sale.SaleKey == key then
			return sale
		end
	end
	return nil
end

-- The sale entry for a normal product `key`, if any.
function ShopConfig.GetSaleFor(key: string): Sale?
	for _, sale in ShopConfig.Sales do
		if sale.Key == key then
			return sale
		end
	end
	return nil
end

-- Is `key` offered to this viewer at all? (Set up, or Studio; allowed by
-- their policy; not a bought one-time pack. A sale product also needs its
-- window live: ShopState.IsSaleLive.) Server and client both ask this.
function ShopConfig.IsOffered(key: string, restricted: boolean, isStudio: boolean, starterBought: boolean): boolean
	local item = ShopConfig.Items[key]
	if not item then
		return false
	end
	if item.Id == 0 and not isStudio then
		return false
	end
	if item.PolicyRestricted and restricted then
		return false
	end
	if key == "StarterPack" and starterBought then
		return false
	end
	return true
end

-- Permanent income multiplier from passes: 2x Cash x VIP.
function ShopConfig.GetPassIncomeMultiplier(owned: { [string]: boolean }): number
	return (if owned.DoubleCash then ShopConfig.DoubleCashMultiplier else 1)
		* (if owned.VIP then ShopConfig.VipMultiplier else 1)
end

-- Luck from the shop: the Lucky pass x an active Luck Potion.
function ShopConfig.GetLuckMultiplier(owned: { [string]: boolean }, luckSeconds: number): number
	return (if owned.Lucky then ShopConfig.LuckyMultiplier else 1)
		* (if luckSeconds > 0 then ShopConfig.LuckPotionMultiplier else 1)
end

function ShopConfig.GetPedestalCount(owned: { [string]: boolean }): number
	return if owned.ExtraPedestals then ShopConfig.ExtraPedestals else ShopConfig.BasePedestals
end

-- What a cash pack pays right now, from your BASE income per second.
function ShopConfig.GetCashPackAmount(key: string, baseIncomePerSecond: number): number
	local pack = ShopConfig.CashPacks[key]
	if not pack then
		return 0
	end
	return math.max(pack.Floor, math.floor(baseIncomePerSecond * pack.Minutes * 60))
end

-- The smallest cash pack (that `isAvailable`) covering `gap`, or nil.
function ShopConfig.GetSmallestPackCovering(gap: number, baseIncomePerSecond: number, isAvailable: (string) -> boolean): string?
	for _, key in ShopConfig.CashPackOrder do
		if isAvailable(key) and ShopConfig.GetCashPackAmount(key, baseIncomePerSecond) >= gap then
			return key
		end
	end
	return nil
end

-- Adds `seconds` to a banked timer, capped.
function ShopConfig.AddBanked(current: number, seconds: number, cap: number): number
	return math.min(cap, math.max(0, current) + seconds)
end

-- "SAVE 56%" from live prices: the bundle's price vs. its parts bought one
-- by one. nil when any price is unknown or there's no saving.
function ShopConfig.GetSavePercent(price: number?, partsTotal: number?): number?
	if not price or not partsTotal or partsTotal <= 0 or price >= partsTotal then
		return nil
	end
	return math.floor((1 - price / partsTotal) * 100 + 0.5)
end

return ShopConfig
