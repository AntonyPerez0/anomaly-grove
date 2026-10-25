--!strict
-- Camera feel (M6-05): the field of view widens with speed (sprint, slide, Dash
-- Boots, grapple) and settles back when walking or standing, plus a short punch
-- when the player gets tagged. Purely cosmetic and client-only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

if player:GetAttribute("CameraFeelInitialized") then
	return
end
player:SetAttribute("CameraFeelInitialized", true)

local BASE_FOV = 70
local MAX_EXTRA = 14 -- degrees at full speed
local WALK_SPEED = 16
local FOV_PER_STUD = 0.55 -- extra degrees per stud/s above walking speed
local LERP = 6 -- per second

local punch = 0

-- Tag hit (TagFlash already flashes the screen): a quick FOV punch sells the impact.
Remotes.get("Juice").OnClientEvent:Connect(function(kind: string)
	if kind == "Shake" then
		punch = 6
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root or not root:IsA("BasePart") then
		return
	end
	-- Planar speed (ignores falling) drives the kick.
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local target = BASE_FOV + math.clamp((speed - WALK_SPEED) * FOV_PER_STUD, 0, MAX_EXTRA) + punch
	punch = math.max(0, punch - dt * 30)
	camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, dt * LERP)
end)
