--!strict
--[[
	TrailerConfig
	-------------
	The /trailer cinematic (TrailerController, client-only; AdminService
	answers /trailer for admins with TrailerStart). Every camera keyframe,
	actor path and beat time lives here, in PLOT-LOCAL space (PlotLayout:
	origin at the floor centre, +Z toward the gate, y = height above the
	floor), so the same shots work from any of the 12 slots.

	Camera keyframe { T, Pos, LookAt, Fov, Easing?, ArcAround?, Follow? }:
	  T         seconds from the shot's start
	  Pos       plot-local position; with Follow, an offset (plot axes) from
	            that actor
	  LookAt    plot-local point, or a target name the shot registers
	            ("Thief", "Owner", "Moon", "Core")
	  Fov       vertical field of view
	  Easing    Enum.EasingStyle name for the move INTO this keyframe
	            (default "Sine", InOut)
	  ArcAround the move into this keyframe swings round this plot-local
	            point (angle + radius + height interpolated) instead of a
	            straight line

	Items (tiers, mutations) are names from FusionConfig / MutationConfig;
	the controller resolves each to the first item of that tier, so the
	trailer always shows the live game's items.
]]
local TrailerConfig = {}

local v3 = Vector3.new

export type Keyframe = {
	T: number,
	Pos: Vector3,
	LookAt: Vector3 | string,
	Fov: number,
	Easing: string?,
	ArcAround: Vector3?,
	Follow: string?,
}

export type Shot = {
	Id: string,
	Duration: number,
	Camera: { Keyframe },
}

export type ItemLook = { Tier: string, Mutation: string? }

TrailerConfig.CountdownSeconds = 3 -- "3 2 1" on black before shot 1
TrailerConfig.FadeSeconds = 0.25 -- each way, between shots
TrailerConfig.BlackHoldSeconds = 0.35 -- black after the countdown, before shot 1
TrailerConfig.StopKey = Enum.KeyCode.F8 -- the chat is hidden, so F8 also stops

-- Shot 1 / 6: what every pedestal shows (index = PlotLayout pedestal).
TrailerConfig.Pedestals = {
	{ Tier = "Mythic", Mutation = "Rainbow" },
	{ Tier = "Legendary", Mutation = "Golden" },
	{ Tier = "Epic", Mutation = "Diamond" },
	{ Tier = "Mythic", Mutation = "Celestial" },
	{ Tier = "Legendary", Mutation = "Void" },
	{ Tier = "Epic", Mutation = "Charged" },
} :: { ItemLook }
TrailerConfig.HeroPedestal = 1 -- shot 6: this pedestal shows the Secret
TrailerConfig.HeroItem = { Tier = "Secret", Mutation = nil } :: ItemLook

--[[ Shot 2: Pull ]]
TrailerConfig.Pull = {
	Item = { Tier = "Legendary", Mutation = "Rainbow" } :: ItemLook,
	WalkFrom = v3(13, 0, 28),
	WalkTo = v3(20, 1, 22), -- on the Gacha Pad (PlotLayout.GACHA_STATION, pad top y 1)
	WalkStart = 0.2,
	WalkEnd = 1.5,
	PullAt = 1.7, -- the pad's burst
	CardAt = 2.2, -- the big reveal card
}

--[[ Shot 3: Fuse to Secret ]]
TrailerConfig.Fuse = {
	InputTier = "Mythic",
	InputFrom = { v3(-8, 6, -11), v3(8, 6, -11) },
	FloatStart = 0.2,
	FloatEnd = 2.0, -- the orbs reach the core (PlotLayout.Machine.CoreY)
	ChargeSeconds = 2.2,
	ResultTier = "Secret",
	BannerDelay = 0.3, -- after the reveal
}

--[[ Shot 4: Heist (staged in your own lab: the thief takes pedestal 2 and
	runs out of your gate; the owner catches him inside the gate) ]]
TrailerConfig.Heist = {
	Pedestal = 2, -- the hold ring fills over HeistConfig.GrabHoldSeconds
	ThiefPath = { v3(-6, 0, 2), v3(-3, 0, 12), v3(0, 0, 24) },
	ThiefRunStart = 1.6,
	ThiefRunEnd = 5.0,
	OwnerPath = { v3(-17, 0, 14), v3(-6, 0, 21), v3(-0.5, 0, 22.5) },
	OwnerRunStart = 2.0,
	OwnerRunEnd = 4.9,
	CatchAt = 5.0,
	OrbBackAt = 5.6,
}

--[[ Shot 5: Void Moon ]]
TrailerConfig.VoidMoon = {
	-- The preview moon sits behind and above the machine (plot-local
	-- direction), so the tilt up from the machine finds it from any slot.
	MoonDirection = v3(0.2, 0.62, -0.76),
	RevealAt = 3.5,
	CardAt = 3.8,
	Item = { Tier = "Epic", Mutation = "Void" } :: ItemLook,
}

TrailerConfig.Shots = {
	{
		Id = "night",
		Duration = 4,
		Camera = {
			{ T = 0, Pos = v3(0, 6, 42), LookAt = v3(0, 5, -14), Fov = 60 },
			{ T = 4, Pos = v3(0, 7.5, 13), LookAt = v3(0, 5.5, -17), Fov = 52, Easing = "Quad" },
		},
	},
	{
		Id = "pull",
		Duration = 5,
		Camera = {
			{ T = 0, Pos = v3(9, 5, 31), LookAt = v3(18, 3, 22), Fov = 55 },
			{ T = 5, Pos = v3(29, 6, 31), LookAt = v3(20, 3.5, 22), Fov = 50, ArcAround = v3(20, 3, 22) },
		},
	},
	{
		Id = "fuse",
		Duration = 7,
		Camera = {
			{ T = 0, Pos = v3(0, 2.5, -3), LookAt = v3(0, 8, -19), Fov = 60 },
			{ T = 4.4, Pos = v3(-2, 2.8, -5), LookAt = "Core", Fov = 56 },
			{ T = 7, Pos = v3(9, 7, -10), LookAt = "Core", Fov = 50, ArcAround = v3(0, 9.5, -19) },
		},
	},
	{
		Id = "heist",
		Duration = 7,
		Camera = {
			{ T = 0, Pos = v3(9, 3, 2), LookAt = v3(-6, 4, -2), Fov = 55 },
			{ T = 1.6, Pos = v3(8, 2.5, 4), LookAt = "Thief", Fov = 55 },
			{ T = 5.0, Pos = v3(9, 2.5, 3), LookAt = "Thief", Fov = 58, Follow = "Thief" },
			-- The whip-pan to the owner.
			{ T = 5.3, Pos = v3(9, 2.5, 3), LookAt = "Owner", Fov = 52, Follow = "Thief", Easing = "Quad" },
			{ T = 7, Pos = v3(8, 3, 6), LookAt = "Owner", Fov = 48, Follow = "Thief" },
		},
	},
	{
		Id = "voidmoon",
		Duration = 5,
		Camera = {
			{ T = 0, Pos = v3(0, 4, 4), LookAt = v3(0, 7, -19), Fov = 60 },
			{ T = 1.8, Pos = v3(0, 4.5, 3), LookAt = "Moon", Fov = 55 },
			{ T = 2.4, Pos = v3(0, 4.5, 3), LookAt = "Moon", Fov = 55 },
			{ T = 3.4, Pos = v3(0, 4, 1), LookAt = "Core", Fov = 52 },
			{ T = 5, Pos = v3(0, 4, 0), LookAt = "Core", Fov = 50 },
		},
	},
	{
		Id = "hold",
		Duration = 2,
		Camera = {
			{ T = 0, Pos = v3(24, 17, 42), LookAt = v3(-1, 4, -7), Fov = 55 },
			{ T = 2, Pos = v3(24, 17, 42), LookAt = v3(-1, 4, -7), Fov = 55 },
		},
	},
} :: { Shot }

function TrailerConfig.GetShot(id: string): Shot?
	for _, shot in TrailerConfig.Shots do
		if shot.Id == id then
			return shot
		end
	end
	return nil
end

-- Seconds of the whole run (shots + the fades between them).
function TrailerConfig.GetTotalSeconds(): number
	local total = 0
	for _, shot in TrailerConfig.Shots do
		total += shot.Duration
	end
	return total + (#TrailerConfig.Shots - 1) * TrailerConfig.FadeSeconds * 2
end

return TrailerConfig
