--!strict
-- Companions (M9-07). Remote SetCompanion(id | "None"): equip an unlocked
-- companion (its perk stats flow through Perks.compute via state.companion) or
-- put it away. The "Companion" player attribute drives every client's visual.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)

local CompanionService = {}

-- Pure: may this state equip `id`? ("None" always works.)
function CompanionService.canEquip(state: Types.PlayerState, id: string): (boolean, string?)
	if id == "None" then
		return true, nil
	end
	local def = Perks.companion(id)
	if not def then
		return false, "unknown companion"
	end
	if not Perks.companionUnlocked(def, state.skills) then
		return false, `needs {def.skill} {def.level}`
	end
	return true, nil
end

function CompanionService.equip(player: Player, id: string): boolean
	local state = PlayerState.get(player)
	local ok, reason = CompanionService.canEquip(state, id)
	if not ok then
		Remotes.get("TutorialToast"):FireClient(player, `Locked: {reason}`)
		return false
	end
	state.companion = if id == "None" then nil else id
	player:SetAttribute("Companion", state.companion)
	SkillService.publish(player, state) -- refresh perk mirrors (MonsterSight, seed bag...)
	print(`[CompanionService] {player.Name} companion -> {id}`)
	return true
end

function CompanionService.init()
	task.spawn(function()
		Remotes.get("SetCompanion").OnServerEvent:Connect(function(player, id)
			if type(id) == "string" and #id <= 32 then
				CompanionService.equip(player, id)
			end
		end)
	end)
end

return CompanionService
