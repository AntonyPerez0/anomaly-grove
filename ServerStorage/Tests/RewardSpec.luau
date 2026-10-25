--!strict
-- M9-10 codes + group reward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local RewardService = require(ServerScriptService.RewardService)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Free rewards (M9-10)", function()
		t.it("codes are case/space-insensitive and reject junk", function()
			t.equal(RewardService.normalize("  grove "), "GROVE")
			t.equal(RewardService.normalize("Zo nes"), "ZONES")
			t.equal(RewardService.normalize(""), nil)
			t.equal(RewardService.normalize("drop;table"), nil)
			t.equal(RewardService.normalize(string.rep("A", 40)), nil)
		end)

		t.it("a code works once per account", function()
			local state = PlayerState.createDefault()
			local reward = RewardService.check(state, "GROVE")
			t.truthy(reward ~= nil)
			state.codes.GROVE = true
			local again, reason = RewardService.check(state, "GROVE")
			t.equal(again, nil)
			t.truthy(reason ~= nil)
			t.equal((RewardService.check(state, "NOTACODE")), nil)
		end)

		t.it("every configured code is already normalised", function()
			for code in Config.FreeRewards.Codes do
				t.equal(RewardService.normalize(code), code)
			end
		end)
	end)
end
