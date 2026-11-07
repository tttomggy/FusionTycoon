--!strict
--[[
	MinigameConfig
	--------------
	ORB RUSH: a 90-second arena minigame every 15 minutes (MinigameService is
	the server, MinigameController the client; geometry in ArenaLayout, the
	street portal in StreetLayout). Every number lives here; tools/econ_sim.py
	(--minigame) mirrors the prizes.

	  Schedule  hh:07, :22, :37, :52 on the UTC clock (deterministic, like
	            EventConfig; EventConfig starts at :00/:15/:30/:45 and never
	            shares a start minute with a round).
	  Call      the 60 s before a round: the portal is on, anyone can JOIN.
	  Fill      at the end of the call the queued humans (up to MaxPlayers)
	            play; fewer than FillTo get bots up to FillTo; nobody queued,
	            no round.
	  Round     a 3-2-1-GO countdown, then RoundSeconds of orbs raining from
	            the sky; points = orb value; the last GoldenWaveSeconds only
	            gold orbs, twice as often. A weapon hit knocks
	            ScatterFraction of the target's points out as orbs.
	  Prizes    1st / 2nd / 3rd: one orb (Prizes); everyone else with at least
	            MinPointsToPlace points: cash = ParticipationIncomeSeconds of
	            their own passive income. A bot's place awards nothing. At most
	            PlacementPrizesPerHour placement prizes per player an hour.
]]
local MinigameConfig = {}

export type Round = {
	Slot: number, -- floor(unix / SlotSeconds)
	CallAt: number, -- unix seconds: the call (portal on, JOIN)
	StartAt: number, -- unix seconds: the queue closes, the arena round begins
}

--[[ Schedule ------------------------------------------------------------------- ]]

MinigameConfig.SlotSeconds = 15 * 60
MinigameConfig.CallMinute = 7 -- minutes into each 15-minute slot: hh:07, :22, :37, :52
MinigameConfig.CallSeconds = 60
MinigameConfig.CountdownSeconds = 3
MinigameConfig.RoundSeconds = 90
MinigameConfig.GoldenWaveSeconds = 15
MinigameConfig.ResultsHoldSeconds = 1.5 -- a beat on the final scores before everyone goes home

MinigameConfig.MaxPlayers = 8
MinigameConfig.FillTo = 4 -- humans + bots are at least this many

-- The round whose call falls in slot `slot` (deterministic from the clock).
function MinigameConfig.GetRoundForSlot(slot: number): Round
	local callAt = slot * MinigameConfig.SlotSeconds + MinigameConfig.CallMinute * 60
	return { Slot = slot, CallAt = callAt, StartAt = callAt + MinigameConfig.CallSeconds }
end

function MinigameConfig.GetSlot(unix: number): number
	return math.floor(unix / MinigameConfig.SlotSeconds)
end

-- The round to show at `unix`: the one in its call window or still playing
-- (ends at StartAt + countdown + round), else the next one to come.
function MinigameConfig.GetCurrentOrNext(unix: number): Round
	local slot = MinigameConfig.GetSlot(unix)
	local round = MinigameConfig.GetRoundForSlot(slot)
	local endsAt = round.StartAt + MinigameConfig.CountdownSeconds + MinigameConfig.RoundSeconds + MinigameConfig.ResultsHoldSeconds
	if unix < endsAt then
		return round
	end
	return MinigameConfig.GetRoundForSlot(slot + 1)
end

-- "m:ss" for a countdown.
function MinigameConfig.FormatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(whole // 60, whole % 60)
end

-- ":22" for the minute a call opens ("NEXT ORB RUSH at :22").
function MinigameConfig.FormatMinute(unix: number): string
	return (":%02d"):format(math.floor(unix / 60) % 60)
end

--[[ Orbs and points ----------------------------------------------------------- ]]

-- Cosmetic orb tiers: colour (UITheme.World token), value, drop weight.
MinigameConfig.OrbTiers = {
	{ Id = "White", Value = 1, Weight = 60, Token = "OrbWhite" },
	{ Id = "Blue", Value = 2, Weight = 22, Token = "OrbBlue" },
	{ Id = "Purple", Value = 3, Weight = 12, Token = "OrbPurple" },
	{ Id = "Gold", Value = 5, Weight = 6, Token = "OrbGold" },
}
MinigameConfig.GoldenWaveTier = "Gold"

MinigameConfig.WaveSeconds = 2.4 -- one wave of orbs this often
MinigameConfig.OrbsPerWave = 5
MinigameConfig.GoldenWaveRateMultiplier = 2 -- waves come this much faster in the last seconds
MinigameConfig.OrbFallSeconds = 1.1 -- sky to floor
MinigameConfig.OrbSkyHeight = 36
MinigameConfig.OrbLifetimeSeconds = 14 -- on the floor before it fades if nobody takes it
MinigameConfig.MaxOrbs = 70 -- live orbs at once (server cap)
MinigameConfig.OrbSize = 2.2
MinigameConfig.OrbHoverHeight = 2 -- orb centre above the floor top
MinigameConfig.PickupRadius = 4.2 -- studs from the character root (flat) to the orb
MinigameConfig.PickupsPerTick = 6 -- at most this many orbs per player per server tick (a rate limit)
MinigameConfig.TickSeconds = 0.1

MinigameConfig.ScatterFraction = 0.3 -- of the target's points knocked out by a weapon hit
MinigameConfig.HitImmunitySeconds = 2
MinigameConfig.ScatterArmSeconds = 0.5 -- scattered orbs can't be grabbed for this long
MinigameConfig.ScatterSpeed = 22
MinigameConfig.MinHitPoints = 1 -- a target with fewer points than this loses nothing

-- Round rules
MinigameConfig.PointsToPlace = 10

--[[ Prizes ------------------------------------------------------------------------ ]]

-- Place -> tier weights of the ONE orb that place wins.
MinigameConfig.Prizes = {
	[1] = { Epic = 60, Legendary = 35, Mythic = 4.5, Secret = 0.5 },
	[2] = { Rare = 50, Epic = 45, Legendary = 5 },
	[3] = { Rare = 80, Epic = 20 },
} :: { [number]: { [string]: number } }
MinigameConfig.TierOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" } :: { string }

MinigameConfig.MinPointsToPlace = MinigameConfig.PointsToPlace
MinigameConfig.ParticipationIncomeSeconds = 90 -- everyone else: this many seconds of their own passive income in cash
MinigameConfig.PlacementPrizesPerHour = 4
MinigameConfig.PrizeWindowSeconds = 3600

-- The tier prize `place` (1-3) wins for `roll` in [0, 1); nil for any other place.
function MinigameConfig.PickPrizeTier(place: number, roll: number): string?
	local weights = MinigameConfig.Prizes[place]
	if not weights then
		return nil
	end
	local total = 0
	for _, tier in MinigameConfig.TierOrder do
		total += weights[tier] or 0
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	local last: string? = nil
	for _, tier in MinigameConfig.TierOrder do
		local weight = weights[tier] or 0
		if weight > 0 then
			last = tier
			if target < weight then
				return tier
			end
			target -= weight
		end
	end
	return last
end

-- The lowest tier `place` can win (the floor /selftest holds a roll to).
function MinigameConfig.PrizeFloor(place: number): string?
	local weights = MinigameConfig.Prizes[place]
	if not weights then
		return nil
	end
	for _, tier in MinigameConfig.TierOrder do
		if (weights[tier] or 0) > 0 then
			return tier
		end
	end
	return nil
end

function MinigameConfig.PrizeShare(place: number, tier: string): number
	local weights = MinigameConfig.Prizes[place]
	if not weights then
		return 0
	end
	local total = 0
	for _, name in MinigameConfig.TierOrder do
		total += weights[name] or 0
	end
	return if total > 0 then (weights[tier] or 0) / total else 0
end

--[[ Orb drops (pure) ------------------------------------------------------------ ]]

-- One cosmetic orb tier by weight (`roll` in [0, 1)); only gold in the golden wave.
function MinigameConfig.PickOrbTier(roll: number, golden: boolean): { Id: string, Value: number, Weight: number, Token: string }
	local tiers = MinigameConfig.OrbTiers
	if golden then
		for _, tier in tiers do
			if tier.Id == MinigameConfig.GoldenWaveTier then
				return tier
			end
		end
	end
	local total = 0
	for _, tier in tiers do
		total += tier.Weight
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	for _, tier in tiers do
		if target < tier.Weight then
			return tier
		end
		target -= tier.Weight
	end
	return tiers[1]
end

function MinigameConfig.GetOrbValue(id: string): number
	for _, tier in MinigameConfig.OrbTiers do
		if tier.Id == id then
			return tier.Value
		end
	end
	return 1
end

-- Breaks `points` into orb tiers (greedy: largest value first) for a hit's
-- scatter: { "Gold", "Purple", "White" ... }. The values sum to `points`.
function MinigameConfig.SplitPoints(points: number): { string }
	local ids: { string } = {}
	local order: { { Id: string, Value: number } } = {}
	for _, tier in MinigameConfig.OrbTiers do
		table.insert(order, { Id = tier.Id, Value = tier.Value })
	end
	table.sort(order, function(a, b)
		return a.Value > b.Value
	end)
	local left = math.max(0, math.floor(points))
	for _, tier in order do
		while left >= tier.Value do
			table.insert(ids, tier.Id)
			left -= tier.Value
		end
	end
	return ids
end

-- Points a weapon hit knocks out of a target holding `points`.
function MinigameConfig.ScatterPoints(points: number): number
	if points < MinigameConfig.MinHitPoints then
		return 0
	end
	return math.max(1, math.floor(points * MinigameConfig.ScatterFraction))
end

--[[ Bots ---------------------------------------------------------------------------- ]]

MinigameConfig.BotNames = {
	"Pixel", "Zippy", "Nova", "Bolt", "Mochi", "Turbo", "Echo", "Juno",
	"Fizz", "Rocket", "Sprout", "Orbit", "Blip", "Comet", "Waffle", "Dash",
} :: { string }

-- Skill mix per bot (a round rolls each bot from this) and what a skill means:
-- WalkSpeed, the seconds before it reacts to a new orb (it re-picks after
-- this), and how well it values far, rich orbs (Greed: 0 = nearest, 1 = best
-- value per stud).
MinigameConfig.BotSkill = {
	{ Id = "Weak", Weight = 40, Speed = 14, Reaction = 0.8, Greed = 0.1 },
	{ Id = "Normal", Weight = 45, Speed = 15.5, Reaction = 0.45, Greed = 0.3 },
	{ Id = "Strong", Weight = 15, Speed = 16, Reaction = 0.35, Greed = 0.25 },
}
-- Tuned with the headless model below (400-600 simulated rounds, an "average
-- player" who walks at 16 to the nearest orb after a 0.35 s decision): the
-- player wins ~39% of rounds against 4 bots from this mix and ~40% head to
-- head against a Strong bot (a Strong bot is as fast as a player but picks
-- richer orbs and reacts a little quicker).
MinigameConfig.BotThinkSeconds = 0.2 -- the one bot loop
MinigameConfig.BotReachStuds = 70 -- orbs farther than this are ignored
MinigameConfig.BotHitStunSeconds = 0.8 -- a bot hit by a weapon stands still this long

function MinigameConfig.PickBotSkill(roll: number): { Id: string, Weight: number, Speed: number, Reaction: number, Greed: number }
	local total = 0
	for _, skill in MinigameConfig.BotSkill do
		total += skill.Weight
	end
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	for _, skill in MinigameConfig.BotSkill do
		if target < skill.Weight then
			return skill
		end
		target -= skill.Weight
	end
	return MinigameConfig.BotSkill[1]
end

--[[ Headless round model (also /selftest) --------------------------------------- ]]

export type Racer = { Speed: number, Reaction: number, Greed: number }

-- Anything with NextNumber(min?, max?) (a Random, or /selftest's seeded LCG, so
-- the bot win-rate check gives the same answer in Studio and in the Luau CLI).
export type RngLike = { NextNumber: (self: any, min: number?, max: number?) -> number }

-- The score a racer gives an orb `distance` studs away worth `value`: Greed 0
-- takes the nearest, Greed 1 the best value per stud. Bots and the model use it.
function MinigameConfig.ScoreOrb(greed: number, value: number, distance: number): number
	return (1 - greed) * -distance + greed * (value * 10 - distance)
end

-- A flat-disc model of a round: orbs rain in waves (the golden wave at the
-- end), each racer walks to the orb its rule picks and takes it on arrival.
-- `radius` is the arena's walkable radius. A racer scores each orb by
-- (1 - Greed) x (-distance) + Greed x (10 x value - distance), re-picks every
-- Reaction seconds and when its orb is gone. Returns each racer's points.
-- Idealised (no weapons, no collisions): the bots' win rate against a player who
-- just walks to the nearest orb. `rng` gives the drop positions and tiers.
function MinigameConfig.SimulateRound(rng: RngLike, racers: { Racer }, radius: number): { number }
	local count = #racers
	local points: { number } = table.create(count, 0)
	local pos: { Vector2 } = {}
	local goal: { number? } = table.create(count, nil)
	local nextThink: { number } = table.create(count, 0)
	for index = 1, count do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local ring = radius * 0.5
		pos[index] = Vector2.new(math.cos(angle) * ring, math.sin(angle) * ring)
		nextThink[index] = racers[index].Reaction
	end
	local orbs: { { Pos: Vector2, Value: number, Born: number, Alive: boolean } } = {}
	local step = 0.1
	local t = 0
	local nextWave = 1.0
	local total = MinigameConfig.RoundSeconds
	local goldenFrom = total - MinigameConfig.GoldenWaveSeconds
	while t < total do
		-- Waves.
		if t >= nextWave then
			local golden = t >= goldenFrom
			for _ = 1, MinigameConfig.OrbsPerWave do
				local angle = rng:NextNumber(0, 2 * math.pi)
				local distance = radius * 0.92 * math.sqrt(rng:NextNumber())
				local tier = MinigameConfig.PickOrbTier(rng:NextNumber(), golden)
				table.insert(orbs, { Pos = Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance), Value = tier.Value, Born = t + MinigameConfig.OrbFallSeconds, Alive = true })
			end
			nextWave += MinigameConfig.WaveSeconds / (if golden then MinigameConfig.GoldenWaveRateMultiplier else 1)
		end
		for _, orb in orbs do
			if orb.Alive and t - orb.Born > MinigameConfig.OrbLifetimeSeconds then
				orb.Alive = false
			end
		end
		-- Racers (the order rotates each step so nobody wins a tie by their seat).
		local seat = math.floor(t / step)
		for k = 1, count do
			local index = (k + seat) % count + 1
			local racer = racers[index]
			local current = goal[index]
			if current and not orbs[current].Alive then
				current = nil
				goal[index] = nil
			end
			if t >= nextThink[index] or current == nil then
				nextThink[index] = t + math.max(racer.Reaction, 0.05)
				local best: number? = nil
				local bestScore = -math.huge
				for orbIndex, orb in orbs do
					if orb.Alive and orb.Born <= t then
						local distance = (orb.Pos - pos[index]).Magnitude
						if distance <= MinigameConfig.BotReachStuds then
							-- Greed 0: nearest wins. Greed 1: value per stud.
							local score = MinigameConfig.ScoreOrb(racer.Greed, orb.Value, distance)
							if score > bestScore then
								best, bestScore = orbIndex, score
							end
						end
					end
				end
				goal[index] = best
				current = best
			end
			if current then
				local orb = orbs[current]
				local offset = orb.Pos - pos[index]
				local reach = racer.Speed * step
				if offset.Magnitude <= math.max(reach, MinigameConfig.PickupRadius) then
					pos[index] = orb.Pos
					points[index] += orb.Value
					orb.Alive = false
					goal[index] = nil
				else
					pos[index] += offset.Unit * reach
				end
			end
		end
		t += step
	end
	return points
end

return MinigameConfig
