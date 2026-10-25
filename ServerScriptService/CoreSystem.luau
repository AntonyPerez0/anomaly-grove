--!strict
-- Cores: placing seeds on pedestals, incubation, rarity hatching and cash ticks.
-- The tick loop is server-authoritative; clients see results via the Cash attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local DayNightCycle = require(script.Parent.DayNightCycle)
local CollectionIndex = require(script.Parent.CollectionIndex)
local FXService = require(script.Parent.FXService)
local TutorialService = require(script.Parent.TutorialService)
local PerfBudget = require(script.Parent.PerfBudget)
local AnalyticsService = require(script.Parent.AnalyticsService)
local QuestService = require(script.Parent.QuestService)
local EventService = require(script.Parent.EventService)
local FriendBoostService = require(script.Parent.FriendBoostService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Zones = require(ReplicatedStorage.Shared.Zones)

local CoreSystem = {}

local CoreModelBuilder = require(game:GetService("ServerStorage").Builders.CoreModelBuilder)

-- Pure helpers (spec-testable).

-- Roll order (must cover every Config.Rarities entry).
-- NOTE: luau-lsp widens array-of-union elements during generalized iteration, so each
-- element is re-narrowed through an explicit cast when read.
local RARITY_NAMES: { Types.Rarity } = Config.RarityOrder :: any
local MUTATION_NAMES: { Types.Mutation } = { "Gold", "Void", "Celestial" }

-- M8 Feed cap: growth cycles a core can hold = base + per pedestal level.
function CoreSystem.feedCap(pedestal: Types.PedestalState): number
	return Config.Feed.BaseCap + math.floor(Config.Feed.CapPerLevel * (pedestal.level or 1))
end

-- M7-03: Void/Celestial hatches are announced to the whole server.
function CoreSystem.shouldAnnounce(rarity: Types.Rarity): boolean
	return Config.Rarities[rarity].tier >= Config.Notify.AnnounceMinTier
end

-- Incubation for this player: onboarding fast-hatch, then Cultivation + Quick
-- Sprouts hatch speed (capped at -60%).
function CoreSystem.hatchSeconds(state: Types.PlayerState, hasPlacedBefore: boolean): number
	local speed = math.min(Perks.get(SkillService.stats(state), "hatchSpeed"), 0.6)
	-- M9-06: Rain makes seeds hatch faster (applies to seeds planted during it).
	return CoreSystem.incubationSeconds(hasPlacedBefore) * (1 - speed) * EventService.incubationMultiplier()
end

-- M7-01: a player's very first seed hatches fast (until they have placed once).
function CoreSystem.incubationSeconds(hasPlacedBefore: boolean): number
	if hasPlacedBefore then
		return Config.Incubation.Duration
	end
	return Config.Onboarding.FirstHatchSeconds
end

-- M7-01: the first core a player ever hatches (empty index) is at least FirstMinTier.
function CoreSystem.applyFirstCoreFloor(rarity: Types.Rarity, isFirstCore: boolean): Types.Rarity
	if isFirstCore and Config.Rarities[rarity].tier < Config.Onboarding.FirstMinTier then
		for _, name in RARITY_NAMES do
			if Config.Rarities[name].tier == Config.Onboarding.FirstMinTier then
				return name :: any
			end
		end
	end
	return rarity
end

-- Forest seed odds straight from Config.Rarities (crate-only rarities are 0).
function CoreSystem.forestOdds(): { [string]: number }
	local odds: { [string]: number } = {}
	for _, name in RARITY_NAMES do
		odds[name :: string] = Config.Rarities[name].chance
	end
	return odds
end

-- Rarity luck (M8): every rarity above the table's lowest one gets x(1 + luck);
-- rollFrom re-normalises, so luck shifts weight upward without breaking the sum.
function CoreSystem.luckOdds(base: { [string]: number }, luck: number): { [string]: number }
	local lowestTier = math.huge
	for name, chance in base do
		if chance > 0 then
			lowestTier = math.min(lowestTier, Config.Rarities[name :: Types.Rarity].tier)
		end
	end
	local out: { [string]: number } = {}
	for name, chance in base do
		out[name] = if Config.Rarities[name :: Types.Rarity].tier > lowestTier then chance * (1 + luck) else chance
	end
	return out
end

-- Weighted roll over `odds` (any total). `isUnlocked` gates crate-only rarities:
-- a locked pick falls to the best unlocked rarity below it.
function CoreSystem.rollFrom(odds: { [string]: number }, rng: Random, isUnlocked: ((string) -> boolean)?): Types.Rarity
	local total = 0
	for _, name in RARITY_NAMES do
		total += odds[name :: string] or 0
	end
	local roll = rng:NextNumber() * total
	local cumulative = 0
	local pickIndex = 1
	for index, name in RARITY_NAMES do
		local chance = odds[name :: string] or 0
		if chance > 0 then
			pickIndex = index -- float edge: the last rarity with weight
			cumulative += chance
			if roll < cumulative then
				break
			end
		end
	end
	if isUnlocked then
		while pickIndex > 1 and not isUnlocked(RARITY_NAMES[pickIndex] :: string) do
			pickIndex -= 1
		end
	end
	return RARITY_NAMES[pickIndex] :: any
end

-- Forest roll (luck optional).
function CoreSystem.rollRarity(rng: Random, luck: number?): Types.Rarity
	return CoreSystem.rollFrom(CoreSystem.luckOdds(CoreSystem.forestOdds(), luck or 0), rng)
end

-- Mutation roll from Config weights (Gold 70% / Void 25% / Celestial 5%), with the
-- Alchemy unlocks that make Void / Celestial likelier (M8-03).
function CoreSystem.rollMutation(rng: Random, voidBonus: number?, celestialBonus: number?): Types.Mutation
	local weights: { [string]: number } = {
		Gold = Config.Mutations.Gold.weight,
		Void = Config.Mutations.Void.weight * (1 + (voidBonus or 0)),
		Celestial = Config.Mutations.Celestial.weight * (1 + (celestialBonus or 0)),
	}
	local total = weights.Gold + weights.Void + weights.Celestial
	local roll = rng:NextNumber() * total
	local cumulative = 0
	for _, key in MUTATION_NAMES do
		cumulative += weights[key :: string]
		if roll < cumulative then
			return key :: any
		end
	end
	return "Gold"
end

-- Cash/s for a hatched core: rarity rate x (1 + bonus per completed cycle).
function CoreSystem.coreRate(pedestal: Types.PedestalState): number
	assert(pedestal.rarity ~= nil, "coreRate called on an empty pedestal")
	local info = Config.Rarities[pedestal.rarity :: Types.Rarity]
	local mutationMultiplier = 1
	if pedestal.mutation ~= nil then
		mutationMultiplier = Config.Mutations[pedestal.mutation :: Types.Mutation].multiplier
	end
	return info.cashPerSecond
		* (1 + Config.Incubation.PedestalCycleBonus * pedestal.completedCycles)
		* mutationMultiplier
		* Perks.pedestalIncomeMultiplier(pedestal.level or 1) -- M8-04 upgrade level
		* Perks.sizeMultiplier(pedestal.size) -- M9-01 core size
end

-- One tick of income for a hatched core. Whole cash goes to the player; fractions
-- accumulate on the pedestal until they roll over. Returns the whole cash awarded.
-- The rebirth cash bonus (GDD 5.7) applies globally per rebirth.
-- `extraMultiplier` carries session boosts (M6-05 friend boost); default 1.
function CoreSystem.tickPedestal(
	state: Types.PlayerState,
	pedestal: Types.PedestalState,
	deltaSeconds: number,
	extraMultiplier: number?
): number
	if pedestal.rarity == nil or pedestal.hatchAt ~= nil then
		return 0 -- empty or still incubating
	end
	local rebirthMultiplier = Perks.rebirthMultiplier(state.rebirths) -- M8-06 compounding
	pedestal.tickFrac += CoreSystem.coreRate(pedestal) * rebirthMultiplier * (extraMultiplier or 1) * deltaSeconds
	local whole = math.floor(pedestal.tickFrac)
	if whole >= 1 then
		pedestal.tickFrac -= whole
		PlayerState.addCash(state, whole)
	end
	return whole
end

-- World helpers.

local function plotsRoot(): Folder?
	local root = Workspace:FindFirstChild("AnomalyGrove")
	return root and root:FindFirstChild("Plots") :: Folder?
end

local function pedestalModel(plotIndex: number, slot: number): Model?
	local root = plotsRoot()
	local plot = root and root:FindFirstChild("Plot" .. (plotIndex + 1))
	if not plot then
		return nil
	end
	local model = plot:FindFirstChild("Pedestal" .. slot)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- Replaces the orb above a pedestal: none | seed (incubating) | core (hatched).
-- M5-07: gem + aura + overhead label via CoreModelBuilder (names stay CoreOrb/SeedOrb).
local function setOrb(
	model: Model?,
	kind: "none" | "seed" | "core",
	color: Color3?,
	rarity: Types.Rarity?,
	mutation: Types.Mutation?,
	boosted: boolean?,
	extra: { level: number?, title: string?, size: string? }?
)
	if kind == "none" then
		CoreModelBuilder.attach(model, nil)
		return
	end
	local rate: number? = nil
	if kind == "core" and rarity ~= nil then
		local mult = if mutation ~= nil then Config.Mutations[mutation :: Types.Mutation].multiplier else 1
		rate = Config.Rarities[rarity :: Types.Rarity].cashPerSecond * mult * Perks.sizeMultiplier(extra and extra.size)
	end
	CoreModelBuilder.attach(model, {
		kind = kind,
		color = color or Color3.fromRGB(200, 255, 210),
		rarity = rarity :: any,
		mutation = mutation :: any,
		rate = rate,
		secondsLeft = if kind == "seed" then Config.Incubation.Duration else nil,
		boosted = boosted,
		level = extra and extra.level,
		title = extra and extra.title,
		size = extra and extra.size,
	})
end

-- Placement.

-- Special seeds (zone + market), best first by expected income.
local function zoneSeedOrder(): { string }
	return Zones.seedOrder()
end

-- Consume one seed. Planting (default) spends the best seed first: zone seeds
-- (best zone first), then Grove Heart seeds, then regular ones. Feeding a hatched
-- core (`cheapestFirst`) spends the plainest seed first, so specials are never
-- wasted. Pure so specs can exercise the priority.
-- Returns "regular" | "grove" | a zone seed id (e.g. "RelicSeed") | nil.
function CoreSystem.consumeSeed(state: Types.PlayerState, cheapestFirst: boolean?): string?
	local function takeZone(): string?
		local order = zoneSeedOrder()
		local from, to, step = 1, #order, 1
		if cheapestFirst then
			from, to, step = #order, 1, -1
		end
		for index = from, to, step do
			local seedId = order[index]
			if (state.zoneSeeds[seedId] or 0) >= 1 then
				PlayerState.addZoneSeed(state, seedId, -1)
				return seedId
			end
		end
		return nil
	end
	if cheapestFirst then
		if state.seedsCarried >= 1 then
			state.seedsCarried -= 1
			if state.player then
				state.player:SetAttribute("SeedsCarried", state.seedsCarried)
			end
			return "regular"
		end
		if state.groveSeeds >= 1 then
			state.groveSeeds -= 1
			if state.player then
				state.player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
			end
			return "grove"
		end
		return takeZone()
	end
	local zoneSeed = takeZone()
	if zoneSeed then
		return zoneSeed
	end
	if state.groveSeeds >= 1 then
		state.groveSeeds -= 1
		if state.player then
			state.player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
		end
		return "grove"
	end
	if state.seedsCarried >= 1 then
		state.seedsCarried -= 1
		if state.player then
			state.player:SetAttribute("SeedsCarried", state.seedsCarried)
		end
		return "regular"
	end
	return nil
end

-- Server-authoritative place. Returns false (with a log line) on rejection.
function CoreSystem.tryPlace(player: Player, plotIndex: number, slot: number): boolean
	local state = PlayerState.get(player)
	if state.plotIndex ~= plotIndex then
		print(`[CoreSystem] {player.Name} place rejected: plot {plotIndex} is not theirs`)
		return false
	end
	-- Reach (2026-10-18 audit): prompts can be fired from anywhere by exploits.
	local reachModel = pedestalModel(plotIndex, slot)
	local reachRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not (reachModel and reachModel.PrimaryPart and reachRoot and reachRoot:IsA("BasePart"))
		or (reachRoot.Position - reachModel.PrimaryPart.Position).Magnitude > 16
	then
		return false
	end
	if PlayerState.seedCount(state) < 1 then
		print(`[CoreSystem] {player.Name} place rejected: no seeds carried`)
		return false
	end
	local pedestal = state.pedestals[slot]
	if not pedestal then
		return false
	end
	if pedestal.hatchAt ~= nil then
		print(`[CoreSystem] {player.Name} place rejected: pedestal {slot} is incubating`)
		return false
	end
	if pedestal.rarity ~= nil then
		-- M8 Feed: a seed on a hatched core adds a growth cycle (+10% income) up
		-- to the pedestal's feed cap, so seeds stay useful once the plot is full.
		if CoreSystem.consumeSeed(state, true) == nil then
			return false
		end
		if pedestal.completedCycles >= CoreSystem.feedCap(pedestal) then
			-- Fully fed: compost the seed for a little cash + XP, so seeds are never
			-- useless (upgrading the pedestal raises the feed cap again).
			local cash = math.floor(
				CoreSystem.coreRate(pedestal) * CoreSystem.playerMultiplier(player, state) * Config.Feed.CompostSeconds
			)
			PlayerState.addCash(state, cash)
			SkillService.addXp(player, "Cultivation", Config.Skills.Xp.feed)
			QuestService.record(player, "plant")
			print(`[CoreSystem] {player.Name} composted a seed on pedestal {slot} (+${cash})`)
			return true
		end
		pedestal.completedCycles += 1
		SkillService.addXp(player, "Cultivation", Config.Skills.Xp.feed)
		CoreSystem.refreshPedestalVisual(state, slot)
		local fedModel = pedestalModel(plotIndex, slot)
		if fedModel and fedModel.PrimaryPart then
			FXService.placeAt(fedModel.PrimaryPart.Position)
		end
		QuestService.record(player, "plant")
		print(`[CoreSystem] {player.Name} fed pedestal {slot} ({pedestal.completedCycles} cycles)`)
		return true
	end
	local seedKind = CoreSystem.consumeSeed(state)
	if seedKind == nil then
		return false
	end
	pedestal.hatchAt = os.clock() + CoreSystem.hatchSeconds(state, state.tutorial.placed)
	pedestal.size = nil
	pedestal.tickFrac = 0
	pedestal.completedCycles = 0
	-- Wild-zone seeds (2026-10-18) hatch with their own odds, stored in the crate
	-- field (rollHatch resolves zone seed ids too); Spore seeds are also boosted.
	local zoneSeed = Zones.seed(seedKind)
	pedestal.mutationBoost = seedKind == "grove" or (zoneSeed ~= nil and zoneSeed.boost)
	pedestal.crate = if zoneSeed then zoneSeed.id else nil
	SkillService.addXp(player, "Cultivation", Config.Skills.Xp.plant)
	CoreSystem.setPedestalSeed(plotIndex, slot, pedestal.mutationBoost, pedestal.crate)
	local placedModel = pedestalModel(plotIndex, slot)
	if placedModel and placedModel.PrimaryPart then
		FXService.placeAt(placedModel.PrimaryPart.Position)
	end
	print(`[CoreSystem] {player.Name} placed a {seedKind} seed on pedestal {slot} (plot {plotIndex})`)
	TutorialService.onPlaced(player)
	QuestService.record(player, "plant")
	return true
end

local function hatchedVisual(state: Types.PlayerState, slot: number, rarity: Types.Rarity)
	local info = Config.Rarities[rarity]
	if state.plotIndex ~= nil then
		local pedestal = state.pedestals[slot]
		setOrb(
			pedestalModel(state.plotIndex, slot),
			"core",
			info.color,
			rarity,
			nil,
			nil,
			{ level = pedestal and pedestal.level, size = pedestal and pedestal.size }
		)
	end
end

-- Public visual helper (used by DataService restore): put a core orb on a pedestal.
-- A mutated core wears the mutation color instead of the rarity color.
function CoreSystem.setPedestalCore(
	plotIndex: number,
	slot: number,
	rarity: Types.Rarity,
	mutation: Types.Mutation?,
	level: number?,
	size: string?
)
	local color = if mutation ~= nil
		then Config.Mutations[mutation :: Types.Mutation].color
		else Config.Rarities[rarity].color
	setOrb(pedestalModel(plotIndex, slot), "core", color, rarity, mutation, nil, { level = level, size = size })
end

-- Public visual helper: clear a pedestal's orb (M9-05 fuse inputs).
function CoreSystem.clearPedestalVisual(plotIndex: number, slot: number)
	setOrb(pedestalModel(plotIndex, slot), "none")
end

-- Public visual helper: an incubating seed / crate (restore + crate planting).
function CoreSystem.setPedestalSeed(plotIndex: number, slot: number, boosted: boolean, crateId: string?)
	local crate = if crateId then Perks.crate(crateId) else nil
	local zoneSeed = Zones.seed(crateId or "")
	local special = Zones.seedColor(crateId or "")
	local color = if crate
		then crate.color
		elseif special then special
		elseif boosted then Config.Mutations.Gold.color
		else nil
	local title = if crate then crate.name elseif zoneSeed then zoneSeed.name else nil
	setOrb(pedestalModel(plotIndex, slot), "seed", color, nil, nil, boosted, { title = title })
end

-- Pure (M9-01): is this size announced to the server (Huge and up)?
function CoreSystem.isBigSize(size: string): boolean
	local order = Config.Sizes.Order
	local at, from = 0, math.huge
	for index, name in order do
		if name == size then
			at = index
		end
		if name == Config.Sizes.AnnounceFrom then
			from = index
		end
	end
	return at >= from
end

-- Pure: does `rolled` beat the current mutation? Passive and offline rolls only
-- ever upgrade (2026-10-18 fix: a Gold roll used to overwrite a Void x10 core).
function CoreSystem.isMutationUpgrade(current: string?, rolled: string): boolean
	local currentMultiplier = if current then (Config.Mutations :: any)[current].multiplier else 1
	return (Config.Mutations :: any)[rolled].multiplier > currentMultiplier
end

-- Applies a mutation to a hatched core: state, visuals, log. Night rolls are 2x.
function CoreSystem.applyMutation(state: Types.PlayerState, slot: number, mutation: Types.Mutation)
	local pedestal = state.pedestals[slot]
	if not pedestal or pedestal.rarity == nil then
		return
	end
	pedestal.mutation = mutation :: any
	local info = Config.Mutations[mutation]
	local fxPosition: Vector3? = nil
	if state.plotIndex ~= nil then
		setOrb(
			pedestalModel(state.plotIndex, slot),
			"core",
			info.color,
			pedestal.rarity :: any,
			mutation,
			nil,
			{ level = pedestal.level, size = pedestal.size }
		)
		local model = pedestalModel(state.plotIndex :: number, slot)
		if model and model.PrimaryPart then
			fxPosition = model.PrimaryPart.Position
		end
	end
	CollectionIndex.onMutation(state, mutation, pedestal.rarity :: any)
	if state.player then
		SkillService.addXp(state.player, "Alchemy", (Config.Skills.Xp.mutation :: any)[mutation] or 0)
		FXService.mutation(state.player, fxPosition)
		print(`[CoreSystem] {state.player.Name}'s pedestal {slot} mutated to {mutation} (x{info.multiplier} rate)`)
	end
end

-- One mutation roll step per tick for a hatched core. Pure logic core here so specs
-- can exercise it; returns the mutation when one triggers.
function CoreSystem.mutationTick(
	pedestal: Types.PedestalState,
	deltaSeconds: number,
	isNight: boolean,
	rng: Random,
	chanceMultiplier: number?, -- world events (Blood Moon x2) x Alchemy/tree chance; default 1
	voidBonus: number?, -- Alchemy unlocks (M8-03)
	celestialBonus: number?
): Types.Mutation?
	if pedestal.rarity == nil or pedestal.hatchAt ~= nil then
		return nil -- nothing hatched to mutate
	end
	pedestal.mutationProgress += deltaSeconds
	if pedestal.mutationProgress < Config.MutationRollInterval then
		return nil
	end
	pedestal.mutationProgress -= Config.MutationRollInterval
	-- Grove Heart seeds boost their core to the night chance around the clock.
	local chance = if isNight or pedestal.mutationBoost == true
		then Config.MutationNightChance
		else Config.MutationChance
	if rng:NextNumber() < chance * (chanceMultiplier or 1) then
		-- M9-09: during the weekly event a share of mutations are the limited Eclipse.
		if EventService.weeklyActive() and rng:NextNumber() < Config.Weekly.EclipseShare then
			return "Eclipse"
		end
		return CoreSystem.rollMutation(rng, voidBonus, celestialBonus)
	end
	return nil
end

-- Pure-ish hatch roll for a state (spec-testable): crate odds or forest odds,
-- rarity luck, rebirth-tier + Cultivation gates, then the first-core floor.
function CoreSystem.rollHatch(state: Types.PlayerState, crateId: string?, rng: Random): Types.Rarity
	local stats = SkillService.stats(state)
	local cultivation = SkillService.level(state, "Cultivation")
	-- crateId is a shop crate or a wild-zone seed id (both pick the hatch odds).
	local crate = if crateId then Perks.crate(crateId) else nil
	local zoneSeed = if crateId then Zones.seed(crateId) else nil
	local base = if crate then crate.odds elseif zoneSeed then zoneSeed.odds else CoreSystem.forestOdds()
	local rarity = CoreSystem.rollFrom(CoreSystem.luckOdds(base, Perks.get(stats, "rarityLuck")), rng, function(name)
		return Perks.rarityUnlocked(name, state.rebirths, cultivation)
	end)
	return CoreSystem.applyFirstCoreFloor(rarity :: Types.Rarity, next(state.indexDiscovered) == nil)
end

local function hatch(state: Types.PlayerState, slot: number, pedestal: Types.PedestalState)
	local rng = Random.new(os.clock() * 1e6)
	local rarity: Types.Rarity = CoreSystem.rollHatch(state, pedestal.crate, rng)
	pedestal.rarity = rarity
	pedestal.size = Perks.rollSize(rng) -- M9-01
	pedestal.hatchAt = nil
	pedestal.crate = nil
	pedestal.completedCycles += 1
	if state.player then
		SkillService.addXp(state.player, "Cultivation", Config.Skills.Xp.hatchByTier[Config.Rarities[rarity].tier] or 0)
		CollectionIndex.onCoreHatched(state.player, state, rarity, pedestal.mutation)
		AnalyticsService.onCoreHatched(state)
		if Config.Rarities[rarity].tier >= 3 then
			QuestService.record(state.player, "hatchRare")
		end
		hatchedVisual(state, slot, rarity)
		local model = pedestalModel(state.plotIndex :: number, slot)
		if model and model.PrimaryPart then
			FXService.hatchAt(model.PrimaryPart.Position, Config.Rarities[rarity].color)
		end
		if pedestal.size and CoreSystem.isBigSize(pedestal.size) then
			-- M9-01: Huge / Titanic hatches are server news (and a raid magnet).
			Remotes.get("TutorialToast")
				:FireAllClients(`{state.player.Name} hatched a {string.upper(pedestal.size)} {rarity} core!`)
		elseif CoreSystem.shouldAnnounce(rarity) then
			-- M7-03: everyone in the server sees a Void/Celestial hatch (a raid magnet!).
			Remotes.get("TutorialToast"):FireAllClients(`{state.player.Name} hatched a {rarity} core!`)
		end
		print(`[CoreSystem] {state.player.Name}'s pedestal {slot} hatched a {rarity} core!`)
	end
end

-- Friend boost x 2x Cash pass (the server sets DoubleCash; client attribute writes
-- never replicate up) x M8 income perks (skills, Golden Touch, Index) x night income.
local function incomeMultiplier(player: Player, stats: Perks.Stats?): number
	local perkMultiplier = 1
	if stats then
		perkMultiplier = (1 + Perks.get(stats, "income"))
			* (if DayNightCycle.getPhase() == "Night" then 1 + Perks.get(stats, "nightIncome") else 1)
	end
	return FriendBoostService.multiplier(player)
		* (if player:GetAttribute("DoubleCash") == true then Config.DoubleCashMultiplier else 1)
		* perkMultiplier
end

-- Every multiplier on top of a core's own rate, for one player right now.
function CoreSystem.playerMultiplier(player: Player, state: Types.PlayerState): number
	return Perks.rebirthMultiplier(state.rebirths) * incomeMultiplier(player, SkillService.stats(state))
end

-- M8-05: plant a crate into `slot` (empty, or a weaker core it replaces).
function CoreSystem.plantCrate(player: Player, state: Types.PlayerState, crateId: string, slot: number): number?
	local pedestal = state.pedestals[slot]
	if not pedestal then
		return nil
	end
	pedestal.rarity = nil -- a replaced weaker core is consumed by the crate
	pedestal.mutation = nil
	pedestal.mutationProgress = 0
	pedestal.hatchAt = os.clock() + CoreSystem.hatchSeconds(state, true)
	pedestal.tickFrac = 0
	pedestal.completedCycles = 0
	pedestal.mutationBoost = false
	pedestal.crate = crateId
	pedestal.size = nil
	if state.plotIndex ~= nil then
		CoreSystem.setPedestalSeed(state.plotIndex :: number, slot, false, crateId)
		local model = pedestalModel(state.plotIndex :: number, slot)
		if model and model.PrimaryPart then
			FXService.placeAt(model.PrimaryPart.Position)
		end
	end
	SkillService.addXp(player, "Cultivation", Config.Skills.Xp.plant)
	QuestService.record(player, "plant")
	return slot
end

-- Refresh one pedestal's core visual (after an upgrade changes its level).
function CoreSystem.refreshPedestalVisual(state: Types.PlayerState, slot: number)
	local pedestal = state.pedestals[slot]
	if state.plotIndex ~= nil and pedestal and pedestal.rarity ~= nil and pedestal.hatchAt == nil then
		CoreSystem.setPedestalCore(
			state.plotIndex :: number,
			slot,
			pedestal.rarity :: Types.Rarity,
			pedestal.mutation,
			pedestal.level,
			pedestal.size
		)
	end
end

-- Wiring.

local function normalizePrompt(prompt: ProximityPrompt)
	prompt.HoldDuration = Config.Incubation.PlaceHoldTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
end

local function wirePedestal(plotIndex: number, model: Model)
	-- The prompt lives on the Pad part (M5-05 restyle), so search recursively.
	local prompt = model:FindFirstChild("PlacePrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") and not prompt:GetAttribute("Wired") then
		prompt:SetAttribute("Wired", true)
		normalizePrompt(prompt)
		prompt.Triggered:Connect(function(player)
			local slot = tonumber(string.match(model.Name, "^Pedestal(%d+)$"))
			if slot then
				CoreSystem.tryPlace(player, plotIndex, slot)
			end
		end)
	end
end

-- Nearest pedestal (any slot, any plot) to a position; used by the mobile remote path.
local function nearestPedestal(from: Vector3): Model?
	local root = plotsRoot()
	if not root then
		return nil
	end
	local best: Model? = nil
	local bestDist = math.huge
	for _, plot in root:GetChildren() do
		if not plot:IsA("Folder") then
			continue
		end
		for _, child in plot:GetChildren() do
			local slot = tonumber(string.match(child.Name, "^Pedestal(%d+)$"))
			if child:IsA("Model") and slot and child.PrimaryPart then
				local dist = (child.PrimaryPart.Position - from).Magnitude
				if dist < bestDist then
					bestDist = dist
					best = child
				end
			end
		end
	end
	return best
end

-- Boot: wire prompts + remote, then run the 1 Hz income/hatch loop. Call from Main.server.
function CoreSystem.init()
	local root = plotsRoot()
	if root then
		for _, plot in root:GetChildren() do
			if not plot:IsA("Folder") then
				continue
			end
			local plotIndex = plot:GetAttribute("PlotIndex")
			if type(plotIndex) ~= "number" then
				continue
			end
			for _, child in plot:GetChildren() do
				if child:IsA("Model") and string.match(child.Name, "^Pedestal%d+$") then
					wirePedestal(plotIndex :: number, child)
				end
			end
			-- Pedestals bought later (and rebuilt on rejoin) get wired too.
			plot.ChildAdded:Connect(function(child)
				if child:IsA("Model") and string.match(child.Name, "^Pedestal%d+$") then
					wirePedestal(plotIndex :: number, child)
				end
			end)
		end
	end

	task.spawn(function()
		local placeRemote = Remotes.get("PlaceCore")
		placeRemote.OnServerEvent:Connect(function(player)
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or not rootPart:IsA("BasePart") then
				return
			end
			local model = nearestPedestal(rootPart.Position)
			if not model then
				return
			end
			local slot = tonumber(string.match(model.Name, "^Pedestal(%d+)$"))
			local plot = model.Parent
			local plotIndex = plot and plot:GetAttribute("PlotIndex")
			if slot and type(plotIndex) == "number" then
				CoreSystem.tryPlace(player, plotIndex :: number, slot)
			end
		end)
	end)

	-- Cash-blip bookkeeping: one soft blip per CashBlipSeconds of income per player,
	-- carrying the amount earned since the previous blip for the popup (M3-08).
	local lastBlipAt: { [Player]: number } = {}
	local blipBuffer: { [Player]: number } = {}

	local function maybeBlip(player: Player, earned: number)
		local now = os.clock()
		local last = lastBlipAt[player] or 0
		blipBuffer[player] = (blipBuffer[player] or 0) + earned
		if now - last >= Config.HUD.CashBlipSeconds then
			lastBlipAt[player] = now
			FXService.cashBlip(player, math.floor(blipBuffer[player] or 0))
			blipBuffer[player] = 0
		end
	end

	-- 1 Hz heartbeat: hatch due seeds, then pay out income.
	task.spawn(function()
		local rng = Random.new(os.clock() * 1e6)
		while true do
			task.wait(1)
			local spotStart = os.clock()
			local now = os.clock()
			local changedPlayers: { [Player]: boolean } = {}
			for _, player in Players:GetPlayers() do
				local state = PlayerState.peek(player)
				if not state or state.plotIndex == nil then
					continue
				end
				local earned = 0
				local stats = SkillService.stats(state)
				local multiplier = incomeMultiplier(player, stats)
				local mutationMultiplier = EventService.mutationMultiplier() * (1 + Perks.get(stats, "mutationChance"))
				local levels: { string } = {}
				for slot, pedestal in state.pedestals do
					table.insert(levels, tostring(pedestal.level or 1))
					if pedestal.hatchAt ~= nil and now >= pedestal.hatchAt then
						hatch(state, slot, pedestal)
						changedPlayers[player] = true
					end
					-- Mutation rolls every MutationRollInterval of pedestal lifetime;
					-- each roll is a little Alchemy XP (more for higher-tier cores).
					if
						pedestal.rarity ~= nil
						and pedestal.hatchAt == nil
						and pedestal.mutationProgress + 1 >= Config.MutationRollInterval
					then
						SkillService.addXp(
							player,
							"Alchemy",
							Config.Skills.Xp.mutationRoll * Config.Rarities[pedestal.rarity :: Types.Rarity].tier,
							true
						)
					end
					local rolled = CoreSystem.mutationTick(
						pedestal,
						1,
						DayNightCycle.getPhase() == "Night",
						rng,
						mutationMultiplier,
						Perks.get(stats, "voidWeight"),
						Perks.get(stats, "celestialWeight") + EventService.celestialBonus() -- M9-06 Aurora
					)
					if rolled ~= nil and CoreSystem.isMutationUpgrade(pedestal.mutation, rolled) then
						local mutation: Types.Mutation = rolled :: any
						CoreSystem.applyMutation(state, slot, mutation)
						changedPlayers[player] = true
					end
					earned += CoreSystem.tickPedestal(state, pedestal, 1, multiplier)
				end
				local levelText = table.concat(levels, ",")
				if player:GetAttribute("PedestalLevels") ~= levelText then
					player:SetAttribute("PedestalLevels", levelText)
				end
				if earned > 0 then
					QuestService.record(player, "earn", earned)
					changedPlayers[player] = true
					maybeBlip(player, earned)
				end
				-- Pedestal summary for the panel readout (1 Hz, cheap string build).
				local summaryParts: { string } = {}
				for slot, pedestal in state.pedestals do
					local entry: string
					if pedestal.hatchAt ~= nil then
						entry = "seed"
					elseif pedestal.rarity ~= nil then
						entry = pedestal.rarity :: string
					else
						entry = "empty"
					end
					if pedestal.mutation ~= nil then
						entry = `{entry}+{pedestal.mutation}`
					end
					if pedestal.size ~= nil and pedestal.hatchAt == nil then
						entry = `{entry}~{pedestal.size}`
					end
					if pedestal.vaultLocked then
						entry = `{entry}V`
					end
					table.insert(summaryParts, `{slot}={entry}`)
				end
				player:SetAttribute("PedestalSummary", table.concat(summaryParts, "|"))
				-- Overhead labels: live $/s (cycle bonus + rebirth) or the hatch countdown.
				local rebirthMultiplier = Perks.rebirthMultiplier(state.rebirths) * multiplier
				local totalRate = 0
				for slot, pedestal in state.pedestals do
					if pedestal.rarity ~= nil and pedestal.hatchAt == nil then
						totalRate += CoreSystem.coreRate(pedestal) * rebirthMultiplier
					end
					local model = pedestalModel(state.plotIndex :: number, slot)
					if pedestal.hatchAt ~= nil then
						CoreModelBuilder.setRateText(
							model,
							`Hatching {math.max(0, math.ceil((pedestal.hatchAt :: number) - now))}s`
						)
					elseif pedestal.rarity ~= nil then
						CoreModelBuilder.setRateText(
							model,
							CoreModelBuilder.formatRate(CoreSystem.coreRate(pedestal) * rebirthMultiplier)
						)
					end
				end
				-- HUD income line (replicated; written only when the rounded value moves).
				local rounded = math.floor(totalRate * 10 + 0.5) / 10
				if player:GetAttribute("IncomeRate") ~= rounded then
					player:SetAttribute("IncomeRate", rounded)
				end
			end
			for player in changedPlayers do
				PlotSystem.refreshSign(player)
			end
			PerfBudget.spot("CoreTick", os.clock() - spotStart)
		end
	end)
end

return CoreSystem
