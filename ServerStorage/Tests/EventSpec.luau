--!strict
-- World events (M6-04): Blood Moon cadence, meteor roll threshold, neutral multipliers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local EventService = require(ServerScriptService.EventService)
local CoreSystem = require(ServerScriptService.CoreSystem)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("EventService", function()
		t.it("every Nth night is a Blood Moon, others are not", function()
			local every = Config.Events.BloodMoonEvery
			t.equal(EventService.rollFor("Night", every, 0), "BloodMoon")
			t.equal(EventService.rollFor("Night", every * 2, 0), "BloodMoon")
			t.equal(EventService.rollFor("Night", every - 1, 1), nil)
			t.equal(EventService.rollFor("Night", every - 1, 0), "Aurora") -- M9-06: other nights may get an Aurora
			t.equal(EventService.rollFor("Night", 0, 1), nil)
		end)

		t.it("meteor showers follow the day roll threshold", function()
			t.equal(EventService.rollFor("Day", 3, Config.Events.MeteorChance - 0.01), "MeteorShower")
			t.equal(EventService.rollFor("Day", 3, Config.Events.MeteorChance + 0.01), "Rain") -- M9-06
			t.equal(
				EventService.rollFor("Day", 3, Config.Events.MeteorChance + Config.Events.RainChance + 0.01),
				"Thunderstorm"
			)
			t.equal(EventService.rollFor("Day", 3, 0.99), nil)
		end)

		t.it("multipliers are neutral with no event running", function()
			if EventService.current() == nil then
				t.equal(EventService.mutationMultiplier(), 1)
				t.equal(EventService.monsterMultiplier(), 1)
			end
		end)

		t.it("mutation chance multiplier can turn a miss into a hit", function()
			-- rng stub that always rolls 0.06: above the 4% night chance, below 8% (x2).
			local stub = {
				NextNumber = function(_self)
					return 0.06
				end,
				NextInteger = function(_self, a)
					return a
				end,
			}
			local pedestal: any = { rarity = "Sprout", hatchAt = nil, mutationProgress = Config.MutationRollInterval }
			t.equal(CoreSystem.mutationTick(pedestal, 0, true, stub :: any, 1), nil)
			pedestal.mutationProgress = Config.MutationRollInterval
			t.truthy(CoreSystem.mutationTick(pedestal, 0, true, stub :: any, 2) ~= nil)
		end)
	end)
end
