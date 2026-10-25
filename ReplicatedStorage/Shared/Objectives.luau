--!strict
-- Objective chain (M6-01): what should this player do next? Pure function of a
-- snapshot of replicated attributes, so the client can draw a pill + guide beam
-- and ObjectiveSpec can test every branch without a player.

local Config = require(script.Parent.Config)
local Progression = require(script.Parent.Progression)

local Objectives = {}

export type Snapshot = {
	hasPlot: boolean,
	seeds: number,
	carryingCore: boolean,
	summary: string, -- PedestalSummary attribute ("1=Sprout|2=seed|3=empty")
	pedestalSlots: number,
	cash: number,
	coresStolen: number,
	netWorth: number,
	night: boolean,
	rivalCores: boolean?, -- any stealable core on another plot right now (nil = unknown -> assume yes)
	-- M8-11 (all optional; absent = pre-M8 behaviour):
	maxPedestals: number?, -- Perks.maxPedestals
	nextPedestalPrice: number?, -- discounted
	rebirthCost: number?, -- current requirement
	incomeRate: number?, -- $/s, for "ready in ..."
	bestUpgrade: { slot: number, level: number, price: number }?,
	-- Early-game variety (nil = unknown -> goal skipped):
	defenseCount: number?,
	hasGadget: boolean?,
	cultivationLevel: number?,
}

export type Target = "claim" | "seed" | "ownPedestal" | "rivalCore" | "home"

export type Objective = {
	id: string,
	text: string,
	target: Target?,
	progress: number?, -- 0..1 for "save up" goals
}

-- Counts pedestal states from the summary string.
function Objectives.parseSummary(summary: string): (number, number, number)
	local cores, seeds, empty = 0, 0, 0
	for entry in string.gmatch(summary, "[^|]+") do
		local info = string.match(entry, "%d+=(.+)")
		if info then
			if string.sub(info, 1, 5) == "empty" then
				empty += 1
			elseif string.sub(info, 1, 4) == "seed" then
				seeds += 1
			else
				cores += 1
			end
		end
	end
	return cores, seeds, empty
end

local function money(n: number): string
	return `${Progression.format(n)}`
end

-- "ready!" or "in 38s" / "in 4m" / "in 2h" at the current income.
function Objectives.eta(price: number, cash: number, income: number?): string
	if cash >= price then
		return "ready!"
	end
	if not income or income <= 0 then
		return "save up"
	end
	local seconds = (price - cash) / income
	if seconds < 90 then
		return `in {math.ceil(seconds)}s`
	elseif seconds < 5400 then
		return `in {math.ceil(seconds / 60)}m`
	end
	return `in {math.ceil(seconds / 3600)}h`
end

function Objectives.next(s: Snapshot): Objective
	if s.carryingCore then
		return { id = "secure", text = "Run it home - cross your gate!", target = "home" }
	end
	if not s.hasPlot then
		return { id = "claim", text = "Walk into a FREE plot to claim it", target = "claim" }
	end
	local cores, incubating, empty = Objectives.parseSummary(s.summary)
	if s.seeds > 0 then
		if empty > 0 then
			return { id = "plant", text = "Plant your seed on a pedestal", target = "ownPedestal" }
		end
		return { id = "feed", text = "Feed the seed to a core (+10% income)", target = "ownPedestal" }
	end
	if cores == 0 and incubating == 0 then
		return { id = "harvest", text = "Harvest a glowing seed in the forest", target = "seed" }
	end
	if cores == 0 then
		return { id = "hatch", text = "Your seed is hatching... grab another!", target = "seed" }
	end
	if s.night then
		return { id = "night", text = "Night! Monsters roam - stay near your base" }
	end
	local nextSlot = s.pedestalSlots + 1
	if s.pedestalSlots < 2 then
		local price = Config.Prices.Pedestals[1]
		return {
			id = "pedestal2",
			text = `Save {money(price)} for Pedestal 2 (SHOP)`,
			progress = math.clamp(s.cash / price, 0, 1),
		}
	end
	-- Raid goal only when there is something to raid (a solo server would stall here).
	if s.coresStolen == 0 and s.rivalCores ~= false then
		return { id = "raid", text = "Raid a rival base & steal a core!", target = "rivalCore" }
	end
	if empty > 0 then
		return { id = "fill", text = "Fill your empty pedestals with seeds", target = "seed" }
	end
	local need = s.rebirthCost or Config.Rebirth.NetWorthRequired
	-- M8-11: once rebirth is affordable it is the headline goal.
	if s.rebirthCost and s.netWorth >= need then
		return { id = "rebirth", text = "REBIRTH is ready - open the SHOP!" }
	end
	local pedestalPrice: number? = nil
	if nextSlot <= (s.maxPedestals or Config.Plot.PedestalSlots) then
		pedestalPrice = s.nextPedestalPrice or Config.Prices.Pedestals[nextSlot - 1]
	end
	local function save(id: string, text: string, price: number): Objective
		return {
			id = id,
			text = `{text} ({money(price)}, {Objectives.eta(price, s.cash, s.incomeRate)})`,
			progress = math.clamp(s.cash / price, 0, 1),
		}
	end
	-- Opening milestones in a fixed, varied order (M8 feedback: the start was all
	-- pedestal upgrades): pedestal 3, a defense, pedestal 5, a gadget, then more.
	if pedestalPrice and s.pedestalSlots < 3 then
		return save("pedestalN", `Buy Pedestal {nextSlot} in the SHOP`, pedestalPrice)
	end
	if s.defenseCount == 0 then
		return save("defense", "Guard your cores: buy a Trap Tile (SHOP > Defense)", Config.Prices.TrapTile)
	end
	if pedestalPrice and s.pedestalSlots < 5 then
		return save("pedestalN", `Buy Pedestal {nextSlot} in the SHOP`, pedestalPrice)
	end
	if s.hasGadget == false then
		return save("gadget", "Get Dash Boots for faster raids (SHOP > Gadgets)", Config.Prices.DashBoots)
	end
	-- Then the cheapest of a new pedestal / pedestal upgrades (one UPGRADE ALL tap).
	local upgrade = s.bestUpgrade
	if upgrade and (pedestalPrice == nil or upgrade.price < pedestalPrice) then
		return save("upgrade", "Tap UPGRADE ALL in the SHOP", upgrade.price)
	end
	if pedestalPrice then
		return save("pedestalN", `Buy Pedestal {nextSlot} in the SHOP`, pedestalPrice)
	end
	local cultivation = s.cultivationLevel
	local unlockAt = Config.PedestalUpgrade.UnlockCultivation
	if cultivation and cultivation < unlockAt then
		return {
			id = "cultivate",
			text = `Plant & hatch cores: Cultivation {cultivation}/{unlockAt} unlocks upgrades`,
			progress = math.clamp(cultivation / unlockAt, 0, 1),
		}
	end
	if s.netWorth < need then
		return {
			id = "rebirthGoal",
			text = `Reach {money(need)} net worth to Rebirth`,
			progress = math.clamp(s.netWorth / need, 0, 1),
		}
	end
	return { id = "rebirth", text = "REBIRTH is ready - open the SHOP!" }
end

return Objectives
