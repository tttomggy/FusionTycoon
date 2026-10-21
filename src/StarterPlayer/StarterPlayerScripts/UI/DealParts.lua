--!strict
--[[
	DealParts
	---------
	What a bundle contains, in pictures and plain words (Polish 10): used by
	the shop's Deal banner and the Starter Pack / "New deal!" side cards.

	  Distinct(parts)           the bundle's parts with repeat counts, in order
	                            ({ SafeFusion1 x3, LuckPotion } = two entries)
	  BuildTiles(parent, parts) one tile per DISTINCT part: the part product's
	                            live icon (ShopPrices; the emoji until it
	                            loads), its duration or amount on the tile
	                            (ShopConfig `Tile`), its name under it and a
	                            "x3" badge when the same part appears more than
	                            once. Tiles are named "PartTile_<Key>".
	  BuildYouGet(parent, parts) "YOU GET:" and one check line per distinct
	                            part, from its ShopConfig `Plain`. Lines are
	                            named "YouGet_<Key>".

	  PlainLine(key)            a part's YOU GET text. The shop's text (Plain),
	                            unless ShopController installs a resolver
	                            (SetPlainResolver): a cash part says what it
	                            pays THIS player right now, "A pile of cash
	                            (+$1.2M)".

	No price is typed here: the "Worth ... if bought separately" line comes
	from ShopController.GetWorthLine (live ShopPrices).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ShopPrices = require(ReplicatedStorage.Shared.Modules.ShopPrices)
local UITheme = require(ReplicatedStorage.Shared.Modules.UITheme)
local UIKit = require(script.Parent.UIKit)

local DealParts = {}

local Colors = UITheme.Colors
local Fonts = UITheme.Fonts

DealParts.TILE_SIZE = 72
local TILE_GAP = 8
local NAME_HEIGHT = 30
local ICON_FRACTION = 0.62 -- of the tile

export type Part = { Key: string, Count: number }

local plainResolver: ((key: string) -> string?)? = nil

-- ShopController installs the live resolver (it knows the player's income).
function DealParts.SetPlainResolver(resolver: (key: string) -> string?)
	plainResolver = resolver
end

-- One part's YOU GET text (plain words).
function DealParts.PlainLine(key: string): string
	local resolver = plainResolver
	local line = if resolver then resolver(key) else nil
	return line or (ShopConfig.GetItem(key) :: ShopConfig.Item).Plain
end

-- The distinct parts in first-seen order with how many times each appears.
function DealParts.Distinct(parts: { string }): { Part }
	local list: { Part } = {}
	local byKey: { [string]: Part } = {}
	for _, key in parts do
		local existing = byKey[key]
		if existing then
			existing.Count += 1
		elseif ShopConfig.GetItem(key) then
			local part = { Key = key, Count = 1 }
			byKey[key] = part
			table.insert(list, part)
		end
	end
	return list
end

-- Width of a tile (its name gets a little more room than the square).
function DealParts.TileWidth(tileSize: number?): number
	return (tileSize or DealParts.TILE_SIZE) + TILE_GAP
end

function DealParts.TileHeight(tileSize: number?): number
	return (tileSize or DealParts.TILE_SIZE) + 4 + NAME_HEIGHT
end

local function buildTile(parent: Instance, part: Part, tileSize: number, z: number, order: number): Frame
	local item = ShopConfig.GetItem(part.Key) :: ShopConfig.Item
	local holder = Instance.new("Frame")
	holder.Name = "PartTile_" .. part.Key
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.Size = UDim2.fromOffset(DealParts.TileWidth(tileSize), DealParts.TileHeight(tileSize))
	holder.ZIndex = z
	holder.Parent = parent

	local box = Instance.new("Frame")
	box.Name = "Box"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 0)
	box.Size = UDim2.fromOffset(tileSize, tileSize)
	box.BackgroundColor3 = Colors.White
	box.BorderSizePixel = 0
	box.ZIndex = z
	box.Parent = holder
	UIKit.Corner(box, 14)
	UIKit.Stroke(box, 2, Colors.White)
	UIKit.Gradient(box, { { 0, Colors.PanelTop }, { 1, Colors.Panel2 } })
	UIKit.Shadow(box, UITheme.SmallShadowOffset)

	-- The live store icon, else the emoji.
	local iconSize = math.floor(tileSize * ICON_FRACTION)
	local image = ShopPrices.GetIcon(part.Key)
	if image then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Icon"
		picture.BackgroundTransparency = 1
		picture.AnchorPoint = Vector2.new(0.5, 0)
		picture.Position = UDim2.new(0.5, 0, 0, 4)
		picture.Size = UDim2.fromOffset(iconSize, iconSize)
		picture.Image = image
		picture.ScaleType = Enum.ScaleType.Fit
		picture.ZIndex = z + 1
		picture.Parent = box
	else
		UIKit.Label({
			Name = "Icon",
			Text = item.Icon,
			TextSize = math.floor(iconSize * 0.8),
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(iconSize, iconSize),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = z + 1,
			Parent = box,
		})
	end
	-- Its duration or amount, on the tile.
	local amount = UIKit.Label({
		Name = "Amount",
		Text = item.Tile or "",
		Font = Fonts.Display,
		TextSize = 13,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -4, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = z + 2,
		Stroke = 1.5,
		Parent = box,
	})
	UIKit.FitText(amount, 13, 8) -- "20 min cash" in a narrow tile shrinks, never clips
	if part.Count > 1 then
		local badge = UIKit.Badge(box, part.Count)
		badge.Text = "×" .. part.Count
		badge.ZIndex = z + 3
	end
	-- Its name, under the tile.
	UIKit.Label({
		Name = "Name",
		Text = item.Name,
		Font = Fonts.BodyHeavy,
		TextSize = 13,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, tileSize + 6),
		Size = UDim2.new(1, 0, 0, NAME_HEIGHT - 2),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = z + 1,
		Stroke = 1,
		Parent = holder,
	})
	return holder
end

-- A row of tiles, one per distinct part. Returns the row (AutomaticSize XY).
function DealParts.BuildTiles(parent: Instance, parts: { string }, z: number, tileSize: number?): Frame
	local size = tileSize or DealParts.TILE_SIZE
	local row = Instance.new("Frame")
	row.Name = "PartTiles"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Size = UDim2.new()
	row.ZIndex = z
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	for order, part in DealParts.Distinct(parts) do
		buildTile(row, part, size, z, order)
	end
	return row
end

local function lineText(part: Part): string
	return ("%s %s%s"):format(
		UIKit.Colored("✓", Colors.Cash),
		UIKit.EscapeRichText(DealParts.PlainLine(part.Key)),
		if part.Count > 1 then UIKit.Colored(("  ×%d"):format(part.Count), Colors.GoldLabel) else ""
	)
end

-- Re-reads every line's text (a cash part's amount follows your income).
function DealParts.UpdateYouGet(list: Frame, parts: { string })
	for _, part in DealParts.Distinct(parts) do
		local label = list:FindFirstChild("YouGet_" .. part.Key)
		if label and label:IsA("TextLabel") then
			local text = lineText(part)
			if label.Text ~= text then
				label.Text = text
			end
		end
	end
end

-- "YOU GET:" and a check line per distinct part. Returns the list
-- (AutomaticSize Y, `width` wide).
function DealParts.BuildYouGet(parent: Instance, parts: { string }, z: number, width: UDim, textSize: number?): Frame
	local size = textSize or 16
	local list = Instance.new("Frame")
	list.Name = "YouGet"
	list.BackgroundTransparency = 1
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.Size = UDim2.new(width, UDim.new(0, 0))
	list.ZIndex = z
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	UIKit.Label({
		Name = "Header",
		Text = "YOU GET:",
		Font = Fonts.Display,
		TextSize = size,
		TextColor3 = Colors.GoldLabel,
		Size = UDim2.new(1, 0, 0, size + 4),
		LayoutOrder = 0,
		ZIndex = z,
		Stroke = 1.5,
		Parent = list,
	})
	for order, part in DealParts.Distinct(parts) do
		UIKit.Label({
			Name = "YouGet_" .. part.Key,
			Text = lineText(part),
			RichText = true,
			Font = Fonts.BodyHeavy,
			TextSize = size,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, size + 2),
			LayoutOrder = order,
			ZIndex = z,
			Stroke = 1.5,
			Parent = list,
		})
	end
	return list
end

-- Part glyphs for the HUD tile's bottom strip: "⚡ 🧪" (distinct parts).
function DealParts.Glyphs(parts: { string }): string
	local glyphs: { string } = {}
	for _, part in DealParts.Distinct(parts) do
		table.insert(glyphs, (ShopConfig.GetItem(part.Key) :: ShopConfig.Item).Icon)
	end
	return table.concat(glyphs, " ")
end

return DealParts
