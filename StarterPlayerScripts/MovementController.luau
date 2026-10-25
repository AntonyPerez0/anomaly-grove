--!strict
-- Movement feel (GDD 4): sprint and slide. Client-authoritative for responsiveness;
-- server clamps extremes later (M4 hardening). Mobile auto-sprints at full stick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer

local sprinting = false
local sliding = false
local lastSlideEnd = 0

local function currentBaseSpeed(): number
	-- Carrying a core already slows the player (attribute set by the server).
	local carried = player:GetAttribute("CarriedCore")
	local base = Config.Movement.WalkSpeed
	if carried ~= nil and carried ~= "" then
		local heavy = carried == "Void" or carried == "Celestial"
		base *= if heavy then Config.Steal.HeavyCarrySpeedMultiplier else Config.Steal.CarrySpeedMultiplier
	end
	return base
end

local function applySpeed()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = currentBaseSpeed()
	if sprinting then
		speed = Config.Movement.SprintSpeed
	end
	if sliding then
		speed = Config.Movement.SlideSpeed
	end
	humanoid.WalkSpeed = speed
end

-- Slide: short burst forward, only while sprinting, with a cooldown.
local function trySlide()
	if sliding or os.clock() - lastSlideEnd < Config.Movement.SlideCooldown then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return
	end
	sliding = true
	applySpeed()
	-- A forward shove sells the slide on any device.
	local direction = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if direction.Magnitude > 0.01 then
		root.AssemblyLinearVelocity = direction.Unit * Config.Movement.SlideSpeed + Vector3.new(0, 4, 0)
	end
	task.delay(Config.Movement.SlideDuration, function()
		sliding = false
		lastSlideEnd = os.clock()
		applySpeed()
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.C or input.KeyCode == Enum.KeyCode.LeftControl then
		trySlide()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		applySpeed()
	end
end)

-- Expose the slide for the touch pad (TouchControls calls this via _G-free module path).
local MovementController = {}

function MovementController.trySlide()
	trySlide()
end

function MovementController.setAutoSprint(enabled: boolean)
	sprinting = enabled
	applySpeed()
end

-- Respawn/reset handling.
player.CharacterAdded:Connect(function(character)
	sliding = false
	sprinting = false
	character:WaitForChild("Humanoid")
	task.wait(0.1)
	applySpeed()
end)

return MovementController
