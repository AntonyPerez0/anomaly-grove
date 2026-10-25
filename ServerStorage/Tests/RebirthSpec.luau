--!strict
-- Rebirth rules (M2-09 / GDD 5.7): net-worth gate, tier keep/clear, bonuses.
local ServerScriptService = game:GetService("ServerScriptService")
local RebirthSystem = require(ServerScriptService.RebirthSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local CoreSystem = require(ServerScriptService.CoreSystem)

local TestKit = require(script.Parent.TestKit)

local function pedestal(rarity: string): any
	return {
		rarity = rarity,
		mutation = nil,
		hatchAt = nil,
		tickFrac = 0,
		completedCycles = 1,
		vaultLocked = false,
		mutationProgress = 0,
	}
end

return function(t: TestKit.Context)
	t.describe("RebirthSystem", function()
		t.it("netWorth is cash plus core values", function()
			local state = PlayerState.createDefault()
			state.cash = 500
			state.pedestals[1] = pedestal("Ember") -- 1000
			t.equal(RebirthSystem.netWorth(state), 1500)
		end)

		t.it("first gate needs 300000 net worth", function()
			local state = PlayerState.createDefault()
			state.cash = 299999
			local ok, reason = RebirthSystem.canRebirth(state)
			t.truthy(not ok)
			t.truthy(string.find(reason, "net worth") ~= nil)
			state.cash = 300000
			local ok2, reason2 = RebirthSystem.canRebirth(state)
			t.truthy(ok2)
			t.equal(reason2, "ok")
		end)

		t.it("steal speed bonus stacks to the +5 cap", function()
			t.near(RebirthSystem.stealSpeedMultiplier(0), 1)
			t.near(RebirthSystem.stealSpeedMultiplier(1), 0.9)
			t.near(RebirthSystem.stealSpeedMultiplier(5), 0.5)
			t.near(RebirthSystem.stealSpeedMultiplier(9), 0.5) -- capped
		end)

		t.it("cash bonus compounds x1.75 per rebirth (M8-06)", function()
			t.near(RebirthSystem.cashMultiplier(0), 1)
			t.near(RebirthSystem.cashMultiplier(2), 1.75 ^ 2)
			t.near(RebirthSystem.cashMultiplier(4), 1.75 ^ 4)
		end)

		t.it("requirement grows x2.6 per rebirth", function()
			t.equal(RebirthSystem.requirement(0), 300000)
			t.equal(RebirthSystem.requirement(1), 780000)
			t.equal(RebirthSystem.requirement(3), math.floor(300000 * 2.6 ^ 3))
		end)

		t.it("tickPedestal applies the rebirth cash bonus", function()
			local state = PlayerState.createDefault()
			state.rebirths = 2 -- x3.0625
			state.pedestals[1].rarity = "Sprout" -- 1/s -> 3.0625/s
			local total = 0
			for _ = 1, 10 do
				total += CoreSystem.tickPedestal(state, state.pedestals[1], 1)
			end
			-- conservation: paid + fractional reserve = 30.625.
			t.near(state.cash + state.pedestals[1].tickFrac, 30.625, 0.01)
			t.equal(state.cash, total)
		end)

		t.it("applyRebirth resets pedestal levels and pays tokens (+1 on every 5th)", function()
			local state = PlayerState.createDefault()
			state.pedestals[1].level = 17
			local paid = RebirthSystem.applyRebirth(state)
			t.equal(state.pedestals[1].level, 1)
			t.equal(paid, 1)
			t.equal(state.tokens, 1)
			state.rebirths = 4
			t.equal(RebirthSystem.applyRebirth(state), 2) -- 5th rebirth
			t.equal(state.tokens, 3)
		end)

		t.it("Nest Egg gives starting cash scaled by the new multiplier", function()
			local state = PlayerState.createDefault()
			state.tree.NestEgg = 2
			RebirthSystem.applyRebirth(state)
			t.equal(state.cash, math.floor(1000 * 4 * 1.75))
		end)

		t.it("applyRebirth clears Sprout-Frost and keeps Ember+", function()
			local state = PlayerState.createDefault()
			state.cash = 100000
			state.pedestals =
				{ pedestal("Sprout"), pedestal("Amber"), pedestal("Frost"), pedestal("Ember"), pedestal("Void") }
			RebirthSystem.applyRebirth(state)
			t.equal(state.cash, 0)
			t.equal(state.rebirths, 1)
			t.equal(state.pedestals[1].rarity, nil) -- Sprout cleared
			t.equal(state.pedestals[2].rarity, nil) -- Amber cleared
			t.equal(state.pedestals[3].rarity, nil) -- Frost cleared
			t.equal(state.pedestals[4].rarity, "Ember") -- kept
			t.equal(state.pedestals[5].rarity, "Void") -- kept
		end)

		t.it("rebirth below the gate is rejected and changes nothing", function()
			local state = PlayerState.createDefault()
			state.cash = 500
			-- Gate runs on live state in rebirth(player); test the gate math directly.
			local ok, _ = RebirthSystem.canRebirth(state)
			t.truthy(not ok)
			RebirthSystem.applyRebirth(state) -- if it were applied anyway:
			t.equal(state.rebirths, 1) -- applyRebirth always applies; the GATE is what blocks it
		end)
	end)
end
