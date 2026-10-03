--[[
	HeistController
	---------------
	The client side of stealing (HeistService owns every rule).

	  * Grab: holding E on an enemy pedestal's StealPrompt (enabled only when
	    the steal is allowed, WorldLabelController) fires RequestSteal with
	    just which pedestal: { OwnerUserId, PedestalIndex }. A rejection comes
	    back as HeistEnded { Outcome = "Rejected", Reason } -> a toast.
	  * Every client, for every carrying player (the server sets Heist*
	    attributes on the Player): a cosmetic copy of the pedestal orb 3 studs
	    over their head (mutation shell included), a 40-stud Danger beam up
	    from it, and a "THIEF · 31s" pill.
	  * The thief: an orange "GET HOME!" banner (item, seconds, a draining
	    bar) and the goal arrow on their own gate.
	  * The victim: a red "THIEF IN YOUR LAB!" banner with a live distance, a
	    Danger arrow locked on the thief, and an alarm.
	  * Results: HEIST COMPLETE! / stolen cards (ResultController), toasts
	    for the rest.
	  * Shield fences: every plot's ForceField fence fades in and out from its
	    ShieldUntil attribute, so remote players see your shield too.

	The alarm reuses the project's one proven sound id (AnnouncementController,
	RevealEffects): rbxasset://sounds/electronicpingshort.wav, three low pings.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HeistConfig = require(ReplicatedStorage.Shared.Config.HeistConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PedestalVisuals = require(ReplicatedStorage.Shared.Modules.PedestalVisuals)
local PlotKit = require(ReplicatedStorage.Shared.Modules.PlotKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local ToastController = require(script.Parent.ToastController)
local ResultController = require(script.Parent.ResultController)
local GoalMarkerController = require(script.Parent.GoalMarkerController)

local HeistController = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local localPlayer = Players.LocalPlayer

local STEAL_PROMPT_NAME = "StealPrompt"
local CARRY_HEIGHT_ABOVE_HEAD = 3
local BEAM_LENGTH = 40
local BEAM_WIDTH = 0.6
local PILL_SIZE = UDim2.fromOffset(150, 36)
local PILL_MAX_DISTANCE = 200
local BANNER_SIZE = Vector2.new(480, 92)
local BANNER_TOP = 118 -- under the server banners (AnnouncementController)
local ALARM_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local ALARM_PINGS = 3
local ALARM_GAP_SECONDS = 0.25
local FENCE_FADE_SECONDS = 0.3
local FENCE_SHOWN_TRANSPARENCY = 0
local FENCE_LINE_SHOWN_TRANSPARENCY = 0.2
local FENCE_CHECK_SECONDS = 0.2

-- Rejection reason -> toast. Unlisted reasons (exploit-only) stay silent.
local REJECT_MESSAGES: { [string]: string } = {
	AlreadyCarrying = "You're already carrying something!",
	Shielded = "Their shield is up",
	LabCapped = "This lab has been robbed enough for now",
	AlreadyStolen = "Someone's already carrying that",
	Empty = "Nothing to steal there",
	TooFar = "Get closer",
	NoCharacter = "Can't steal right now",
	DataNotLoaded = "Can't steal right now",
}

local THIEF_FAIL_TOASTS: { [string]: string } = {
	Saved = "Caught!",
	Timeout = "Too slow!",
	Died = "You dropped it!",
	Left = "The heist was called off",
	Failed = "It slipped away",
}

type Visual = { Orb: Model, Pill: TextLabel, Connections: { RBXScriptConnection } }

-- Carried-orb visuals by carrying player.
local visuals: { [Player]: Visual } = {}

type Banner = { Holder: Frame, Title: TextLabel, Detail: TextLabel, Bar: Frame? }
local screenGui: ScreenGui
local banner: Banner? = nil
-- The local player's active heist: role, item, other player, end time.
type Active = { Role: string, Item: any, OtherName: string, OtherUserId: number, EndsAt: number }
local active: Active? = nil

-- Plot -> whether its fence is currently shown on this client.
local fenceShown: { [Instance]: boolean } = {}
local fenceAccumulator = 0

--[[ Helpers ------------------------------------------------------------------ ]]

local function secondsLeft(endsAt: number): number
	return math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow()))
end

local function getOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--[[ Carried orb (every client, every carrier) --------------------------------- ]]

local function clearVisual(player: Player)
	local visual = visuals[player]
	if not visual then
		return
	end
	visuals[player] = nil
	for _, connection in visual.Connections do
		connection:Disconnect()
	end
	visual.Orb:Destroy()
end

-- Welds the orb group's parts to its orb (unanchored, massless), and the
-- orb above the head. Satellites stay anchored: WorldAnimationController
-- moves them round the orb's live position (FT_Orbit).
local function attachOrb(group: Model, head: BasePart)
	local orb = group.PrimaryPart :: BasePart
	for _, part in group:GetDescendants() do
		local holder = part:FindFirstAncestorWhichIsA("Model")
		local orbiting = holder ~= nil and holder:HasTag(PartKit.ORBIT_TAG)
		if part:IsA("BasePart") and part ~= orb and not orbiting then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = orb
			weld.Part1 = part
			weld.Parent = part
		end
	end
	orb.Anchored = false
	orb.Massless = true
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = orb
	weld.C0 = CFrame.new(0, head.Size.Y / 2 + CARRY_HEIGHT_ABOVE_HEAD, 0)
	weld.Parent = orb
end

local function buildBeam(orb: BasePart)
	local bottom = Instance.new("Attachment")
	bottom.Name = "BeamBottom"
	bottom.Parent = orb
	local top = Instance.new("Attachment")
	top.Name = "BeamTop"
	top.Position = Vector3.new(0, BEAM_LENGTH, 0)
	top.Parent = orb
	local beam = Instance.new("Beam")
	beam.Name = "ThiefBeam"
	beam.Attachment0 = bottom
	beam.Attachment1 = top
	beam.Color = ColorSequence.new(Colors.Danger)
	beam.Transparency = NumberSequence.new(0.2, 1)
	beam.Width0 = BEAM_WIDTH
	beam.Width1 = BEAM_WIDTH
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = orb
end

local function buildPill(orb: BasePart): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "ThiefPill"
	gui.Size = PILL_SIZE
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = PILL_MAX_DISTANCE
	gui.Adornee = orb
	gui.Parent = orb
	local label = UIKit.Pill({
		Name = "Text",
		Parent = gui,
		Text = "THIEF",
		Gradient = UITheme.Gradients.Heist,
		Font = Fonts.Display,
		TextSize = 18,
		Height = 32,
		TextStroke = 1.5,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	return label
end

local function buildVisual(player: Player)
	clearVisual(player)
	local tier = player:GetAttribute("HeistTier")
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if typeof(tier) ~= "string" or not head or not head:IsA("BasePart") then
		return
	end
	local mutation = player:GetAttribute("HeistMutation")
	local center = head.CFrame * CFrame.new(0, head.Size.Y / 2 + CARRY_HEIGHT_ABOVE_HEAD, 0)
	local group = PedestalVisuals.BuildCarryOrb(tier, if typeof(mutation) == "string" then mutation else nil, center, Workspace)
	group.Name = "CarriedOrb_" .. player.UserId
	attachOrb(group, head)
	local orb = group.PrimaryPart :: BasePart
	buildBeam(orb)
	local pill = buildPill(orb)
	visuals[player] = { Orb = group, Pill = pill, Connections = {} }
end

local function refreshVisual(player: Player)
	if player:GetAttribute("HeistTier") ~= nil then
		buildVisual(player)
	else
		clearVisual(player)
	end
end

local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("HeistTier"):Connect(function()
		refreshVisual(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(refreshVisual, player)
	end)
	refreshVisual(player)
end

local function updatePills()
	for player, visual in visuals do
		local endsAt = player:GetAttribute("HeistEndsAt")
		if typeof(endsAt) == "number" then
			visual.Pill.Text = ("THIEF · %ds"):format(secondsLeft(endsAt))
		end
	end
end

--[[ Banner (local player only) ------------------------------------------------- ]]

local function clearBanner()
	if banner then
		local holder = banner.Holder
		banner = nil
		UIKit.PopOut(holder).Completed:Once(function()
			holder:Destroy()
		end)
	end
end

local function buildBanner(isThief: boolean): Banner
	if banner then
		banner.Holder:Destroy()
		banner = nil
	end
	local gradient = if isThief then UITheme.Gradients.Orange else UITheme.Gradients.Heist
	local body, holder = UIKit.Panel({
		Name = "HeistBanner",
		Parent = screenGui,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, BANNER_TOP),
		Size = UDim2.fromOffset(BANNER_SIZE.X, BANNER_SIZE.Y),
		Gradient = { { 0, gradient.Top }, { 1, gradient.Bottom } },
		Radius = 18,
		StrokeThickness = UITheme.Stroke.Modal,
		ZIndex = 2,
	})
	local z = body.ZIndex + 1
	local title = UIKit.Label({
		Name = "Title",
		Text = if isThief then "GET HOME!" else "THIEF IN YOUR LAB!",
		Font = Fonts.Display,
		TextSize = 28,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.new(1, -32, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
	local detail = UIKit.Label({
		Name = "Detail",
		Font = Fonts.BodyHeavy,
		TextSize = 15,
		TextWrapped = true,
		RichText = true,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, if isThief then 22 else 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 1.5,
		Parent = body,
	})
	local bar: Frame? = nil
	if isThief then
		bar = UIKit.ProgressBar({
			Name = "TimeBar",
			Parent = body,
			Position = UDim2.new(0, 24, 1, -22),
			Size = UDim2.new(1, -48, 0, 12),
			FillColor = Colors.Text,
			Value = 1,
			ZIndex = z,
		})
	end
	UIKit.PopIn(holder)
	local built: Banner = { Holder = holder, Title = title, Detail = detail, Bar = bar }
	banner = built
	return built
end

local function updateBanner()
	local current = active
	local shown = banner
	if not current or not shown then
		return
	end
	local left = secondsLeft(current.EndsAt)
	local itemName = UIKit.EscapeRichText(tostring(current.Item.Name))
	if current.Role == "Thief" then
		shown.Detail.Text = ("%s · %ds"):format(itemName, left)
		if shown.Bar then
			UIKit.SetProgress(shown.Bar, left / HeistConfig.CarrySeconds)
		end
	else
		local thief = Players:GetPlayerByUserId(current.OtherUserId)
		local thiefRoot = thief and getRoot(thief)
		local myRoot = getRoot(localPlayer)
		local distance = if thiefRoot and myRoot then (thiefRoot.Position - myRoot.Position).Magnitude else nil
		shown.Detail.Text = ("%s grabbed your %s · Touch them to get it back%s"):format(
			UIKit.EscapeRichText(current.OtherName),
			itemName,
			if distance then UIKit.Colored(("\n%d studs away · %ds"):format(math.floor(distance + 0.5), left), Colors.Text) else ""
		)
	end
end

local function playAlarm()
	task.spawn(function()
		for _ = 1, ALARM_PINGS do
			local sound = Instance.new("Sound")
			sound.SoundId = ALARM_SOUND_ID
			sound.Volume = 1
			sound.PlaybackSpeed = 0.7
			sound.Parent = screenGui
			sound:Play()
			sound.Ended:Once(function()
				sound:Destroy()
			end)
			task.wait(ALARM_GAP_SECONDS)
		end
	end)
end

--[[ Remote handlers --------------------------------------------------------------- ]]

local function onPromptTriggered(prompt: ProximityPrompt, triggeringPlayer: Player)
	if triggeringPlayer ~= localPlayer or prompt.Name ~= STEAL_PROMPT_NAME then
		return
	end
	local owner = prompt:GetAttribute("OwnerUserId")
	local pedestal = prompt.Parent
	local index = pedestal and pedestal:GetAttribute("PedestalIndex")
	if typeof(owner) ~= "number" or typeof(index) ~= "number" then
		return
	end
	RemoteEvents.RequestSteal:FireServer({ OwnerUserId = owner, PedestalIndex = index })
end

local function onHeistStarted(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.Item) ~= "table" or typeof(payload.EndsAt) ~= "number" then
		return
	end
	local isThief = payload.Role == "Thief"
	local started: Active = {
		Role = if isThief then "Thief" else "Victim",
		Item = payload.Item,
		OtherName = tostring(payload.OtherName),
		OtherUserId = tonumber(payload.OtherUserId) or 0,
		EndsAt = payload.EndsAt,
	}
	active = started
	buildBanner(isThief)
	updateBanner()
	if isThief then
		local plot = getOwnPlot()
		local gate = plot and plot:FindFirstChild("SignGate")
		if gate then
			GoalMarkerController.SetOverride(gate, "GET HOME!", false)
		end
	else
		local thief = Players:GetPlayerByUserId(started.OtherUserId)
		local thiefRoot = thief and getRoot(thief)
		if thiefRoot then
			GoalMarkerController.SetOverride(thiefRoot, "THIEF!", true)
		end
		playAlarm()
	end
end

local function onHeistEnded(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Outcome == "Rejected" then
		if payload.Reason == "Cooldown" then
			ToastController.Show(("Lay low for %ds"):format(tonumber(payload.Seconds) or 0), "Neutral")
			return
		end
		local message = REJECT_MESSAGES[payload.Reason]
		if message then
			ToastController.Show(message, "Neutral")
		end
		return
	end

	active = nil
	clearBanner()
	GoalMarkerController.SetOverride(nil)
	local item = payload.Item
	if typeof(item) ~= "table" then
		return
	end
	local other = tostring(payload.OtherName)
	if payload.Role == "Thief" then
		if payload.Outcome == "Delivered" then
			ResultController.ShowHeistComplete(item, other)
		else
			ToastController.Show(THIEF_FAIL_TOASTS[payload.Outcome] or "It slipped away", "Error")
		end
	else
		if payload.Outcome == "Delivered" then
			ResultController.ShowItemStolen(item, other, HeistConfig.VictimShieldSeconds)
		elseif payload.Outcome == "Saved" then
			ToastController.Show(("SAVED! You got your %s back"):format(tostring(item.Name)), "Neutral")
		else
			ToastController.Show(("Your %s is back!"):format(tostring(item.Name)), "Neutral")
		end
	end
end

--[[ Shield fences (every plot) ------------------------------------------------------ ]]

local function setFence(plot: Instance, shown: boolean)
	fenceShown[plot] = shown
	local fence = plot:FindFirstChild("ShieldFence")
	if not fence then
		return
	end
	local info = TweenInfo.new(FENCE_FADE_SECONDS, Enum.EasingStyle.Quad)
	for _, part in fence:GetChildren() do
		if part:IsA("BasePart") and part:GetAttribute(PlotKit.SHIELD_PART_ATTRIBUTE) then
			local shownTransparency = if part.Material == Enum.Material.Neon
				then FENCE_LINE_SHOWN_TRANSPARENCY
				else FENCE_SHOWN_TRANSPARENCY
			TweenService:Create(part, info, { Transparency = if shown then shownTransparency else 1 }):Play()
		end
	end
end

local function updateFences()
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	if not folder then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, plot in folder:GetChildren() do
		local shieldUntil = plot:GetAttribute("ShieldUntil")
		local shown = typeof(shieldUntil) == "number" and shieldUntil > now
		if (fenceShown[plot] == true) ~= shown then
			setFence(plot, shown)
		end
	end
	for plot in fenceShown do
		if plot.Parent ~= folder then
			fenceShown[plot] = nil
		end
	end
end

--[[ Init ------------------------------------------------------------------------- ]]

function HeistController.Init()
	screenGui = UIKit.Screen("Heist", 105)
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	RemoteEvents.HeistStarted.OnClientEvent:Connect(onHeistStarted)
	RemoteEvents.HeistEnded.OnClientEvent:Connect(onHeistEnded)

	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(clearVisual)

	RunService.Heartbeat:Connect(function(dt: number)
		updatePills()
		updateBanner()
		fenceAccumulator += dt
		if fenceAccumulator >= FENCE_CHECK_SECONDS then
			fenceAccumulator = 0
			updateFences()
		end
	end)
end

return HeistController
