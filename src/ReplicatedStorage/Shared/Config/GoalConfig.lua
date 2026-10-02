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
]]
local GoalConfig = {}

export type GoalDef = {
	Id: string,
	Text: string,
	Reward: number,
	Unit: string?,
}

GoalConfig.Goals = {
	{ Id = "claim_base", Text = "Claim your base", Reward = 50 },
	{ Id = "buy_dropper2", Text = "Buy Dropper 2", Reward = 60 },
	{ Id = "buy_basic_generator", Text = "Buy a Basic Generator", Reward = 100 },
	{ Id = "gacha_pull", Text = "Pull from the Gacha Pad", Reward = 150 },
	{ Id = "display_item", Text = "Put an item on a pedestal", Reward = 200 },
	{ Id = "first_fusion", Text = "Fuse at your Fusion Machine", Reward = 300 },
	{ Id = "own_rare", Text = "Own a Rare item", Reward = 400, Unit = "Rare" },
	{ Id = "upgrade_multiplier", Text = "Upgrade your Multiplier", Reward = 1500 },
	{ Id = "own_epic", Text = "Fuse 2 Rare items into an Epic", Reward = 3000, Unit = "Rare" },
	{ Id = "unlock_ember_forge", Text = "Unlock the Ember Forge", Reward = 5000, Unit = "Basic LV" },
	{ Id = "own_legendary", Text = "Own a Legendary", Reward = 20000, Unit = "Epic" },
	{ Id = "multiplier_x3", Text = "Reach a x3 multiplier", Reward = 100000, Unit = "LV" },
	{ Id = "own_mythic", Text = "Own a Mythic", Reward = 500000, Unit = "Legendary" },
} :: { GoalDef }

function GoalConfig.GetGoal(index: number): GoalDef?
	return GoalConfig.Goals[index]
end

return GoalConfig
