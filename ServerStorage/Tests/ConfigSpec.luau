--!strict
-- Config must match docs/GDD.md numbers (task M1-01).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Config", function()
		t.it("matches GDD day/night cycle", function()
			t.equal(Config.Cycle.DayLength, 240)
			t.equal(Config.Cycle.NightLength, 120)
		end)

		t.it("matches GDD seed and incubation rules", function()
			t.equal(Config.Seeds.HarvestTime, 1.5)
			t.equal(Config.Seeds.MaxCarriedSeeds, 3)
			t.equal(Config.Seeds.NodeRespawnSeconds, 30)
			t.equal(Config.Incubation.Duration, 60)
			t.equal(Config.Map.Plots, 8)
		end)

		t.it("matches GDD rarity table", function()
			t.near(Config.Rarities.Sprout.chance, 0.62)
			t.near(Config.Rarities.Celestial.chance, 0.001)
			t.equal(Config.Rarities.Sprout.cashPerSecond, 1)
			t.equal(Config.Rarities.Amber.cashPerSecond, 3)
			t.equal(Config.Rarities.Frost.cashPerSecond, 8)
			t.equal(Config.Rarities.Ember.cashPerSecond, 20)
			t.equal(Config.Rarities.Void.cashPerSecond, 50)
			t.equal(Config.Rarities.Celestial.cashPerSecond, 120)
			t.equal(Config.Rarities.Void.heavy, true)
			t.equal(Config.Rarities.Celestial.heavy, true)
		end)

		t.it("rarity chances sum to 100%", function()
			local total = 0
			for _, rarity in Config.Rarities :: { [string]: Types.RarityInfo } do
				total += rarity.chance
			end
			t.near(total, 1)
		end)

		t.it("matches GDD prices", function()
			t.equal(Config.Prices.Pedestals[1], 150)
			t.equal(Config.Prices.Pedestals[7], 10000)
			t.equal(Config.Prices.Turret, 2500)
			t.equal(Config.Prices.LaserDoor, 1000)
			t.equal(Config.Prices.TrapTile, 500)
			t.equal(Config.Prices.DashBoots, 4000)
			t.equal(Config.Prices.SmokeBomb, 6000)
			t.equal(Config.Prices.Grapple, 10000)
			t.equal(Config.Rebirth.NetWorthRequired, 300000)
		end)

		t.it("matches GDD monster stats", function()
			t.equal(Config.Monsters.Fogling.Health, 12)
			t.equal(Config.Monsters.Fogling.Damage, 15)
			t.equal(Config.Monsters.Fogling.MaxAlive, 6)
			t.equal(Config.Monsters.Stalker.Health, 150)
			t.equal(Config.Monsters.Stalker.Damage, 40)
			t.equal(Config.Monsters.Bounty, 10)
		end)

		t.it("matches GDD steal, carry and tag rules", function()
			t.equal(Config.Steal.RipTime, 2)
			t.near(Config.Steal.CarrySpeedMultiplier, 0.65)
			t.near(Config.Steal.HeavyCarrySpeedMultiplier, 0.5)
			t.equal(Config.Steal.OwnerLockSeconds, 3)
			t.equal(Config.Zapper.Range, 6)
			t.near(Config.Zapper.Cooldown, 1.2)
		end)

		t.it("matches GDD mutation rules", function()
			t.near(Config.MutationChance, 0.02)
			t.near(Config.MutationNightChance, 0.04)
			t.equal(Config.MutationRollInterval, 300)
			t.equal(Config.Mutations.Gold.multiplier, 2)
			t.equal(Config.Mutations.Void.multiplier, 10)
			t.equal(Config.Mutations.Celestial.multiplier, 30)
		end)

		t.it("matches GDD offline growth rules", function()
			t.near(Config.Offline.Efficiency, 0.25)
			t.equal(Config.Offline.CapSeconds, 4 * 60 * 60)
			t.equal(Config.Offline.MaxMutationRollsPerCore, 20)
		end)

		t.it("has launch monetization IDs wired", function()
			-- Real IDs created on the Creator Dashboard (docs/LAUNCH_CHECKLIST.md);
			-- a wired ID must stay positive so the in-game purchase buttons appear.
			t.truthy(Config.GamePasses.VaultLock > 0)
			t.truthy(Config.GamePasses.OfflineMutationLuck > 0)
			t.truthy(Config.Products.InstantLockdown > 0)
		end)
	end)
end
