--!strict
-- Side menu (M5-09): a grid of big icon buttons on the left edge (Shop / Index /
-- Settings, Quests + Daily join in M6, red Instant Lockdown quick-buy). It sits
-- under the HUD stack and reflows to 2-3 columns on short landscape phones.
-- Everything opens through UIRouter so only one modal shows at a time.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("SideMenuInitialized") then
	return
end
player:SetAttribute("SideMenuInitialized", true)

-- 2026-10-18: was 64 px with captions hanging below, a grid that reached the
-- thumbstick. Now 48 px (still above the 44 px touch minimum) with the caption
-- inside the button, and the grid never goes below the top half of the screen.
local BUTTON = 48

local gui = Instance.new("ScreenGui")
gui.Name = "SideMenu"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12

-- The column starts below the HUD stack (cash pill, income line, carried pill end
-- at ~116 px) so it can never cover them; it grows downwards from there.
local TOP = 126
local CAPTION_GAP = 6 -- gap between rows (captions sit inside the buttons)
local MAX_BOTTOM = 0.52 -- fraction of screen height the grid may reach (portrait)
local LANDSCAPE_WIDTH = 700
local BESIDE_X = 218 -- right of the 196 px cash pill
local BESIDE_HEIGHT = 120 -- the HUD stack's height: the grid stays in that band
local ROW = BUTTON + CAPTION_GAP

local column = Instance.new("Frame")
column.Name = "Column"
column.AnchorPoint = Vector2.new(0, 0)
column.Position = UDim2.fromOffset(10, TOP)
column.Size = UDim2.fromOffset(BUTTON, ROW * 5)
column.BackgroundTransparency = 1
column.Parent = gui
-- A grid (not a list) so short landscape phones can switch to two columns
-- instead of shrinking buttons below a comfortable touch size.
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(BUTTON, BUTTON)
layout.CellPadding = UDim2.fromOffset(6, CAPTION_GAP)
layout.FillDirection = Enum.FillDirection.Horizontal
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = column

local columnScale = Instance.new("UIScale")
columnScale.Parent = column

-- Pure: the fewest columns (max 5) that keep buttons near full size in
-- `available` px of height; falls back to the best scale five columns allow.
local function layoutFor(count: number, available: number): (number, number)
	local bestColumns, bestScale = 5, 0
	for columns = 1, 5 do
		local scale = math.min(1, available / (math.ceil(count / columns) * ROW))
		if scale >= 0.9 then
			return columns, scale
		end
		if scale > bestScale then
			bestColumns, bestScale = columns, scale
		end
	end
	return bestColumns, math.max(bestScale, 0.75)
end

-- Captions go inside the button (bottom strip); every controller's button gets
-- the same treatment here, whoever created it.
local function compact(b: GuiButton)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, 2)
		padding.PaddingBottom = UDim.new(0, 13)
	end
	local cap = b:FindFirstChild("Caption")
	if cap and cap:IsA("TextLabel") then
		cap.AnchorPoint = Vector2.new(0.5, 1)
		cap.Position = UDim2.new(0.5, 0, 1, 12)
		cap.Size = UDim2.new(1, 10, 0, 11)
	end
end

local function fitColumn()
	local count = 0
	for _, child in column:GetChildren() do
		if child:IsA("GuiButton") then
			compact(child)
			if child.Visible then -- grids skip hidden buttons
				count += 1
			end
		end
	end
	count = math.max(count, 1)
	local size = gui.AbsoluteSize -- below the Roblox top bar
	if size.X >= LANDSCAPE_WIDTH then
		-- Landscape: two rows in the top band beside the cash/carried stack, so
		-- the whole left side (thumbstick) stays clear for walking.
		local columns = math.clamp(math.ceil(count / 2), 4, 6)
		local rows = math.ceil(count / columns)
		local width = columns * BUTTON + (columns - 1) * 6
		local height = rows * ROW - CAPTION_GAP
		layout.FillDirectionMaxCells = columns
		column.Position = UDim2.fromOffset(BESIDE_X, 6)
		column.Size = UDim2.fromOffset(width, height)
		columnScale.Scale = math.min(1, (BESIDE_HEIGHT - 6) / height, (size.X * 0.62 - BESIDE_X) / width)
		return
	end
	-- Portrait: a grid under the HUD stack, never past the top half.
	local columns, scale = layoutFor(count, size.Y * MAX_BOTTOM - TOP)
	layout.FillDirectionMaxCells = columns
	column.Position = UDim2.fromOffset(10, TOP)
	column.Size = UDim2.fromOffset(columns * BUTTON + (columns - 1) * 6, math.ceil(count / columns) * ROW)
	columnScale.Scale = scale
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumn)
-- Quests/Daily join the column later from their own scripts.
column.ChildAdded:Connect(function()
	task.defer(fitColumn)
end)
fitColumn()

local buttons: { [string]: TextButton } = {}

-- Icon button with a small caption across the bottom edge.
local function menuButton(
	name: string,
	icon: string,
	caption: string,
	style: UITheme.ButtonStyle,
	order: number
): TextButton
	local b = UITheme.button(column, name, icon, style)
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(BUTTON, BUTTON)
	local padding = b:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingBottom = UDim.new(0, 13)
	end
	UITheme.label(b, "Caption", caption, Color3.new(1, 1, 1))
	compact(b)
	buttons[name] = b
	return b
end

menuButton("Shop", "🛒", "SHOP", "green", 1).Activated:Connect(function()
	UIRouter.toggle("Shop")
end)
menuButton("Index", "📖", "INDEX", "blue", 2).Activated:Connect(function()
	UIRouter.toggle("Index")
end)
menuButton("Settings", "⚙", "SETTINGS", "grey", 9).Activated:Connect(function()
	UIRouter.toggle("Settings")
end)

-- Expose the column so M6 controllers (Quests, Daily) can add their own buttons.
gui:SetAttribute("MenuReady", true)

-- Instant Lockdown quick-buy: only with a plot and a real product ID.
local lockdown: TextButton? = nil
if (Config.Products.InstantLockdown :: number) > 0 then
	-- Lives in the side-menu grid (LayoutOrder 5, before Settings): on short
	-- landscape phones the right edge belongs to the touch pad.
	local b = menuButton("Lockdown", "🛡", "LOCKDOWN", "red", 5)
	b.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(player, Config.Products.InstantLockdown)
	end)
	lockdown = b
end

local function updateLockdown()
	if lockdown then
		lockdown.Visible = player:GetAttribute("PlotIndex") ~= nil
	end
	fitColumn()
end
player:GetAttributeChangedSignal("PlotIndex"):Connect(updateLockdown)
updateLockdown()

-- Night makes the lockdown button pulse (it matters most when raids + monsters peak).
local pulse: Tween? = nil
Remotes.get("PhaseChanged").OnClientEvent:Connect(function(phase: string)
	if not lockdown then
		return
	end
	local scale = (lockdown :: TextButton):FindFirstChild("PressScale") :: UIScale?
	if pulse then
		pulse:Cancel()
		pulse = nil
	end
	if scale then
		scale.Scale = 1
		if phase == "Night" then
			pulse = TweenService:Create(
				scale,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Scale = 1.08 }
			);
			(pulse :: Tween):Play()
		end
	end
end)

-- Highlight the open modal's button.
UIRouter.onChanged(function(current)
	for name, b in buttons do
		local border = b:FindFirstChild("Border")
		if border and border:IsA("UIStroke") then
			border.Color = if name == current then Color3.new(1, 1, 1) else UITheme.COLORS.stroke
		end
	end
end)

gui.Parent = player:WaitForChild("PlayerGui")
