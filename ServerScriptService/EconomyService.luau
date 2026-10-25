--!strict
-- M8 purchases: pedestal upgrade levels (M8-04), seed crates (M8-05), alchemy
-- infuse, Rebirth Tree nodes (M8-07) and defense/gadget upgrades (M8-08).
-- Every remote validates types, ranges, ownership, gates and cash on the server,
-- is rate limited, applies the Commerce discount and pays Commerce XP.
-- Pure "check" functions are exported for EconomySpec.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local CoreSystem = require(script.Parent.CoreSystem)
local SkillService = require(script.Parent.SkillService)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)

local EconomyService = {}

local RATE_LIMIT = 0.15 -- seconds between purchases per player (holding a button is fine)
local lastAt: { [Player]: number } = {}

-- Pure gates ---------------------------------------------------------------

-- Pedestal upgrade: (ok, reasonOrPrice).
function EconomyService.checkUpgradePedestal(state: Types.PlayerState, slot: number): (boolean, string | number)
	local pedestal = state.pedestals[slot]
	if state.plotIndex == nil or not pedestal then
		return false, "no such pedestal"
	end
	if not Perks.upgradesUnlocked(state.skills) then
		return false, `needs Cultivation {Config.PedestalUpgrade.UnlockCultivation}`
	end
	if pedestal.level >= Perks.pedestalCap(state.rebirths) then
		return false, "level cap reached (rebirth tier raises it)"
	end
	local price =
		Perks.discounted(Perks.pedestalUpgradeCost(slot, pedestal.level, state.rebirths), SkillService.stats(state))
	if state.cash < price then
		return false, "not enough cash"
	end
	return true, price
end

-- Where a crate goes: the first empty pedestal, otherwise the weakest core whose
-- income is below what the crate is EXPECTED to give on that pedestal (same level
-- and growth cycles), mutations included. So a crate is never a downgrade on
-- average, and late-game crates stay a real chase (2026-10-18 economy review:
-- the old "unmutated, near the floor" rule left nothing to spend on late).
function EconomyService.crateSlot(state: Types.PlayerState, crateId: string): number?
	local crate = Perks.crate(crateId)
	if not crate then
		return nil
	end
	local maxTier, total, weighted = 0, 0, 0
	for rarity, weight in crate.odds do
		local info = Config.Rarities[rarity :: Types.Rarity]
		maxTier = math.max(maxTier, info.tier)
		total += weight
		weighted += info.cashPerSecond * weight
	end
	local expectedBase = if total > 0 then weighted / total else 0
	local weakestSlot, weakestRate = nil, math.huge
	for slot, pedestal in state.pedestals do
		if pedestal.rarity == nil and pedestal.hatchAt == nil then
			return slot
		end
		if pedestal.rarity ~= nil and pedestal.hatchAt == nil then
			local rate = CoreSystem.coreRate(pedestal)
			local expected = expectedBase
				* (1 + Config.Incubation.PedestalCycleBonus * pedestal.completedCycles)
				* Perks.pedestalIncomeMultiplier(pedestal.level or 1)
			if
				Config.Rarities[pedestal.rarity :: Types.Rarity].tier < maxTier
				and rate < expected
				and rate < weakestRate
			then
				weakestSlot, weakestRate = slot, rate
			end
		end
	end
	return weakestSlot
end
function EconomyService.checkCrate(state: Types.PlayerState, crateId: string): (boolean, string | number)
	local crate = Perks.crate(crateId)
	if not crate then
		return false, "unknown crate"
	end
	if state.plotIndex == nil then
		return false, "claim a plot first"
	end
	if not Perks.crateUnlocked(crate, SkillService.level(state, "Cultivation")) then
		return false, `needs Cultivation {crate.cultivation}`
	end
	if EconomyService.crateSlot(state, crateId) == nil then
		return false, "no empty pedestal or weaker core to replace"
	end
	local income = if state.player then state.player:GetAttribute("IncomeRate") else nil
	local price = Perks.discounted(
		Perks.cratePrice(crate, state.rebirths, if type(income) == "number" then income else 0),
		SkillService.stats(state)
	)
	if state.cash < price then
		return false, "not enough cash"
	end
	return true, price
end

-- Infuse price for a hatched core: CostSeconds of that core's income (min MinCost).
function EconomyService.infusePrice(state: Types.PlayerState, pedestal: Types.PedestalState): number
	local rate = CoreSystem.coreRate(pedestal) * Perks.rebirthMultiplier(state.rebirths)
	return Perks.discounted(
		math.max(Config.Infuse.MinCost, math.floor(rate * Config.Infuse.CostSeconds)),
		SkillService.stats(state)
	)
end

function EconomyService.checkInfuse(state: Types.PlayerState, slot: number): (boolean, string | number)
	local pedestal = state.pedestals[slot]
	if state.plotIndex == nil or not pedestal or pedestal.rarity == nil or pedestal.hatchAt ~= nil then
		return false, "needs a hatched core"
	end
	if pedestal.mutation == "Celestial" then
		return false, "already Celestial"
	end
	local price = EconomyService.infusePrice(state, pedestal)
	if state.cash < price then
		return false, "not enough cash"
	end
	return true, price
end

function EconomyService.checkTreeNode(state: Types.PlayerState, nodeId: string): (boolean, string | number)
	local node = Perks.treeNode(nodeId)
	if not node then
		return false, "unknown node"
	end
	local cost = Perks.treeCost(node, state.tree[nodeId] or 0)
	if cost == nil then
		return false, "maxed"
	end
	if state.tokens < cost then
		return false, "not enough tokens"
	end
	return true, cost
end

function EconomyService.checkUpgrade(state: Types.PlayerState, upgradeId: string): (boolean, string | number)
	local def = Perks.upgrade(upgradeId)
	if not def then
		return false, "unknown upgrade"
	end
	local base = Perks.upgradeCost(def, state.upgrades[upgradeId] or 0)
	if base == nil then
		return false, "maxed"
	end
	local price = Perks.discounted(base, SkillService.stats(state))
	if state.cash < price then
		return false, "not enough cash"
	end
	return true, price
end

-- Mutation order for infuse: an infuse only ever upgrades a core's mutation.
local MUTATION_RANK: { [string]: number } = { Gold = 1, Void = 2, Shocked = 2.5, Eclipse = 2.8, Celestial = 3 }

-- Runtime ------------------------------------------------------------------

local function paid(player: Player, state: Types.PlayerState, price: number): boolean
	if not PlayerState.spendCash(state, price) then
		return false
	end
	SkillService.addCommerceXp(player, price)
	return true
end

function EconomyService.upgradePedestal(player: Player, slot: number): boolean
	local state = PlayerState.get(player)
	local ok, result = EconomyService.checkUpgradePedestal(state, slot)
	if not ok or not paid(player, state, result :: number) then
		print(`[Economy] {player.Name} upgrade pedestal {slot} rejected: {result}`)
		return false
	end
	local pedestal = state.pedestals[slot]
	pedestal.level += 1
	CoreSystem.refreshPedestalVisual(state, slot)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Pure: the pedestal UPGRADE ALL buys next: the best income gained per dollar,
-- hatched cores only (2026-10-18 review: it used to buy the cheapest level, even
-- on empty pedestals). Returns (slot, price) or nil when nothing is affordable.
function EconomyService.bestUpgrade(state: Types.PlayerState): (number?, number?)
	local bestSlot, bestPrice, bestValue = nil, nil, 0
	for slot, pedestal in state.pedestals do
		if pedestal.rarity ~= nil and pedestal.hatchAt == nil then
			local ok, price = EconomyService.checkUpgradePedestal(state, slot)
			if ok then
				local value = Perks.upgradeValue(
					pedestal.rarity :: any,
					pedestal.mutation :: any,
					slot,
					pedestal.level,
					pedestal.size
				)
				if value > bestValue then
					bestSlot, bestPrice, bestValue = slot, price :: number, value
				end
			end
		end
	end
	return bestSlot, bestPrice
end

-- "Upgrade All": the best-value affordable level, repeatedly, in one tap.
-- Returns how many levels were bought.
function EconomyService.upgradeAll(player: Player): number
	local state = PlayerState.get(player)
	local bought = 0
	for _ = 1, Config.PedestalUpgrade.UpgradeAllMax do
		local bestSlot, bestPrice = EconomyService.bestUpgrade(state)
		if not bestSlot or not bestPrice or not PlayerState.spendCash(state, bestPrice) then
			break
		end
		state.pedestals[bestSlot :: number].level += 1
		bought += 1
	end
	if bought > 0 then
		local rate = player:GetAttribute("IncomeRate")
		SkillService.addCommerceXp(player, (if type(rate) == "number" then rate else 0) * 60) -- one full-size purchase
		for slot in state.pedestals do
			CoreSystem.refreshPedestalVisual(state, slot)
		end
		FXService.purchase(player)
		QuestService.record(player, "buy")
		Remotes.get("TutorialToast")
			:FireClient(player, `Upgraded {bought} pedestal level{if bought == 1 then "" else "s"}!`)
	end
	return bought
end

function EconomyService.buyCrate(player: Player, crateId: string): boolean
	local state = PlayerState.get(player)
	local ok, result = EconomyService.checkCrate(state, crateId)
	if not ok or not paid(player, state, result :: number) then
		print(`[Economy] {player.Name} crate {crateId} rejected: {result}`)
		return false
	end
	local slot = CoreSystem.plantCrate(player, state, crateId, EconomyService.crateSlot(state, crateId) :: number)
	print(`[Economy] {player.Name} planted a {crateId} crate on pedestal {slot} for ${result}`)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

function EconomyService.infuse(player: Player, slot: number): boolean
	local state = PlayerState.get(player)
	local ok, result = EconomyService.checkInfuse(state, slot)
	if not ok or not paid(player, state, result :: number) then
		print(`[Economy] {player.Name} infuse {slot} rejected: {result}`)
		return false
	end
	local pedestal = state.pedestals[slot]
	local stats = SkillService.stats(state)
	local tier = Config.Rarities[pedestal.rarity :: Types.Rarity].tier
	-- XP scales with how big the price is next to a minute of income (2026-10-18
	-- audit: cheap infuses on the weakest core were a spam XP farm).
	local weight = math.clamp((result :: number) / math.max(PlayerState.incomeRate(state) * 60, 1), 0.1, 1)
	SkillService.addXp(player, "Alchemy", (Config.Skills.Xp.infuse + 10 * tier) * weight)
	local chance = Config.Infuse.BaseChance + Perks.get(stats, "infuseChance")
	if math.random() < chance then
		local rolled = CoreSystem.rollMutation(
			Random.new(os.clock() * 1e6),
			Perks.get(stats, "voidWeight"),
			Perks.get(stats, "celestialWeight")
		)
		local current = if pedestal.mutation then MUTATION_RANK[pedestal.mutation :: string] else 0
		if MUTATION_RANK[rolled :: string] > current then
			CoreSystem.applyMutation(state, slot, rolled :: Types.Mutation)
			Remotes.get("TutorialToast"):FireClient(player, `Infuse worked! Core became {rolled}`)
			return true
		end
	end
	Remotes.get("TutorialToast"):FireClient(player, "The infusion fizzled... try again")
	return true
end

function EconomyService.buyTreeNode(player: Player, nodeId: string): boolean
	local state = PlayerState.get(player)
	local ok, result = EconomyService.checkTreeNode(state, nodeId)
	if not ok then
		print(`[Economy] {player.Name} tree {nodeId} rejected: {result}`)
		return false
	end
	state.tokens -= result :: number
	state.tree[nodeId] = (state.tree[nodeId] or 0) + 1
	SkillService.publish(player, state)
	FXService.purchase(player)
	print(`[Economy] {player.Name} tree {nodeId} -> {state.tree[nodeId]}`)
	return true
end

function EconomyService.buyUpgrade(player: Player, upgradeId: string): boolean
	local state = PlayerState.get(player)
	local ok, result = EconomyService.checkUpgrade(state, upgradeId)
	if not ok or not paid(player, state, result :: number) then
		print(`[Economy] {player.Name} upgrade {upgradeId} rejected: {result}`)
		return false
	end
	state.upgrades[upgradeId] = (state.upgrades[upgradeId] or 0) + 1
	SkillService.publish(player, state)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Wiring -------------------------------------------------------------------

local function allowed(player: Player): boolean
	local now = os.clock()
	if now - (lastAt[player] or 0) < RATE_LIMIT then
		return false
	end
	lastAt[player] = now
	local state = PlayerState.peek(player)
	return state ~= nil and state.quests ~= nil
end

local function slotArg(value: any): number?
	if
		type(value) == "number"
		and value == math.floor(value)
		and value >= 1
		and value <= Config.Plot.MaxPedestalSlots
	then
		return value
	end
	return nil
end

local function idArg(value: any): string?
	if type(value) == "string" and #value <= 40 then
		return value
	end
	return nil
end

function EconomyService.init()
	Remotes.get("UpgradePedestal").OnServerEvent:Connect(function(player, slot)
		local s = slotArg(slot)
		if s and allowed(player) then
			EconomyService.upgradePedestal(player, s)
		end
	end)
	Remotes.get("UpgradeAll").OnServerEvent:Connect(function(player)
		if allowed(player) then
			EconomyService.upgradeAll(player)
		end
	end)
	Remotes.get("Infuse").OnServerEvent:Connect(function(player, slot)
		local s = slotArg(slot)
		if s and allowed(player) then
			EconomyService.infuse(player, s)
		end
	end)
	Remotes.get("BuyCrate").OnServerEvent:Connect(function(player, crateId)
		local id = idArg(crateId)
		if id and allowed(player) then
			EconomyService.buyCrate(player, id)
		end
	end)
	Remotes.get("BuyTreeNode").OnServerEvent:Connect(function(player, nodeId)
		local id = idArg(nodeId)
		if id and allowed(player) then
			EconomyService.buyTreeNode(player, id)
		end
	end)
	Remotes.get("BuyUpgrade").OnServerEvent:Connect(function(player, upgradeId)
		local id = idArg(upgradeId)
		if id and allowed(player) then
			EconomyService.buyUpgrade(player, id)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAt[player] = nil
	end)
end

return EconomyService
