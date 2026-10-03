--!strict
--[[
	PortalKit
	---------
	The Rebirth Portal in the plot's back-right corner (PlotLayout.RebirthPortal),
	built by TycoonService on claim. A Model "RebirthPortal" facing +Z:

	  * Base     8-wide cylinder, Structure, with a BillboardKit pad face ring
	             in AccentRebirth on top (never a flat Neon disc).
	  * Pillars  two StructureLight posts with a Neon AccentRebirth strip on
	             each inner face, and a Beam across their tops.
	  * Sheet    an invisible pane between the pillars with a SurfaceGui on
	             both faces: a "Swirl" Frame with a UIGradient through
	             UITheme.RebirthPortal. Tagged FT_PortalSwirl; clients rotate
	             the gradient and set its opacity (WorldAnimationController).
	  * Light    AccentRebirth PointLight.
	  * RebirthPrompt  owner-only; the client opens the Rebirth panel from it
	             (it never calls the server).

	The server only sets the model's Ready attribute and the light's
	brightness (SetReady); everything that moves is client-side.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local PortalKit = {}

local World = UITheme.World

PortalKit.MODEL_NAME = "RebirthPortal"
PortalKit.PROMPT_NAME = "RebirthPrompt"
PortalKit.SWIRL_TAG = "FT_PortalSwirl"
PortalKit.READY_ATTRIBUTE = "Ready"

local function buildSwirlFace(sheet: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Swirl" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PlotLayout.RebirthPortal.SheetPixelsPerStud
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = sheet

	local swirl = Instance.new("Frame")
	swirl.Name = "Swirl"
	swirl.BackgroundColor3 = UITheme.Colors.White
	swirl.BackgroundTransparency = PlotLayout.RebirthPortal.SwirlIdleTransparency
	swirl.BorderSizePixel = 0
	swirl.Size = UDim2.fromScale(1, 1)
	swirl.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = swirl

	local stops = UITheme.RebirthPortal
	local gradient = Instance.new("UIGradient")
	gradient.Name = "SwirlGradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, stops[1]),
		ColorSequenceKeypoint.new(0.5, stops[2]),
		ColorSequenceKeypoint.new(1, stops[3]),
	})
	gradient.Parent = swirl
end

-- Builds the portal into `parent` (complete, then parented) and returns it.
function PortalKit.Build(origin: CFrame, parent: Instance): Model
	local P = PlotLayout.RebirthPortal
	local model = Instance.new("Model")
	model.Name = PortalKit.MODEL_NAME
	model:SetAttribute(PortalKit.READY_ATTRIBUTE, false)

	local base = PartKit.Cylinder({
		Name = "Base",
		Center = PartKit.At(origin, P.Position, P.BaseHeight / 2),
		Height = P.BaseHeight,
		Diameter = P.BaseDiameter,
		Color = World.Structure,
		Parent = model,
	})
	local top = PartKit.At(origin, P.Position, P.BaseHeight)
	local face = BillboardKit.BuildPadFace(model, top, P.BaseDiameter, World.AccentRebirth, nil)
	local faceLight = face:FindFirstChild("FaceLight")
	if faceLight then
		faceLight:Destroy() -- the portal's own light covers it
	end

	local pillarY = P.BaseHeight + P.PillarSize.Y / 2
	for _, side in { -1, 1 } do
		local pillar = PartKit.Part({
			Name = "Pillar",
			Size = P.PillarSize,
			CFrame = top * CFrame.new(side * P.PillarX, P.PillarSize.Y / 2, 0),
			Color = World.StructureLight,
			Parent = model,
		})
		-- Neon strip on the inner face (toward the sheet).
		local edge = PartKit.Part({
			Name = "Edge",
			Size = Vector3.new(P.EdgeDepth, P.PillarSize.Y, P.EdgeWidth),
			CFrame = pillar.CFrame * CFrame.new(-side * (P.PillarSize.X / 2 + P.EdgeDepth / 2), 0, 0),
			Color = World.AccentRebirth,
			Material = Enum.Material.Neon,
			Parent = pillar,
		})
		PartKit.MakeDecorative(edge)
	end
	PartKit.Part({
		Name = "Beam",
		Size = P.BeamSize,
		CFrame = top * CFrame.new(0, P.PillarSize.Y + P.BeamSize.Y / 2, 0),
		Color = World.StructureLight,
		Parent = model,
	})

	local sheet = PartKit.Part({
		Name = "Sheet",
		Size = P.SheetSize,
		CFrame = PartKit.At(origin, P.Position, pillarY),
		Color = World.AccentRebirth,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = model,
	})
	buildSwirlFace(sheet, Enum.NormalId.Front)
	buildSwirlFace(sheet, Enum.NormalId.Back)
	sheet:AddTag(PortalKit.SWIRL_TAG)

	local light = Instance.new("PointLight")
	light.Name = "PortalLight"
	light.Color = World.AccentRebirth
	light.Range = P.LightRange
	light.Brightness = P.LightBrightnessIdle
	light.Parent = sheet

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PortalKit.PROMPT_NAME
	prompt.ActionText = "Rebirth"
	prompt.ObjectText = "Portal"
	prompt.HoldDuration = P.PromptHoldSeconds
	prompt.MaxActivationDistance = P.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute(BillboardKit.OWNER_ONLY_ATTRIBUTE, true)
	prompt.Parent = base

	model.PrimaryPart = base
	model.Parent = parent
	return model
end

-- Server: flips the portal between "not ready" and "ready". Clients read
-- the Ready attribute to animate the swirl and the ring.
function PortalKit.SetReady(model: Model, ready: boolean)
	if model:GetAttribute(PortalKit.READY_ATTRIBUTE) == ready then
		return
	end
	model:SetAttribute(PortalKit.READY_ATTRIBUTE, ready)
	local sheet = model:FindFirstChild("Sheet")
	local light = sheet and sheet:FindFirstChild("PortalLight")
	if light and light:IsA("PointLight") then
		local P = PlotLayout.RebirthPortal
		light.Brightness = if ready then P.LightBrightnessReady else P.LightBrightnessIdle
	end
end

return PortalKit
