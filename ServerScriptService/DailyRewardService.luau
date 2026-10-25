--!strict
-- Daily login reward (M6-03): a 7-day streak calendar. Claim once per UTC day; the
-- next claim continues the streak if it is the very next day, otherwise the streak
-- restarts at day 1. Day 7 also grants a Grove Heart seed (cash instead when the
-- player's hands are full). Free rewards only - no paid random items.
-- Status replicates as a JSON attribute ("Daily"); pure rules exported for DailySpec.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)

local DailyRewardService = {}

local CYCLE = #Config.Daily.Rewards
local FULL_HANDS_BONUS = 2000 -- replaces the day-7 seed when no hand slot is free

function DailyRewardService.dayNumber(now: number): number
	return math.floor(now / 86400)
end

export type Status = { canClaim: boolean, nextStreak: number, dayIndex: number }

-- What claiming today would give. Pure.
function DailyRewardService.status(daily: Types.DailyState, today: number): Status
	if daily.lastClaimDay == today then
		local dayIndex = ((math.max(daily.streak, 1) - 1) % CYCLE) + 1
		return { canClaim = false, nextStreak = daily.streak, dayIndex = dayIndex }
	end
	local nextStreak = if daily.lastClaimDay == today - 1 then daily.streak + 1 else 1
	return { canClaim = true, nextStreak = nextStreak, dayIndex = ((nextStreak - 1) % CYCLE) + 1 }
end

-- At least RewardSeconds[day] of income (2026-10-18 review), never below the
-- flat reward x rebirth multiplier.
function DailyRewardService.rewardFor(dayIndex: number, rebirths: number, income: number?): number
	local base = Config.Daily.Rewards[dayIndex] or Config.Daily.Rewards[1]
	local seconds = Config.Daily.RewardSeconds[dayIndex] or Config.Daily.RewardSeconds[1]
	return Perks.scaledReward(base, rebirths, income, seconds)
end

-- Apply a claim to the state. Returns (ok, dayIndexOrReason, cash, gotSeed).
function DailyRewardService.claimState(
	state: Types.PlayerState,
	today: number
): (boolean, number | string, number, boolean)
	local daily = state.daily
	if not daily then
		return false, "not loaded", 0, false
	end
	local status = DailyRewardService.status(daily, today)
	if not status.canClaim then
		return false, "already claimed today", 0, false
	end
	state.daily = { lastClaimDay = today, streak = status.nextStreak }
	local cash = DailyRewardService.rewardFor(status.dayIndex, state.rebirths, PlayerState.incomeRate(state))
	local gotSeed = false
	if status.dayIndex == Config.Daily.GroveSeedDay then
		-- Seed bag includes the Foraging bonus (fix: used the base 3 before).
		local bag = Config.Seeds.MaxCarriedSeeds + math.floor(Perks.get(SkillService.stats(state), "seedBag"))
		if PlayerState.seedCount(state) < bag then
			state.groveSeeds += 1
			gotSeed = true
		else
			cash += FULL_HANDS_BONUS
		end
	end
	PlayerState.addCash(state, cash)
	return true, status.dayIndex, cash, gotSeed
end

-- Runtime -------------------------------------------------------------------------

local function publish(player: Player, state: Types.PlayerState)
	local daily = state.daily
	if not daily then
		return
	end
	local status = DailyRewardService.status(daily, DailyRewardService.dayNumber(os.time()))
	local encoded = HttpService:JSONEncode({
		canClaim = status.canClaim,
		dayIndex = status.dayIndex,
		streak = daily.streak,
		rewards = (function()
			local list = {}
			for i = 1, CYCLE do
				list[i] = DailyRewardService.rewardFor(i, state.rebirths, PlayerState.incomeRate(state))
			end
			return list
		end)(),
	})
	if player:GetAttribute("Daily") ~= encoded then
		player:SetAttribute("Daily", encoded)
	end
end

-- Push status right after the profile loads (the loop below only re-checks every 5 s).
function DailyRewardService.publishNow(player: Player)
	local state = PlayerState.peek(player)
	if state then
		publish(player, state)
	end
end

function DailyRewardService.init()
	local lastClaimAt: { [Player]: number } = {}
	Remotes.get("ClaimDaily").OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastClaimAt[player] or 0) < 1 then
			return -- rate limit
		end
		lastClaimAt[player] = now
		local state = PlayerState.peek(player)
		if not state then
			return
		end
		local ok, dayOrReason, cash, gotSeed =
			DailyRewardService.claimState(state, DailyRewardService.dayNumber(os.time()))
		if ok then
			SkillService.addXp(player, "Commerce", Config.Skills.Xp.dailyClaim)
			if gotSeed then
				player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
			end
			print(
				`[DailyReward] {player.Name} claimed day {dayOrReason}: ${cash}{if gotSeed
					then " + Grove Heart seed"
					else ""}`
			)
			Remotes.get("Juice"):FireClient(player, "Rebirth") -- big sting + confetti
		else
			print(`[DailyReward] {player.Name} claim rejected: {dayOrReason}`)
		end
		publish(player, state)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastClaimAt[player] = nil
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local state = PlayerState.peek(player)
				if state and state.daily ~= nil then
					publish(player, state)
				end
			end
			task.wait(5)
		end
	end)
end

return DailyRewardService
