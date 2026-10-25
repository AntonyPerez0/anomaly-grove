--!strict
-- Fuse Machine (M9-05). Remote FuseCores(rarity): fuse the player's 3 weakest
-- hatched cores of that rarity. Success = one core of the next rarity; fail = one
-- core of the same rarity. Either way the survivor sits on the highest-level of
-- the three pedestals, keeps the best mutation and re-rolls its size (best of 2);
-- the other two pedestals are emptied (their levels stay).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Fuse = require(ReplicatedStorage.Shared.Fuse)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local CoreSystem = require(script.Parent.CoreSystem)
local SkillService = require(script.Parent.SkillService)
local CollectionIndex = require(script.Parent.CollectionIndex)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)

local FuseService = {}

export type Plan = { inputs: { number }, target: number }

-- Pure: which pedestals a fuse of `rarity` would use, or (nil, reason).
function FuseService.plan(state: Types.PlayerState, rarity: string): (Plan?, string?)
	local candidates: { number } = {}
	for slot, pedestal in state.pedestals do
		if pedestal.rarity == rarity and pedestal.hatchAt == nil then
			table.insert(candidates, slot)
		end
	end
	if #candidates < Config.Fuse.Count then
		return nil, `need {Config.Fuse.Count} {rarity} cores`
	end
	table.sort(candidates, function(a, b)
		local ra, rb = CoreSystem.coreRate(state.pedestals[a]), CoreSystem.coreRate(state.pedestals[b])
		if ra == rb then
			return a < b
		end
		return ra < rb
	end)
	local inputs = { table.unpack(candidates, 1, Config.Fuse.Count) }
	local target = inputs[1]
	for _, slot in inputs do
		if (state.pedestals[slot].level or 1) > (state.pedestals[target].level or 1) then
			target = slot
		end
	end
	return { inputs = inputs, target = target }, nil
end

-- Pure-ish: apply a plan. Returns (resultRarity, success).
function FuseService.apply(state: Types.PlayerState, plan: Plan, rarity: string, rng: Random): (string, boolean)
	local bestMutation: string? = nil
	for _, slot in plan.inputs do
		local mutation = state.pedestals[slot].mutation
		if mutation and (bestMutation == nil or CoreSystem.isMutationUpgrade(bestMutation, mutation)) then
			bestMutation = mutation
		end
	end
	local result = Fuse.nextRarity(rarity)
	local success = result ~= nil and rng:NextNumber() < Fuse.chance(rarity)
	local outRarity = if success then result :: string else rarity
	for _, slot in plan.inputs do
		local pedestal = state.pedestals[slot]
		if slot == plan.target then
			pedestal.rarity = outRarity :: any
			pedestal.mutation = bestMutation :: any
			local a, b = Perks.rollSize(rng), Perks.rollSize(rng)
			pedestal.size = if Perks.sizeMultiplier(a) >= Perks.sizeMultiplier(b) then a else b
			pedestal.tickFrac = 0
		else
			pedestal.rarity = nil
			pedestal.mutation = nil
			pedestal.size = nil
			pedestal.completedCycles = 0
			pedestal.tickFrac = 0
			pedestal.mutationProgress = 0
			pedestal.mutationBoost = false
		end
	end
	return outRarity, success
end

function FuseService.fuse(player: Player, rarity: string): boolean
	local state = PlayerState.get(player)
	if state.plotIndex == nil or player:GetAttribute("ProfileLoaded") ~= true then
		return false
	end
	local result = Fuse.nextRarity(rarity)
	if result == nil then
		Remotes.get("TutorialToast"):FireClient(player, "That rarity can't be fused any higher")
		return false
	end
	if not Perks.rarityUnlocked(result, state.rebirths, SkillService.level(state, "Cultivation")) then
		Remotes.get("TutorialToast"):FireClient(player, `{result} cores are locked - rebirth / level Cultivation first`)
		return false
	end
	local plan, reason = FuseService.plan(state, rarity)
	if not plan then
		Remotes.get("TutorialToast"):FireClient(player, `Can't fuse: {reason}`)
		return false
	end
	local stats = SkillService.stats(state)
	local fee = Perks.discounted(Fuse.fee(state.rebirths, PlayerState.incomeRate(state)), stats)
	if not PlayerState.spendCash(state, fee) then
		Remotes.get("TutorialToast"):FireClient(player, "Not enough cash for the fuse fee")
		return false
	end
	local outRarity, success = FuseService.apply(state, plan, rarity, Random.new(os.clock() * 1e6))
	local plotIndex = state.plotIndex :: number
	for _, slot in plan.inputs do
		local pedestal = state.pedestals[slot]
		if slot == plan.target then
			CoreSystem.setPedestalCore(
				plotIndex,
				slot,
				pedestal.rarity :: any,
				pedestal.mutation,
				pedestal.level,
				pedestal.size
			)
		else
			CoreSystem.clearPedestalVisual(plotIndex, slot)
		end
	end
	local tier = Config.Rarities[rarity :: Types.Rarity].tier
	SkillService.addXp(player, "Alchemy", Config.Fuse.Xp + 20 * tier)
	SkillService.addCommerceXp(player, fee)
	CollectionIndex.onCoreHatched(player, state, outRarity :: any, state.pedestals[plan.target].mutation)
	QuestService.record(player, "buy")
	FXService.purchase(player)
	if success then
		Remotes.get("TutorialToast"):FireClient(player, `FUSED! You made a {outRarity} core`)
		if CoreSystem.shouldAnnounce(outRarity :: any) then
			Remotes.get("TutorialToast"):FireAllClients(`{player.Name} fused a {outRarity} core!`)
		end
	else
		Remotes.get("TutorialToast"):FireClient(player, `The fuse fizzled - you kept one {rarity} core`)
	end
	print(
		`[FuseService] {player.Name} fused 3x {rarity} -> {outRarity} ({if success then "success" else "fail"}, fee {fee})`
	)
	return true
end

function FuseService.init()
	task.spawn(function()
		Remotes.get("FuseCores").OnServerEvent:Connect(function(player, rarity)
			if type(rarity) == "string" and (Config.Rarities :: any)[rarity] then
				FuseService.fuse(player, rarity)
			end
		end)
	end)
end

return FuseService
