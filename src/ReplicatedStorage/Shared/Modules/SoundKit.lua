--!strict
--[[
	SoundKit
	--------
	The one way to play a sound (slots in SoundConfig):

	  SoundKit.Play(slot, parent?, options?)  -> Sound?
	      A new Sound per play, parented to `parent` (positional) or
	      SoundService (2D), Debris-cleaned. An empty Id, an unknown slot or
	      an Id that failed to load plays nothing and returns nil.
	  SoundKit.Preload()   (client, once at boot)
	      ContentProvider:PreloadAsync over every slot with a status
	      callback; a failed Id warns ONCE ("SoundKit: <slot> failed to load
	      <id>") and that slot is silent from then on.
]]
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local SoundKit = {}

export type PlayOptions = {
	PlaybackSpeed: number?,
	Volume: number?, -- multiplies the slot's volume
	Lifetime: number?, -- seconds before cleanup (default 6)
}

local DEFAULT_LIFETIME = 6

-- Ids that failed to load (silenced) and slots already warned about.
local failedIds: { [string]: boolean } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(slot: string, id: string)
	if not warned[slot] then
		warned[slot] = true
		warn(("SoundKit: %s failed to load %s"):format(slot, id))
	end
end

function SoundKit.Play(slot: string, parent: Instance?, options: PlayOptions?): Sound?
	local config = SoundConfig.Slots[slot]
	if not config or config.Id == "" or failedIds[config.Id] then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = slot
	sound.SoundId = config.Id
	sound.Volume = config.Volume * (if options and options.Volume then options.Volume else 1)
	sound.PlaybackSpeed = if options and options.PlaybackSpeed then options.PlaybackSpeed else 1
	sound.Parent = parent or SoundService
	sound:Play()
	Debris:AddItem(sound, if options and options.Lifetime then options.Lifetime else DEFAULT_LIFETIME)
	return sound
end

-- Client only (PreloadAsync does nothing useful on the server).
function SoundKit.Preload()
	if not RunService:IsClient() then
		return
	end
	local slotsById: { [string]: { string } } = {}
	local assets: { Sound } = {}
	for slot, config in SoundConfig.Slots do
		if config.Id ~= "" then
			if not slotsById[config.Id] then
				slotsById[config.Id] = {}
				local probe = Instance.new("Sound")
				probe.SoundId = config.Id
				table.insert(assets, probe)
			end
			table.insert(slotsById[config.Id], slot)
		end
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets, function(contentId: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Failure then
					failedIds[contentId] = true
					local slots = slotsById[contentId]
					if slots then
						for _, slot in slots do
							warnOnce(slot, contentId)
						end
					end
				end
			end)
		end)
		if not ok then
			warn(("SoundKit: preload failed (%s)"):format(tostring(err)))
		end
		for _, probe in assets do
			probe:Destroy()
		end
	end)
end

return SoundKit
