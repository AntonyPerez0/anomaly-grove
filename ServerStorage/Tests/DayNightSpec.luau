--!strict
-- Day/night cycle rules (M1-14): durations, alternation, transition timing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DayNightCycle = require(ServerScriptService.DayNightCycle)
local Config = require(ReplicatedStorage.Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("DayNightCycle", function()
		t.it("phase lengths come from Config", function()
			t.equal(Config.Cycle.DayLength, 240)
			t.equal(Config.Cycle.NightLength, 120)
			t.truthy(Config.Cycle.NightLength < Config.Cycle.DayLength)
		end)

		t.it("server reports a valid phase", function()
			local phase = DayNightCycle.getPhase()
			t.truthy(phase == "Day" or phase == "Night")
		end)

		t.it("seconds remaining is bounded by the phase length", function()
			local remaining = DayNightCycle.getSecondsRemaining()
			t.truthy(remaining >= 0)
			local phase = DayNightCycle.getPhase()
			local length = if phase == "Day" then Config.Cycle.DayLength else Config.Cycle.NightLength
			t.truthy(remaining <= length)
		end)
	end)
end
