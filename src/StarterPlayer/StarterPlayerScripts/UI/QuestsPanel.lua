--!strict
--[[
	QuestsPanel
	-----------
	The HUD 📜 QUESTS button's panel (UIKit.Modal), one scrolling list:

	  TODAY        the 3 daily quests (QuestConfig, handed out by the
	               server per UTC day): the text, the reward, a progress
	               bar with "12 / 20", and CLAIM once done (ClaimQuest
	               { Id }); claimed ones dim with a ✓.
	  LAB QUEST #n the chain's current quest, the same row.
	  POWER-UPS    each one you own: its glyph, name, what it does, the
	               count and USE (UsePowerUp { Key }). Never sold.

	Everything shown comes from the server's quest status in the snapshot
	(TycoonController.GetQuests); the server re-checks every claim and use.
	QuestResult / PowerUpResult answer with a toast.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestConfig = require(ReplicatedStorage.Shared.Config.QuestConfig)
local EventState = require(ReplicatedStorage.Shared.Modules.EventState)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local SoundKit = require(ReplicatedStorage.Shared.Modules.SoundKit)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local RemoteEvents = require(ReplicatedStorage.Shared.Network.RemoteEvents)
local Controllers = script.Parent.Parent.Controllers
local TycoonController = require(Controllers.TycoonController)
local ToastController = require(Controllers.ToastController)
local UIKit = require(script.Parent.UIKit)

local QuestsPanel = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

local PANEL_SIZE = Vector2.new(580, 560)
local DISPLAY_ORDER = 142 -- with the Gifts panel (they never show together)
local ROW_HEIGHT = 84
local POWER_ROW_HEIGHT = 64
local BUTTON_WIDTH = 112
local CLAIMED_OPACITY = 0.45

local REFUSALS: { [string]: string } = {
	NotComplete = "Not finished yet, keep going!",
	AlreadyClaimed = "Already claimed",
	Unknown = "That quest isn't here any more",
	NotLoaded = "Your lab is still loading, try again",
	NoneLeft = "You don't have any of those",
	BankFull = "Your boost time is full (3 h)",
	Carrying = "Not while you're carrying an orb",
	AlreadyOn = "Already on",
}

local modal: UIKit.Modal? = nil
local list: ScrollingFrame
local lastSignature = ""
local pendingClaims: { [string]: boolean } = {}
local pendingUses: { [string]: boolean } = {}

local function claim(id: string)
	if pendingClaims[id] then
		return
	end
	pendingClaims[id] = true
	RemoteEvents.ClaimQuest:FireServer({ Id = id })
	task.delay(6, function()
		pendingClaims[id] = nil
	end)
end

local function use(key: string)
	if pendingUses[key] then
		return
	end
	pendingUses[key] = true
	RemoteEvents.UsePowerUp:FireServer({ Key = key })
	task.delay(3, function()
		pendingUses[key] = nil
	end)
end

local function sectionLabel(text: string, order: number, color: Color3)
	UIKit.Label({
		Name = "Section" .. order,
		Text = text,
		Font = Fonts.Display,
		TextSize = 16,
		TextColor3 = color,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		ZIndex = list.ZIndex + 1,
		Stroke = UITheme.Stroke.Text,
		Parent = list,
	})
end

-- One quest row: text + reward on the left, the bar under them, CLAIM /
-- ✓ / the count on the right.
local function questRow(view: any, order: number)
	local done = view.Done == true
	local claimed = view.Claimed == true
	local gradient: { { any } } = if done and not claimed
		then { { 0, UITheme.TowardInk(Colors.Cash, 0.55) }, { 1, Colors.Panel2 } }
		else { { 0, Colors.Panel3 }, { 1, Colors.Panel2 } }
	local body, holder = UIKit.Panel({
		Name = "Quest_" .. tostring(view.Id),
		Parent = list,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Gradient = gradient,
		Radius = 14,
		StrokeColor = if done and not claimed then Colors.Cash else nil,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = list.ZIndex + 1,
	})
	local z = body.ZIndex + 1
	UIKit.Padding(body, 8, 12, 8, 12)
	local textLabel = UIKit.Label({
		Name = "Text",
		Text = tostring(view.Text),
		Font = Fonts.BodyHeavy,
		TextSize = 16,
		Size = UDim2.new(1, -(BUTTON_WIDTH + 12), 0, 22),
		ZIndex = z,
		Parent = body,
	})
	UIKit.FitText(textLabel, 16, 11)
	UIKit.Label({
		Name = "Reward",
		Text = "Reward: " .. tostring(view.RewardText),
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = Colors.Muted,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -(BUTTON_WIDTH + 12), 0, 18),
		ZIndex = z,
		Parent = body,
	})
	local target = if typeof(view.Target) == "number" and view.Target > 0 then view.Target else 1
	local progress = if typeof(view.Progress) == "number" then view.Progress else 0
	local bar = UIKit.ProgressBar({
		Name = "Progress",
		Parent = body,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, -(BUTTON_WIDTH + 70), 0, 10),
		Fill = if done then UITheme.Gradients.Green else UITheme.Gradients.Gold,
		ZIndex = z,
	})
	UIKit.SetProgress(bar, math.clamp(progress / target, 0, 1))
	UIKit.Label({
		Name = "Count",
		Text = ("%s / %s"):format(NumberFormat.Short(progress), NumberFormat.Short(target)),
		Font = Fonts.Body,
		TextSize = 12,
		TextColor3 = Colors.Muted,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -(BUTTON_WIDTH + 8), 1, 2),
		Size = UDim2.fromOffset(58, 14),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = z,
		Parent = body,
	})
	if claimed then
		UIKit.SetOpacity(holder, CLAIMED_OPACITY)
		UIKit.Label({
			Name = "Check",
			Text = "✓",
			Font = Fonts.Display,
			TextSize = 36,
			TextColor3 = Colors.Cash,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(BUTTON_WIDTH, 44),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z,
			Stroke = UITheme.Stroke.Text,
			Parent = body,
		})
	else
		UIKit.Button({
			Name = "Claim",
			Parent = body,
			Style = if done then "Green" else "Disabled",
			Text = if done then "CLAIM" else "…",
			TextSize = 18,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(BUTTON_WIDTH, UITheme.MinTapSize + 4),
			ShadowOffset = UITheme.SmallShadowOffset,
			ZIndex = z,
			OnClick = function()
				if done then
					claim(tostring(view.Id))
				else
					ToastController.Show(REFUSALS.NotComplete, "Neutral")
				end
			end,
		})
	end
end

local function powerUpRow(def: QuestConfig.PowerUpDef, count: number, order: number)
	local body = UIKit.Panel({
		Name = "PowerUp_" .. def.Key,
		Parent = list,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, POWER_ROW_HEIGHT),
		Color = Colors.Panel2,
		Radius = 14,
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = list.ZIndex + 1,
	})
	local z = body.ZIndex + 1
	UIKit.Padding(body, 6, 12, 6, 12)
	UIKit.Label({
		Name = "Glyph",
		Text = def.Glyph,
		TextSize = 30,
		Size = UDim2.fromOffset(40, 50),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z,
		Parent = body,
	})
	UIKit.Label({
		Name = "Name",
		Text = ("%s  ×%d"):format(def.Name, count),
		Font = Fonts.BodyHeavy,
		TextSize = 16,
		Position = UDim2.fromOffset(48, 2),
		Size = UDim2.new(1, -(48 + BUTTON_WIDTH + 12), 0, 22),
		ZIndex = z,
		Parent = body,
	})
	local armed = TycoonController.IsArmed(def.Key)
	local blurb = UIKit.Label({
		Name = "Blurb",
		Text = if armed then "Armed: waiting for its moment" else def.Blurb,
		Font = Fonts.Body,
		TextSize = 13,
		TextColor3 = if armed then Colors.Cash else Colors.Muted,
		Position = UDim2.fromOffset(48, 26),
		Size = UDim2.new(1, -(48 + BUTTON_WIDTH + 12), 0, 22),
		ZIndex = z,
		Parent = body,
	})
	UIKit.FitText(blurb, 13, 10)
	UIKit.Button({
		Name = "Use",
		Parent = body,
		Style = if armed then "Disabled" else "Violet",
		Text = if armed then "ARMED" else "USE",
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(BUTTON_WIDTH, UITheme.MinTapSize + 2),
		ShadowOffset = UITheme.SmallShadowOffset,
		ZIndex = z,
		OnClick = function()
			if not armed then
				use(def.Key)
			end
		end,
	})
end

local function signatureOf(quests: any): string
	local parts = {}
	if quests then
		for _, view in quests.Daily or {} do
			table.insert(parts, ("%s:%s:%s:%s"):format(tostring(view.Id), tostring(view.Progress), tostring(view.Done), tostring(view.Claimed)))
		end
		local chain = quests.Chain
		if chain then
			table.insert(parts, ("c%s:%s:%s"):format(tostring(chain.Chain), tostring(chain.Progress), tostring(chain.Done)))
		end
	end
	for _, key in QuestConfig.PowerUpOrder do
		table.insert(parts, ("%s=%d%s"):format(key, TycoonController.GetPowerUpCount(key), if TycoonController.IsArmed(key) then "a" else ""))
	end
	return table.concat(parts, ",")
end

local function refresh(force: boolean?)
	local card = modal
	if not card or not card.IsOpen() then
		return
	end
	local quests = TycoonController.GetQuests()
	local signature = signatureOf(quests)
	if not force and signature == lastSignature then
		return
	end
	lastSignature = signature
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local resetIn = 86400 - os.time() % 86400
	sectionLabel(("TODAY · new quests in %s"):format(EventState.FormatTimer(resetIn)), nextOrder(), Colors.Goal)
	if quests and quests.Daily then
		for _, view in quests.Daily do
			questRow(view, nextOrder())
		end
	else
		sectionLabel("Loading…", nextOrder(), Colors.Muted)
	end
	if quests and quests.Chain then
		sectionLabel(("LAB QUEST #%d"):format(tonumber(quests.Chain.Chain) or 1), nextOrder(), Colors.Rebirth)
		questRow(quests.Chain, nextOrder())
	end
	sectionLabel("POWER-UPS · earned from quests, use them any time", nextOrder(), Colors.Cash)
	local any = false
	for _, key in QuestConfig.PowerUpOrder do
		local count = TycoonController.GetPowerUpCount(key)
		local def = QuestConfig.PowerUps[key]
		if def and (count > 0 or TycoonController.IsArmed(key)) then
			any = true
			powerUpRow(def, count, nextOrder())
		end
	end
	if not any then
		UIKit.Label({
			Name = "NoPowerUps",
			Text = "None yet: claim quests to earn some.",
			Font = Fonts.Body,
			TextSize = 14,
			TextColor3 = Colors.Faint,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = nextOrder(),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = list.ZIndex + 1,
			Parent = list,
		})
	end
end

local function build(): UIKit.Modal
	local created = UIKit.Modal({
		Name = "Quests",
		Title = "📜 QUESTS",
		DisplayOrder = DISPLAY_ORDER,
		MaxSize = PANEL_SIZE,
		HeaderTop = Colors.QuestsTop,
	})
	created.Subtitle.Text = "Finish quests for free power-ups"
	created.Subtitle.Visible = true
	local content = created.Content

	list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Colors.Faint
	list.ZIndex = content.ZIndex + 1
	list.Parent = content
	UIKit.Padding(list, 4, 12, 8, 4)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	modal = created
	return created
end

local function onQuestResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.Id) == "string" then
		pendingClaims[payload.Id] = nil
	end
	if payload.Result == "Claimed" then
		local lines = if typeof(payload.Lines) == "table" then payload.Lines else {}
		SoundKit.Play("RevealMinor", nil)
		ToastController.Show("📜 Quest complete! " .. table.concat(lines, " · "), "Neutral", { Big = true })
	else
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else ""
		ToastController.Show(REFUSALS[reason] or "Couldn't claim that, try again", "Error")
	end
	refresh(true)
end

local function onPowerUpResult(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if typeof(payload.Key) == "string" then
		pendingUses[payload.Key] = nil
	end
	if payload.Result == "Used" then
		SoundKit.Play("Toast", nil)
		ToastController.Show(if typeof(payload.Text) == "string" then payload.Text else "Power-up on!", "Neutral")
	else
		local reason = if typeof(payload.Reason) == "string" then payload.Reason else ""
		ToastController.Show(REFUSALS[reason] or "Can't use that right now", "Error")
	end
	refresh(true)
end

function QuestsPanel.Init()
	RemoteEvents.QuestResult.OnClientEvent:Connect(onQuestResult)
	RemoteEvents.PowerUpResult.OnClientEvent:Connect(onPowerUpResult)
	TycoonController.TycoonChanged:Connect(function()
		refresh()
	end)
end

-- The HUD power-up row's taps go through the same request path.
QuestsPanel.UsePowerUp = use

function QuestsPanel.IsOpen(): boolean
	return modal ~= nil and (modal :: UIKit.Modal).IsOpen()
end

function QuestsPanel.Open()
	local card = modal or build()
	if not card.IsOpen() then
		card.Open()
	end
	refresh(true)
end

function QuestsPanel.Close()
	if modal then
		(modal :: UIKit.Modal).Close()
	end
end

function QuestsPanel.Toggle()
	if QuestsPanel.IsOpen() then
		QuestsPanel.Close()
	else
		QuestsPanel.Open()
	end
end

-- For the HUD: quests done and not claimed (the QUESTS badge).
function QuestsPanel.GetReadyCount(): number
	local quests = TycoonController.GetQuests()
	return if quests and typeof(quests.Ready) == "number" then quests.Ready else 0
end

-- The goal card's tracker: the nearest unfinished quest (the unclaimed
-- daily closest to done, else the chain), or nil.
function QuestsPanel.GetNearest(): any
	local quests = TycoonController.GetQuests()
	if not quests then
		return nil
	end
	local best: any = nil
	local bestShare = -1
	for _, view in quests.Daily or {} do
		if not view.Done and not view.Claimed and typeof(view.Target) == "number" and view.Target > 0 then
			local share = (tonumber(view.Progress) or 0) / view.Target
			if share > bestShare then
				best, bestShare = view, share
			end
		end
	end
	if not best and quests.Chain and not quests.Chain.Done then
		best = quests.Chain
	end
	return best
end

return QuestsPanel
