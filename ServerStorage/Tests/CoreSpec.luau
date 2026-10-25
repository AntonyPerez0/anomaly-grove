--!strict
-- Core economy math (M1-06): rarity rolls, rates and cash tick aggregation.
local ServerScriptService = game:GetService("ServerScriptService")
local CoreSystem = require(ServerScriptService.CoreSystem)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("CoreSystem", function()
		t.it("consumeSeed uses Grove Heart seeds first, then regular (M3-03)", function()
			local empty = PlayerState.createDefault()
			t.equal(CoreSystem.consumeSeed(empty), nil)

			local regular = PlayerState.createDefault()
			regular.seedsCarried = 2
			t.equal(CoreSystem.consumeSeed(regular), "regular")
			t.equal(regular.seedsCarried, 1)
			t.equal(regular.groveSeeds, 0)

			local groveOnly = PlayerState.createDefault()
			groveOnly.groveSeeds = 1
			t.equal(CoreSystem.consumeSeed(groveOnly), "grove")
			t.equal(groveOnly.groveSeeds, 0)
			t.equal(groveOnly.seedsCarried, 0)

			local both = PlayerState.createDefault()
			both.seedsCarried = 2
			both.groveSeeds = 1
			t.equal(CoreSystem.consumeSeed(both), "grove") -- grove seeds are the boosted kind
			t.equal(CoreSystem.consumeSeed(both), "regular")
			t.equal(both.groveSeeds, 0)
			t.equal(both.seedsCarried, 1)
		end)

		t.it("rollRarity returns valid rarities", function()
			local valid = { Sprout = true, Amber = true, Frost = true, Ember = true, Void = true, Celestial = true }
			for seed = 1, 50 do
				local rarity = CoreSystem.rollRarity(Random.new(seed * 7919))
				t.truthy((valid :: { [string]: boolean })[rarity], "invalid rarity rolled: " .. rarity)
			end
		end)

		t.it("rollRarity proportions roughly match Config chances", function()
			local counts: { [string]: number } = {}
			local rolls = 100000
			local rng = Random.new(42)
			for _ = 1, rolls do
				local rarity = CoreSystem.rollRarity(rng)
				counts[rarity] = (counts[rarity] or 0) + 1
			end
			t.near(counts.Sprout / rolls, 0.62, 0.02)
			t.near(counts.Amber / rolls, 0.25, 0.02)
			t.truthy((counts.Void or 0) > 0, "Void should occur in 100k rolls")
			t.truthy((counts.Celestial or 0) > 0, "Celestial should occur in 100k rolls")
		end)

		t.it("coreRate applies the pedestal cycle bonus", function()
			local function pedestal(rarity: string, cycles: number): any
				return {
					rarity = rarity :: any,
					mutation = nil,
					hatchAt = nil,
					tickFrac = 0,
					completedCycles = cycles,
					vaultLocked = false,
					mutationProgress = 0,
					mutationBoost = false,
					level = 1,
				}
			end
			t.near(CoreSystem.coreRate(pedestal("Sprout", 0)), 1)
			t.near(CoreSystem.coreRate(pedestal("Sprout", 2)), 1.2)
			t.near(CoreSystem.coreRate(pedestal("Void", 0)), 50)
			t.near(CoreSystem.coreRate(pedestal("Celestial", 1)), 132)
		end)

		t.it("tickPedestal pays whole cash and keeps fractions", function()
			local state = PlayerState.createDefault()
			local pedestal = PlayerState.newPedestal()
			pedestal.rarity = "Amber" -- 3/s
			t.equal(CoreSystem.tickPedestal(state, pedestal, 1), 3)
			t.equal(state.cash, 3)
			t.equal(CoreSystem.tickPedestal(state, pedestal, 0.1), 0) -- fraction accumulates
			t.near(pedestal.tickFrac, 0.3)
			for _ = 1, 3 do
				CoreSystem.tickPedestal(state, pedestal, 0.3)
			end
			-- 2.0 s total income = 6.0; whole 5 paid, ~1.0 still in fractional reserve.
			t.equal(state.cash, 5)
			t.near(pedestal.tickFrac, 1, 0.05)
			-- Conservation: paid + fractional reserve ~= total income (no cash created or lost).
			t.near(state.cash + pedestal.tickFrac, 6, 0.05)
		end)

		t.it("tickPedestal pays nothing while incubating", function()
			local state = PlayerState.createDefault()
			local pedestal = PlayerState.newPedestal()
			pedestal.rarity = "Ember"
			pedestal.hatchAt = os.clock() + 30
			t.equal(CoreSystem.tickPedestal(state, pedestal, 1), 0)
			t.equal(state.cash, 0)
		end)
	end)
end
