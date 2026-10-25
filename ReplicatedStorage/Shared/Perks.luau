--!strict
-- Perks + prices (M8). Pure and shared: the server applies these numbers, the
-- client uses the same functions to display them, so they can never disagree.
-- Every bonus in the game is a "stat" summed from three sources:
--   skills (level tracks + one-off unlocks), the Rebirth Tree, and the Index.

local Config = require(script.Parent.Config)
local Progression = require(script.Parent.Progression)

local Perks = {}

export type Stats = { [string]: number }
export type Input = {
	skills: { [string]: number }?, -- XP per skill
	tree: { [string]: number }?, -- node levels
	upgrades: { [string]: number }?, -- defense/gadget upgrade levels
	indexEntries: number?,
	companion: string?, -- M9-07 equipped companion id
}

type Track = { stat: string, per: number, every: number, text: string }
type Unlock = { level: number, stat: string?, value: number?, text: string }
type TreeNode = { id: string, branch: string, name: string, stat: string, per: number, costs: { number } }
type UpgradeDef = {
	id: string,
	name: string,
	tab: string,
	stat: string,
	per: number,
	max: number,
	base: number,
	growth: number,
}
type CrateDef = {
	id: string,
	name: string,
	price: number,
	incomeSeconds: number,
	cultivation: number,
	color: Color3,
	odds: { [string]: number },
}

local TRACKS: { [string]: { Track } } = Config.Skills.Tracks :: any
local UNLOCKS: { [string]: { Unlock } } = Config.Skills.Unlocks :: any
local TREE: { TreeNode } = Config.RebirthTree :: any
local UPGRADES: { UpgradeDef } = Config.Upgrades :: any
local CRATES: { CrateDef } = Config.Crates :: any

function Perks.skillLevel(skills: { [string]: number }?, skill: string): number
	return Progression.levelForXp(if skills then skills[skill] or 0 else 0)
end

function Perks.totalLevel(skills: { [string]: number }?): number
	local total = 0
	for _, skill in Config.Skills.Order do
		total += Perks.skillLevel(skills, skill)
	end
	return total
end

local function add(stats: Stats, stat: string, value: number)
	stats[stat] = (stats[stat] or 0) + value
end

-- Stats from one skill at `level`.
function Perks.skillStats(skill: string, level: number, into: Stats?): Stats
	local stats = into or {}
	for _, track in (TRACKS[skill] or {}) :: { Track } do
		add(stats, track.stat, math.floor(level / track.every) * track.per)
	end
	for _, unlock in (UNLOCKS[skill] or {}) :: { Unlock } do
		if level >= unlock.level and unlock.stat and unlock.value then
			add(stats, unlock.stat, unlock.value)
		end
	end
	return stats
end

function Perks.compute(input: Input): Stats
	local stats: Stats = {}
	for _, skill in Config.Skills.Order do
		Perks.skillStats(skill, Perks.skillLevel(input.skills, skill), stats)
	end
	local tree = input.tree or {}
	for _, node in TREE do
		local level = tree[node.id] or 0
		if level > 0 then
			add(stats, node.stat, node.per * level)
		end
	end
	local upgrades = input.upgrades or {}
	for _, def in UPGRADES do
		local level = upgrades[def.id] or 0
		if level > 0 then
			add(stats, def.stat, def.per * level)
		end
	end
	add(stats, "income", (input.indexEntries or 0) * Config.IndexIncomePerEntry)
	local companion = if input.companion then Perks.companion(input.companion) else nil
	if companion and Perks.companionUnlocked(companion, input.skills) then
		for stat, value in companion.stats do
			add(stats, stat, value)
		end
	end
	return stats
end

export type CompanionDef = typeof(Config.Companions[1])

-- M9-07 companion lookup + unlock rule (a skill level).
function Perks.companion(id: string): CompanionDef?
	for _, def in Config.Companions do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Perks.companionUnlocked(def: CompanionDef, skills: { [string]: number }?): boolean
	return Perks.skillLevel(skills, def.skill) >= def.level
end

-- Player-facing names for stats (UI text).
local STAT_NAMES: { [string]: string } = {
	hatchSpeed = "hatch speed",
	rarityLuck = "rarity luck",
	mutationChance = "mutation chance",
	carrySpeed = "carry speed",
	ripSpeed = "rip speed",
	defenseSlots = "defense slot",
	maxHealth = "max health",
	pedestalSlots = "pedestal slot (9-12)",
	income = "income",
	startCash = "rebirth starting cash",
	offlineHours = "offline hour",
	xpBoost = "skill XP",
	questBonus = "quest rewards",
	turretDamage = "turret damage",
	laserDamage = "laser damage",
	trapRoot = "trap root time",
	dashCooldown = "dash cooldown cut",
	smokeCooldown = "smoke cooldown cut",
	grappleCooldown = "grapple cooldown cut",
}

function Perks.statName(stat: string): string
	return STAT_NAMES[stat] or stat
end

function Perks.get(stats: Stats, stat: string): number
	return stats[stat] or 0
end

-- What a level-up at exactly `level` gives (track steps + unlocks), as text lines.
function Perks.rewardsAt(skill: string, level: number): { string }
	local lines: { string } = {}
	for _, track in (TRACKS[skill] or {}) :: { Track } do
		if level % track.every == 0 then
			local total = math.floor(level / track.every) * track.per
			local shown = if track.per < 1
				then `+{string.format("%.1f", total * 100)}% {track.text}`
				else `+{total} {track.text}`
			table.insert(lines, shown)
		end
	end
	for _, unlock in (UNLOCKS[skill] or {}) :: { Unlock } do
		if unlock.level == level then
			table.insert(lines, unlock.text)
		end
	end
	return lines
end

-- The next level (above `level`) that gives anything, with its text.
function Perks.nextReward(skill: string, level: number): (number?, { string })
	for next = level + 1, Progression.MAX_LEVEL do
		local lines = Perks.rewardsAt(skill, next)
		if #lines > 0 then
			return next, lines
		end
	end
	return nil, {}
end

-- XP multiplier for an action in `skill` (better methods as you level + Scholar +
-- the per-skill pacing scale).
function Perks.xpMultiplier(level: number, stats: Stats, skill: string?): number
	local scale = if skill then (Config.Skills.XpScale :: { [string]: number })[skill] or 1 else 1
	return (1 + Config.Skills.LevelXpFactor * (level - 1)) * (1 + Perks.get(stats, "xpBoost")) * scale
end

-- Rebirth curve (M8-06).
function Perks.rebirthTier(rebirths: number): number
	return math.floor(rebirths / Config.Rebirth.TierEvery)
end

function Perks.rebirthMultiplier(rebirths: number): number
	return Progression.compound(Config.Rebirth.IncomeGrowth, rebirths)
end

function Perks.rebirthRequirement(rebirths: number): number
	return math.floor(Config.Rebirth.NetWorthRequired * Config.Rebirth.RequirementGrowth ^ rebirths)
end

function Perks.tokensForRebirth(newRebirthCount: number): number
	local bonus = if newRebirthCount % Config.Rebirth.BonusTokenEvery == 0 then 1 else 0
	return Config.Rebirth.TokensPerRebirth + bonus
end

-- Shop discount (Commerce), capped.
function Perks.discounted(price: number, stats: Stats): number
	return math.floor(price * (1 - math.min(Perks.get(stats, "discount"), Config.Skills.MaxDiscount)))
end

-- Pedestal levels (M8-04).
function Perks.pedestalCap(rebirths: number): number
	local cfg = Config.PedestalUpgrade
	return math.min(cfg.BaseCap + cfg.CapPerTier * Perks.rebirthTier(rebirths), cfg.MaxCap)
end

function Perks.pedestalIncomeMultiplier(level: number): number
	return Progression.compound(Config.PedestalUpgrade.IncomeGrowth, math.max(level, 1) - 1)
end

-- Price of upgrading pedestal `slot` from `level` to level + 1 (before discount).
-- Not scaled by rebirths (2026-10-18 review), so re-climbing after a rebirth is
-- fast; `_rebirths` is kept so callers need not change.
function Perks.pedestalUpgradeCost(slot: number, level: number, _rebirths: number?): number
	local cfg = Config.PedestalUpgrade
	return math.floor(
		Progression.cost(cfg.BaseCost, cfg.CostGrowth, level) * (1 + cfg.SlotCostStep * (slot - 1)) + 1e-6 -- float guard: 200 x 1.15 must not floor to 229
	)
end

-- Cash already sunk into a pedestal's levels (closed-form geometric sum, before
-- discounts). Counts toward net worth so upgrading never pushes rebirth away.
function Perks.levelInvestment(slot: number, level: number): number
	local cfg = Config.PedestalUpgrade
	local steps = math.max(level, 1) - 1
	if steps == 0 then
		return 0
	end
	local g = cfg.CostGrowth
	return math.floor(cfg.BaseCost * (1 + cfg.SlotCostStep * (slot - 1)) * (g ^ steps - 1) / (g - 1))
end

-- M9-01: income multiplier of a core size (nil / unknown = Normal).
function Perks.sizeMultiplier(size: string?): number
	local def = if size then Config.Sizes.Defs[size] else nil
	return if def then def.mult else 1
end

-- M9-01: roll a size. Returns nil for Normal (saves space in the profile).
function Perks.rollSize(rng: Random): string?
	local roll = rng:NextNumber()
	local cumulative = 0
	for _, name in Config.Sizes.Order do
		cumulative += Config.Sizes.Defs[name].chance
		if roll < cumulative then
			return if name == "Normal" then nil else name
		end
	end
	return nil
end

-- Income gained per dollar by the next level on a core (0 for empty pedestals).
-- UPGRADE ALL and the GOAL pill pick the highest value, not the cheapest level.
function Perks.upgradeValue(rarity: string?, mutation: string?, slot: number, level: number, size: string?): number
	if rarity == nil then
		return 0
	end
	local info = (Config.Rarities :: any)[rarity]
	if not info then
		return 0
	end
	local mutationInfo = if mutation then (Config.Mutations :: any)[mutation] else nil
	local rate = info.cashPerSecond
		* (if mutationInfo then mutationInfo.multiplier else 1)
		* Perks.pedestalIncomeMultiplier(level)
		* Perks.sizeMultiplier(size)
	return rate * (Config.PedestalUpgrade.IncomeGrowth - 1) / Perks.pedestalUpgradeCost(slot, level)
end

-- Cores per slot from the PedestalSummary attribute ("1=Amber+Gold~HugeV|2=seed|3=empty").
function Perks.coresFromSummary(summary: string): { [number]: { rarity: string, mutation: string?, size: string? } }
	local out: { [number]: { rarity: string, mutation: string?, size: string? } } = {}
	for slotText, info in string.gmatch(summary, "(%d+)=([^|]+)") do
		local clean = string.gsub(info :: string, "V$", "")
		local size = string.match(clean, "~(%a+)$")
		clean = string.gsub(clean, "~%a+$", "")
		local rarity, mutation = string.match(clean, "^(%a+)%+(%a+)$")
		if not rarity then
			rarity = string.match(clean, "^(%a+)$")
		end
		if rarity and rarity ~= "seed" and rarity ~= "empty" then
			out[tonumber(slotText) :: number] = { rarity = rarity, mutation = mutation, size = size }
		end
	end
	return out
end

-- At least `seconds` of the player's income, never below the old flat reward
-- (x rebirth multiplier). Used by quests, dailies, milestones, nights, bounties.
function Perks.scaledReward(base: number, rebirths: number, incomePerSecond: number?, seconds: number?): number
	return math.floor(math.max(base * Perks.rebirthMultiplier(rebirths), (incomePerSecond or 0) * (seconds or 0)))
end

function Perks.upgradesUnlocked(skills: { [string]: number }?): boolean
	return Perks.skillLevel(skills, "Cultivation") >= Config.PedestalUpgrade.UnlockCultivation
end

-- Max pedestals: Config.Plot.PedestalSlots + Expansion (tree).
function Perks.maxPedestals(stats: Stats): number
	return Config.Plot.PedestalSlots + math.floor(Perks.get(stats, "pedestalSlots"))
end

-- Crates (M8-05).
function Perks.crate(id: string): CrateDef?
	for _, crate in CRATES do
		if crate.id == id then
			return crate
		end
	end
	return nil
end

function Perks.crateUnlocked(crate: CrateDef, cultivationLevel: number): boolean
	return cultivationLevel >= crate.cultivation
end

-- Never below `incomeSeconds` of the player's income, so crates stay meaningful.
function Perks.cratePrice(crate: CrateDef, rebirths: number, incomePerSecond: number?): number
	return math.floor(
		math.max(crate.price * Perks.rebirthMultiplier(rebirths), (incomePerSecond or 0) * crate.incomeSeconds)
	)
end

function Perks.rarityUnlocked(rarity: string, rebirths: number, cultivationLevel: number): boolean
	local gate = (Config.RarityUnlocks :: { [string]: { rebirthTier: number, cultivation: number } })[rarity]
	if not gate then
		return true
	end
	return Perks.rebirthTier(rebirths) >= gate.rebirthTier and cultivationLevel >= gate.cultivation
end

-- Rebirth Tree (M8-07).
function Perks.treeNode(id: string): TreeNode?
	for _, node in TREE do
		if node.id == id then
			return node
		end
	end
	return nil
end

-- Token cost of the NEXT level of a node (nil = maxed).
function Perks.treeCost(node: TreeNode, currentLevel: number): number?
	return node.costs[currentLevel + 1]
end

-- Defense/gadget upgrades (M8-08).
function Perks.upgrade(id: string): UpgradeDef?
	for _, def in UPGRADES do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Price of taking upgrade `def` from `level` to level + 1 (nil = maxed).
function Perks.upgradeCost(def: UpgradeDef, level: number): number?
	if level >= def.max then
		return nil
	end
	return Progression.cost(def.base, def.growth, level + 1)
end

-- Grove Pass (M8-10): pass XP needed to go from level n - 1 to n.
function Perks.passLevelXp(level: number): number
	return Config.Pass.XpBase + Config.Pass.XpStep * (level - 1)
end

-- Pass level reached with `xp` total pass XP (0..Levels).
function Perks.passLevel(xp: number): number
	local level, spent = 0, 0
	while level < Config.Pass.Levels do
		local need = Perks.passLevelXp(level + 1)
		if spent + need > xp then
			break
		end
		spent += need
		level += 1
	end
	return level
end

-- Index (M8-09): 10 rarities x (plain + 3 mutations) = 40 entries.
function Perks.indexKey(rarity: string, mutation: string?): string
	return if mutation then `{rarity}+{mutation}` else rarity
end

function Perks.indexEntries(discovered: { [string]: boolean }): number
	local count = 0
	for _, rarity in Config.RarityOrder do
		if discovered[rarity] then
			count += 1
		end
		for mutation in Config.Mutations do
			if discovered[Perks.indexKey(rarity, mutation :: string)] then
				count += 1
			end
		end
	end
	return count
end

function Perks.indexRowComplete(discovered: { [string]: boolean }, rarity: string): boolean
	if not discovered[rarity] then
		return false
	end
	for mutation, info in Config.Mutations do
		-- Limited (event-only) mutations are bonus entries, never required.
		if not info.limited and not discovered[Perks.indexKey(rarity, mutation :: string)] then
			return false
		end
	end
	return true
end

-- Commerce XP for a purchase: a flat part plus a part that grows with how big the
-- purchase is next to the player's income (a minute of income or more = full), so
-- spamming tiny upgrades cannot farm it and late-game prices stay meaningful.
function Perks.commerceXp(cost: number, incomePerSecond: number?): number
	local xp = Config.Skills.Xp
	local relative = math.min(1, cost / math.max((incomePerSecond or 0) * 60, 1))
	return math.floor(xp.commerceFlat + xp.commerceScale * relative)
end

return Perks
