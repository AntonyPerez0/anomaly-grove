--!strict
-- Grove Pass (M8-10): a free 50-level seasonal track. Pass XP is a share of every
-- skill XP gain (so everything you do counts); each level pays a reward you claim
-- in the Pass panel: cash worth minutes of your income, Rebirth Tokens every 5th
-- level, a big token bonus at the end. A new Config.Pass.Season resets the track.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)
local FXService = require(script.Parent.FXService)

local PassService = {}

local CLAIM_COOLDOWN = 0.3
local lastClaimAt: { [Player]: number } = {}

-- Pure: reward for `level` given the player's income per second.
function PassService.rewardFor(level: number, incomePerSecond: number): { cash: number, tokens: number }
	local cfg = Config.Pass
	local cash = math.max(500, math.floor(incomePerSecond * (cfg.CashSecondsBase + cfg.CashSecondsStep * level)))
	local tokens = if level % cfg.TokenEvery == 0 then 1 else 0
	if level == cfg.Levels then
		tokens += cfg.FinalTokens
	end
	return { cash = cash, tokens = tokens }
end

-- Pure: start a fresh track when the season changed.
function PassService.ensureSeason(state: Types.PlayerState): boolean
	if state.pass.season ~= Config.Pass.Season then
		state.pass = { season = Config.Pass.Season, xp = 0, claimed = {} }
		return true
	end
	return false
end

-- Pure claim: (ok, reasonOrReward).
function PassService.claimState(state: Types.PlayerState, level: number, incomePerSecond: number): (boolean, any)
	if level < 1 or level > Config.Pass.Levels then
		return false, "no such level"
	end
	if level > Perks.passLevel(state.pass.xp) then
		return false, "level not reached"
	end
	local key = tostring(level)
	if state.pass.claimed[key] then
		return false, "already claimed"
	end
	state.pass.claimed[key] = true
	local reward = PassService.rewardFor(level, incomePerSecond)
	PlayerState.addCash(state, reward.cash)
	state.tokens += reward.tokens
	return true, reward
end

function PassService.publish(player: Player, state: Types.PlayerState)
	player:SetAttribute("PassXp", math.floor(state.pass.xp))
	player:SetAttribute("PassClaimed", HttpService:JSONEncode(state.pass.claimed))
end

-- Called after the profile loads.
function PassService.onProfileLoaded(player: Player, state: Types.PlayerState)
	PassService.ensureSeason(state)
	PassService.publish(player, state)
end

function PassService.init()
	SkillService.onXpGained(function(player, state, _skill, gained)
		local before = Perks.passLevel(state.pass.xp)
		state.pass.xp += gained * Config.Pass.PassXpShare
		player:SetAttribute("PassXp", math.floor(state.pass.xp))
		local after = Perks.passLevel(state.pass.xp)
		if after > before then
			Remotes.get("TutorialToast"):FireClient(player, `Grove Pass level {after}! Claim your reward`)
		end
	end)

	Remotes.get("ClaimPass").OnServerEvent:Connect(function(player, level)
		if type(level) ~= "number" or level ~= math.floor(level) then
			return
		end
		local now = os.clock()
		if now - (lastClaimAt[player] or 0) < CLAIM_COOLDOWN then
			return
		end
		lastClaimAt[player] = now
		local state = PlayerState.peek(player)
		if not state or state.quests == nil then
			return
		end
		local rate = player:GetAttribute("IncomeRate")
		local ok, result = PassService.claimState(state, level, if type(rate) == "number" then rate else 0)
		if ok then
			PassService.publish(player, state)
			player:SetAttribute("Tokens", state.tokens)
			FXService.purchase(player)
			print(`[PassService] {player.Name} claimed pass level {level}: ${result.cash} +{result.tokens} tokens`)
		else
			print(`[PassService] {player.Name} pass claim {level} rejected: {result}`)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastClaimAt[player] = nil
	end)
end

return PassService
