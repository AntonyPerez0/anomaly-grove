--!strict
-- Free rewards (M9-10): redeemable codes and a one-time group-join reward.
-- Remotes: RedeemCode(text), ClaimGroupReward(). Both are once per account
-- (saved in state.codes), rate-limited, and pay at least N seconds of income.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)
local FXService = require(script.Parent.FXService)

local RewardService = {}

type Reward = { base: number, seconds: number, groveSeeds: number }

local lastTry: { [Player]: number } = {}
local groupPending: { [Player]: boolean } = {}

-- Security (2026-10-18 audit): nothing pays out before the saved profile loaded
-- (its redeemed codes are not known yet).
local function profileReady(player: Player): boolean
	return player:GetAttribute("ProfileLoaded") == true
end

-- Pure: normalise a typed code ("  grove " -> "GROVE"); nil when it can't be one.
function RewardService.normalize(text: string): string?
	local code = string.upper((string.gsub(text, "%s", "")))
	if #code == 0 or #code > 24 or string.find(code, "[^%w]") then
		return nil
	end
	return code
end

-- Pure: may this state redeem `code`? Returns (reward, nil) or (nil, reason).
function RewardService.check(state: Types.PlayerState, code: string): (Reward?, string?)
	local reward = Config.FreeRewards.Codes[code]
	if not reward then
		return nil, "That code doesn't exist"
	end
	if state.codes[code] then
		return nil, "You already used that code"
	end
	return reward, nil
end

local function pay(player: Player, state: Types.PlayerState, reward: Reward): number
	local cash = Perks.scaledReward(reward.base, state.rebirths, PlayerState.incomeRate(state), reward.seconds)
	PlayerState.addCash(state, cash)
	local capacity = Config.Seeds.MaxCarriedSeeds + math.floor(Perks.get(SkillService.stats(state), "seedBag"))
	local seeds = math.min(reward.groveSeeds, math.max(0, capacity - PlayerState.seedCount(state)))
	if seeds > 0 then
		state.groveSeeds += seeds
		player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
	end
	FXService.purchase(player)
	return cash
end

local function publish(player: Player, state: Types.PlayerState)
	player:SetAttribute("GroupRewardClaimed", state.codes.group == true)
end

function RewardService.redeem(player: Player, text: string): boolean
	local now = os.clock()
	if lastTry[player] and now - lastTry[player] < Config.FreeRewards.RedeemCooldown then
		return false
	end
	lastTry[player] = now
	if not profileReady(player) then
		return false
	end
	local state = PlayerState.get(player)
	local code = RewardService.normalize(text)
	if not code then
		Remotes.get("TutorialToast"):FireClient(player, "That code doesn't exist")
		return false
	end
	local reward, reason = RewardService.check(state, code)
	if not reward then
		Remotes.get("TutorialToast"):FireClient(player, reason or "That code doesn't exist")
		return false
	end
	state.codes[code] = true
	local cash = pay(player, state, reward)
	Remotes.get("TutorialToast"):FireClient(player, `Code {code} redeemed! +${cash}`)
	print(`[RewardService] {player.Name} redeemed {code} (+{cash})`)
	return true
end

function RewardService.claimGroup(player: Player): boolean
	local groupId = Config.FreeRewards.GroupId
	local now = os.clock()
	-- Security (2026-10-18 audit, CRITICAL): IsInGroupAsync yields, so spammed
	-- requests all passed the "already claimed" check before any set it. One
	-- request in flight per player, a cooldown, and a re-check after the yield.
	if groupPending[player] or (lastTry[player] and now - lastTry[player] < Config.FreeRewards.RedeemCooldown) then
		return false
	end
	lastTry[player] = now
	if not profileReady(player) then
		return false
	end
	local state = PlayerState.get(player)
	if groupId <= 0 or state.codes.group then
		return false
	end
	groupPending[player] = true
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	groupPending[player] = nil
	if state.codes.group or not player.Parent then
		return false
	end
	if not ok or not inGroup then
		Remotes.get("TutorialToast"):FireClient(player, "Join the group first, then claim!")
		return false
	end
	state.codes.group = true
	local cash = pay(player, state, Config.FreeRewards.Group)
	publish(player, state)
	Remotes.get("TutorialToast"):FireClient(player, `Thanks for joining the group! +${cash}`)
	return true
end

function RewardService.init()
	task.spawn(function()
		Remotes.get("RedeemCode").OnServerEvent:Connect(function(player, text)
			if type(text) == "string" and #text <= 64 then
				RewardService.redeem(player, text)
			end
		end)
		Remotes.get("ClaimGroupReward").OnServerEvent:Connect(function(player)
			RewardService.claimGroup(player)
		end)
	end)
	-- Mirror the group flag once the profile has loaded (DataService sets codes).
	local function hook(player: Player)
		task.delay(3, function()
			local state = PlayerState.peek(player)
			if state then
				publish(player, state)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTry[player] = nil
		groupPending[player] = nil
	end)
end

return RewardService
