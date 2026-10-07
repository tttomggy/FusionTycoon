--!strict
--[[
	TutorialExplain
	---------------
	Tutorial 3's EXPLAIN CARD: before a step that introduces something new
	(never the claim) one big, simple card opens, then the banner, path and
	hand take over:

	  * a large image of the real thing: a ViewportFrame with a clone of the
	    world object (generator, pad, pedestal, machine), or UIKit.TierOrbs
	    (Fuse: Common + Common -> Rare), or the big icon when there is no model;
	  * a title;
	  * one or two short sentences at >= 22 px saying what it is for;
	  * a big green OK (the only way out, ✕ and a tap outside count as OK).

	  Show(card, model?, onOk)   opens it; OK calls onOk once
	  Close()                    closes without calling onOk
	  IsOpen() / GetBody() / PressOk()   /selftest
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local UIKit = require(script.Parent.UIKit)

local TutorialExplain = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(520, 440)
local DISPLAY_ORDER = 166 -- over the "?" cards (165), under the hand (175)
local IMAGE_HEIGHT = 170
local BODY_TEXT = 24
local BODY_MIN = 22
local OK_SIZE = Vector2.new(240, 64)

local modal: UIKit.Modal? = nil
local imageArea: Frame
local bodyLabel: TextLabel
local okButton: TextButton
local onOk: (() -> ())? = nil
local closingByOk = false

local function finish()
	local callback = onOk
	onOk = nil
	if callback then
		callback()
	end
end

local function clearImage()
	for _, child in imageArea:GetChildren() do
		child:Destroy()
	end
end

-- A clone of a world object lit in a ViewportFrame; nil when it can't be
-- drawn (not built yet), so the caller falls back to the icon.
local function modelView(source: Instance): ViewportFrame?
	local copy = source:Clone()
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("ProximityPrompt") or descendant:IsA("BillboardGui") or descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
	local center: Vector3
	local extent: number
	if copy:IsA("Model") then
		local cframe, size = copy:GetBoundingBox()
		center, extent = cframe.Position, size.Magnitude
	elseif copy:IsA("BasePart") then
		center, extent = copy.Position, copy.Size.Magnitude
	else
		copy:Destroy()
		return nil
	end
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Model"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Colors.White
	viewport.LightColor = Colors.White
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.6)
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	copy.Parent = world
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = math.max(extent, 1) * 1.15
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0.8, 0.65, 1).Unit * distance, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function buildImage(card: TutorialConfig.ExplainCard, model: Instance?)
	clearImage()
	if card.Orbs then
		-- "Common + Common → Rare" in tier orbs and symbols.
		local row = Instance.new("Frame")
		row.Name = "Orbs"
		row.BackgroundTransparency = 1
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.fromScale(0.5, 0.5)
		row.Size = UDim2.new(1, 0, 0, 90)
		row.Parent = imageArea
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 14)
		layout.Parent = row
		for index, part in card.Orbs do
			if UITheme.TierOrb[part] then
				local orb = UIKit.TierOrb(part, 84)
				orb.LayoutOrder = index
				orb.Parent = row
			else
				UIKit.Label({
					Name = "Symbol",
					Text = part,
					Font = Fonts.Display,
					TextSize = 48,
					Size = UDim2.fromOffset(44, 84),
					TextXAlignment = Enum.TextXAlignment.Center,
					LayoutOrder = index,
					Stroke = UITheme.Stroke.Text,
					Parent = row,
				})
			end
		end
		return
	end
	local viewport = if model then modelView(model) else nil
	if viewport then
		viewport.Parent = imageArea
		return
	end
	UIKit.Label({
		Name = "Icon",
		Text = card.Icon,
		Font = Fonts.Display,
		TextSize = 120,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = imageArea,
	})
end

local function build()
	local m = UIKit.Modal({
		Name = "TutorialExplain",
		Title = "",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = MAX_SIZE,
		FitContent = true,
		HeaderTop = UITheme.Gradients.Teal.Bottom,
		-- ✕ or a tap outside counts as OK: the tutorial keeps going.
		OnClose = function()
			if not closingByOk then
				finish()
			end
		end,
	})
	modal = m
	local content = m.Content
	imageArea = Instance.new("Frame")
	imageArea.Name = "Image"
	imageArea.BackgroundTransparency = 1
	imageArea.Position = UDim2.fromOffset(8, 0)
	imageArea.Size = UDim2.new(1, -16, 0, IMAGE_HEIGHT)
	imageArea.ZIndex = content.ZIndex + 1
	imageArea.Parent = content

	bodyLabel = UIKit.Label({
		Name = "Body",
		Font = Fonts.BodyHeavy,
		TextSize = BODY_TEXT,
		Position = UDim2.fromOffset(16, IMAGE_HEIGHT + 6),
		Size = UDim2.new(1, -32, 1, -(IMAGE_HEIGHT + OK_SIZE.Y + 26 + UITheme.ShadowOffset)),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})
	UIKit.FitText(bodyLabel, BODY_TEXT, BODY_MIN)

	okButton = UIKit.Button({
		Name = "Ok",
		Parent = content,
		Style = "Green",
		Text = "OK",
		TextSize = 32,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(UITheme.ShadowOffset + 6)),
		Size = UDim2.fromOffset(OK_SIZE.X, OK_SIZE.Y),
		ZIndex = content.ZIndex + 1,
		OnClick = function()
			closingByOk = true
			m.Close()
			closingByOk = false
			finish()
		end,
	})
end

-- Opens the card. `model` is the world object to draw (nil: the icon).
function TutorialExplain.Show(card: TutorialConfig.ExplainCard, model: Instance?, callback: () -> ())
	if not modal then
		build()
	end
	local m = modal :: UIKit.Modal
	onOk = callback
	m.Title.Text = card.Title:upper()
	bodyLabel.Text = card.Body
	buildImage(card, model)
	if not m.IsOpen() then
		m.Open()
	end
end

function TutorialExplain.Close()
	local m = modal
	if m and m.IsOpen() then
		closingByOk = true
		m.Close()
		closingByOk = false
	end
	onOk = nil
end

function TutorialExplain.IsOpen(): boolean
	local m = modal
	return m ~= nil and m.IsOpen()
end

-- /selftest: the body text label (size >= 22) and "tap OK".
function TutorialExplain.GetBody(): TextLabel?
	return if modal then bodyLabel else nil
end

function TutorialExplain.GetOkButton(): TextButton?
	return if modal then okButton else nil
end

function TutorialExplain.PressOk()
	local m = modal
	if m and m.IsOpen() then
		closingByOk = true
		m.Close()
		closingByOk = false
		finish()
	end
end

function TutorialExplain.Init()
	build()
end

return TutorialExplain
