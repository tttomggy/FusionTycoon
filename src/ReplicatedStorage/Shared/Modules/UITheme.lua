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
	Goal = hex("#FFBE28"), -- goal tracker label and bar

	-- One-off accents the design calls for by exact value.
	CoinText = hex("#0B3D1E"), -- "$" on the green HUD coin
	GoldText = hex("#3B2300"), -- text on the gold Gacha pill
	GoldLabel = hex("#FFD566"), -- "PULLED", GACHA title
	VioletLight = hex("#C9A9FF"), -- "purple pad", MULTIPLIER title, odds title
	VioletPill = hex("#6A3FE0"), -- multiplier pill fill
	PlotSignDetail = hex("#EDE3FF"), -- plot sign second line
	InventoryTop = hex("#1F3C78"), -- Inventory header gradient top (Blue tint)
	CardBottom = hex("#2A2140"), -- Inventory card gradient bottom
	ResultMid = hex("#2A1550"), -- big result card gradient mid
	FuseAllTop = hex("#3A1F6E"), -- Fuse All summary card gradient top
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
	AccentGreen = hex("#3BEB7E"), -- claim
	AccentGold = hex("#FFBE28"), -- gacha, collector
	Unclaimed = hex("#3A3560"), -- wall strip before claiming
	AccentBlue = hex("#4FB3FF"), -- west belt rail + chevrons
	Belt = hex("#1B1834"), -- speed belt surface
	CapsuleWhite = hex("#F4F1FF"), -- bottom half of the gacha capsule hologram
	AccentRebirth = hex("#FF8A3D"), -- Rebirth Portal ring, edge strips, light
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
	Disabled = { Top = hex("#3A3560"), Bottom = hex("#3A3560") }, -- locked/maxed/unaffordable
} :: { [string]: GradientPair }

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
} :: { [string]: Color3 }

export type OrbStops = { Light: Color3, Mid: Color3, Dark: Color3 }

UITheme.TierOrb = {
	Common = { Light = hex("#FFFFFF"), Mid = hex("#C8C8C8"), Dark = hex("#5A5A5A") },
	Rare = { Light = hex("#CFE8FF"), Mid = hex("#3CA0FF"), Dark = hex("#12407A") },
	Epic = { Light = hex("#F0C8FF"), Mid = hex("#BE3CFF"), Dark = hex("#5A1080") },
	Legendary = { Light = hex("#FFF2C2"), Mid = hex("#FFBE28"), Dark = hex("#8A5A00") },
	Mythic = { Light = hex("#FFD6DD"), Mid = hex("#FF3C5A"), Dark = hex("#7A0A1E") },
} :: { [string]: OrbStops }

-- Tiers that get the soft glow ring behind their orb.
UITheme.GlowTiers = {
	Epic = true,
	Legendary = true,
	Mythic = true,
} :: { [string]: boolean }

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
	Close = "",
	Lock = "",
	Sunburst = "",
}

return UITheme
