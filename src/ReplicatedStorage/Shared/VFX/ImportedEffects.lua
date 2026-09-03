-- Plays a short one-shot burst from a pre-built, imported VFX object (a
-- BasePart with one or more ParticleEmitter descendants, either directly on
-- the part or nested under an Attachment) - e.g. the LevelingUp/Explosion
-- pieces extracted from a user-supplied Toolbox pack. Clones fresh every
-- call, so concurrent plays never fight over the same emitter instances,
-- positions the clone, runs every ParticleEmitter descendant for a short
-- window, then cleans up automatically once the last particle would have
-- died. Lives in ReplicatedStorage (not StarterPlayerScripts/Effects) since
-- both server code (world-visible pad VFX) and client code (RevealEffects)
-- need it.
local Debris = game:GetService("Debris")

local ImportedEffects = {}

local DEFAULT_BURST_SECONDS = 0.3
local CLEANUP_BUFFER_SECONDS = 0.5

export type PlayOptions = {
	-- Multiplies Rate and Speed on every ParticleEmitter descendant (not
	-- Color/Size/Transparency curves - those define the effect's actual
	-- look, not its scale). 1 = play exactly as authored in the source pack.
	Scale: number?,
	-- How long emission stays on before being switched off; existing
	-- particles still live out their own Lifetime after that. Defaults to a
	-- short burst rather than the source pack's original continuous Rate.
	BurstSeconds: number?,
}

function ImportedEffects.Play(effectTemplate: BasePart, cframe: CFrame, parent: Instance, options: PlayOptions?)
	local scale = (options and options.Scale) or 1
	local burstSeconds = (options and options.BurstSeconds) or DEFAULT_BURST_SECONDS

	local clone = effectTemplate:Clone()
	clone.CFrame = cframe
	clone.Anchored = true
	clone.CanCollide = false
	clone.Transparency = 1
	clone.Parent = parent

	local maxLifetime = 0
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			if scale ~= 1 then
				descendant.Rate *= scale
				local speed = descendant.Speed
				descendant.Speed = NumberRange.new(speed.Min * scale, speed.Max * scale)
			end
			descendant.Enabled = true
			maxLifetime = math.max(maxLifetime, descendant.Lifetime.Max)
		end
	end

	task.delay(burstSeconds, function()
		if clone.Parent then
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("ParticleEmitter") then
					descendant.Enabled = false
				end
			end
		end
	end)

	Debris:AddItem(clone, burstSeconds + maxLifetime + CLEANUP_BUFFER_SECONDS)
end

return ImportedEffects
