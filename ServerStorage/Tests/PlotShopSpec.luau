--!strict
-- Pedestal purchase rules (M2-06).
local ServerScriptService = game:GetService("ServerScriptService")
local PlotSystem = require(ServerScriptService.PlotSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("PlotSystem.checkPedestalPurchase", function()
		t.it("rejects a plotless player", function()
			local state = PlayerState.createDefault()
			state.cash = 100000
			local ok, reason = PlotSystem.checkPedestalPurchase(state, 2)
			t.truthy(not ok)
			t.equal(reason, "claim a plot first")
		end)

		t.it("allows the second pedestal at the first price tier", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 0
			state.cash = 150
			local ok, reason, price = PlotSystem.checkPedestalPurchase(state, 2)
			t.truthy(ok)
			t.equal(reason, "ok")
			t.equal(price, 150)
		end)

		t.it("rejects when cash is short", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 0
			state.cash = 149
			local ok, reason, price = PlotSystem.checkPedestalPurchase(state, 2)
			t.truthy(not ok)
			t.equal(reason, "not enough cash (need 150)")
			t.equal(price, 150)
		end)

		t.it("price ladder matches the GDD table", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 0
			state.cash = math.huge
			-- Buying slots 2..8 costs 150/300/600/1200/2500/5000/10000.
			local expected = { 150, 300, 600, 1200, 2500, 5000, 10000 }
			for i, want in expected do
				local nextSlot = i + 1 -- state has 1 pedestal; each purchase adds one
				local _, _, price = PlotSystem.checkPedestalPurchase(state, nextSlot)
				t.equal(price, want)
				table.insert(state.pedestals, PlayerState.newPedestal())
			end
		end)

		t.it("rejects beyond the 8-slot cap", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 0
			state.cash = math.huge
			for _ = 1, Config.Plot.PedestalSlots - 1 do
				table.insert(state.pedestals, PlayerState.newPedestal())
			end
			t.equal(#state.pedestals, 8)
			local ok, reason = PlotSystem.checkPedestalPurchase(state, 9)
			t.truthy(not ok)
			t.equal(reason, "plot is full")
		end)

		t.it("nextPedestalPrice mirrors the ladder and goes nil when full", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 0
			t.equal(PlotSystem.nextPedestalPrice(state), 150)
			for _ = 1, Config.Plot.PedestalSlots - 1 do
				table.insert(state.pedestals, PlayerState.newPedestal())
			end
			t.equal(PlotSystem.nextPedestalPrice(state), nil)
		end)
	end)
end
