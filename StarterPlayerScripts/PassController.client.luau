--!strict
-- Grove Pass UI (M8-10): PASS side-menu button (red badge = rewards to claim) and
-- a modal with the season track: level, XP bar and one row per level with its
-- reward and a claim button. Claims go through the validated ClaimPass remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("PassControllerInitialized") then
	return
end
player:SetAttribute("PassControllerInitialized", true)

local C = UITheme.COLORS
local DESIGN = Vector2.new(420, 360) -- short: lists scroll, so phones get a bigger scale
local LEVELS = Config.Pass.Levels

local function claimedSet(): { [string]: boolean }
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("PassClaimed") or "{}")
	end)
	return if ok and type(value) == "table" then value else {}
end

-- Same formula as PassService.rewardFor (shown as an estimate at today's income).
local function rewardText(level: number): string
	local cfg = Config.Pass
	local rate = player:GetAttribute("IncomeRate") or 0
	local cash = math.max(500, math.floor(rate * (cfg.CashSecondsBase + cfg.CashSecondsStep * level)))
	local tokens = (if level % cfg.TokenEvery == 0 then 1 else 0) + (if level == cfg.Levels then cfg.FinalTokens else 0)
	return `~${Progression.format(cash)}{if tokens > 0 then `  +{tokens} token{if tokens == 1 then "" else "s"}` else ""}`
end

-- Modal ------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PassModal"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Enabled = false
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.55
dim.Parent = gui
local root = UITheme.panel(gui, "Root", C.panelDeep)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.52)
root.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "🎟 GROVE PASS", C.gold)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local season = UITheme.label(root, "Season", Config.Pass.SeasonName, C.muted)
season.Position = UDim2.fromOffset(16, 40)
season.Size = UDim2.new(1, -32, 0, 18)
season.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local barBack = Instance.new("Frame")
barBack.Position = UDim2.fromOffset(16, 64)
barBack.Size = UDim2.new(1, -32, 0, 22)
barBack.BackgroundColor3 = C.panel
barBack.Parent = root
UITheme.corner(barBack, 11)
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = C.gold
barFill.Parent = barBack
UITheme.corner(barFill, 11)
local barText = UITheme.label(barBack, "Text", "", C.text)
barText.Size = UDim2.fromScale(1, 1)

local list = Instance.new("ScrollingFrame")
list.Name = "Track"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(12, 94)
list.Size = UDim2.new(1, -24, 1, -106)
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = root
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

type Row = { frame: Frame, reward: TextLabel, button: TextButton }
local rows: { Row } = {}
for level = 1, LEVELS do
	local frame = UITheme.panel(list, "Level" .. level, C.panel)
	frame.LayoutOrder = level
	frame.Size = UDim2.new(1, -8, 0, 56)
	local number = UITheme.label(frame, "Number", `Lv {level}`, C.gold)
	number.Position = UDim2.fromOffset(10, 0)
	number.Size = UDim2.new(0, 70, 1, 0)
	number.TextXAlignment = Enum.TextXAlignment.Left
	local reward = UITheme.label(frame, "Reward", "", C.text)
	reward.Position = UDim2.fromOffset(80, 0)
	reward.Size = UDim2.new(1, -210, 1, 0)
	reward.TextXAlignment = Enum.TextXAlignment.Left
	local button = UITheme.button(frame, "Claim", "", "grey")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -8, 0.5, 0)
	button.Size = UDim2.fromOffset(112, 44)
	local lvl = level
	button.Activated:Connect(function()
		Remotes.get("ClaimPass"):FireServer(lvl)
	end)
	rows[level] = { frame = frame, reward = reward, button = button }
end
gui.Parent = player:WaitForChild("PlayerGui")

local badge: TextLabel? = nil

local function render()
	local xp = player:GetAttribute("PassXp") or 0
	local level = Perks.passLevel(xp)
	local spent = 0
	for l = 1, level do
		spent += Perks.passLevelXp(l)
	end
	if level >= LEVELS then
		barFill.Size = UDim2.fromScale(1, 1)
		barText.Text = `Level {level} / {LEVELS} · COMPLETE!`
	else
		local need = Perks.passLevelXp(level + 1)
		barFill.Size = UDim2.fromScale(math.clamp((xp - spent) / need, 0, 1), 1)
		barText.Text =
			`Level {level} / {LEVELS} · {Progression.format(xp - spent)} / {Progression.format(need)} pass XP`
	end
	local claimed = claimedSet()
	local ready = 0
	for l, row in rows do
		row.reward.Text = rewardText(l)
		if claimed[tostring(l)] then
			row.button.Text = "✓"
			UITheme.setStyle(row.button, "teal")
		elseif l <= level then
			row.button.Text = "CLAIM"
			UITheme.setStyle(row.button, "gold")
			ready += 1
		else
			row.button.Text = "🔒"
			UITheme.setStyle(row.button, "grey")
		end
	end
	if badge then
		(badge :: TextLabel).Visible = ready > 0
		(badge :: TextLabel).Text = tostring(ready)
	end
end

for _, attribute in { "PassXp", "PassClaimed" } do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if gui.Enabled or attribute == "PassClaimed" then
			render()
		end
	end)
end

UIRouter.register("Pass", {
	open = function()
		render()
		local camera = workspace.CurrentCamera
		if camera then
			fit.Scale = math.clamp(
				math.min(camera.ViewportSize.X * 0.94 / DESIGN.X, camera.ViewportSize.Y * 0.84 / DESIGN.Y),
				0.55,
				1.25
			)
		end
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Pass")
end)

-- Side-menu button + badge (refreshed every few seconds: levels come from XP).
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Pass", "🎟", "gold")
	b.LayoutOrder = 6
	b.Size = UDim2.fromOffset(64, 64)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 18)
	end
	local cap = UITheme.label(b, "Caption", "PASS", Color3.new(1, 1, 1))
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
	badge = dot
	b.Activated:Connect(function()
		UIRouter.toggle("Pass")
	end)
	while true do
		render()
		task.wait(3)
	end
end)
