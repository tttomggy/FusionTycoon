--[[
	FusePanel
	---------
	The FUSE modal, opened from the Fusion Machine's "Fuse" prompt (through
	ProximityPromptService, owner-only). Put 2-6 items of one tier in: more
	inputs, better odds (FusionConfig.SuccessChanceByCount). Success makes 1
	random item of the next tier; a fail keeps your best input and loses
	the rest.

	  Left   the chamber: 6 slots in a hexagon round a dim silhouette of the
	         next tier's orb, the chance (coloured by how safe it is), the
	         recipe, the mutation prediction, count chips (2 · 55% ...)
	         and the fail rule.
	  Right  tier tabs with fusable counts (Mythic locked before Rebirth 1,
	         no Secret tab) and a grid of that tier's items, normal first.
	         Tap to add or remove; selected cards dim and show a check.
	  Bottom AUTO-FILL (the first orb's mutation; normal items into an
	         empty chamber), CLEAR, FUSE (2+), FUSE ALL.

	Under the recipe, the mutation prediction (FusionConfig.GetMutationMix):
	"✨ Keeps GOLDEN ×2, might roll better" when every orb shares it, a red
	warning box when a lower orb is mixed in (those orbs get a red ring).

	The panel leads you UP the ladder (FuseLadder holds the rules):
	  * it opens on the HIGHEST tier with >= 2 fusable orbs, and jumps there
	    again after a fuse (Common -> Rare -> Epic ...) unless the player
	    picked a tab themselves since opening it;
	  * a tab with a fusable pair that isn't selected gets a pulsing dot and
	    a white count; tabs with < 2 are muted;
	  * the ladder strip above the tabs (the tier orbs, the best one owned lit,
	    the NEXT one ringed and labelled "Next: Epic"; tap = that tab) hides
	    when the column is too small (phones) - the dots and the jump stay.

	After FUSE the slot orbs fly into the centre, then FusionController runs
	the machine's charge-up and ResultController's reveal; the panel stays
	open on the same tab with the chamber cleared. DisplayOrder sits under
	Results and Toasts so those show on top.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FusionConfig = require(ReplicatedStorage.Shared.Config.FusionConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MutationConfig = require(ReplicatedStorage.Shared.Config.MutationConfig)
local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local GoalSteps = require(ReplicatedStorage.Shared.Modules.GoalSteps)
local FuseLadder = require(ReplicatedStorage.Shared.Modules.FuseLadder)
local Controllers = script.Parent.Parent.Controllers
local InventoryController = require(Controllers.InventoryController)
local TycoonController = require(Controllers.TycoonController)
local FusionController = require(Controllers.FusionController)
local ToastController = require(Controllers.ToastController)
local TutorialCards = require(script.Parent.TutorialCards)
local UIKit = require(script.Parent.UIKit)

local FusePanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

-- 860 x 520 on desktop; on a phone the Modal's 92% x 90% fit takes over
-- (844 x 390 after the 0.8 UIScale). No text in the panel is under 12 px.
local MAX_SIZE = Vector2.new(860, 520)
local DISPLAY_ORDER = 115 -- under Toasts (120) and Results (130)
local FUSE_PROMPT_NAME = "FusePrompt"
local LEFT_WIDTH = 0.44
local COLUMN_GAP = 14
local BAR_HEIGHT = 56
local TAB_HEIGHT = 50 -- tier name over its count; five equal tabs, no scroll
local TAB_GAP = 6
local CARD_SIZE = Vector2.new(100, 112)
local CHIP_HEIGHT = 40 -- two lines: "3 orbs" over the chance
local CHIP_GAP = 6
local CHIP_CHANCE_MAX_TEXT = 18 -- the % scales down to fit ("100%" on the narrowest phone)
local FLY_SECONDS = 0.35
local METER_HEIGHT = 36 -- the Secret meter: its label (14 px) over the bar
local METER_BAR_HEIGHT = 10
local LADDER_HEIGHT = 36 -- the tier-orb strip above the tabs
local LADDER_ORB = 24
local LADDER_CELL = 44 -- one tier's tap target (>= 44 px)
local LADDER_MIN_SIZE = Vector2.new(420, 250) -- the picker column (px) below which the strip hides
local JUMP_WINDOW_SECONDS = 3 -- after a fuse: inventory syncs inside this window re-pick the tab
local DOT_SIZE = 12

-- Chamber geometry (px) per layout. Height = 2 x Radius + Slot. Desktop
-- meets the legibility floor (slots 64, silhouette 96, chance 48); the
-- phone column is ~270 px tall, so it shrinks to keep the chance, recipe
-- and chips in view without scrolling.
local HEX = {
	Desktop = { Height = 232, Radius = 84, Slot = 64, Center = 96, ChanceSize = 48 },
	Phone = { Height = 160, Radius = 56, Slot = 48, Center = 60, ChanceSize = 40 },
}
local CHANCE_SAFE = 0.75 -- Cash colour at or above
local CHANCE_OK = 0.40 -- Gold colour at or above; Danger below

local localPlayer = Players.LocalPlayer

local modal: UIKit.Modal
local hexFrame: Frame
local slots: { Frame } = {}
local silhouette: Frame? = nil
local chanceLabel: TextLabel
local recipeLabel: TextLabel
-- The Secret pity meter (Mythic tab, once Mythic fusion is unlocked): label
-- over a track with a mint fill.
local meterBox: Frame
local meterLabel: TextLabel
local meterTrack: Frame
local meterFill: Frame
local meterShownPity = -1 -- the value the bar was last drawn at (-1: hidden)
local pitySeen = -1 -- the meter value the chamber was last refreshed with
local meterTarget = 0 -- the fill fraction the bar is heading for
local chipsRow: Frame
local predictionBox: Frame
local optionsRow: Frame
local tipLabel: TextLabel
-- Assigned after largestMutatedGroup (the chamber refresh sits above it).
local updateMutationTip: () -> () = function() end
local safeButton: TextButton
local safeHolder: Frame
local autoButton: TextButton
local autoHolder: Frame
-- Safe Fusion armed for the next FUSE (one token; disarms after use).
local safeArmed = false
local predictionLabel: TextLabel
local tabsFrame: Frame
local grid: ScrollingFrame
local fuseButton: TextButton
local autoFillHolder: Frame? = nil
local fuseAllButton: TextButton
local tabButtons: { [string]: TextButton } = {}
-- Ladder UI: the strip's cells by tier, the ring on the NEXT tier, its label,
-- and each tab's ready dot.
local ladder: {
	Frame: Frame?,
	Cells: { [string]: Frame },
	Dim: { [string]: Frame },
	Ring: Frame?,
	NextLabel: TextLabel?,
	Dots: { [string]: Frame },
	Aim: string?,
	Best: string?,
} = { Cells = {}, Dim = {}, Dots = {} }
-- The tab was picked by hand since the panel opened: auto-jump leaves it alone.
local userPicked = false
local jumpUntil = 0 -- os.clock() until which an inventory change re-picks the tab (after a fuse)
local countsOverride: FuseLadder.Counts? = nil -- /selftest: stubbed fusable counts

local isPhone = false
local selectedTier = FusionConfig.TierOrder[1]
local selected: { string } = {} -- Uids, in the order they went in
local flying = false

--[[ Helpers ------------------------------------------------------------------ ]]

local function percent(chance: number): string
	return FusionConfig.FormatPercent(chance * 100) .. "%"
end

local function itemName(item: any): string
	local def = ItemConfig.GetItemById(item.ItemId)
	return MutationConfig.GetDisplayName(if def then def.Name else tostring(item.ItemId), item.Mutation, item.EventMutations)
end

local function fusableTiers(): { string }
	local tiers = {}
	for _, tier in FusionConfig.TierOrder do
		if FusionConfig.CanFuseTier(tier) then
			table.insert(tiers, tier)
		end
	end
	return tiers
end

local function rebirthsNeeded(tier: string): number?
	local needed = FusionConfig.RebirthGatedTiers[tier]
	if needed and TycoonController.GetRebirths() < needed then
		return needed
	end
	return nil
end

-- Fusable orbs per tier (the tabs' counts); /selftest can stub them.
local function fusableCounts(): FuseLadder.Counts
	if countsOverride then
		return countsOverride
	end
	local counts: FuseLadder.Counts = {}
	for _, tier in FusionConfig.TierOrder do
		counts[tier] = #InventoryController.GetFusableItemsByTier(tier)
	end
	return counts
end

-- The success bonus the roll adds: the live event's (Void Moon) and an armed
-- Fusion Spark's (quest power-up). Also returns the spark part alone.
local function fusionBonus(): (number, number)
	local spark = if TycoonController.IsArmed("FusionSpark")
		then QuestConfig.PowerUps.FusionSpark.FusionBonus or 0
		else 0
	return EventState.GetFusionSuccessBonus() + spark, spark
end

local function itemsByUid(): { [string]: any }
	local byUid = {}
	for _, item in InventoryController.GetInventory() do
		byUid[item.Uid] = item
	end
	return byUid
end

local function selectedItems(): { any }
	local byUid = itemsByUid()
	local items = {}
	for _, uid in selected do
		local item = byUid[uid]
		if item then
			table.insert(items, item)
		end
	end
	return items
end

local function isSelected(uid: string): boolean
	return table.find(selected, uid) ~= nil
end

-- Drops selections that are gone, carried off by a thief, or of another tier.
local function pruneSelection()
	local byUid = itemsByUid()
	for index = #selected, 1, -1 do
		local item = byUid[selected[index]]
		if not item or InventoryController.IsCarried(item) or item.Tier ~= selectedTier then
			table.remove(selected, index)
		end
	end
end

local function chanceColor(chance: number): Color3
	if chance >= CHANCE_SAFE then
		return Colors.Cash
	elseif chance >= CHANCE_OK then
		return Colors.Goal
	end
	return Colors.Danger
end

-- The prediction line under the recipe (FusionConfig.GetMutationMix, the
-- rule the server applies): all one mutation keeps it, mixed loses it,
-- all plain says nothing. Returns (text, isWarning, colour) or nil.
local function predictionText(items: { any }, nextTier: string): (string?, boolean, Color3?)
	if #items == 0 then
		return nil, false, nil
	end
	local mix = FusionConfig.GetMutationMix(items)
	-- Stacking: the base and the event mutations, "GOLDEN + CHARGED".
	local function stackWords(base: string?, events: { string }?): string
		local words = {}
		for _, name in MutationConfig.List(base, events) do
			table.insert(words, name:upper())
		end
		return table.concat(words, " + ")
	end
	local bestTop = MutationConfig.GetTop(mix.Best, mix.AllEvents)
	if not bestTop then
		return nil, false, nil
	end
	if not mix.Mixed then
		return ("✨ Keeps %s ×%d, might roll better"):format(
			stackWords(mix.Kept, mix.KeptEvents),
			MutationConfig.GetStackedMultiplier(mix.Kept, mix.KeptEvents)
		),
			false,
			UITheme.GetMutationColor(MutationConfig.GetTop(mix.Kept, mix.KeptEvents))
	end
	local bestWords = stackWords(mix.Best, mix.AllEvents)
	local below = if mix.BelowShared then (mix.BelowMutation or "plain") else "lower"
	local keptWords = stackWords(mix.Kept, mix.KeptEvents)
	local result = if keptWords ~= "" then keptWords else "plain"
	return ("⚠ %d %s orb%s mixed in: the %s comes out %s, not %s. Use only %s orbs to keep it all."):format(
		mix.BelowCount,
		below,
		if mix.BelowCount == 1 then "" else "s",
		nextTier,
		result,
		bestWords,
		bestWords
	),
		true,
		Colors.Text
end

--[[ Chamber ------------------------------------------------------------------ ]]

local function layoutHex()
	local hex = if isPhone then HEX.Phone else HEX.Desktop
	hexFrame.Size = UDim2.new(1, 0, 0, hex.Height)
	chanceLabel.TextSize = hex.ChanceSize
	chanceLabel.Size = UDim2.new(1, 0, 0, hex.ChanceSize + 4)
	for index, slot in slots do
		local angle = math.rad(-90 + (index - 1) * 60)
		slot.Size = UDim2.fromOffset(hex.Slot, hex.Slot)
		slot.Position = UDim2.new(0.5, math.cos(angle) * hex.Radius, 0.5, math.sin(angle) * hex.Radius)
	end
end

local function refreshChamber()
	local hex = if isPhone then HEX.Phone else HEX.Desktop
	local items = selectedItems()
	local count = #items
	local nextTier = FusionConfig.GetNextTier(selectedTier) or selectedTier
	local mix = FusionConfig.GetMutationMix(items)

	-- Silhouette of what you're fusing toward.
	if silhouette then
		silhouette:Destroy()
	end
	local ghost = UIKit.TierOrb(nextTier, hex.Center, 0.7)
	ghost.Name = "Silhouette"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Position = UDim2.fromScale(0.5, 0.5)
	ghost.ZIndex = hexFrame.ZIndex + 1
	ghost.Parent = hexFrame
	silhouette = ghost

	for index, slot in slots do
		local existing = slot:FindFirstChild("Orb")
		if existing then
			existing:Destroy()
		end
		local item = items[index]
		-- A red ring on every orb dragging the result's mutation down.
		local dragging = item ~= nil and FusionConfig.IsDragging(mix, item)
		local ring = slot:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = if dragging then Colors.Danger else Colors.Faint
			ring.Thickness = if dragging then 4 else 2
		end
		if item then
			local orb = UIKit.TierOrb(item.Tier, hex.Slot - 10, nil, MutationConfig.GetTop(item.Mutation, item.EventMutations))
			orb.Name = "Orb"
			orb.AnchorPoint = Vector2.new(0.5, 0.5)
			orb.Position = UDim2.fromScale(0.5, 0.5)
			orb.ZIndex = slot.ZIndex + 1
			orb.Parent = slot
		end
	end

	-- With the live event's success bonus (Void Moon) and an armed Fusion
	-- Spark (quest power-up), like the server's roll.
	local bonus, spark = fusionBonus()
	local pity = TycoonController.GetSecretPity()
	pitySeen = pity
	local chance = FusionConfig.GetFusionChanceWithPity(selectedTier, math.max(count, FusionConfig.MinFusionInputs), bonus, pity)
	if count >= FusionConfig.MinFusionInputs then
		chanceLabel.Text = percent(chance) .. (if spark > 0 then " ⚗️" else "")
		chanceLabel.TextColor3 = chanceColor(chance)
	else
		chanceLabel.Text = ("Add %d+"):format(FusionConfig.MinFusionInputs)
		chanceLabel.TextColor3 = Colors.Faint
	end
	-- The Secret meter: only on the Mythic tab and only once Mythic fusion is
	-- unlocked; full says so in the Secret colour.
	local meterOn = FusionConfig.HasPity(selectedTier) and FusionConfig.CanFuseTierFor(selectedTier, TycoonController.GetRebirths())
	meterBox.Visible = meterOn
	if meterOn then
		local full = FusionConfig.IsPityFull(pity)
		meterLabel.Text = if full
			then "NEXT FUSE IS A SURE SECRET!"
			else ("SECRET METER  %d / %d"):format(pity, FusionConfig.SecretPityFull)
		meterLabel.TextColor3 = if full then UITheme.GetTierLight("Secret") else Colors.Muted
		local fraction = math.clamp(pity / FusionConfig.SecretPityFull, 0, 1)
		meterTarget = fraction
		if meterShownPity < 0 then
			meterFill.Size = UDim2.fromScale(fraction, 1)
		elseif meterShownPity ~= pity then
			-- Up after a fail (and back to empty after a Secret).
			TweenService:Create(meterFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(fraction, 1),
			}):Play()
		end
		meterShownPity = pity
	else
		meterShownPity = -1
	end
	recipeLabel.Text = ("%d %s → %s"):format(
		count,
		selectedTier,
		UIKit.Colored(nextTier:upper(), UITheme.GetTierLight(nextTier))
	)

	for _, chip in chipsRow:GetChildren() do
		if chip:IsA("GuiObject") then
			chip:Destroy()
		end
	end
	local chipTotal = FusionConfig.MaxFusionInputs - FusionConfig.MinFusionInputs + 1
	for chipCount = FusionConfig.MinFusionInputs, FusionConfig.MaxFusionInputs do
		local current = chipCount == count
		-- Each count its own chip (one row, a 6 px gap between them): the
		-- count small on top, its chance bold under it. The count matching
		-- the chamber is highlighted in the selected green (UIKit); a Void
		-- Moon tints every other chip purple.
		local chip = Instance.new("Frame")
		chip.Name = "Chip" .. chipCount
		chip.LayoutOrder = chipCount
		chip.Size = UDim2.new(1 / chipTotal, -CHIP_GAP * (chipTotal - 1) / chipTotal, 1, 0)
		chip.ZIndex = chipsRow.ZIndex + 1
		UIKit.SetSelectedFill(
			chip,
			current,
			if bonus > 0 then UITheme.TowardInk(UITheme.Mutation.Void, 0.45) else Colors.Panel2
		)
		UIKit.Corner(chip, 12)
		UIKit.Stroke(chip, if current then 3 else 2, if current then Colors.White else nil)
		UIKit.Label({
			Name = "Count",
			Text = ("%d orbs"):format(chipCount),
			Font = Fonts.BodyHeavy,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if current then Colors.Text else Colors.Muted,
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = chip.ZIndex + 1,
			Stroke = if current then 1 else nil,
			Parent = chip,
		})
		local chanceLabel = UIKit.Label({
			Name = "Chance",
			Text = percent(FusionConfig.GetFusionChanceWithPity(selectedTier, chipCount, bonus, pity)),
			Font = Fonts.Display,
			TextSize = CHIP_CHANCE_MAX_TEXT,
			TextScaled = true,
			TextColor3 = Colors.Text,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 17),
			Size = UDim2.new(1, -6, 0, 20),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = chip.ZIndex + 1,
			Stroke = UITheme.Stroke.Text,
			Parent = chip,
		})
		local cap = Instance.new("UITextSizeConstraint")
		cap.MaxTextSize = CHIP_CHANCE_MAX_TEXT
		cap.Parent = chanceLabel
		chip.Parent = chipsRow
	end

	updateMutationTip()

	local prediction, warning, color = predictionText(items, nextTier)
	predictionBox.Visible = prediction ~= nil
	predictionLabel.Text = prediction or ""
	predictionLabel.TextColor3 = color or Colors.Text
	predictionBox.BackgroundTransparency = if warning then 0 else 1
	local boxStroke = predictionBox:FindFirstChildOfClass("UIStroke")
	if boxStroke then
		boxStroke.Enabled = warning
	end

	-- Shop options: Safe Fusion (only with tokens) and Auto-Fuse (only with
	-- the pass).
	local tokens = TycoonController.GetShop().SafeFusionTokens
	if tokens <= 0 then
		safeArmed = false
	end
	safeHolder.Visible = tokens > 0
	UIKit.SetButton(safeButton, {
		Style = if safeArmed then "Teal" else "Disabled",
		Text = ("🛡 Safe Fusion (%d)"):format(tokens),
		SubText = if safeArmed then "ON · a fail keeps every orb" else "OFF",
		TextColor3 = if safeArmed then Colors.Text else Colors.Muted,
	})
	local ownsAuto = TycoonController.OwnsPass("AutoFuse")
	autoHolder.Visible = ownsAuto
	local autoOn = TycoonController.IsAutoFuseOn()
	UIKit.SetButton(autoButton, {
		Style = if autoOn then "Teal" else "Disabled",
		Text = "🔁 Auto-Fuse",
		SubText = if autoOn then "ON · Fuse All when items arrive" else "OFF",
		TextColor3 = if autoOn then Colors.Text else Colors.Muted,
	})
	optionsRow.Visible = tokens > 0 or ownsAuto

	local pending = FusionController.IsRequestPending() or flying
	local canFuse = count >= FusionConfig.MinFusionInputs and not pending and rebirthsNeeded(selectedTier) == nil
	UIKit.SetButton(fuseButton, {
		Style = if canFuse then "Violet" else "Disabled",
		TextColor3 = if canFuse then Colors.Text else Colors.Muted,
	})
	local canFuseAll = not pending
	UIKit.SetButton(fuseAllButton, {
		Style = if canFuseAll then "Violet" else "Disabled",
		TextColor3 = if canFuseAll then Colors.Text else Colors.Muted,
	})
end

--[[ Picker ------------------------------------------------------------------- ]]

local refreshAll: () -> ()

local function toggle(uid: string)
	local index = table.find(selected, uid)
	if index then
		table.remove(selected, index)
	elseif #selected < FusionConfig.MaxFusionInputs then
		table.insert(selected, uid)
	else
		ToastController.Show(("Up to %d orbs at once"):format(FusionConfig.MaxFusionInputs), "Neutral")
		return
	end
	refreshAll()
end

local function buildCard(item: any, order: number)
	local tierColor = FusionConfig.TierAccentColors[item.Tier] or Colors.Text
	local chosen = isSelected(item.Uid)
	local body = UIKit.Panel({
		Name = item.Uid,
		Parent = grid,
		LayoutOrder = order,
		Gradient = { { 0, UITheme.TowardInk(tierColor, 0.7) }, { 1, Colors.CardBottom } },
		Radius = UITheme.Radius.Row,
		NoShadow = true,
		ZIndex = grid.ZIndex + 1,
	})
	local top = MutationConfig.GetTop(item.Mutation, item.EventMutations)
	UIKit.MutationCardStroke(body, top)
	local z = body.ZIndex + 1
	local orb = UIKit.TierOrb(item.Tier, 48, nil, top)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 8)
	orb.ZIndex = z
	orb.Parent = body
	UIKit.Label({
		Name = "ItemName",
		Text = itemName(item),
		Font = Fonts.Display,
		TextSize = 13,
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 60),
		Size = UDim2.new(1, -8, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 1.5,
		Parent = body,
	})
	-- The name already says the mutation; the pill carries the multiplier
	-- so it stays legible at 12 px inside the card.
	UIKit.MutationPill({
		Parent = body,
		Mutation = top,
		Label = if top then ("×%d"):format(MutationConfig.GetStackedMultiplier(item.Mutation, item.EventMutations)) else nil,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		TextSize = 13,
		Height = 20,
		ZIndex = z + 1,
	})
	if chosen then
		local dim = Instance.new("Frame")
		dim.Name = "Selected"
		dim.BackgroundColor3 = Colors.Ink
		dim.BackgroundTransparency = 0.45
		dim.Size = UDim2.fromScale(1, 1)
		dim.ZIndex = z + 2
		dim.Parent = body
		UIKit.Corner(dim, UITheme.Radius.Row)
		UIKit.Label({
			Name = "Check",
			Text = "✓",
			Font = Fonts.Display,
			TextSize = 30,
			TextColor3 = Colors.Cash,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 3,
			Stroke = UITheme.Stroke.Text,
			Parent = dim,
		})
	end
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = z + 5
	hit.Parent = body
	hit.Activated:Connect(function()
		toggle(item.Uid)
	end)
end

local function rebuildGrid()
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local needed = rebirthsNeeded(selectedTier)
	if needed then
		UIKit.Label({
			Name = "Locked",
			Text = ("🔒 Rebirth %d to fuse %ss"):format(needed, selectedTier),
			Font = Fonts.Display,
			TextSize = 18,
			TextColor3 = Colors.Muted,
			Size = UDim2.new(1, 0, 0, 40),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = grid.ZIndex + 1,
			Parent = grid,
		})
		return
	end
	-- Normal items first, mutated last (GetFusableItemsByTier sorts by rank).
	for order, item in InventoryController.GetFusableItemsByTier(selectedTier) do
		buildCard(item, order)
	end
end

-- The ladder strip: the best tier owned and everything below it lit, the
-- NEXT tier ringed and labelled. Cheap enough to run on every refresh.
local function refreshLadder(counts: FuseLadder.Counts)
	local best = FuseLadder.BestOwned(counts)
	local aim = FuseLadder.NextAim(counts)
	ladder.Best, ladder.Aim = best, aim
	local bestRank = if best then table.find(FusionConfig.TierOrder, best) :: number else 0
	for index, tier in FusionConfig.TierOrder do
		local dim = ladder.Dim[tier]
		if dim then
			dim.Visible = index > bestRank
		end
	end
	local ring, nextLabel = ladder.Ring, ladder.NextLabel
	local aimCell = if aim then ladder.Cells[aim] else nil
	if ring then
		ring.Parent = aimCell
		ring.Visible = aimCell ~= nil
	end
	if nextLabel then
		nextLabel.Visible = aim ~= nil
		nextLabel.Text = if aim then ("Next: %s"):format(aim) else ""
	end
end

local function refreshTabs()
	local counts = fusableCounts()
	for tier, button in tabButtons do
		local needed = rebirthsNeeded(tier)
		local current = tier == selectedTier
		local ready = not needed and FuseLadder.IsReady(counts[tier] or 0)
		-- Selected = green + white; the rest the muted panel colour: white
		-- count while there is a pair to fuse, Muted when < 2 or locked.
		UIKit.SetSelected(button, current, if ready then Colors.Text else Colors.Muted)
		UIKit.SetButton(button, {
			SubText = if needed then "🔒" else tostring(counts[tier] or 0),
		})
		local dot = ladder.Dots[tier]
		if dot then
			dot.Visible = ready and not current
		end
	end
	refreshLadder(counts)
end

function refreshAll()
	if not modal then
		return
	end
	pruneSelection()
	refreshTabs()
	rebuildGrid()
	refreshChamber()
end

local function selectTier(tier: string)
	if tier ~= selectedTier then
		selectedTier = tier
		table.clear(selected) -- switching tab clears the chamber
	end
	refreshAll()
end

-- The ladder's pick: the highest tier with a fusable pair (Common when
-- nothing is). A hand-picked tab is left alone until the panel reopens.
-- Returns whether the tab changed; the caller refreshes.
local function jumpToBest(): boolean
	if userPicked then
		return false
	end
	local tier = FuseLadder.PickTab(fusableCounts(), TycoonController.GetRebirths())
	if tier == selectedTier then
		return false
	end
	selectedTier = tier
	table.clear(selected)
	return true
end

-- A tab or ladder-strip tap.
local function pickTab(tier: string)
	local needed = rebirthsNeeded(tier)
	if needed then
		ToastController.Show(("Rebirth %d to fuse %ss"):format(needed, tier), "Neutral")
		return
	end
	if not tabButtons[tier] then
		return -- Secret is the end of the ladder: no tab
	end
	userPicked = true
	selectTier(tier)
end

--[[ Actions ------------------------------------------------------------------ ]]

-- Tops the chamber up to 6. Empty chamber: unmutated items, as before.
-- Otherwise only items with the SAME stack (base and event set) as the
-- first orb in, so a fill never drags a mutation down.
local function matchingUids(first: any?): { string }
	if first == nil or MutationConfig.GetTop(first.Mutation, first.EventMutations) == nil then
		return FusionController.GetAutoFill(selectedTier)
	end
	local uids = {}
	for _, item in InventoryController.GetInventory() do
		if
			item.Tier == selectedTier
			and MutationConfig.SameStack(item.Mutation, item.EventMutations, first.Mutation, first.EventMutations)
			and not InventoryController.IsCarried(item)
		then
			table.insert(uids, item.Uid)
		end
	end
	return uids
end

-- Empty chamber and no unmutated item of this tier: the largest group of
-- mutated items sharing one stack (not carried; displayed ones count, as
-- everywhere else in the panel, but come last), max 6. Ties go to the lower stacked multiplier, so the rarest stack is kept.
-- Returns the uids, the stack's label and its top mutation; nothing when no group has 2+.
local function largestMutatedGroup(): ({ string }, string?, string?)
	local groups: { { Uids: { string }, Displayed: { string }, Base: string?, Events: { string }?, Value: number } } = {}
	for _, item in InventoryController.GetInventory() do
		if
			item.Tier == selectedTier
			and MutationConfig.GetTop(item.Mutation, item.EventMutations) ~= nil
			and not InventoryController.IsCarried(item)
		then
			local group = nil
			for _, candidate in groups do
				if MutationConfig.SameStack(candidate.Base, candidate.Events, item.Mutation, item.EventMutations) then
					group = candidate
					break
				end
			end
			if not group then
				group = {
					Uids = {},
					Displayed = {},
					Base = item.Mutation,
					Events = item.EventMutations,
					Value = MutationConfig.GetStackedMultiplier(item.Mutation, item.EventMutations),
				}
				table.insert(groups, group)
			end
			table.insert(if InventoryController.IsInUse(item) then group.Displayed else group.Uids, item.Uid)
		end
	end
	-- Spare copies first, displayed ones after them.
	for _, group in groups do
		table.move(group.Displayed, 1, #group.Displayed, #group.Uids + 1, group.Uids)
	end
	local best = nil
	for _, group in groups do
		if #group.Uids >= FusionConfig.MinFusionInputs and (not best or #group.Uids > #best.Uids or (#group.Uids == #best.Uids and group.Value < best.Value)) then
			best = group
		end
	end
	if not best then
		return {}, nil, nil
	end
	local uids = {}
	for index = 1, math.min(#best.Uids, FusionConfig.MaxFusionInputs) do
		uids[index] = best.Uids[index]
	end
	return uids, MutationConfig.GetStackLabel(best.Base, best.Events), MutationConfig.GetTop(best.Base, best.Events)
end

-- A chamber of 2-5 orbs with more of the tab's tier in the inventory: what
-- the next orb and a full chamber would do to the odds ("" when nothing to say:
-- full, nothing more owned, a locked tier or an already sure fusion).
local function moreOrbsLine(): string
	local count = #selected
	if count < FusionConfig.MinFusionInputs or count >= FusionConfig.MaxFusionInputs or rebirthsNeeded(selectedTier) then
		return ""
	end
	local owned = 0
	for _, item in InventoryController.GetInventory() do
		if item.Tier == selectedTier then
			owned += 1
		end
	end
	local reachable = math.min(owned, FusionConfig.MaxFusionInputs)
	if reachable <= count then
		return ""
	end
	local bonus = fusionBonus()
	local pity = TycoonController.GetSecretPity()
	if FusionConfig.GetFusionChanceWithPity(selectedTier, count, bonus, pity) >= 1 then
		return ""
	end
	local parts = {}
	for _, orbs in { count + 1, if reachable > count + 1 then reachable else nil } do
		table.insert(parts, ("%d → %s"):format(orbs, percent(FusionConfig.GetFusionChanceWithPity(selectedTier, orbs, bonus, pity))))
	end
	return ("Add more %s for better odds: %s"):format(GoalSteps.Plural(selectedTier), table.concat(parts, ", "))
end

-- AUTO-FILL only matches a mutation when the first orb in the chamber has it,
-- so with an empty chamber and a group of 2+ orbs sharing one stack on this
-- tab, one muted line says how. The more-orbs odds line (it needs orbs in the
-- chamber, so the two never apply together) takes the same slot and wins.
updateMutationTip = function()
	local text = moreOrbsLine()
	if text == "" and #selected == 0 and not rebirthsNeeded(selectedTier) then
		local _, _, top = largestMutatedGroup()
		if top then
			local word = string.upper(top)
			text = ("Tip: put a %s orb in first, then AUTO-FILL fills %s."):format(word, word)
		end
	end
	tipLabel.Text = text
	tipLabel.Visible = text ~= ""
end

local function autoFill()
	if rebirthsNeeded(selectedTier) then
		return
	end
	local first = selectedItems()[1]
	local fill = matchingUids(first)
	if first == nil and #fill == 0 then
		local label
		fill, label = largestMutatedGroup()
		if label then
			ToastController.Show(("Filled with %s orbs (they keep their mutation)"):format(label), "Neutral")
		else
			ToastController.Show("Not enough matching orbs to fuse", "Neutral")
			local tabButton = tabButtons[selectedTier]
			if tabButton then
				UIKit.SelectFeedback(tabButton)
			end
		end
	end
	for _, uid in fill do
		if #selected >= FusionConfig.MaxFusionInputs then
			break
		end
		if not isSelected(uid) then
			table.insert(selected, uid)
		end
	end
	refreshAll()
end

-- Flies the slot orbs into the centre (client-only), then fuses.
local function fuse()
	if flying or FusionController.IsRequestPending() then
		return
	end
	if #selected < FusionConfig.MinFusionInputs or rebirthsNeeded(selectedTier) then
		return
	end
	local uids = table.clone(selected)
	flying = true
	refreshChamber()
	local info = TweenInfo.new(FLY_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, slot in slots do
		local orb = slot:FindFirstChild("Orb")
		if orb and orb:IsA("GuiObject") then
			-- The slot's offset from the hexagon's centre, reversed.
			local offset = slot.Position
			TweenService:Create(orb, info, {
				Position = UDim2.new(0.5, -offset.X.Offset, 0.5, -offset.Y.Offset),
			}):Play()
		end
	end
	task.delay(FLY_SECONDS, function()
		flying = false
		table.clear(selected)
		refreshAll()
		local safe = safeArmed
		safeArmed = false -- one token per arming
		task.spawn(FusionController.RequestFusion, uids, safe)
		task.defer(refreshChamber) -- shows the pending state
	end)
end

local function fuseAll()
	if flying or FusionController.IsRequestPending() then
		return
	end
	table.clear(selected)
	task.spawn(FusionController.RequestFuseAll)
	task.defer(refreshAll)
end

--[[ Build -------------------------------------------------------------------- ]]

local function buildChamber(column: ScrollingFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = column

	hexFrame = Instance.new("Frame")
	hexFrame.Name = "Hex"
	hexFrame.BackgroundTransparency = 1
	hexFrame.LayoutOrder = 1
	hexFrame.ZIndex = column.ZIndex + 1
	hexFrame.Parent = column
	for index = 1, FusionConfig.MaxFusionInputs do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. index
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.BackgroundColor3 = Colors.Panel2
		slot.ZIndex = hexFrame.ZIndex + 2
		slot.Parent = hexFrame
		UIKit.Corner(slot, 999)
		UIKit.Stroke(slot, 2, Colors.Faint)
		table.insert(slots, slot)
	end

	chanceLabel = UIKit.Label({
		Name = "Chance",
		Font = Fonts.Display,
		TextSize = 36,
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		ZIndex = column.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = column,
	})
	recipeLabel = UIKit.Label({
		Name = "Recipe",
		Font = Fonts.Display,
		TextSize = 18,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 4,
		ZIndex = column.ZIndex + 1,
		Stroke = 1.5,
		Parent = column,
	})

	-- The Secret meter, right under the success %.
	meterBox = Instance.new("Frame")
	meterBox.Name = "SecretMeter"
	meterBox.BackgroundTransparency = 1
	meterBox.Size = UDim2.new(1, 0, 0, METER_HEIGHT)
	meterBox.LayoutOrder = 3
	meterBox.ZIndex = column.ZIndex + 1
	meterBox.Visible = false
	meterBox.Parent = column
	meterLabel = UIKit.Label({
		Name = "Text",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = meterBox.ZIndex + 1,
		Parent = meterBox,
	})
	meterTrack = Instance.new("Frame")
	meterTrack.Name = "Track"
	meterTrack.BackgroundColor3 = Colors.Panel2
	meterTrack.AnchorPoint = Vector2.new(0.5, 0)
	meterTrack.Position = UDim2.new(0.5, 0, 0, 22)
	meterTrack.Size = UDim2.new(1, -40, 0, METER_BAR_HEIGHT)
	meterTrack.ZIndex = meterBox.ZIndex + 1
	meterTrack.Parent = meterBox
	UIKit.Corner(meterTrack, METER_BAR_HEIGHT / 2)
	UIKit.Stroke(meterTrack, 2, Colors.Faint)
	meterFill = Instance.new("Frame")
	meterFill.Name = "Fill"
	meterFill.BackgroundColor3 = UITheme.GetTierLight("Secret")
	meterFill.Size = UDim2.fromScale(0, 1)
	meterFill.ZIndex = meterTrack.ZIndex + 1
	meterFill.Parent = meterTrack
	UIKit.Corner(meterFill, METER_BAR_HEIGHT / 2)

	-- The mutation prediction, right under the recipe: plain text when the
	-- mutation carries, a red box when mixing loses it.
	predictionBox = Instance.new("Frame")
	predictionBox.Name = "Prediction"
	predictionBox.BackgroundColor3 = UITheme.TowardInk(Colors.Danger, 0.55)
	predictionBox.BackgroundTransparency = 1
	predictionBox.Size = UDim2.new(1, 0, 0, 0)
	predictionBox.AutomaticSize = Enum.AutomaticSize.Y
	predictionBox.LayoutOrder = 5
	predictionBox.ZIndex = column.ZIndex + 1
	predictionBox.Visible = false
	predictionBox.Parent = column
	UIKit.Corner(predictionBox, 10)
	local warnStroke = UIKit.Stroke(predictionBox, 2, Colors.Danger)
	warnStroke.Enabled = false
	UIKit.Padding(predictionBox, 4, 8, 4, 8)
	predictionLabel = UIKit.Label({
		Name = "Text",
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = predictionBox.ZIndex + 1,
		Parent = predictionBox,
	})

	chipsRow = Instance.new("Frame")
	chipsRow.Name = "Chips"
	chipsRow.BackgroundTransparency = 1
	chipsRow.Size = UDim2.new(1, 0, 0, CHIP_HEIGHT)
	chipsRow.LayoutOrder = 6
	chipsRow.ZIndex = column.ZIndex + 1
	chipsRow.Parent = column
	-- One row, never two: a non-wrapping list with scale widths (each chip
	-- sizes itself to 1/5 of the row minus its share of the gaps).
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.Wraps = false
	chipLayout.Padding = UDim.new(0, CHIP_GAP)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipsRow

	UIKit.Label({
		Name = "FailRule",
		Text = "Fail: keep your best orb, lose the rest",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Faint,
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 7,
		ZIndex = column.ZIndex + 1,
		Parent = column,
	})
	tipLabel = UIKit.Label({
		Name = "MutationTip",
		Text = "",
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 9,
		ZIndex = column.ZIndex + 1,
		Visible = false,
		Parent = column,
	})
	-- Shop options (hidden unless you own a token / the pass).
	optionsRow = Instance.new("Frame")
	optionsRow.Name = "ShopOptions"
	optionsRow.BackgroundTransparency = 1
	optionsRow.Size = UDim2.new(1, 0, 0, UITheme.MinTapSize + UITheme.SmallShadowOffset)
	optionsRow.LayoutOrder = 8
	optionsRow.ZIndex = column.ZIndex + 1
	optionsRow.Visible = false
	optionsRow.Parent = column
	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.FillDirection = Enum.FillDirection.Horizontal
	optionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	optionsLayout.Padding = UDim.new(0, 8)
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Parent = optionsRow
	safeButton, safeHolder = UIKit.Button({
		Name = "SafeFusion",
		Parent = optionsRow,
		Style = "Disabled",
		Text = "🛡 Safe Fusion",
		SubText = "OFF",
		TextSize = 14,
		SubTextSize = 13,
		Size = UDim2.new(0.5, -4, 0, UITheme.MinTapSize),
		LayoutOrder = 1,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = optionsRow.ZIndex,
		OnClick = function()
			safeArmed = not safeArmed and TycoonController.GetShop().SafeFusionTokens > 0
			refreshChamber()
		end,
	})
	autoButton, autoHolder = UIKit.Button({
		Name = "AutoFuse",
		Parent = optionsRow,
		Style = "Disabled",
		Text = "🔁 Auto-Fuse",
		SubText = "OFF",
		TextSize = 14,
		SubTextSize = 13,
		Size = UDim2.new(0.5, -4, 0, UITheme.MinTapSize),
		LayoutOrder = 2,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = optionsRow.ZIndex,
		OnClick = function()
			TycoonController.SetAutoFuse(not TycoonController.IsAutoFuseOn())
			refreshChamber()
		end,
	})
	layoutHex()
end

-- The ladder strip: one orb per tier with a › between, tap = that tab. The
-- best tier owned is lit (the rest dimmed), the NEXT one is ringed (a pulsing
-- stroke, never a Highlight) with "Next: Epic" at the end of the row.
local function buildLadder(column: Frame)
	local frame = Instance.new("Frame")
	frame.Name = "Ladder"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, LADDER_HEIGHT)
	frame.ZIndex = column.ZIndex + 1
	frame.Parent = column
	ladder.Frame = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 0)
	layout.Parent = frame
	for index, tier in FusionConfig.TierOrder do
		if index > 1 then
			UIKit.Label({
				Name = "Arrow",
				Text = "›",
				Font = Fonts.Display,
				TextSize = 18,
				TextColor3 = Colors.Faint,
				Size = UDim2.fromOffset(12, LADDER_HEIGHT),
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = index * 2 - 2,
				ZIndex = frame.ZIndex + 1,
				Parent = frame,
			})
		end
		local cell = Instance.new("Frame")
		cell.Name = tier .. "Cell"
		cell.BackgroundTransparency = 1
		cell.Size = UDim2.fromOffset(LADDER_CELL, LADDER_HEIGHT)
		cell.LayoutOrder = index * 2 - 1
		cell.ZIndex = frame.ZIndex + 1
		cell.Parent = frame
		ladder.Cells[tier] = cell
		local orb = UIKit.TierOrb(tier, LADDER_ORB)
		orb.AnchorPoint = Vector2.new(0.5, 0.5)
		orb.Position = UDim2.fromScale(0.5, 0.5)
		orb.ZIndex = cell.ZIndex + 1
		orb.Parent = cell
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.AnchorPoint = Vector2.new(0.5, 0.5)
		dim.Position = UDim2.fromScale(0.5, 0.5)
		dim.Size = UDim2.fromOffset(LADDER_ORB + 2, LADDER_ORB + 2)
		dim.BackgroundColor3 = Colors.Panel
		dim.BackgroundTransparency = 0.25
		dim.BorderSizePixel = 0
		dim.ZIndex = cell.ZIndex + 3
		dim.Parent = cell
		local dimCorner = Instance.new("UICorner")
		dimCorner.CornerRadius = UDim.new(1, 0)
		dimCorner.Parent = dim
		ladder.Dim[tier] = dim
		-- The tap target: >= 44 px both ways (it overlaps the strip's margins).
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AnchorPoint = Vector2.new(0.5, 0.5)
		hit.Position = UDim2.fromScale(0.5, 0.5)
		hit.Size = UDim2.fromOffset(UITheme.MinTapSize, UITheme.MinTapSize)
		hit.ZIndex = cell.ZIndex
		hit.Parent = cell
		hit.Activated:Connect(function()
			pickTab(tier)
		end)
	end
	local ring = Instance.new("Frame")
	ring.Name = "NextRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(LADDER_ORB + 8, LADDER_ORB + 8)
	ring.BackgroundTransparency = 1
	ring.ZIndex = frame.ZIndex + 6
	ring.Visible = false
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Colors.Goal
	ringStroke.Thickness = 2.5
	ringStroke.Parent = ring
	TweenService:Create(ringStroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 }):Play()
	ladder.Ring = ring
	ladder.NextLabel = UIKit.Label({
		Name = "Next",
		Text = "",
		Font = Fonts.Display,
		TextSize = 15,
		TextColor3 = Colors.Goal,
		Size = UDim2.new(1, -(LADDER_CELL * #FusionConfig.TierOrder + 12 * (#FusionConfig.TierOrder - 1)), 0, LADDER_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 99,
		ZIndex = frame.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Visible = false,
		Parent = frame,
	})
end

local function buildPicker(column: Frame)
	buildLadder(column)
	-- One row of equal-width tabs (no scrolling): name on top, count under.
	local tiers = fusableTiers()
	local tabCount = #tiers
	tabsFrame = Instance.new("Frame")
	tabsFrame.Name = "Tabs"
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.Size = UDim2.new(1, 0, 0, TAB_HEIGHT + UITheme.SmallShadowOffset + 4)
	tabsFrame.ZIndex = column.ZIndex + 1
	tabsFrame.Parent = column
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, TAB_GAP)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsFrame
	for order, tier in tiers do
		tabButtons[tier] = UIKit.Button({
			Name = tier .. "Tab",
			Parent = tabsFrame,
			Style = UIKit.UNSELECTED_STYLE,
			Text = tier,
			SubText = "0",
			TextSize = 14,
			SubTextSize = 13,
			Size = UDim2.new(1 / tabCount, -TAB_GAP * (tabCount - 1) / tabCount, 0, TAB_HEIGHT),
			LayoutOrder = order,
			ShadowOffset = UITheme.SmallShadowOffset,
			ZIndex = tabsFrame.ZIndex + 1,
			OnClick = function()
				UIKit.SelectFeedback(tabButtons[tier])
				pickTab(tier)
			end,
		})
		-- The ready dot: a fusable pair is waiting on this (unselected) tab.
		local dot = Instance.new("Frame")
		dot.Name = "ReadyDot"
		dot.AnchorPoint = Vector2.new(1, 0)
		dot.Position = UDim2.new(1, -4, 0, 4)
		dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
		dot.BackgroundColor3 = Colors.Cash
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.ZIndex = tabButtons[tier].ZIndex + 6
		dot.Parent = tabButtons[tier]
		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot
		local dotStroke = Instance.new("UIStroke")
		dotStroke.Color = Colors.Text
		dotStroke.Thickness = 1.5
		dotStroke.Parent = dot
		TweenService:Create(dot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.6 }):Play()
		ladder.Dots[tier] = dot
	end

	local gridTop = TAB_HEIGHT + UITheme.SmallShadowOffset + 10
	grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, gridTop)
	grid.Size = UDim2.new(1, 0, 1, -gridTop)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = Colors.Faint
	grid.ZIndex = column.ZIndex + 1
	grid.Parent = column
	UIKit.Padding(grid, 4, 8, 4, 4)
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y)
	gridLayout.CellPadding = UDim2.fromOffset(8, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	-- The strip shows only where it fits (not on a short phone column); the
	-- tabs and the grid slide up into its place.
	local function layoutPicker()
		local size = column.AbsoluteSize
		local shown = size.X >= LADDER_MIN_SIZE.X and size.Y >= LADDER_MIN_SIZE.Y
		local top = if shown then LADDER_HEIGHT + 4 else 0
		local strip = ladder.Frame :: Frame
		strip.Visible = shown
		tabsFrame.Position = UDim2.fromOffset(0, top)
		grid.Position = UDim2.fromOffset(0, top + gridTop)
		grid.Size = UDim2.new(1, 0, 1, -(top + gridTop))
	end
	column:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPicker)
	layoutPicker()
end

local function buildBar(content: Frame)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 0, 1, -UITheme.ShadowOffset)
	bar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT - UITheme.ShadowOffset)
	bar.ZIndex = content.ZIndex + 1
	bar.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	local autoWidth, clearWidth, allWidth = 126, 96, 168
	local _, autoHolder = UIKit.Button({
		Name = "AutoFill",
		Parent = bar,
		Style = "Blue",
		Text = "AUTO-FILL",
		TextSize = 16,
		Size = UDim2.new(0, autoWidth, 1, 0),
		LayoutOrder = 1,
		ZIndex = bar.ZIndex,
		OnClick = autoFill,
	})
	autoFillHolder = autoHolder
	UIKit.Button({
		Name = "Clear",
		Parent = bar,
		Style = "Disabled",
		Text = "CLEAR",
		TextColor3 = Colors.Muted,
		TextSize = 16,
		Size = UDim2.new(0, clearWidth, 1, 0),
		LayoutOrder = 2,
		ZIndex = bar.ZIndex,
		OnClick = function()
			table.clear(selected)
			refreshAll()
		end,
	})
	fuseButton = UIKit.Button({
		Name = "Fuse",
		Parent = bar,
		Style = "Violet",
		Text = "FUSE",
		TextSize = 24,
		Size = UDim2.new(1, -(autoWidth + clearWidth + allWidth + 30), 1, 0),
		LayoutOrder = 3,
		ZIndex = bar.ZIndex,
		OnClick = fuse,
	})
	fuseAllButton = UIKit.Button({
		Name = "FuseAll",
		Parent = bar,
		Style = "Violet",
		Text = "FUSE ALL",
		SubText = "pairs · skips mutated",
		TextSize = 15,
		SubTextSize = 13,
		Size = UDim2.new(0, allWidth, 1, 0),
		LayoutOrder = 4,
		ZIndex = bar.ZIndex,
		OnClick = fuseAll,
	})
end

local function build()
	modal = UIKit.Modal({
		Name = "FusePanel",
		Title = "FUSE",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = MAX_SIZE,
		FitContent = true,
		HeaderTop = Colors.FuseAllTop,
		BigPanel = true,
	})
	UIKit.AddHelpButton(modal, function()
		TutorialCards.ShowTopic("Fuse")
	end)
	local content = modal.Content
	local columnsHeight = UDim2.new(0, 0, 1, -(BAR_HEIGHT + 8))

	local left = Instance.new("ScrollingFrame")
	left.Name = "Chamber"
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.Size = UDim2.new(LEFT_WIDTH, -COLUMN_GAP / 2, columnsHeight.Y.Scale, columnsHeight.Y.Offset)
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.CanvasSize = UDim2.new()
	left.ScrollBarThickness = 4
	left.ScrollBarImageColor3 = Colors.Faint
	left.ZIndex = content.ZIndex + 1
	left.Parent = content
	buildChamber(left)

	local right = Instance.new("Frame")
	right.Name = "Picker"
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(LEFT_WIDTH, COLUMN_GAP / 2, 0, 0)
	right.Size = UDim2.new(1 - LEFT_WIDTH, -COLUMN_GAP / 2, columnsHeight.Y.Scale, columnsHeight.Y.Offset)
	right.ZIndex = content.ZIndex + 1
	right.Parent = content
	buildPicker(right)

	buildBar(content)
end

--[[ Public ------------------------------------------------------------------- ]]

-- Opens on the highest tier you can fuse a pair of (the ladder), or on
-- `tier` when something asked for that tab (the fusion result card's
-- GO TO RARE; that counts as picked by hand).
function FusePanel.Open(tier: string?)
	if not modal then
		return
	end
	userPicked = false
	jumpUntil = 0
	if typeof(tier) == "string" and tabButtons[tier] and not rebirthsNeeded(tier) then
		userPicked = true
		if tier ~= selectedTier then
			selectedTier = tier
			table.clear(selected)
		end
	else
		jumpToBest()
	end
	refreshAll()
	if not modal.IsOpen() then
		modal.Open()
	end
end

function FusePanel.Close()
	if modal then
		modal.Close()
	end
end

-- The tutorial's coach marks: "AutoFill", "Odds" (the count chips) or
-- "Fuse"; and how many orbs are in the chamber.
function FusePanel.GetCoachTarget(name: string): GuiObject?
	if name == "AutoFill" then
		return autoFillHolder
	elseif name == "Odds" then
		return chipsRow
	elseif name == "Fuse" then
		return fuseButton
	end
	return nil
end

-- /selftest: press AUTO-FILL on `tier` with an empty chamber; returns the
-- selected items.
function FusePanel.SelfTestAutoFill(tier: string): { any }
	if not modal then
		return {}
	end
	selectedTier = tier
	table.clear(selected)
	refreshAll()
	autoFill()
	return selectedItems()
end

-- /selftest: the mutation tip as drawn on `tier`'s tab with an empty chamber
-- (or, with `orbFirst`, one orb of that tier already in); nil when hidden.
function FusePanel.SelfTestTip(tier: string, orbFirst: boolean): string?
	if not modal then
		return nil
	end
	selectedTier = tier
	table.clear(selected)
	if orbFirst then
		for _, item in InventoryController.GetInventory() do
			if item.Tier == tier then
				table.insert(selected, item.Uid)
				break
			end
		end
	end
	refreshAll()
	return if tipLabel.Visible then tipLabel.Text else nil
end

-- /selftest: the more-orbs odds line as drawn with the first `chamber` orbs of
-- `tier` in the chamber; nil when hidden.
function FusePanel.SelfTestOdds(tier: string, chamber: number): string?
	if not modal then
		return nil
	end
	selectedTier = tier
	table.clear(selected)
	for _, item in InventoryController.GetInventory() do
		if #selected < chamber and item.Tier == tier then
			table.insert(selected, item.Uid)
		end
	end
	refreshAll()
	return if tipLabel.Visible then tipLabel.Text else nil
end

-- /selftest: the Secret meter as drawn, with `tier` on the tab and its orbs
-- auto-filled (so the success % shows): visible, its text, the fill fraction
-- it is heading for, and the chamber's % text.
function FusePanel.SelfTestMeter(tier: string): { Visible: boolean, Text: string, Fill: number, Chance: string, Selected: number }
	if modal then
		selectedTier = tier
		table.clear(selected)
		refreshAll()
		autoFill()
	end
	return {
		Visible = meterBox.Visible,
		Text = meterLabel.Text,
		Fill = meterTarget,
		Chance = chanceLabel.Text,
		Selected = #selected,
	}
end

export type LadderView = {
	Tier: string, -- the selected tab
	Ready: { [string]: boolean }, -- the tabs showing the ready dot
	Best: string?, -- the lit end of the strip
	Aim: string?, -- the ringed tier
	NextText: string, -- the strip's label ("" when hidden)
	StripShown: boolean,
	TabHeights: { [string]: number }, -- tab hit height in logical px
}

-- /selftest: what the ladder shows right now.
function FusePanel.SelfTestView(): LadderView
	local ready = {}
	local heights = {}
	for tier, dot in ladder.Dots do
		ready[tier] = dot.Visible
	end
	for tier, button in tabButtons do
		heights[tier] = button.AbsoluteSize.Y / math.max(UIKit.EffectiveScale(button), 0.01)
	end
	local strip = ladder.Frame :: Frame
	local nextLabel = ladder.NextLabel :: TextLabel
	return {
		Tier = selectedTier,
		Ready = ready,
		Best = ladder.Best,
		Aim = ladder.Aim,
		NextText = if nextLabel.Visible then nextLabel.Text else "",
		StripShown = strip.Visible,
		TabHeights = heights,
	}
end

-- /selftest: stub the fusable counts (nil = the real inventory), then open
-- the panel's tab the way Open does.
function FusePanel.SelfTestOpenWith(counts: FuseLadder.Counts?): LadderView
	countsOverride = counts
	userPicked = false
	jumpToBest()
	refreshAll()
	return FusePanel.SelfTestView()
end

-- /selftest: a fuse finished with these stubbed counts (the auto-jump).
function FusePanel.SelfTestAfterFuse(counts: FuseLadder.Counts): LadderView
	countsOverride = counts
	jumpToBest()
	refreshAll()
	return FusePanel.SelfTestView()
end

-- /selftest: tap a tab by hand (it sticks until the panel reopens).
function FusePanel.SelfTestPick(tier: string): LadderView
	pickTab(tier)
	return FusePanel.SelfTestView()
end

-- /selftest: back to the real inventory.
function FusePanel.SelfTestReset()
	countsOverride = nil
	userPicked = false
	if modal then
		refreshAll()
	end
end

function FusePanel.GetSelectedCount(): number
	return #selected
end

function FusePanel.IsOpen(): boolean
	return modal ~= nil and modal.IsOpen()
end

local function getOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function applyLayout(phone: boolean)
	isPhone = phone
	if hexFrame then
		layoutHex()
		if modal.IsOpen() then
			refreshChamber()
		end
	end
end

function FusePanel.Init()
	build()
	applyLayout(UIKit.IsPhone())
	UIKit.LayoutChanged:Connect(applyLayout)
	local function refreshIfOpen()
		if modal.IsOpen() then
			refreshAll()
		end
	end
	InventoryController.InventoryChanged:Connect(function()
		-- Right after a fuse the new orb may arrive a sync later: keep leading
		-- the player up the ladder for a few seconds.
		if modal.IsOpen() and os.clock() < jumpUntil then
			jumpToBest()
		end
		refreshIfOpen()
	end)
	TycoonController.TycoonChanged:Connect(function()
		-- Rebirths unlock Mythic; cash doesn't matter here.
		if modal.IsOpen() then
			refreshTabs()
			-- The Secret meter and a sure Secret's 100% come with the sync
			-- that follows the fusion result.
			if TycoonController.GetSecretPity() ~= pitySeen then
				refreshChamber()
			end
		end
	end)
	-- A fuse finished: lead the player to the best tier they can fuse now.
	local function afterFuse()
		jumpUntil = os.clock() + JUMP_WINDOW_SECONDS
		if modal.IsOpen() then
			jumpToBest()
		end
		refreshIfOpen()
	end
	FusionController.FusionResolved:Connect(afterFuse)
	FusionController.FuseAllResolved:Connect(afterFuse)
	FusionController.FuseTabRequested:Connect(function(tier: string)
		FusePanel.Open(tier)
	end)
	-- A Void Moon changes the success chance (and every event the odds line).
	Workspace:GetAttributeChangedSignal("EventId"):Connect(function()
		task.defer(refreshIfOpen)
	end)
	-- The machine's "Fuse" prompt opens this panel (owner-only).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player)
		if triggeringPlayer ~= localPlayer or prompt.Name ~= FUSE_PROMPT_NAME then
			return
		end
		local plot = getOwnPlot()
		if plot and prompt:IsDescendantOf(plot) then
			FusePanel.Open()
		end
	end)
end

return FusePanel
