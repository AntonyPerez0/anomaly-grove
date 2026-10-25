--!strict
-- Daily quests (M6-02): deterministic rolls, progress caps, claim rules, rewards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(ServerScriptService.PlayerState)
local QuestService = require(ServerScriptService.QuestService)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("QuestService", function()
		t.it("rolls PerDay distinct quests, same for the same day + player", function()
			local a = QuestService.roll(20000, 11822142171)
			local b = QuestService.roll(20000, 11822142171)
			t.equal(#a, Config.Quests.PerDay)
			local seen: { [string]: boolean } = {}
			for i, quest in a do
				t.equal(quest.id, b[i].id)
				t.truthy(not seen[quest.id], "quests must be distinct")
				seen[quest.id] = true
				t.equal(quest.progress, 0)
			end
		end)

		t.it("re-rolls only when the day changes", function()
			local state = PlayerState.createDefault()
			t.truthy(QuestService.ensureDay(state, 100, 1))
			t.equal(QuestService.ensureDay(state, 100, 1), false)
			t.truthy(QuestService.ensureDay(state, 101, 1))
		end)

		t.it("records progress capped at the goal and claims once", function()
			local state = PlayerState.createDefault()
			state.quests = { day = 1, list = { { id = "harvest", goal = 3, progress = 0, claimed = false } } }
			QuestService.recordState(state, "harvest", 2)
			t.equal((state.quests :: any).list[1].progress, 2)
			local ok, reason = QuestService.claimState(state, 1)
			t.equal(ok, false)
			t.equal(reason, "not complete")
			QuestService.recordState(state, "harvest", 10)
			t.equal((state.quests :: any).list[1].progress, 3) -- capped
			local before = state.cash
			local claimed, reward = QuestService.claimState(state, 1)
			t.truthy(claimed)
			t.equal(state.cash - before, reward)
			local again = QuestService.claimState(state, 1)
			t.equal(again, false)
		end)

		t.it("ignores other kinds and bad indexes", function()
			local state = PlayerState.createDefault()
			state.quests = { day = 1, list = { { id = "plant", goal = 1, progress = 0, claimed = false } } }
			t.equal(QuestService.recordState(state, "harvest", 1), false)
			t.equal((QuestService.claimState(state, 5)), false)
		end)

		t.it("rewards scale with rebirths", function()
			local base = QuestService.rewardFor("night", 0)
			t.equal(base, 500)
			t.equal(QuestService.rewardFor("night", 2), math.floor(500 * 1.75 ^ 2))
			t.equal(QuestService.rewardFor("night", 0, 0.5), 750)
		end)
	end)
end
