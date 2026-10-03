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
	         recipe, count chips (2 · 55% ...), the fail rule, and a
	         mutation line when any input is mutated.
	  Right  tier tabs with fusable counts (Mythic locked before Rebirth 1,
	         no Secret tab) and a grid of that tier's items, normal first.
	         Tap to add or remove; selected cards dim and show a check.
	  Bottom AUTO-FILL (normal items only), CLEAR, FUSE (2+), FUSE ALL.

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
local Controllers = script.Parent.Parent.Controllers
local InventoryController = require(Controllers.InventoryController)
local TycoonController = require(Controllers.TycoonController)
local FusionController = require(Controllers.FusionController)
local ToastController = require(Controllers.ToastController)
local UIKit = require(script.Parent.UIKit)

local FusePanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(760, 470)
local DISPLAY_ORDER = 115 -- under Toasts (120) and Results (130)
local FUSE_PROMPT_NAME = "FusePrompt"
local LEFT_WIDTH = 0.44
local COLUMN_GAP = 14
local BAR_HEIGHT = 56
local TAB_SIZE = Vector2.new(124, UITheme.MinTapSize)
local CARD_SIZE = Vector2.new(88, 108)
local FLY_SECONDS = 0.35

-- Chamber geometry (px) per layout.
local HEX = {
	Desktop = { Height = 190, Radius = 70, Slot = 52, Center = 66 },
	Phone = { Height = 150, Radius = 54, Slot = 42, Center = 50 },
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
local mutationLabel: TextLabel
local tabsFrame: ScrollingFrame
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
		if not item or item.InUse or item.Tier ~= selectedTier then
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

-- The mutation line: shared mutation carries, mixed doesn't.
local function mutationText(items: { any }): string?
	local anyMutated = false
	local shared: string? = nil
	local allShare = true
	for index, item in items do
		if item.Mutation then
			anyMutated = true
		end
		if index == 1 then
			shared = item.Mutation
		elseif item.Mutation ~= shared then
			allShare = false
		end
	end
	if not anyMutated then
		return nil
	end
	if allShare and shared then
		return ("All %s → result stays %s"):format(shared, shared)
	end
	return "Mixed mutations → result is normal (can still roll one)"
end

--[[ Chamber ------------------------------------------------------------------ ]]

local function layoutHex()
	local hex = if isPhone then HEX.Phone else HEX.Desktop
	hexFrame.Size = UDim2.new(1, 0, 0, hex.Height)
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
		if item then
			local orb = UIKit.TierOrb(item.Tier, hex.Slot - 10, nil, item.Mutation)
			orb.Name = "Orb"
			orb.AnchorPoint = Vector2.new(0.5, 0.5)
			orb.Position = UDim2.fromScale(0.5, 0.5)
			orb.ZIndex = slot.ZIndex + 1
			orb.Parent = slot
		end
	end

	local chance = FusionConfig.GetFusionChance(selectedTier, math.max(count, FusionConfig.MinFusionInputs))
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
	for chipCount = FusionConfig.MinFusionInputs, FusionConfig.MaxFusionInputs do
		local current = chipCount == count
		UIKit.Pill({
			Name = "Chip" .. chipCount,
			Parent = chipsRow,
			Text = ("%d · %s"):format(chipCount, percent(FusionConfig.GetFusionChance(selectedTier, chipCount))),
			Color = if current then Colors.VioletPill else Colors.Panel2,
			TextColor3 = if current then Colors.Text else Colors.Muted,
			Font = Fonts.BodyHeavy,
			TextSize = 12,
			Height = 24,
			LayoutOrder = chipCount,
			ZIndex = chipsRow.ZIndex + 1,
		})
	end

	local mutation = mutationText(items)
	mutationLabel.Visible = mutation ~= nil
	mutationLabel.Text = mutation or ""

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
	local orb = UIKit.TierOrb(item.Tier, 44, nil, item.Mutation)
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
		Position = UDim2.fromOffset(4, 58),
		Size = UDim2.new(1, -8, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Stroke = 1.5,
		Parent = body,
	})
	UIKit.MutationPill({
		Parent = body,
		Mutation = item.Mutation,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		TextSize = 10,
		Height = 16,
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
			Text = if needed
				then ("🔒 %s"):format(tier)
				else ("%s %d"):format(tier, #InventoryController.GetFusableItemsByTier(tier)),
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

-- Tops the chamber up to 6 with unmutated items (never mutated ones).
local function autoFill()
	if rebirthsNeeded(selectedTier) then
		return
	end
	for _, uid in FusionController.GetAutoFill(selectedTier) do
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
		task.spawn(FusionController.RequestFusion, uids)
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
		TextSize = 16,
		RichText = true,
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 3,
		ZIndex = column.ZIndex + 1,
		Stroke = 1.5,
		Parent = column,
	})

	chipsRow = Instance.new("Frame")
	chipsRow.Name = "Chips"
	chipsRow.BackgroundTransparency = 1
	chipsRow.Size = UDim2.new(1, 0, 0, 26)
	chipsRow.LayoutOrder = 4
	chipsRow.ZIndex = column.ZIndex + 1
	chipsRow.Parent = column
	local chipLayout = Instance.new("UIListLayout")
	chipLayout.FillDirection = Enum.FillDirection.Horizontal
	chipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	chipLayout.Padding = UDim.new(0, 4)
	chipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipLayout.Parent = chipsRow

	UIKit.Label({
		Name = "FailRule",
		Text = "Fail: keep your best orb, lose the rest",
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Faint,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 5,
		ZIndex = column.ZIndex + 1,
		Parent = column,
	})
	mutationLabel = UIKit.Label({
		Name = "MutationRule",
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.GoldLabel,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 6,
		ZIndex = column.ZIndex + 1,
		Visible = false,
		Parent = column,
	})
	layoutHex()
end

local function buildPicker(column: Frame)
	tabsFrame = Instance.new("ScrollingFrame")
	tabsFrame.Name = "Tabs"
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.BorderSizePixel = 0
	tabsFrame.Size = UDim2.new(1, 0, 0, TAB_SIZE.Y + UITheme.SmallShadowOffset + 8)
	tabsFrame.ScrollingDirection = Enum.ScrollingDirection.X
	tabsFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabsFrame.CanvasSize = UDim2.new()
	tabsFrame.ScrollBarThickness = 4
	tabsFrame.ScrollBarImageColor3 = Colors.Faint
	tabsFrame.ZIndex = column.ZIndex + 1
	tabsFrame.Parent = column
	UIKit.Padding(tabsFrame, 2, 4, 6, 2)
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabsFrame
	for order, tier in fusableTiers() do
		tabButtons[tier] = UIKit.Button({
			Name = tier .. "Tab",
			Parent = tabsFrame,
			Style = "Blue",
			Text = tier,
			TextSize = 14,
			Size = UDim2.fromOffset(TAB_SIZE.X, TAB_SIZE.Y),
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

	local gridTop = TAB_SIZE.Y + UITheme.SmallShadowOffset + 14
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
		SubTextSize = 10,
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
