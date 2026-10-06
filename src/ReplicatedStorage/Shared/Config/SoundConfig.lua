--!strict
--[[
	SoundConfig
	-----------
	Every sound the game plays, by named slot. SoundKit.Play(slot) plays it;
	an empty Id plays nothing (no error), and an Id that fails to load warns
	once and then stays silent. docs/SOUNDS.md lists each slot, what it
	sounds like and where it plays.

	Every Id is a public Creator Store sound effect uploaded by the Roblox
	account (creator id 1), so it loads in any experience. Picked by Claude
	from the store's names and lengths (not listened to): flag any that
	sound wrong in a playtest. No slot reuses another's sound.

	Optional per slot:
	  SpeedJitter        { min, max } random PlaybackSpeed per play (a coin
	                     streak doesn't drone); an explicit PlaybackSpeed
	                     option wins.
	  RollOffMaxDistance positional plays only (parented to a part or
	                     played with SoundKit.PlayAt).
]]
local SoundConfig = {}

export type Slot = {
	Id: string,
	Volume: number,
	SpeedJitter: { number }?,
	RollOffMaxDistance: number?,
}

local function asset(id: number): string
	return ("rbxassetid://%d"):format(id)
end

SoundConfig.Slots = {
	-- Roblox_UI_Tonal_Stinger (1 s): once, as the event start banner shows.
	EventStart = { Id = asset(15675043410), Volume = 0.6 },
	-- Roblox_UI_Cute_Goodbye: "<event> is over".
	EventEnd = { Id = asset(15675081158), Volume = 0.5 },
	-- Roblox_Pinball_8Bit_Blip_01: a Golden Rain coin.
	CoinPickup = { Id = asset(16480580213), Volume = 0.45, SpeedJitter = { 0.95, 1.1 } },
	-- CoinTransfer_01 (2 s): a BIG coin.
	BigCoin = { Id = asset(127645268874265), Volume = 0.6 },
	-- HalloweenThunder.wav (4 s): a Power Surge strike, at the struck target.
	Thunder = { Id = asset(12222030), Volume = 0.55, RollOffMaxDistance = 150 },
	-- Cannon_Explode: a meteor landing, at the crater.
	MeteorImpact = { Id = asset(3149249837), Volume = 0.5, RollOffMaxDistance = 200 },
	-- Roblox_Pinball_8Bit_Riser_04 (3 s): the Charged / Void / Celestial reveal card.
	EventReveal = { Id = asset(16480577565), Volume = 0.6 },
	-- Roblox_UI_Whoosh_01: a thief grabs an item.
	Grab = { Id = asset(15675024286), Volume = 0.6 },
	-- Roblox_Pinball_8Bit_Blip_05: your item is being stolen (played 3x).
	Alarm = { Id = asset(16480579431), Volume = 0.5 },
	-- victory.wav: a big fusion reveal at the machine.
	RevealMajor = { Id = asset(12222253), Volume = 0.6 },
	-- Roblox_UI_Cute_Pop: other fusion reveals, skipped-card pulls.
	RevealMinor = { Id = asset(15675055424), Volume = 0.45 },
	-- Roblox_UI_Bright_Click: top banners (announcements).
	Toast = { Id = asset(15675059323), Volume = 0.35 },
	-- RBLX UI Purchase (SFX): a station purchase (Multiplier Pad, gacha).
	Station = { Id = asset(10066947742), Volume = 0.5 },
	-- Combat (CombatController). EMPTY until picked from the Creator Store
	-- (creator id 1): a cartoon bonk, a laser zap, an ice crackle, a
	-- banana slip. Silent meanwhile (an empty Id is no error).
	Bonk = { Id = "", Volume = 0.6, SpeedJitter = { 0.9, 1.1 }, RollOffMaxDistance = 120 },
	Laser = { Id = "", Volume = 0.5, RollOffMaxDistance = 150 },
	Freeze = { Id = "", Volume = 0.5, RollOffMaxDistance = 120 },
	Slip = { Id = "", Volume = 0.6, RollOffMaxDistance = 120 },
} :: { [string]: Slot }

-- At most this many sounds of one slot play at once; extra plays are
-- dropped, not stacked (a Golden Rain coin streak, Pull x10).
SoundConfig.MaxConcurrentPerSlot = 6

-- The SoundGroup every SoundKit sound plays through. Each client sets its
-- Volume locally to the player's SfxVolume (0 when muted), which also
-- covers sounds the server plays (Station).
SoundConfig.GroupName = "SFX"

return SoundConfig
