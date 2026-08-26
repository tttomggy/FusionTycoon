-- Shows a brief on-screen banner/toast for two kinds of one-off feedback:
-- server-wide RareFusionAnnouncement events (a Legendary/Mythic item was
-- just displayed on someone's Pedestal Showcase) and the local player's own
-- MultiplierUpgraded purchases. Built entirely in Luau (no StarterGui asset
-- in this project) and queued so a burst of announcements displays one at a
-- time instead of stacking.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local RarityVisuals = require(ReplicatedStorage.Shared.Config.RarityVisuals)

local AnnouncementController = {}

local BANNER_SIZE = UDim2.fromOffset(520, 64)
local BANNER_VISIBLE_POSITION = UDim2.new(0.5, -260, 0, 24)
local BANNER_HIDDEN_POSITION = UDim2.new(0.5, -260, 0, -100)
local SLIDE_IN_SECONDS = 0.35
local SLIDE_OUT_SECONDS = 0.3
local HOLD_SECONDS = 3.5
local SOUND_ID = "rbxasset://sounds/bell.wav"
-- Matches MULTIPLIER_UPGRADE_ACCENT_COLOR in TycoonService.lua (the pad's own accent).
local MULTIPLIER_ACCENT_COLOR = Color3.fromRGB(200, 60, 255)

local queue: { any } = {}
local isProcessing = false

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

			-- A statement ending in an expression followed by a line that
			-- starts with "(" is ambiguous in Lua (looks like a function
			-- call spanning both lines), so these go through local variables
			-- instead of an inline `(x :: T).Field = ...` cast.
			local currentLabel = label :: TextLabel
			local currentAccentBar = accentBar :: Frame
			currentLabel.Text = announcement.Message
			currentAccentBar.BackgroundColor3 = announcement.AccentColor

			local sound = Instance.new("Sound")
			sound.SoundId = SOUND_ID
			sound.Volume = 0.7
			sound.Parent = banner :: Frame
			sound:Play()
			Debris:AddItem(sound, 3)

			TweenService:Create(
				banner :: Frame,
				TweenInfo.new(SLIDE_IN_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = BANNER_VISIBLE_POSITION }
			):Play()

			task.wait(SLIDE_IN_SECONDS + HOLD_SECONDS)

			local slideOut = TweenService:Create(
				banner :: Frame,
				TweenInfo.new(SLIDE_OUT_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = BANNER_HIDDEN_POSITION }
			)
			slideOut:Play()
			slideOut.Completed:Wait()
		end
		isProcessing = false
	end)
end

local function onRareFusionAnnouncement(payload: any)
	local tierVisual = RarityVisuals.Tiers[payload.Tier]
	table.insert(queue, {
		Message = payload.Message,
		AccentColor = (tierVisual and tierVisual.GlowColor) or Color3.new(1, 1, 1),
	})
	processQueue()
end

local function onMultiplierUpgraded(payload: any)
	table.insert(queue, {
		Message = ("Multiplier Upgraded! x%d -> x%d"):format(payload.OldMultiplier, payload.NewMultiplier),
		AccentColor = MULTIPLIER_ACCENT_COLOR,
	})
	processQueue()
end

function AnnouncementController.Init()
	buildUI()
	RemoteEvents.RareFusionAnnouncement.OnClientEvent:Connect(onRareFusionAnnouncement)
	RemoteEvents.MultiplierUpgraded.OnClientEvent:Connect(onMultiplierUpgraded)
end

return AnnouncementController
