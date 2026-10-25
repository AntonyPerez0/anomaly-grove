--!strict
-- Daily login streak (M6-03): once per day, consecutive days advance, gaps reset,
-- day 7 grants a Grove Heart seed (or cash when hands are full), cycle wraps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(ServerScriptService.PlayerState)
local Daily = require(ServerScriptService.DailyRewardService)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("DailyRewardService", function()
		t.it("first ever claim is day 1 and pays Rewards[1]", function()
			local state = PlayerState.createDefault()
			state.daily = { lastClaimDay = -1, streak = 0 }
			local ok, day, cash = Daily.claimState(state, 1000)
			t.truthy(ok)
			t.equal(day, 1)
			t.equal(cash, Config.Daily.Rewards[1])
			t.equal(state.cash, cash)
		end)

		t.it("only once per day", function()
			local state = PlayerState.createDefault()
			state.daily = { lastClaimDay = 1000, streak = 1 }
			local ok, reason = Daily.claimState(state, 1000)
			t.equal(ok, false)
			t.equal(reason, "already claimed today")
		end)

		t.it("consecutive days advance, a gap resets to day 1", function()
			t.equal(Daily.status({ lastClaimDay = 999, streak = 3 }, 1000).dayIndex, 4)
			t.equal(Daily.status({ lastClaimDay = 997, streak = 3 }, 1000).dayIndex, 1)
		end)

		t.it("day 7 grants a Grove Heart seed, or cash when hands are full", function()
			local state = PlayerState.createDefault()
			state.daily = { lastClaimDay = 999, streak = 6 }
			local ok, day, _, gotSeed = Daily.claimState(state, 1000)
			t.truthy(ok)
			t.equal(day, 7)
			t.truthy(gotSeed)
			t.equal(state.groveSeeds, 1)
			local full = PlayerState.createDefault()
			full.daily = { lastClaimDay = 999, streak = 6 }
			full.seedsCarried = Config.Seeds.MaxCarriedSeeds
			local _, _, cash, seed = Daily.claimState(full, 1000)
			t.equal(seed, false)
			t.equal(cash, Config.Daily.Rewards[7] + 2000)
		end)

		t.it("the calendar wraps after 7 days", function()
			t.equal(Daily.status({ lastClaimDay = 999, streak = 7 }, 1000).dayIndex, 1)
			t.equal(Daily.status({ lastClaimDay = 999, streak = 8 }, 1000).dayIndex, 2)
		end)
	end)
end
