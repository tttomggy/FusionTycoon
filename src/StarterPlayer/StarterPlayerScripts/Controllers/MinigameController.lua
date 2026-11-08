--!strict
--[[
	MinigameController
	------------------
	The client of ORB RUSH (MinigameService is the server; numbers in
	MinigameConfig, docs/systems/minigames.md). It only renders: the server owns
	every orb, score and prize.

	  * The schedule comes from Workspace attributes (OrbRushPhase / CallAt /
	    StartAt / NextAt / Queued / Max), so a late joiner sees the same call.
	  * The JOIN pill ("ORB RUSH 0:45 / JOIN") sits in the HUD's left column,
	    under whatever the column holds (or beside it when the screen is short;
	    never over a HUD rect: /selftest checks), only during a call and once
	    the progressive HUD has opened the SHOP row. Tapping it queues (the
	    server walks you to the portal); tapping again leaves. A TopStack
	    announcement says "ORB RUSH in 1:00 · win an Epic+ orb!" at the start.
	  * In the round: the 3 · 2 · 1 · GO! countdown, TopStack's mission slot
	    ("ORB RUSH 1:12 · You 34 · #2"), a compact live top 3 in the left column,
	    pop sounds pitched up with the pickup streak, +N floaters in the orb's
	    colour, a light FOV punch on gold, the GOLDEN WAVE line.
	  * Orbs are server parts; their fall from the sky and the scatter arc are
	    animated here (local-only position changes from the FromPos / DropSeconds /
	    Arc attributes).
	  * Results: a centred card (UIKit.Modal, FitContent) with the podium, your
	    place, the prize (the orb itself pops out through the normal pull card, a
	    cash line otherwise), "NEXT ORB RUSH at :22" and CLOSE. No purchase prompt.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local MinigameConfig = require(ReplicatedStorage.Shared.Config.MinigameConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local HudGate = require(script.Parent.Parent.UI.HudGate)
local TopStack = require(script.Parent.Parent.UI.TopStack)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local AnnouncementController = require(script.Parent.AnnouncementController)
local HudController = require(script.Parent.HudController)
local ToastController = require(script.Parent.ToastController)

local MinigameController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts
local World = UITheme.World
local localPlayer = Players.LocalPlayer

local DISPLAY_ORDER = 42 -- over the HUD (40), under every modal
local RESULTS_DISPLAY_ORDER = 126
local RESULTS_SIZE = Vector2.new(540, 470)
local PILL_SIZE_DESKTOP = Vector2.new(210, 52)
local PILL_SIZE_PHONE = Vector2.new(196, 58) -- x 0.8 = 46 px tap height
local LIST_SIZE = Vector2.new(190, 84)
local COLUMN_GAP = 8
local POLL_SECONDS = 0.2
local PLACE_POLL_SECONDS = 0.5
local STREAK_WINDOW = 1.0
local STREAK_PITCH = 0.07
local STREAK_MAX = 8
local FOV_PUNCH = 5
local FOV_SECONDS = 0.18
local COUNTDOWN_TEXT_SIZE = 150
local MISSION_HEIGHT = 40
local MISSION_WIDTH = 360
local RESULTS_NEXT_PREFIX = "NEXT ORB RUSH at "

-- Rejection reason -> toast (MinigameService.WhyCantQueue; unknown reasons stay silent).
local MESSAGES: { [string]: string } = {
	NoCall = "No ORB RUSH call right now",
	Carrying = "Not while carrying a stolen orb!",
	Full = "ORB RUSH is full (8 / 8)",
	InArena = "You're already in the arena",
	NoCharacter = "Can't join right now",
	DataNotLoaded = "Can't join right now",
}

type ScreenRect = { Position: Vector2, Size: Vector2 }

local screenGui: ScreenGui
local pillButton: TextButton
local pillHolder: Frame
local listHolder: Frame
local listRows: { { Name: TextLabel, Points: TextLabel } } = {}
local countdownLabel: TextLabel
local missionFrame: Frame
local missionLabel: TextLabel
local resultsModal: UIKit.Modal
local resultsContent: Frame

-- Schedule (Workspace attributes) and round state.
local phase = "Idle"
local callAt = 0
local startAt = 0
local nextAt = 0
local queuedCount = 0
local maxPlayers = MinigameConfig.MaxPlayers
local selfTestShown = false -- /selftest forces the pill and the list up

local inRound = false
local roundGoAt = 0
local roundEndsAt = 0
local goldenOn = false
local lastCountdownNumber = 0
local myPoints = 0
local myPlace = 1
local playersInRound = 0
local lastTop: { { [string]: any } } = {}
local streak = 0
local lastPickupAt = 0
local announcedCall = 0 -- the CallAt we announced
local missionShown = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

--[[ Placement in the left column ------------------------------------------------ ]]

local function overlaps(a: ScreenRect, b: ScreenRect): boolean
	return math.min(a.Position.X + a.Size.X, b.Position.X + b.Size.X) - math.max(a.Position.X, b.Position.X) > 0.5
		and math.min(a.Position.Y + a.Size.Y, b.Position.Y + b.Size.Y) - math.max(a.Position.Y, b.Position.Y) > 0.5
end

-- The HUD's rects (logical px). The left column's are everything but the bottom row.
local function hudRects(): { [string]: ScreenRect }
	local ok, rects = pcall(function(): { [string]: ScreenRect }
		return HudController.GetObstacleRectsFor(UIKit.GetLogicalViewport())
	end)
	if not ok then
		return {}
	end
	-- The HUD's rects are in the Position space of the HUD gui (top-bar inset
	-- added back); this gui is an IgnoreGuiInset Screen too, so its Position
	-- offsets are in that same space. No shift here (the old shift put the pill
	-- one inset too high). The pill and list are the HUD's own column items:
	-- they never count as obstacles for their own placement.
	local others: { [string]: ScreenRect } = {}
	for name, rect in rects do
		if name ~= "OrbRushPill" and name ~= "OrbRushList" then
			others[name] = rect
		end
	end
	return others
end

-- Where an element of `size` goes: under the left column, else beside its foot,
-- else above the bottom row; the first spot inside the screen that overlaps no
-- HUD rect and not the Roblox top-left buttons. Returns (position, ok).
local function chooseSpot(size: Vector2, rects: { [string]: ScreenRect }): (Vector2, boolean)
	local view = UIKit.GetLogicalViewport()
	local columnRight, columnBottom, columnLeft = 0, 0, math.huge
	local bottomRowTop = view.Y
	for name, rect in rects do
		if name == "BottomRow" then
			bottomRowTop = rect.Position.Y
		else
			columnRight = math.max(columnRight, rect.Position.X + rect.Size.X)
			columnBottom = math.max(columnBottom, rect.Position.Y + rect.Size.Y)
			columnLeft = math.min(columnLeft, rect.Position.X)
		end
	end
	if columnLeft == math.huge then
		columnLeft, columnBottom, columnRight = 12, UIKit.GetCardTop(), 12
	end
	local candidates = {
		Vector2.new(columnLeft, columnBottom + COLUMN_GAP),
		Vector2.new(columnRight + COLUMN_GAP, math.max(columnBottom - size.Y, UIKit.GetCardTop())),
		Vector2.new(columnLeft, bottomRowTop - size.Y - COLUMN_GAP),
		-- Phone, no room in the column: the right edge, just under the top bar.
		Vector2.new(view.X - size.X - 12, UIKit.GetCardTop() + 8),
	}
	local robloxButtons: ScreenRect = { Position = Vector2.zero, Size = Vector2.new(170, 60) }
	for _, candidate in candidates do
		local rect: ScreenRect = { Position = candidate, Size = size }
		local inside = candidate.X >= 0 and candidate.Y >= 0 and candidate.X + size.X <= view.X - 8 and candidate.Y + size.Y <= view.Y - 8
		if inside and not overlaps(rect, robloxButtons) then
			local free = true
			for _, other in rects do
				if overlaps(rect, other) then
					free = false
					break
				end
			end
			if free then
				return candidate, true
			end
		end
	end
	return candidates[1], false
end

local function pillSize(): Vector2
	return if UIKit.IsPhone() then PILL_SIZE_PHONE else PILL_SIZE_DESKTOP
end

local function placeColumn()
	local rects = hudRects()
	local pillShown = pillHolder.Visible
	local listShown = listHolder.Visible
	if pillShown then
		local size = pillSize()
		pillHolder.Size = UDim2.fromOffset(size.X, size.Y)
		local position = chooseSpot(size, rects)
		pillHolder.Position = UDim2.fromOffset(position.X, position.Y)
	end
	if listShown then
		if pillShown then
			-- The list goes where the pill is not.
			rects.OrbRushPill = { Position = Vector2.new(pillHolder.Position.X.Offset, pillHolder.Position.Y.Offset), Size = pillSize() }
		end
		local position = chooseSpot(LIST_SIZE, rects)
		listHolder.Position = UDim2.fromOffset(position.X, position.Y)
	end
end

--[[ Building the HUD pieces ---------------------------------------------------------- ]]

local function buildPill()
	local button, holder = UIKit.Button({
		Name = "OrbRushPill",
		Parent = screenGui,
		Style = "OrbRush",
		Text = "ORB RUSH",
		SubText = "JOIN",
		TextSize = 18,
		SubTextSize = 15,
		Size = UDim2.fromOffset(PILL_SIZE_DESKTOP.X, PILL_SIZE_DESKTOP.Y),
		OnClick = function()
			local queued = localPlayer:GetAttribute("OrbRushQueued") == true
			RemoteEvents.MinigameQueue:FireServer({ Action = if queued then "Leave" else "Join" })
		end,
	})
	pillButton = button
	pillHolder = holder
	holder.Visible = false
end

local function buildList()
	local body, holder = UIKit.Panel({
		Name = "OrbRushList",
		Parent = screenGui,
		Size = UDim2.fromOffset(LIST_SIZE.X, LIST_SIZE.Y),
		Color = Colors.Panel,
	})
	listHolder = holder
	holder.Visible = false
	UIKit.Padding(body, 6, 8, 6, 8)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = body
	local title = UIKit.Label({
		Name = "Title",
		Text = "ORB RUSH · TOP 3",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 0,
		Parent = body,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	local tints = { Colors.RankGold, Colors.RankSilver, Colors.RankBronze }
	for index = 1, 3 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. index
		row.BackgroundColor3 = tints[index]
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 16)
		row.LayoutOrder = index
		row.Parent = body
		UIKit.Corner(row, 6)
		local name = UIKit.Label({
			Name = "Name",
			Text = "",
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = Colors.Text,
			Size = UDim2.new(0.68, 0, 1, 0),
			Position = UDim2.fromOffset(6, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		local points = UIKit.Label({
			Name = "Points",
			Text = "",
			Font = Fonts.Display,
			TextSize = 13,
			TextColor3 = World.OrbGold,
			Size = UDim2.new(0.3, -6, 1, 0),
			Position = UDim2.new(0.7, 0, 0, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		listRows[index] = { Name = name, Points = points }
	end
end

local function buildCountdown()
	countdownLabel = UIKit.Label({
		Name = "Countdown",
		Text = "",
		Font = Fonts.Display,
		TextSize = COUNTDOWN_TEXT_SIZE,
		TextColor3 = Colors.Text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromOffset(420, 180),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 6,
		Visible = false,
		ZIndex = 5,
		Parent = screenGui,
	})
end

local function buildMission()
	missionFrame = Instance.new("Frame")
	missionFrame.Name = "OrbRushLine"
	missionFrame.AnchorPoint = Vector2.new(0.5, 0)
	missionFrame.Position = UDim2.new(0.5, 0, 0, -MISSION_HEIGHT - 20)
	missionFrame.Size = UDim2.fromOffset(MISSION_WIDTH, MISSION_HEIGHT)
	missionFrame.BackgroundColor3 = Colors.White
	missionFrame.BorderSizePixel = 0
	missionFrame.Visible = false
	missionFrame.Parent = screenGui
	UIKit.Corner(missionFrame, 999)
	UIKit.Stroke(missionFrame, 3)
	UIKit.PairGradient(missionFrame, UITheme.Gradients.OrbRush)
	missionLabel = UIKit.Label({
		Name = "Text",
		Text = "",
		Font = Fonts.Display,
		TextSize = 20,
		TextColor3 = Colors.Text,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 2,
		Parent = missionFrame,
	})
end

local function setMissionShown(shown: boolean)
	if shown == missionShown then
		return
	end
	missionShown = shown
	if shown then
		TopStack.SetMission({
			Key = "OrbRush",
			Height = MISSION_HEIGHT + UITheme.ShadowOffset,
			Show = function(y: number)
				missionFrame.Visible = true
				missionFrame.Position = UDim2.new(0.5, 0, 0, y)
			end,
			Hide = function()
				missionFrame.Visible = false
			end,
			Move = function(y: number)
				missionFrame.Position = UDim2.new(0.5, 0, 0, y)
			end,
		})
	elseif TopStack.GetMissionKey() == "OrbRush" then
		TopStack.SetMission(nil)
	end
end

--[[ Results card ------------------------------------------------------------------------ ]]

local confettiGeneration = 0

local function clearResults()
	for _, child in resultsContent:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

-- A short burst of falling squares behind the winner (UITheme colours only).
local function confetti(parent: Frame)
	confettiGeneration += 1
	local generation = confettiGeneration
	local palette = { World.OrbGold, World.OrbBlue, World.OrbPurple, World.AccentPink, World.AccentGreen, World.OrbWhite }
	local rng = Random.new()
	for index = 1, 36 do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.BackgroundColor3 = palette[(index - 1) % #palette + 1]
		piece.BorderSizePixel = 0
		piece.Size = UDim2.fromOffset(rng:NextInteger(6, 10), rng:NextInteger(6, 10))
		piece.Position = UDim2.new(rng:NextNumber(0.1, 0.9), 0, 0, -12)
		piece.Rotation = rng:NextInteger(0, 360)
		piece.ZIndex = parent.ZIndex + 20
		piece.Parent = parent
		local fall = rng:NextNumber(1.4, 2.4)
		task.delay(rng:NextNumber(0, 0.5), function()
			if generation ~= confettiGeneration or not piece.Parent then
				piece:Destroy()
				return
			end
			local tween = TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(piece.Position.X.Scale, rng:NextInteger(-30, 30), 1, 12),
				Rotation = piece.Rotation + rng:NextInteger(-300, 300),
				BackgroundTransparency = 0.6,
			})
			tween.Completed:Once(function()
				piece:Destroy()
			end)
			tween:Play()
		end)
	end
end

local PLACE_NAMES = { "1ST", "2ND", "3RD" }

local function placeLabel(place: number): string
	return PLACE_NAMES[place] or (tostring(place) .. "TH")
end

local function buildPodiumColumn(parent: Frame, entry: { [string]: any }?, place: number, slot: number)
	local heights = { [1] = 112, [2] = 84, [3] = 66 }
	local tints = { [1] = Colors.RankGold, [2] = Colors.RankSilver, [3] = Colors.RankBronze }
	local column = Instance.new("Frame")
	column.Name = "Podium" .. place
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(0.5, 1)
	column.Position = UDim2.new(0.18 + (slot - 1) * 0.32, 0, 1, 0)
	column.Size = UDim2.new(0.3, 0, 1, 0)
	column.Parent = parent
	if not entry then
		return
	end
	local block = Instance.new("Frame")
	block.Name = "Block"
	block.BackgroundColor3 = tints[place]
	block.BorderSizePixel = 0
	block.AnchorPoint = Vector2.new(0.5, 1)
	block.Position = UDim2.fromScale(0.5, 1)
	block.Size = UDim2.new(0.92, 0, 0, heights[place])
	block.Parent = column
	UIKit.Corner(block, 10)
	UIKit.Stroke(block, 3)
	UIKit.Label({
		Name = "Place",
		Text = placeLabel(place),
		Font = Fonts.Display,
		TextSize = 26,
		TextColor3 = Colors.Text,
		Size = UDim2.fromScale(1, 0.5),
		Position = UDim2.fromScale(0, 0.04),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 3,
		Parent = block,
	})
	UIKit.Label({
		Name = "Points",
		Text = ("%d pts"):format(entry.Points or 0),
		Font = Fonts.BodyHeavy,
		TextSize = 15,
		TextColor3 = Colors.Text,
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.55),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 2,
		Parent = block,
	})
	-- The avatar sits on the block (a bot gets a gear face and a BOT chip).
	local avatar = Instance.new("Frame")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Colors.Panel2
	avatar.BorderSizePixel = 0
	avatar.AnchorPoint = Vector2.new(0.5, 1)
	avatar.Position = UDim2.new(0.5, 0, 1, -heights[place] - 22)
	avatar.Size = UDim2.fromOffset(60, 60)
	avatar.Parent = column
	UIKit.Corner(avatar, 999)
	UIKit.Stroke(avatar, 3)
	if entry.Bot == true then
		UIKit.Label({
			Name = "Face",
			Text = "🤖",
			TextSize = 34,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = avatar,
		})
	else
		local image = Instance.new("ImageLabel")
		image.Name = "Face"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(tonumber(entry.UserId) or 0)
		image.Parent = avatar
		UIKit.Corner(image, 999)
	end
	local name = UIKit.Label({
		Name = "Name",
		Text = tostring(entry.Name or "?"),
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.Text,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -heights[place] - 2),
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Stroke = 2,
		Parent = column,
	})
	name.ZIndex = column.ZIndex + 2
	if entry.Bot == true then
		local chip = UIKit.Pill({
			Name = "BotChip",
			Text = "BOT",
			Color = Colors.Panel3,
			Height = 16,
			TextSize = 10,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -heights[place] - 20),
			Parent = column,
		})
		UIKit.PillRoot(chip).ZIndex = column.ZIndex + 5
	end
end

local function showResults(payload: { [string]: any })
	clearResults()
	local podium: { { [string]: any } } = if typeof(payload.Podium) == "table" then payload.Podium else {}
	local place = tonumber(payload.Place) or 1
	local points = tonumber(payload.Points) or 0
	resultsModal.Title.Text = "ORB RUSH"
	-- The podium: 2nd, 1st, 3rd.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.new(1, 0, 0, 226)
	stage.LayoutOrder = 1
	stage.ClipsDescendants = false
	stage.Parent = resultsContent
	local byPlace: { [number]: { [string]: any } } = {}
	for _, entry in podium do
		byPlace[tonumber(entry.Place) or 0] = entry
	end
	buildPodiumColumn(stage, byPlace[2], 2, 1)
	buildPodiumColumn(stage, byPlace[1], 1, 2)
	buildPodiumColumn(stage, byPlace[3], 3, 3)

	local summary = UIKit.Label({
		Name = "Summary",
		Text = ("You placed %s · %d pts"):format(placeLabel(place):lower(), points),
		Font = Fonts.Display,
		TextSize = 24,
		TextColor3 = Colors.Text,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = 3,
		Parent = resultsContent,
	})
	summary.ZIndex = resultsContent.ZIndex + 2

	-- The prize line: the orb pops out through the normal pull card right after.
	local prize = Instance.new("Frame")
	prize.Name = "Prize"
	prize.BackgroundColor3 = Colors.Panel2
	prize.BorderSizePixel = 0
	prize.Size = UDim2.new(1, 0, 0, 56)
	prize.LayoutOrder = 3
	prize.Parent = resultsContent
	UIKit.Corner(prize, 12)
	UIKit.Stroke(prize, 2)
	local prizeText: string
	local prizeColor = Colors.Muted
	if typeof(payload.Prize) == "string" then
		prizeText = ("%s orb · coming up!"):format(payload.Prize)
		prizeColor = Colors.Text
		local orb = UIKit.TierOrb(payload.Prize, 40)
		orb.AnchorPoint = Vector2.new(0, 0.5)
		orb.Position = UDim2.new(0, 10, 0.5, 0)
		orb.Parent = prize
	elseif typeof(payload.Cash) == "number" and payload.Cash > 0 then
		prizeText = ("%s cash · %d seconds of your income"):format(NumberFormat.Money(payload.Cash), MinigameConfig.ParticipationIncomeSeconds)
		prizeColor = Colors.Cash
		if payload.Capped == true then
			prizeText = ("%s cash · you've won 4 orbs this hour"):format(NumberFormat.Money(payload.Cash))
		end
	elseif points < MinigameConfig.MinPointsToPlace then
		prizeText = ("Score %d+ points to place"):format(MinigameConfig.MinPointsToPlace)
	else
		prizeText = "No prize this round"
	end
	UIKit.Label({
		Name = "Text",
		Text = prizeText,
		Font = Fonts.BodyHeavy,
		TextSize = 17,
		TextColor3 = prizeColor,
		Position = UDim2.fromOffset(if typeof(payload.Prize) == "string" then 60 else 14, 0),
		Size = UDim2.new(1, -(if typeof(payload.Prize) == "string" then 70 else 28), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = prize.ZIndex + 1,
		Parent = prize,
	})
	local nextAtValue = tonumber(payload.NextAt) or nextAt
	UIKit.Label({
		Name = "Next",
		Text = RESULTS_NEXT_PREFIX .. MinigameConfig.FormatMinute(nextAtValue),
		Font = Fonts.BodyHeavy,
		TextSize = 15,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = resultsContent,
	})
	UIKit.Button({
		Name = "Close",
		Parent = resultsContent,
		Style = "Green",
		Text = "CLOSE",
		TextSize = 22,
		Size = UDim2.fromOffset(200, 52),
		LayoutOrder = 5,
		OnClick = function()
			resultsModal.Close()
		end,
	})
	SoundKit.Play("RushResults")
	resultsModal.Open()
	if place == 1 then
		confetti(stage)
	end
end

local function buildResults()
	resultsModal = UIKit.Modal({
		Name = "OrbRushResults",
		Title = "ORB RUSH",
		DisplayOrder = RESULTS_DISPLAY_ORDER,
		MaxSize = RESULTS_SIZE,
		FitContent = true,
		HeaderTop = UITheme.Gradients.OrbRush.Top,
	})
	resultsContent = resultsModal.Content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = resultsContent
end

--[[ Orb animation ------------------------------------------------------------------------- ]]

type Drop = { Part: BasePart, From: Vector3, To: Vector3, Started: number, Duration: number, Arc: number }

local drops: { Drop } = {}

local function watchOrb(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local from = part:GetAttribute("FromPos")
	local duration = part:GetAttribute("DropSeconds")
	if typeof(from) ~= "Vector3" or typeof(duration) ~= "number" or duration <= 0 then
		return
	end
	local arc = part:GetAttribute("Arc")
	local landing = part.Position
	part.Position = from
	table.insert(drops, {
		Part = part,
		From = from,
		To = landing,
		Started = os.clock(),
		Duration = duration,
		Arc = if typeof(arc) == "number" then arc else 0,
	})
end

local function stepDrops()
	local now = os.clock()
	for index = #drops, 1, -1 do
		local drop = drops[index]
		if not drop.Part.Parent then
			table.remove(drops, index)
		else
			local t = math.clamp((now - drop.Started) / drop.Duration, 0, 1)
			if t >= 1 then
				drop.Part.Position = drop.To
				table.remove(drops, index)
			else
				local eased = t * t
				local position = drop.From:Lerp(drop.To, if drop.Arc > 0 then t else eased)
				position += Vector3.new(0, drop.Arc * 4 * t * (1 - t), 0)
				drop.Part.Position = position
			end
		end
	end
end

local function hookOrbFolder()
	task.spawn(function()
		local arena = Workspace:WaitForChild("OrbRushArena", 60)
		local folder = arena and arena:WaitForChild("Orbs", 30)
		if not folder then
			return
		end
		for _, orb in folder:GetChildren() do
			watchOrb(orb)
		end
		folder.ChildAdded:Connect(watchOrb)
	end)
	RunService.RenderStepped:Connect(stepDrops)
end

--[[ Round events ------------------------------------------------------------------------------ ]]

local function fovPunch()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local base = camera.FieldOfView
	local out = TweenInfo.new(FOV_SECONDS / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	TweenService:Create(camera, out, { FieldOfView = base + FOV_PUNCH }):Play()
end

local function tierColor(tier: string): Color3
	for _, def in MinigameConfig.OrbTiers do
		if def.Id == tier then
			return (World :: any)[def.Token]
		end
	end
	return Colors.Text
end

local function onPickup(payload: { [string]: any })
	local now = os.clock()
	streak = if now - lastPickupAt <= STREAK_WINDOW then streak + 1 else 1
	lastPickupAt = now
	local pitch = 1 + STREAK_PITCH * math.min(streak - 1, STREAK_MAX)
	SoundKit.Play("RushPop", nil, { PlaybackSpeed = pitch })
	local value = tonumber(payload.Value) or 1
	local tier = tostring(payload.Tier)
	if typeof(payload.Position) == "Vector3" then
		HudController.FloatPop(payload.Position, "+" .. value, tierColor(tier))
	end
	if tier == MinigameConfig.GoldenWaveTier then
		fovPunch()
	end
	if typeof(payload.Points) == "number" then
		myPoints = payload.Points
	end
end

local function refreshList()
	for index, row in listRows do
		local entry = lastTop[index]
		row.Name.Text = if entry then ("%d. %s%s"):format(index, tostring(entry.Name), if entry.Bot == true then " 🤖" else "") else ("%d."):format(index)
		row.Points.Text = if entry then tostring(entry.Points) else ""
	end
end

local function refreshMission(timeLeft: number)
	missionLabel.Text = ("ORB RUSH %s · You %d · #%d"):format(MinigameConfig.FormatClock(timeLeft), myPoints, myPlace)
	if goldenOn then
		missionLabel.Text = ("GOLDEN WAVE %s · You %d · #%d"):format(MinigameConfig.FormatClock(timeLeft), myPoints, myPlace)
	end
end

local function onScores(payload: { [string]: any })
	inRound = true
	lastTop = if typeof(payload.Top) == "table" then payload.Top else {}
	myPoints = tonumber(payload.Points) or myPoints
	myPlace = tonumber(payload.Place) or myPlace
	playersInRound = tonumber(payload.Players) or playersInRound
	goldenOn = payload.Golden == true
	refreshList()
	refreshMission(tonumber(payload.TimeLeft) or 0)
end

local function runCountdown(goAt: number)
	task.spawn(function()
		lastCountdownNumber = 0
		countdownLabel.Visible = true
		while inRound do
			local left = goAt - serverNow()
			if left <= -0.9 then
				break
			end
			local text: string
			local number = math.ceil(left)
			if left > 0 then
				text = tostring(math.clamp(number, 1, 9))
				if number ~= lastCountdownNumber then
					lastCountdownNumber = number
					SoundKit.Play("RushTick")
					countdownLabel.TextSize = COUNTDOWN_TEXT_SIZE * 1.25
					TweenService:Create(countdownLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = COUNTDOWN_TEXT_SIZE }):Play()
				end
			else
				text = "GO!"
				if lastCountdownNumber ~= 0 then
					lastCountdownNumber = 0
					SoundKit.Play("RushGo")
					countdownLabel.TextSize = COUNTDOWN_TEXT_SIZE * 1.4
					TweenService:Create(countdownLabel, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = COUNTDOWN_TEXT_SIZE }):Play()
				end
			end
			countdownLabel.Text = text
			task.wait(0.05)
		end
		countdownLabel.Visible = false
	end)
end

local function onStart(payload: { [string]: any })
	inRound = true
	goldenOn = false
	streak = 0
	myPoints = 0
	myPlace = 1
	lastTop = {}
	roundGoAt = tonumber(payload.GoAt) or serverNow()
	roundEndsAt = tonumber(payload.EndsAt) or (roundGoAt + MinigameConfig.RoundSeconds)
	refreshList()
	refreshMission(roundEndsAt - serverNow())
	setMissionShown(true)
	runCountdown(roundGoAt)
end

local function onGolden()
	goldenOn = true
	SoundKit.Play("RushGolden")
	AnnouncementController.ShowLine("GOLDEN WAVE! Only gold orbs, twice as fast", "OrbRushGolden")
	fovPunch()
end

local function onMessage(payload: { [string]: any })
	local reason = tostring(payload.Reason)
	if reason == "NoCall" then
		local upcoming = nextAt
		ToastController.Show(("NEXT ORB RUSH at %s"):format(MinigameConfig.FormatMinute(upcoming)), "Neutral")
		return
	end
	local text = MESSAGES[reason]
	if text then
		ToastController.Show(text, "Neutral")
	end
end

local function onResults(payload: { [string]: any })
	inRound = false
	countdownLabel.Visible = false
	setMissionShown(false)
	showResults(payload)
end

local function onState(payload: unknown)
	if typeof(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: any }
	local kind = data.Kind
	if kind == "Start" then
		onStart(data)
	elseif kind == "Scores" then
		onScores(data)
	elseif kind == "Pickup" then
		onPickup(data)
	elseif kind == "Golden" then
		onGolden()
	elseif kind == "Message" then
		onMessage(data)
	elseif kind == "Queued" then
		SoundKit.Play("Toast")
	elseif kind == "Results" then
		onResults(data)
	end
end

--[[ Polling the schedule ------------------------------------------------------------------------ ]]

local function readSchedule()
	local value = Workspace:GetAttribute("OrbRushPhase")
	phase = if typeof(value) == "string" then value else "Idle"
	local function number(name: string): number
		local raw = Workspace:GetAttribute(name)
		return if typeof(raw) == "number" then raw else 0
	end
	callAt = number("OrbRushCallAt")
	startAt = number("OrbRushStartAt")
	nextAt = number("OrbRushNextAt")
	queuedCount = number("OrbRushQueued")
	maxPlayers = if number("OrbRushMax") > 0 then number("OrbRushMax") else MinigameConfig.MaxPlayers
end

local function pillWanted(): boolean
	if selfTestShown then
		return true
	end
	if phase ~= "Call" or localPlayer:GetAttribute("InOrbRush") == true then
		return false
	end
	-- The progressive HUD: not before the SHOP row is open (a new player in the tutorial).
	return HudGate.IsShown("Shop")
end

local function updatePill()
	local wanted = pillWanted()
	if pillHolder.Visible ~= wanted then
		pillHolder.Visible = wanted
		if wanted then
			placeColumn()
		end
	end
	if not wanted then
		return
	end
	local left = if selfTestShown and phase ~= "Call" then 45 else startAt - serverNow()
	local queued = localPlayer:GetAttribute("OrbRushQueued") == true
	local label = pillButton:FindFirstChild("Label")
	local sub = pillButton:FindFirstChild("SubLabel")
	if label and label:IsA("TextLabel") then
		label.Text = ("ORB RUSH %s"):format(MinigameConfig.FormatClock(left))
	end
	if sub and sub:IsA("TextLabel") then
		sub.Text = if queued then ("✓ QUEUED %d / %d · tap to leave"):format(math.max(queuedCount, 1), maxPlayers) else ("JOIN · %d / %d"):format(queuedCount, maxPlayers)
	end
end

local function updateList()
	local wanted = selfTestShown or (inRound and phase ~= "Idle")
	if listHolder.Visible ~= wanted then
		listHolder.Visible = wanted
		if wanted then
			refreshList()
			placeColumn()
		end
	end
	if inRound then
		refreshMission(math.max(0, roundEndsAt - serverNow()))
	end
end

local function announceCall()
	if phase ~= "Call" or callAt == announcedCall or localPlayer:GetAttribute("InOrbRush") == true then
		return
	end
	announcedCall = callAt
	if not HudGate.IsShown("Shop") then
		return
	end
	SoundKit.Play("RushCall")
	AnnouncementController.ShowLine(
		("ORB RUSH in %s · win an Epic+ orb!"):format(MinigameConfig.FormatClock(math.max(0, startAt - serverNow()))),
		"OrbRushCall"
	)
end

local pollAccumulator = 0
local placeAccumulator = 0

local function onHeartbeat(dt: number)
	pollAccumulator += dt
	placeAccumulator += dt
	if pollAccumulator < POLL_SECONDS then
		return
	end
	pollAccumulator = 0
	readSchedule()
	-- A round that ended without the Results message (the server aborted it).
	if inRound and phase == "Idle" and localPlayer:GetAttribute("InOrbRush") ~= true then
		inRound = false
		countdownLabel.Visible = false
		setMissionShown(false)
	end
	announceCall()
	updatePill()
	updateList()
	if placeAccumulator >= PLACE_POLL_SECONDS then
		placeAccumulator = 0
		if pillHolder.Visible or listHolder.Visible then
			placeColumn()
		end
	end
end

--[[ /selftest ----------------------------------------------------------------------------------- ]]

-- The pill and the live list, forced up at the current layout: each tap target is at
-- least 44 px after the UIScale, nothing overlaps a HUD rect or the Roblox
-- top-left buttons, and both sit inside the screen. The caller forces the layout.
function MinigameController.SelfTestLines(scaleName: string): { string }
	local lines: { string } = {}
	selfTestShown = true
	pillHolder.Visible = true
	listHolder.Visible = true
	lastTop = { { Name = "A very long name here", Points = 123, Bot = false }, { Name = "Bolt", Points = 98, Bot = true }, { Name = "Nova", Points = 76, Bot = true } }
	refreshList()
	task.wait(0.3)
	placeColumn()
	task.wait(0.2)
	local rects = hudRects()
	local view = UIKit.GetLogicalViewport()
	local scale = UIKit.EffectiveScale(screenGui)
	local failures: { string } = {}
	local inset = Vector2.new(0, GuiService:GetGuiInset().Y)
	local holders: { [string]: Frame } = { OrbRushPill = pillHolder, OrbRushList = listHolder }
	for name, holder in holders do
		local rect: ScreenRect = { Position = (holder.AbsolutePosition + inset) / scale, Size = holder.AbsoluteSize / scale }
		for other, hud in rects do
			if overlaps(rect, hud) then
				table.insert(failures, ("%s overlaps HUD %s"):format(name, other))
			end
		end
		if rect.Position.X < 0 or rect.Position.Y < 0 or rect.Position.X + rect.Size.X > view.X + 0.5 or rect.Position.Y + rect.Size.Y > view.Y + 0.5 then
			table.insert(failures, name .. " is off screen")
		end
		if overlaps(rect, { Position = Vector2.zero, Size = Vector2.new(170, 60) }) then
			table.insert(failures, name .. " covers the Roblox top-left buttons")
		end
	end
	local pillFrame: Frame = holders.OrbRushPill
	local listFrame: Frame = holders.OrbRushList
	if overlaps(
		{ Position = (pillFrame.AbsolutePosition + inset) / scale, Size = pillFrame.AbsoluteSize / scale },
		{ Position = (listFrame.AbsolutePosition + inset) / scale, Size = listFrame.AbsoluteSize / scale }
	) then
		table.insert(failures, "OrbRushPill overlaps OrbRushList")
	end
	local tapHeight = pillHolder.AbsoluteSize.Y
	if tapHeight < 44 then
		table.insert(failures, ("the JOIN pill is %d px tall (needs 44)"):format(math.floor(tapHeight)))
	end
	table.insert(
		lines,
		if #failures == 0
			then ("PASS orb rush hud (%s): the JOIN pill (%d px tall) and the live top 3 overlap no HUD rect, stay on screen and clear the top-left"):format(scaleName, math.floor(tapHeight))
			else ("FAIL orb rush hud (%s): %s"):format(scaleName, table.concat(failures, "; "))
	)
	selfTestShown = false
	pillHolder.Visible = false
	listHolder.Visible = false
	return lines
end

--[[ Lifecycle -------------------------------------------------------------------------------------- ]]

function MinigameController.Init()
	screenGui = UIKit.Screen("OrbRush", DISPLAY_ORDER)
	buildPill()
	buildList()
	-- Part of the HUD's left-column stack: its rects are obstacles like every
	-- other element's, and the HUD re-places them whenever the column moves.
	HudController.SetColumnItem("OrbRushPill", pillHolder)
	HudController.SetColumnItem("OrbRushList", listHolder)
	HudController.ColumnChanged:Connect(function()
		if pillHolder.Visible or listHolder.Visible then
			task.defer(placeColumn)
		end
	end)
	buildCountdown()
	buildMission()
	buildResults()
	hookOrbFolder()
	readSchedule()
	RemoteEvents.MinigameState.OnClientEvent:Connect(onState)
	RunService.Heartbeat:Connect(onHeartbeat)
	UIKit.LayoutChanged:Connect(function()
		if pillHolder.Visible or listHolder.Visible then
			placeColumn()
		end
	end)
end

return MinigameController
