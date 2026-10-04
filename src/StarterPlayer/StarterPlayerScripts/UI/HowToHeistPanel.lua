--[[
	HowToHeistPanel
	---------------
	The HOW TO HEIST card: a UIKit Modal (640 x 480) with four slides, one
	at a time (◀ ▶, dots, GOT IT on the last). Each slide is a live 3D scene
	(UI/HeistScenes: a ViewportFrame + WorldModel built from the game's own
	pedestal, orb, LOCK console and your own avatar, looping a ~3 s clip of
	its rule), then a pink number badge with the title (Display 26) and one
	16 px line:

	  1 GRAB   2 GUARD   3 CATCH   4 LOCK

	Numbers come from HeistConfig (CarrySeconds, ShieldSeconds). The scene
	takes up to 600 x 250 and shrinks first, so the card fits a phone
	(390 px tall after the UIScale).

	The scenes are built when the card opens and destroyed when it closes;
	only the slide on screen ticks.

	Opened automatically once per account right after the first-rebirth
	result card closes (ResultController; TipConfig id "howToHeist"), and
	any time from the HUD's "?" button.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)
local HeistScenes = require(script.Parent.HeistScenes)

local HowToHeistPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(640, 480)
local DISPLAY_ORDER = 118 -- over the HUD and Fuse panel, under Toasts (120)
local SCENE_MAX = Vector2.new(600, 250)
local TITLE_HEIGHT = 36
local LINE_HEIGHT = 40
local NAV_HEIGHT = 52
local TEXT_GAP = 6
local BADGE_SIZE = 32
local ARROW_SIZE = 52
local DOT_SIZE = 12

type Slide = { Title: string, Line: string }

local modal: UIKit.Modal
local sceneArea: Frame
local titleLabel: TextLabel
local badgeLabel: TextLabel
local lineLabel: TextLabel
local dots: { Frame } = {}
local prevButton: TextButton
local nextButton: TextButton
local gotItHolder: Frame
local nextHolder: Frame
local slides: { Slide }
local index = 1

local scenes: { HeistScenes.Scene } = {}
local sceneClock = 0
local tickConnection: RBXScriptConnection? = nil

--[[ Slides --------------------------------------------------------------------- ]]

local function buildSlides(): { Slide }
	return {
		{
			Title = "GRAB",
			Line = ("Hold E on someone's pedestal. Run it home in %ds and it's yours."):format(HeistConfig.CarrySeconds),
		},
		{
			Title = "GUARD",
			Line = "Stand next to your item. Nobody can steal it while you're there.",
		},
		{
			Title = "CATCH",
			Line = "A thief has your item? Touch them and it flies back.",
		},
		{
			Title = "LOCK",
			Line = ("Run to the LOCK button inside your gate. Nobody gets in for %ds."):format(HeistConfig.ShieldSeconds),
		},
	}
end

--[[ Scenes ----------------------------------------------------------------------- ]]

local function destroyScenes()
	if tickConnection then
		tickConnection:Disconnect()
		tickConnection = nil
	end
	for _, scene in scenes do
		scene.Destroy()
	end
	scenes = {}
end

-- One ViewportFrame per slide; only the one on screen is visible and ticks.
local function buildScenes()
	destroyScenes()
	for i = 1, #slides do
		local holder = Instance.new("Frame")
		holder.Name = "Slide" .. i
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.fromScale(1, 1)
		holder.ZIndex = sceneArea.ZIndex
		holder.Visible = false
		holder.Parent = sceneArea
		local scene = HeistScenes.Build(i, holder)
		local destroy = scene.Destroy
		scenes[i] = {
			Frame = scene.Frame,
			Step = scene.Step,
			Destroy = function()
				destroy()
				holder:Destroy()
			end,
		}
	end
	tickConnection = RunService.RenderStepped:Connect(function(dt: number)
		sceneClock += dt
		local scene = scenes[index]
		if scene then
			scene.Step(sceneClock)
		end
	end)
end

--[[ Paging --------------------------------------------------------------------- ]]

local function show(newIndex: number)
	index = math.clamp(newIndex, 1, #slides)
	sceneClock = 0
	for i, scene in scenes do
		local holder = scene.Frame.Parent
		if holder and holder:IsA("GuiObject") then
			holder.Visible = i == index
		end
	end
	local slide = slides[index]
	badgeLabel.Text = tostring(index)
	titleLabel.Text = slide.Title
	lineLabel.Text = slide.Line
	for i, dot in dots do
		dot.BackgroundColor3 = if i == index then Colors.Text else Colors.Faint
	end
	local last = index == #slides
	UIKit.SetButton(prevButton, {
		Style = if index > 1 then "Blue" else "Disabled",
		TextColor3 = if index > 1 then Colors.Text else Colors.Muted,
	})
	nextHolder.Visible = not last
	gotItHolder.Visible = last
	nextButton.Visible = not last
end

--[[ Build ---------------------------------------------------------------------- ]]

local function build()
	modal = UIKit.Modal({
		Name = "HowToHeist",
		Title = "HOW TO HEIST",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.MythicBannerLeft,
		OnClose = destroyScenes,
	})
	local content = modal.Content
	local textBlock = TITLE_HEIGHT + LINE_HEIGHT + NAV_HEIGHT + TEXT_GAP * 3 + UITheme.ShadowOffset

	-- The scene: up to 600 x 250, shrinking first on a short screen.
	sceneArea = Instance.new("Frame")
	sceneArea.Name = "SceneArea"
	sceneArea.AnchorPoint = Vector2.new(0.5, 0)
	sceneArea.Position = UDim2.fromScale(0.5, 0)
	sceneArea.Size = UDim2.new(1, 0, 1, -textBlock)
	sceneArea.BackgroundColor3 = Colors.Panel2
	sceneArea.ZIndex = content.ZIndex + 1
	sceneArea.Parent = content
	UIKit.Corner(sceneArea, UITheme.Radius.Row)
	UIKit.Stroke(sceneArea, 2)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = SCENE_MAX
	constraint.Parent = sceneArea

	-- Pink number badge + title, centred under the scene.
	local titleRow = Instance.new("Frame")
	titleRow.Name = "TitleRow"
	titleRow.BackgroundTransparency = 1
	titleRow.AnchorPoint = Vector2.new(0, 1)
	titleRow.Position = UDim2.new(0, 0, 1, -(LINE_HEIGHT + NAV_HEIGHT + TEXT_GAP * 2 + UITheme.ShadowOffset))
	titleRow.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
	titleRow.ZIndex = content.ZIndex + 1
	titleRow.Parent = content
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, 10)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = titleRow

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	badge.BackgroundColor3 = Colors.White
	badge.LayoutOrder = 1
	badge.ZIndex = titleRow.ZIndex
	badge.Parent = titleRow
	UIKit.Corner(badge, 999)
	UIKit.Stroke(badge, 3)
	UIKit.PairGradient(badge, UITheme.Gradients.Shield)
	badgeLabel = UIKit.Label({
		Name = "Number",
		Text = "1",
		Font = Fonts.Display,
		TextSize = 20,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		ZIndex = badge.ZIndex + 1,
		Parent = badge,
	})
	titleLabel = UIKit.Label({
		Name = "SlideTitle",
		Font = Fonts.Display,
		TextSize = 26,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, TITLE_HEIGHT),
		LayoutOrder = 2,
		Stroke = UITheme.Stroke.Text,
		ZIndex = titleRow.ZIndex,
		Parent = titleRow,
	})
	lineLabel = UIKit.Label({
		Name = "SlideLine",
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -(NAV_HEIGHT + TEXT_GAP + UITheme.ShadowOffset)),
		Size = UDim2.new(1, -16, 0, LINE_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = content.ZIndex + 1,
		Parent = content,
	})

	local nav = Instance.new("Frame")
	nav.Name = "Nav"
	nav.BackgroundTransparency = 1
	nav.AnchorPoint = Vector2.new(0, 1)
	nav.Position = UDim2.new(0, 0, 1, -UITheme.ShadowOffset)
	nav.Size = UDim2.new(1, 0, 0, NAV_HEIGHT)
	nav.ZIndex = content.ZIndex + 1
	nav.Parent = content

	prevButton = UIKit.Button({
		Name = "Prev",
		Parent = nav,
		Style = "Blue",
		Text = "◀",
		TextSize = 22,
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			show(index - 1)
		end,
	})
	local dotRow = Instance.new("Frame")
	dotRow.Name = "Dots"
	dotRow.BackgroundTransparency = 1
	dotRow.AnchorPoint = Vector2.new(0.5, 0.5)
	dotRow.Position = UDim2.fromScale(0.5, 0.5)
	dotRow.Size = UDim2.fromOffset(4 * (DOT_SIZE + 10), DOT_SIZE)
	dotRow.ZIndex = nav.ZIndex
	dotRow.Parent = nav
	local dotLayout = Instance.new("UIListLayout")
	dotLayout.FillDirection = Enum.FillDirection.Horizontal
	dotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotLayout.Padding = UDim.new(0, 10)
	dotLayout.Parent = dotRow

	slides = buildSlides()
	for i = 1, #slides do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = Colors.Faint
		dot.LayoutOrder = i
		dot.ZIndex = nav.ZIndex
		dot.Parent = dotRow
		UIKit.Corner(dot, 999)
		table.insert(dots, dot)
	end

	local nextBody, holder = UIKit.Button({
		Name = "Next",
		Parent = nav,
		Style = "Blue",
		Text = "NEXT ▶",
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(120, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			show(index + 1)
		end,
	})
	nextButton, nextHolder = nextBody, holder
	local _, gotIt = UIKit.Button({
		Name = "GotIt",
		Parent = nav,
		Style = "Green",
		Text = "GOT IT",
		TextSize = 20,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(140, ARROW_SIZE),
		ZIndex = nav.ZIndex,
		OnClick = function()
			modal.Close()
		end,
	})
	gotItHolder = gotIt
	gotItHolder.Visible = false
end

--[[ Public --------------------------------------------------------------------- ]]

-- Opens on the first slide, building the four scenes.
function HowToHeistPanel.Open()
	if not modal then
		return
	end
	buildScenes()
	show(1)
	modal.Open()
end

function HowToHeistPanel.Init()
	build()
	-- The rigs are built from HumanoidDescriptions (network); start now so
	-- the first open has them.
	HeistScenes.Preload()
end

return HowToHeistPanel
