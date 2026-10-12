--!strict
--[[
	WeaponViewport
	--------------
	A ViewportFrame showing the real WeaponKit model, slowly turning, lit
	with UITheme (viewports ignore world lights, so the look comes from the
	HeistScene tokens). Used by the weapon bar and the unlock card.

	  Create(weaponId, parent, props?)  -> ViewportFrame (fills its parent;
	                                       transparent background)
	  SetDim(viewport, dim)             a dimmed, greyed model (locked slots,
	                                    the bar while you carry an orb)

	One shared Heartbeat turns every live viewport; a destroyed one drops out
	by itself.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local WeaponKit = require(ReplicatedStorage.Shared.Modules.WeaponKit)

local WeaponViewport = {}

local Colors = UITheme.Colors
local Scene = UITheme.HeistScene

local FIELD_OF_VIEW = 35
local SPIN_SPEED = 0.9 -- radians per second
local FIT = 1.08 -- a little air round the model

type Entry = {
	Model: Model,
	Tilt: CFrame,
	Center: Vector3,
	Phase: number,
}

local live: { [ViewportFrame]: Entry } = {}
local connection: RBXScriptConnection? = nil

local function place(entry: Entry, angle: number)
	-- Turn about the model's own centre: centre to the origin, then spin
	-- (about the screen's vertical), then the display tilt.
	entry.Model:PivotTo(CFrame.Angles(0, angle, 0) * entry.Tilt * CFrame.new(-entry.Center))
end

local function step()
	local now = os.clock()
	for viewport, entry in live do
		if not viewport:IsDescendantOf(game) then
			live[viewport] = nil
		else
			place(entry, entry.Phase + now * SPIN_SPEED)
		end
	end
	if next(live) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

function WeaponViewport.Create(weaponId: string, parent: Instance, props: { Name: string?, ZIndex: number?, Phase: number? }?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = if props and props.Name then props.Name else "Weapon"
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Scene.Ambient
	viewport.LightColor = Scene.LightColor
	viewport.LightDirection = Scene.LightDirection
	if props and props.ZIndex then
		viewport.ZIndex = props.ZIndex
	end

	local model = WeaponKit.BuildModel(weaponId)
	model.Parent = viewport
	-- The bounding box (handle at the origin) gives the centre and a size
	-- to frame; the tilt turns it first, so frame the diagonal.
	local boxCFrame, boxSize = model:GetBoundingBox()
	local radius = boxSize.Magnitude / 2
	local distance = radius / math.sin(math.rad(FIELD_OF_VIEW / 2)) * FIT

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	camera.CFrame = CFrame.new(Vector3.new(0, 0, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = parent

	local entry: Entry = {
		Model = model,
		Tilt = WeaponKit.GetDisplayTilt(weaponId),
		Center = boxCFrame.Position,
		Phase = if props and props.Phase then props.Phase else 0,
	}
	live[viewport] = entry
	place(entry, entry.Phase)
	if not connection then
		connection = RunService.Heartbeat:Connect(step)
	end
	return viewport
end

-- dim: 0 = full colour, 1 = nearly gone. Greys the model too.
function WeaponViewport.SetDim(viewport: ViewportFrame, dim: number)
	viewport.ImageTransparency = dim * 0.7
	viewport.ImageColor3 = Colors.White:Lerp(Colors.Faint, math.clamp(dim * 1.4, 0, 1))
end

return WeaponViewport
