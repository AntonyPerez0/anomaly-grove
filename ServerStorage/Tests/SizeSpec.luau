--!strict
-- M9-01 core sizes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local CoreSystem = require(ServerScriptService.CoreSystem)
local Profile = require(ServerScriptService.Profile)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Core sizes (M9-01)", function()
		t.it("size chances sum to 1 and Normal is stored as nil", function()
			local total = 0
			for _, name in Config.Sizes.Order do
				total += Config.Sizes.Defs[name].chance
			end
			t.near(total, 1, 1e-6)
			local counts: { [string]: number } = {}
			local rng = Random.new(42)
			for _ = 1, 20000 do
				local size = Perks.rollSize(rng) or "Normal"
				counts[size] = (counts[size] or 0) + 1
			end
			t.near(counts.Normal / 20000, Config.Sizes.Defs.Normal.chance, 0.02)
			t.near(counts.Huge / 20000, Config.Sizes.Defs.Huge.chance, 0.01)
		end)

		t.it("size multiplies a core's income", function()
			local pedestal = { rarity = "Amber", level = 1, completedCycles = 0, size = "Huge" } :: any
			t.near(
				CoreSystem.coreRate(pedestal),
				Config.Rarities.Amber.cashPerSecond * Config.Sizes.Defs.Huge.mult,
				1e-9
			)
			pedestal.size = nil
			t.near(CoreSystem.coreRate(pedestal), Config.Rarities.Amber.cashPerSecond, 1e-9)
		end)

		t.it("only Huge and Titanic are announced", function()
			t.equal(CoreSystem.isBigSize("Big"), false)
			t.equal(CoreSystem.isBigSize("Huge"), true)
			t.equal(CoreSystem.isBigSize("Titanic"), true)
		end)

		t.it("summary parsing keeps the size; profiles keep valid sizes only", function()
			local cores = Perks.coresFromSummary("1=Sprout+Void~HugeV|2=Amber~Tiny|3=Frost")
			t.equal(cores[1].mutation, "Void")
			t.equal(cores[1].size, "Huge")
			t.equal(cores[2].size, "Tiny")
			t.equal(cores[3].size, nil)
			local merged = Profile.migrate({
				schemaVersion = 4,
				pedestals = { { rarity = "Sprout", size = "Titanic" }, { rarity = "Sprout", size = "Gigantic" } },
			})
			t.equal(merged.pedestals[1].size, "Titanic")
			t.equal(merged.pedestals[2].size, nil)
		end)
	end)
end
