--!strict
-- Offline growth (GDD 5.5): while away, cores tick at reduced efficiency (capped)
-- and each core gets mutation rolls. Pure math here; DataService triggers apply.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CoreSystem = require(script.Parent.CoreSystem)
local CollectionIndex = require(script.Parent.CollectionIndex)
local PlayerState = require(script.Parent.PlayerState)
local MonetizationService = require(script.Parent.MonetizationService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)

local OfflineGrowth = {}

export type OfflineSummary = {
	cashEarned: number,
	mutations: { { slot: number, mutation: Types.Mutation } },
	elapsed: number,
}

-- Pure: which mutation a successful roll grants (weights live in CoreSystem).
function OfflineGrowth.rollMutation(rng: Random): Types.Mutation
	return CoreSystem.rollMutation(rng)
end

-- Pure-ish core of the offline math. Mutates the given pedestal states (rarity set
-- only): adds income fraction and applies at most one mutation per core.
-- Returns the summary for the popup.
function OfflineGrowth.computeFor(
	pedestals: { Types.PedestalState },
	lastSeen: number,
	now: number,
	mutationChance: number?,
	capSeconds: number?, -- M8: Commerce / Long Nap raise the cap
	multiplier: number? -- M8: rebirth x income perks (offline skips night/friend boosts)
): OfflineSummary
	local elapsed = math.clamp(now - lastSeen, 0, capSeconds or Config.Offline.CapSeconds)
	local chance = mutationChance or Config.Offline.Chance
	local cashEarned = 0
	local mutations: { { slot: number, mutation: Types.Mutation } } = {}
	if elapsed < Config.Offline.MinOfflineSeconds then
		return { cashEarned = 0, mutations = mutations, elapsed = elapsed }
	end
	local rng = Random.new(now % 1e6)
	for slot, pedestal in pedestals do
		if pedestal.rarity ~= nil and pedestal.hatchAt == nil then
			local rate = CoreSystem.coreRate(pedestal)
			cashEarned += rate * elapsed * Config.Offline.Efficiency * (multiplier or 1)
			-- Mutation rolls: floor(elapsed / interval), capped, chance each, one mutation max.
			-- The chance is injectable so the Offline Mutation Luck pass can double it (M3-05).
			local rolls =
				math.min(math.floor(elapsed / Config.Offline.RollInterval), Config.Offline.MaxMutationRollsPerCore)
			for _ = 1, rolls do
				if rng:NextNumber() < chance then
					local mutation: Types.Mutation = OfflineGrowth.rollMutation(rng)
					-- Never a downgrade (2026-10-18 fix); a worse roll is simply lost.
					if CoreSystem.isMutationUpgrade(pedestal.mutation, mutation) then
						pedestal.mutation = mutation :: any
						table.insert(mutations, { slot = slot, mutation = mutation })
					end
					break -- one mutation roll per core per absence
				end
			end
		end
	end
	cashEarned = math.floor(cashEarned)
	return { cashEarned = cashEarned, mutations = mutations, elapsed = elapsed }
end

-- M7-02 popup teaser: seconds until the soonest incubating seed hatches, or 0 when
-- nothing is incubating or it is further away than the teaser window.
function OfflineGrowth.nextHatchSeconds(pedestals: { Types.PedestalState }, now: number): number
	local soonest = math.huge
	for _, pedestal in pedestals do
		if pedestal.hatchAt ~= nil then
			soonest = math.min(soonest, math.max(0, pedestal.hatchAt - now))
		end
	end
	if soonest == math.huge or soonest > Config.Notify.TeaserMaxSeconds then
		return 0
	end
	return math.ceil(soonest)
end

-- Apply offline growth to a live player state and fire the popup.
function OfflineGrowth.applyToState(player: Player, lastSeen: number)
	local state = PlayerState.get(player)
	local chance = MonetizationService.offlineMutationChance(player, Config.Offline.Chance)
	local stats = SkillService.stats(state)
	local summary = OfflineGrowth.computeFor(
		state.pedestals,
		lastSeen,
		os.time(),
		chance,
		Config.Offline.CapSeconds + 3600 * Perks.get(stats, "offlineHours"),
		Perks.rebirthMultiplier(state.rebirths) * (1 + Perks.get(stats, "income"))
	)
	-- The 2x Cash pass doubles offline earnings too.
	summary.cashEarned = math.floor(
		summary.cashEarned
			* MonetizationService.doubleCashMultiplier(
				MonetizationService.isPassOwner(player, Config.GamePasses.DoubleCash)
			)
	)
	if summary.cashEarned > 0 then
		PlayerState.addCash(state, summary.cashEarned)
	end
	for _, entry in summary.mutations do
		local pedestal = state.pedestals[entry.slot]
		if pedestal then
			pedestal.mutation = entry.mutation
			if state.plotIndex ~= nil then
				CoreSystem.setPedestalCore(
					state.plotIndex,
					entry.slot,
					pedestal.rarity :: Types.Rarity,
					entry.mutation,
					pedestal.level,
					pedestal.size
				)
				CollectionIndex.onMutation(state, entry.mutation, pedestal.rarity :: Types.Rarity)
			end
		end
	end
	if summary.cashEarned > 0 or #summary.mutations > 0 then
		Remotes.get("OfflineSummary"):FireClient(
			player,
			summary.cashEarned,
			#summary.mutations,
			summary.elapsed,
			OfflineGrowth.nextHatchSeconds(state.pedestals, os.clock())
		)
		print(
			`[OfflineGrowth] {player.Name} collected {summary.cashEarned} cash offline ({math.floor(
				summary.elapsed / 60
			)} min) and {#summary.mutations} mutations`
		)
	end
	return summary
end

return OfflineGrowth
