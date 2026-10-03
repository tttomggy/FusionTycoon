--!strict
--[[
	GeneratorKit
	------------
	The five generators in the plot's back-corner bays (PlotLayout.GENERATORS),
	built by TycoonService. Each is a Model "Generator_<id>" facing +Z:

	  * Body   footprint x height, Structure SmoothPlastic, bottom at y 0.
	  * Band   a thin ring at 40% height in the tier colour: matte below
	           level 10, Neon from 10, plus a PointLight at max level.
	  * Core   the pedestal-orb look (Glass ball around a Neon ball), tagged
	           FT_Hover so clients spin and bob it.
	  * Screen a SurfaceGui on the Body's +Z face: name and "LV n" / "MAX",
	           or a lock while locked.
	  * GeneratorLabel  owner-only "LOCKED" / "BUY" panel (BillboardKit).
	  * GeneratorPrompt owner-only Buy / Upgrade prompt; the client fires
	           the existing RequestUpgrade remote from it.

	The parts are built once and restyled in place by SetState (locked ghost,
	buy ghost, owned), so client references (the Body the purchase pop scales,
	the hover-tracked Core) stay valid across state changes.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)

local GeneratorKit = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local World = UITheme.World

GeneratorKit.MODEL_PREFIX = "Generator_"
GeneratorKit.PROMPT_NAME = "GeneratorPrompt"
GeneratorKit.ID_ATTRIBUTE = "GeneratorId"

type Parts = {
	Body: BasePart,
	Band: BasePart,
	Light: PointLight,
	Outer: BasePart,
	Inner: BasePart,
	NameText: TextLabel,
	LevelText: TextLabel,
	Lock: Frame,
	Label: BillboardKit.GeneratorLabel,
	Prompt: ProximityPrompt,
}

-- Built parts per model, so SetState never searches by name.
local partsByModel: { [Model]: Parts } = {}

function GeneratorKit.GetModelName(id: string): string
	return GeneratorKit.MODEL_PREFIX .. id
end

function GeneratorKit.GetTierColor(tier: string): Color3
	return FusionConfig.TierAccentColors[tier] or World.StructureLight
end

-- The core's centre, relative to the Body's centre.
function GeneratorKit.GetCoreOffset(spot: PlotLayout.GeneratorSpot): Vector3
	local diameter = spot.Footprint * PlotLayout.Generator.CoreScale
	return Vector3.new(0, spot.Height / 2 + diameter / 2, 0)
end

--[[ Screen ------------------------------------------------------------------ ]]

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function newText(parent: Instance, name: string, font: Font, color: Color3, y: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextColor3 = color
	text.TextScaled = true
	text.Position = UDim2.fromScale(0, y)
	text.Size = UDim2.fromScale(1, height)
	text.Parent = parent
	return text
end

-- A padlock drawn from frames (UITheme.Icons.Lock has no asset yet).
local function buildLock(parent: Instance): Frame
	local lock = Instance.new("Frame")
	lock.Name = "Lock"
	lock.BackgroundTransparency = 1
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.5, 0.5)
	lock.Size = UDim2.fromScale(0.8, 0.8)
	lock.SizeConstraint = Enum.SizeConstraint.RelativeYY
	lock.Parent = parent

	local shackle = Instance.new("Frame")
	shackle.Name = "Shackle"
	shackle.BackgroundTransparency = 1
	shackle.AnchorPoint = Vector2.new(0.5, 0)
	shackle.Position = UDim2.fromScale(0.5, 0)
	shackle.Size = UDim2.fromScale(0.5, 0.6)
	shackle.Parent = lock
	corner(shackle, UDim.new(0.5, 0))
	local stroke = Instance.new("UIStroke")
	stroke.Color = Colors.Faint
	stroke.Thickness = 4
	stroke.Parent = shackle

	local body = Instance.new("Frame")
	body.Name = "LockBody"
	body.BackgroundColor3 = Colors.Faint
	body.BorderSizePixel = 0
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromScale(0.8, 0.55)
	body.Parent = lock
	corner(body, UDim.new(0.2, 0))
	return lock
end

-- Name (Body, Muted) over a dark Ink panel with the level (Display, Cash),
-- kept above the band. Returns (name, level, lock).
local function buildScreen(body: BasePart, displayName: string): (TextLabel, TextLabel, Frame)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Back -- the +Z face, toward the lab centre
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PlotLayout.Generator.ScreenPixelsPerStud
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = body

	local name = newText(gui, "Name", Fonts.Body, Colors.Muted, 0.06, 0.12)
	name.Position = UDim2.fromScale(0.08, 0.06)
	name.Size = UDim2.fromScale(0.84, 0.12)
	name.Text = displayName

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Colors.Ink
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromScale(0.12, 0.2)
	panel.Size = UDim2.fromScale(0.76, 0.3)
	panel.Parent = gui
	corner(panel, UDim.new(0.18, 0))

	local level = newText(panel, "Level", Fonts.Display, Colors.Cash, 0.1, 0.8)
	return name, level, buildLock(panel)
end

--[[ Build ------------------------------------------------------------------- ]]

local function newPrompt(body: BasePart, id: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = GeneratorKit.PROMPT_NAME
	prompt.MaxActivationDistance = PlotLayout.Generator.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = false
	prompt:SetAttribute(GeneratorKit.ID_ATTRIBUTE, id)
	prompt:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	prompt.Parent = body
	return prompt
end

-- Builds generator `id` at its PlotLayout spot and parents it to `parent`
-- (complete, last). Call SetState right after to give it its look.
function GeneratorKit.Build(origin: CFrame, id: string, parent: Instance): Model?
	local spot = PlotLayout.GENERATORS[id]
	local generator = TycoonConfig.GetGeneratorById(id)
	if not spot or not generator then
		warn(("GeneratorKit: no layout or config for generator %s"):format(id))
		return nil
	end
	local g = PlotLayout.Generator
	local tierColor = GeneratorKit.GetTierColor(generator.Tier)

	local model = Instance.new("Model")
	model.Name = GeneratorKit.GetModelName(id)
	model:SetAttribute(GeneratorKit.ID_ATTRIBUTE, id)

	local body = PartKit.Part({
		Name = "Body",
		Size = Vector3.new(spot.Footprint, spot.Height, spot.Footprint),
		CFrame = PartKit.At(origin, spot.Position, spot.Height / 2),
		Color = World.Structure,
		Parent = model,
	})

	local bandWidth = spot.Footprint + g.BandInflate
	local band = PartKit.Part({
		Name = "Band",
		Size = Vector3.new(bandWidth, g.BandHeight, bandWidth),
		CFrame = body.CFrame * CFrame.new(0, -spot.Height / 2 + spot.Height * g.BandAt, 0),
		Color = tierColor,
		Parent = model,
	})
	PartKit.MakeDecorative(band)
	local light = Instance.new("PointLight")
	light.Name = "MaxLight"
	light.Color = tierColor
	light.Range = g.MaxLightRange
	light.Brightness = g.MaxLightBrightness
	light.Enabled = false
	light.Parent = band

	local coreCenter = body.CFrame * CFrame.new(GeneratorKit.GetCoreOffset(spot))
	local diameter = spot.Footprint * g.CoreScale
	local core = Instance.new("Model")
	core.Name = "Core"
	local outer = PartKit.Part({
		Name = "Outer",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter,
		CFrame = coreCenter,
		Color = tierColor,
		Material = Enum.Material.Glass,
		Transparency = g.CoreTransparency,
		Parent = core,
	})
	PartKit.MakeDecorative(outer)
	local inner = PartKit.Part({
		Name = "Inner",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * diameter * g.CoreInnerScale,
		CFrame = coreCenter,
		Color = tierColor,
		Material = Enum.Material.Neon,
		Parent = core,
	})
	PartKit.MakeDecorative(inner)
	core.PrimaryPart = outer
	PartKit.SetHover(core, g.CoreSpinDegPerSec, g.CoreBob, g.CoreBobPeriod, "Bob")
	core.Parent = model

	local nameText, levelText, lock = buildScreen(body, generator.Name)

	local labelOffset = GeneratorKit.GetCoreOffset(spot) + Vector3.new(0, diameter / 2 + g.LabelAboveCore, 0)
	local label = BillboardKit.GeneratorLabel(body, labelOffset, g.LabelMaxDistance)

	partsByModel[model] = {
		Body = body,
		Band = band,
		Light = light,
		Outer = outer,
		Inner = inner,
		NameText = nameText,
		LevelText = levelText,
		Lock = lock,
		Label = label,
		Prompt = newPrompt(body, id),
	}
	model.PrimaryPart = body
	model.Destroying:Connect(function()
		partsByModel[model] = nil
	end)
	model.Parent = parent
	return model
end

--[[ States ------------------------------------------------------------------ ]]

local function setGhost(parts: Parts, color: Color3, transparency: number)
	for _, part in { parts.Body, parts.Outer } do
		part.Material = Enum.Material.ForceField
		part.Color = color
		part.Transparency = transparency
	end
	parts.Inner.Transparency = 1
	parts.Band.Transparency = 1
	parts.Light.Enabled = false
end

-- Restyles `model` for `level` (0 = not bought) and `unlocked`. Cheap to
-- call on every sync: it does nothing when neither changed.
function GeneratorKit.SetState(model: Model, level: number, unlocked: boolean)
	local parts = partsByModel[model]
	local id = model:GetAttribute(GeneratorKit.ID_ATTRIBUTE)
	local generator = typeof(id) == "string" and TycoonConfig.GetGeneratorById(id) or nil
	if not parts or not generator then
		return
	end
	local stateKey = ("%d:%s"):format(level, tostring(unlocked))
	if model:GetAttribute("StateKey") == stateKey then
		return
	end
	model:SetAttribute("StateKey", stateKey)
	model:SetAttribute("Level", level)

	local g = PlotLayout.Generator
	local tierColor = GeneratorKit.GetTierColor(generator.Tier)
	local prompt = parts.Prompt

	if not unlocked then
		setGhost(parts, Colors.Faint, g.GhostLockedTransparency)
		parts.LevelText.Visible = false
		parts.Lock.Visible = true
		local requirement = generator.UnlockRequirement
		local required = requirement and TycoonConfig.GetGeneratorById(requirement.GeneratorId)
		local detail = if requirement and required then ("%s LV %d"):format(required.Name, requirement.Level) else ""
		parts.Label.Set("LOCKED", detail, Colors.Muted)
		parts.Label.Gui.Enabled = true
		prompt.Enabled = false
		return
	end

	parts.Lock.Visible = false
	parts.LevelText.Visible = true
	local cost = NumberFormat.Money(TycoonConfig.GetUpgradeCost(generator, level))

	if level <= 0 then
		setGhost(parts, tierColor, g.GhostBuyTransparency)
		parts.LevelText.Text = "LV 0"
		parts.Label.Set("BUY", cost, Colors.Cash)
		parts.Label.Gui.Enabled = true
		prompt.ActionText = "Buy"
		prompt.ObjectText = ("%s · %s"):format(generator.Name, cost)
		prompt.Enabled = true
		return
	end

	-- Owned: the real model.
	local isMax = level >= generator.MaxLevel
	parts.Body.Material = Enum.Material.SmoothPlastic
	parts.Body.Color = World.Structure
	parts.Body.Transparency = 0
	parts.Outer.Material = Enum.Material.Glass
	parts.Outer.Color = tierColor
	parts.Outer.Transparency = g.CoreTransparency
	parts.Inner.Transparency = 0
	parts.Band.Transparency = 0
	parts.Band.Material = if level >= g.NeonFromLevel then Enum.Material.Neon else Enum.Material.SmoothPlastic
	parts.Light.Enabled = isMax
	parts.LevelText.Text = if isMax then "MAX" else ("LV %d"):format(level)
	parts.Label.Gui.Enabled = false
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = if isMax then "MAX" else ("LV %d → %d · %s"):format(level, level + 1, cost)
	prompt.Enabled = not isMax
end

return GeneratorKit
