--!strict
-- Profile schema + migration rules (M2-01).
local ServerScriptService = game:GetService("ServerScriptService")
local Profile = require(ServerScriptService.Profile)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Profile", function()
		t.it("default profile matches GDD section 7", function()
			local profile = Profile.newDefault()
			t.equal(profile.schemaVersion, Profile.currentVersion())
			t.equal(profile.plotIndex, nil)
			t.equal(profile.cash, 0)
			t.equal(#profile.pedestals, 1)
			t.equal(profile.pedestals[1].rarity, nil)
			t.equal(profile.pedestals[1].vaultLocked, false)
			t.deepEqual(profile.defenses, {})
			t.deepEqual(profile.gadgets, {})
			t.equal(profile.rebirths, 0)
			t.deepEqual(profile.indexDiscovered, {})
			t.equal(profile.coresStolen, 0)
			t.equal(profile.nightStreak, 0)
			t.truthy(profile.lastSeen > 0)
		end)

		t.it("pre-schema (v0) data migrates to v1 with defaults filled", function()
			local v0 = {
				cash = 250,
				plotIndex = 3,
				pedestals = { { rarity = "Amber", completedCycles = 2 } },
				coresStolen = 4,
				lastSeen = 1700000000,
				-- no schemaVersion field
			}
			local profile = Profile.migrate(v0)
			t.equal(profile.schemaVersion, Profile.currentVersion())
			t.equal(profile.cash, 250)
			t.equal(profile.plotIndex, 3)
			t.equal(profile.pedestals[1].rarity, "Amber")
			t.equal(profile.pedestals[1].completedCycles, 2)
			t.equal(profile.pedestals[1].tickFrac, 0) -- missing field filled
			t.equal(profile.pedestals[1].vaultLocked, false)
			t.equal(profile.coresStolen, 4)
			t.equal(profile.rebirths, 0) -- missing field filled
			t.equal(profile.lastSeen, 1700000000)
		end)

		t.it("partial v1 data merges safely", function()
			local partial = { schemaVersion = 1, cash = 99 }
			local profile = Profile.migrate(partial)
			t.equal(profile.cash, 99)
			t.equal(#profile.pedestals, 1) -- default pedestal kept
		end)

		t.it("corrupt payloads fall back to a fresh default", function()
			t.equal(Profile.migrate("garbage").cash, 0)
			t.equal(Profile.migrate(42).schemaVersion, Profile.currentVersion())
			t.equal(Profile.migrate(nil).rebirths, 0)
		end)

		t.it("v1 saves migrate to v2 with fresh quests + daily streak (M6)", function()
			local profile = Profile.migrate({ schemaVersion = 1, cash = 500 })
			t.equal(profile.schemaVersion, Profile.currentVersion())
			t.equal(profile.cash, 500)
			t.equal(profile.quests.day, -1)
			t.deepEqual(profile.quests.list, {})
			t.equal(profile.daily.streak, 0)
		end)

		t.it("v2 quest rows + streak round-trip; corrupt rows dropped", function()
			local profile = Profile.migrate({
				schemaVersion = 2,
				-- (typed as any: the second row is deliberately malformed)
				quests = {
					day = 20000,
					list = {
						{ id = "harvest", goal = 10, progress = 4, claimed = false },
						{ id = 5, goal = "x" } :: any,
					},
				},
				daily = { lastClaimDay = 19999, streak = 3 },
			} :: any)
			t.equal(profile.quests.day, 20000)
			t.equal(#profile.quests.list, 1)
			t.equal(profile.quests.list[1].progress, 4)
			t.equal(profile.daily.streak, 3)
		end)

		t.it("negative numbers are clamped to zero", function()
			local profile = Profile.migrate({ schemaVersion = 1, cash = -5, coresStolen = -2 })
			t.equal(profile.cash, 0)
			t.equal(profile.coresStolen, 0)
		end)

		t.it("out-of-range plotIndex resets to nil", function()
			local profile = Profile.migrate({ schemaVersion = 1, plotIndex = 12 })
			t.equal(profile.plotIndex, nil)
		end)

		t.it("valid defense entries survive migration (M3-02)", function()
			local profile = Profile.migrate({
				schemaVersion = 1,
				defenses = {
					{ kind = "LaserDoor", slot = 1 },
					{ kind = "TrapTile", slot = 2 },
				},
			})
			t.equal(#profile.defenses, 2)
			t.equal(profile.defenses[1].kind, "LaserDoor")
			t.equal(profile.defenses[2].slot, 2)
		end)

		t.it("corrupt defense entries are dropped, valid ones kept", function()
			local badDefenses: { any } = {
				{ kind = "LaserDoor", slot = 1 },
				"garbage",
				{ kind = "Nuke", slot = 3 },
				{ kind = "TrapTile" }, -- missing slot
				{ kind = "TrapTile", slot = "two" },
				{ kind = "Turret", slot = 2 },
			}
			local profile = Profile.migrate({ schemaVersion = 1, defenses = badDefenses })
			t.equal(#profile.defenses, 2)
			t.equal(profile.defenses[1].kind, "LaserDoor")
			t.equal(profile.defenses[2].kind, "Turret")
		end)

		t.it("non-table defenses field resets to empty", function()
			local profile = Profile.migrate({ schemaVersion = 1, defenses = "nope" } :: any)
			t.deepEqual(profile.defenses, {})
		end)

		t.it("tutorial flags default false and merge from saves (M3-10)", function()
			local fresh = Profile.migrate({ schemaVersion = 1 })
			t.equal(fresh.tutorial.claimed, false)
			t.equal(fresh.tutorial.stealHint, false)
			local partial = Profile.migrate({
				schemaVersion = 1,
				tutorial = { claimed = true, placed = true, harvested = "yes" },
			} :: any)
			t.equal(partial.tutorial.claimed, true)
			t.equal(partial.tutorial.placed, true)
			t.equal(partial.tutorial.harvested, false) -- non-boolean dropped
			t.equal(partial.tutorial.stealHint, false)
		end)
	end)
end
