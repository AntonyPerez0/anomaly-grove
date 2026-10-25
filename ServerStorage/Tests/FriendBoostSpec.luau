--!strict
-- Friend boost (M6-05): +10% per friend, capped at +40%, never below x1.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local CoreSystem = require(ServerScriptService.CoreSystem)
local FriendBoostService = require(ServerScriptService.FriendBoostService)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("FriendBoost", function()
		t.it("scales per friend and caps", function()
			t.equal(FriendBoostService.multiplierFor(0), 1)
			t.near(FriendBoostService.multiplierFor(2), 1 + 2 * Config.FriendBoost.PerFriend)
			t.near(FriendBoostService.multiplierFor(20), 1 + Config.FriendBoost.Max)
			t.equal(FriendBoostService.multiplierFor(-3), 1)
		end)

		t.it("tickPedestal applies the extra multiplier", function()
			local state = PlayerState.createDefault()
			local pedestal = state.pedestals[1]
			pedestal.rarity = "Frost" -- 8/s
			pedestal.completedCycles = 0
			t.equal(CoreSystem.tickPedestal(state, pedestal, 1, 1.25), 10)
		end)
	end)
end
