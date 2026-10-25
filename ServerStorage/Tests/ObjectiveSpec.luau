--!strict
-- Objective chain (M6-01): the guide always points at the right next step.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Objectives = require(ReplicatedStorage.Shared.Objectives)

local TestKit = require(script.Parent.TestKit)

local function snapshot(overrides: { [string]: any }): Objectives.Snapshot
	local s: { [string]: any } = {
		hasPlot = true,
		seeds = 0,
		carryingCore = false,
		summary = "1=empty",
		pedestalSlots = 1,
		cash = 0,
		coresStolen = 0,
		netWorth = 0,
		night = false,
	}
	for k, v in overrides do
		s[k] = v
	end
	return s :: any
end

return function(t: TestKit.Context)
	t.describe("Objectives", function()
		t.it("the opening mixes pedestals, a defense and a gadget before upgrades", function()
			local base = {
				summary = "1=A|2=A|3=A",
				pedestalSlots = 3,
				coresStolen = 1,
				defenseCount = 0,
				hasGadget = false,
				cultivationLevel = 4,
				bestUpgrade = { slot = 1, level = 1, price = 10 },
			}
			t.equal(Objectives.next(snapshot(base)).id, "defense")
			base.defenseCount = 1
			t.equal(Objectives.next(snapshot(base)).id, "pedestalN") -- pedestal 4
			base.pedestalSlots = 5
			base.summary = "1=A|2=A|3=A|4=A|5=A"
			t.equal(Objectives.next(snapshot(base)).id, "gadget")
			base.hasGadget = true
			t.equal(Objectives.next(snapshot(base)).id, "upgrade") -- cheaper than pedestal 6
			base.bestUpgrade = nil :: any
			base.pedestalSlots = 8
			base.summary = "1=A|2=A|3=A|4=A|5=A|6=A|7=A|8=A"
			t.equal(Objectives.next(snapshot(base)).id, "cultivate") -- upgrades still locked
		end)

		t.it("parses the pedestal summary", function()
			local cores, seeds, empty = Objectives.parseSummary("1=Sprout+GoldV|2=seed|3=empty|4=Frost")
			t.equal(cores, 2)
			t.equal(seeds, 1)
			t.equal(empty, 1)
		end)

		t.it("walks a new player through claim -> harvest -> plant -> hatch", function()
			t.equal(Objectives.next(snapshot({ hasPlot = false })).id, "claim")
			t.equal(Objectives.next(snapshot({})).id, "harvest")
			t.equal(Objectives.next(snapshot({ seeds = 1 })).target, "ownPedestal")
			t.equal(Objectives.next(snapshot({ summary = "1=seed" })).id, "hatch")
		end)

		t.it("carrying a core always means run home", function()
			t.equal(Objectives.next(snapshot({ carryingCore = true, hasPlot = false })).target, "home")
		end)

		t.it("saves up for pedestal 2 with progress, then raids", function()
			local o = Objectives.next(snapshot({ summary = "1=Sprout", cash = 75 }))
			t.equal(o.id, "pedestal2")
			t.near(o.progress :: number, 0.5)
			t.equal(Objectives.next(snapshot({ summary = "1=Sprout|2=Amber", pedestalSlots = 2 })).id, "raid")
		end)

		t.it("skips the raid goal when no rival has a core (solo server)", function()
			local o = Objectives.next(snapshot({ summary = "1=Sprout|2=Amber", pedestalSlots = 2, rivalCores = false }))
			t.equal(o.id, "pedestalN")
		end)

		t.it("late game points at pedestals then rebirth", function()
			local base = { summary = "1=Sprout|2=Amber", pedestalSlots = 2, coresStolen = 3 }
			t.equal(Objectives.next(snapshot(base)).id, "pedestalN")
			local full = "1=A|2=A|3=A|4=A|5=A|6=A|7=A|8=A"
			t.equal(
				Objectives.next(snapshot({ summary = full, pedestalSlots = 8, coresStolen = 3, netWorth = 50 })).id,
				"rebirthGoal"
			)
			t.equal(
				Objectives.next(snapshot({ summary = full, pedestalSlots = 8, coresStolen = 3, netWorth = 400000 })).id,
				"rebirth"
			)
		end)

		t.it("night warns once the player has a core", function()
			t.equal(Objectives.next(snapshot({ summary = "1=Sprout", night = true })).id, "night")
		end)
	end)
end
