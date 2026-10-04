--!strict
--[[
	EventInfoCard
	-------------
	What the HUD event chip opens (EventController): the event explained,
	every number from EventConfig.GetInfo so the copy can't drift.

	  header      the event gradient, icon + name, the live timer ("3:12
	              left", or "Starts in 8:40" between events) and "Lab
	              weather · every server"
	  WHAT'S HAPPENING  up to 2 bullets
	  WHAT TO DO        1 bullet
	  Can give:   the mutation pills this event affects (+ a note)
	  NEXT        the next 2 events with timers, and the Admin Abuse line

	400 px wide under the chip; on a phone 90% of the width (capped at 400).
	Between events it explains the NEXT one. EventController also opens it
	once per event type per account (Tips "event_<Id>") after the start
	banner.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local EventInfoCard = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local CARD_WIDTH = 400
local PHONE_WIDTH_SCALE = 0.9
local HEADER_HEIGHT = 74
local PAD = 14
local NEXT_COUNT = 2

local holder: Frame? = nil
local body: Frame
local timerLabel: TextLabel
local nextRows: { { Name: TextLabel, Timer: TextLabel } } = {}
local adminLabel: TextLabel
local shownId: string? = nil
local shownNow = false
local order = 0

--[[ Helpers -------------------------------------------------------------------- ]]

local function nextOrder(): number
	order += 1
	return order
end

local function title(id: string): string
	return ("%s %s"):format(EventConfig.Icons[id] or "", EventConfig.Names[id] or id)
end

local function heading(parent: Instance, text: string)
	UIKit.Label({
		Name = "Heading",
		Text = text,
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = nextOrder(),
		ZIndex = body.ZIndex + 1,
		Parent = parent,
	})
end

local function bullet(parent: Instance, text: string)
	UIKit.Label({
		Name = "Bullet",
		Text = "• " .. text,
		Font = Fonts.Body,
		TextSize = 15,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = nextOrder(),
		ZIndex = body.ZIndex + 1,
		Parent = parent,
	})
end

local function row(parent: Instance, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = nextOrder()
	frame.ZIndex = body.ZIndex + 1
	frame.Parent = parent
	return frame
end

-- The header's live timer for the shown event.
local function timerText(): string
	if not shownId then
		return ""
	end
	local lineup = EventState.GetLineup(NEXT_COUNT + 1)
	for _, entry in lineup do
		if entry.Id == shownId and entry.Now == shownNow then
			local timer = EventState.FormatTimer(entry.Seconds)
			return if entry.Now then timer .. " left" else "Starts in " .. timer
		end
	end
	return ""
end

--[[ Build ---------------------------------------------------------------------- ]]

local function clearBody()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	nextRows = {}
	order = 0
end

local function buildContent(id: string)
	clearBody()
	local info = EventConfig.GetInfo(id)
	local z = body.ZIndex + 1

	-- Header: the event gradient (rainbow stops for Rainbow Storm).
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundColor3 = Colors.White
	header.LayoutOrder = nextOrder()
	header.ZIndex = z
	header.Parent = body
	UIKit.Corner(header, UITheme.Radius.Row)
	UIKit.Stroke(header, 2)
	if id == "RainbowStorm" then
		local gradient = Instance.new("UIGradient")
		gradient.Color = UITheme.GetRainbowSequence()
		gradient.Parent = header
	else
		UIKit.PairGradient(header, UITheme.GetEventGradient(id))
	end
	UIKit.Label({
		Name = "Title",
		Text = title(id),
		Font = Fonts.Display,
		TextSize = 22,
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -24 - UITheme.MinTapSize, 0, 28),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = header,
	})
	timerLabel = UIKit.Label({
		Name = "Timer",
		Text = timerText(),
		Font = Fonts.Display,
		TextSize = 17,
		Position = UDim2.fromOffset(12, 36),
		Size = UDim2.new(0.5, -12, 0, 22),
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = header,
	})
	UIKit.Label({
		Name = "Scope",
		Text = "Lab weather · every server",
		Font = Fonts.Body,
		TextSize = 13,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 40),
		Size = UDim2.new(0.5, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = header,
	})
	UIKit.CloseButton({
		Parent = header,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6, 0, 6),
		ZIndex = z + 2,
		OnClick = function()
			EventInfoCard.Hide()
		end,
	})

	if info then
		heading(body, "WHAT'S HAPPENING")
		for _, line in info.Happening do
			bullet(body, line)
		end
		heading(body, "WHAT TO DO")
		bullet(body, info.ToDo)
		local gives = row(body, 26)
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gives
		UIKit.Label({
			Name = "CanGive",
			Text = "Can give:",
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			TextColor3 = Colors.Muted,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = 0,
			ZIndex = z,
			Parent = gives,
		})
		for index, mutation in info.CanGive do
			local pill = UIKit.MutationPill({ Parent = gives, Mutation = mutation, TextSize = 12, Height = 22, ZIndex = z })
			if pill then
				pill.LayoutOrder = index
			end
		end
		if info.CanGiveNote then
			UIKit.Label({
				Name = "Note",
				Text = info.CanGiveNote,
				Font = Fonts.Body,
				TextSize = 13,
				TextColor3 = Colors.Muted,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22),
				LayoutOrder = #info.CanGive + 1,
				ZIndex = z,
				Parent = gives,
			})
		end
	end

	heading(body, "NEXT")
	for _ = 1, NEXT_COUNT do
		local line = row(body, 22)
		local name = UIKit.Label({
			Name = "Name",
			Font = Fonts.Display,
			TextSize = 16,
			Size = UDim2.new(0.65, 0, 1, 0),
			ZIndex = z,
			Parent = line,
		})
		local timer = UIKit.Label({
			Name = "Timer",
			Font = Fonts.Display,
			TextSize = 15,
			TextColor3 = Colors.Muted,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.35, 0, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = z,
			Parent = line,
		})
		table.insert(nextRows, { Name = name, Timer = timer })
	end
	adminLabel = UIKit.Label({
		Name = "AdminAbuse",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.GoldLabel,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = nextOrder(),
		ZIndex = z,
		Parent = body,
	})
end

local function ensureBuilt(parent: Instance, top: number): Frame
	local existing = holder
	if existing then
		return existing
	end
	local panel, panelHolder = UIKit.Panel({
		Name = "EventInfoCard",
		Parent = parent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, top),
		Size = UDim2.new(PHONE_WIDTH_SCALE, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Radius = 18,
		ZIndex = 5,
	})
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(CARD_WIDTH, math.huge)
	constraint.Parent = panelHolder
	UIKit.Padding(panel, PAD)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	body = panel
	panelHolder.Visible = false
	holder = panelHolder
	return panelHolder
end

--[[ Public ---------------------------------------------------------------------- ]]

-- Updates the timers and the NEXT rows (EventController calls it every
-- second while the card is open).
function EventInfoCard.Refresh()
	local frame = holder
	if not frame or not frame.Visible or not shownId then
		return
	end
	timerLabel.Text = timerText()
	local lineup = EventState.GetLineup(NEXT_COUNT + 2)
	-- The rows list what comes after the shown event: the upcoming slots,
	-- minus the first one when that's the event the card explains.
	local upcoming: { EventState.LineupEntry } = {}
	local skipFirst = not shownNow
	for _, entry in lineup do
		if not entry.Now then
			if skipFirst then
				skipFirst = false
			else
				table.insert(upcoming, entry)
			end
		end
	end
	for index, line in nextRows do
		local entry = upcoming[index]
		line.Name.Text = if entry then title(entry.Id) else ""
		line.Name.TextColor3 = if entry then UITheme.GetEventGradient(entry.Id).Top else Colors.Text
		line.Timer.Text = if entry then "in " .. EventState.FormatTimer(entry.Seconds) else ""
	end
	adminLabel.Text = EventState.GetAdminAbuseText()
end

-- Shows the card for `id` (`now`: it's running; else it's the next one),
-- under the chip at `top` px in `parent`.
function EventInfoCard.Show(parent: Instance, top: number, id: string, now: boolean)
	local frame = ensureBuilt(parent, top)
	if shownId ~= id or shownNow ~= now or not frame.Visible then
		shownId, shownNow = id, now
		buildContent(id)
	end
	frame.Visible = true
	UIKit.PopIn(frame)
	EventInfoCard.Refresh()
end

function EventInfoCard.Hide()
	local frame = holder
	if frame then
		frame.Visible = false
	end
end

function EventInfoCard.IsOpen(): boolean
	local frame = holder
	return frame ~= nil and frame.Visible
end

-- The event the card shows (nil when closed).
function EventInfoCard.GetShown(): (string?, boolean)
	if not EventInfoCard.IsOpen() then
		return nil, false
	end
	return shownId, shownNow
end

return EventInfoCard
