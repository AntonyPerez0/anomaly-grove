--!strict
-- Skills UI (M8-02/03): a SKILLS side-menu button, a modal with every skill's
-- level, XP bar, next unlock and cape toggle, RuneScape-style XP drops ("+120 🌿")
-- and a level-up banner. Reads the server's "Skills" JSON attribute; capes go
-- through the validated SetCape remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("SkillsControllerInitialized") then
	return
end
player:SetAttribute("SkillsControllerInitialized", true)

local C = UITheme.COLORS
local META = Config.Skills.Meta :: { [string]: { icon: string, color: Color3, verb: string } }
local ORDER = Config.Skills.Order
local DESIGN = Vector2.new(420, 360) -- short: lists scroll, so phones get a bigger scale
local ROW_HEIGHT = 92

local function skillsTable(): { [string]: number }
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Skills") or "{}")
	end)
	return if ok and type(decoded) == "table" then decoded else {}
end

-- Modal ----------------------------------------------------------------------
type Row = {
	frame: Frame,
	level: TextLabel,
	fill: Frame,
	xp: TextLabel,
	nextText: TextLabel,
	cape: TextButton,
}

local gui = Instance.new("ScreenGui")
gui.Name = "SkillsModal"
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
local title = UITheme.label(root, "Title", "🎓 SKILLS", C.gold)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 36)
title.TextXAlignment = Enum.TextXAlignment.Left
local totalLabel = UITheme.label(root, "Total", "", C.muted)
totalLabel.Position = UDim2.fromOffset(16, 44)
totalLabel.Size = UDim2.new(1, -32, 0, 20)
totalLabel.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(12, 72)
list.Size = UDim2.new(1, -24, 1, -84)
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = root
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local rows: { [string]: Row } = {}
for index, skill in ORDER do
	local meta = META[skill]
	local frame = UITheme.panel(list, skill, C.panel)
	frame.LayoutOrder = index
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	local icon = UITheme.label(frame, "Icon", meta.icon, Color3.new(1, 1, 1))
	icon.Position = UDim2.fromOffset(8, 10)
	icon.Size = UDim2.fromOffset(44, 44)
	local name = UITheme.label(frame, "Name", skill, meta.color)
	name.Position = UDim2.fromOffset(58, 6)
	name.Size = UDim2.new(1, -170, 0, 24)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local level = UITheme.label(frame, "Level", "", C.gold)
	level.AnchorPoint = Vector2.new(1, 0)
	level.Position = UDim2.new(1, -10, 0, 6)
	level.Size = UDim2.fromOffset(100, 24)
	level.TextXAlignment = Enum.TextXAlignment.Right
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(58, 34)
	barBack.Size = UDim2.new(1, -68, 0, 18)
	barBack.BackgroundColor3 = C.panelDeep
	barBack.Parent = frame
	UITheme.corner(barBack, 9)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = meta.color
	fill.Parent = barBack
	UITheme.corner(fill, 9)
	local xp = UITheme.label(barBack, "Xp", "", C.text)
	xp.Size = UDim2.fromScale(1, 1)
	local nextText = UITheme.label(frame, "Next", "", C.muted)
	nextText.Position = UDim2.fromOffset(10, 58)
	nextText.Size = UDim2.new(1, -130, 0, 26)
	nextText.TextXAlignment = Enum.TextXAlignment.Left
	nextText.TextWrapped = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 14
	cap.Parent = nextText
	local cape = UITheme.button(frame, "Cape", "WEAR CAPE", "gold")
	cape.AnchorPoint = Vector2.new(1, 1)
	cape.Position = UDim2.new(1, -8, 1, -6)
	cape.Size = UDim2.fromOffset(112, 28)
	cape.Visible = false
	local skillName = skill
	cape.Activated:Connect(function()
		local worn = player:GetAttribute("Cape")
		Remotes.get("SetCape"):FireServer(if worn == skillName then "None" else skillName)
	end)
	rows[skill] = { frame = frame, level = level, fill = fill, xp = xp, nextText = nextText, cape = cape }
end
gui.Parent = player:WaitForChild("PlayerGui")

local function render()
	local skills = skillsTable()
	local worn = player:GetAttribute("Cape")
	for _, skill in ORDER do
		local row = rows[skill]
		local xp = skills[skill] or 0
		local level, into, span = Progression.progress(xp)
		row.level.Text = `Lv {level}`
		if span > 0 then
			row.fill.Size = UDim2.fromScale(math.clamp(into / span, 0, 1), 1)
			row.xp.Text = `{Progression.format(xp)} XP · {Progression.format(span - into)} to {level + 1}`
		else
			row.fill.Size = UDim2.fromScale(1, 1)
			row.xp.Text = `{Progression.format(xp)} XP · MAXED`
		end
		local nextLevel, lines = Perks.nextReward(skill, level)
		row.nextText.Text = if nextLevel
			then `Next at {nextLevel}: {table.concat(lines, ", ")}`
			else `{META[skill].verb}. Cape earned!`
		row.cape.Visible = level >= Config.Skills.CapeLevel
		row.cape.Text = if worn == skill then "TAKE OFF" else "WEAR CAPE"
	end
	local total = Perks.totalLevel(skills)
	totalLabel.Text = `Total level {total} / {Config.Skills.CapeLevel * #ORDER}   ·   tap a 99 to wear its cape`
end
player:GetAttributeChangedSignal("Skills"):Connect(function()
	if gui.Enabled then
		render()
	end
end)
player:GetAttributeChangedSignal("Cape"):Connect(render)

UIRouter.register("Skills", {
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
	UIRouter.close("Skills")
end)

-- Side-menu button ---------------------------------------------------------------
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Skills", "🎓", "teal")
	b.LayoutOrder = 3
	b.Size = UDim2.fromOffset(64, 64)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 18)
	end
	local cap = UITheme.label(b, "Caption", "SKILLS", Color3.new(1, 1, 1))
	cap.AnchorPoint = Vector2.new(0.5, 1)
	cap.Position = UDim2.new(0.5, 0, 1, 16)
	cap.Size = UDim2.new(1, 8, 0, 16)
	b.Activated:Connect(function()
		UIRouter.toggle("Skills")
	end)
end)

-- XP drops + level-up banner ---------------------------------------------------------
local fx = Instance.new("ScreenGui")
fx.Name = "SkillFx"
fx.ResetOnSpawn = false
fx.DisplayOrder = 30
fx.IgnoreGuiInset = true
fx.Parent = player:WaitForChild("PlayerGui")

local dropSlot = 0
local function xpDrop(skill: string, amount: number)
	local meta = META[skill]
	if not meta then
		return
	end
	dropSlot = (dropSlot + 1) % 4
	local label = UITheme.label(fx, "Drop", `+{Progression.format(amount)} {meta.icon}`, meta.color)
	label.AnchorPoint = Vector2.new(1, 0.5)
	label.Position = UDim2.new(0.97, 0, 0.5, dropSlot * 26)
	label.Size = UDim2.fromOffset(150, 26)
	label.TextXAlignment = Enum.TextXAlignment.Right
	local tween = TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.97, 0, 0.5, dropSlot * 26 - 70),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

local banner: Frame? = nil
local function levelBanner(skill: string, level: number, lines: { string })
	local meta = META[skill]
	if not meta then
		return
	end
	if banner then
		banner:Destroy()
	end
	local frame = UITheme.panel(fx, "LevelUp", C.panelDeep)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -120)
	frame.Size = UDim2.fromOffset(380, 92)
	local scale = Instance.new("UIScale")
	local camera = workspace.CurrentCamera
	scale.Scale = if camera then math.clamp(camera.ViewportSize.X * 0.9 / 380, 0.6, 1.1) else 1
	scale.Parent = frame
	local head = UITheme.label(frame, "Head", `{meta.icon} {string.upper(skill)} LEVEL {level}!`, meta.color)
	head.Position = UDim2.fromOffset(10, 6)
	head.Size = UDim2.new(1, -20, 0, 40)
	local rewardText = table.concat(lines, "  ·  ")
	if #lines == 0 then
		local nextLevel, nextLines = Perks.nextReward(skill, level)
		rewardText = if nextLevel then `Next at {nextLevel}: {table.concat(nextLines, ", ")}` else "Keep going!"
	end
	local reward = UITheme.label(frame, "Reward", rewardText, C.text)
	reward.Position = UDim2.fromOffset(10, 50)
	reward.Size = UDim2.new(1, -20, 0, 32)
	reward.TextWrapped = true
	banner = frame
	TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 110),
	}):Play()
	task.delay(3.8, function()
		if banner == frame then
			local out = TweenService:Create(frame, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -140) })
			out:Play()
			out.Completed:Wait()
			frame:Destroy()
		end
	end)
end

Remotes.get("SkillEvent").OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any)
	if kind == "xp" and type(a) == "table" then
		for skill, amount in a :: { [string]: number } do
			xpDrop(skill, amount)
		end
	elseif kind == "level" and type(a) == "string" then
		levelBanner(a, b :: number, (c or {}) :: { string })
	end
end)
