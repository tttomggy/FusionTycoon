--!strict
--[[
	AdminPanel
	----------
	The Admin Abuse panel (UIKit Modal). It is BUILT only on the first
	AdminOpen from the server, which AdminService sends to admins only, so a
	non-admin client never has it. Every button just fires AdminAction; the
	server re-checks the sender and validates every arg.

	  TARGET        This server / All servers (applies to every action
	                below; Next Admin Abuse is always global)
	  START EVENT   any of the six, strength x1/x2/x3, 5/10/15 min; END EVENT
	  GIFT EVERYONE a random item of a tier, optional mutation
	  LUCK x3       for 10 min
	  BROADCAST     <= 80 chars (filtered on the server)
	  NEXT ADMIN ABUSE  stepped in your local time, sent as UTC unix seconds

	  PLAYERS       everyone in THIS server (you first): pick one, then
	                RESTART TUTORIAL or RESET TO ZERO (red confirm + 2 s hold).
	                This server only, whatever TARGET says.

	Results come back as AdminResult toasts (AdminController).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AdminConfig = require(ReplicatedStorage.Shared.Config.AdminConfig)
local EventConfig = require(ReplicatedStorage.Shared.Config.EventConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UIKit = require(script.Parent.UIKit)

local AdminPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(600, 620)
local TAP = UITheme.MinTapSize
local GAP = 8
local SELECTED_STYLE = UIKit.SELECTED_STYLE
local UNSELECTED_STYLE = UIKit.UNSELECTED_STYLE
local STEP_HOUR = 3600

local modal: UIKit.Modal? = nil
local list: ScrollingFrame
local order = 0

-- Current choices.
local choice = {
	Scope = "Server",
	EventId = EventConfig.Order[1],
	Strength = AdminConfig.Strengths[1],
	Minutes = AdminConfig.DurationMinutes[1],
	Tier = AdminConfig.GiftTiers[1],
	Mutation = "",
	AbuseUnix = 0,
}

local selectedUserId: number? = nil
local playerRows: Frame
local selectedLabel: TextLabel
local confirmBox: Frame
local confirmLabel: TextLabel
local holdButton: TextButton
local holdStarted: number? = nil
local holdConnection: RBXScriptConnection? = nil

local abuseLabel: TextLabel
local broadcastBox: TextBox
local countLabel: TextLabel

--[[ Builders ----------------------------------------------------------------- ]]

local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string)
	UIKit.Label({
		Name = "Heading",
		Text = text,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = nextOrder(),
		Parent = list,
	})
end

-- A wrapping row of buttons.
local function row(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Row"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = nextOrder()
	frame.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Wraps = true
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, UITheme.ShadowOffset)
	padding.Parent = frame
	return frame
end

local function button(parent: Instance, text: string, width: number, style: string, onClick: () -> ()): TextButton
	local b = UIKit.Button({
		Name = text,
		Parent = parent,
		Style = style,
		Text = text,
		TextSize = 15,
		Size = UDim2.fromOffset(width, TAP),
		LayoutOrder = nextOrder(),
		OnClick = onClick,
	})
	return b
end

-- One-of-N buttons; `set(value)` is called with the picked option's value.
local function picker(options: { { Label: string, Value: any } }, width: number, initial: any, set: (any) -> ())
	local parent = row()
	local buttons: { [TextButton]: any } = {}
	local function restyle(selected: any)
		for b, value in buttons do
			UIKit.SetButton(b, { Style = if value == selected then SELECTED_STYLE else UNSELECTED_STYLE })
		end
	end
	for _, option in options do
		local b: TextButton
		b = button(parent, option.Label, width, UNSELECTED_STYLE, function()
			UIKit.SelectFeedback(b)
			set(option.Value)
			restyle(option.Value)
		end)
		buttons[b] = option.Value
	end
	restyle(initial)
end

local function send(action: string, args: { [string]: any })
	RemoteEvents.AdminAction:FireServer({ Action = action, Args = args, Scope = choice.Scope })
end

--[[ Next Admin Abuse ------------------------------------------------------------ ]]

local function nextFullHour(): number
	local now = math.floor(Workspace:GetServerTimeNow())
	return (now // STEP_HOUR + 1) * STEP_HOUR
end

local function refreshAbuse()
	if choice.AbuseUnix <= 0 then
		abuseLabel.Text = "Not set"
		return
	end
	abuseLabel.Text = DateTime.fromUnixTimestamp(choice.AbuseUnix):FormatLocalTime("ddd D MMM YYYY · HH:mm", "en-us")
		.. " (your time)"
end

local function stepAbuse(seconds: number)
	if choice.AbuseUnix <= 0 then
		choice.AbuseUnix = nextFullHour()
	end
	choice.AbuseUnix = math.max(nextFullHour() - STEP_HOUR, choice.AbuseUnix + seconds)
	refreshAbuse()
end

--[[ Players ------------------------------------------------------------------------ ]]

local ROW_HEIGHT = 52
local HOLD_TEXT = "HOLD TO RESET"

local function statText(player: Player): string
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	local rebirths = stats and stats:FindFirstChild("Rebirths")
	local cashText = if cash and cash:IsA("StringValue") then cash.Value else "-"
	local rebirthText = if rebirths and rebirths:IsA("IntValue") then tostring(rebirths.Value) else "0"
	return ("R%s · %s"):format(rebirthText, cashText)
end

local function selectedPlayer(): Player?
	return if selectedUserId then Players:GetPlayerByUserId(selectedUserId) else nil
end

local function stopHold()
	holdStarted = nil
	if holdConnection then
		holdConnection:Disconnect()
		holdConnection = nil
	end
	UIKit.SetButton(holdButton, { Text = HOLD_TEXT })
end

local function closeConfirm()
	stopHold()
	confirmBox.Visible = false
end

local function refreshPlayers()
	if not modal then
		return
	end
	for _, child in playerRows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local me = Players.LocalPlayer
	local ordered: { Player } = { me }
	local others = Players:GetPlayers()
	table.sort(others, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	for _, other in others do
		if other ~= me then
			table.insert(ordered, other)
		end
	end
	if selectedUserId and not Players:GetPlayerByUserId(selectedUserId) then
		selectedUserId = nil
		closeConfirm()
	end
	for index, player in ordered do
		local rowButton = Instance.new("TextButton")
		rowButton.Name = "Player_" .. player.UserId
		rowButton.Text = ""
		rowButton.AutoButtonColor = false
		rowButton.BackgroundColor3 = Colors.Panel2
		rowButton.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		rowButton.LayoutOrder = index
		rowButton.Parent = playerRows
		UIKit.Corner(rowButton, UITheme.Radius.Row)
		UIKit.Stroke(rowButton, 2)
		local head = Instance.new("ImageLabel")
		head.Name = "Head"
		head.BackgroundColor3 = Colors.Panel3
		head.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100"):format(player.UserId)
		head.Position = UDim2.fromOffset(6, 6)
		head.Size = UDim2.fromOffset(ROW_HEIGHT - 12, ROW_HEIGHT - 12)
		head.Parent = rowButton
		UIKit.Corner(head, 999)
		UIKit.Label({
			Name = "Name",
			Text = if player == me then player.DisplayName .. " (you)" else player.DisplayName,
			Font = Fonts.BodyHeavy,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(ROW_HEIGHT + 4, 0),
			Size = UDim2.new(0.5, -(ROW_HEIGHT + 4), 1, 0),
			Parent = rowButton,
		})
		UIKit.Label({
			Name = "Stats",
			Text = statText(player),
			Font = Fonts.Body,
			TextSize = 14,
			TextColor3 = Colors.Muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0.5, -10, 1, 0),
			Parent = rowButton,
		})
		UIKit.SetSelectedFill(rowButton, player.UserId == selectedUserId, Colors.Panel2)
		rowButton.Activated:Connect(function()
			UIKit.SelectFeedback(rowButton)
			if selectedUserId ~= player.UserId then
				closeConfirm()
			end
			selectedUserId = player.UserId
			refreshPlayers()
		end)
	end
	local target = selectedPlayer()
	selectedLabel.Text = if target then ("Selected: %s"):format(target.DisplayName) else "Tap a player"
end

local function sendPlayerAction(action: string)
	local target = selectedPlayer()
	if target then
		RemoteEvents.AdminAction:FireServer({ Action = action, Args = { UserId = target.UserId } })
	end
end

local function startHold()
	if holdStarted then
		return
	end
	holdStarted = os.clock()
	holdConnection = RunService.Heartbeat:Connect(function()
		local began = holdStarted
		if not began then
			return
		end
		local left = AdminConfig.ResetHoldSeconds - (os.clock() - began)
		if left > 0 then
			UIKit.SetButton(holdButton, { Text = ("HOLD… %.1f s"):format(left) })
			return
		end
		closeConfirm()
		sendPlayerAction("ResetPlayer")
	end)
end

local function buildPlayers()
	heading("PLAYERS · this server only")
	playerRows = Instance.new("Frame")
	playerRows.Name = "PlayerRows"
	playerRows.BackgroundTransparency = 1
	playerRows.Size = UDim2.new(1, 0, 0, 0)
	playerRows.AutomaticSize = Enum.AutomaticSize.Y
	playerRows.LayoutOrder = nextOrder()
	playerRows.Parent = list
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 6)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = playerRows

	selectedLabel = UIKit.Label({
		Name = "Selected",
		Text = "Tap a player",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = nextOrder(),
		Parent = list,
	})
	local actions = row()
	button(actions, "↺ RESTART TUTORIAL", 220, "Blue", function()
		if selectedPlayer() then
			closeConfirm()
			sendPlayerAction("RestartTutorial")
		end
	end)
	button(actions, "⚠ RESET TO ZERO", 200, "Red", function()
		local target = selectedPlayer()
		if target then
			confirmLabel.Text = ("Reset %s to zero? This can't be undone."):format(target.DisplayName)
			confirmBox.Visible = true
		end
	end)

	confirmBox = Instance.new("Frame")
	confirmBox.Name = "ResetConfirm"
	confirmBox.BackgroundTransparency = 1
	confirmBox.Size = UDim2.new(1, 0, 0, 0)
	confirmBox.AutomaticSize = Enum.AutomaticSize.Y
	confirmBox.LayoutOrder = nextOrder()
	confirmBox.Visible = false
	confirmBox.Parent = list
	local confirmLayout = Instance.new("UIListLayout")
	confirmLayout.Padding = UDim.new(0, GAP)
	confirmLayout.SortOrder = Enum.SortOrder.LayoutOrder
	confirmLayout.Parent = confirmBox
	confirmLabel = UIKit.Label({
		Name = "Warning",
		Text = "",
		Font = Fonts.BodyHeavy,
		TextSize = 16,
		TextColor3 = Colors.Danger,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
		Parent = confirmBox,
	})
	local confirmActions = Instance.new("Frame")
	confirmActions.Name = "Row"
	confirmActions.BackgroundTransparency = 1
	confirmActions.Size = UDim2.new(1, 0, 0, TAP + UITheme.ShadowOffset)
	confirmActions.LayoutOrder = 2
	confirmActions.Parent = confirmBox
	local confirmRow = Instance.new("UIListLayout")
	confirmRow.FillDirection = Enum.FillDirection.Horizontal
	confirmRow.Padding = UDim.new(0, GAP)
	confirmRow.Parent = confirmActions
	holdButton = button(confirmActions, HOLD_TEXT, 220, "Red", function() end)
	holdButton.MouseButton1Down:Connect(startHold)
	holdButton.MouseButton1Up:Connect(stopHold)
	holdButton.MouseLeave:Connect(stopHold)
	button(confirmActions, "CANCEL", 120, UNSELECTED_STYLE, closeConfirm)

	Players.PlayerAdded:Connect(refreshPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPlayers)
	end)
	-- Rebirths and cash tick: refresh the list while the panel is open.
	task.spawn(function()
		while true do
			task.wait(2)
			if modal and modal.IsOpen() then
				refreshPlayers()
			end
		end
	end)
end

--[[ Build -------------------------------------------------------------------------- ]]

local function build(): UIKit.Modal
	local m = UIKit.Modal({
		Name = "AdminPanel",
		Title = "ADMIN ABUSE",
		DisplayOrder = 140,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.MythicBannerLeft,
	})
	m.Subtitle.Text = "Admins only · every action is logged"
	m.Subtitle.Visible = true

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.ZIndex = m.Content.ZIndex
	list.Parent = m.Content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local padding = Instance.new("UIPadding")
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = list

	buildPlayers()

	heading("TARGET")
	picker({ { Label = "THIS SERVER", Value = "Server" }, { Label = "ALL SERVERS", Value = "All" } }, 160, choice.Scope, function(value)
		choice.Scope = value
	end)

	heading("START EVENT")
	local events = {}
	for _, id in EventConfig.Order do
		table.insert(events, { Label = ("%s %s"):format(EventConfig.Icons[id] or "", EventConfig.Names[id] or id), Value = id })
	end
	picker(events, 170, choice.EventId, function(value)
		choice.EventId = value
	end)
	local strengths = {}
	for _, strength in AdminConfig.Strengths do
		table.insert(strengths, { Label = ("x%d"):format(strength), Value = strength })
	end
	picker(strengths, 70, choice.Strength, function(value)
		choice.Strength = value
	end)
	local durations = {}
	for _, minutes in AdminConfig.DurationMinutes do
		table.insert(durations, { Label = ("%d MIN"):format(minutes), Value = minutes })
	end
	picker(durations, 90, choice.Minutes, function(value)
		choice.Minutes = value
	end)
	local eventActions = row()
	button(eventActions, "START EVENT", 170, "Green", function()
		send("StartEvent", { Id = choice.EventId, Strength = choice.Strength, Minutes = choice.Minutes })
	end)
	button(eventActions, "END EVENT", 140, "Red", function()
		send("EndEvent", {})
	end)

	heading("GIFT EVERYONE · a random item of the tier")
	local tiers = {}
	for _, tier in AdminConfig.GiftTiers do
		table.insert(tiers, { Label = tier:upper(), Value = tier })
	end
	picker(tiers, 110, choice.Tier, function(value)
		choice.Tier = value
	end)
	local mutations = { { Label = "NO MUTATION", Value = "" } }
	for _, mutation in MutationConfig.Order do
		table.insert(mutations, { Label = mutation:upper(), Value = mutation })
	end
	picker(mutations, 120, choice.Mutation, function(value)
		choice.Mutation = value
	end)
	button(row(), "🎁 GIFT", 170, "Gold", function()
		send("Gift", { Tier = choice.Tier, Mutation = choice.Mutation })
	end)

	heading("LUCK")
	button(row(), ("🍀 LUCK x%d · %d MIN"):format(AdminConfig.LuckMultiplier, AdminConfig.LuckSeconds // 60), 220, "Teal", function()
		send("Luck", {})
	end)

	heading(("BROADCAST · max %d characters, filtered"):format(AdminConfig.BroadcastMaxChars))
	local boxRow = row()
	local boxHolder = Instance.new("Frame")
	boxHolder.Name = "BroadcastBox"
	boxHolder.BackgroundColor3 = Colors.Panel2
	boxHolder.Size = UDim2.new(1, -150, 0, TAP)
	boxHolder.LayoutOrder = nextOrder()
	boxHolder.Parent = boxRow
	UIKit.Corner(boxHolder, UITheme.Radius.Row)
	UIKit.Stroke(boxHolder, 2)
	broadcastBox = Instance.new("TextBox")
	broadcastBox.Name = "Text"
	broadcastBox.BackgroundTransparency = 1
	broadcastBox.ClearTextOnFocus = false
	broadcastBox.FontFace = Fonts.Body
	broadcastBox.TextSize = 16
	broadcastBox.TextColor3 = Colors.Text
	broadcastBox.PlaceholderText = "Type a banner for everyone…"
	broadcastBox.PlaceholderColor3 = Colors.Faint
	broadcastBox.Text = ""
	broadcastBox.TextXAlignment = Enum.TextXAlignment.Left
	broadcastBox.Position = UDim2.fromOffset(12, 0)
	broadcastBox.Size = UDim2.new(1, -60, 1, 0)
	broadcastBox.Parent = boxHolder
	countLabel = UIKit.Label({
		Name = "Count",
		Text = ("0/%d"):format(AdminConfig.BroadcastMaxChars),
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.Faint,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 44, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = boxHolder,
	})
	broadcastBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = broadcastBox.Text
		local length = utf8.len(text) or #text
		if length > AdminConfig.BroadcastMaxChars then
			local cut = utf8.offset(text, AdminConfig.BroadcastMaxChars + 1)
			broadcastBox.Text = if cut then text:sub(1, cut - 1) else text
			return
		end
		countLabel.Text = ("%d/%d"):format(length, AdminConfig.BroadcastMaxChars)
	end)
	button(boxRow, "📣 SEND", 130, "Blue", function()
		if broadcastBox.Text:match("%S") then
			send("Broadcast", { Text = broadcastBox.Text })
			broadcastBox.Text = ""
		end
	end)

	heading("NEXT ADMIN ABUSE · always all servers")
	abuseLabel = UIKit.Label({
		Name = "AbuseTime",
		Text = "",
		Font = Fonts.Display,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = nextOrder(),
		Stroke = UITheme.Stroke.Text,
		Parent = list,
	})
	local steps = row()
	local stepButtons: { { Label: string, Seconds: number } } = {
		{ Label = "-1 DAY", Seconds = -86400 },
		{ Label = "+1 DAY", Seconds = 86400 },
		{ Label = "-1 H", Seconds = -3600 },
		{ Label = "+1 H", Seconds = 3600 },
		{ Label = "-15 MIN", Seconds = -900 },
		{ Label = "+15 MIN", Seconds = 900 },
	}
	for _, step in stepButtons do
		button(steps, step.Label, 84, UNSELECTED_STYLE, function()
			stepAbuse(step.Seconds)
		end)
	end
	local abuseActions = row()
	button(abuseActions, "SET", 120, "Green", function()
		if choice.AbuseUnix > 0 then
			send("SetNextAdminAbuse", { Unix = choice.AbuseUnix })
		end
	end)
	button(abuseActions, "CLEAR", 120, "Red", function()
		choice.AbuseUnix = 0
		refreshAbuse()
		send("SetNextAdminAbuse", { Unix = 0 })
	end)
	refreshAbuse()
	return m
end

--[[ Public ---------------------------------------------------------------------------- ]]

-- Builds the panel on first use (the server only asks admins), then opens it.
function AdminPanel.Open(nextAdminAbuse: number?)
	local m: UIKit.Modal = modal or build()
	modal = m
	if nextAdminAbuse and nextAdminAbuse > Workspace:GetServerTimeNow() then
		choice.AbuseUnix = math.floor(nextAdminAbuse)
	end
	refreshAbuse()
	refreshPlayers()
	m.Open()
end

return AdminPanel
