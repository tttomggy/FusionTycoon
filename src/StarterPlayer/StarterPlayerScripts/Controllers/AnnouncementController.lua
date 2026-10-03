--[[
	AnnouncementController
	----------------------
	Top-of-screen banners for one-off moments:
	  * server-wide RareFusionAnnouncement (someone fused/displayed a
	    Legendary or Mythic) - Mythic gets the bigger "SERVER · MYTHIC" variant
	  * server-wide RebirthAnnouncement - the same big kit as "SERVER · REBIRTH",
	    shown to everyone including the player who rebirthed
	  * your own events: multiplier upgrades, completed goals, and Rare-tier
	    fusion successes (Epic+ get ResultController's big card instead)

	Queued so a burst plays one at a time. Fusion banners are "instant": the
	newest replaces whatever is showing. Error messages (e.g. "Need $936 for
	a pull") are toasts now, not banners.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local FusionController = require(script.Parent.FusionController)
local ResultController = require(script.Parent.ResultController)
local ToastController = require(script.Parent.ToastController)

local AnnouncementController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local BANNER_WIDTH = 520
local BANNER_HEIGHT = 64
local MYTHIC_BANNER_HEIGHT = 84
local VISIBLE_Y = 24
local SLIDE_IN_SECONDS = 0.35
local SLIDE_OUT_SECONDS = 0.3
local HOLD_SECONDS = 3.5
local MYTHIC_HOLD_SECONDS = 5
local MYTHIC_SHAKE_MAGNITUDE_STUDS = 0.35
local MYTHIC_SHAKE_DURATION_SECONDS = 0.5
-- The one sound id proven to load in this project (see RevealEffects).
local SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
-- How often a hold re-checks for a newer instant banner preempting it.
local HOLD_POLL_SECONDS = 0.1

-- The bigger server-wide banner: caption, left->right gradient, an emblem.
type BigStyle = {
	Caption: string,
	CaptionColor: Color3,
	Left: Color3,
	Right: Color3,
	Emblem: () -> GuiObject,
	Shake: boolean,
}

type Announcement = {
	Text: string, -- RichText
	AccentColor: Color3,
	Big: BigStyle?, -- the bigger server-wide variant
	Instant: boolean?,
}

local MYTHIC_STYLE: BigStyle = {
	Caption = "SERVER · MYTHIC",
	CaptionColor = Colors.MythicBannerLabel,
	Left = Colors.MythicBannerLeft,
	Right = Colors.Panel,
	Emblem = function()
		return UIKit.TierOrb("Mythic", 50)
	end,
	Shake = true,
}

-- A rebirth "⟳" disc in the Orange gradient.
local function rebirthEmblem(): GuiObject
	local disc = Instance.new("Frame")
	disc.Name = "RebirthEmblem"
	disc.Size = UDim2.fromOffset(50, 50)
	disc.BackgroundColor3 = Colors.White
	UIKit.Corner(disc, 999)
	UIKit.Stroke(disc, 3)
	UIKit.PairGradient(disc, UITheme.Gradients.Orange)
	UIKit.Label({
		Name = "Glyph",
		Text = "⟳",
		Font = Fonts.Display,
		TextSize = 30,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Stroke = UITheme.Stroke.Text,
		Parent = disc,
	})
	return disc
end

local SECRET_STYLE: BigStyle = {
	Caption = "SERVER · SECRET",
	CaptionColor = UITheme.GetTierLight("Secret"),
	Left = Colors.Ink,
	Right = UITheme.GetTierOrb("Secret").Dark,
	Emblem = function()
		return UIKit.TierOrb("Secret", 50)
	end,
	Shake = true,
}

local REBIRTH_STYLE: BigStyle = {
	Caption = "SERVER · REBIRTH",
	CaptionColor = Colors.RebirthLabel,
	Left = Colors.RebirthBannerLeft,
	Right = Colors.Rebirth,
	Emblem = rebirthEmblem,
	Shake = false,
}

local queue: { Announcement } = {}
local isProcessing = false
-- Bumped whenever an instant announcement preempts the current one; a hold
-- whose generation goes stale exits early without sliding out.
local displayGeneration = 0

local screenGui: ScreenGui
local currentBanner: Frame? = nil

--[[ Banner construction ------------------------------------------------------- ]]

local function hiddenPosition(height: number): UDim2
	return UDim2.new(0.5, 0, 0, -(height + 20))
end

local function buildBanner(announcement: Announcement): Frame
	local big = announcement.Big
	local height = if big then MYTHIC_BANNER_HEIGHT else BANNER_HEIGHT
	local gradient = if big
		then nil
		else { { 0, Colors.Panel2 }, { 1, Colors.Panel } }

	local body, holder = UIKit.Panel({
		Name = "Banner",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = hiddenPosition(height),
		Size = UDim2.fromOffset(BANNER_WIDTH, height),
		Gradient = gradient,
		Radius = 18,
		ZIndex = 2,
	})
	if big then
		-- Horizontal: the style's dark colour on the left fading right.
		body.BackgroundColor3 = Colors.White
		UIKit.Gradient(body, { { 0, big.Left }, { 1, big.Right } }, 0)
	end
	local z = body.ZIndex + 1

	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.BackgroundColor3 = announcement.AccentColor
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(10, 10)
	bar.Size = UDim2.new(0, 10, 1, -20)
	bar.ZIndex = z
	bar.Parent = body
	UIKit.Corner(bar, 5)

	if big then
		local emblem = big.Emblem()
		emblem.AnchorPoint = Vector2.new(0, 0.5)
		emblem.Position = UDim2.new(0, 32, 0.5, 0)
		emblem.ZIndex = z
		emblem.Parent = body

		UIKit.Label({
			Name = "Caption",
			Text = big.Caption,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			TextColor3 = big.CaptionColor,
			Position = UDim2.fromOffset(96, 14),
			Size = UDim2.new(1, -112, 0, 16),
			ZIndex = z,
			Parent = body,
		})
		UIKit.Label({
			Name = "Message",
			Text = announcement.Text,
			RichText = true,
			Font = Fonts.Display,
			TextSize = 25,
			Position = UDim2.fromOffset(96, 32),
			Size = UDim2.new(1, -112, 0, 36),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = z,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
	else
		UIKit.Label({
			Name = "Message",
			Text = announcement.Text,
			RichText = true,
			Font = Fonts.Display,
			TextSize = 21,
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -48, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = z,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
	end

	return holder
end

--[[ Queue ---------------------------------------------------------------------- ]]

local function processQueue()
	if isProcessing then
		return
	end
	isProcessing = true

	task.spawn(function()
		while #queue > 0 do
			local announcement = table.remove(queue, 1) :: Announcement
			local myGeneration = displayGeneration
			local big = announcement.Big
			local height = if big then MYTHIC_BANNER_HEIGHT else BANNER_HEIGHT

			-- A preempted banner is swapped out in place, no slide-out.
			if currentBanner then
				(currentBanner :: Frame):Destroy()
			end
			local banner = buildBanner(announcement)
			currentBanner = banner

			local sound = Instance.new("Sound")
			sound.SoundId = SOUND_ID
			sound.Volume = if big then 1 else 0.7
			sound.Parent = banner
			sound:Play()
			Debris:AddItem(sound, 3)

			TweenService:Create(
				banner,
				TweenInfo.new(SLIDE_IN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, VISIBLE_Y) }
			):Play()
			if big and big.Shake then
				RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE_STUDS, MYTHIC_SHAKE_DURATION_SECONDS)
			end

			local holdSeconds = SLIDE_IN_SECONDS + (if big then MYTHIC_HOLD_SECONDS else HOLD_SECONDS)
			local elapsed = 0
			while elapsed < holdSeconds and displayGeneration == myGeneration do
				local step = math.min(HOLD_POLL_SECONDS, holdSeconds - elapsed)
				task.wait(step)
				elapsed += step
			end

			if displayGeneration == myGeneration then
				local slideOut = TweenService:Create(
					banner,
					TweenInfo.new(SLIDE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = hiddenPosition(height) }
				)
				slideOut:Play()
				slideOut.Completed:Wait()
				if currentBanner == banner then
					banner:Destroy()
					currentBanner = nil
				end
			end
		end
		isProcessing = false
	end)
end

-- FIFO: plays out in full, never interrupting another.
local function enqueue(announcement: Announcement)
	table.insert(queue, announcement)
	processQueue()
end

-- Newest wins: drops queued instants, jumps the queue, cuts the current hold.
local function enqueueInstant(announcement: Announcement)
	announcement.Instant = true
	for i = #queue, 1, -1 do
		if queue[i].Instant then
			table.remove(queue, i)
		end
	end
	table.insert(queue, 1, announcement)
	displayGeneration += 1
	processQueue()
end

--[[ Event handlers --------------------------------------------------------------- ]]

local function tierWord(tier: string): string
	return UIKit.Colored(tier:upper(), UITheme.GetTierLight(tier))
end

local function onRareFusionAnnouncement(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Tier) ~= "string" then
		return
	end
	local tier = payload.Tier :: string
	local text: string
	if typeof(payload.PlayerName) == "string" and typeof(payload.ItemName) == "string" then
		text = ("%s %s a %s %s!"):format(
			UIKit.EscapeRichText(payload.PlayerName),
			if payload.Verb == "displayed" then "just displayed" else "fused",
			tierWord(tier),
			UIKit.EscapeRichText(payload.ItemName)
		)
	else
		text = UIKit.EscapeRichText(tostring(payload.Message))
	end
	enqueue({
		Text = text,
		AccentColor = FusionConfig.TierAccentColors[tier] or Colors.Text,
		Big = if tier == "Secret" then SECRET_STYLE elseif tier == "Mythic" then MYTHIC_STYLE else nil,
	})
end

local function onRebirthAnnouncement(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Name) ~= "string" or typeof(payload.Rebirths) ~= "number" then
		return
	end
	enqueue({
		Text = ("%s reached %s!"):format(
			UIKit.EscapeRichText(payload.Name),
			UIKit.Colored(("Rebirth %d"):format(payload.Rebirths), Colors.RebirthLabel)
		),
		AccentColor = Colors.Rebirth,
		Big = REBIRTH_STYLE,
	})
end

local function onMultiplierUpgraded(payload: any)
	enqueue({
		Text = ("Multiplier upgraded! %s → %s"):format(
			UIKit.Colored(NumberFormat.Multiplier(payload.OldMultiplier), Colors.VioletLight),
			UIKit.Colored(NumberFormat.Multiplier(payload.NewMultiplier), Colors.VioletLight)
		),
		AccentColor = UITheme.Gradients.Violet.Bottom,
	})
end

local function onGoalCompleted(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Reward) ~= "number" then
		return
	end
	enqueue({
		Text = ("Goal complete! %s"):format(UIKit.Colored("+" .. NumberFormat.Money(payload.Reward), Colors.Goal)),
		AccentColor = Colors.Goal,
	})
end

local function onGachaPullResult(payload: any)
	-- Successful pulls are ResultController's pull/result cards.
	if typeof(payload) == "table" and not payload.Success and payload.Reason == "InsufficientCash" and payload.Cost then
		ToastController.Show(("Need %s for a pull"):format(NumberFormat.Money(payload.Cost)), "Error")
	end
end

-- Shown after the Fusion Machine's reveal finishes, so it never spoils it.
local function onFusionResolved(result: any)
	if not result or not result.Success or not result.NewItem or not result.Upgraded then
		return
	end
	local newItem = result.NewItem
	local tier = newItem.Tier :: string
	-- Epic+ get the big result card; fails get the fail card.
	if ResultController.ShowsBigCardFor(tier) then
		return
	end
	local def = ItemConfig.GetItemById(newItem.ItemId)
	enqueueInstant({
		Text = ("FUSION SUCCESS! → %s %s"):format(
			tierWord(tier),
			UIKit.EscapeRichText(def and def.Name or tostring(newItem.ItemId))
		),
		AccentColor = FusionConfig.TierAccentColors[tier] or Colors.Text,
	})
end

function AnnouncementController.Init()
	screenGui = UIKit.Screen("Announcements", 100)
	FusionController.FusionResolved:Connect(onFusionResolved)
	RemoteEvents.RareFusionAnnouncement.OnClientEvent:Connect(onRareFusionAnnouncement)
	RemoteEvents.MultiplierUpgraded.OnClientEvent:Connect(onMultiplierUpgraded)
	RemoteEvents.GachaPullResult.OnClientEvent:Connect(onGachaPullResult)
	RemoteEvents.GoalCompleted.OnClientEvent:Connect(onGoalCompleted)
	RemoteEvents.RebirthAnnouncement.OnClientEvent:Connect(onRebirthAnnouncement)
end

return AnnouncementController
