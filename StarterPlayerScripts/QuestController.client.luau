--!strict
-- Daily quests UI (M6-02): a QUESTS side-menu button with a red badge when a reward
-- is ready, and a modal listing the day's three quests (progress bar, reward, claim).
-- Reads the server's replicated "Quests" JSON attribute; claims go through the
-- validated ClaimQuest remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("QuestControllerInitialized") then
	return
end
player:SetAttribute("QuestControllerInitialized", true)

local C = UITheme.COLORS

-- Quest text by id from the shared pool ("{n}" = goal).
local TEXT: { [string]: string } = {}
for _, def in Config.Quests.Pool do
	TEXT[def.id] = def.text
end

type Row = { frame: Frame, label: TextLabel, fill: Frame, count: TextLabel, button: TextButton }

-- Modal ------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "QuestModal"
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
root.Size = UDim2.fromOffset(380, 330)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "📜 DAILY QUESTS", C.gold)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 36)
title.TextXAlignment = Enum.TextXAlignment.Left
local resetLabel = UITheme.label(root, "Reset", "", C.muted)
resetLabel.Position = UDim2.fromOffset(16, 44)
resetLabel.Size = UDim2.new(1, -32, 0, 18)
resetLabel.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local rows: { Row } = {}
for i = 1, Config.Quests.PerDay do
	local frame = UITheme.panel(root, "Quest" .. i, C.panel)
	frame.Position = UDim2.fromOffset(12, 70 + (i - 1) * 84)
	frame.Size = UDim2.new(1, -24, 0, 76)
	local label = UITheme.label(frame, "Text", "", C.text)
	label.Position = UDim2.fromOffset(12, 8)
	label.Size = UDim2.new(1, -140, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(12, 42)
	barBack.Size = UDim2.new(1, -140, 0, 16)
	barBack.BackgroundColor3 = C.panelDeep
	barBack.Parent = frame
	UITheme.corner(barBack, 8)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.green
	fill.Parent = barBack
	UITheme.corner(fill, 8)
	local count = UITheme.label(barBack, "Count", "", C.text)
	count.Size = UDim2.fromScale(1, 1)
	local button = UITheme.button(frame, "Claim", "", "grey")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Size = UDim2.fromOffset(112, 52)
	local index = i
	button.Activated:Connect(function()
		Remotes.get("ClaimQuest"):FireServer(index)
	end)
	rows[i] = { frame = frame, label = label, fill = fill, count = count, button = button }
end
gui.Parent = player:WaitForChild("PlayerGui")

-- Side-menu button (joins the SideMenu column) -----------------------------------
local menuButton: TextButton? = nil
local badge: TextLabel? = nil
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Quests", "📜", "purple")
	b.LayoutOrder = 3
	b.Size = UDim2.fromOffset(64, 64)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 18)
	end
	local cap = UITheme.label(b, "Caption", "QUESTS", Color3.new(1, 1, 1))
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
		UIRouter.toggle("Quests")
	end)
	menuButton = b
	badge = dot
end)

-- Rendering ------------------------------------------------------------------------
local function render()
	local raw = player:GetAttribute("Quests")
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw or "[]")
	end)
	if not ok or type(list) ~= "table" then
		list = {}
	end
	local ready = 0
	for i, row in rows do
		local quest = (list :: { any })[i]
		row.frame.Visible = quest ~= nil
		if quest then
			local text = (TEXT[quest.id] or quest.id):gsub("{n}", UITheme.commas(quest.goal))
			row.label.Text = text
			local ratio = math.clamp(quest.progress / math.max(1, quest.goal), 0, 1)
			row.fill.Size = UDim2.fromScale(ratio, 1)
			row.count.Text = `{UITheme.short(quest.progress)}/{UITheme.short(quest.goal)}`
			if quest.claimed then
				row.button.Text = "DONE ✓"
				UITheme.setStyle(row.button, "teal")
			elseif quest.progress >= quest.goal then
				row.button.Text = `CLAIM ${UITheme.short(quest.reward)}`
				UITheme.setStyle(row.button, "gold")
				ready += 1
			else
				row.button.Text = `${UITheme.short(quest.reward)}`
				UITheme.setStyle(row.button, "grey")
			end
		end
	end
	if badge then
		(badge :: TextLabel).Visible = ready > 0
		(badge :: TextLabel).Text = tostring(ready)
	end
end
player:GetAttributeChangedSignal("Quests"):Connect(render)
render()

-- Reset countdown (UTC midnight).
task.spawn(function()
	while true do
		local left = 86400 - (os.time() % 86400)
		resetLabel.Text = string.format("New quests in %dh %02dm", left // 3600, (left % 3600) // 60)
		if badge == nil and menuButton then
			render()
		end
		task.wait(20)
	end
end)

UIRouter.register("Quests", {
	open = function()
		render()
		local camera = workspace.CurrentCamera
		if camera then
			fit.Scale =
				math.clamp(math.min(camera.ViewportSize.X * 0.94 / 380, camera.ViewportSize.Y * 0.8 / 330), 0.6, 1.25)
		end
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Quests")
end)
