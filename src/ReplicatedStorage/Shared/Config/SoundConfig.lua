--!strict
--[[
	SoundConfig
	-----------
	Every sound the game plays, by named slot. SoundKit.Play(slot) plays it;
	an empty Id plays nothing (no error), and an Id that fails to load warns
	once and then stays silent. docs/SOUNDS.md describes what each slot
	should sound like and where it plays: fill the Ids from the Creator
	Store there and here.

	Only one asset is proven to load in this project so far
	(rbxasset://sounds/electronicpingshort.wav); it sits in the slots that
	already used it. New slots stay EMPTY rather than reusing it for
	everything (thunder used to be the same ping slowed down).
]]
local SoundConfig = {}

export type Slot = { Id: string, Volume: number }

local PING = "rbxasset://sounds/electronicpingshort.wav"

SoundConfig.Slots = {
	EventStart = { Id = PING, Volume = 0.6 }, -- the event start banner
	EventEnd = { Id = "", Volume = 0.6 }, -- "<event> is over"
	CoinPickup = { Id = "", Volume = 0.5 }, -- a Golden Rain coin
	BigCoin = { Id = "", Volume = 0.8 }, -- a BIG coin
	Thunder = { Id = "", Volume = 1 }, -- a Power Surge lightning strike
	MeteorImpact = { Id = "", Volume = 0.9 }, -- a meteor landing
	EventReveal = { Id = "", Volume = 1 }, -- the event-only mutation reveal card
	Grab = { Id = PING, Volume = 1 }, -- a thief grabs an item
	Alarm = { Id = PING, Volume = 0.8 }, -- your item is being stolen
	RevealMajor = { Id = PING, Volume = 1 }, -- Epic+ / Diamond+ fusion reveal
	RevealMinor = { Id = PING, Volume = 0.55 }, -- other fusion reveals
	Toast = { Id = PING, Volume = 0.7 }, -- top banners (announcements)
	Station = { Id = PING, Volume = 0.8 }, -- a station purchase (Multiplier Pad, gacha)
} :: { [string]: Slot }

return SoundConfig
