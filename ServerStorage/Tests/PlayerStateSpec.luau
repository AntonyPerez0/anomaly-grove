--!strict
-- PlayerState pure helpers (M1-02). Lifecycle needs a real Player, so only the
-- player-free logic is unit tested.
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("PlayerState", function()
		t.it("creates an empty pedestal", function()
			local pedestal = PlayerState.newPedestal()
			t.equal(pedestal.rarity, nil)
			t.equal(pedestal.mutation, nil)
			t.equal(pedestal.hatchAt, nil)
			t.equal(pedestal.tickFrac, 0)
			t.equal(pedestal.completedCycles, 0)
			t.equal(pedestal.vaultLocked, false)
			t.equal(pedestal.mutationProgress, 0)
		end)

		t.it("default state starts broke with one pedestal", function()
			local state = PlayerState.createDefault()
			t.equal(state.cash, 0)
			t.equal(state.plotIndex, nil)
			t.equal(#state.pedestals, 1)
		end)

		t.it("addCash adds", function()
			local state = PlayerState.createDefault()
			t.equal(PlayerState.addCash(state, 25), 25)
			t.equal(PlayerState.addCash(state, 5), 30)
		end)

		t.it("addCash never goes negative", function()
			local state = PlayerState.createDefault()
			PlayerState.addCash(state, 10)
			t.equal(PlayerState.addCash(state, -50), 0)
		end)
	end)
end
