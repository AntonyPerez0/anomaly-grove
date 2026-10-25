--!strict
-- Wild zones + monster variety (2026-10-18).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Zones)
local CoreSystem = require(ServerScriptService.CoreSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local MonsterAI = require(ServerScriptService.MonsterAI)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Wild zones", function()
		t.it("zone seed odds sum to 1 and use real rarities", function()
			for _, zone in Zones.list() do
				local total = 0
				for rarity, chance in zone.seed.odds do
					t.truthy((Config.Rarities :: any)[rarity], `{zone.id}: unknown rarity {rarity}`)
					total += chance
				end
				t.near(total, 1, 1e-6)
			end
		end)

		t.it("gates sit between plots and away from the hub", function()
			for _, zone in Zones.list() do
				t.near(zone.angle % Config.Map.PlotSpacingDegrees, Config.Map.PlotSpacingDegrees / 2, 1e-6)
				t.truthy(zone.angle ~= 22.5, "a gate on the hub")
				t.truthy((Config.Monsters :: any)[zone.guardian], `{zone.id}: unknown guardian`)
			end
		end)

		t.it("Zones.at finds a zone by position and lookups resolve", function()
			local crystal = Zones.get("Crystal") :: Zones.ZoneDef
			t.equal((Zones.at(Zones.center(crystal)) :: Zones.ZoneDef).id, "Crystal")
			t.equal(Zones.at(Vector3.zero), nil)
			local seed, zone = Zones.seed("RelicSeed")
			t.equal((seed :: any).name, "Relic Seed")
			t.equal((zone :: any).id, "Shrine")
			t.equal(Zones.seed("nope"), nil)
			t.equal(Zones.canHarvest(crystal, crystal.foraging - 1), false)
			t.equal(Zones.canHarvest(crystal, crystal.foraging), true)
		end)

		t.it("planting spends the best seed first, feeding the plainest", function()
			local state = PlayerState.createDefault()
			state.seedsCarried = 1
			state.groveSeeds = 1
			PlayerState.addZoneSeed(state, "CrystalSeed", 1)
			PlayerState.addZoneSeed(state, "RelicSeed", 1)
			t.equal(PlayerState.seedCount(state), 4)
			t.equal(CoreSystem.consumeSeed(state), "RelicSeed")
			t.equal(CoreSystem.consumeSeed(state, true), "regular")
			t.equal(CoreSystem.consumeSeed(state, true), "grove")
			t.equal(CoreSystem.consumeSeed(state), "CrystalSeed")
			t.equal(CoreSystem.consumeSeed(state), nil)
			t.equal(next(state.zoneSeeds), nil)
		end)

		t.it("a zone seed hatches with its zone's odds", function()
			local state = PlayerState.createDefault()
			state.indexDiscovered = { Sprout = true } :: any -- skip the first-core floor
			local relic = (Zones.seed("RelicSeed")) :: Zones.ZoneSeedDef
			for i = 1, 200 do
				local rarity = CoreSystem.rollHatch(state, "RelicSeed", Random.new(i))
				t.truthy(Config.Rarities[rarity].tier >= Config.Rarities.Frost.tier, `rolled {rarity}`)
				t.truthy(relic.odds[rarity] ~= nil or Config.Rarities[rarity].tier < Config.Rarities.Celestial.tier)
			end
		end)
	end)

	t.describe("Monster variety", function()
		t.it("Golem slam: windup in range when rested, slam after the windup", function()
			local golem = Config.Monsters.Golem
			local m = { kind = "Golem", lungeState = "none", lungeUntil = 0, lastAttack = 0 }
			t.equal(MonsterAI.golemSlamStep(m, 10, golem.SlamRange + 1), nil)
			t.equal(MonsterAI.golemSlamStep(m, 10, golem.SlamRange), "windup")
			m.lastAttack = 9
			t.equal(MonsterAI.golemSlamStep(m, 10, 1), nil) -- still recovering
			local winding = { kind = "Golem", lungeState = "windup", lungeUntil = 12, lastAttack = 0 }
			t.equal(MonsterAI.golemSlamStep(winding, 11, 1), nil)
			t.equal(MonsterAI.golemSlamStep(winding, 12, 1), "slam")
			t.equal(
				MonsterAI.golemSlamStep(
					{ kind = "Fogling", lungeState = "none", lungeUntil = 0, lastAttack = 0 },
					10,
					1
				),
				nil
			)
		end)

		t.it("Spitter globs land where they were aimed", function()
			local from, to, time, g = Vector3.new(0, 5, 0), Vector3.new(30, 0, -12), 1.1, 196.2
			local v = MonsterAI.lobVelocity(from, to, time, g)
			local landed = from + v * time - Vector3.new(0, 0.5 * g * time * time, 0)
			t.near((landed - to).Magnitude, 0, 1e-3) -- Vector3 is float32
		end)

		t.it("mutation rolls never downgrade a core", function()
			t.equal(CoreSystem.isMutationUpgrade(nil, "Gold"), true)
			t.equal(CoreSystem.isMutationUpgrade("Gold", "Void"), true)
			t.equal(CoreSystem.isMutationUpgrade("Void", "Gold"), false)
			t.equal(CoreSystem.isMutationUpgrade("Void", "Void"), false)
		end)

		t.it("the Lantern reaches monsters within its radius only (M9-02)", function()
			local r = Config.Gadgets.Lantern.radius
			t.equal(MonsterAI.inLanternRange(Vector3.new(r - 1, 0, 0), Vector3.zero), true)
			t.equal(MonsterAI.inLanternRange(Vector3.new(r + 1, 0, 0), Vector3.zero), false)
			t.truthy((Config.Prices :: any).Lantern > 0)
		end)

		t.it("guardians are leashed to their zone", function()
			local home = Zones.center(Zones.get("Mire") :: Zones.ZoneDef)
			t.equal(MonsterAI.inLeash(home + Vector3.new(Config.Zones.Radius, 0, 0), home), true)
			t.equal(MonsterAI.inLeash(home + Vector3.new(Config.Zones.Radius + 20, 0, 0), home), false)
		end)
	end)
end
