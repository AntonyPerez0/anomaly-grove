--!strict
-- Milestone badges (M7-05): one-time cash rewards for long-term goals (first heist,
-- night streaks, rebirth, index completion). Progress is derived from stats the
-- profile already stores; only the claimed ids persist. A 5 s poll is cheap and
-- means no gameplay system needs a hook.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local Perks = require(ReplicatedStorage.Shared.Perks)

local MilestoneService = {}

local POLL_SECONDS = 5

export type Milestone = {
	id: string,
	metric: string,
	goal: number,
	title: string,
	reward: number,
	seconds: number, -- at least this many seconds of income
}

local function metricValue(state: Types.PlayerState, metric: string): number
	if metric == "coresStolen" then
		return state.coresStolen
	elseif metric == "nightStreak" then
		return state.nightStreak
	elseif metric == "rebirths" then
		return state.rebirths
	elseif metric == "discovered" then
		local count = 0
		for _ in state.indexDiscovered do
			count += 1
		end
		return count
	end
	return 0
end

function MilestoneService.rewardFor(milestone: Milestone, rebirths: number, income: number?): number
	return Perks.scaledReward(milestone.reward, rebirths, income, milestone.seconds)
end

-- Pure: milestones reached but not yet claimed.
function MilestoneService.pending(state: Types.PlayerState): { Milestone }
	local result: { Milestone } = {}
	for _, milestone in Config.Milestones :: { Milestone } do
		if not state.milestones[milestone.id] and metricValue(state, milestone.metric) >= milestone.goal then
			table.insert(result, milestone)
		end
	end
	return result
end

-- Claims every pending milestone: marks, pays cash. Returns the claimed list.
function MilestoneService.claimState(state: Types.PlayerState): { Milestone }
	local claimed = MilestoneService.pending(state)
	for _, milestone in claimed do
		state.milestones[milestone.id] = true
		PlayerState.addCash(state, MilestoneService.rewardFor(milestone, state.rebirths, PlayerState.incomeRate(state)))
	end
	return claimed
end

local function check(player: Player)
	local state = PlayerState.peek(player)
	if not state or state.quests == nil then
		return -- profile not loaded yet
	end
	for _, milestone in MilestoneService.claimState(state) do
		local reward = MilestoneService.rewardFor(milestone, state.rebirths, PlayerState.incomeRate(state))
		Remotes
			.get("TutorialToast") -- reuse the generic toast channel (text only)
			:FireClient(player, `Badge: {milestone.title}! +${reward}`)
		print(`[MilestoneService] {player.Name} earned '{milestone.id}' (+${reward})`)
	end
end

function MilestoneService.init()
	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in Players:GetPlayers() do
				check(player)
			end
		end
	end)
end

return MilestoneService
