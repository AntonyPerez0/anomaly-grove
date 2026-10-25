-- Wild-zone title banner (2026-10-18): entering Crystal Hollow / Spore Mire /
-- Ruined Shrine fades in the zone name, what its seeds do, the Foraging level
-- they need and who guards it. Pure presentation; the server owns the rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Zones = require(ReplicatedStorage.Shared.Zones)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ZoneBanner"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.fromScale(0.5, 0.4) -- below the toast + GOAL pill
frame.Size = UDim2.fromScale(0.8, 0.13)
frame.BackgroundTransparency = 1
frame.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.fromScale(1, 0.58)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextTransparency = 1
title.TextStrokeTransparency = 1
title.Parent = frame

local subtitle = Instance.new("TextLabel")
subtitle.Position = UDim2.fromScale(0, 0.6)
subtitle.Size = UDim2.fromScale(1, 0.32)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamBold
subtitle.TextScaled = true
subtitle.TextColor3 = Color3.new(1, 1, 1)
subtitle.TextTransparency = 1
subtitle.TextStrokeTransparency = 1
subtitle.Parent = frame

local showToken = 0

local function fade(visible: boolean, seconds: number)
	local info = TweenInfo.new(seconds)
	local text = if visible then 0 else 1
	local stroke = if visible then 0.3 else 1
	for _, label in { title, subtitle } do
		TweenService:Create(label, info, { TextTransparency = text, TextStrokeTransparency = stroke }):Play()
	end
end

local function show(zone: Zones.ZoneDef)
	showToken += 1
	local token = showToken
	title.Text = string.upper(zone.name)
	title.TextColor3 = zone.color
	subtitle.Text = `{zone.blurb} · Foraging {zone.foraging} · guarded by {zone.guardianName}`
	fade(true, 0.4)
	task.delay(4, function()
		if showToken == token then
			fade(false, 0.8)
		end
	end)
end

local current: string? = nil
while true do
	task.wait(0.5)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local zone = Zones.at(root.Position)
		local id = zone and zone.id
		if id ~= current then
			current = id
			if zone then
				show(zone)
			end
		end
	end
end
