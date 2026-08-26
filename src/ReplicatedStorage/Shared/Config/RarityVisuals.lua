-- Data-driven mapping from item tier to Pedestal Showcase visuals. This is
-- the ONLY place tier-appearance tuning should happen: PedestalVisuals.lua
-- just reads whatever fields are present here and builds the corresponding
-- elements, so a future tier (or a redesign of an existing one) only ever
-- needs a new/edited entry below, never a change to placement or building
-- logic.
local RarityVisuals = {}

export type ParticlePreset = {
	Rate: number,
	Speed: NumberRange?,
	SpreadAngle: Vector2?,
}

export type TierVisual = {
	GlowColor: Color3,
	LightBrightness: number,
	LightRange: number,
	Particles: ParticlePreset?, -- nil = no ambient particles
	RotatingRing: boolean, -- rotating light ring around the pedestal's base
	Pulse: boolean, -- soft rumble/pulse animation on the pedestal itself
	Beam: boolean, -- animated beam of light from the pedestal into the sky
	AmbientSoundId: string?, -- nil = no looping ambient sound
	ProximityBurst: boolean, -- particle burst when a player walks near
	AnnounceServerWide: boolean, -- fires RareFusionAnnouncement on display
}

RarityVisuals.Tiers = {
	Common = {
		GlowColor = Color3.fromRGB(225, 225, 225),
		LightBrightness = 1.5,
		LightRange = 8,
		Particles = nil,
		RotatingRing = false,
		Pulse = false,
		Beam = false,
		AmbientSoundId = nil,
		ProximityBurst = false,
		AnnounceServerWide = false,
	},
	Rare = {
		GlowColor = Color3.fromRGB(60, 160, 255),
		LightBrightness = 3,
		LightRange = 12,
		Particles = { Rate = 3, Speed = NumberRange.new(0.2, 0.6), SpreadAngle = Vector2.new(20, 20) },
		RotatingRing = false,
		Pulse = false,
		Beam = false,
		AmbientSoundId = nil,
		ProximityBurst = false,
		AnnounceServerWide = false,
	},
	Epic = {
		GlowColor = Color3.fromRGB(190, 60, 255),
		LightBrightness = 5,
		LightRange = 16,
		Particles = { Rate = 6, Speed = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(45, 45) },
		RotatingRing = true,
		Pulse = false,
		Beam = false,
		AmbientSoundId = nil,
		ProximityBurst = false,
		AnnounceServerWide = false,
	},
	Legendary = {
		GlowColor = Color3.fromRGB(255, 190, 40),
		LightBrightness = 8,
		LightRange = 22,
		Particles = { Rate = 12, Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(90, 90) },
		RotatingRing = true,
		Pulse = true,
		Beam = false,
		AmbientSoundId = nil,
		ProximityBurst = false,
		AnnounceServerWide = true,
	},
	Mythic = {
		GlowColor = Color3.fromRGB(255, 60, 90),
		LightBrightness = 12,
		LightRange = 32,
		Particles = { Rate = 20, Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180) },
		RotatingRing = true,
		Pulse = true,
		Beam = true,
		-- Placeholder built-in engine sound; swap for an uploaded asset id
		-- when one's available.
		AmbientSoundId = "rbxasset://sounds/bell.wav",
		ProximityBurst = true,
		AnnounceServerWide = true,
	},
} :: { [string]: TierVisual }

return RarityVisuals
