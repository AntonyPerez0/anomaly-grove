--!strict
-- 2026-10-18 security audit regressions.
local ServerScriptService = game:GetService("ServerScriptService")
local StealSystem = require(ServerScriptService.StealSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local RewardService = require(ServerScriptService.RewardService)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Security audit (2026-10-18)", function()
		t.it("a steal needs a server-timed hold on the same pedestal", function()
			t.equal(StealSystem.ripHeldLongEnough(nil, 1, 2, 100, 2), false) -- no begin: instant rip refused
			local start = { plot = 1, slot = 2, at = 100 }
			t.equal(StealSystem.ripHeldLongEnough(start, 1, 2, 100.5, 2), false) -- too quick
			t.equal(StealSystem.ripHeldLongEnough(start, 1, 2, 102, 2), true)
			t.equal(StealSystem.ripHeldLongEnough(start, 1, 3, 102, 2), false) -- other pedestal
		end)

		t.it("spendCash refuses NaN, infinite and negative amounts", function()
			local state = PlayerState.createDefault()
			state.cash = 100
			t.equal(PlayerState.spendCash(state, 0 / 0), false)
			t.equal(PlayerState.spendCash(state, math.huge), false)
			t.equal(PlayerState.spendCash(state, -5), false)
			t.equal(state.cash, 100)
		end)

		t.it("codes reject anything but letters and digits", function()
			t.equal(RewardService.normalize("GROVE\0"), nil)
			t.equal(RewardService.normalize("../../x"), nil)
		end)
	end)
end
