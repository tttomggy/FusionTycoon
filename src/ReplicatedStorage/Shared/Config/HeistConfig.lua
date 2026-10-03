--!strict
--[[
	HeistConfig
	-----------
	Every number of the heist: from Rebirth 1, an item on a pedestal can be
	stolen by another Rebirth 1+ player, and every lab has a shield.

	  Grab     hold E GrabHoldSeconds at an enemy pedestal (victim's shield
	           down, both at MinRebirths+).
	  Carry    CarrySeconds to reach your own plot at CarryWalkSpeed.
	  Deliver  your root inside your own plot's walls: the item is yours.
	  Tag      the owner within TagDistance of you: the item goes back.
	  Fail     tagged, timeout, thief dies or leaves, victim leaves: back.

	HeistService owns the state; nothing here is saved.
]]
local HeistConfig = {}

HeistConfig.MinRebirths = 1 -- both thief and victim need at least this many rebirths

-- Grab
HeistConfig.GrabHoldSeconds = 1.5 -- StealPrompt HoldDuration
HeistConfig.PromptDistance = 7 -- StealPrompt MaxActivationDistance
HeistConfig.GrabRangeSlack = 2 -- the server accepts a root within PromptDistance + this of the pedestal

-- Carry
HeistConfig.CarrySeconds = 45 -- time to get home
HeistConfig.CarryWalkSpeed = 12
HeistConfig.NormalWalkSpeed = 16 -- restored when a carry ends
HeistConfig.TagDistance = 5 -- owner root within this of the thief's root saves the item
HeistConfig.TagGraceSeconds = 2 -- no tag for the first seconds of a carry (the thief gets to see it happen)
HeistConfig.OwnerBlockRadius = 6 -- owner root within this of the pedestal when the hold completes: guarded, no grab
HeistConfig.OwnerChaseWalkSpeed = 18 -- the owner's speed while one of their items is being carried
HeistConfig.CarryTickSeconds = 0.1 -- carry loop rate (~10 Hz)

-- Cooldowns and protection
HeistConfig.ThiefCooldownSeconds = 60 -- after any attempt, success or fail
HeistConfig.VictimShieldSeconds = 120 -- auto-shield after losing an item
HeistConfig.LossCap = 3 -- at most this many items lost ...
HeistConfig.LossWindowSeconds = 10 * 60 -- ... per this window; then the lab is unstealable until one ages out

-- Shield
HeistConfig.ShieldSeconds = 60 -- per activation (stepping ONTO your YOURS pad while it's down; standing there does nothing)
HeistConfig.ShieldRearmSeconds = 20 -- after any shield ends (timeout or drop), the pad can't raise it for this long: the thieves' window
HeistConfig.ClaimShieldSeconds = 60 -- automatic, on claim
HeistConfig.EjectTickSeconds = 0.25 -- shielded labs push non-owners out this often

-- Feed: only these tiers (and up) go to the server banner
HeistConfig.FeedMinTier = "Legendary"

return HeistConfig
