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
}

CombatConfig.MinRebirths = 1 -- both sides (the same gate as stealing)
CombatConfig.RagdollSeconds = 1.5
CombatConfig.GetUpImmuneSeconds = 3
CombatConfig.SpawnProtectSeconds = 5
CombatConfig.RangeSlack = 4 -- studs of lag allowance on the server's range checks
CombatConfig.UpwardKick = 25 -- added to every knockback (a little hop)
CombatConfig.HitsPerSecond = 4 -- RequestHit rate limit (spam is dropped)
CombatConfig.HitBurst = 6
CombatConfig.MeleeMaxAngle = 100 -- degrees off your facing a melee target may be

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
		Knockback = 60,
		UnlockRebirth = 1,
		Blurb = "Hit a thief to make them drop your orb.",
	},
	{
		Id = "LaserGun",
		Name = "Laser Gun",
		Glyph = "🔫",
		Kind = "Ranged",
		Range = 60,
		Cooldown = 3,
		Knockback = 35,
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
		Knockback = 120,
		UnlockRebirth = nil,
		Blurb = "One slap sends them flying.",
	},
	{
		Id = "BananaPeel",
		Name = "Banana Peel",
		Glyph = "🍌",
		Kind = "Peel",
		Range = 8,
		Cooldown = 10,
		Knockback = 30,
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
