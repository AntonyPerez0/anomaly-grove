--!strict
-- M8: perks, curves, gated rolls, skill XP, purchase gates, Grove Pass, schema v4.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local CoreSystem = require(ServerScriptService.CoreSystem)
local EconomyService = require(ServerScriptService.EconomyService)
local PassService = require(ServerScriptService.PassService)
local PlayerState = require(ServerScriptService.PlayerState)
local Profile = require(ServerScriptService.Profile)
local SkillService = require(ServerScriptService.SkillService)
local LeaderboardService = require(ServerScriptService.LeaderboardService)
local RebirthSystem = require(ServerScriptService.RebirthSystem)

local TestKit = require(script.Parent.TestKit)

local function withPlot(): any
	local state = PlayerState.createDefault()
	state.plotIndex = 0
	return state
end

return function(t: TestKit.Context)
	t.describe("Perks (M8)", function()
		t.it("skill tracks step every 3 levels and unlocks add on top", function()
			local stats = Perks.compute({ skills = { Cultivation = Progression.xpForLevel(30) } })
			t.near(Perks.get(stats, "hatchSpeed"), 10 * 0.0075)
			t.near(Perks.get(stats, "rarityLuck"), 10 * 0.015)
			local forager = Perks.compute({ skills = { Foraging = Progression.xpForLevel(25) } })
			t.equal(Perks.get(forager, "seedBag"), 2) -- unlocks at 10 and 25
		end)

		t.it("tree, upgrades and the Index all feed the same stats", function()
			local stats = Perks.compute({
				tree = { GoldenTouch = 2, Expansion = 1 },
				upgrades = { TurretPower = 3 },
				indexEntries = 5,
			})
			t.near(Perks.get(stats, "income"), 0.10 + 0.05)
			t.equal(Perks.get(stats, "pedestalSlots"), 1)
			t.near(Perks.get(stats, "turretDamage"), 0.45)
			t.equal(Perks.maxPedestals(stats), 9)
		end)

		t.it("level-up texts and the next reward", function()
			local lines = Perks.rewardsAt("Foraging", 10)
			t.truthy(table.find(lines, "Seed bag +1") ~= nil)
			local nextLevel, nextLines = Perks.nextReward("Cultivation", 19)
			t.equal(nextLevel, 20)
			t.truthy(table.find(nextLines, "Fertile Crates unlocked") ~= nil)
			for level = 1, 99 do
				-- every skill gives something at least every 3 levels
				t.truthy(#Perks.rewardsAt("Survival", level) > 0 or level % 3 ~= 0)
			end
		end)

		t.it("pedestal caps, costs and rebirth curve", function()
			t.equal(Perks.pedestalCap(0), 50)
			t.equal(Perks.pedestalCap(5), 60)
			t.equal(Perks.pedestalCap(1e6), Config.PedestalUpgrade.MaxCap)
			t.equal(Perks.pedestalUpgradeCost(1, 1, 0), 200)
			t.equal(Perks.pedestalUpgradeCost(2, 1, 0), 230)
			t.equal(Perks.rebirthRequirement(2), math.floor(300000 * 2.6 ^ 2))
			t.equal(Perks.tokensForRebirth(5), 2)
			t.near(Perks.pedestalIncomeMultiplier(11), 1.08 ^ 10)
		end)

		t.it("discount is capped and commerce XP grows with the log of the price", function()
			t.equal(Perks.discounted(1000, { discount = 0.1 }), 900)
			t.equal(Perks.discounted(1000, { discount = 5 }), 700) -- MaxDiscount 0.3
			-- relative to income: a minute of income or more is the full 45 XP
			t.equal(Perks.commerceXp(6000, 100), 45)
			t.equal(Perks.commerceXp(600, 100), 9)
			t.equal(Perks.commerceXp(1e30, 0), 45)
		end)

		t.it("pass levels and index rows", function()
			t.equal(Perks.passLevel(1499), 0)
			t.equal(Perks.passLevel(1500), 1)
			t.equal(Perks.passLevel(1500 + 1650), 2)
			local discovered = { Ember = true, ["Ember+Gold"] = true, ["Ember+Void"] = true }
			t.equal(Perks.indexEntries(discovered), 3)
			t.truthy(not Perks.indexRowComplete(discovered, "Ember"))
			discovered["Ember+Celestial"] = true
			t.truthy(not Perks.indexRowComplete(discovered, "Ember")) -- M9-06: Shocked is part of the row
			discovered["Ember+Shocked"] = true
			t.truthy(Perks.indexRowComplete(discovered, "Ember"))
		end)
	end)

	t.describe("Gated rolls (M8-05)", function()
		t.it("locked rarities fall to the best unlocked one", function()
			local rng = Random.new(7)
			for _ = 1, 200 do
				local pick = CoreSystem.rollFrom({ Celestial = 0.2, Prismatic = 0.8 }, rng, function(name)
					return name ~= "Prismatic"
				end)
				t.equal(pick, "Celestial")
			end
		end)

		t.it("luck shifts weight above the lowest tier", function()
			local odds = CoreSystem.luckOdds({ Sprout = 0.5, Amber = 0.5 }, 1)
			t.near(odds.Sprout, 0.5)
			t.near(odds.Amber, 1.0)
			local counts = { Sprout = 0, Amber = 0 }
			local rng = Random.new(3)
			for _ = 1, 3000 do
				local pick = CoreSystem.rollFrom(odds, rng)
				counts[pick :: string] += 1
			end
			t.truthy(counts.Amber > counts.Sprout * 1.6)
		end)

		t.it("crates never roll below their table", function()
			local state = withPlot()
			state.skills.Cultivation = Progression.xpForLevel(99)
			state.indexDiscovered.Sprout = true
			local rng = Random.new(11)
			for _ = 1, 200 do
				local rarity = CoreSystem.rollHatch(state, "Ancient", rng)
				t.truthy(Config.Rarities[rarity].tier >= 3)
				t.truthy(rarity ~= "Prismatic") -- rebirth tier 0: still locked
			end
		end)
	end)

	t.describe("Skill XP (M8-02)", function()
		t.it("applies the level factor and levels up", function()
			local state = withPlot()
			local gained, oldLevel, newLevel = SkillService.applyXp(state, "Foraging", 20)
			t.equal(gained, 20)
			t.equal(oldLevel, 1)
			t.equal(newLevel, 1)
			local _, _, after = SkillService.applyXp(state, "Foraging", 100)
			t.equal(after, 2)
			state.skills.Survival = Progression.xpForLevel(51)
			local scaled = SkillService.applyXp(state, "Survival", 100)
			t.equal(scaled, math.floor(100 * (1 + 0.03 * 50) + 0.5))
		end)
	end)

	t.describe("Purchase gates (M8-04/05/07/08)", function()
		t.it("pedestal upgrades need a plot, cash and room under the cap", function()
			local state = PlayerState.createDefault()
			t.truthy(not (EconomyService.checkUpgradePedestal(state, 1)))
			state.plotIndex = 0
			state.cash = 1000
			local locked, why = EconomyService.checkUpgradePedestal(state, 1)
			t.truthy(not locked)
			t.truthy(string.find(why :: string, "Cultivation") ~= nil)
			state.skills.Cultivation = Progression.xpForLevel(10)
			state.cash = 50
			t.truthy(not (EconomyService.checkUpgradePedestal(state, 1)))
			state.cash = 1000
			local ok, price = EconomyService.checkUpgradePedestal(state, 1)
			t.truthy(ok)
			t.equal(price, 200)
			state.pedestals[1].level = 50
			t.truthy(not (EconomyService.checkUpgradePedestal(state, 1)))
		end)

		t.it("crates need Cultivation, an empty pedestal and cash", function()
			local state = withPlot()
			state.cash = 1e9
			local ok, reason = EconomyService.checkCrate(state, "Fertile")
			t.truthy(not ok)
			t.truthy(string.find(reason :: string, "Cultivation") ~= nil)
			state.skills.Cultivation = Progression.xpForLevel(20)
			t.truthy((EconomyService.checkCrate(state, "Fertile")))
			state.pedestals[1].hatchAt = 123
			t.truthy(not (EconomyService.checkCrate(state, "Fertile")))
			t.truthy(not (EconomyService.checkCrate(state, "Nope")))
		end)

		t.it("full plots: a crate replaces the weakest core below its expected income", function()
			local state = withPlot()
			state.pedestals = {
				{ rarity = "Ember", level = 1, completedCycles = 0, tickFrac = 0, mutationProgress = 0 } :: any,
				{
					rarity = "Sprout",
					mutation = "Gold",
					level = 1,
					completedCycles = 0,
					tickFrac = 0,
					mutationProgress = 0,
				},
				{ rarity = "Sprout", level = 1, completedCycles = 0, tickFrac = 0, mutationProgress = 0 } :: any,
			} :: any
			-- Fertile expects ~8.3/s: Ember (20/s) is safe; the weakest below it is slot 3.
			t.equal(EconomyService.crateSlot(state, "Fertile"), 3)
			state.pedestals[3].rarity = "Void"
			t.equal(EconomyService.crateSlot(state, "Fertile"), 2) -- Sprout+Gold (2/s) < 8.3/s
			state.pedestals[2].mutation = "Celestial" -- 30/s now beats Fertile's expectation
			t.equal(EconomyService.crateSlot(state, "Fertile"), nil)
			t.equal(EconomyService.crateSlot(state, "Ancient"), 1) -- Ember (20/s) < Ancient ~24/s
		end)

		t.it("tree nodes cost tokens and max out", function()
			local state = withPlot()
			t.truthy(not (EconomyService.checkTreeNode(state, "Bulwark")))
			state.tokens = 2
			local ok, cost = EconomyService.checkTreeNode(state, "Bulwark")
			t.truthy(ok)
			t.equal(cost, 2)
			state.tree.Bulwark = 3
			local maxed, reason = EconomyService.checkTreeNode(state, "Bulwark")
			t.truthy(not maxed)
			t.equal(reason, "maxed")
		end)

		t.it("defense upgrades follow their curve to the max", function()
			local state = withPlot()
			state.cash = 1e12
			local ok, price = EconomyService.checkUpgrade(state, "TurretPower")
			t.truthy(ok)
			t.equal(price, 3000)
			state.upgrades.TurretPower = 20
			t.truthy(not (EconomyService.checkUpgrade(state, "TurretPower")))
		end)
	end)

	t.describe("Grove Pass (M8-10)", function()
		t.it("claims reached levels once and pays tokens every 5th", function()
			local state = withPlot()
			state.pass = { season = Config.Pass.Season, xp = 0, claimed = {} }
			t.truthy(not (PassService.claimState(state, 1, 10)))
			state.pass.xp = 1e9
			local ok, reward = PassService.claimState(state, 5, 10)
			t.truthy(ok)
			t.equal(reward.tokens, 1)
			t.equal(state.tokens, 1)
			t.truthy(not (PassService.claimState(state, 5, 10)))
			local _, final = PassService.claimState(state, 50, 10)
			t.equal(final.tokens, 1 + Config.Pass.FinalTokens)
		end)

		t.it("a new season resets the track", function()
			local state = withPlot()
			state.pass = { season = 0, xp = 999, claimed = { ["1"] = true } }
			t.truthy(PassService.ensureSeason(state))
			t.equal(state.pass.xp, 0)
		end)
	end)

	t.describe("Economy review (2026-10-18)", function()
		t.it("level investment equals the summed level prices and counts toward net worth", function()
			local sum = 0
			for level = 1, 29 do
				sum += Perks.pedestalUpgradeCost(3, level)
			end
			t.near(Perks.levelInvestment(3, 30), sum, sum * 0.001 + 30)
			local state = withPlot()
			state.pedestals[1].level = 30
			t.equal(RebirthSystem.netWorth(state), Perks.levelInvestment(1, 30))
		end)

		t.it("level prices no longer scale with rebirths", function()
			t.equal(Perks.pedestalUpgradeCost(1, 10, 0), Perks.pedestalUpgradeCost(1, 10, 20))
		end)

		t.it("rebirth keeps mutated cores and Ember+, clears plain Sprout-Frost", function()
			local state = withPlot()
			state.pedestals = {
				{
					rarity = "Sprout",
					mutation = "Void",
					level = 40,
					completedCycles = 1,
					tickFrac = 0,
					mutationProgress = 0,
				},
				{ rarity = "Frost", level = 10, completedCycles = 1, tickFrac = 0, mutationProgress = 0 } :: any,
				{ rarity = "Ember", level = 5, completedCycles = 1, tickFrac = 0, mutationProgress = 0 } :: any,
			} :: any
			RebirthSystem.applyRebirth(state)
			t.equal(state.pedestals[1].rarity, "Sprout")
			t.equal(state.pedestals[1].mutation, "Void")
			t.equal(state.pedestals[2].rarity, nil)
			t.equal(state.pedestals[3].rarity, "Ember")
			t.equal(state.pedestals[1].level, 1)
		end)

		t.it("UPGRADE ALL picks the best value and skips empty pedestals", function()
			local state = withPlot()
			state.cash = 1e9
			state.skills.Cultivation = Progression.xpForLevel(10)
			state.pedestals = {
				{ rarity = "Sprout", level = 1, completedCycles = 0, tickFrac = 0, mutationProgress = 0 } :: any,
				{
					rarity = "Sprout",
					mutation = "Void",
					level = 20,
					completedCycles = 0,
					tickFrac = 0,
					mutationProgress = 0,
				},
				{ level = 1, completedCycles = 0, tickFrac = 0, mutationProgress = 0 } :: any,
			} :: any
			local slot = EconomyService.bestUpgrade(state)
			t.equal(slot, 2) -- the Void core beats a cheaper plain Sprout; the empty one is never picked
		end)

		t.it("summary parsing and income-scaled rewards", function()
			local cores = Perks.coresFromSummary("1=Amber+GoldV|2=seed|3=empty|4=Sprout")
			t.equal(cores[1].rarity, "Amber")
			t.equal(cores[1].mutation, "Gold")
			t.equal(cores[2], nil)
			t.equal(cores[3], nil)
			t.equal(cores[4].rarity, "Sprout")
			t.equal(Perks.scaledReward(100, 0, 1000, 180), 180000)
			t.equal(Perks.scaledReward(100, 0, 0, 180), 100)
		end)

		t.it("feed cap grows 1 per 10 levels", function()
			t.equal(CoreSystem.feedCap({ level = 1 } :: any), 10)
			t.equal(CoreSystem.feedCap({ level = 200 } :: any), 30)
		end)
	end)

	t.describe("Leaderboard encoding (M8)", function()
		t.it("net worth is log-encoded into int64 range and decodes back", function()
			local stored = LeaderboardService.encode("NetWorth", 1e40)
			t.truthy(stored < 2 ^ 53)
			t.near(LeaderboardService.decode("NetWorth", stored) / 1e40, 1, 1e-6)
			t.equal(LeaderboardService.encode("CoresStolen", 12.7), 12)
		end)
	end)

	t.describe("Schema v4 (M8)", function()
		t.it("v3 saves migrate with empty progression and keep incubating seeds", function()
			local profile = Profile.migrate({
				schemaVersion = 3,
				cash = 777,
				pedestals = { { incubateRemaining = 42, tickFrac = 0, completedCycles = 0 } },
			})
			t.equal(profile.schemaVersion, 4)
			t.equal(profile.cash, 777)
			t.equal(profile.tokens, 0)
			t.equal(profile.pedestals[1].level, 1)
			t.equal((profile.pedestals[1] :: any).incubateRemaining, 42)
		end)

		t.it("malformed v4 fields are dropped, valid ones kept", function()
			local profile = Profile.migrate({
				schemaVersion = 4,
				skills = { Foraging = 500, Bad = "x", [3] = 9 },
				tree = { Bulwark = 2 },
				tokens = -4,
				pass = { season = 1, xp = 50, claimed = { ["2"] = true, ["3"] = "yes" } },
			})
			t.equal(profile.skills.Foraging, 500)
			t.equal(profile.skills.Bad, nil)
			t.equal(profile.tree.Bulwark, 2)
			t.equal(profile.tokens, 0)
			t.equal(profile.pass.claimed["2"], true)
			t.equal(profile.pass.claimed["3"], nil)
		end)
	end)
end
