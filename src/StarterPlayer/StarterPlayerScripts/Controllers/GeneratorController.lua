--[[
	GeneratorController
	-------------------
	The client side of the generator bays (GeneratorKit builds them on the
	server):

	  * Buy / Upgrade prompts on your own generators fire the same
	    RequestUpgrade remote as the Upgrades panel (TycoonController), or
	    show the "Need $X" toast when you can't afford it.
	  * A successful upgrade (from either place) bursts the Core in the tier
	    colour, bumps the Body 1 -> 1.08 -> 1 and toasts "+$X/s".
	  * Once a second, each owned generator within PopRadius of the camera
	    floats "+$X" (its income/s, multiplier included) over its Core.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)
local HudController = require(script.Parent.HudController)

local GeneratorController = {}

local BUMP_SCALE = 1.08
local BUMP_SECONDS = 0.25
local BURST_COUNT = 30
local POP_ABOVE_CORE = 1

local localPlayer = Players.LocalPlayer

local function getPlot(): Instance?
	local folder = Workspace:FindFirstChild(PlotNaming.PlotsFolderName)
	return folder and folder:FindFirstChild(PlotNaming.GetPlotName(localPlayer.UserId))
end

local function getModel(id: string): Model?
	local plot = getPlot()
	local model = plot and plot:FindFirstChild(GeneratorKit.GetModelName(id))
	return if model and model:IsA("Model") then model else nil
end

local function getMultiplier(): number
	return TycoonConfig.GetCashMultiplierValue(TycoonController.GetCashMultiplierLevel())
end

-- The Core's outer ball (where it is right now, mid-bob).
local function getCore(model: Model): BasePart?
	local core = model:FindFirstChild("Core")
	local outer = core and core:FindFirstChild("Outer")
	return if outer and outer:IsA("BasePart") then outer else nil
end

--[[ Purchases ---------------------------------------------------------------- ]]

local function onPromptTriggered(prompt: ProximityPrompt, triggeringPlayer: Player)
	if triggeringPlayer ~= localPlayer or prompt.Name ~= GeneratorKit.PROMPT_NAME then
		return
	end
	local plot = getPlot()
	local id = prompt:GetAttribute(GeneratorKit.ID_ATTRIBUTE)
	if not plot or not prompt:IsDescendantOf(plot) or typeof(id) ~= "string" then
		return
	end
	local generator = TycoonConfig.GetGeneratorById(id)
	if not generator then
		return
	end
	local level = TycoonController.GetGeneratorLevel(id)
	if level >= generator.MaxLevel or not TycoonConfig.IsUnlocked(generator, TycoonController.GetGeneratorLevels()) then
		return
	end
	local cost = TycoonConfig.GetUpgradeCost(generator, level)
	if TycoonController.GetCash() < cost then
		ToastController.Show(("Need %s"):format(NumberFormat.Money(cost)), "Error")
		return
	end
	TycoonController.RequestUpgrade(id)
end

local function bump(body: BasePart)
	local baseSize = body.Size
	local info = TweenInfo.new(BUMP_SECONDS / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
	local tween = TweenService:Create(body, info, { Size = baseSize * BUMP_SCALE })
	tween.Completed:Connect(function()
		body.Size = baseSize
	end)
	tween:Play()
end

local function burst(core: BasePart, color: Color3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "UpgradeBurst"
	attachment.WorldPosition = core.Position
	attachment.Parent = Workspace.Terrain
	local emitter = SparkleEmitter.Create({ Color = color })
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(BURST_COUNT)
	Debris:AddItem(attachment, 3)
end

local function onUpgradeResolved(result: any)
	if typeof(result) ~= "table" or result.Success ~= true or typeof(result.GeneratorId) ~= "string" then
		return
	end
	local generator = TycoonConfig.GetGeneratorById(result.GeneratorId)
	if not generator then
		return
	end
	-- Each level adds the same amount: one level's worth of base output.
	local gain = TycoonConfig.GetGeneratorCashPerSecond(generator, 1) * getMultiplier()
	ToastController.Show(("+%s/s"):format(NumberFormat.Money(gain)), "Neutral")

	local model = getModel(generator.Id)
	local body = model and model:FindFirstChild("Body")
	if model and body and body:IsA("BasePart") then
		bump(body)
		local core = getCore(model)
		if core then
			burst(core, GeneratorKit.GetTierColor(generator.Tier))
		end
	end
end

--[[ Income pops ---------------------------------------------------------------- ]]

-- One pop per owned generator per tick; a pop lives 0.8 s, under the 1 s
-- tick, so they never stack.
local function popIncome()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local multiplier = getMultiplier()
	for _, generator in TycoonConfig.Generators do
		local level = TycoonController.GetGeneratorLevel(generator.Id)
		local model = level > 0 and getModel(generator.Id)
		local core = model and getCore(model)
		if core and (core.Position - camera.CFrame.Position).Magnitude <= PlotLayout.Generator.PopRadius then
			local rate = TycoonConfig.GetGeneratorCashPerSecond(generator, level) * multiplier
			local top = core.Position + Vector3.new(0, core.Size.Y / 2 + POP_ABOVE_CORE, 0)
			HudController.FloatPop(top, "+" .. NumberFormat.Money(rate), UITheme.GetTierLight(generator.Tier))
		end
	end
end

function GeneratorController.Init()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	TycoonController.UpgradeResolved:Connect(onUpgradeResolved)
	task.spawn(function()
		while true do
			task.wait(TycoonConfig.PassiveIncomeIntervalSeconds)
			popIncome()
		end
	end)
end

return GeneratorController
