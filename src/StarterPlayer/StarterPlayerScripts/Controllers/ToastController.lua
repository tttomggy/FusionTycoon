--[[
	ToastController
	---------------
	Small, short-lived messages just above the HUD's bottom buttons: "Need $936
	for a pull", "Need $13.5K", "Pedestals full · remove one first".

	44 px tall, corner 12, ink stroke 3. Error toasts use the Red gradient,
	neutral ones the Disabled fill. Each holds 2 s; at most 2 are visible (a
	third pushes the oldest out). No sound.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local ToastController = {}

export type ToastKind = "Error" | "Neutral" | "Success"

local Colors = UITheme.Colors

local TOAST_HEIGHT = 44
local HOLD_SECONDS = 2
-- Big toasts: the one-time heist tips (bigger text, held longer).
local BIG_TOAST_HEIGHT = 56
local BIG_HOLD_SECONDS = 4
local BIG_TEXT_SIZE = 20
local MAX_VISIBLE = 2
-- Sits above the bottom buttons and the REBIRTH! slot (UITheme). Raised
-- while a bottom result card (fail / pull row) is showing.
local BASE_BOTTOM_OFFSET = UITheme.BottomStackOffset

local stack: Frame? = nil
local visible: { Frame } = {}
local bottomInset = 0

local function ensureBuilt(): Frame
	if stack then
		return stack
	end
	local gui = UIKit.Screen("Toasts", 120)

	local frame = Instance.new("Frame")
	frame.Name = "Stack"
	frame.BackgroundTransparency = 1
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -BASE_BOTTOM_OFFSET)
	frame.Size = UDim2.fromOffset(720, (BIG_TOAST_HEIGHT + 12) * MAX_VISIBLE)
	frame.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 8)
	layout.Parent = frame

	stack = frame
	return frame
end

local function dismiss(toast: Frame)
	local index = table.find(visible, toast)
	if not index then
		return
	end
	table.remove(visible, index)
	local tween = UIKit.PopOut(toast)
	tween.Completed:Once(function()
		toast:Destroy()
	end)
end

local order = 0

export type ToastOptions = { Big: boolean? }

-- While the tutorial runs, one-time tips (big toasts) wait: `hold` says
-- whether to hold them now; FlushHeld shows what waited, in order.
local holdBig: (() -> boolean)? = nil
local held: { { Text: string, Kind: ToastKind?, Options: ToastOptions? } } = {}

function ToastController.SetBigHold(hold: () -> boolean)
	holdBig = hold
end

function ToastController.Show(text: string, kind: ToastKind?, options: ToastOptions?)
	if options and options.Big and holdBig and holdBig() then
		table.insert(held, { Text = text, Kind = kind, Options = options })
		return
	end
	local parent = ensureBuilt()
	order += 1
	local big = options ~= nil and options.Big == true
	local height = if big then BIG_TOAST_HEIGHT else TOAST_HEIGHT

	-- Holder sized to the toast + its 4 px shadow so the list layout spaces
	-- them correctly.
	local holder = Instance.new("Frame")
	holder.Name = "Toast"
	holder.BackgroundTransparency = 1
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Size = UDim2.fromOffset(0, height + UITheme.SmallShadowOffset)
	holder.LayoutOrder = order

	-- The gradient lives on a background Frame and the words on a child
	-- label: a UIGradient on a TextLabel tints its text too, which turned
	-- white text red-on-red (blank toasts).
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AutomaticSize = Enum.AutomaticSize.X
	body.Size = UDim2.fromOffset(0, height)
	body.BackgroundColor3 = Colors.White
	body.ZIndex = 2
	body.Parent = holder
	UIKit.Padding(body, 0, 18, 0, 18)
	UIKit.Corner(body, UITheme.Radius.Toast)
	UIKit.Stroke(body, UITheme.Stroke.Default)
	UIKit.PairGradient(
		body,
		if kind == "Neutral" then UITheme.Gradients.Disabled
			elseif kind == "Success" then UITheme.Gradients.Green
			else UITheme.Gradients.Red
	)
	UIKit.Label({
		Name = "Text",
		Text = text,
		Font = if big then UITheme.Fonts.BodyHeavy else UITheme.Fonts.Body,
		TextSize = if big then BIG_TEXT_SIZE else 16,
		TextColor3 = Colors.Text,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = body,
	})
	UIKit.Shadow(body, UITheme.SmallShadowOffset)

	holder.Parent = parent
	table.insert(visible, holder)
	UIKit.PopIn(holder)

	while #visible > MAX_VISIBLE do
		dismiss(visible[1])
	end

	task.delay(if big then BIG_HOLD_SECONDS else HOLD_SECONDS, function()
		dismiss(holder)
	end)
end

-- Raises the toast stack by `inset` px (a bottom result card is showing).
function ToastController.FlushHeld()
	local waiting = held
	held = {}
	for index, toast in waiting do
		task.delay((index - 1) * 1.5, ToastController.Show, toast.Text, toast.Kind, toast.Options)
	end
end

function ToastController.SetBottomInset(inset: number)
	bottomInset = inset
	local frame = ensureBuilt()
	TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
		Position = UDim2.new(0.5, 0, 1, -(BASE_BOTTOM_OFFSET + bottomInset)),
	}):Play()
end

function ToastController.Init()
	ensureBuilt()
end

return ToastController
