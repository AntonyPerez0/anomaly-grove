--!strict
-- Fuse Machine rules (M9-05), shared by the server (FuseService) and the client
-- (Fuse modal): which rarity comes next, the success chance, and which rarity
-- groups a player can fuse right now.

local Config = require(script.Parent.Config)
local Perks = require(script.Parent.Perks)

local Fuse = {}

-- The rarity one tier above (nil at the top).
function Fuse.nextRarity(rarity: string): string?
	local info = (Config.Rarities :: any)[rarity]
	if not info then
		return nil
	end
	for name, other in Config.Rarities :: any do
		if other.tier == info.tier + 1 then
			return name
		end
	end
	return nil
end

function Fuse.chance(rarity: string): number
	local info = (Config.Rarities :: any)[rarity]
	return if info then Config.Fuse.ChanceByTier[info.tier] or 0 else 0
end

export type Group = {
	rarity: string,
	count: number,
	result: string?,
	chance: number,
	locked: boolean, -- the result rarity needs a higher rebirth tier / Cultivation
}

-- Rarity groups among `cores` (slot -> { rarity }), lowest tier first.
function Fuse.groups(cores: { [number]: { rarity: string } }, rebirths: number, cultivation: number): { Group }
	local counts: { [string]: number } = {}
	for _, core in cores do
		counts[core.rarity] = (counts[core.rarity] or 0) + 1
	end
	local out: { Group } = {}
	for rarity, count in counts do
		local result = Fuse.nextRarity(rarity)
		table.insert(out, {
			rarity = rarity,
			count = count,
			result = result,
			chance = Fuse.chance(rarity),
			locked = result == nil or not Perks.rarityUnlocked(result, rebirths, cultivation),
		})
	end
	table.sort(out, function(a, b)
		return (Config.Rarities :: any)[a.rarity].tier < (Config.Rarities :: any)[b.rarity].tier
	end)
	return out
end

-- The fee for one fuse (before the Commerce discount).
function Fuse.fee(rebirths: number, income: number): number
	return Perks.scaledReward(Config.Fuse.MinFee, rebirths, income, Config.Fuse.FeeSeconds)
end

return Fuse
