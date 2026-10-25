--!strict
-- M9-09 weekly Eclipse Event clock + limited mutation rules.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Weekly = require(ReplicatedStorage.Shared.Weekly)

local TestKit = require(script.Parent.TestKit)

-- 2026-10-17 00:00 UTC, a Saturday.
local SATURDAY = 1792195200
local HOUR = 3600

return function(t: TestKit.Context)
	t.describe("Weekly Eclipse Event (M9-09)", function()
		t.it("the test anchor really is a Saturday", function()
			t.equal((os.date("!*t", SATURDAY) :: any).wday, Config.Weekly.Weekday)
		end)

		t.it("runs Saturday StartHour .. StartHour + Duration (UTC) only", function()
			local start = SATURDAY + Config.Weekly.StartHour * HOUR
			t.equal(Weekly.isActive(start - 1), false)
			t.equal(Weekly.isActive(start), true)
			t.equal(Weekly.isActive(start + Config.Weekly.DurationHours * HOUR - 1), true)
			t.equal(Weekly.isActive(start + Config.Weekly.DurationHours * HOUR), false)
			t.equal(Weekly.isActive(start + 24 * HOUR), false) -- Sunday
		end)

		t.it("countdowns", function()
			local start = SATURDAY + Config.Weekly.StartHour * HOUR
			t.equal(Weekly.secondsUntilStart(start - HOUR), HOUR)
			t.equal(
				Weekly.secondsUntilStart(start + Config.Weekly.DurationHours * HOUR),
				7 * 24 * HOUR - Config.Weekly.DurationHours * HOUR
			)
			t.equal(Weekly.secondsLeft(start + HOUR), (Config.Weekly.DurationHours - 1) * HOUR)
			t.equal(Weekly.secondsLeft(start - 1), 0)
		end)

		t.it("Eclipse is limited: never rolled normally, never needed for a row", function()
			t.equal(Config.Mutations.Eclipse.weight, 0)
			t.equal(Config.Mutations.Eclipse.limited, true)
			local row: { [string]: boolean } = { Sprout = true }
			for mutation, info in Config.Mutations do
				if not info.limited then
					row["Sprout+" .. mutation] = true
				end
			end
			t.equal(Perks.indexRowComplete(row, "Sprout"), true)
		end)
	end)
end
