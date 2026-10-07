--[[
	AnnouncementController
	----------------------
	Top-of-screen banners for one-off moments:
	  * server-wide RareFusionAnnouncement (someone fused/displayed a
	    Legendary or Mythic) - Mythic gets the bigger "SERVER · MYTHIC" variant
	  * server-wide RebirthAnnouncement - the same big kit as "SERVER · REBIRTH",
	    shown to everyone including the player who rebirthed
	  * your own events: multiplier upgrades, completed goals, and every
	    fusion success without a big card (your RevealRule; the banner says
	    "GOLDEN kept / rolled!" and replaces the skipped-card line)

	Queued by TopStack (one line at the top, 2.5 s each, capped at 4, the
	oldest dropped). Fusion banners are priority items: they jump the queue
	and the newest replaces any queued twin. Error messages (e.g. "Need $936 for
	a pull") are toasts now, not banners.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local TopStack = require(script.Parent.Parent.UI.TopStack)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)
local FusionController = require(script.Parent.FusionController)
local ResultController = require(script.Parent.ResultController)
local ToastController = require(script.Parent.ToastController)
local ShopController = require(script.Parent.ShopController)

local AnnouncementController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local BANNER_WIDTH = 520
local BANNER_HEIGHT = 64
local SMALL_BANNER_TEXT_MAX = 21
local SMALL_BANNER_TEXT_MIN = 14
local MYTHIC_BANNER_HEIGHT = 84
local SLIDE_IN_SECONDS = 0.35
local SLIDE_OUT_SECONDS = 0.3
local HOLD_SECONDS = TopStack.DEFAULT_SECONDS
local MYTHIC_HOLD_SECONDS = 4
local MYTHIC_SHAKE_MAGNITUDE_STUDS = 0.35
local MYTHIC_SHAKE_DURATION_SECONDS = 0.5

-- The bigger server-wide banner: caption, left->right gradient, an emblem.
type BigStyle = {
	Caption: string,
	CaptionColor: Color3,
	Left: Color3,
	Right: Color3,
	Stops: { Color3 }?, -- a multi-stop gradient instead of Left -> Right
	Emblem: () -> GuiObject,
	Shake: boolean,
}

type Announcement = {
	Text: string, -- RichText
	AccentColor: Color3,
	Big: BigStyle?, -- the bigger server-wide variant
	Priority: number?, -- 1: jumps the queue (your own big success)
	Key: string?, -- a queued item with the same key is replaced
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

-- A disc on the rainbow gradient.
local function rainbowEmblem(): GuiObject
	local disc = Instance.new("Frame")
	disc.Name = "RainbowEmblem"
	disc.Size = UDim2.fromOffset(50, 50)
	disc.BackgroundColor3 = Colors.White
	UIKit.Corner(disc, 999)
	UIKit.Stroke(disc, 3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = UITheme.GetRainbowSequence()
	gradient.Rotation = 45
	gradient.Parent = disc
	return disc
end

local RAINBOW_STYLE: BigStyle = {
	Caption = "SERVER · RAINBOW",
	CaptionColor = Colors.White,
	Left = UITheme.Mutation.RainbowStops[1],
	Right = UITheme.Mutation.RainbowStops[#UITheme.Mutation.RainbowStops],
	Stops = UITheme.Mutation.RainbowStops,
	Emblem = rainbowEmblem,
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

local screenGui: ScreenGui

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
		local stops = { { 0, big.Left }, { 1, big.Right } }
		if big.Stops then
			stops = {}
			for index, color in big.Stops do
				table.insert(stops, { (index - 1) / (#big.Stops - 1), color })
			end
		end
		UIKit.Gradient(body, stops, 0)
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
			Stroke = if UITheme.IsWarm(big.Left) then 1.5 else nil,
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
		-- Scales down (21 → 14 px) so a long line ("FUSION SUCCESS! → EPIC
		-- Golden Plasma Orb · GOLDEN kept") fits before it truncates.
		local message = UIKit.Label({
			Name = "Message",
			Text = announcement.Text,
			RichText = true,
			Font = Fonts.Display,
			TextSize = SMALL_BANNER_TEXT_MAX,
			TextScaled = true,
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -48, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = z,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = SMALL_BANNER_TEXT_MAX
		cap.MinTextSize = SMALL_BANNER_TEXT_MIN
		cap.Parent = message
	end

	return holder
end

--[[ Queue ---------------------------------------------------------------------- ]]

-- Hands the banner to TopStack: it builds it at the announcement slot's y,
-- holds it, and slides it out.
local function enqueue(announcement: Announcement)
	local big = announcement.Big
	local height = if big then MYTHIC_BANNER_HEIGHT else BANNER_HEIGHT
	local banner: Frame? = nil
	TopStack.Announce({
		Key = announcement.Key,
		Priority = announcement.Priority,
		Seconds = if big then MYTHIC_HOLD_SECONDS else HOLD_SECONDS,
		Height = height + UITheme.ShadowOffset,
		Show = function(y: number)
			local built = buildBanner(announcement)
			banner = built
			SoundKit.Play("Toast", built, { Volume = if big then 1.4 else 1 })
			TweenService:Create(
				built,
				TweenInfo.new(SLIDE_IN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.5, 0, 0, y) }
			):Play()
			if big and big.Shake then
				RevealEffects.ShakeCamera(MYTHIC_SHAKE_MAGNITUDE_STUDS, MYTHIC_SHAKE_DURATION_SECONDS)
			end
		end,
		Move = function(y: number)
			local shown = banner
			if shown then
				shown.Position = UDim2.new(0.5, 0, 0, y)
			end
		end,
		Hide = function(cut: boolean): number?
			local shown = banner
			banner = nil
			if not shown then
				return nil
			end
			if cut then
				-- Preempted: swapped out in place, no slide-out.
				shown:Destroy()
				return nil
			end
			local slideOut = TweenService:Create(
				shown,
				TweenInfo.new(SLIDE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = hiddenPosition(height) }
			)
			slideOut:Play()
			slideOut.Completed:Once(function()
				shown:Destroy()
			end)
			return SLIDE_OUT_SECONDS
		end,
	})
end

-- Your own big success: front of the queue, newest replaces its twin.
local function enqueueInstant(announcement: Announcement)
	announcement.Priority = 1
	announcement.Key = announcement.Key or "Instant"
	enqueue(announcement)
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
	local mutation = if MutationConfig.IsValid(payload.Mutation) then payload.Mutation :: string else nil
	local verb = if payload.Verb == "displayed"
		then "just displayed"
		elseif payload.Verb == "pulled" then "pulled"
		elseif payload.Verb == "grabbed" then "grabbed"
		else "fused"
	local text: string
	if typeof(payload.PlayerName) == "string" and typeof(payload.ItemName) == "string" then
		local who = UIKit.EscapeRichText(payload.PlayerName)
		-- A stacked item's banner names the whole stack; `mutation` is its top.
		local events = MutationConfig.SanitizeEvents(payload.EventMutations)
		local base = if mutation and not MutationConfig.IsEventOnly(mutation) then mutation else nil
		local name = UIKit.EscapeRichText(
			if events then MutationConfig.GetDisplayName(payload.ItemName, base, events)
				else MutationConfig.GetDisplayName(payload.ItemName, mutation)
		)
		local mutationColor = UITheme.GetMutationColor(mutation)
		if payload.Verb == "event" and mutation then
			-- An event-only mutation: a SERVER banner at any tier, in its colour.
			local label = if events then MutationConfig.GetStackLabel(base, events) else mutation:upper()
			local word = UIKit.Colored(UIKit.EscapeRichText(label), mutationColor or Colors.Text)
			local item = UIKit.EscapeRichText(payload.ItemName)
			local line = if payload.Source == "VoidMoon"
				then ("%s got a %s %s under the Void Moon!"):format(who, word, item)
				elseif payload.Source == "Lightning" then ("%s's %s got %s by lightning!"):format(who, item, word)
				elseif payload.Source == "Meteor" then ("%s found a %s %s in a meteor!"):format(who, word, item)
				else ("%s got a %s %s!"):format(who, word, item)
			enqueue({
				Text = line,
				AccentColor = mutationColor or Colors.Text,
				Big = {
					Caption = "SERVER · EVENT MUTATION",
					CaptionColor = mutationColor or Colors.White,
					Left = UITheme.TowardInk(mutationColor or Colors.Panel, 0.55),
					Right = Colors.Panel,
					Emblem = function()
						return UIKit.TierOrb(tier, 50, nil, mutation)
					end,
					Shake = false,
				},
			})
			return
		elseif payload.Verb == "charged" then
			-- "Har's Charged Rift Engine got CHARGED!" (Power Surge lightning)
			text = ("%s's %s got %s!"):format(who, UIKit.Colored(name, UITheme.GetTierLight(tier)), UIKit.Colored("CHARGED", mutationColor or Colors.Text))
		elseif payload.Verb == "grabbed" then
			-- "Har grabbed a Celestial Star Core from a meteor!"
			text = ("%s grabbed a %s from a meteor!"):format(who, UIKit.Colored(name, mutationColor or UITheme.GetTierLight(tier)))
		elseif mutation == "Rainbow" then
			-- "Har pulled a Rainbow Star Core!"
			text = ("%s %s a %s!"):format(who, verb, name)
		elseif tier == "Secret" and payload.Verb ~= "displayed" then
			-- "Har found Event Horizon!"
			text = ("%s found %s!"):format(who, UIKit.Colored(name, UITheme.GetTierLight(tier)))
		else
			text = ("%s %s a %s %s!"):format(who, verb, tierWord(tier), name)
		end
	else
		text = UIKit.EscapeRichText(tostring(payload.Message))
	end
	enqueue({
		Text = text,
		AccentColor = FusionConfig.TierAccentColors[tier] or Colors.Text,
		Big = if mutation == "Rainbow"
			then RAINBOW_STYLE
			elseif tier == "Secret" then SECRET_STYLE
			elseif tier == "Mythic" then MYTHIC_STYLE
			else nil,
	})
end

-- "Har stole a Golden Rift Engine from Bob!" (Legendary+ only; the server
-- filters). The mutation word in its colour, the item in its tier's.
local function heistItemText(payload: any): string
	local def = typeof(payload.ItemId) == "string" and ItemConfig.GetItemById(payload.ItemId) or nil
	local tier = if typeof(payload.Tier) == "string" then payload.Tier else "Legendary"
	local base = UIKit.Colored(UIKit.EscapeRichText(def and def.Name or tostring(payload.ItemName)), UITheme.GetTierLight(tier))
	local mutation = if typeof(payload.Mutation) == "string" then payload.Mutation else nil
	local color = UITheme.GetMutationColor(mutation)
	if mutation and color then
		return UIKit.Colored(mutation, color) .. " " .. base
	end
	return base
end

local function onHeistFeed(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Thief) ~= "string" or typeof(payload.Victim) ~= "string" then
		return
	end
	local thief = UIKit.EscapeRichText(payload.Thief)
	local victim = UIKit.EscapeRichText(payload.Victim)
	local text
	if payload.Kind == "Stole" then
		text = ("%s stole a %s from %s!"):format(thief, heistItemText(payload), victim)
	elseif payload.Kind == "Caught" then
		text = ("%s caught %s!"):format(victim, thief)
	elseif payload.Kind == "Grab" then
		text = ("%s is stealing %s's %s!"):format(thief, victim, heistItemText(payload))
	else
		return
	end
	enqueue({ Text = text, AccentColor = Colors.Danger })
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
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Success == false then
		if payload.Reason == "InsufficientCash" and typeof(payload.Cost) == "number" then
			ToastController.Show(("Need %s"):format(NumberFormat.Money(payload.Cost)), "Error")
			ShopController.OfferForShortfall("Multiplier Pad", payload.Cost)
		end
		return
	end
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
		ShopController.OfferForShortfall("Gacha pull", payload.Cost)
	end
end

local showFusionBanner: (newItem: any, sourceLine: string?) -> ()

-- Shown after the Fusion Machine's reveal finishes, so it never spoils it.
local function onFusionResolved(result: any)
	if not result or not result.Success or not result.NewItem or not result.Upgraded then
		return
	end
	local newItem = result.NewItem
	-- Big-card results (the player's RevealRule) and event mutations get
	-- their card instead; fails get the fail card. Same rule that keeps the
	-- skipped line off (ResultController.FusionBannerShows).
	if not ResultController.FusionBannerShows(result) then
		return
	end
	showFusionBanner(
		newItem,
		ResultController.GetMutationSourceLine(
			MutationConfig.GetStackLabel(newItem.Mutation, newItem.EventMutations),
			result.MutationSource
		)
	)
end

-- /trailer: your own "FUSION SUCCESS!" banner for a local item (no rule
-- check: the shot needs it even for a big-card tier).
function AnnouncementController.PreviewFusionBanner(newItem: any)
	if typeof(newItem) == "table" and typeof(newItem.Tier) == "string" then
		showFusionBanner(newItem, nil)
	end
end

showFusionBanner = function(newItem: any, sourceLine: string?)
	local tier = newItem.Tier :: string
	local def = ItemConfig.GetItemById(newItem.ItemId)
	local name = UIKit.EscapeRichText(
		MutationConfig.GetDisplayName(def and def.Name or tostring(newItem.ItemId), newItem.Mutation, newItem.EventMutations)
	)
	local mutationColor = UITheme.GetMutationColor(MutationConfig.GetTop(newItem.Mutation, newItem.EventMutations))
	enqueueInstant({
		Text = ("FUSION SUCCESS! → %s %s%s"):format(
			tierWord(tier),
			if mutationColor then UIKit.Colored(name, mutationColor) else name,
			if sourceLine and mutationColor then " · " .. UIKit.Colored(UIKit.EscapeRichText(sourceLine), mutationColor) else ""
		),
		AccentColor = FusionConfig.TierAccentColors[tier] or Colors.Text,
	})
end

-- Rainbow Storm's server-wide hype banner (every client sees the event at
-- once; this is the big rainbow kit on top of the event's own banner).
function AnnouncementController.ShowEventHype(text: string)
	enqueue({
		Text = UIKit.EscapeRichText(text),
		AccentColor = UITheme.Mutation.RainbowStops[1],
		Big = {
			Caption = "SERVER · EVENT",
			CaptionColor = Colors.White,
			Left = RAINBOW_STYLE.Left,
			Right = RAINBOW_STYLE.Right,
			Stops = RAINBOW_STYLE.Stops,
			Emblem = rainbowEmblem,
			Shake = false,
		},
	})
end

-- An admin's broadcast (already filtered on the server): the big banner
-- in the Heist red, "SERVER · ADMIN".
function AnnouncementController.ShowAdminBroadcast(text: string)
	enqueue({
		Text = "📣 " .. UIKit.EscapeRichText(text),
		AccentColor = Colors.Danger,
		Big = {
			Caption = "SERVER · ADMIN",
			CaptionColor = Colors.MythicBannerLabel,
			Left = UITheme.Gradients.Heist.Bottom,
			Right = Colors.Panel,
			Emblem = rainbowEmblem,
			Shake = false,
		},
	})
end

-- The Server Overclock: "⚡ Harris overclocked the server! ×2 income for
-- everyone" on the big gold banner, for everyone.
function AnnouncementController.ShowOverclock(playerName: string, seconds: number)
	enqueue({
		Text = ("⚡ %s overclocked the server! ×%d income for everyone · %d min"):format(
			UIKit.EscapeRichText(playerName),
			ShopConfig.OverclockMultiplier,
			math.max(1, math.floor(seconds / 60))
		),
		AccentColor = UITheme.World.VipGold,
		Big = {
			Caption = "SERVER · OVERCLOCK",
			-- White on the gold end (the contrast rule), not gold-on-gold.
			CaptionColor = Colors.Text,
			Left = UITheme.Gradients.Gold.Bottom,
			Right = Colors.Panel,
			Emblem = rainbowEmblem,
			Shake = false,
		},
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
	RemoteEvents.HeistFeed.OnClientEvent:Connect(onHeistFeed)
	RemoteEvents.ShopAnnouncement.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and payload.Kind == "Overclock" and typeof(payload.PlayerName) == "string" then
			local seconds = if typeof(payload.Seconds) == "number" then payload.Seconds else ShopConfig.OverclockSeconds
			AnnouncementController.ShowOverclock(payload.PlayerName, seconds)
		end
	end)
end

return AnnouncementController
