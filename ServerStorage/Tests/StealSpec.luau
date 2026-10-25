--!strict
-- Steal rules (M1-09/M1-10): who may steal what, carry speed, drop conditions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StealSystem = require(ServerScriptService.StealSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local Types = require(ReplicatedStorage.Shared.Types)
local Config = require(ReplicatedStorage.Shared.Config)

local TestKit = require(script.Parent.TestKit)

local function plotsWith(index: number, owner: any): { { index: number, owner: any, pendingReleaseAt: number? } }
	local plots: { { index: number, owner: any, pendingReleaseAt: number? } } = {}
	for i = 0, Config.Map.Plots - 1 do
		plots[i + 1] = { index = i, owner = if i == index then owner else nil, pendingReleaseAt = nil }
	end
	return plots
end

local function securedPedestal(rarity: Types.Rarity): Types.PedestalState
	return {
		rarity = rarity,
		mutation = nil,
		hatchAt = nil,
		tickFrac = 0,
		completedCycles = 1,
		vaultLocked = false,
		mutationProgress = 0,
		mutationBoost = false,
		level = 1,
	}
end

return function(t: TestKit.Context)
	t.describe("StealSystem.canStealFrom", function()
		local victim = PlayerState.createDefault()
		victim.player = { Name = "Vic" } :: any
		victim.plotIndex = 1
		local plots = plotsWith(1, victim.player :: any)

		t.it("rejects a plotless thief", function()
			local thief = PlayerState.createDefault()
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, victim, 1)
			t.truthy(not ok)
			t.equal(reason, "claim a plot first")
		end)

		t.it("rejects stealing from your own plot", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 1
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, victim, 1)
			t.truthy(not ok)
			t.equal(reason, "you cannot steal from your own plot")
		end)

		t.it("rejects an unowned plot", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			local ok, reason = StealSystem.canStealFrom(plots, thief, 3, nil, 1)
			t.truthy(not ok)
			t.equal(reason, "that plot is not owned")
		end)

		t.it("rejects a thief already carrying", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			thief.carried = { kind = "Core", rarity = "Sprout", mutation = nil }
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, victim, 1)
			t.truthy(not ok)
			t.equal(reason, "you are already carrying a core")
		end)

		t.it("rejects an empty or incubating pedestal", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			local empty = PlayerState.createDefault()
			empty.plotIndex = 1
			empty.pedestals[1] = PlayerState.newPedestal()
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, empty, 1)
			t.truthy(not ok)
			t.equal(reason, "no secured core on that pedestal")

			local incubating = PlayerState.createDefault()
			incubating.plotIndex = 1
			incubating.pedestals[1] = PlayerState.newPedestal()
			incubating.pedestals[1].rarity = "Amber"
			incubating.pedestals[1].hatchAt = os.clock() + 30
			local ok2, reason2 = StealSystem.canStealFrom(plots, thief, 1, incubating, 1)
			t.truthy(not ok2)
			t.equal(reason2, "no secured core on that pedestal")
		end)

		t.it("rejects a vault-locked pedestal", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			local locked = PlayerState.createDefault()
			locked.plotIndex = 1
			locked.pedestals[1] = securedPedestal("Amber")
			locked.pedestals[1].vaultLocked = true
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, locked, 1)
			t.truthy(not ok)
			t.equal(reason, "that pedestal is vault locked")
		end)

		t.it("rejects a steal-immune victim", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			local immune = PlayerState.createDefault()
			immune.plotIndex = 1
			immune.pedestals[1] = securedPedestal("Amber")
			immune.stealImmuneUntil = os.clock() + 10
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, immune, 1)
			t.truthy(not ok)
			t.equal(reason, "that core was just secured - steal immunity")
		end)

		t.it("allows a legitimate steal", function()
			local thief = PlayerState.createDefault()
			thief.plotIndex = 0
			local rich = PlayerState.createDefault()
			rich.plotIndex = 1
			rich.pedestals[1] = securedPedestal("Frost")
			local ok, reason = StealSystem.canStealFrom(plots, thief, 1, rich, 1)
			t.truthy(ok)
			t.equal(reason, "ok")
		end)
	end)

	t.describe("StealSystem.carrySpeedMultiplier", function()
		t.it("normal cores slow to 65%", function()
			t.near(StealSystem.carrySpeedMultiplier({ kind = "Core", rarity = "Sprout", mutation = nil }), 0.65)
			t.near(StealSystem.carrySpeedMultiplier({ kind = "Core", rarity = "Ember", mutation = nil }), 0.65)
		end)

		t.it("heavy cores slow to 50%", function()
			t.near(StealSystem.carrySpeedMultiplier({ kind = "Core", rarity = "Void", mutation = nil }), 0.5)
			t.near(StealSystem.carrySpeedMultiplier({ kind = "Core", rarity = "Celestial", mutation = nil }), 0.5)
		end)
	end)

	t.describe("StealSystem tag rules", function()
		t.it("zapper ready check", function()
			local state = PlayerState.createDefault()
			state.zapperReadyAt = os.clock() + 5
			local ok, reason = StealSystem.checkTagReady(state, os.clock())
			t.truthy(not ok)
			t.equal(reason, "zapper on cooldown")
			local ok2, _ = StealSystem.checkTagReady(state, os.clock() + 10)
			t.truthy(ok2)
		end)

		t.it("tag range uses Config + 2 studs tolerance", function()
			t.truthy(StealSystem.tagInRange(Vector3.zero, Vector3.new(Config.Zapper.Range, 0, 0)))
			t.truthy(not StealSystem.tagInRange(Vector3.zero, Vector3.new(Config.Zapper.Range + 5, 0, 0)))
		end)
	end)

	t.describe("StealSystem.canGrabDrop (owner lock)", function()
		local function makeDrop(owner: string, untilSeconds: number): BasePart
			local part = Instance.new("Part")
			part:SetAttribute("LockOwner", owner)
			part:SetAttribute("LockUntil", untilSeconds)
			return part
		end

		t.it("rejects a non-owner inside the lock window", function()
			local drop = makeDrop("Victim", os.clock() + 2)
			local thief = { Name = "Thief" } :: any
			local ok, reason = StealSystem.canGrabDrop(drop, thief :: any, os.clock())
			t.truthy(not ok)
			t.truthy(string.find(reason, "locked for") ~= nil)
		end)

		t.it("allows the owner inside the lock window", function()
			local drop = makeDrop("Victim", os.clock() + 2)
			local ok = StealSystem.canGrabDrop(drop, { Name = "Victim" } :: any, os.clock())
			t.truthy(ok)
		end)

		t.it("allows anyone after the lock expires", function()
			local drop = makeDrop("Victim", os.clock() - 1)
			local ok = StealSystem.canGrabDrop(drop, { Name = "Thief" } :: any, os.clock())
			t.truthy(ok)
		end)
	end)

	t.describe("StealSystem reach gate (M4-02)", function()
		t.it("rejects remote steals from across the map", function()
			local pedestalPos = Vector3.new(175, 3, 0)
			t.truthy(StealSystem.isWithinInteract(pedestalPos + Vector3.new(5, 0, 0), pedestalPos))
			t.truthy(StealSystem.isWithinInteract(pedestalPos + Vector3.new(11, 2, 0), pedestalPos))
			t.truthy(not StealSystem.isWithinInteract(pedestalPos + Vector3.new(40, 0, 0), pedestalPos))
			t.truthy(not StealSystem.isWithinInteract(Vector3.zero, pedestalPos))
		end)
	end)
end
