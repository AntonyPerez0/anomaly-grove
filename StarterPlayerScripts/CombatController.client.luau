--!strict
-- Zapper combat input: F key or left-click swings at the nearest player in range.
-- The server re-validates everything; the client only selects a target and shows
-- a white flash when it gets tagged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once
-- (respawn/clone); every run after the first must be a no-op.
if player:GetAttribute("CombatInitialized") then
	return
end
player:SetAttribute("CombatInitialized", true)

-- Build the tag-flash overlay once.
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "TagFlash"
flashGui.ResetOnSpawn = false
flashGui.DisplayOrder = 50
local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.Parent = flashGui
flashGui.Parent = player:WaitForChild("PlayerGui")

local function nearestVictim(): Player?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local best: Player? = nil
	local bestDist = Config.Zapper.Range + 2
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist <= bestDist then
					bestDist = dist
					best = other
				end
			end
		end
	end
	return best
end

local function swing()
	local victim = nearestVictim()
	if victim then
		Remotes.get("TagHit"):FireServer(victim)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.MouseButton1 then
		swing()
	end
end)

-- Victim feedback: white flash on tag.
Remotes.get("TagHit").OnClientEvent:Connect(function(_attackerName: string)
	local tween = game:GetService("TweenService"):Create(
		flash,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 2, true),
		{ BackgroundTransparency = 0.25 }
	)
	tween:Play()
end)
