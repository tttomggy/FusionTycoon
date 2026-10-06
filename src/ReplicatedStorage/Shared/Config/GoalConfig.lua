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
]]
local GoalConfig = {}

export type GoalDef = {
	Id: string,
	Text: string,
	Reward: number,
	Unit: string?,
	Target: string,
}

GoalConfig.Goals = {
	{ Id = "claim_base", Text = "Claim your base", Reward = 50, Target = "ClaimStation" },
	{ Id = "upgrade_basic", Text = "Upgrade your Basic Generator", Reward = 60, Target = "Generator_basic_generator" },
	{ Id = "basic_lv5", Text = "Get Basic Generator to LV 5", Reward = 100, Unit = "Basic LV", Target = "Generator_basic_generator" },
	{ Id = "gacha_pull", Text = "Pull from the Gacha Pad", Reward = 150, Target = "GachaStation" },
	-- Automatic now (your best items fill the pedestals): it completes with
	-- the first pull. Kept (not removed) so saved GoalIndex values still line up.
	{ Id = "display_item", Text = "Your best orb goes on a pedestal", Reward = 200, Target = "FirstEmptyPedestal" },
	{ Id = "first_fusion", Text = "Fuse at your Fusion Machine", Reward = 300, Target = "FusionMachine" },
	{ Id = "own_rare", Text = "Own a Rare item", Reward = 400, Unit = "Rare", Target = "FusionMachine" },
	{ Id = "upgrade_multiplier", Text = "Upgrade your Multiplier", Reward = 1500, Target = "MultiplierStation" },
	{ Id = "own_epic", Text = "Fuse Rares into an Epic", Reward = 3000, Unit = "Rare", Target = "FusionMachine" },
	{ Id = "unlock_ember_forge", Text = "Unlock the Ember Forge", Reward = 5000, Unit = "Basic LV", Target = "Generator_ember_forge" },
	{ Id = "own_legendary", Text = "Own a Legendary", Reward = 20000, Unit = "Epic", Target = "FusionMachine" },
	{ Id = "multiplier_x2", Text = "Reach a x2 multiplier", Reward = 100000, Unit = "LV", Target = "MultiplierStation" },
	{ Id = "own_mythic", Text = "Own a Mythic", Reward = 500000, Unit = "Legendary", Target = "FusionMachine" },
	-- Checked after the rebirth resets the run, so the reward lands in the new run.
	{ Id = "first_rebirth", Text = "Rebirth for the first time", Reward = 25000, Target = "RebirthPortal" },
	-- Heist (unlocks at Rebirth 1): defend first, then steal.
	{ Id = "first_shield", Text = "Lock your lab with the LOCK button", Reward = 10000, Target = "LockConsole" },
	{ Id = "first_steal", Text = "Steal an item from another lab", Reward = 50000, Target = "NearestEnemyPedestal" },
} :: { GoalDef }

function GoalConfig.GetGoal(index: number): GoalDef?
	return GoalConfig.Goals[index]
end

return GoalConfig
