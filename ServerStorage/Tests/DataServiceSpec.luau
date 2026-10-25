--!strict
-- Save-safety (M4-03): the serialized shape and the save retry path, driven with
-- a fake DataStore and a stub player so no real DataStores are touched.

local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService.DataService)
local PlayerState = require(ServerScriptService.PlayerState)
local Profile = require(ServerScriptService.Profile)

local TestKit = require(script.Parent.TestKit)

-- A Player stand-in that satisfies the attribute calls save/serialize make.
local function stubPlayer(name: string): any
	local calls = 0
	return {
		Name = name,
		UserId = 424242,
		Parent = nil,
		SetAttribute = function(_self, _key, _value)
			calls += 1
		end,
		GetAttribute = function(_self, _key)
			return nil
		end,
		callCount = function()
			return calls
		end,
	}
end

return function(t: TestKit.Context)
	t.describe("DataService", function()
		t.it("serialize keeps floors and flags, never yields", function()
			local state = PlayerState.createDefault()
			state.cash = 12.9
			state.plotIndex = 3
			state.rebirths = 2
			state.tutorial.claimed = true
			state.defenses = { { kind = "LaserDoor", slot = 1 } }
			local payload = DataService.serialize(state)
			t.equal(payload.cash, 12) -- floored, never negative/float
			t.equal(payload.plotIndex, 3)
			t.equal(payload.rebirths, 2)
			t.equal(payload.tutorial.claimed, true)
			t.equal(payload.tutorial.harvested, false)
			t.equal(#payload.defenses, 1)
			t.equal(payload.defenses[1].kind, "LaserDoor")
			t.truthy(payload.lastSeen > 0)
		end)

		t.it("owned gadgets are saved (regression: they used to serialize as {})", function()
			local state = PlayerState.createDefault()
			local owned: any = state.gadgets
			owned.DashBoots = true
			owned.Grapple = true
			local payload = DataService.serialize(state)
			t.deepEqual(payload.gadgets, { "DashBoots", "Grapple" })
			t.equal(payload.schemaVersion, Profile.currentVersion())
			t.equal(payload.quests.day, -1)
		end)

		t.it("save commits on the first attempt with a healthy store", function()
			local writes = 0
			DataService.setStoreForTests({
				UpdateAsync = function(_self, _key, transform)
					writes += 1
					transform(nil)
					return true
				end,
			} :: any)
			local player = stubPlayer("Healthy")
			PlayerState.get(player :: any) -- state must exist for save to see it
			DataService.setLoadedForTests(player :: any, true)
			local outcome = DataService.save(player :: any)
			t.equal(outcome, "committed")
			t.equal(writes, 1)
			PlayerState.remove(player :: any)
			DataService.setStoreForTests(nil)
		end)

		t.it("flaky store retries and still commits (counted)", function()
			local attempts = 0
			DataService.setStoreForTests({
				UpdateAsync = function(_self, _key, transform)
					attempts += 1
					transform(nil)
					if attempts < 3 then
						error("DataStore throttled (simulated)")
					end
					return true
				end,
			} :: any)
			local player = stubPlayer("Flaky")
			PlayerState.get(player :: any)
			DataService.setLoadedForTests(player :: any, true)
			local outcome = DataService.save(player :: any)
			t.equal(outcome, "committed")
			t.equal(attempts, 3) -- two failures, one success
			PlayerState.remove(player :: any)
			DataService.setStoreForTests(nil)
		end)

		t.it("a persistently failing store gives up after 3 attempts", function()
			DataService.setStoreForTests({
				UpdateAsync = function()
					error("DataStore down (simulated)")
				end,
			} :: any)
			local player = stubPlayer("Doomed")
			PlayerState.get(player :: any)
			DataService.setLoadedForTests(player :: any, true)
			local outcome = DataService.save(player :: any)
			t.equal(outcome, "error")
			PlayerState.remove(player :: any)
			DataService.setStoreForTests(nil)
		end)

		t.it("a profile that never loaded is never saved (would wipe the real save)", function()
			local writes = 0
			DataService.setStoreForTests({
				UpdateAsync = function()
					writes += 1
					return true
				end,
			} :: any)
			local player = stubPlayer("NotLoaded")
			PlayerState.get(player :: any)
			t.equal(DataService.save(player :: any), "not-loaded")
			t.equal(writes, 0)
			PlayerState.remove(player :: any)
			DataService.setStoreForTests(nil)
		end)

		t.it("session lock: load only when free / own / stale; save only while owned", function()
			local now = 1000000
			t.equal(DataService.canTakeLock(nil, "A", now), true)
			t.equal(DataService.canTakeLock({ cash = 5 }, "A", now), true)
			t.equal(DataService.canTakeLock({ _lock = { job = "A", at = now } }, "A", now), true)
			t.equal(DataService.canTakeLock({ _lock = { job = "B", at = now - 10 } }, "A", now), false)
			t.equal(DataService.canTakeLock({ _lock = { job = "B", at = now - 3600 } }, "A", now), true)
			local saved = DataService.saveValue({ _lock = { job = "A", at = 1 } }, { cash = 7 }, "A", now, false)
			t.equal(saved.cash, 7)
			t.equal(saved._lock.job, "A")
			t.equal(saved._lock.at, now)
			t.equal(DataService.saveValue({ _lock = { job = "B", at = now } }, { cash = 7 }, "A", now, false), nil)
			t.equal(DataService.saveValue({ _lock = { job = "A", at = now } }, { cash = 7 }, "A", now, true)._lock, nil)
		end)
	end)
end
