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
	lowest-index empty pedestal), or "ui:<Button>" for a HUD button.
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
	{ Id = "buy_dropper2", Text = "Buy Dropper 2", Reward = 60, Target = "Dropper2Station" },
	{ Id = "buy_basic_generator", Text = "Buy a Basic Generator", Reward = 100, Target = "ui:Upgrades" },
	{ Id = "gacha_pull", Text = "Pull from the Gacha Pad", Reward = 150, Target = "GachaStation" },
	{ Id = "display_item", Text = "Put an item on a pedestal", Reward = 200, Target = "FirstEmptyPedestal" },
	{ Id = "first_fusion", Text = "Fuse at your Fusion Machine", Reward = 300, Target = "FusionMachine" },
	{ Id = "own_rare", Text = "Own a Rare item", Reward = 400, Unit = "Rare", Target = "FusionMachine" },
	{ Id = "upgrade_multiplier", Text = "Upgrade your Multiplier", Reward = 1500, Target = "MultiplierStation" },
	{ Id = "own_epic", Text = "Fuse 2 Rare items into an Epic", Reward = 3000, Unit = "Rare", Target = "FusionMachine" },
	{ Id = "unlock_ember_forge", Text = "Unlock the Ember Forge", Reward = 5000, Unit = "Basic LV", Target = "ui:Upgrades" },
	{ Id = "own_legendary", Text = "Own a Legendary", Reward = 20000, Unit = "Epic", Target = "FusionMachine" },
	{ Id = "multiplier_x3", Text = "Reach a x3 multiplier", Reward = 100000, Unit = "LV", Target = "MultiplierStation" },
	{ Id = "own_mythic", Text = "Own a Mythic", Reward = 500000, Unit = "Legendary", Target = "FusionMachine" },
} :: { GoalDef }

function GoalConfig.GetGoal(index: number): GoalDef?
	return GoalConfig.Goals[index]
end

return GoalConfig
