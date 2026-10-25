--!strict
-- Physical leaderboards (M3-06): three boards on the hub platform - Net Worth,
-- Cores Stolen, Night Streak. Idempotent: wipes the Leaderboards folder first.
-- LeaderboardService fills the rows from OrderedDataStore rankings every 60 s.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local LeaderboardBuilder = {}

export type Stat = { key: string, title: string }

LeaderboardBuilder.STATS = {
	{ key = "NetWorth", title = "Net Worth $" },
	{ key = "CoresStolen", title = "Cores Stolen" },
	{ key = "NightStreak", title = "Night Streak" },
	{ key = "TotalLevel", title = "Total Level" }, -- M8-03 skills
} :: { Stat }

local ROWS = Config.Leaderboards.Rows
local HubBuilder = require(script.Parent.HubBuilder)

local WOOD = Color3.fromRGB(122, 86, 58)
local GOLD = Color3.fromRGB(255, 205, 90)

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(240, 240, 235)
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.Parent = parent
	return l
end

-- One board: two wooden legs + a framed dark panel with a SurfaceGui (title + rows).
local function buildBoard(parent: Folder, stat: Stat, position: Vector3, lookAt: Vector3)
	local board = Instance.new("Model")
	board.Name = "Leaderboard_" .. stat.key
	board:SetAttribute("Stat", stat.key)

	local facing = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	for _, side in { -1, 1 } do
		local leg = Instance.new("Part")
		leg.Name = "Post"
		leg.Size = Vector3.new(0.8, 12, 0.8)
		leg.CFrame = facing * CFrame.new(side * 4.6, 6, 0.4)
		leg.Color = WOOD
		leg.Material = Enum.Material.Wood
		leg.Anchored = true
		leg.Parent = board
	end
	local frame = Instance.new("Part")
	frame.Name = "Frame"
	frame.Size = Vector3.new(9.6, 7.6, 0.4)
	frame.CFrame = facing * CFrame.new(0, 7.8, 0.45)
	frame.Color = WOOD
	frame.Material = Enum.Material.Wood
	frame.Anchored = true
	frame.Parent = board

	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(8, 6, 0.5)
	panel.CFrame = facing * CFrame.new(0, 7.8, 0)
	panel.Color = Color3.fromRGB(34, 30, 46)
	panel.Material = Enum.Material.SmoothPlastic
	panel.Anchored = true
	panel.Parent = board
	board.PrimaryPart = panel

	local gui = Instance.new("SurfaceGui")
	gui.Name = "BoardGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50 -- canvas 400x300
	gui.LightInfluence = 0
	gui.Parent = panel

	label(gui, "Title", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 0), stat.title).TextColor3 = GOLD

	for i = 1, ROWS do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, -12, 0, 24)
		row.Position = UDim2.fromOffset(6, 42 + (i - 1) * 26)
		row.BackgroundTransparency = 1
		row.Parent = gui
		label(row, "Name", UDim2.fromScale(0.7, 1), UDim2.fromScale(0, 0), "—").TextXAlignment =
			Enum.TextXAlignment.Left
		label(row, "Value", UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), "").TextXAlignment =
			Enum.TextXAlignment.Right
	end

	board.Parent = parent
end

-- How-to-play sign on the hub deck (GDD 9): teaches the raid loop to new players.
local function buildHubSign(parent: Folder, position: Vector3, lookAt: Vector3)
	local sign = Instance.new("Model")
	sign.Name = "HowToSign"

	local facing = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	local post = Instance.new("Part")
	post.Name = "Post"
	post.Size = Vector3.new(1, 6, 1)
	post.CFrame = facing * CFrame.new(0, 3, 0.4)
	post.Color = WOOD
	post.Material = Enum.Material.Wood
	post.Anchored = true
	post.Parent = sign

	local panel = Instance.new("Part")
	panel.Name = "Panel"
	panel.Size = Vector3.new(10, 7, 0.5)
	panel.CFrame = facing * CFrame.new(0, 8, 0)
	panel.Color = Color3.fromRGB(34, 30, 46)
	panel.Material = Enum.Material.SmoothPlastic
	panel.Anchored = true
	panel.Parent = sign
	sign.PrimaryPart = panel

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = panel
	local body = Instance.new("TextLabel")
	body.Name = "Text"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.FredokaOne
	body.TextColor3 = Color3.fromRGB(235, 240, 235)
	body.TextWrapped = true
	body.TextScaled = true
	body.Text =
		"HOW TO PLAY\n1. Claim a plot\n2. Harvest seeds -> place on pedestals\n3. Earn cash while cores grow\n4. Raid rivals: rip their cores, carry them home\n5. Survive the night - monsters hunt in the fog"
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Parent = gui

	sign.Parent = parent
end

function LeaderboardBuilder.build(): string
	local root = Workspace:FindFirstChild("AnomalyGrove")
	if not root then
		error("MapBuilder.build() must run before LeaderboardBuilder.build()", 2)
	end
	local old = root:FindFirstChild("Leaderboards")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	folder.Parent = root

	-- Boards line both sides of the hub deck, facing the spawn (HubBuilder frame:
	-- X along the wall, -Z toward the map centre).
	local hub = HubBuilder.frame()
	local center = hub.Position
	local function at(x: number, z: number): Vector3
		return (hub * CFrame.new(x, 0, z)).Position
	end
	buildBoard(folder, LeaderboardBuilder.STATS[1], at(-24, -10), center)
	buildBoard(folder, LeaderboardBuilder.STATS[2], at(-24, 6), center)
	buildBoard(folder, LeaderboardBuilder.STATS[3], at(24, -10), center)
	buildBoard(folder, LeaderboardBuilder.STATS[4], at(24, -22), center) -- deck spans z -28..20
	buildHubSign(folder, at(24, 6), center)
	return `[LeaderboardBuilder] built {#LeaderboardBuilder.STATS} leaderboards ({ROWS} rows each) + how-to sign`
end

return LeaderboardBuilder
