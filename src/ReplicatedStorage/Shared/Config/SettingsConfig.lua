--!strict
--[[
	SettingsConfig
	--------------
	Player settings (PlayerData.Settings, saved; sent as Settings in the
	snapshot; changed with SetSetting { Key, Tier?, Value }). Sections:
	which pulls and fusions get the big reveal card, and the sound-effects
	volume.

	SfxVolume 0..1 (default 0.8; the server clamps it) and SfxMuted: every
	SoundKit slot plays at its Volume x SfxVolume (0 when muted), through
	the client's SFX SoundGroup.

	RevealRule = { [tier] = "Never" | "Golden" | "Diamond" | "Rainbow" |
	"Always" } for Common → Mythic. "Golden" means Golden or any mutation
	ranked above it (MutationConfig.GetRank), likewise Diamond / Rainbow.
	Secret and the event-only mutations (Charged / Void / Celestial) always
	get their card; the player can't turn those off.

	The defaults reproduce FusionConfig.IsMajorReveal and are derived from
	it: a tier in MajorRevealTiers is "Always", any other tier gets the
	lowest threshold that covers MajorRevealMutationRank.
]]
local FusionConfig = require(script.Parent.FusionConfig)
local MutationConfig = require(script.Parent.MutationConfig)

local SettingsConfig = {}

export type RevealRule = { [string]: string }
-- GoalPath: the lit path to the current goal (the goal card's 👣):
-- "Auto" = on for the first TutorialConfig.GoalPathSessions sessions.
export type GoalPath = "Auto" | "On" | "Off"
export type Settings = { RevealRule: RevealRule, SfxVolume: number, SfxMuted: boolean, AutoFuse: boolean, GoalPath: GoalPath }

function SettingsConfig.IsGoalPathValue(value: unknown): boolean
	return value == "Auto" or value == "On" or value == "Off"
end

SettingsConfig.DefaultSfxVolume = 0.8

-- A volume from untrusted data: a finite number clamped to 0..1, else the
-- default.
function SettingsConfig.SanitizeSfxVolume(raw: unknown): number
	if typeof(raw) ~= "number" or raw ~= raw or raw == math.huge or raw == -math.huge then
		return SettingsConfig.DefaultSfxVolume
	end
	return math.clamp(raw, 0, 1)
end

-- A complete, valid Settings table from untrusted data (an old save, a
-- snapshot).
function SettingsConfig.Sanitize(raw: unknown): Settings
	local source = if typeof(raw) == "table" then raw :: any else {}
	return {
		RevealRule = SettingsConfig.SanitizeRevealRule(source.RevealRule),
		SfxVolume = SettingsConfig.SanitizeSfxVolume(source.SfxVolume),
		SfxMuted = source.SfxMuted == true,
		-- The Auto-Fuse pass's toggle (Fuse panel); off until switched on.
		AutoFuse = source.AutoFuse == true,
		GoalPath = if SettingsConfig.IsGoalPathValue(source.GoalPath) then source.GoalPath else "Auto",
	}
end

-- What SoundKit plays at: 0 when muted, else the volume.
function SettingsConfig.GetEffectiveSfxVolume(settings: Settings): number
	return if settings.SfxMuted then 0 else settings.SfxVolume
end

-- Segmented-control order, and the label each value shows.
SettingsConfig.RevealValues = { "Never", "Golden", "Diamond", "Rainbow", "Always" }
SettingsConfig.RevealLabels = {
	Never = "Never",
	Golden = "Golden+",
	Diamond = "Diamond+",
	Rainbow = "Rainbow+",
	Always = "Always",
} :: { [string]: string }

-- The tiers a player can set (every tier but Secret, which always shows).
SettingsConfig.AlwaysTier = "Secret"
SettingsConfig.RevealTiers = {} :: { string }
for _, tier in FusionConfig.TierOrder do
	if tier ~= SettingsConfig.AlwaysTier then
		table.insert(SettingsConfig.RevealTiers, tier)
	end
end

local validValue: { [string]: boolean } = {}
for _, value in SettingsConfig.RevealValues do
	validValue[value] = true
end
local validTier: { [string]: boolean } = {}
for _, tier in SettingsConfig.RevealTiers do
	validTier[tier] = true
end

function SettingsConfig.IsRevealTier(tier: unknown): boolean
	return typeof(tier) == "string" and validTier[tier] == true
end

function SettingsConfig.IsRevealValue(value: unknown): boolean
	return typeof(value) == "string" and validValue[value] == true
end

-- Today's IsMajorReveal as a rule value for `tier`.
local function defaultFor(tier: string): string
	if FusionConfig.MajorRevealTiers[tier] then
		return "Always"
	end
	-- The lowest threshold whose rank reaches MajorRevealMutationRank.
	for _, value in SettingsConfig.RevealValues do
		local rank = MutationConfig.GetRank(value)
		if rank > 0 and rank >= FusionConfig.MajorRevealMutationRank then
			return value
		end
	end
	return "Never"
end

function SettingsConfig.GetDefaultRevealRule(): RevealRule
	local rule: RevealRule = {}
	for _, tier in SettingsConfig.RevealTiers do
		rule[tier] = defaultFor(tier)
	end
	return rule
end

-- A complete, valid rule from untrusted data (an old save, a snapshot):
-- every settable tier, unknown values replaced by the default.
function SettingsConfig.SanitizeRevealRule(raw: unknown): RevealRule
	local rule = SettingsConfig.GetDefaultRevealRule()
	if typeof(raw) == "table" then
		for _, tier in SettingsConfig.RevealTiers do
			local value = (raw :: any)[tier]
			if SettingsConfig.IsRevealValue(value) then
				rule[tier] = value
			end
		end
	end
	return rule
end

function SettingsConfig.GetDefaultSettings(): Settings
	return {
		RevealRule = SettingsConfig.GetDefaultRevealRule(),
		SfxVolume = SettingsConfig.DefaultSfxVolume,
		SfxMuted = false,
		AutoFuse = false,
		GoalPath = "Auto",
	}
end

-- Does a `tier` item with `mutation` get the big card under `rule`?
function SettingsConfig.ShowsBigCard(tier: string, mutation: string?, rule: RevealRule?): boolean
	if tier == SettingsConfig.AlwaysTier or MutationConfig.IsEventOnly(mutation) then
		return true
	end
	local value = (rule and rule[tier]) or defaultFor(tier)
	if value == "Always" then
		return true
	elseif value == "Never" then
		return false
	end
	local rank = MutationConfig.GetRank(mutation)
	return rank > 0 and rank >= MutationConfig.GetRank(value)
end

return SettingsConfig
