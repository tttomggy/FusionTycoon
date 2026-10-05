--!strict
--[[
	UITheme
	-------
	"Fusion Lab" design tokens. Every colour, gradient and font used by the
	game's UI (ScreenGuis on the client, BillboardGuis on the server) comes
	from here. No other UI file may hard-code a colour - add a token instead.

	Lives in Shared so the server-built world labels (pads, pedestals, the
	plot sign, the Fusion odds board) read the same tokens as the HUD.
]]
local UITheme = {}

local hex = Color3.fromHex

--[[ Core tokens ----------------------------------------------------------- ]]

UITheme.Colors = {
	Ink = hex("#0B0A1A"), -- every outline and drop shadow
	Panel = hex("#17142E"), -- panel body
	PanelTop = hex("#2A2552"), -- panel header tint (gradient top)
	Panel2 = hex("#221E42"), -- rows, cards, footers
	Panel3 = hex("#2D2856"), -- locked icon wells, pedestal bases
	Disabled = hex("#3A3560"), -- locked/maxed/unaffordable buttons
	Text = hex("#FFFFFF"),
	Muted = hex("#B3AED6"), -- secondary text
	Faint = hex("#7D77A8"), -- captions, empty states
	Cash = hex("#4CF08A"), -- every money number
	Danger = hex("#FF5470"), -- badges, error toasts
	ShieldTeal = hex("#1FB49A"), -- shield up: HUD chip, PROTECTED sign pill
	ShieldAmber = hex("#FFBE28"), -- shield down: HUD chip
	Goal = hex("#FFBE28"), -- goal tracker label and bar

	-- One-off accents the design calls for by exact value.
	CoinText = hex("#0B3D1E"), -- "$" on the green HUD coin
	GoldLabel = hex("#FFD566"), -- "PULLED", GACHA title
	VioletLight = hex("#C9A9FF"), -- "purple pad", MULTIPLIER title, odds title
	VioletPill = hex("#6A3FE0"), -- multiplier pill fill
	PlotSignDetail = hex("#EDE3FF"), -- plot sign second line
	InventoryTop = hex("#1F3C78"), -- Inventory header gradient top (Blue tint)
	CardBottom = hex("#2A2140"), -- Inventory card gradient bottom
	ResultMid = hex("#2A1550"), -- big result card gradient mid
	FuseAllTop = hex("#3A1F6E"), -- Fuse All summary card gradient top
	WelcomeTop = hex("#1B5A3A"), -- welcome-back (offline earnings) card gradient top
	DailyTop = hex("#6A4A0E"), -- the daily reward card's header (gold)
	GiftsTop = hex("#6E1F5A"), -- the GIFTS panel's header (pink)
	RankGold = hex("#8A6A12"), -- leaderboard row tint: rank 1
	RankSilver = hex("#5E6378"), -- rank 2
	RankBronze = hex("#7A4A26"), -- rank 3
	ShopTop = hex("#4A1F8E"), -- the SHOP panel header (violet)
	ShopGlow = hex("#A47BFF"), -- the SHOP header's radial glow
	Sale = hex("#FF3355"), -- the red SALE tag on the HUD SHOP button
	MythicBannerLeft = hex("#6E0F24"), -- server Mythic banner gradient left
	MythicBannerLabel = hex("#FF8FA0"), -- "SERVER · MYTHIC"
	Rebirth = hex("#FF8A3D"), -- REBIRTH titles, HUD rebirth pill, banner right
	RebirthLabel = hex("#FFD9B8"), -- "SERVER · REBIRTH", rebirth captions
	RebirthBannerLeft = hex("#7A2A00"), -- server rebirth banner gradient left
	White = hex("#FFFFFF"),
	Black = hex("#000000"),
}

-- 3D world colours (parts, not GUIs). Every solid part is SmoothPlastic and
-- every accent Neon; the ground's Grass material is the one exception.
UITheme.World = {
	Grass = hex("#5E9C63"), -- ground
	Street = hex("#34305E"), -- street
	Floor = hex("#3A3668"), -- plot floor
	Walkway = hex("#4A4580"), -- walkway inlay
	Structure = hex("#221E42"), -- walls, pads, pedestal columns, generator bodies, belt-side parts, machine platform
	StructureLight = hex("#2D2856"), -- pylons, posts, locked/unclaimed trim
	AccentViolet = hex("#8B5CFF"), -- wall strips, machine rim, multiplier
	Shield = hex("#FF4FD8"), -- lab shield fence (ForceField) and gate line
	AccentGreen = hex("#3BEB7E"), -- claim
	AccentGold = hex("#FFBE28"), -- gacha, collector
	Unclaimed = hex("#3A3560"), -- wall strip before claiming
	AccentBlue = hex("#4FB3FF"), -- west belt rail + chevrons
	Belt = hex("#1B1834"), -- speed belt surface
	CapsuleWhite = hex("#F4F1FF"), -- bottom half of the gacha capsule hologram
	AccentRebirth = hex("#FF8A3D"), -- Rebirth Portal ring, edge strips, light
	AccentPink = hex("#FF5CC8"), -- the Neon Pink Lab (LabStyle): wall + sign strips, cash balls
	VipGold = hex("#FFD23F"), -- the VIP pass: sign border, wall trims, head tag
	VoidShell = hex("#0B0A1A"), -- the Secret orb's dark glass shell
}

export type GradientPair = { Top: Color3, Bottom: Color3 }

-- Button gradients: UIGradient, Rotation 90, Top -> Bottom.
UITheme.Gradients = {
	Green = { Top = hex("#3BEB7E"), Bottom = hex("#1FB458") }, -- buy, confirm, Upgrades
	Blue = { Top = hex("#4FB3FF"), Bottom = hex("#2378E0") }, -- Items, open
	Violet = { Top = hex("#A47BFF"), Bottom = hex("#6A3FE0") }, -- fusion, multiplier
	Red = { Top = hex("#FF7A8E"), Bottom = hex("#E0304E") }, -- close (X), error toasts
	Gold = { Top = hex("#FFD566"), Bottom = hex("#F0A100") }, -- gacha, goal bar
	Orange = { Top = hex("#FFB066"), Bottom = hex("#F06A1F") }, -- rebirth button, pills, bars
	Teal = { Top = hex("#5CF2D6"), Bottom = hex("#1FB49A") }, -- INDEX button
	Heist = { Top = hex("#FF5470"), Bottom = hex("#6E0F24") }, -- victim banner, heist cards (Danger -> deep red)
	Shield = { Top = hex("#FF8AE6"), Bottom = hex("#E02FBE") }, -- LOCK (ready): the console pill
	Disabled = { Top = hex("#3A3560"), Bottom = hex("#3A3560") }, -- locked/maxed/unaffordable
	ShopFeatured = { Top = hex("#FFB347"), Bottom = hex("#E0306E") }, -- the shop's featured banner (warm)
	Pink = { Top = hex("#FF8AD8"), Bottom = hex("#E02F9E") }, -- the HUD GIFTS button
	-- Events (HUD chip, start banner, Event Board). Rainbow Storm also
	-- runs the full Mutation.RainbowStops where a multi-stop gradient fits.
	GoldRain = { Top = hex("#FFD566"), Bottom = hex("#C98A00") },
	Surge = { Top = hex("#4FB3FF"), Bottom = hex("#1F3C78") },
	Meteor = { Top = hex("#FFB066"), Bottom = hex("#B33A1F") },
	Night = { Top = hex("#3D3A8A"), Bottom = hex("#0B0A1A") },
	VoidMoon = { Top = hex("#A47BFF"), Bottom = hex("#2A1550") },
	Rainbow = { Top = hex("#FF5470"), Bottom = hex("#A47BFF") },
} :: { [string]: GradientPair }

--[[ Contrast rule ----------------------------------------------------------
	On any gold, yellow or orange fill, text is WHITE with the ink stroke
	(the UPGRADES / ITEMS / INDEX look), never dark brown or gold-on-gold.
	UIKit.Button / SetButton / Pill and BillboardKit's pills read IsWarm*
	and pick that by themselves.
]]
UITheme.WarmText = UITheme.Colors.Text
UITheme.WarmTextStroke = 2 -- px of Ink on the glyphs

-- Gold, yellow or orange (hue 7°–65°, saturated, bright).
function UITheme.IsWarm(color: Color3): boolean
	local h, s, v = color:ToHSV()
	return h >= 0.02 and h <= 0.18 and s >= 0.4 and v >= 0.6
end

-- A gradient is warm when either end is (ShopFeatured: orange -> pink).
function UITheme.IsWarmPair(pair: GradientPair?): boolean
	return pair ~= nil and (UITheme.IsWarm(pair.Top) or UITheme.IsWarm(pair.Bottom))
end

-- The text colour for a fill: white on warm, else `default` (or Text).
function UITheme.TextOn(fill: GradientPair | Color3 | nil, default: Color3?): Color3
	if typeof(fill) == "Color3" then
		if UITheme.IsWarm(fill) then
			return UITheme.WarmText
		end
	elseif fill ~= nil and UITheme.IsWarmPair(fill :: GradientPair) then
		return UITheme.WarmText
	end
	return default or UITheme.Colors.Text
end

-- HOW TO HEIST's 3D scenes (UI/HeistScenes, ViewportFrames). Viewports
-- ignore lights, so the look comes from these: tuned to read like the lab
-- at golden hour (LightingService) without its post effects.
UITheme.HeistScene = {
	Background = hex("#2A2552"), -- behind the set (PanelTop: the lab's violet haze)
	Ambient = hex("#9C94C8"),
	LightColor = hex("#FFE9D2"),
	LightDirection = Vector3.new(-0.45, -1, -0.35),
	ThiefBody = hex("#E0304E"), -- the other player's body colours (red)
	HomeGate = hex("#4FB3FF"), -- the "🏠 YOUR LAB" gate (AccentBlue)
	Beam = hex("#FF5470"), -- the carried orb's red beam (Danger)
	GuardRing = hex("#1FB49A"), -- the owner's guard ring (ShieldTeal)
	LockedButton = hex("#1FB49A"), -- the console button once locked
}

-- /trailer actors (TrailerController's local NPC rigs).
UITheme.Trailer = {
	ThiefBody = hex("#E0304E"), -- the masked thief (HeistScene.ThiefBody)
	ThiefMask = hex("#0B0A1A"), -- his head (Ink)
	OwnerHead = hex("#F5CD30"), -- the classic yellow / blue owner
	OwnerArms = hex("#F5CD30"),
	OwnerTorso = hex("#1F6FE0"),
	OwnerLegs = hex("#1B3F8F"),
}

-- Event id -> its gradient key above.
UITheme.EventGradient = {
	GoldenRain = "GoldRain",
	PowerSurge = "Surge",
	MeteorShower = "Meteor",
	Night = "Night",
	VoidMoon = "VoidMoon",
	RainbowStorm = "Rainbow",
} :: { [string]: string }

function UITheme.GetEventGradient(eventId: string?): GradientPair
	local key = eventId and UITheme.EventGradient[eventId]
	return (key and UITheme.Gradients[key]) or UITheme.Gradients.Disabled
end

-- Event weather on the client (EventController): Lighting tints lerped in
-- and restored after, and the world FX colours.
UITheme.EventSky = {
	GoldTint = hex("#FFE3A8"), -- Golden Rain ColorCorrection tint
	StormTint = hex("#A8B8FF"), -- Power Surge tint
	StormHaze = hex("#3A4A80"), -- Power Surge Atmosphere colour
	VoidTint = hex("#D2B8FF"), -- Void Moon tint
	Moon = hex("#A47BFF"), -- the Void Moon disc
	MoonGlow = hex("#E4D6FF"), -- its centre
	Lightning = hex("#D8F4FF"), -- strike beam
	MeteorRock = hex("#3B2A22"), -- falling rock
	MeteorGlow = hex("#FF8A3D"), -- its trail
}

-- The Rebirth Portal's swirl: a UIGradient through these three stops.
UITheme.RebirthPortal = { hex("#FF8A3D"), hex("#FFD566"), hex("#FF4F7A") }

--[[ Tiers ------------------------------------------------------------------
	The saturated tier colours themselves stay FusionConfig.TierAccentColors.
	These are the lighter versions for tier text on dark backgrounds, and the
	three-stop orb gradients (light centre -> tier colour -> dark edge).
]]
UITheme.TierLight = {
	Common = hex("#DADADA"),
	Rare = hex("#6CBBFF"),
	Epic = hex("#D27BFF"),
	Legendary = hex("#FFBE28"),
	Mythic = hex("#FF6C82"),
	Secret = hex("#3DFFD0"),
} :: { [string]: Color3 }

export type OrbStops = { Light: Color3, Mid: Color3, Dark: Color3 }

UITheme.TierOrb = {
	Common = { Light = hex("#FFFFFF"), Mid = hex("#C8C8C8"), Dark = hex("#5A5A5A") },
	Rare = { Light = hex("#CFE8FF"), Mid = hex("#3CA0FF"), Dark = hex("#12407A") },
	Epic = { Light = hex("#F0C8FF"), Mid = hex("#BE3CFF"), Dark = hex("#5A1080") },
	Legendary = { Light = hex("#FFF2C2"), Mid = hex("#FFBE28"), Dark = hex("#8A5A00") },
	Mythic = { Light = hex("#FFD6DD"), Mid = hex("#FF3C5A"), Dark = hex("#7A0A1E") },
	Secret = { Light = hex("#D6FFF5"), Mid = hex("#1FE0B4"), Dark = hex("#06574A") },
} :: { [string]: OrbStops }

-- Tiers that get the soft glow ring behind their orb.
UITheme.GlowTiers = {
	Epic = true,
	Legendary = true,
	Mythic = true,
	Secret = true,
} :: { [string]: boolean }

--[[ Mutations ------------------------------------------------------------- ]]

UITheme.Mutation = {
	Golden = hex("#FFD23F"),
	Charged = hex("#7DF9FF"), -- event: Power Surge lightning
	Diamond = hex("#BFF4FF"),
	Void = hex("#A47BFF"), -- event: Void Moon fusions
	Celestial = hex("#C9F0FF"), -- event: Meteor Shower cores
	RainbowStops = { hex("#FF5470"), hex("#FFBE28"), hex("#4CF08A"), hex("#4FB3FF"), hex("#A47BFF") },
}

-- Index book orb looks (UI/IndexPanel): the tint laid over a found orb
-- where the mutation colour alone is too pale (Void reads deep purple).
UITheme.MutationOrbTint = {
	Void = hex("#3A1A78"),
} :: { [string]: Color3 }

-- A mutation's solid colour (Rainbow's first stop; nil for normal items).
function UITheme.GetMutationColor(mutation: string?): Color3?
	if mutation == "Rainbow" then
		return UITheme.Mutation.RainbowStops[1]
	end
	local color = mutation and (UITheme.Mutation :: any)[mutation]
	return if typeof(color) == "Color3" then color else nil
end

-- The five Rainbow stops as an evenly spaced ColorSequence (UIGradient,
-- particles).
function UITheme.GetRainbowSequence(): ColorSequence
	local stops = UITheme.Mutation.RainbowStops
	local keypoints = {}
	for index, color in stops do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#stops - 1), color))
	end
	return ColorSequence.new(keypoints)
end

function UITheme.GetTierLight(tier: string): Color3
	return UITheme.TierLight[tier] or UITheme.Colors.Text
end

function UITheme.GetTierOrb(tier: string): OrbStops
	return UITheme.TierOrb[tier] or UITheme.TierOrb.Common
end

-- `color` lerped `alpha` of the way toward Ink. Used for the dark tier tints
-- on inventory cards (0.7) and the big result card (0.5).
function UITheme.TowardInk(color: Color3, alpha: number): Color3
	return color:Lerp(UITheme.Colors.Ink, alpha)
end

-- "#RRGGBB" for RichText <font color="..."> tags.
function UITheme.ToHex(color: Color3): string
	return "#" .. color:ToHex()
end

--[[ Type --------------------------------------------------------------------
	Display: titles, every number, button labels.
	Body: labels, details, captions. BodyHeavy: small all-caps labels.
]]
local NUNITO = "rbxasset://fonts/families/Nunito.json"

UITheme.Fonts = {
	Display = Font.fromEnum(Enum.Font.FredokaOne),
	Body = Font.new(NUNITO, Enum.FontWeight.ExtraBold),
	BodyHeavy = Font.new(NUNITO, Enum.FontWeight.Heavy),
}

--[[ Shape ------------------------------------------------------------------ ]]

UITheme.Radius = {
	Button = 14,
	Row = 14,
	Panel = 22,
	Toast = 12,
}

UITheme.Stroke = {
	Default = 3,
	Modal = 4,
	Text = 2,
}

UITheme.ShadowOffset = 5
UITheme.SmallShadowOffset = 4
-- Baseline (px above the screen bottom, before the phone UIScale) for
-- toasts and the bottom result cards. It clears the HUD's bottom button row
-- AND the REBIRTH! button's slot above it (HudController: 22 margin + 5
-- shadow + 64 button + 14 gap + 56 button, +4% pulse), whether or not
-- REBIRTH! is showing, so toasts never jump when it appears.
UITheme.BottomStackOffset = 176
UITheme.MinTapSize = 44

-- Viewport height under which the phone layout + 0.8 UIScale apply.
UITheme.PhoneHeightThreshold = 500
UITheme.PhoneScale = 0.8

--[[ Icons ------------------------------------------------------------------
	Optional image asset ids. "" means "no icon yet": render the label only,
	never a broken image.
]]
UITheme.Icons = {
	Upgrades = "",
	Items = "rbxassetid://18469524765",
	Index = "",
	Close = "",
	Lock = "",
	Sunburst = "",
}

return UITheme
