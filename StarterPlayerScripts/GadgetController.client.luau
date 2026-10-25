--!strict
-- Gadget input (M2-07): Q fires the owned Dash Boots. The server validates
-- ownership and cooldown; this only sends intent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once.
if player:GetAttribute("GadgetControllerInitialized") then
	return
end
player:SetAttribute("GadgetControllerInitialized", true)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		Remotes.get("UseGadget"):FireServer("DashBoots")
	elseif input.KeyCode == Enum.KeyCode.R then
		Remotes.get("UseGadget"):FireServer("SmokeBomb")
	elseif input.KeyCode == Enum.KeyCode.G then
		Remotes.get("UseGadget"):FireServer("Lantern")
	elseif input.KeyCode == Enum.KeyCode.T then
		-- Aim from the camera forward; the server clamps to gadget range.
		local camera = workspace.CurrentCamera
		local aim = camera and (camera.CFrame.Position + camera.CFrame.LookVector * 1000)
		Remotes.get("UseGadget"):FireServer("Grapple", aim)
	end
end)
