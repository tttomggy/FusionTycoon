--!strict
-- Short, readable money/number formatting shared by every label in the game
-- (pads, HUD, banners). "$1.25M" instead of "$1250000". Also safe for
-- non-integer values: string.format("%d", 1.5) throws in Luau, which matters
-- now that multipliers like x1.5 exist.
local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function NumberFormat.Short(value: number): string
	if value ~= value then
		return "0"
	end
	local negative = value < 0
	local n = math.abs(value)
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end

	local text
	if index == 1 then
		-- Below 1K: whole numbers, or one decimal for small fractional values.
		if n == math.floor(n) or n >= 100 then
			text = tostring(math.floor(n))
		else
			text = ("%.1f"):format(n):gsub("%.0$", "")
		end
	elseif n >= 100 then
		text = ("%d"):format(math.floor(n)) .. SUFFIXES[index]
	elseif n >= 10 then
		text = (("%.1f"):format(math.floor(n * 10) / 10):gsub("%.0$", "")) .. SUFFIXES[index]
	else
		text = (("%.2f"):format(math.floor(n * 100) / 100):gsub("0$", ""):gsub("%.0?$", "")) .. SUFFIXES[index]
	end

	return (if negative then "-" else "") .. text
end

function NumberFormat.Money(value: number): string
	return "$" .. NumberFormat.Short(value)
end

-- "x1.5", "x2", "x12.5"
function NumberFormat.Multiplier(value: number): string
	if value == math.floor(value) then
		return ("x%d"):format(value)
	end
	return (("x%.2f"):format(value):gsub("0+$", ""))
end

return NumberFormat
