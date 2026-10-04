--[[
	RebirthPanel
	------------
	The REBIRTH modal, opened from the portal's prompt (through
	ProximityPromptService, never the server) or the HUD's rebirth pill:

	  * Header "REBIRTH <next number>"
	  * Two stat cards: INCOME x1 -> x1.5, LUCK +0% -> +5% (RebirthConfig)
	  * An unlock row when RebirthConfig.Unlocks[next] exists
	  * YOU KEEP / YOU RESET lines
	  * Cash progress bar and "You have $9.2M of $15M" (a rebirth costs cash)
	  * The button: Disabled "Earn $X more", or Orange REBIRTH, which opens
	    a second-step confirm modal. Only the confirm's REBIRTH fires
	    RequestRebirth.

	On RebirthResult: success closes the panel and plays a short full-screen
	orange flash (ResultController shows the "REBIRTH n!" card); failure
	toasts the reason.

	Content scrolls, so the panel fits a phone (844 x 390 after the 0.8
	UIScale); card sizes follow UIKit.LayoutChanged.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local RebirthConfig = require(ReplicatedStorage.Shared.Config.RebirthConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PortalKit = require(ReplicatedStorage.Shared.Modules.PortalKit)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local ShopController = require(Controllers.ShopController)
local UIKit = require(script.Parent.UIKit)

local RebirthPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local MAX_SIZE = Vector2.new(460, 500)
local CONFIRM_SIZE = Vector2.new(400, 250)
local CARD_HEIGHT = { Desktop = 74, Phone = 62 }
local BUTTON_HEIGHT = 52
local FLASH_SECONDS = 0.4
local FLASH_START_TRANSPARENCY = 0.15

-- Short, never-blank toast text for every RebirthResult reason.
local REJECTION_TOASTS: { [string]: string } = {
	NotReady = "Not enough cash for the rebirth yet",
	TooFast = "One moment, then try again",
	NoPlot = "Your lab isn't ready yet, try again",
	DataNotLoaded = "Your lab isn't ready yet, try again",
	Carrying = "Get home with that item first!",
	ItemBeingStolen = "A thief has one of your items! Get it back first",
}
local FALLBACK_TOAST = "Couldn't rebirth, try again"

local localPlayer = Players.LocalPlayer

local modal: UIKit.Modal
local confirm: UIKit.Modal
local cardsRow: Frame
local incomeValue: TextLabel
local luckValue: TextLabel
local unlockHolder: Frame
local unlockText: TextLabel
local progressBar: Frame
local progressCaption: TextLabel
local resetLabel: TextLabel
local actionButton: TextButton
local isReady = false
local requestPending = false

--[[ Helpers ------------------------------------------------------------------ ]]

local function percent(value: number): string
	return ("+%d%%"):format(math.floor(value * 100 + 0.5))
end

local function luckBonus(rebirths: number): number
	return RebirthConfig.GetLuck(rebirths) - 1
end

local function section(parent: Instance, name: string, order: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, height)
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

local function statCard(parent: Instance, title: string, order: number): TextLabel
	local body = UIKit.Panel({
		Name = title .. "Card",
		Parent = parent,
		Size = UDim2.new(0.5, -6, 1, 0),
		LayoutOrder = order,
		Color = Colors.Panel2,
		Radius = UITheme.Radius.Row,
		StrokeColor = Colors.Rebirth,
		ShadowOffset = UITheme.SmallShadowOffset,
	})
	UIKit.Padding(body, 8, 10, 8, 10)
	UIKit.Label({
		Name = "Title",
		Text = title,
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = Colors.RebirthLabel,
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = body.ZIndex + 1,
		Parent = body,
	})
	return UIKit.Label({
		Name = "Value",
		Font = Fonts.Display,
		TextSize = 24,
		RichText = true,
		TextScaled = true,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = body.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = body,
	})
end

local function infoLines(parent: Instance, name: string, order: number, heading: string, headingColor: Color3, text: string): TextLabel
	local frame = section(parent, name, order, 40)
	UIKit.Label({
		Name = "Heading",
		Text = heading,
		Font = Fonts.BodyHeavy,
		TextSize = 12,
		TextColor3 = headingColor,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = frame,
	})
	return UIKit.Label({
		Name = "Text",
		Text = text,
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Text,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 17),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = frame,
	})
end

-- "Cash (pays the $15M) · Generators → Basic LV 1 · ..."
local function resetText(cost: number): string
	return ("Cash (pays the %s) · Generators → Basic LV %d · Multiplier → %s · Gacha price → %s"):format(
		NumberFormat.Money(cost),
		TycoonConfig.StartingBasicGeneratorLevel,
		NumberFormat.Multiplier(TycoonConfig.GetCashMultiplierValue(0)),
		NumberFormat.Money(TycoonConfig.GetGachaPullCost(0))
	)
end

--[[ Refresh ------------------------------------------------------------------ ]]

local function refresh()
	if not modal then
		return
	end
	local rebirths = TycoonController.GetRebirths()
	local nextNumber = rebirths + 1
	modal.Title.Text = ("REBIRTH %d"):format(nextNumber)

	incomeValue.Text = ("%s → %s"):format(
		NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(rebirths)),
		UIKit.Colored(NumberFormat.Multiplier(RebirthConfig.GetIncomeMultiplier(nextNumber)), Colors.Rebirth)
	)
	luckValue.Text = ("%s → %s"):format(
		percent(luckBonus(rebirths)),
		UIKit.Colored(percent(luckBonus(nextNumber)), Colors.Rebirth)
	)

	local unlock = RebirthConfig.Unlocks[nextNumber]
	unlockHolder.Visible = unlock ~= nil
	unlockText.Text = if unlock then ("UNLOCKS · %s"):format(unlock) else ""

	local cash = TycoonController.GetCash()
	local cost = math.max(TycoonController.GetRebirthCost(), 1)
	resetLabel.Text = resetText(cost)
	UIKit.SetProgress(progressBar, cash / cost)
	progressCaption.Text = ("You have %s of %s"):format(NumberFormat.Money(math.min(cash, cost)), NumberFormat.Money(cost))

	isReady = cash >= cost
	if isReady then
		UIKit.SetButton(actionButton, {
			Style = "Orange",
			Text = ("REBIRTH · %s"):format(NumberFormat.Money(cost)),
			TextColor3 = Colors.Text,
		})
	else
		UIKit.SetButton(actionButton, {
			Style = "Disabled",
			Text = ("Need %s more"):format(NumberFormat.Money(cost - cash)),
			TextColor3 = Colors.Muted,
		})
	end
end

local function applyLayout(isPhone: boolean)
	if cardsRow then
		cardsRow.Size = UDim2.new(1, 0, 0, if isPhone then CARD_HEIGHT.Phone else CARD_HEIGHT.Desktop)
	end
end

--[[ Flash -------------------------------------------------------------------- ]]

local flashGui: ScreenGui? = nil

local function playFlash()
	local gui = flashGui
	if not gui then
		local screen = UIKit.Screen("RebirthFlash", 200)
		local frame = Instance.new("Frame")
		frame.Name = "Flash"
		frame.BackgroundColor3 = Colors.Rebirth
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Parent = screen
		flashGui = screen
		gui = screen
	end
	local frame = (gui :: ScreenGui):FindFirstChild("Flash") :: Frame
	frame.BackgroundTransparency = FLASH_START_TRANSPARENCY
	TweenService:Create(frame, TweenInfo.new(FLASH_SECONDS, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

--[[ Build -------------------------------------------------------------------- ]]

local function onActionClicked()
	if not isReady then
		-- The disabled "Need $X more" button was tapped: maybe the shop's
		-- offer (its own rules).
		ShopController.OfferForShortfall("Rebirth", TycoonController.GetRebirthCost(), "RebirthPanel")
		return
	end
	confirm.Open()
end

local function onConfirmed()
	confirm.Close()
	if requestPending then
		return
	end
	requestPending = true
	RemoteEvents.RequestRebirth:FireServer()
end

local function buildConfirm()
	confirm = UIKit.Modal({
		Name = "RebirthConfirm",
		Title = "ARE YOU SURE?",
		DisplayOrder = 160,
		MaxSize = CONFIRM_SIZE,
		HeaderTop = Colors.RebirthBannerLeft,
	})
	local content = confirm.Content
	UIKit.Label({
		Name = "Message",
		Text = "Cash, generators and the Multiplier reset. Items stay.",
		Font = Fonts.Body,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 48),
		ZIndex = content.ZIndex,
		Parent = content,
	})
	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(0, 1)
	buttons.Position = UDim2.new(0, 0, 1, -UITheme.SmallShadowOffset)
	buttons.Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT)
	buttons.ZIndex = content.ZIndex
	buttons.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons
	UIKit.Button({
		Name = "Cancel",
		Parent = buttons,
		Style = "Disabled",
		Text = "Cancel",
		TextColor3 = Colors.Muted,
		TextSize = 18,
		Size = UDim2.new(0.5, -6, 1, 0),
		LayoutOrder = 1,
		ZIndex = content.ZIndex,
		OnClick = function()
			confirm.Close()
		end,
	})
	UIKit.Button({
		Name = "Rebirth",
		Parent = buttons,
		Style = "Orange",
		Text = "REBIRTH",
		TextSize = 20,
		Size = UDim2.new(0.5, -6, 1, 0),
		LayoutOrder = 2,
		ZIndex = content.ZIndex,
		OnClick = onConfirmed,
	})
end

local function build()
	modal = UIKit.Modal({
		Name = "RebirthPanel",
		Title = "REBIRTH 1",
		DisplayOrder = 145,
		MaxSize = MAX_SIZE,
		HeaderTop = Colors.RebirthBannerLeft,
	})
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = modal.Content.ZIndex
	list.Parent = modal.Content
	-- Room for strokes and shadows so the list doesn't clip them.
	UIKit.Padding(list, 3, 4, 8, 3)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	cardsRow = section(list, "Cards", 1, CARD_HEIGHT.Desktop)
	local cardsLayout = Instance.new("UIListLayout")
	cardsLayout.FillDirection = Enum.FillDirection.Horizontal
	cardsLayout.Padding = UDim.new(0, 12)
	cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	cardsLayout.Parent = cardsRow
	incomeValue = statCard(cardsRow, "INCOME", 1)
	luckValue = statCard(cardsRow, "LUCK", 2)

	local unlockBody, holder = UIKit.Panel({
		Name = "Unlock",
		Parent = list,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 2,
		Color = Colors.Panel2,
		Radius = UITheme.Radius.Row,
		StrokeColor = Colors.Rebirth,
		NoShadow = true,
	})
	unlockHolder = holder
	unlockText = UIKit.Label({
		Name = "Text",
		Font = Fonts.BodyHeavy,
		TextSize = 14,
		TextColor3 = Colors.RebirthLabel,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = unlockBody.ZIndex + 1,
		Parent = unlockBody,
	})

	infoLines(list, "Keep", 3, "YOU KEEP", Colors.Cash, "Every item · your pedestals · Index · goals · rebirths")
	resetLabel = infoLines(list, "Reset", 4, "YOU RESET", Colors.Danger, resetText(RebirthConfig.GetCost(0)))

	local progress = section(list, "Progress", 5, 40)
	progressBar = UIKit.ProgressBar({
		Name = "Bar",
		Parent = progress,
		Size = UDim2.new(1, 0, 0, 14),
		Fill = UITheme.Gradients.Orange,
	})
	progressCaption = UIKit.Label({
		Name = "Caption",
		Font = Fonts.Body,
		TextSize = 14,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = progress,
	})

	local buttonRow = section(list, "Action", 6, BUTTON_HEIGHT + UITheme.ShadowOffset)
	actionButton = UIKit.Button({
		Name = "RebirthButton",
		Parent = buttonRow,
		Style = "Disabled",
		Text = "",
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		OnClick = onActionClicked,
	})

	buildConfirm()
end

--[[ Public ------------------------------------------------------------------- ]]

function RebirthPanel.Open()
	if not modal then
		return
	end
	refresh()
	modal.Open()
end

function RebirthPanel.IsOpen(): boolean
	return modal ~= nil and modal.IsOpen()
end

local function getOwnPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function onRebirthResult(result: any)
	requestPending = false
	if typeof(result) ~= "table" then
		return
	end
	if result.Success == true then
		modal.Close()
		playFlash()
	else
		local reason = if typeof(result.Reason) == "string" then result.Reason else ""
		ToastController.Show(REJECTION_TOASTS[reason] or FALLBACK_TOAST, "Error")
	end
end

function RebirthPanel.Init()
	build()
	applyLayout(UIKit.IsPhone())
	UIKit.LayoutChanged:Connect(applyLayout)
	TycoonController.TycoonChanged:Connect(function()
		if modal.IsOpen() then
			refresh()
		end
	end)
	RemoteEvents.RebirthResult.OnClientEvent:Connect(onRebirthResult)
	-- The portal's prompt only opens this panel; it never calls the server.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, triggeringPlayer: Player)
		if triggeringPlayer ~= localPlayer or prompt.Name ~= PortalKit.PROMPT_NAME then
			return
		end
		local plot = getOwnPlot()
		if plot and prompt:IsDescendantOf(plot) then
			RebirthPanel.Open()
		end
	end)
end

return RebirthPanel
