--!strict
-- M9-06 weather + the Shocked mutation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local CoreSystem = require(ServerScriptService.CoreSystem)
local EventService = require(ServerScriptService.EventService)
local WeatherService = require(ServerScriptService.WeatherService)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Weather (M9-06)", function()
		t.it("Shocked is storm-only: normal rolls never give it", function()
			local rng = Random.new(5)
			for _ = 1, 3000 do
				t.truthy(CoreSystem.rollMutation(rng, 0, 0) ~= "Shocked")
			end
			t.equal(Config.Mutations.Shocked.weight, 0)
		end)

		t.it("lightning only targets cores Shocked would improve", function()
			local pedestals: { any } = {
				{ rarity = "Sprout", mutation = nil } :: any,
				{ rarity = "Sprout", mutation = "Void" } :: any,
				{ rarity = "Sprout", mutation = "Celestial" } :: any,
				{ rarity = "Sprout", mutation = "Shocked" } :: any,
				{ rarity = nil } :: any,
				{ rarity = "Amber", hatchAt = 10 } :: any,
			}
			t.deepEqual(WeatherService.strikeTargets(pedestals), { 1, 2 })
		end)

		t.it("weather multipliers are neutral when nothing runs", function()
			if EventService.current() == nil then
				t.equal(EventService.incubationMultiplier(), 1)
				t.equal(EventService.celestialBonus(), 0)
			end
			t.truthy(Config.Events.Rain.IncubationMultiplier < 1)
		end)

		t.it("Index backfill counts owned cores (fix: offline mutations were missing)", function()
			local PlayerState = require(ServerScriptService.PlayerState)
			local CollectionIndex = require(ServerScriptService.CollectionIndex)
			local state = PlayerState.createDefault()
			state.pedestals = {
				{
					rarity = "Sprout",
					mutation = "Void",
					level = 1,
					completedCycles = 1,
					tickFrac = 0,
					mutationProgress = 0,
				} :: any,
			}
			t.equal(CollectionIndex.backfill(state), 3)
			t.equal(state.indexDiscovered["Sprout+Void"], true)
			t.equal(CollectionIndex.backfill(state), 0)
		end)

		t.it("the Index grows by one entry per rarity for Shocked", function()
			local discovered: { [string]: boolean } = { Sprout = true, ["Sprout+Shocked"] = true }
			t.equal(Perks.indexEntries(discovered), 2)
			t.equal(Perks.indexRowComplete(discovered, "Sprout"), false)
		end)
	end)
end
