--!strict
-- Plot claim rules (M1-04). Pure checks only: no world instances are touched, so
-- running this spec cannot disturb the live playtest state.
local ServerScriptService = game:GetService("ServerScriptService")
local PlotSystem = require(ServerScriptService.PlotSystem)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("PlotSystem.checkClaim", function()
		local plots = {
			{ index = 0, owner = nil },
			{ index = 1, owner = nil },
		}

		t.it("allows claiming a free plot for a plotless player", function()
			local state = PlayerState.createDefault()
			local ok, reason = PlotSystem.checkClaim(plots, state, 0)
			t.truthy(ok)
			t.equal(reason, "ok")
		end)

		t.it("rejects an out-of-range index", function()
			local state = PlayerState.createDefault()
			local ok, reason = PlotSystem.checkClaim(plots, state, 5)
			t.truthy(not ok)
			t.equal(reason, "invalid plot index")
		end)

		t.it("rejects a player who already owns a plot", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 1
			local ok, reason = PlotSystem.checkClaim(plots, state, 0)
			t.truthy(not ok)
			t.equal(reason, "already owns plot 1")
		end)

		t.it("rejects a plot owned by someone else", function()
			local state = PlayerState.createDefault()
			local other = PlayerState.createDefault()
			other.player = { Name = "Someone" } :: any
			plots[2] = { index = 1, owner = other.player :: any }
			local ok, reason = PlotSystem.checkClaim(plots, state, 1)
			t.truthy(not ok)
			t.equal(reason, "plot owned by Someone")
		end)
	end)
end
