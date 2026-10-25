--!strict
-- Defense rules (M3-01): turret targeting filters and capacity.
local ServerScriptService = game:GetService("ServerScriptService")
local DefenseSystem = require(ServerScriptService.DefenseSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("DefenseSystem.canTarget", function()
		local owner = { Name = "Owner" } :: any
		local raider = { Name = "Raider" } :: any

		t.it("never targets its owner", function()
			local ok, reason = DefenseSystem.canTarget(owner :: any, owner :: any, nil, nil, false, 0)
			t.truthy(not ok)
			t.equal(reason, "owner")
		end)

		t.it("smoke blinds the turret", function()
			local ok, reason = DefenseSystem.canTarget(raider :: any, owner :: any, nil, nil, true, 0)
			t.truthy(not ok)
			t.equal(reason, "smoked")
		end)

		t.it("targets raiders in the open", function()
			local state = PlayerState.createDefault()
			state.plotIndex = nil
			local ok, reason = DefenseSystem.canTarget(raider :: any, owner :: any, state, nil, false, 0)
			t.truthy(ok)
			t.equal(reason, "ok")
		end)

		t.it("does not shoot a player inside their own plot", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 3 -- same plot index the turret defends
			local ok, reason = DefenseSystem.canTarget(raider :: any, owner :: any, state, 3, false, 0)
			t.truthy(not ok)
			t.equal(reason, "inside own plot")
		end)
	end)

	t.describe("DefenseSystem capacity", function()
		t.it("base slots + rebirth bonus", function()
			t.equal(Config.Plot.DefenseBaseSlots + math.min(0, Config.Rebirth.MaxDefenseSlotBonus), 1)
			t.equal(Config.Plot.DefenseBaseSlots + math.min(2, Config.Rebirth.MaxDefenseSlotBonus), 3)
			t.equal(Config.Turret.MaxPerPlot, 2)
			t.equal(Config.Prices.Turret, 2500)
			t.equal(Config.Turret.Range, 30)
			t.equal(Config.Turret.DamagePerSecond, 10)
			t.equal(Config.Turret.StunSeconds, 1.5)
		end)
	end)

	t.describe("Laser door and traps (M3-02)", function()
		t.it("laser tuning matches GDD: 15 dmg/s", function()
			t.equal(Config.LaserDoor.DamagePerSecond, 15)
			t.equal(Config.LaserDoor.TickSeconds, 0.5)
		end)

		t.it("trap tuning matches GDD: root 2s, 10 dmg, 30s recharge, max 3", function()
			t.equal(Config.TrapTile.RootSeconds, 2)
			t.equal(Config.TrapTile.Damage, 10)
			t.equal(Config.TrapTile.RechargeSeconds, 30)
			t.equal(Config.TrapTile.TriggerRadius, 3.5)
			t.equal(Config.TrapTile.MaxPerPlot, 3)
			t.equal(Config.Prices.LaserDoor, 1000)
			t.equal(Config.Prices.TrapTile, 500)
		end)

		t.it("laser beam box hits crossing players, misses pass-bys", function()
			local beam = Instance.new("Part")
			beam.CFrame = CFrame.new(0, 2.5, 0) -- vertical beam across the gap
			-- Dead center: hit.
			t.truthy(DefenseSystem.isInLaserBeam(beam, Vector3.new(0, 2.5, 0)))
			-- Inside the damage box (half extents X 1.5, Y 3, Z 4.5).
			t.truthy(DefenseSystem.isInLaserBeam(beam, Vector3.new(1, 2.5, 4)))
			-- Outside on X: a runner hugging the doorframe edge is safe.
			t.truthy(not DefenseSystem.isInLaserBeam(beam, Vector3.new(2, 2.5, 0)))
			-- Outside on Y: jumping well over the beam is safe.
			t.truthy(not DefenseSystem.isInLaserBeam(beam, Vector3.new(0, 6, 0)))
			-- Outside on Z: far from the gap is safe.
			t.truthy(not DefenseSystem.isInLaserBeam(beam, Vector3.new(0, 2.5, 6)))
			beam:Destroy()
		end)

		t.it("trap radius triggers up close, not from afar", function()
			local platePos = Vector3.new(10, 0.5, -20)
			t.truthy(DefenseSystem.isInTrapRadius(platePos, Vector3.new(12, 0.5, -20))) -- 2 studs
			t.truthy(DefenseSystem.isInTrapRadius(platePos, platePos + Vector3.new(3.4, 0, 0)))
			t.truthy(not DefenseSystem.isInTrapRadius(platePos, platePos + Vector3.new(4, 0, 0)))
		end)
	end)
end
