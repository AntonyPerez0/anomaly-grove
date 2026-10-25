--!strict
-- Mutation rules (M2-05 / GDD 5.3): rate multipliers x2/x10/x30, roll cadence
-- (every 300 s of pedestal lifetime, 2% day / 4% night), one mutation at a time.
local ServerScriptService = game:GetService("ServerScriptService")
local CoreSystem = require(ServerScriptService.CoreSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

local function hatchedPedestal(rarity: string, mutation: string?): any
	return {
		rarity = rarity,
		mutation = mutation,
		hatchAt = nil,
		tickFrac = 0,
		completedCycles = 0,
		vaultLocked = false,
		mutationProgress = 0,
	}
end

return function(t: TestKit.Context)
	t.describe("CoreSystem mutations", function()
		t.it("coreRate applies mutation multipliers x2/x10/x30", function()
			t.near(CoreSystem.coreRate(hatchedPedestal("Sprout", nil)), 1)
			t.near(CoreSystem.coreRate(hatchedPedestal("Sprout", "Gold")), 2)
			t.near(CoreSystem.coreRate(hatchedPedestal("Amber", "Void")), 30) -- 3 x 10
			t.near(CoreSystem.coreRate(hatchedPedestal("Frost", "Celestial")), 240) -- 8 x 30
		end)

		t.it("mutationTick accumulates progress and rolls only past the interval", function()
			local pedestal = hatchedPedestal("Sprout", nil)
			local rng = Random.new(1)
			-- 299 s of ticks: never rolls
			local rolled = nil
			for _ = 1, 299 do
				rolled = CoreSystem.mutationTick(pedestal, 1, false, rng)
				if rolled ~= nil then
					break
				end
			end
			t.equal(rolled, nil)
			t.near(pedestal.mutationProgress, 299)
			-- one more second crosses the interval: roll happens (chance 2%, this seed misses)
			rolled = CoreSystem.mutationTick(pedestal, 1, false, rng)
			t.near(pedestal.mutationProgress, 0) -- interval consumed either way
		end)

		t.it("night rolls use the doubled chance", function()
			-- Deterministic check: Config night chance is exactly 2x the day chance.
			t.near(Config.MutationNightChance, Config.MutationChance * 2)
			t.near(Config.MutationChance, 0.02)
			t.near(Config.MutationNightChance, 0.04)
		end)

		t.it("Grove Heart seeds roll at the night chance around the clock (M3-03)", function()
			-- Stub rng returning 0.03: below the night chance (0.04), above the day one (0.02).
			local stubRng = {
				NextNumber = function()
					return 0.03
				end,
			} :: any
			local day = hatchedPedestal("Sprout", nil)
			day.mutationProgress = Config.MutationRollInterval
			t.equal(CoreSystem.mutationTick(day, 1, false, stubRng), nil) -- 0.03 >= 0.02: no roll
			local boosted = hatchedPedestal("Sprout", nil)
			boosted.mutationBoost = true
			boosted.mutationProgress = Config.MutationRollInterval
			local rolled = CoreSystem.mutationTick(boosted, 1, false, stubRng) -- 0.03 < 0.04: rolls
			t.truthy(rolled ~= nil, "boosted pedestal should roll at the night chance")
			local night = hatchedPedestal("Sprout", nil)
			night.mutationProgress = Config.MutationRollInterval
			t.truthy(CoreSystem.mutationTick(night, 1, true, stubRng) ~= nil)
		end)

		t.it("incubating or empty pedestals never mutate", function()
			local incubating = hatchedPedestal("Amber", nil)
			incubating.hatchAt = os.clock() + 30
			t.equal(CoreSystem.mutationTick(incubating, 1000, true, Random.new(1)), nil)
			t.near(incubating.mutationProgress, 0)
			local empty = hatchedPedestal("Amber", nil)
			empty.rarity = nil
			t.equal(CoreSystem.mutationTick(empty, 1000, true, Random.new(1)), nil)
		end)

		t.it("rollMutation stays within the weighted set", function()
			local counts = { Gold = 0, Void = 0, Celestial = 0 }
			local rng = Random.new(7)
			for _ = 1, 1000 do
				counts[CoreSystem.rollMutation(rng)] += 1
			end
			-- 70/25/5 split: loose bounds keep the test stable.
			t.truthy(counts.Gold > 600 and counts.Gold < 800)
			t.truthy(counts.Void > 150 and counts.Void < 350)
			t.truthy(counts.Celestial > 0 and counts.Celestial < 150)
		end)

		t.it("applyMutation sets the mutation on a hatched core", function()
			local state = PlayerState.createDefault()
			state.pedestals[1] = hatchedPedestal("Sprout", nil)
			CoreSystem.applyMutation(state, 1, "Gold")
			t.equal(state.pedestals[1].mutation, "Gold")
			-- Empty pedestals are untouched.
			CoreSystem.applyMutation(state, 2, "Void")
			t.equal(state.pedestals[2], nil)
		end)
	end)
end
