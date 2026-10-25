--!strict
-- Stats (M2-11): single writer for session stats (coresStolen, nightStreak).
-- Values live in PlayerState and replicate through player attributes.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local FXService = require(script.Parent.FXService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local QuestService = require(script.Parent.QuestService)
local SkillService = require(script.Parent.SkillService)
local EventService = require(script.Parent.EventService)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local StatsService = {}

-- A stolen core was secured onto one of the thief's pedestals.
function StatsService.addCoreStolen(state: Types.PlayerState)
	state.coresStolen += 1
	if state.player then
		state.player:SetAttribute("CoresStolen", state.coresStolen)
	end
end

-- Survived a full night: streak up and pay the bonus; died during it: reset.
-- Returns the new streak.
function StatsService.resolveNight(state: Types.PlayerState, alive: boolean): number
	if alive then
		state.nightStreak += 1
	else
		state.nightStreak = 0
	end
	if state.player then
		state.player:SetAttribute("NightStreak", state.nightStreak)
		if alive then
			FXService.streakStinger(state.player) -- M3-08: streak stinger on survival
			AnalyticsService.onNightSurvive(state) -- M4-04
			QuestService.record(state.player, "night")
			-- M8 skills: Survival for the night (streak adds up to 20 nights' bonus),
			-- Guarding for every defense that stood watch.
			local xp = Config.Skills.Xp
			local survival = xp.nightSurvived + xp.nightStreakBonus * math.min(state.nightStreak, 20)
			if EventService.current() == "BloodMoon" then
				survival *= xp.bloodMoonMultiplier
			end
			SkillService.addXp(state.player, "Survival", survival)
			if #state.defenses > 0 then
				SkillService.addXp(state.player, "Guarding", xp.nightPerDefense * #state.defenses)
			end
		end
	end
	return state.nightStreak
end

return StatsService
