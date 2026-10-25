--!strict
-- Monetization placeholders (M3-04): placeholder IDs never grant; ownership goes
-- through an injectable provider so specs stub it without MarketplaceService.
local ServerScriptService = game:GetService("ServerScriptService")
local MonetizationService = require(ServerScriptService.MonetizationService)
local PlayerState = require(ServerScriptService.PlayerState)
local StealSystem = require(ServerScriptService.StealSystem)
local OfflineGrowth = require(ServerScriptService.OfflineGrowth)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("MonetizationService", function()
		t.it("placeholder ID 0 is never treated as owned in production", function()
			local player = { UserId = 1, Name = "Test" } :: any
			MonetizationService.setOwnershipProvider(nil)
			t.equal(MonetizationService.ownsPass(player :: any, 0), false)
			t.equal(MonetizationService.ownsPass(player :: any, -5), false)
		end)

		t.it("applyVaultLock grants pedestal 1 only for pass owners", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 3
			-- No provider and no real player: not owned -> no grant.
			MonetizationService.setOwnershipProvider(nil)
			t.equal(MonetizationService.applyVaultLockToState(state), false)
			t.equal(state.pedestals[1].vaultLocked, false)

			-- Stubbed owner (the test stand-in for a fake owned pass): grant applies
			-- and is idempotent.
			MonetizationService.setOwnershipProvider(function()
				return true
			end)
			t.equal(MonetizationService.applyVaultLockToState(state), true)
			t.equal(state.pedestals[1].vaultLocked, true)
			t.equal(MonetizationService.applyVaultLockToState(state), false) -- already locked
			MonetizationService.setOwnershipProvider(nil)
		end)

		t.it("steal from a vault-locked pedestal is rejected", function()
			local plots = { { index = 0, owner = nil, pendingReleaseAt = nil } }
			local victim = PlayerState.createDefault()
			victim.plotIndex = 0
			victim.pedestals[1].rarity = "Amber"
			victim.pedestals[1].vaultLocked = true
			local thief = PlayerState.createDefault()
			thief.plotIndex = 5
			local ok, reason = StealSystem.canStealFrom(plots :: any, thief, 0, victim, 1)
			t.truthy(not ok)
			t.equal(reason, "that pedestal is vault locked")
		end)

		t.it("unlocked pedestals stay stealable", function()
			local plots = { { index = 0, owner = nil, pendingReleaseAt = nil } }
			local victim = PlayerState.createDefault()
			victim.plotIndex = 0
			victim.pedestals[1].rarity = "Amber"
			victim.pedestals[1].vaultLocked = false
			local thief = PlayerState.createDefault()
			thief.plotIndex = 5
			local ok, reason = StealSystem.canStealFrom(plots :: any, thief, 0, victim, 1)
			t.truthy(ok)
			t.equal(reason, "ok")
		end)

		t.it("lockdown grants up to the nightly cap, then rejects (M3-05)", function()
			local state = PlayerState.createDefault()
			state.plotIndex = 2
			MonetizationService.setOwnershipProvider(nil)
			for _ = 1, Config.Lockdown.MaxPerNight do
				t.equal(MonetizationService.applyLockdownToState(state), true)
				t.truthy(state.lockdownUntil > os.clock())
			end
			t.equal(state.lockdownsUsed, Config.Lockdown.MaxPerNight)
			t.equal(MonetizationService.applyLockdownToState(state), false) -- cap reached
			t.equal(Config.Lockdown.MaxPerNight, 3)
			t.equal(Config.Lockdown.Seconds, 60)
		end)

		t.it("an active lockdown blocks stealing", function()
			local plots = { { index = 0, owner = nil, pendingReleaseAt = nil } }
			local victim = PlayerState.createDefault()
			victim.plotIndex = 0
			victim.pedestals[1].rarity = "Amber"
			victim.lockdownUntil = os.clock() + 30
			local thief = PlayerState.createDefault()
			thief.plotIndex = 5
			local ok, reason = StealSystem.canStealFrom(plots :: any, thief, 0, victim, 1)
			t.truthy(not ok)
			t.equal(reason, "that plot is locked down")
		end)

		t.it("expired lockdown does not block stealing", function()
			local plots = { { index = 0, owner = nil, pendingReleaseAt = nil } }
			local victim = PlayerState.createDefault()
			victim.plotIndex = 0
			victim.pedestals[1].rarity = "Amber"
			victim.lockdownUntil = os.clock() - 1
			local thief = PlayerState.createDefault()
			thief.plotIndex = 5
			local ok, reason = StealSystem.canStealFrom(plots :: any, thief, 0, victim, 1)
			t.truthy(ok)
			t.equal(reason, "ok")
		end)

		t.it("Offline Mutation Luck pass doubles the offline chance (M3-05)", function()
			local player = { UserId = 3, Name = "Lucky" } :: any
			MonetizationService.setOwnershipProvider(nil)
			t.near(
				MonetizationService.offlineMutationChance(player :: any, Config.Offline.Chance),
				Config.Offline.Chance
			)
			MonetizationService.setOwnershipProvider(function()
				return true
			end)
			t.near(
				MonetizationService.offlineMutationChance(player :: any, Config.Offline.Chance),
				Config.Offline.Chance * Config.Offline.LuckMultiplier
			)
			MonetizationService.setOwnershipProvider(nil)
		end)

		t.it("computeFor honors the injected mutation chance", function()
			local now = os.time()
			local lastSeen = now - 400 -- 1 roll per core at the 300 s interval
			local function seededPedestals(): { Types.PedestalState }
				return {
					{
						rarity = "Amber" :: any,
						mutation = nil,
						hatchAt = nil,
						tickFrac = 0,
						completedCycles = 0,
						vaultLocked = false,
						mutationProgress = 0,
						mutationBoost = false,
						level = 1,
					},
					{
						rarity = "Frost" :: any,
						mutation = nil,
						hatchAt = nil,
						tickFrac = 0,
						completedCycles = 0,
						vaultLocked = false,
						mutationProgress = 0,
						mutationBoost = false,
						level = 1,
					},
				}
			end
			-- chance 0: no mutation can trigger.
			local none = OfflineGrowth.computeFor(seededPedestals(), lastSeen, now, 0)
			t.equal(#none.mutations, 0)
			-- chance 1: every roll succeeds, but one mutation max per core.
			local all = OfflineGrowth.computeFor(seededPedestals(), lastSeen, now, 1)
			t.equal(#all.mutations, 2)
		end)
	end)
end
