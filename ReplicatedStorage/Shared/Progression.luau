--!strict
-- Progression math (M8-01), shared by server and client. Pure: no services, no state.
--  * The RuneScape experience table (levels 1-99, 13,034,431 XP at 99).
--  * Short number formatting that scales to absurd late-game values (K .. Dc).
--  * Exponential cost / income curves used by every upgrade track.

local Progression = {}

Progression.MAX_LEVEL = 99

-- XP_FOR[L] = total XP needed to BE level L (XP_FOR[1] = 0). Classic formula:
-- sum over n = 1..L-1 of floor(n + 300 * 2^(n / 7)), divided by 4, floored.
local XP_FOR: { number } = { 0 }
do
	local points = 0
	for n = 1, Progression.MAX_LEVEL - 1 do
		points += math.floor(n + 300 * 2 ^ (n / 7))
		XP_FOR[n + 1] = math.floor(points / 4)
	end
end

function Progression.xpForLevel(level: number): number
	return XP_FOR[math.clamp(math.floor(level), 1, Progression.MAX_LEVEL)]
end

-- Highest level whose XP requirement `xp` meets (binary search over the table).
function Progression.levelForXp(xp: number): number
	local lo, hi = 1, Progression.MAX_LEVEL
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if XP_FOR[mid] <= xp then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- Level plus progress inside it: (level, xpIntoLevel, xpSpanOfLevel). At 99 the
-- span is 0 (maxed; XP keeps counting for bragging rights).
function Progression.progress(xp: number): (number, number, number)
	local level = Progression.levelForXp(xp)
	if level >= Progression.MAX_LEVEL then
		return level, xp - XP_FOR[level], 0
	end
	return level, xp - XP_FOR[level], XP_FOR[level + 1] - XP_FOR[level]
end

-- Short number formatting: 950, 9,950, 12.3K, 4.56M ... 1.2Dc. Rounds down so a
-- price never looks cheaper than it is... and cash never looks bigger.
local SUFFIXES = {
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
}

function Progression.format(n: number): string
	local sign = if n < 0 then "-" else ""
	local abs = math.abs(n)
	if abs < 10000 then
		local whole = tostring(math.floor(abs))
		local withCommas = whole:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if withCommas:sub(1, 1) == "," then
			withCommas = withCommas:sub(2)
		end
		return sign .. withCommas
	end
	if abs ~= abs or abs == math.huge then
		return sign .. "inf"
	end
	if abs >= 1e66 then
		return sign .. string.format("%.2e", abs) -- past Vigintillion: scientific
	end
	local tier = math.min(math.floor(math.log10(abs) / 3), #SUFFIXES)
	local scaled = abs / 10 ^ (tier * 3)
	-- 3 significant digits: 12.3K, 123K, 1.23M
	local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
	local factor = 10 ^ decimals
	local shown = math.floor(scaled * factor + 1e-6) / factor -- epsilon: 4.56 * 100 = 455.999...
	return sign .. string.format(`%.{decimals}f`, shown) .. SUFFIXES[tier]
end

-- Exponential price of level `level` -> level + 1 on a track: base * growth^(level - 1).
function Progression.cost(base: number, growth: number, level: number): number
	return math.floor(base * growth ^ (level - 1))
end

-- Compounding multiplier after `steps` steps of `perStep` (e.g. 1.07^(level - 1)).
function Progression.compound(perStep: number, steps: number): number
	return perStep ^ math.max(steps, 0)
end

-- Total XP still needed for `targetLevel` from `xp`.
function Progression.xpToLevel(xp: number, targetLevel: number): number
	return math.max(0, Progression.xpForLevel(targetLevel) - xp)
end

return Progression
