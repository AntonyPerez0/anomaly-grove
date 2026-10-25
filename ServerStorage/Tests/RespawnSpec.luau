--!strict
-- Respawn and night-streak logic (M1-13).
local ServerScriptService = game:GetService("ServerScriptService")
local RespawnSystem = require(ServerScriptService.RespawnSystem)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("RespawnSystem", function()
		t.it("survivedNight requires positive health", function()
			t.truthy(RespawnSystem.survivedNight(1))
			t.truthy(RespawnSystem.survivedNight(100))
			t.truthy(not RespawnSystem.survivedNight(0))
			t.truthy(not RespawnSystem.survivedNight(-5))
		end)

		t.it("streak increments on survival", function()
			t.equal(RespawnSystem.streakAfterNight(0, true, 120), 1)
			t.equal(RespawnSystem.streakAfterNight(4, true, 120), 5)
		end)

		t.it("death resets the streak", function()
			t.equal(RespawnSystem.streakAfterNight(7, false, 120), 0)
		end)
	end)
end
