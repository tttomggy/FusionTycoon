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

	The income itself is pictured by FactoryController's cash balls.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TycoonConfig = require(ReplicatedStorage.Shared.Config.TycoonConfig)
local PlotNaming = require(ReplicatedStorage.Shared.Config.PlotNaming)
local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local NumberFormat = require(ReplicatedStorage.Shared.Modules.NumberFormat)
local GeneratorKit = require(ReplicatedStorage.Shared.Modules.GeneratorKit)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local SparkleEmitter = require(ReplicatedStorage.Shared.VFX.SparkleEmitter)
local TycoonController = require(script.Parent.TycoonController)
local ToastController = require(script.Parent.ToastController)

local GeneratorController = {}

local BUMP_SCALE = 1.08
local BUMP_SECONDS = 0.25
local BURST_COUNT = 30
local SIZE_CHECK_DELAY = 1
local SIZE_TOLERANCE = 0.01

local warnedSizes: { [string]: boolean } = {}

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

-- Studio only: 1 s after a bump, the Body must be back at its PlotLayout
-- size (and the Core orb at its built size) within SIZE_TOLERANCE. Warns
-- once per generator, so a regression of the compounding-size bug shows up.
local function checkSize(id: string, model: Model)
	if warnedSizes[id] then
		return
	end
	local spot = PlotLayout.GENERATORS[id]
	local body = model:FindFirstChild("Body")
	if not spot or not body or not body:IsA("BasePart") then
		return
	end
	local expected = Vector3.new(spot.Footprint, spot.Height, spot.Footprint)
	local core = getCore(model)
	local coreExpected = spot.Footprint * PlotLayout.Generator.CoreScale
	local function off(actual: number, wanted: number): boolean
		return math.abs(actual - wanted) > wanted * SIZE_TOLERANCE
	end
	if
		off(body.Size.X, expected.X)
		or off(body.Size.Y, expected.Y)
		or off(body.Size.Z, expected.Z)
		or (core ~= nil and off(core.Size.X, coreExpected))
	then
		warnedSizes[id] = true
		warn(
			("GeneratorController: Generator_%s has drifted from its PlotLayout size (body %s, core %s)"):format(
				id,
				tostring(body.Size),
				if core then tostring(core.Size) else "-"
			)
		)
	end
end

-- The upgrade bump: always against the Body's stored base size (PartKit),
-- so rapid upgrades can't compound it.
local function bump(id: string, model: Model, body: BasePart)
	PartKit.Pulse(body, BUMP_SCALE, BUMP_SECONDS)
	if RunService:IsStudio() then
		task.delay(SIZE_CHECK_DELAY, checkSize, id, model)
	end
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
		bump(generator.Id, model, body)
		local core = getCore(model)
		if core then
			burst(core, GeneratorKit.GetTierColor(generator.Tier))
		end
	end
end

function GeneratorController.Init()
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)
	TycoonController.UpgradeResolved:Connect(onUpgradeResolved)
end

return GeneratorController
