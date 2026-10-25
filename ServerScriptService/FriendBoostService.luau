--!strict
-- Friend boost (M6-05): each friend playing in the same server adds
-- FriendBoost.PerFriend to the player's core income, up to FriendBoost.Max.
-- Friendship checks yield, so they run in the background on join/leave and are
-- cached per pair. The percent replicates as the "FriendBoost" attribute (HUD).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local FriendBoostService = {}

local multipliers: { [Player]: number } = {}
local friendCache: { [string]: boolean } = {}

-- Pure: income multiplier for `friends` friends in the server.
function FriendBoostService.multiplierFor(friends: number): number
	return 1 + math.min(math.max(friends, 0) * Config.FriendBoost.PerFriend, Config.FriendBoost.Max)
end

function FriendBoostService.multiplier(player: Player?): number
	return if player then multipliers[player] or 1 else 1
end

local function pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

local function areFriends(a: Player, b: Player): boolean
	local key = pairKey(a.UserId, b.UserId)
	local cached = friendCache[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function()
		return a:IsFriendsWith(b.UserId)
	end)
	local friends = ok and result == true
	if ok then
		friendCache[key] = friends -- only cache real answers (retry on failures)
	end
	return friends
end

local function recompute()
	local everyone = Players:GetPlayers()
	for _, player in everyone do
		local count = 0
		for _, other in everyone do
			if other ~= player and other.Parent and areFriends(player, other) then
				count += 1
			end
		end
		local multiplier = FriendBoostService.multiplierFor(count)
		multipliers[player] = multiplier
		local percent = math.floor((multiplier - 1) * 100 + 0.5)
		if player:GetAttribute("FriendBoost") ~= percent then
			player:SetAttribute("FriendBoost", percent)
		end
	end
end

function FriendBoostService.init()
	Players.PlayerAdded:Connect(function()
		task.spawn(recompute)
	end)
	Players.PlayerRemoving:Connect(function(player)
		multipliers[player] = nil
		task.defer(recompute)
	end)
	task.spawn(recompute)
end

return FriendBoostService
