--!strict
-- Gadget rules (M2-07): purchase + cooldown gates for Dash Boots.
local ServerScriptService = game:GetService("ServerScriptService")
local GadgetSystem = require(ServerScriptService.GadgetSystem)
local PlayerState = require(ServerScriptService.PlayerState)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("GadgetSystem", function()
		t.it("purchase needs the GDD price (4000)", function()
			local state = PlayerState.createDefault()
			state.cash = 3999
			local ok, reason = GadgetSystem.checkPurchase(state, "DashBoots")
			t.truthy(not ok)
			t.equal(reason, "not enough cash (need 4000)")
			state.cash = 4000
			local ok2, reason2 = GadgetSystem.checkPurchase(state, "DashBoots")
			t.truthy(ok2)
			t.equal(reason2, "ok")
		end)

		t.it("rejects a second purchase of the same gadget", function()
			local state = PlayerState.createDefault()
			state.cash = 8000
			state.gadgets["DashBoots" :: any] = true
			local ok, reason = GadgetSystem.checkPurchase(state, "DashBoots")
			t.truthy(not ok)
			t.equal(reason, "already owned")
		end)

		t.it("rejects unknown gadget names", function()
			local state = PlayerState.createDefault()
			state.cash = math.huge
			local ok, reason = GadgetSystem.checkPurchase(state, "TeleportHack" :: any)
			t.truthy(not ok)
			t.equal(reason, "unknown gadget")
		end)

		t.it("use requires ownership", function()
			local state = PlayerState.createDefault()
			local ok, reason = GadgetSystem.checkUse(state, "DashBoots", 0, 10)
			t.truthy(not ok)
			t.equal(reason, "not owned")
			state.gadgets["DashBoots" :: any] = true
			local ok2, _ = GadgetSystem.checkUse(state, "DashBoots", 0, 10)
			t.truthy(ok2)
		end)

		t.it("cooldown gate rejects reuse inside 20 s", function()
			local state = PlayerState.createDefault()
			state.gadgets["DashBoots" :: any] = true
			local now = 100
			local readyAt = now + Config.Gadgets.DashBoots.cooldown -- just used
			local ok, reason = GadgetSystem.checkUse(state, "DashBoots", readyAt, now + 5)
			t.truthy(not ok)
			t.truthy(string.find(reason, "on cooldown") ~= nil)
			local ok2, _ = GadgetSystem.checkUse(state, "DashBoots", readyAt, now + 20)
			t.truthy(ok2)
		end)

		t.it("GDD tuning: 4 s burst of +20 speed, 20 s cooldown", function()
			t.equal(Config.Gadgets.DashBoots.burstBonus, 20)
			t.equal(Config.Gadgets.DashBoots.burstSeconds, 4)
			t.equal(Config.Gadgets.DashBoots.cooldown, 20)
			t.equal(Config.Prices.DashBoots, 4000)
		end)

		t.it("Smoke Bomb tuning: 3 s cover, 45 s cooldown, price 6000", function()
			t.equal(Config.Gadgets.SmokeBomb.duration, 3)
			t.equal(Config.Gadgets.SmokeBomb.cooldown, 45)
			t.equal(Config.Prices.SmokeBomb, 6000)
		end)

		t.it("Grapple tuning: 60 studs, 25 s cooldown, price 10000", function()
			t.equal(Config.Gadgets.Grapple.range, 60)
			t.equal(Config.Gadgets.Grapple.cooldown, 25)
			t.equal(Config.Prices.Grapple, 10000)
		end)
	end)
end
