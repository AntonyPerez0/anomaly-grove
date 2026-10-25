--!strict
-- Tutorial toast listener (M3-10): the server sends one toast per milestone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ToastBuilder = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("ToastBuilder"))

local player = Players.LocalPlayer

if player:GetAttribute("TutorialToastsWired") then
	return
end
player:SetAttribute("TutorialToastsWired", true)

Remotes.get("TutorialToast").OnClientEvent:Connect(function(text: string)
	ToastBuilder.show(text)
end)
