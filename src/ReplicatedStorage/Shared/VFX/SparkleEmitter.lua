-- Factory for the ambient "sparkle" ParticleEmitter used across the sci-fi
-- fusion lab aesthetic. Returns a fresh, unparented instance
-- on every call rather than one shared instance, since a ParticleEmitter can
-- only live under a single parent at a time and every pad wants its own.
local SparkleEmitter = {}

export type SparkleEmitterOptions = {
	Color: Color3?,
	Rate: number?,
}

local DEFAULT_COLOR = Color3.fromRGB(120, 220, 255)
local DEFAULT_RATE = 8

function SparkleEmitter.Create(options: SparkleEmitterOptions?): ParticleEmitter
	options = options or {}
	local color = options.Color or DEFAULT_COLOR

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SparkleEmitter"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = options.Rate or DEFAULT_RATE
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 2, 0)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-30, 30)

	return emitter
end

return SparkleEmitter
