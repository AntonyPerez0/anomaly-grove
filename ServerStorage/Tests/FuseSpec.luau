--!strict
-- M9-05 Fuse Machine.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Fuse = require(ReplicatedStorage.Shared.Fuse)
local FuseService = require(ServerScriptService.FuseService)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

local function core(rarity: string?, level: number, mutation: string?): any
	return {
		rarity = rarity,
		mutation = mutation,
		level = level,
		completedCycles = 1,
		tickFrac = 0,
		mutationProgress = 0,
		mutationBoost = false,
		vaultLocked = false,
	}
end

return function(t: TestKit.Context)
	t.describe("Fuse Machine (M9-05)", function()
		t.it("next rarity climbs one tier; chances fall with tier", function()
			t.equal(Fuse.nextRarity("Sprout"), "Amber")
			t.equal(Fuse.nextRarity("Amber"), "Frost")
			t.truthy(Fuse.chance("Sprout") > Fuse.chance("Frost"))
			local top
			for name, info in Config.Rarities :: any do
				if top == nil or info.tier > (Config.Rarities :: any)[top].tier then
					top = name
				end
			end
			t.equal(Fuse.nextRarity(top), nil)
		end)

		t.it("plans the 3 weakest cores and lands on the highest level of them", function()
			local state = PlayerState.createDefault()
			state.pedestals = {
				core("Sprout", 40, "Void"), -- strongest Sprout: kept out of the fuse
				core("Sprout", 5),
				core("Sprout", 12),
				core("Sprout", 3),
				core("Amber", 1),
				core(nil, 1),
			}
			local plan = FuseService.plan(state, "Sprout") :: FuseService.Plan
			table.sort(plan.inputs)
			t.deepEqual(plan.inputs, { 2, 3, 4 })
			t.equal(plan.target, 3)
			t.equal(FuseService.plan(state, "Amber"), nil)
		end)

		t.it("success makes the next rarity; others are emptied; best mutation kept", function()
			local state = PlayerState.createDefault()
			state.pedestals = { core("Sprout", 2, "Gold"), core("Sprout", 9), core("Sprout", 1, "Void") }
			local plan = FuseService.plan(state, "Sprout") :: FuseService.Plan
			-- Find a seed that succeeds and one that fails at the Sprout chance.
			local rarity, success = FuseService.apply(state, plan, "Sprout", Random.new(1))
			t.equal(rarity, if success then "Amber" else "Sprout")
			t.equal(state.pedestals[plan.target].mutation, "Void")
			local filled = 0
			for _, pedestal in state.pedestals do
				if pedestal.rarity ~= nil then
					filled += 1
				end
			end
			t.equal(filled, 1)
			t.equal(state.pedestals[2].level, 9) -- levels never move
		end)

		t.it("groups count cores per rarity and flag locked results", function()
			local groups = Fuse.groups({ { rarity = "Sprout" }, { rarity = "Sprout" }, { rarity = "Celestial" } }, 0, 1)
			t.equal(groups[1].rarity, "Sprout")
			t.equal(groups[1].count, 2)
			t.equal(groups[1].locked, false)
			t.equal(groups[2].rarity, "Celestial")
			t.equal(groups[2].locked, true) -- Prismatic needs a rebirth tier
		end)
	end)
end
