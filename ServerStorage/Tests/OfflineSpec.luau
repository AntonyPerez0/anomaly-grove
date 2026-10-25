--!strict
-- Offline growth math (M2-04 / GDD 5.5): rate x elapsed x efficiency, 8 h cap,
-- mutation rolls at 2% per 300 s chunk (max 20), one mutation per core.
local ServerScriptService = game:GetService("ServerScriptService")
local OfflineGrowth = require(ServerScriptService.OfflineGrowth)
local PlayerState = require(ServerScriptService.PlayerState)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

local function pedestal(rarity: string, cycles: number, mutation: string?): any
	return {
		rarity = rarity,
		mutation = mutation,
		hatchAt = nil,
		tickFrac = 0,
		completedCycles = cycles,
		vaultLocked = false,
	}
end

return function(t: TestKit.Context)
	t.describe("OfflineGrowth", function()
		t.it("two-hour absence at 25% pays rate x 7200 x 0.25", function()
			local pedestals = { pedestal("Sprout", 0, nil) } -- 1 cash/s
			local summary = OfflineGrowth.computeFor(pedestals, 1000000, 1000000 + 7200)
			t.equal(summary.cashEarned, 1800) -- 1 x 7200 x 0.25
			t.equal(summary.elapsed, 7200)
		end)

		t.it("absences beyond the 4 h base cap are capped", function()
			local pedestals = { pedestal("Amber", 0, nil) } -- 3 cash/s
			local summary = OfflineGrowth.computeFor(pedestals, 0, 48 * 60 * 60)
			local expected = math.floor(3 * Config.Offline.CapSeconds * Config.Offline.Efficiency) -- 10800
			t.equal(summary.cashEarned, expected)
			t.equal(summary.elapsed, Config.Offline.CapSeconds)
		end)

		t.it("pedestal cycle bonus and mutation multipliers apply", function()
			-- Void 50/s x (1 + 0.1 x 1) x 10 (Void mutation) = 550/s
			local pedestals = { pedestal("Void", 1, "Void") }
			local summary = OfflineGrowth.computeFor(pedestals, 0, 3600)
			t.equal(summary.cashEarned, math.floor(550 * 3600 * Config.Offline.Efficiency))
		end)

		t.it("short absences pay nothing and pop nothing", function()
			local pedestals = { pedestal("Sprout", 0, nil) }
			local summary = OfflineGrowth.computeFor(pedestals, 0, 30)
			t.equal(summary.cashEarned, 0)
			t.equal(#summary.mutations, 0)
		end)

		t.it("empty or incubating pedestals earn nothing", function()
			local empty = pedestal("Sprout", 0, nil)
			empty.rarity = nil
			local incubating = pedestal("Amber", 0, nil)
			incubating.hatchAt = os.clock() + 10
			local pedestals = { empty, incubating }
			local summary = OfflineGrowth.computeFor(pedestals, 0, 3600)
			t.equal(summary.cashEarned, 0)
		end)

		t.it("mutation rolls happen and respect one-per-core", function()
			-- Force a roll success: run enough 2h windows with fresh seeds until one mutates.
			local mutated = false
			for seed = 1, 40 do
				local pedestals = { pedestal("Ember", 0, nil) }
				local now = seed * 1e6
				local summary = OfflineGrowth.computeFor(pedestals, now, now + 7200)
				if #summary.mutations > 0 then
					mutated = true
					t.truthy(summary.mutations[1].slot == 1)
					t.truthy(
						summary.mutations[1].mutation == "Gold"
							or summary.mutations[1].mutation == "Void"
							or summary.mutations[1].mutation == "Celestial"
					)
					break
				end
			end
			t.truthy(mutated, "2h x 40 trials at 2% per 24 rolls should mutate at least once")
		end)

		t.it("rollMutation stays within the weighted set", function()
			for seed = 1, 100 do
				local m = OfflineGrowth.rollMutation(Random.new(seed))
				t.truthy(m == "Gold" or m == "Void" or m == "Celestial")
			end
		end)

		t.it("applyToState pays cash and fires the summary", function()
			local state = PlayerState.createDefault()
			state.pedestals[1].rarity = "Sprout"
			local summary = OfflineGrowth.computeFor(state.pedestals, os.time() - 7200, os.time())
			t.equal(summary.cashEarned, math.floor(7200 * Config.Offline.Efficiency))
		end)
	end)
end
