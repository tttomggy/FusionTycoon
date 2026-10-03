--!strict
--[[
	LockKit
	-------
	Builds the heist LOCK console (built once per plot on claim; TycoonService
	adds its prompt and label, HeistService answers the prompt):

	  Post        a SmoothPlastic column, Structure colour.
	  Top         a slab on the post, tilted toward the gate (+Z).
	  ButtonFace  a round pink button on the top: a SurfaceGui disc
	              (BillboardKit.BuildButtonFace), never a flat Neon disc.
	              Clients recolour its "Disc" from the plot's shield
	              attributes (HeistController).

	Every number comes from PlotLayout.LockConsole; the position from
	PlotLayout.LOCK_CONSOLE.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.Config.PlotLayout)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local PartKit = require(ReplicatedStorage.Shared.Modules.PartKit)
local BillboardKit = require(ReplicatedStorage.Shared.Modules.BillboardKit)

local LockKit = {}

LockKit.MODEL_NAME = "LockConsole"
LockKit.PROMPT_NAME = "LockPrompt"

-- Builds the console in `parent` and returns (model, post). The post holds
-- the prompt and the label.
function LockKit.Build(origin: CFrame, parent: Instance): (Model, BasePart)
	local L = PlotLayout.LockConsole
	local model = Instance.new("Model")
	model.Name = LockKit.MODEL_NAME

	local post = PartKit.Part({
		Name = "Post",
		Size = L.PostSize,
		CFrame = PartKit.At(origin, PlotLayout.LOCK_CONSOLE, L.PostSize.Y / 2),
		Color = UITheme.World.Structure,
		Parent = model,
	})
	-- Tilted so its top face leans toward the gate (+Z), where you walk in.
	local topCFrame = post.CFrame
		* CFrame.new(0, L.PostSize.Y / 2 + L.TopSize.Y / 2, 0)
		* CFrame.Angles(math.rad(L.TopTiltDegrees), 0, 0)
	local top = PartKit.Part({
		Name = "Top",
		Size = L.TopSize,
		CFrame = topCFrame,
		Color = UITheme.World.StructureLight,
		Parent = model,
	})
	BillboardKit.BuildButtonFace(
		model,
		top.CFrame * CFrame.new(0, L.TopSize.Y / 2, 0),
		L.ButtonDiameter,
		UITheme.World.Shield,
		L.ButtonGap
	)

	model.PrimaryPart = post
	model.Parent = parent
	return model, post
end

return LockKit
