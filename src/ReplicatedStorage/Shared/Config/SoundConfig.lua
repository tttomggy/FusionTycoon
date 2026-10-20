--!strict
--[[
	SoundConfig
	-----------
	Every sound the game plays, by named slot. SoundKit.Play(slot) plays it;
	an empty Id plays nothing (no error), and an Id that fails to load warns
	once and then stays silent. docs/SOUNDS.md lists each slot, what it
	sounds like and where it plays.

	Every Id is a public Creator Store sound effect. The non-combat ones are
	uploaded by the Roblox account (creator id 1); the combat ones are APM /
	ProSoundEffects / DistroKid-licensed or short public SFX. Picked by
	Claude from the store's names and lengths (not listened to): flag any
	that sound wrong in a playtest ("/sound <slot>" auditions one). Shoot
	and Laser are the same clip on purpose (Laser at 1.3x).

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
	PlaybackSpeed: number?,
	DucksMusic: boolean?,
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
	EventReveal = { Id = asset(16480577565), Volume = 0.6, DucksMusic = true },
	-- Roblox_UI_Whoosh_01: a thief grabs an item.
	Grab = { Id = asset(15675024286), Volume = 0.6 },
	-- Roblox_Pinball_8Bit_Blip_05: your item is being stolen (played 3x).
	Alarm = { Id = asset(16480579431), Volume = 0.5 },
	-- victory.wav: a big fusion reveal at the machine.
	RevealMajor = { Id = asset(12222253), Volume = 0.6, DucksMusic = true },
	-- Roblox_UI_Cute_Pop: other fusion reveals, skipped-card pulls.
	RevealMinor = { Id = asset(15675055424), Volume = 0.45 },
	-- Roblox_UI_Bright_Click: top banners (announcements).
	Toast = { Id = asset(15675059323), Volume = 0.35 },
	-- RBLX UI Purchase (SFX): a station purchase (Multiplier Pad, gacha).
	Station = { Id = asset(10066947742), Volume = 0.5 },
	-- Combat (CombatController). Ids picked from the Creator Store (Polish
	-- 12; APM / ProSoundEffects / short public SFX), judged by name, not ear:
	-- audition each in Studio with "/sound <slot>" and swap any that miss.
	-- Hit_Fryingpan: a Bat hit.
	Bonk = { Id = asset(121015905545694), Volume = 0.6, SpeedJitter = { 0.9, 1.1 }, RollOffMaxDistance = 120 },
	-- ProSoundEffects "Hand Clap 1": a Slap Glove hit.
	Slap = { Id = asset(9114758204), Volume = 0.65, SpeedJitter = { 0.95, 1.05 }, RollOffMaxDistance = 120 },
	-- eblaster_blast_fire_01 at 1.3x: the Laser Gun's hit (Shoot is the same
	-- clip at normal speed).
	Laser = { Id = asset(96445944074750), Volume = 0.5, PlaybackSpeed = 1.3, RollOffMaxDistance = 150 },
	-- AW Freeze Spreading: a Freeze Ray hit.
	Freeze = { Id = asset(87971519891129), Volume = 0.5, RollOffMaxDistance = 120 },
	-- slide whistle: a Banana Peel slip.
	Slip = { Id = asset(97197794979302), Volume = 0.6, RollOffMaxDistance = 120 },
	-- ProSoundEffects "Wood Whoosh Quick Swing": a Bat / Glove swing.
	Swing = { Id = asset(9120972321), Volume = 0.5, SpeedJitter = { 0.95, 1.1 }, RollOffMaxDistance = 90 },
	-- eblaster_blast_fire_01: a Laser Gun / Freeze Ray shot (the Ray at 0.8x).
	Shoot = { Id = asset(96445944074750), Volume = 0.45, RollOffMaxDistance = 120 },
	-- ProSoundEffects "Plastic Flashlight pick up": a weapon comes out.
	Equip = { Id = asset(9117509491), Volume = 0.4, RollOffMaxDistance = 60 },
} :: { [string]: Slot }

-- At most this many sounds of one slot play at once; extra plays are
-- dropped, not stacked (a Golden Rain coin streak, Pull x10).
SoundConfig.MaxConcurrentPerSlot = 6

-- The SoundGroup every SoundKit sound plays through. Each client sets its
-- Volume locally to the player's SfxVolume (0 when muted), which also
-- covers sounds the server plays (Station).
SoundConfig.GroupName = "SFX"

return SoundConfig
