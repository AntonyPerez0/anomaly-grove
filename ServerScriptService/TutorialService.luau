--!strict
-- Onboarding toasts (M3-10): one toast per milestone, driven by the real events
-- (claim -> harvest -> place -> steal hint). Flags persist in the profile, so a
-- toast never repeats across sessions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)

local TutorialService = {}

local TEXTS = {
	claimed = "Plot claimed! Harvest the glowing seeds in the forest.",
	harvested = "Seed harvested! Place it on a pedestal in your plot.",
	placed = "Core planted! It earns cash while it grows.",
	stealHint = "Raid a rival's plot and carry a core back to yours!",
}

local function fire(player: Player, key: string)
	local state = PlayerState.get(player)
	local flags = state.tutorial
	if not flags or flags[key :: "claimed" | "harvested" | "placed" | "stealHint"] then
		return
	end
	flags[key :: "claimed" | "harvested" | "placed" | "stealHint"] = true
	Remotes.get("TutorialToast"):FireClient(player, TEXTS[key :: "claimed" | "harvested" | "placed" | "stealHint"])
	print(`[TutorialService] {player.Name} toast: {key}`)
end

-- Event hooks called by the owning systems.
function TutorialService.onClaimed(player: Player)
	fire(player, "claimed")
end

function TutorialService.onHarvested(player: Player)
	fire(player, "harvested")
end

function TutorialService.onPlaced(player: Player)
	fire(player, "placed")
	-- The steal hint follows shortly after the first placement (step 4).
	task.delay(6, function()
		if player.Parent then
			fire(player, "stealHint")
		end
	end)
end

-- Wire once from Main.server: claims arrive through the replicated attribute.
function TutorialService.init()
	local function hook(player: Player)
		player:GetAttributeChangedSignal("PlotIndex"):Connect(function()
			if player:GetAttribute("PlotIndex") ~= nil then
				TutorialService.onClaimed(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

return TutorialService
