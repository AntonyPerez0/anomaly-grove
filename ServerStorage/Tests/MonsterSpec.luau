--!strict
-- Monster AI rules (M1-12): plot safe-zone geometry.
local ServerScriptService = game:GetService("ServerScriptService")
local MonsterAI = require(ServerScriptService.MonsterAI)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("MonsterAI.isInsidePlot", function()
		local size = Config.Map.PlotSize -- 70
		local center = Vector3.new(100, 0, 100)

		t.it("center point is inside", function()
			t.truthy(MonsterAI.isInsidePlot(Vector3.new(100, 0, 100), center, size))
		end)

		t.it("just inside the edge is inside", function()
			t.truthy(MonsterAI.isInsidePlot(Vector3.new(100 + size / 2 - 1, 0, 100), center, size))
		end)

		t.it("just outside the edge is outside", function()
			t.truthy(not MonsterAI.isInsidePlot(Vector3.new(100 + size / 2 + 1, 0, 100), center, size))
		end)

		t.it("corner beyond the edge is outside", function()
			t.truthy(not MonsterAI.isInsidePlot(Vector3.new(100 + size / 2 + 1, 0, 100 + size / 2 + 1), center, size))
		end)
	end)

	t.describe("MonsterAI.stalkerLungeStep (M4 telegraphed lunge)", function()
		local function stalker(lungeState: string, lungeUntil: number, lastAttack: number, cooldown: number)
			return {
				kind = "Stalker",
				lungeState = lungeState,
				lungeUntil = lungeUntil,
				lastAttack = lastAttack,
				attackCooldown = cooldown,
			}
		end

		t.it("Foglings never lunge", function()
			t.equal(
				MonsterAI.stalkerLungeStep(
					{ kind = "Fogling", lungeState = "none", lungeUntil = 0, lastAttack = 0, attackCooldown = 1 },
					10,
					5
				),
				nil
			)
		end)

		t.it("windup starts in range when the attack is off cooldown", function()
			t.equal(MonsterAI.stalkerLungeStep(stalker("none", 0, 0, 3), 10, 20), "windup")
			t.equal(Config.Monsters.Stalker.LungeRange >= 20, true)
		end)

		t.it("no windup while far away or on cooldown", function()
			t.equal(
				MonsterAI.stalkerLungeStep(stalker("none", 0, 0, 3), 10, Config.Monsters.Stalker.LungeRange + 1),
				nil
			)
			t.equal(MonsterAI.stalkerLungeStep(stalker("none", 0, 9, 3), 10, 5), nil) -- cooldown running
		end)

		t.it("the lunge starts when the windup expires", function()
			t.equal(MonsterAI.stalkerLungeStep(stalker("windup", 12, 0, 3), 12, 20), "lunge")
			t.equal(MonsterAI.stalkerLungeStep(stalker("windup", 12, 0, 3), 11.9, 20), nil) -- still winding up
		end)
	end)
end
