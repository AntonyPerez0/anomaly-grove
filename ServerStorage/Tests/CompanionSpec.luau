--!strict
-- M9-07 companions.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local CompanionService = require(ServerScriptService.CompanionService)
local PlayerState = require(ServerScriptService.PlayerState)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Companions (M9-07)", function()
		t.it("every companion names a real skill and only uses known perk stats", function()
			local known = {
				seedBag = true,
				xpBoost = true,
				monsterSight = true,
				mutationChance = true,
				income = true,
				hatchSpeed = true,
			}
			for _, def in Config.Companions do
				t.truthy(table.find(Config.Skills.Order, def.skill) ~= nil, def.id)
				for stat in def.stats do
					t.truthy(known[stat], `{def.id}: {stat}`)
				end
			end
		end)

		t.it("the starter is free; others need their skill level", function()
			local state = PlayerState.createDefault()
			t.equal((CompanionService.canEquip(state, "Sprite")), true)
			t.equal((CompanionService.canEquip(state, "Moth")), false)
			t.equal((CompanionService.canEquip(state, "Nope")), false)
			t.equal((CompanionService.canEquip(state, "None")), true)
			state.skills.Alchemy = Progression.xpForLevel(15)
			t.equal((CompanionService.canEquip(state, "Moth")), true)
		end)

		t.it("an equipped companion adds its stats; a locked one adds nothing", function()
			local base = Perks.compute({ skills = {} })
			local withSprite = Perks.compute({ skills = {}, companion = "Sprite" })
			t.equal(Perks.get(withSprite, "seedBag") - Perks.get(base, "seedBag"), 1)
			local lockedMoth = Perks.compute({ skills = {}, companion = "Moth" })
			t.equal(Perks.get(lockedMoth, "mutationChance"), Perks.get(base, "mutationChance"))
		end)
	end)
end
