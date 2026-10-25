--!strict
-- Perf probe (M3-09): samples frame time every 10 s and logs fps + entity counts
-- so low-end tuning has a console trail. Intentionally tiny: one connection, no
-- per-frame allocations beyond the running sum.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

if player:GetAttribute("PerfProbeInitialized") then
	return
end
player:SetAttribute("PerfProbeInitialized", true)

local SAMPLE_SECONDS = 10
local frames = 0
local elapsed = 0

local function countMonsters(): number
	local count = 0
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and (descendant.Name == "Fogling" or descendant.Name == "Stalker") then
			count += 1
		end
	end
	return count
end

local function currentQuality(): string
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	return if ok and level then tostring(level) else "?"
end

RunService.RenderStepped:Connect(function(deltaTime)
	frames += 1
	elapsed += deltaTime
	if elapsed >= SAMPLE_SECONDS then
		local fps = frames / elapsed
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		print(
			`[PerfProbe] fps={string.format("%.0f", fps)} frame={string.format("%.1f", elapsed / frames * 1000)}ms quality={currentQuality()} monsters={countMonsters()} viewport={math.floor(
				viewport.X
			)}x{math.floor(viewport.Y)}`
		)
		frames = 0
		elapsed = 0
	end
end)
