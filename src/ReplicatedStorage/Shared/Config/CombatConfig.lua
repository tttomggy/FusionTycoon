--!strict
--[[
	CombatConfig
	------------
	Weapons and ragdoll (CombatService on the server, CombatController on
	the client). Cartoon bonks for a kid audience: no health, no damage, no
	deaths. A hit ragdolls the target for RagdollSeconds with a knockback,
	then they stand up and are immune for GetUpImmuneSeconds. Only Rebirth
	1+ vs Rebirth 1+ (the stealing gate, HeistConfig.MinRebirths); nobody is
	hit for SpawnProtectSeconds after spawning. Hitting a thief who carries
	an orb sends it straight home (HeistService, "Knocked").

	Weapons are EARNED (rebirth milestones; lab-chain quests), never sold: the
	monetization "never" list forbids selling anything that helps a thief
	or protects a lab.

	Each weapon:
	  Id / Name / Glyph   the tool, its bar circle (a glyph, no image)
	  Kind        "Melee" | "Ranged" | "Freeze" | "Peel"
	  Range       studs (melee: root to root; ranged: the server raycast)
	  Cooldown    seconds, enforced on the server
	  Knockback   impulse speed (studs/s) away from the attacker
	  UnlockRebirth   granted at this rebirth count (nil: a quest reward)
]]
local CombatConfig = {}

export type Kind = "Melee" | "Ranged" | "Freeze" | "Peel"

export type Weapon = {
	Id: string,
	Name: string,
	Glyph: string,
	Kind: Kind,
	Range: number,
	Cooldown: number,
	Knockback: number,
	UnlockRebirth: number?,
	Blurb: string, -- the unlock card
	MeleeBox: Vector3?, -- melee only: the server's hit box (X wide, Y tall, Z deep)
	MeleeBoxForward: number?, -- melee only: its centre, studs in front of the root
}

CombatConfig.MinRebirths = 1 -- both sides (the same gate as stealing)
CombatConfig.RagdollSeconds = 1.5
CombatConfig.GetUpImmuneSeconds = 3
CombatConfig.SpawnProtectSeconds = 5
CombatConfig.RangeSlack = 4 -- studs of lag allowance on the server's range checks
-- Knockback is the speed (studs/s) of a server-made LinearVelocity
-- ("KnockbackMover" on the target's root) that is held for LaunchSeconds, then
-- released: the body keeps that speed through the air (no drag) and the ragdoll
-- slides to a stop. Distance ~ speed x (LaunchSeconds + airtime) + a short slide;
-- with UpwardKick 25 the airtime is ~0.4 s after the mover ends. Targets:
-- the Bat throws about 15-20 studs, the Slap Glove about 25-30 with a spin.
-- These values are a computed first guess (30 x ~0.6 s = 18; 42 x ~0.6 s = 25
-- + the slide): tune them in the 2-player test on the TARGET's screen;
-- /selftest combat measures >= 12 (Bat) / >= 20 (Glove) studs in 0.6 s as the
-- target's own client sees it.
CombatConfig.LaunchSeconds = 0.2 -- how long the mover is held
CombatConfig.UpwardKick = 25 -- added to every knockback (a little hop)
CombatConfig.HitsPerSecond = 4 -- RequestHit rate limit (spam is dropped)
CombatConfig.HitBurst = 6
-- Melee hit detection is the SERVER's: after MeleeHitDelay (about the clip's
-- Hit marker) it boxes the weapon's MeleeBox studs (X wide, Y tall, Z deep)
-- in front of the attacker's root, its centre MeleeBoxForward studs forward,
-- and takes the players whose characters overlap it. The box is generous on
-- purpose ("you have to hit exactly at them" was the complaint). Lag
-- tolerance: a player whose root was inside the box at the swing REQUEST
-- time also counts (the server keeps each root's last HistorySeconds of
-- positions). The Bat hits the nearest one, the Slap Glove everyone in the
-- box. The client sends only the weapon id. A target further than the
-- weapon's Range + RangeSlack from the attacker is never hit.
CombatConfig.MeleeHitDelay = 0.15
CombatConfig.HistorySeconds = 0.3

CombatConfig.SpinImpulse = Vector3.new(0, 14, 5) -- per unit of mass: a peel slip / the glove spins you

-- Published animation ids (Harris fills these after /anim export -> Save to
-- Roblox). An id set = that asset; empty in Studio = the in-code clip
-- (WeaponAnims) registered with KeyframeSequenceProvider; empty live = the
-- C0 WeaponPose fallback. Keys are WeaponAnims clip names.
CombatConfig.AnimationIds = {
	BatHold = "rbxassetid://110401007589373",
	BatSwing = "rbxassetid://138784586483656",
	GloveHold = "rbxassetid://130217269948133",
	GloveSlap = "rbxassetid://101382817461159",
	GunAim = "rbxassetid://76161756196333",
	GunRecoil = "rbxassetid://140487467838970",
	PeelThrow = "rbxassetid://126595384761881",
} :: { [string]: string }

CombatConfig.Freeze = {
	SpeedMultiplier = 0.4,
	Seconds = 3,
}

CombatConfig.Peel = {
	MaxOut = 1,
	LifetimeSeconds = 20,
	PlaceReach = 8, -- studs from your root the peel may go
	Knockback = 30,
	Size = Vector3.new(2, 0.4, 2),
}

CombatConfig.Weapons = {
	{
		Id = "Bat",
		Name = "Bat",
		Glyph = "🏏",
		Kind = "Melee",
		Range = 7,
		Cooldown = 1.2,
		Knockback = 30,
		UnlockRebirth = 1,
		Blurb = "Hit a thief to make them drop your orb.",
		MeleeBox = Vector3.new(9, 8, 10),
		MeleeBoxForward = 4.5,
	},
	{
		Id = "LaserGun",
		Name = "Laser Gun",
		Glyph = "🔫",
		Kind = "Ranged",
		Range = 60,
		Cooldown = 3,
		Knockback = 20,
		UnlockRebirth = 2,
		Blurb = "Zap a runner from far away.",
	},
	{
		Id = "FreezeRay",
		Name = "Freeze Ray",
		Glyph = "🥶",
		Kind = "Freeze",
		Range = 40,
		Cooldown = 6,
		Knockback = 0,
		UnlockRebirth = 3,
		Blurb = "Freeze a thief so you can catch them.",
	},
	{
		Id = "SlapGlove",
		Name = "Slap Glove",
		Glyph = "🖐",
		Kind = "Melee",
		Range = 6,
		Cooldown = 2.5,
		Knockback = 42,
		UnlockRebirth = nil,
		Blurb = "One slap sends them flying.",
		MeleeBox = Vector3.new(11, 8, 11),
		MeleeBoxForward = 5,
	},
	{
		Id = "BananaPeel",
		Name = "Banana Peel",
		Glyph = "🍌",
		Kind = "Peel",
		Range = 8,
		Cooldown = 10,
		Knockback = 20,
		UnlockRebirth = nil,
		Blurb = "Drop it on the ground: the first enemy to step on it slips.",
	},
} :: { Weapon }

function CombatConfig.GetWeapon(id: unknown): Weapon?
	if typeof(id) ~= "string" then
		return nil
	end
	for _, weapon in CombatConfig.Weapons do
		if weapon.Id == id then
			return weapon
		end
	end
	return nil
end

-- A melee weapon's server hit box: its size and how far in front of the
-- attacker's root its centre sits.
function CombatConfig.GetMeleeBox(weapon: Weapon): (Vector3, number)
	return weapon.MeleeBox or Vector3.new(6, 6, 7), weapon.MeleeBoxForward or 3.5
end

-- The weapons a rebirth count earns on its own (the Slap Glove and Banana
-- Peel are lab-chain quest rewards: QuestConfig.Chain, QuestService).
function CombatConfig.GetUnlockedByRebirths(rebirths: number): { string }
	local ids = {}
	for _, weapon in CombatConfig.Weapons do
		if weapon.UnlockRebirth and rebirths >= weapon.UnlockRebirth then
			table.insert(ids, weapon.Id)
		end
	end
	return ids
end

-- "🔫 Laser Gun" for the weapons rebirth `n` itself unlocks (Rebirth panel).
function CombatConfig.GetUnlockText(n: number): string?
	local names = {}
	for _, weapon in CombatConfig.Weapons do
		if weapon.UnlockRebirth == n then
			table.insert(names, ("%s %s"):format(weapon.Glyph, weapon.Name))
		end
	end
	return if #names > 0 then table.concat(names, " · ") else nil
end

return CombatConfig
