--!strict
-- "While you were away" login popup (M2-04): cash earned offline and mutation
-- badges, with a Collect button. Built in code; shown by the OfflineSummary event.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local FxSounds = require(script.Parent.FxSounds)

local player = Players.LocalPlayer

local AwayPopup = {}

local COLORS = {
	panel = Color3.fromRGB(28, 32, 42),
	accent = Color3.fromRGB(60, 255, 220),
	gold = Color3.fromRGB(255, 210, 90),
	text = Color3.fromRGB(255, 255, 255),
}

function AwayPopup.show(cashEarned: number, mutationCount: number, elapsedSeconds: number, nextHatch: number?)
	local old = player.PlayerGui:FindFirstChild("AwayPopup")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AwayPopup"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40

	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromScale(0.6, 0.5)
	modal.BackgroundColor3 = COLORS.panel
	modal.BackgroundTransparency = 0.05
	modal.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = modal
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.accent
	stroke.Thickness = 2
	stroke.Parent = modal

	local minutes = math.floor(elapsedSeconds / 60)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = COLORS.accent
	title.TextScaled = true
	title.Text = "While you were away"
	title.Parent = modal

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.Position = UDim2.fromScale(0, 0.3)
	detail.Size = UDim2.fromScale(1, 0.34)
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.FredokaOne
	detail.TextColor3 = COLORS.text
	detail.TextScaled = true
	local mutationLine = if mutationCount > 0
		then ` {mutationCount} core{if mutationCount == 1 then "" else "s"} mutated!`
		else ""
	detail.Text = `$ {cashEarned} earned while away ({minutes} min){mutationLine}`
	detail.Parent = modal

	-- M7-02: tease the next hatch so there is a reason to stay.
	if nextHatch and nextHatch > 0 then
		local teaser = Instance.new("TextLabel")
		teaser.Name = "Teaser"
		teaser.Position = UDim2.fromScale(0, 0.75)
		teaser.Size = UDim2.fromScale(1, 0.09)
		teaser.BackgroundTransparency = 1
		teaser.Font = Enum.Font.FredokaOne
		teaser.TextColor3 = COLORS.gold
		teaser.TextScaled = true
		teaser.Text = if nextHatch >= 60
			then `A core hatches in {math.ceil(nextHatch / 60)} min!`
			else `A core hatches in {nextHatch}s!`
		teaser.Parent = modal
	end

	local badges = Instance.new("Frame")
	badges.Name = "MutationBadges"
	badges.Position = UDim2.fromScale(0.3, 0.61)
	badges.Size = UDim2.fromScale(0.4, 0.13)
	badges.BackgroundTransparency = 1
	badges.Parent = modal
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = badges
	-- One gold badge per mutation (simple and readable at popup size).
	for i = 1, math.min(mutationCount, 5) do
		local badge = Instance.new("Frame")
		badge.Name = "Mutation" .. i
		badge.Size = UDim2.fromScale(0.12, 1)
		badge.BackgroundColor3 = COLORS.gold
		badge.Parent = badges
		local badgeCorner = Instance.new("UICorner")
		badgeCorner.CornerRadius = UDim.new(0.5, 0)
		badgeCorner.Parent = badge
	end

	local collect = Instance.new("TextButton")
	collect.Name = "Collect"
	collect.AnchorPoint = Vector2.new(0.5, 1)
	collect.Position = UDim2.fromScale(0.5, 0.97)
	collect.Size = UDim2.fromScale(0.5, 0.14)
	collect.BackgroundColor3 = COLORS.accent
	collect.Font = Enum.Font.FredokaOne
	collect.TextColor3 = Color3.fromRGB(15, 20, 25)
	collect.TextScaled = true
	collect.Text = "Collect"
	collect.Parent = modal
	local collectCorner = Instance.new("UICorner")
	collectCorner.CornerRadius = UDim.new(0, 10)
	collectCorner.Parent = collect
	collect.Activated:Connect(function()
		gui:Destroy()
	end)

	-- Warm login chord (M3-08): layered engine tones instead of a single chime.
	FxSounds.layered(Config.FxMix.LoginChordSpeeds)

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- Wire the server event once.
if not player:GetAttribute("AwayPopupWired") then
	player:SetAttribute("AwayPopupWired", true)
	Remotes.get("OfflineSummary").OnClientEvent:Connect(function(cashEarned, mutationCount, elapsedSeconds, nextHatch)
		AwayPopup.show(cashEarned :: number, mutationCount :: number, elapsedSeconds :: number, nextHatch :: number?)
	end)
end

return AwayPopup
