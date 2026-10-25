--!strict
-- M9-03 Grove Warden boss night.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local BossService = require(ServerScriptService.BossService)
local EventService = require(ServerScriptService.EventService)
local MonsterAI = require(ServerScriptService.MonsterAI)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Grove Warden (M9-03)", function()
		t.it("beacons ring the forest, clear of the pond", function()
			local spots = BossService.beaconPositions()
			t.equal(#spots, Config.Boss.Beacons)
			local pond = Config.Map.Pond
			for _, spot in spots do
				t.near(spot.Magnitude, Config.Boss.BeaconRadius, 1e-3)
				t.truthy(spot.Magnitude < Config.Map.ForestRadius)
				t.truthy((spot - Vector3.new(pond.X, 0, pond.Z)).Magnitude > pond.Radius + 6)
			end
		end)

		t.it("Warden nights come every WardenEvery-th night; Blood Moon wins ties", function()
			local every = Config.Events.WardenEvery
			t.equal(EventService.rollFor("Night", every, 0), "WardenNight")
			local both = every * Config.Events.BloodMoonEvery
			t.equal(EventService.rollFor("Night", both, 0), "BloodMoon")
		end)

		t.it("lighters earn the bonus; everyone earns at least the income floor", function()
			local plain = BossService.rewardFor(0, 1000, false)
			t.equal(plain, 1000 * Config.Boss.RewardSeconds)
			t.equal(BossService.rewardFor(0, 1000, true), math.floor(plain * (1 + Config.Boss.LighterBonus)))
			t.equal(BossService.rewardFor(0, 0, false), Config.Boss.RewardBase)
		end)

		t.it("the Warden slams by the Golem rules with its own numbers", function()
			local w = Config.Monsters.Warden
			local m = { kind = "Warden", lungeState = "none", lungeUntil = 0, lastAttack = 0 }
			t.equal(MonsterAI.golemSlamStep(m, 10, w.SlamRange), "windup")
			t.equal(MonsterAI.golemSlamStep(m, 10, w.SlamRange + 1), nil)
		end)
	end)
end
