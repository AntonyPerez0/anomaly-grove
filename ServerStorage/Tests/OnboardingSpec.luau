--!strict
-- M7: first-five-minutes floor, announce threshold, offline teaser, milestone badges.
local ServerScriptService = game:GetService("ServerScriptService")
local CoreSystem = require(ServerScriptService.CoreSystem)
local Milestones = require(ServerScriptService.MilestoneService)
local OfflineGrowth = require(ServerScriptService.OfflineGrowth)
local PlayerState = require(ServerScriptService.PlayerState)
local MonetizationService = require(ServerScriptService.MonetizationService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("first five minutes (M7-01)", function()
		t.it("first seed hatches fast, later seeds use the normal duration", function()
			t.equal(CoreSystem.incubationSeconds(false), Config.Onboarding.FirstHatchSeconds)
			t.equal(CoreSystem.incubationSeconds(true), Config.Incubation.Duration)
		end)
		t.it("first core is at least Amber, other cores are untouched", function()
			t.equal(CoreSystem.applyFirstCoreFloor("Sprout", true), "Amber")
			t.equal(CoreSystem.applyFirstCoreFloor("Sprout", false), "Sprout")
			t.equal(CoreSystem.applyFirstCoreFloor("Ember", true), "Ember")
		end)
	end)

	t.describe("announcements + teaser (M7-02/03)", function()
		t.it("only Void and Celestial hatches are announced", function()
			t.truthy(CoreSystem.shouldAnnounce("Void"))
			t.truthy(CoreSystem.shouldAnnounce("Celestial"))
			t.truthy(not CoreSystem.shouldAnnounce("Ember"))
		end)
		t.it("nextHatchSeconds picks the soonest incubating seed", function()
			local a = PlayerState.newPedestal()
			local b = PlayerState.newPedestal()
			a.hatchAt = 1000
			b.hatchAt = 1040
			t.equal(OfflineGrowth.nextHatchSeconds({ a, b }, 990), 10)
			t.equal(OfflineGrowth.nextHatchSeconds({ PlayerState.newPedestal() }, 0), 0)
			a.hatchAt = 1e9
			t.equal(OfflineGrowth.nextHatchSeconds({ a }, 0), 0)
		end)
	end)

	t.describe("MilestoneService (M7-05)", function()
		t.it("pays each milestone once, scaled by rebirths", function()
			local state = PlayerState.createDefault()
			t.equal(#Milestones.pending(state), 0)
			state.coresStolen = 1
			local first = Milestones.claimState(state)
			t.equal(#first, 1)
			t.equal(state.cash, 500)
			t.equal(#Milestones.claimState(state), 0)
			t.equal(state.cash, 500)
			state.rebirths = 2
			t.equal(Milestones.rewardFor(first[1], 2), math.floor(500 * 1.75 ^ 2))
		end)
		t.it("tracks index discoveries and night streaks", function()
			local state = PlayerState.createDefault()
			state.nightStreak = 3
			for i = 1, 5 do
				state.indexDiscovered["k" .. i] = true
			end
			t.equal(#Milestones.pending(state), 2) -- Night Owl + Collector
		end)
	end)
	t.describe("2x Cash pass (M7)", function()
		t.it("doubles income only when owned", function()
			t.equal(MonetizationService.doubleCashMultiplier(true), Config.DoubleCashMultiplier)
			t.equal(MonetizationService.doubleCashMultiplier(false), 1)
		end)
	end)
end
