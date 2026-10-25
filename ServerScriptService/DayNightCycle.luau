--!strict
-- Server-authoritative day/night clock: 240 s day, 120 s night, forever.
-- Broadcasts (phase, secondsRemaining) on PhaseChanged at each transition and to
-- players joining mid-phase; tweens lighting between presets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LightingBuilder = require(game.ServerStorage.Builders.LightingBuilder)

local DayNightCycle = {}

local TRANSITION_SECONDS = 4 -- lighting tween length at each phase start

type Phase = "Day" | "Night"

local currentPhase: Phase = "Day"
local phaseEndsAt = 0 -- os.clock() when the phase flips
local skipRequested = false -- test hook
local phaseStartedCallbacks: { (Phase) -> () } = {}

function DayNightCycle.getPhase(): Phase
	return currentPhase
end

function DayNightCycle.getSecondsRemaining(): number
	return math.max(0, phaseEndsAt - os.clock())
end

-- Other systems (MonsterAI, mutation rolls) subscribe to phase starts.
function DayNightCycle.onPhaseStarted(callback: (Phase) -> ())
	table.insert(phaseStartedCallbacks, callback)
end

-- Test hook: end the current phase early. Settable from any VM through the shared
-- Workspace attribute (execute_luau cannot reach this module's upvalues).
function DayNightCycle.skipToNextPhase()
	Workspace:SetAttribute("SkipPhaseRequested", true)
end

local function phaseLength(phase: Phase): number
	return if phase == "Day" then Config.Cycle.DayLength else Config.Cycle.NightLength
end

local function announce(phase: Phase)
	local length = phaseLength(phase)
	phaseEndsAt = os.clock() + length
	Remotes.get("PhaseChanged"):FireAllClients(phase, length)
	for _, callback in phaseStartedCallbacks do
		task.spawn(callback, phase)
	end
	print(`[DayNightCycle] {phase} begins ({length}s)`)
end

-- Main clock loop. Call once from Main.server.
function DayNightCycle.init()
	LightingBuilder.build()
	currentPhase = "Day"
	announce("Day")
	LightingBuilder.applyDay(TRANSITION_SECONDS)

	task.spawn(function()
		while true do
			local length = phaseLength(currentPhase)
			local t0 = os.clock()
			while os.clock() - t0 < length do
				if skipRequested or Workspace:GetAttribute("SkipPhaseRequested") == true then
					skipRequested = false
					Workspace:SetAttribute("SkipPhaseRequested", false)
					break
				end
				task.wait(0.25)
			end
			currentPhase = if currentPhase == "Day" then "Night" else "Day" :: Phase
			announce(currentPhase)
			if currentPhase == "Day" then
				LightingBuilder.applyDay(TRANSITION_SECONDS)
			else
				LightingBuilder.applyNight(TRANSITION_SECONDS)
			end
		end
	end)

	-- Late joiners get the current phase immediately.
	Players.PlayerAdded:Connect(function(player)
		Remotes.get("PhaseChanged"):FireClient(player, currentPhase, DayNightCycle.getSecondsRemaining())
	end)
end

return DayNightCycle
