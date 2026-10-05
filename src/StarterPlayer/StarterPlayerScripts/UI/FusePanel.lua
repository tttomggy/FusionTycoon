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
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local Controllers = script.Parent.Parent.Controllers
local InventoryController = require(Controllers.InventoryController)
local TycoonController = require(Controllers.TycoonController)
local FusionController = require(Controllers.FusionController)
local ToastController = require(Controllers.ToastController)
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
local chipsRow: Frame
local predictionBox: Frame
local optionsRow: Frame
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
local fuseAllButton: TextButton
local tabButtons: { [string]: TextButton } = {}

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
	return MutationConfig.GetDisplayName(if def then def.Name else tostring(item.ItemId), item.Mutation)
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

-- Drops selections that are gone, on a pedestal, or of another tier.
local function pruneSelection()
	local byUid = itemsByUid()
	for index = #selected, 1, -1 do
		local item = byUid[selected[index]]
		if not item or InventoryController.IsInUse(item) or item.Tier ~= selectedTier then
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
	local best = mix.Best
	if not best then
		return nil, false, nil
	end
	if not mix.Mixed then
		return ("✨ Keeps %s ×%d, might roll better"):format(best:upper(), MutationConfig.GetMultiplier(best)),
			false,
			UITheme.GetMutationColor(best)
	end
	local below = if mix.BelowShared then (mix.BelowMutation or "plain") else "lower"
	local result = if mix.Kept then mix.Kept else "plain"
	return ("⚠ %d %s orb%s mixed in: the %s comes out %s, not %s. Use only %s orbs to keep %s."):format(
		mix.BelowCount,
		below,
		if mix.BelowCount == 1 then "" else "s",
		nextTier,
		result,
		best,
		best,
		best
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
		local dragging = item ~= nil
			and mix.Mixed
			and MutationConfig.GetRank(item.Mutation) < MutationConfig.GetRank(mix.Best)
		local ring = slot:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Color = if dragging then Colors.Danger else Colors.Faint
			ring.Thickness = if dragging then 4 else 2
		end
		if item then
			local orb = UIKit.TierOrb(item.Tier, hex.Slot - 10, nil, item.Mutation)
			orb.Name = "Orb"
			orb.AnchorPoint = Vector2.new(0.5, 0.5)
			orb.Position = UDim2.fromScale(0.5, 0.5)
			orb.ZIndex = slot.ZIndex + 1
			orb.Parent = slot
		end
	end

	-- With the live event's success bonus (Void Moon), like the server's roll.
	local bonus = EventState.GetFusionSuccessBonus()
	local chance = FusionConfig.GetFusionChance(selectedTier, math.max(count, FusionConfig.MinFusionInputs), bonus)
	if count >= FusionConfig.MinFusionInputs then
		chanceLabel.Text = percent(chance)
		chanceLabel.TextColor3 = chanceColor(chance)
	else
		chanceLabel.Text = ("Add %d+"):format(FusionConfig.MinFusionInputs)
		chanceLabel.TextColor3 = Colors.Faint
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
		-- the chamber is highlighted; a Void Moon tints every chip purple.
		local chip = Instance.new("Frame")
		chip.Name = "Chip" .. chipCount
		chip.BackgroundColor3 = if current then Colors.VioletPill elseif bonus > 0 then UITheme.TowardInk(UITheme.Mutation.Void, 0.45) else Colors.Panel2
		chip.LayoutOrder = chipCount
		chip.Size = UDim2.new(1 / chipTotal, -CHIP_GAP * (chipTotal - 1) / chipTotal, 1, 0)
		chip.ZIndex = chipsRow.ZIndex + 1
		UIKit.Corner(chip, 12)
		UIKit.Stroke(chip, if current then 3 else 2, if current then Colors.White else nil)
		UIKit.Label({
			Name = "Count",
			Text = ("%d orbs"):format(chipCount),
			Font = Fonts.BodyHeavy,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if current then Colors.Text else Colors.Muted,
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = chip.ZIndex + 1,
			Parent = chip,
		})
		local chanceLabel = UIKit.Label({
			Name = "Chance",
			Text = percent(FusionConfig.GetFusionChance(selectedTier, chipCount, bonus)),
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
	UIKit.MutationCardStroke(body, item.Mutation)
	local z = body.ZIndex + 1
	local orb = UIKit.TierOrb(item.Tier, 48, nil, item.Mutation)
	orb.AnchorPoint = Vector2.new(0.5, 0)
	orb.Position = UDim2.new(0.5, 0, 0, 8)
	orb.ZIndex = z
	orb.Parent = body
	UIKit.Label({
		Name = "ItemName",
		Text = itemName(item),
		Font = Fonts.Display,
		TextSize = 12,
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
		Mutation = item.Mutation,
		Label = if item.Mutation then ("×%d"):format(MutationConfig.GetMultiplier(item.Mutation)) else nil,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		TextSize = 12,
		Height = 18,
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

local function refreshTabs()
	for tier, button in tabButtons do
		local needed = rebirthsNeeded(tier)
		local current = tier == selectedTier
		UIKit.SetButton(button, {
			Style = if current then "Violet" elseif needed then "Disabled" else "Blue",
			SubText = if needed then "🔒" else tostring(#InventoryController.GetFusableItemsByTier(tier)),
			TextColor3 = if needed and not current then Colors.Muted else Colors.Text,
		})
	end
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

--[[ Actions ------------------------------------------------------------------ ]]

-- Tops the chamber up to 6. Empty chamber: unmutated items, as before.
-- Otherwise only items with the SAME mutation as the first orb in, so a
-- fill never drags a mutation down.
local function matchingUids(mutation: string?): { string }
	if mutation == nil then
		return FusionController.GetAutoFill(selectedTier)
	end
	local uids = {}
	for _, item in InventoryController.GetInventory() do
		if item.Tier == selectedTier and item.Mutation == mutation and not InventoryController.IsInUse(item) then
			table.insert(uids, item.Uid)
		end
	end
	return uids
end

local function autoFill()
	if rebirthsNeeded(selectedTier) then
		return
	end
	local first = selectedItems()[1]
	for _, uid in matchingUids(if first then first.Mutation else nil) do
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
		LayoutOrder = 3,
		ZIndex = column.ZIndex + 1,
		Stroke = 1.5,
		Parent = column,
	})

	-- The mutation prediction, right under the recipe: plain text when the
	-- mutation carries, a red box when mixing loses it.
	predictionBox = Instance.new("Frame")
	predictionBox.Name = "Prediction"
	predictionBox.BackgroundColor3 = UITheme.TowardInk(Colors.Danger, 0.55)
	predictionBox.BackgroundTransparency = 1
	predictionBox.Size = UDim2.new(1, 0, 0, 0)
	predictionBox.AutomaticSize = Enum.AutomaticSize.Y
	predictionBox.LayoutOrder = 4
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
	chipsRow.LayoutOrder = 5
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
		LayoutOrder = 6,
		ZIndex = column.ZIndex + 1,
		Parent = column,
	})
	-- Shop options (hidden unless you own a token / the pass).
	optionsRow = Instance.new("Frame")
	optionsRow.Name = "ShopOptions"
	optionsRow.BackgroundTransparency = 1
	optionsRow.Size = UDim2.new(1, 0, 0, UITheme.MinTapSize + UITheme.SmallShadowOffset)
	optionsRow.LayoutOrder = 7
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
		SubTextSize = 11,
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
		SubTextSize = 11,
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

local function buildPicker(column: Frame)
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
			Style = "Blue",
			Text = tier,
			SubText = "0",
			TextSize = 14,
			SubTextSize = 12,
			Size = UDim2.new(1 / tabCount, -TAB_GAP * (tabCount - 1) / tabCount, 0, TAB_HEIGHT),
			LayoutOrder = order,
			ShadowOffset = UITheme.SmallShadowOffset,
			ZIndex = tabsFrame.ZIndex + 1,
			OnClick = function()
				local needed = rebirthsNeeded(tier)
				if needed then
					ToastController.Show(("Rebirth %d to fuse %ss"):format(needed, tier), "Neutral")
					return
				end
				selectTier(tier)
			end,
		})
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
	UIKit.Button({
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
		SubTextSize = 12,
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
		HeaderTop = Colors.FuseAllTop,
	})
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

-- Opens on the lowest tier you can fuse a pair of (or the current tab).
function FusePanel.Open()
	if not modal then
		return
	end
	if #selected == 0 then
		for _, tier in fusableTiers() do
			if
				not rebirthsNeeded(tier)
				and #InventoryController.GetFusableItemsByTier(tier) >= FusionConfig.MinFusionInputs
			then
				selectedTier = tier
				break
			end
		end
	end
	refreshAll()
	modal.Open()
end

function FusePanel.Close()
	if modal then
		modal.Close()
	end
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
	InventoryController.InventoryChanged:Connect(refreshIfOpen)
	TycoonController.TycoonChanged:Connect(function()
		-- Rebirths unlock Mythic; cash doesn't matter here.
		if modal.IsOpen() then
			refreshTabs()
		end
	end)
	FusionController.FusionResolved:Connect(refreshIfOpen)
	FusionController.FuseAllResolved:Connect(refreshIfOpen)
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
