-- Event pills under the top band, from the server's Workspace attributes:
--  * Grove Warden boss (M9-03): beacon progress while a Warden night runs;
--  * weekly Eclipse Event (M9-09): time left while it runs, or a countdown in
--    the last 24 h before it starts.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "BossHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local pill = Instance.new("TextLabel")
pill.AnchorPoint = Vector2.new(0.5, 0)
pill.Position = UDim2.new(0.5, 0, 0, 128)
pill.Size = UDim2.fromOffset(250, 30)
pill.BackgroundColor3 = Color3.fromRGB(40, 20, 60)
pill.BackgroundTransparency = 0.15
pill.Font = Enum.Font.FredokaOne
pill.TextScaled = true
pill.TextColor3 = Color3.fromRGB(230, 200, 255)
pill.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = pill
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 4)
padding.PaddingBottom = UDim.new(0, 4)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = pill
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(190, 110, 255)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = pill

local function refresh()
	-- Portrait phones stack: side-menu grid, then the GOAL pill (46 px), then us.
	local camera = Workspace.CurrentCamera
	local narrow = camera ~= nil and camera.ViewportSize.X < 600
	local top = 128
	if narrow then
		local side = player.PlayerGui:FindFirstChild("SideMenu")
		local column = side and side:FindFirstChild("Column")
		top = if column and column:IsA("GuiObject")
			then column.AbsolutePosition.Y + column.AbsoluteSize.Y + 6 + 46 + 6
			else 178
	end
	pill.Position = UDim2.new(0.5, 0, 0, top)
	local active = Workspace:GetAttribute("WardenActive") == true
	gui.Enabled = active
	if active then
		local lit = Workspace:GetAttribute("WardenLit") or 0
		local total = Workspace:GetAttribute("WardenTotal") or 4
		pill.Text = `GROVE WARDEN · beacons {lit}/{total}`
	end
end

for _, name in { "WardenActive", "WardenLit", "WardenTotal" } do
	Workspace:GetAttributeChangedSignal(name):Connect(refresh)
end
refresh()

-- Weekly event pill (its own ScreenGui so it can show next to the boss pill).
local weeklyGui = Instance.new("ScreenGui")
weeklyGui.Name = "WeeklyHUD"
weeklyGui.ResetOnSpawn = false
weeklyGui.DisplayOrder = 11
weeklyGui.Enabled = false
weeklyGui.Parent = player:WaitForChild("PlayerGui")
local weeklyPill = pill:Clone()
weeklyPill.BackgroundColor3 = Color3.fromRGB(60, 25, 20)
weeklyPill.TextColor3 = Color3.fromRGB(255, 200, 170)
local weeklyStroke = weeklyPill:FindFirstChildOfClass("UIStroke")
if weeklyStroke then
	weeklyStroke.Color = Color3.fromRGB(255, 130, 90)
end
weeklyPill.Parent = weeklyGui

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

local syncedAt, leftAtSync, startsAtSync = os.clock(), 0, math.huge
local function syncWeekly()
	syncedAt = os.clock()
	leftAtSync = Workspace:GetAttribute("WeeklySecondsLeft") or 0
	startsAtSync = Workspace:GetAttribute("WeeklyStartsIn") or math.huge
end
Workspace:GetAttributeChangedSignal("WeeklySecondsLeft"):Connect(syncWeekly)
Workspace:GetAttributeChangedSignal("WeeklyStartsIn"):Connect(syncWeekly)
syncWeekly()

task.spawn(function()
	while true do
		local elapsed = os.clock() - syncedAt
		local active = Workspace:GetAttribute("WeeklyActive") == true
		local startsIn = startsAtSync - elapsed
		weeklyGui.Enabled = active or startsIn < 86400
		if active then
			weeklyPill.Text = if leftAtSync > 0
				then `ECLIPSE EVENT · {clock(leftAtSync - elapsed)} left`
				else "ECLIPSE EVENT · live now"
		else
			weeklyPill.Text = `Eclipse Event in {clock(startsIn)}`
		end
		-- Sit under the boss pill when both show (refresh() keeps pill placed).
		refresh()
		weeklyPill.Position = pill.Position + UDim2.fromOffset(0, if gui.Enabled then 36 else 0)
		task.wait(1)
	end
end)
