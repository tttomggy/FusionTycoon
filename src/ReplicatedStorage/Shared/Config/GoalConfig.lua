--!strict
--[[
	GoalConfig
	----------
	The ordered onboarding goals shown on the HUD's goal tracker. The server
	(GoalService) decides when each is met, pays the reward and advances the
	player's GoalIndex; the client only renders Text/Reward/Unit plus the
	server-computed GoalProgress from the tycoon snapshot.

	`Id` keys GoalService's evaluator for that goal. `Unit` labels the
	"1 / 2 Rare" progress line; nil means a yes/no goal with no count line.
	`Target` is where the client's goal marker points: the name of a part or
	model inside the player's own plot, "FirstEmptyPedestal" (the
	lowest-index empty pedestal), "NearestEnemyPedestal" (the closest
	pedestal in another lab you could steal from right now), or
	"ui:<Button>" for a HUD button.

	"Own a tier" goals (own_rare / own_epic / own_legendary / own_mythic:
	`Kind = "OwnTier", Tier = ...`) also show the NEXT ACTION under the goal
	text and move the arrow to match (GoalSteps, computed in GoalService on
	every sync): fuse your N orbs of the tier below, fuse a lower tier up
	first, pull from the Gacha, or earn cash for a pull. Their `Target` is the
	fallback (the Fusion Machine) for a client that has no step yet.

	The LoopCoach (Shared/Config/LoopCoach: Pull -> Fuse -> Earn -> Upgrade,
	+ Steal) runs under every goal after the tutorial. The goal keeps its
	title; when its own step can't be done right now (not enough cash for
	the upgrade, nothing to fuse, an "own a tier" goal's Earn) the coach
	takes the 2nd line and the arrow (LoopCoach.GoalBlocked). `Loop` tells the
	loop strip which icon a goal IS while the goal is the one pointing.

	SAVED PROGRESS is an INDEX into Goals, so inserting a goal in the middle
	shifts every saved player. DataVersion + V1Ids + MigrateIndex put a save
	back on the SAME goal id (PlayerDataService stamps GoalVer on load/save):
	goals inserted BEFORE the player's goal are skipped without paying their
	reward (they are behind the player; no free cash for old saves), goals
	inserted AFTER it simply come up later. A save that finished every goal
	stays finished. Only INSERT goals; to add more later, bump DataVersion and
	freeze the list that was current (V2Ids ...).
]]
local GoalConfig = {}

export type GoalDef = {
	Id: string,
	Text: string,
	Reward: number,
	Unit: string?,
	Target: string,
	-- "OwnTier" + Tier: an "own a <Tier>" goal. GoalService adds the live next
	-- action (GoalSteps) to its progress, and that action's target replaces
	-- `Target` while it lasts.
	Kind: string?,
	Tier: string?,
	-- The LoopCoach step this goal IS ("Pull" | "Fuse" | "Upgrade" | "Steal"):
	-- the loop strip lights it while the goal (not the coach) is pointing.
	-- nil: the goal is no step of the loop, the strip shows the coach's.
	Loop: string?,
}

-- 1: the 16-goal list before "Fuse ladder" (frozen ids, in the old order).
-- 2: the current list (adds fill_pedestals, max_basic, own_3_rares,
--    multiplier_x1_5, own_2_epics, unlock_flare_reactor).
GoalConfig.DataVersion = 2

GoalConfig.V1Ids = {
	"claim_base",
	"upgrade_basic",
	"basic_lv5",
	"gacha_pull",
	"display_item",
	"first_fusion",
	"own_rare",
	"upgrade_multiplier",
	"own_epic",
	"unlock_ember_forge",
	"own_legendary",
	"multiplier_x2",
	"own_mythic",
	"first_rebirth",
	"first_shield",
	"first_steal",
} :: { string }

GoalConfig.Goals = {
	{ Id = "claim_base", Text = "Claim your base", Reward = 50, Target = "ClaimStation" },
	{ Id = "upgrade_basic", Text = "Upgrade your Basic Generator", Reward = 60, Target = "Generator_basic_generator", Loop = "Upgrade" },
	{ Id = "basic_lv5", Text = "Get Basic Generator to LV 5", Reward = 100, Unit = "Basic LV", Target = "Generator_basic_generator", Loop = "Upgrade" },
	{ Id = "gacha_pull", Text = "Pull from the Gacha Pad", Reward = 150, Target = "GachaStation", Loop = "Pull" },
	-- Automatic now (your best items fill the pedestals): it completes with
	-- the first pull. Kept (not removed) so saved GoalIndex values still line up.
	{ Id = "display_item", Text = "Your best orb goes on a pedestal", Reward = 200, Target = "FirstEmptyPedestal" },
	{ Id = "first_fusion", Text = "Fuse at your Fusion Machine", Reward = 300, Target = "FusionMachine", Loop = "Fuse" },
	{ Id = "own_rare", Text = "Fuse Commons into a Rare", Reward = 400, Unit = "Rare", Target = "FusionMachine", Kind = "OwnTier", Tier = "Rare" },
	-- Cheap goals between the first Rare and the 5000-cash Multiplier, where a
	-- real player stalled: each one is a thing to do next.
	{ Id = "fill_pedestals", Text = "Fill all 4 pedestals", Reward = 600, Unit = "Pedestal", Target = "FirstEmptyPedestal" },
	{ Id = "max_basic", Text = "Max your Basic Generator (LV 25)", Reward = 1500, Unit = "Basic LV", Target = "Generator_basic_generator", Loop = "Upgrade" },
	-- (done too when the player already owns an Epic: they fused past it)
	{ Id = "own_3_rares", Text = "Own 3 Rares at once", Reward = 1200, Unit = "Rare", Target = "FusionMachine", Loop = "Fuse" },
	{ Id = "upgrade_multiplier", Text = "Upgrade your Multiplier", Reward = 1500, Target = "MultiplierStation", Loop = "Upgrade" },
	{ Id = "own_epic", Text = "Fuse Rares into an Epic", Reward = 3000, Unit = "Rare", Target = "FusionMachine", Kind = "OwnTier", Tier = "Epic" },
	{ Id = "unlock_ember_forge", Text = "Unlock the Ember Forge", Reward = 5000, Unit = "Basic LV", Target = "Generator_ember_forge", Loop = "Upgrade" },
	{ Id = "multiplier_x1_5", Text = "Reach x1.5 multiplier", Reward = 4000, Unit = "LV", Target = "MultiplierStation", Loop = "Upgrade" },
	-- (done too when the player already owns a Legendary)
	{ Id = "own_2_epics", Text = "Own 2 Epics", Reward = 6000, Unit = "Epic", Target = "FusionMachine", Loop = "Fuse" },
	{ Id = "unlock_flare_reactor", Text = "Unlock the Flare Reactor", Reward = 10000, Unit = "Ember LV", Target = "Generator_flare_reactor", Loop = "Upgrade" },
	{ Id = "own_legendary", Text = "Fuse Epics into a Legendary", Reward = 20000, Unit = "Epic", Target = "FusionMachine", Kind = "OwnTier", Tier = "Legendary" },
	{ Id = "multiplier_x2", Text = "Reach a x2 multiplier", Reward = 100000, Unit = "LV", Target = "MultiplierStation", Loop = "Upgrade" },
	{ Id = "own_mythic", Text = "Fuse Legendaries into a Mythic", Reward = 500000, Unit = "Legendary", Target = "FusionMachine", Kind = "OwnTier", Tier = "Mythic" },
	-- Checked after the rebirth resets the run, so the reward lands in the new run.
	{ Id = "first_rebirth", Text = "Rebirth for the first time", Reward = 25000, Target = "RebirthPortal" },
	-- Heist (unlocks at Rebirth 1): defend first, then steal.
	{ Id = "first_shield", Text = "Lock your lab with the LOCK button", Reward = 10000, Target = "LockConsole" },
	{ Id = "first_steal", Text = "Steal an item from another lab", Reward = 50000, Target = "NearestEnemyPedestal", Loop = "Steal" },
} :: { GoalDef }

function GoalConfig.GetGoal(index: number): GoalDef?
	return GoalConfig.Goals[index]
end

-- The index of goal `id` in the current list, or nil.
function GoalConfig.IndexOf(id: string): number?
	for index, goal in GoalConfig.Goals do
		if goal.Id == id then
			return index
		end
	end
	return nil
end

-- A saved GoalIndex from list version `fromVersion` -> the same goal in the
-- current list (see the header). Pure. Past the end of the old list (every
-- goal done) stays past the end of the new one; an unknown id keeps the
-- index (clamped), which only happens with a hand-edited save.
function GoalConfig.MigrateIndex(index: number, fromVersion: number): number
	if fromVersion >= GoalConfig.DataVersion then
		return index
	end
	local ids = GoalConfig.V1Ids
	if index > #ids then
		return #GoalConfig.Goals + 1
	end
	local migrated = GoalConfig.IndexOf(ids[math.max(index, 1)])
	return migrated or math.min(index, #GoalConfig.Goals + 1)
end

return GoalConfig
