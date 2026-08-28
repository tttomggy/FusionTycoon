-- Shows a brief on-screen banner/toast for three kinds of one-off feedback:
-- server-wide RareFusionAnnouncement events (a Legendary/Mythic item was
-- just displayed on someone's Pedestal Showcase), the local player's own
-- MultiplierUpgraded purchases, and the local player's own GachaPullResult
-- pulls. Built entirely in Luau (no StarterGui asset in this project) and
-- queued so a burst of announcements displays one at a time instead of
-- stacking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local RarityVisuals = require(ReplicatedStorage.Shared.Config.RarityVisuals)
local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local RevealEffects = require(script.Parent.Parent.Effects.RevealEffects)

local AnnouncementController = {}

local BANNER_SIZE = UDim2.fromOffset(520, 64)
local BANNER_VISIBLE_POSITION = UDim2.new(0.5, -260, 0, 24)
local BANNER_HIDDEN_POSITION = UDim2.new(0.5, -260, 0, -100)
local SLIDE_IN_SECONDS = 0.35
local SLIDE_OUT_SECONDS = 0.3
local HOLD_SECONDS = 3.5
-- Gacha pulls landing on a FusionConfig.MajorRevealTiers tier (Epic/Legendary/
-- Mythic) hold longer and shake the camera, mirroring the Fusion Machine's own
-- "big reveal" treatment in RevealEffects.PlayReveal - same dramatic weight,
-- reused rather than re-invented for a second rarity payoff moment.
local MAJOR_HOLD_SECONDS = 5
local MAJOR_SHAKE_MAGNITUDE_STUDS = 0.35
local MAJOR_SHAKE_DURATION_SECONDS = 0.5
-- rbxasset://sounds/bell.wav fails to load in this project ("Temp read
-- failed") - confirmed broken everywhere it was referenced, not just here.
-- electronicpingshort.wav is the one sound ID already proven to load
-- correctly elsewhere in the game (DropperService's per-drop pop, and
-- RevealEffects' own minor fusion reveal), so it's reused here instead of a
-- second untested asset ID.
local SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
-- Matches MULTIPLIER_UPGRADE_ACCENT_COLOR in TycoonService.lua (the pad's own accent).
local MULTIPLIER_ACCENT_COLOR = Color3.fromRGB(200, 60, 255)
-- How often the hold-wait below re-checks displayGeneration for an early-exit
-- request from a newer Instant (Gacha) announcement.
local HOLD_POLL_SECONDS = 0.1

local queue: { any } = {}
local isProcessing = false
-- Bumped every time an Instant announcement (a Gacha pull) preempts whatever's
-- currently showing. The in-flight hold-wait in processQueue compares its own
-- captured generation against this and exits early - without playing the
-- slide-out tween - the moment it goes stale, so a burst of pulls reads as
-- one continuously-updating banner instead of a stack of toasts.
local displayGeneration = 0

local screenGui: ScreenGui? = nil
local banner: Frame? = nil
local label: TextLabel? = nil
local accentBar: Frame? = nil

local function buildUI()
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "RareFusionAnnouncements"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100

	local frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.Size = BANNER_SIZE
	frame.Position = BANNER_HIDDEN_POSITION
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.Size = UDim2.new(0, 6, 1, 0)
	bar.BorderSizePixel = 0
	bar.Parent = frame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 10)
	barCorner.Parent = bar

	local text = Instance.new("TextLabel")
	text.Name = "Message"
	text.Size = UDim2.new(1, -30, 1, 0)
	text.Position = UDim2.new(0, 20, 0, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	text.Parent = frame

	gui.Parent = playerGui

	screenGui = gui
	banner = frame
	label = text
	accentBar = bar
end

local function processQueue()
	if isProcessing then
		return
	end
	isProcessing = true

	task.spawn(function()
		while #queue > 0 do
			local announcement = table.remove(queue, 1)
			local myGeneration = displayGeneration

			-- A statement ending in an expression followed by a line that
			-- starts with "(" is ambiguous in Lua (looks like a function
			-- call spanning both lines), so these go through local variables
			-- instead of an inline `(x :: T).Field = ...` cast.
			local currentLabel = label :: TextLabel
			local currentAccentBar = accentBar :: Frame
			currentLabel.Text = announcement.Message
			currentAccentBar.BackgroundColor3 = announcement.AccentColor

			local isMajor = announcement.IsMajor == true

			local sound = Instance.new("Sound")
			sound.SoundId = SOUND_ID
			sound.Volume = if isMajor then 1 else 0.7
			sound.Parent = banner :: Frame
			sound:Play()
			Debris:AddItem(sound, 3)

			TweenService:Create(
				banner :: Frame,
				TweenInfo.new(SLIDE_IN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = BANNER_VISIBLE_POSITION }
			):Play()

			if isMajor then
				RevealEffects.ShakeCamera(MAJOR_SHAKE_MAGNITUDE_STUDS, MAJOR_SHAKE_DURATION_SECONDS)
			end

			-- Polls in small steps instead of one task.wait(...) so an Instant
			-- announcement queued mid-hold (see enqueueInstant) can cut this
			-- short the moment it lands, rather than waiting out the full
			-- duration of a banner that's already stale.
			local holdSeconds = SLIDE_IN_SECONDS + (if isMajor then MAJOR_HOLD_SECONDS else HOLD_SECONDS)
			local elapsed = 0
			while elapsed < holdSeconds and displayGeneration == myGeneration do
				local step = math.min(HOLD_POLL_SECONDS, holdSeconds - elapsed)
				task.wait(step)
				elapsed += step
			end

			-- Only slide back out if nothing newer preempted this banner
			-- while it was holding - skipping the slide-out lets a
			-- newer Instant announcement swap straight into the still-visible
			-- banner next loop iteration instead of flickering closed and
			-- reopening.
			if displayGeneration == myGeneration then
				local slideOut = TweenService:Create(
					banner :: Frame,
					TweenInfo.new(SLIDE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = BANNER_HIDDEN_POSITION }
				)
				slideOut:Play()
				slideOut.Completed:Wait()
			end
		end
		isProcessing = false
	end)
end

-- Regular (FIFO) announcements: RareFusion/MultiplierUpgraded queue up and
-- each plays out in full, never interrupting one another.
local function enqueue(announcement: any)
	table.insert(queue, announcement)
	processQueue()
end

-- Instant announcements (Gacha pulls only): the newest pull always wins.
-- Drops any of its own kind still waiting in the queue (so a fast burst of
-- pulls doesn't play catch-up one at a time), puts itself at the front, and
-- bumps displayGeneration so whatever's currently showing - Gacha or
-- otherwise - abandons its hold immediately instead of finishing first.
local function enqueueInstant(announcement: any)
	for i = #queue, 1, -1 do
		if queue[i].Instant then
			table.remove(queue, i)
		end
	end
	table.insert(queue, 1, announcement)
	displayGeneration += 1
	processQueue()
end

local function onRareFusionAnnouncement(payload: any)
	local tierVisual = RarityVisuals.Tiers[payload.Tier]
	enqueue({
		Message = payload.Message,
		AccentColor = (tierVisual and tierVisual.GlowColor) or Color3.new(1, 1, 1),
	})
end

local function onMultiplierUpgraded(payload: any)
	enqueue({
		Message = ("Multiplier Upgraded! x%d -> x%d"):format(payload.OldMultiplier, payload.NewMultiplier),
		AccentColor = MULTIPLIER_ACCENT_COLOR,
	})
end

-- Every current ItemConfig entry already spells its own tier out in its Name
-- (e.g. "Common Spark"), so blindly prepending the tier again reads
-- redundantly ("You pulled a COMMON Common Spark!"). Only prepend it when the
-- item's own name doesn't already start with it, so a future item whose name
-- doesn't encode its tier still reads correctly either way.
local function buildGachaPullMessage(tier: string, itemName: string): string
	if itemName:sub(1, #tier):lower() == tier:lower() then
		return ("You pulled a %s!"):format(itemName)
	end
	return ("You pulled a %s %s!"):format(tier:upper(), itemName)
end

local function onGachaPullResult(payload: any)
	if not payload.Success or not payload.NewItem then
		return
	end

	local newItem = payload.NewItem
	local tier = newItem.Tier :: string
	local itemConfigEntry = ItemConfig.GetItemById(newItem.ItemId)
	local itemName = itemConfigEntry and itemConfigEntry.Name or newItem.ItemId
	local tierVisual = RarityVisuals.Tiers[tier]

	enqueueInstant({
		Message = buildGachaPullMessage(tier, itemName),
		AccentColor = (tierVisual and tierVisual.GlowColor) or Color3.new(1, 1, 1),
		IsMajor = FusionConfig.MajorRevealTiers[tier] == true,
		Instant = true,
	})
end

function AnnouncementController.Init()
	buildUI()
	RemoteEvents.RareFusionAnnouncement.OnClientEvent:Connect(onRareFusionAnnouncement)
	RemoteEvents.MultiplierUpgraded.OnClientEvent:Connect(onMultiplierUpgraded)
	RemoteEvents.GachaPullResult.OnClientEvent:Connect(onGachaPullResult)
end

return AnnouncementController
