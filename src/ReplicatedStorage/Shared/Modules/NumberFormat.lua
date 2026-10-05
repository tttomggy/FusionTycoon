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
	local sign = if negative then "-" else ""
	local n = math.abs(value)
	if n == math.huge then
		return sign .. "∞"
	end
	local index = 1
	if n >= 1000 then
		-- The suffix from log10, not by dividing by 1000 repeatedly: eleven
		-- divisions drift (1e33 came out "999No" instead of "1Dc").
		local thousands = math.min(math.floor(math.log10(n) / 3 + 1e-9), #SUFFIXES - 1)
		n /= 1000 ^ thousands
		index = thousands + 1
	end
	if n >= 1000 then
		-- Past the last suffix (1e36+): "1.23e45". "%d" there threw ("no
		-- integer representation") and took the label's whole UI with it.
		local exponent = math.floor(math.log10(math.abs(value)))
		local mantissa = math.abs(value) / 10 ^ exponent
		if mantissa >= 9.995 then
			mantissa, exponent = 1, exponent + 1
		end
		return sign .. ("%.2fe%d"):format(mantissa, exponent)
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

-- "x1.5", "x2", "x12.5" (huge ones: "x1.2M"; never "%d" past 1e15, which
-- throws for numbers with no integer representation).
function NumberFormat.Multiplier(value: number): string
	if value ~= value or math.abs(value) >= 1e6 then
		return "x" .. NumberFormat.Short(value)
	end
	if value == math.floor(value) then
		return ("x%d"):format(value)
	end
	return (("x%.2f"):format(value):gsub("0+$", ""))
end

return NumberFormat
