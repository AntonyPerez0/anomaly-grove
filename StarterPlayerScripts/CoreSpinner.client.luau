--!strict
-- Core spinner (M5-07): spins and bobs every gem tagged "SpinCore" locally, so the
-- server never streams per-frame CFrames. Only gems near the camera animate.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

if player:GetAttribute("CoreSpinnerInitialized") then
	return
end
player:SetAttribute("CoreSpinnerInitialized", true)

local TAG = "SpinCore"
local ANIMATE_DISTANCE = 140
local SPIN_SPEED = 1.3 -- radians per second
local BOB_HEIGHT = 0.25
local BOB_SPEED = 2.2

type Entry = { base: CFrame, phase: number }
local tracked: { [BasePart]: Entry } = {}

local function track(instance: Instance)
	if instance:IsA("BasePart") and not tracked[instance] then
		tracked[instance] = { base = instance.CFrame, phase = math.random() * math.pi * 2 }
	end
end

local function untrack(instance: Instance)
	if instance:IsA("BasePart") then
		tracked[instance] = nil
	end
end

for _, instance in CollectionService:GetTagged(TAG) do
	track(instance)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	for part, entry in tracked do
		if not part.Parent then
			tracked[part] = nil
			continue
		end
		local basePos = entry.base.Position
		if (basePos - camPos).Magnitude > ANIMATE_DISTANCE then
			continue
		end
		local rotation = entry.base - basePos
		local bob = math.sin(t * BOB_SPEED + entry.phase) * BOB_HEIGHT
		-- Spin about world Y while keeping the gem's own tilt.
		part.CFrame = CFrame.new(basePos + Vector3.new(0, bob, 0))
			* CFrame.Angles(0, t * SPIN_SPEED + entry.phase, 0)
			* rotation
	end
end)
