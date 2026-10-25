--!strict
-- Daily login reward UI (M6-03): a 7-tile streak calendar. Auto-opens shortly after
-- joining when today's reward is unclaimed; a DAILY side button (with a badge) opens
-- it any time. Claims go through the validated ClaimDaily remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("DailyControllerInitialized") then
	return
end
player:SetAttribute("DailyControllerInitialized", true)

local C = UITheme.COLORS
local DAYS = #Config.Daily.Rewards

local gui = Instance.new("ScreenGui")
gui.Name = "DailyModal"
gui.ResetOnSpawn = false
gui.DisplayOrder = 45
gui.Enabled = false
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Parent = gui
local root = UITheme.panel(gui, "Root", C.panelDeep)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(400, 330)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "🎁 DAILY REWARDS", C.gold)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 36)
title.TextXAlignment = Enum.TextXAlignment.Left
local sub = UITheme.label(root, "Sub", "Come back every day - day 7 gives a Grove Heart seed!", C.muted)
sub.Position = UDim2.fromOffset(16, 46)
sub.Size = UDim2.new(1, -32, 0, 18)
sub.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(14, 74)
grid.Size = UDim2.new(1, -28, 0, 176)
grid.Parent = root
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.new(0.25, -6, 0, 82)
layout.CellPadding = UDim2.fromOffset(8, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

type Tile = { frame: Frame, amount: TextLabel, check: TextLabel }
local tiles: { Tile } = {}
for day = 1, DAYS do
	local frame = UITheme.panel(grid, "Day" .. day, C.panel)
	frame.LayoutOrder = day
	local label = UITheme.label(frame, "Day", `DAY {day}`, C.muted)
	label.Position = UDim2.fromOffset(4, 4)
	label.Size = UDim2.new(1, -8, 0, 18)
	local icon = UITheme.label(frame, "Icon", if day == Config.Daily.GroveSeedDay then "🌟" else "💰", C.text)
	icon.Position = UDim2.fromOffset(4, 22)
	icon.Size = UDim2.new(1, -8, 0, 30)
	local amount = UITheme.label(frame, "Amount", "", C.green)
	amount.Position = UDim2.fromOffset(4, 54)
	amount.Size = UDim2.new(1, -8, 0, 22)
	local check = UITheme.label(frame, "Check", "✓", C.green)
	check.Size = UDim2.fromScale(1, 1)
	check.TextTransparency = 0.1
	check.Visible = false
	tiles[day] = { frame = frame, amount = amount, check = check }
end

local claim = UITheme.button(root, "Claim", "CLAIM!", "gold")
claim.AnchorPoint = Vector2.new(0.5, 1)
claim.Position = UDim2.new(0.5, 0, 1, -14)
claim.Size = UDim2.fromOffset(220, 54)
claim.Activated:Connect(function()
	Remotes.get("ClaimDaily"):FireServer()
end)
gui.Parent = player:WaitForChild("PlayerGui")

-- Side-menu button with a badge.
local badge: TextLabel? = nil
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Daily", "🎁", "gold")
	b.LayoutOrder = 4
	b.Size = UDim2.fromOffset(64, 64)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 18)
	end
	local cap = UITheme.label(b, "Caption", "DAILY", Color3.new(1, 1, 1))
	cap.AnchorPoint = Vector2.new(0.5, 1)
	cap.Position = UDim2.new(0.5, 0, 1, 16)
	cap.Size = UDim2.new(1, 8, 0, 16)
	local dot = UITheme.label(b, "Badge", "!", Color3.new(1, 1, 1))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -2, 0, 2)
	dot.Size = UDim2.fromOffset(22, 22)
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = C.red
	UITheme.corner(dot, 11)
	dot.Visible = false
	b.Activated:Connect(function()
		UIRouter.toggle("Daily")
	end)
	badge = dot
end)

type Status = { canClaim: boolean, dayIndex: number, streak: number, rewards: { number } }

local function status(): Status?
	local raw = player:GetAttribute("Daily")
	if type(raw) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	return if ok and type(decoded) == "table" then decoded :: any else nil
end

local function render()
	local s = status()
	if not s then
		return
	end
	for day, tile in tiles do
		local reward = s.rewards[day] or 0
		tile.amount.Text = if day == Config.Daily.GroveSeedDay
			then `${UITheme.short(reward)}+🌱`
			else `${UITheme.short(reward)}`
		local claimedToday = not s.canClaim
		local done = day < s.dayIndex or (claimedToday and day == s.dayIndex)
		tile.check.Visible = done
		local stroke = tile.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if day == s.dayIndex then C.gold else C.stroke
			stroke.Thickness = if day == s.dayIndex then 4 else 3
		end
	end
	claim.Text = if s.canClaim then `CLAIM DAY {s.dayIndex}!` else "COME BACK TOMORROW"
	UITheme.setStyle(claim, if s.canClaim then "gold" else "grey")
	if badge then
		(badge :: TextLabel).Visible = s.canClaim
	end
end
player:GetAttributeChangedSignal("Daily"):Connect(render)

UIRouter.register("Daily", {
	open = function()
		render()
		local camera = workspace.CurrentCamera
		if camera then
			fit.Scale =
				math.clamp(math.min(camera.ViewportSize.X * 0.94 / 400, camera.ViewportSize.Y * 0.8 / 330), 0.6, 1.25)
		end
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Daily")
end)

-- Auto-open once per session when a reward is waiting (after the away popup).
task.spawn(function()
	for _ = 1, 30 do
		local s = status()
		if s then
			render()
			if s.canClaim then
				task.wait(4)
				local away = player.PlayerGui:FindFirstChild("AwayPopup")
				while away and away:IsA("ScreenGui") and away.Enabled do
					task.wait(0.5)
				end
				if UIRouter.current() == nil then
					UIRouter.open("Daily")
				end
			end
			return
		end
		task.wait(1)
	end
end)
