--!strict
-- Free rewards modal (M9-10): type a code -> REDEEM, and (when the game has a
-- group) a one-time "join the group" reward. Opened from the FREE side button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("RewardsControllerInitialized") then
	return
end
player:SetAttribute("RewardsControllerInitialized", true)

local C = UITheme.COLORS
local HAS_GROUP = Config.FreeRewards.GroupId > 0
local WIDTH, HEIGHT = 380, if HAS_GROUP then 280 else 190

local gui = Instance.new("ScreenGui")
gui.Name = "RewardsModal"
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
root.Position = UDim2.fromScale(0.5, 0.4) -- higher: the phone keyboard covers the bottom
root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "FREE REWARDS", C.gold)
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local hint = UITheme.label(root, "Hint", "Got a code? Type it here:", C.muted)
hint.Position = UDim2.fromOffset(16, 50)
hint.Size = UDim2.new(1, -32, 0, 18)
hint.TextXAlignment = Enum.TextXAlignment.Left
local box = Instance.new("TextBox")
box.Name = "Code"
box.Position = UDim2.fromOffset(16, 76)
box.Size = UDim2.new(1, -170, 0, 48)
box.BackgroundColor3 = C.panel
box.TextColor3 = C.text
box.PlaceholderText = "CODE"
box.PlaceholderColor3 = C.muted
box.Text = ""
box.ClearTextOnFocus = false
box.Font = Enum.Font.FredokaOne
box.TextScaled = true
box.Parent = root
UITheme.corner(box, 10)
UITheme.stroke(box, 2)
local redeem = UITheme.button(root, "Redeem", "REDEEM", "green")
redeem.AnchorPoint = Vector2.new(1, 0)
redeem.Position = UDim2.new(1, -16, 0, 76)
redeem.Size = UDim2.fromOffset(140, 48)
redeem.Activated:Connect(function()
	if #box.Text > 0 then
		Remotes.get("RedeemCode"):FireServer(box.Text)
		box.Text = ""
	end
end)
local codesNote = UITheme.label(root, "Note", "New codes drop with updates - check the game page!", C.muted)
codesNote.Position = UDim2.fromOffset(16, 134)
codesNote.Size = UDim2.new(1, -32, 0, 16)
codesNote.TextXAlignment = Enum.TextXAlignment.Left

local groupButton: TextButton? = nil
if HAS_GROUP then
	local groupText = UITheme.label(root, "Group", "Join our Roblox group for a one-time free reward!", C.text)
	groupText.Position = UDim2.fromOffset(16, 168)
	groupText.Size = UDim2.new(1, -32, 0, 20)
	groupText.TextXAlignment = Enum.TextXAlignment.Left
	local b = UITheme.button(root, "ClaimGroup", "CLAIM GROUP REWARD", "gold")
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, 0, 0, 200)
	b.Size = UDim2.new(1, -32, 0, 52)
	b.Activated:Connect(function()
		Remotes.get("ClaimGroupReward"):FireServer()
	end)
	groupButton = b
end

local function refresh()
	local button = groupButton
	if button then
		local claimed = player:GetAttribute("GroupRewardClaimed") == true
		button.Text = if claimed then "GROUP REWARD CLAIMED" else "CLAIM GROUP REWARD"
		UITheme.setStyle(button, if claimed then "grey" else "gold")
	end
end
player:GetAttributeChangedSignal("GroupRewardClaimed"):Connect(refresh)

UIRouter.register("Rewards", {
	open = function()
		local camera = Workspace.CurrentCamera
		if camera then
			fit.Scale = math.clamp(
				math.min(camera.ViewportSize.X * 0.94 / WIDTH, camera.ViewportSize.Y * 0.7 / HEIGHT),
				0.6,
				1.25
			)
		end
		refresh()
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Rewards")
end)
gui.Parent = player:WaitForChild("PlayerGui")

-- Side-menu button.
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Rewards", "🎁", "gold")
	b.LayoutOrder = 7
	UITheme.label(b, "Caption", "CODES", Color3.new(1, 1, 1))
	b.Activated:Connect(function()
		UIRouter.toggle("Rewards")
	end)
end)
