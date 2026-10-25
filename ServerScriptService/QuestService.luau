--!strict
-- Daily quests (M6-02). Three quests per UTC day, rolled deterministically from the
-- player's id + the day so a rejoin shows the same set. Progress is recorded by the
-- systems that own each action (harvest, plant, earn, night, buy, hatch); claiming
-- pays a server-computed cash reward. The list replicates as a JSON attribute
-- ("Quests") for the client UI. Pure rules are exported for QuestSpec.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)

local QuestService = {}

local CLAIM_COOLDOWN = 0.5
local lastClaimAt: { [Player]: number } = {}

-- UTC day number (quests reset at 00:00 UTC).
function QuestService.dayNumber(now: number): number
	return math.floor(now / 86400)
end

-- Pick Quests.PerDay distinct pool entries for (day, userId). Pure + deterministic.
function QuestService.roll(day: number, userId: number): { Types.Quest }
	local pool = Config.Quests.Pool
	local order: { number } = {}
	for i = 1, #pool do
		order[i] = i
	end
	local rng = Random.new(day * 7919 + (userId % 100003))
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local list: { Types.Quest } = {}
	for k = 1, math.min(Config.Quests.PerDay, #pool) do
		local def = pool[order[k]]
		table.insert(list, { id = def.id, goal = def.goal, progress = 0, claimed = false })
	end
	return list
end

-- Re-roll when the stored day is stale. Returns true when the list changed.
function QuestService.ensureDay(state: Types.PlayerState, day: number, userId: number, income: number?): boolean
	local quests = state.quests
	if quests and quests.day == day and #quests.list > 0 then
		return false
	end
	local list = QuestService.roll(day, userId)
	-- "Earn $N" grows with the player: at least goalSeconds of income at roll time.
	for _, quest in list do
		for _, def in Config.Quests.Pool do
			local goalSeconds = (def :: any).goalSeconds
			if def.id == quest.id and goalSeconds then
				quest.goal = math.max(quest.goal, math.floor((income or 0) * goalSeconds))
			end
		end
	end
	state.quests = { day = day, list = list }
	return true
end

-- Add progress to every unclaimed quest of `kind`. Returns true when anything moved.
function QuestService.recordState(state: Types.PlayerState, kind: string, amount: number): boolean
	local quests = state.quests
	if not quests or amount <= 0 then
		return false
	end
	local changed = false
	for _, quest in quests.list do
		if quest.id == kind and not quest.claimed and quest.progress < quest.goal then
			quest.progress = math.min(quest.goal, quest.progress + amount)
			changed = true
		end
	end
	return changed
end

-- Rewards scale with the rebirth cash multiplier (M8-06) so quests stay worth doing,
-- plus the quest bonus perk (Commerce unlocks + Bounty node).
function QuestService.rewardFor(questId: string, rebirths: number, bonus: number?, income: number?): number
	for _, def in Config.Quests.Pool do
		if def.id == questId then
			-- At least def.seconds of income (2026-10-18 review: flat rewards were
			-- worth under a second of income by mid-game).
			return math.floor(
				Perks.scaledReward(def.reward, rebirths, income, (def :: any).seconds) * (1 + (bonus or 0))
			)
		end
	end
	return 0
end

-- Claim quest `index`. Returns (ok, rewardOrReason). Pure apart from cash.
function QuestService.claimState(state: Types.PlayerState, index: number): (boolean, number | string)
	local quests = state.quests
	local quest = quests and quests.list[index]
	if not quest then
		return false, "no such quest"
	end
	if quest.claimed then
		return false, "already claimed"
	end
	if quest.progress < quest.goal then
		return false, "not complete"
	end
	quest.claimed = true
	local reward = QuestService.rewardFor(
		quest.id,
		state.rebirths,
		Perks.get(SkillService.stats(state), "questBonus"),
		PlayerState.incomeRate(state)
	)
	PlayerState.addCash(state, reward)
	return true, reward
end

-- Runtime -------------------------------------------------------------------------

local function publish(player: Player, state: Types.PlayerState)
	local quests = state.quests
	if not quests then
		return
	end
	local rows = {}
	for _, quest in quests.list do
		table.insert(rows, {
			id = quest.id,
			goal = quest.goal,
			progress = math.floor(quest.progress),
			claimed = quest.claimed,
			reward = QuestService.rewardFor(
				quest.id,
				state.rebirths,
				Perks.get(SkillService.stats(state), "questBonus"),
				PlayerState.incomeRate(state)
			),
		})
	end
	local encoded = HttpService:JSONEncode(rows) -- local encoding only, no HTTP request
	if player:GetAttribute("Quests") ~= encoded then
		player:SetAttribute("Quests", encoded)
	end
end

-- Systems call this when the action happens (amount defaults to 1).
function QuestService.record(player: Player?, kind: string, amount: number?)
	if not player then
		return
	end
	local state = PlayerState.peek(player)
	if not state or not state.quests then
		return
	end
	if QuestService.recordState(state, kind, amount or 1) then
		publish(player, state)
	end
end

-- Roll (if needed) + publish right after the profile loads.
function QuestService.publishNow(player: Player)
	local state = PlayerState.peek(player)
	if state and state.quests ~= nil then
		QuestService.ensureDay(state, QuestService.dayNumber(os.time()), player.UserId, PlayerState.incomeRate(state))
		publish(player, state)
	end
end

function QuestService.init()
	Remotes.get("ClaimQuest").OnServerEvent:Connect(function(player: Player, index: any)
		-- Validate: integer index in range, rate limited, state loaded.
		if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > Config.Quests.PerDay then
			return
		end
		local now = os.clock()
		if now - (lastClaimAt[player] or 0) < CLAIM_COOLDOWN then
			return
		end
		lastClaimAt[player] = now
		local state = PlayerState.peek(player)
		if not state then
			return
		end
		local ok, result = QuestService.claimState(state, index)
		if ok then
			print(`[QuestService] {player.Name} claimed quest {index} for ${result}`)
			SkillService.addXp(player, "Commerce", Config.Skills.Xp.questClaim)
			Remotes.get("Juice"):FireClient(player, "Purchase") -- coin jingle + confetti
		else
			print(`[QuestService] {player.Name} claim {index} rejected: {result}`)
		end
		publish(player, state)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastClaimAt[player] = nil
	end)

	-- Day roll + publish loop (cheap: string compare before any attribute write).
	task.spawn(function()
		while true do
			local day = QuestService.dayNumber(os.time())
			for _, player in Players:GetPlayers() do
				local state = PlayerState.peek(player)
				-- Wait for the profile load (DataService sets quests from the save).
				if state and state.quests ~= nil then
					QuestService.ensureDay(state, day, player.UserId, PlayerState.incomeRate(state))
					publish(player, state)
				end
			end
			task.wait(5)
		end
	end)
end

return QuestService
