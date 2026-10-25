--!strict
-- Keyboard actions everywhere, plus a compact touch pad above the jump button.
-- The pad only holds what has no world prompt: Tag, Slide and OWNED gadgets.
-- Harvest / Place / Grab / Steal are tappable ProximityPrompts on phones, so they
-- stay keyboard-only here (E/P/G; B is the steal prompt's own key).
-- Buttons are 64 px (GDD mobile rule: >= 64 px); the server re-validates every remote.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MovementController = require(script.Parent:WaitForChild("MovementController"))

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once
-- (respawn/clone); every run after the first must be a no-op.
if player:GetAttribute("TouchControlsInitialized") then
	return
end
player:SetAttribute("TouchControlsInitialized", true)

type Action = {
	name: string,
	label: string,
	key: Enum.KeyCode?,
	run: () -> (),
}

local function nearestVictim(): Player?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local best: Player? = nil
	local bestDist = Config.Zapper.Range + 2
	for _, other in Players:GetPlayers() do
		if other ~= player and other.Character then
			local otherRoot = other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist <= bestDist then
					bestDist = dist
					best = other
				end
			end
		end
	end
	return best
end

local ACTIONS: { Action } = {
	{
		name = "Tag",
		label = "Tag\n[F]",
		key = Enum.KeyCode.F,
		run = function()
			local victim = nearestVictim()
			if victim then
				Remotes.get("TagHit"):FireServer(victim)
			end
		end,
	},
	{
		name = "Harvest",
		label = "Harvest\n[E]",
		key = Enum.KeyCode.E,
		run = function()
			Remotes.get("HarvestSeed"):FireServer()
		end,
	},
	{
		name = "Place",
		label = "Place\n[P]",
		key = Enum.KeyCode.P,
		run = function()
			Remotes.get("PlaceCore"):FireServer()
		end,
	},
	{
		name = "Grab",
		label = "Grab\n[G]",
		key = Enum.KeyCode.G,
		run = function()
			Remotes.get("GrabCore"):FireServer()
		end,
	},
	{
		name = "Slide",
		label = "Slide\n[C]",
		key = Enum.KeyCode.C,
		run = function()
			MovementController.trySlide()
		end,
	},
	{
		name = "Dash",
		label = "Dash\n[Q]",
		key = Enum.KeyCode.Q,
		run = function()
			if player:GetAttribute("Gadget_DashBoots") == "owned" then
				Remotes.get("UseGadget"):FireServer("DashBoots")
			end
		end,
	},
	{
		name = "Smoke",
		label = "Smoke\n[R]",
		key = Enum.KeyCode.R,
		run = function()
			if player:GetAttribute("Gadget_SmokeBomb") == "owned" then
				Remotes.get("UseGadget"):FireServer("SmokeBomb")
			end
		end,
	},
	{
		name = "Lantern",
		label = "Lantern\n[G]",
		run = function()
			if player:GetAttribute("Gadget_Lantern") == "owned" then
				Remotes.get("UseGadget"):FireServer("Lantern")
			end
		end,
	},
	{
		name = "Grapple",
		label = "Grapple\n[T]",
		key = Enum.KeyCode.T,
		run = function()
			if player:GetAttribute("Gadget_Grapple") == "owned" then
				local camera = workspace.CurrentCamera
				local aim = camera and (camera.CFrame.Position + camera.CFrame.LookVector * 1000)
				Remotes.get("UseGadget"):FireServer("Grapple", aim)
			end
		end,
	},
}

-- Keyboard bindings (desktop).
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	for _, action in ACTIONS do
		if action.key and input.KeyCode == action.key then
			action.run()
			return
		end
	end
end)

-- Touch pad (mobile only). Rebuild-safe: replaces a stale pad from a double run.
-- name -> gadget attribute that must be "owned" (nil = always shown).
local PAD: { { name: string, label: string, gadget: string? } } = {
	{ name = "Tag", label = "⚡\nTag" },
	{ name = "Slide", label = "💨\nSlide" },
	{ name = "Dash", label = "👟\nDash", gadget = "DashBoots" },
	{ name = "Smoke", label = "💣\nSmoke", gadget = "SmokeBomb" },
	{ name = "Grapple", label = "🪝\nGrapple", gadget = "Grapple" },
	{ name = "Lantern", label = "🏮\nLantern", gadget = "Lantern" },
}
local PAD_BUTTON = 64
local PAD_GAP = 8
local PAD_BOTTOM = 100 -- clears the Roblox jump button
local PAD_TOP_LIMIT = 80 -- below the day/night pill (top-right on narrow screens)

local runByName: { [string]: () -> () } = {}
for _, action in ACTIONS do
	runByName[action.name] = action.run
end

local function buildPad(): ScreenGui
	local old = player.PlayerGui:FindFirstChild("AnomalyTouchPad")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "AnomalyTouchPad"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	local pad = Instance.new("Frame")
	pad.Name = "Pad"
	pad.AnchorPoint = Vector2.new(1, 1)
	pad.Position = UDim2.new(1, -12, 1, -PAD_BOTTOM)
	pad.Size = UDim2.fromOffset(PAD_BUTTON * 3 + PAD_GAP * 2, PAD_BUTTON * 3 + PAD_GAP * 2)
	pad.BackgroundTransparency = 1
	pad.Parent = gui

	-- Bottom-up, right-to-left so the first buttons sit nearest the thumb.
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(PAD_BUTTON, PAD_BUTTON)
	grid.CellPadding = UDim2.fromOffset(PAD_GAP, PAD_GAP)
	grid.FillDirectionMaxCells = 2
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Right
	grid.VerticalAlignment = Enum.VerticalAlignment.Bottom
	grid.StartCorner = Enum.StartCorner.BottomRight
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = pad

	local scale = Instance.new("UIScale")
	scale.Parent = pad

	for index, def in PAD do
		local button = Instance.new("TextButton")
		button.Name = def.name
		button.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
		button.BackgroundTransparency = 0.25
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.FredokaOne
		button.TextSize = 15
		button.Text = def.label
		button.LayoutOrder = index
		button.Parent = pad
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 14)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 255, 220)
		stroke.Transparency = 0.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		local run = runByName[def.name]
		if run then
			button.Activated:Connect(run)
		end
		-- Gadget buttons only appear once the gadget is owned.
		local gadget = def.gadget
		if gadget then
			local function sync()
				button.Visible = player:GetAttribute("Gadget_" .. gadget) == "owned"
			end
			player:GetAttributeChangedSignal("Gadget_" .. gadget):Connect(sync)
			sync()
		end
	end

	-- Very short screens shrink the pad so it never climbs into the Lockdown button.
	-- Height comes from the rows actually shown (gadgets appear as they are bought)
	-- and the ScreenGui's own height, which excludes the Roblox top bar.
	local function fit()
		local shown = 0
		for _, child in pad:GetChildren() do
			if child:IsA("GuiButton") and child.Visible then
				shown += 1
			end
		end
		-- Two columns while they fit at full size, otherwise a third column.
		local available = gui.AbsoluteSize.Y - PAD_BOTTOM - PAD_TOP_LIMIT
		local best, bestColumns = 0, 2
		for columns = 2, 3 do
			local rows = math.max(1, math.ceil(shown / columns))
			local s = math.min(1, available / (rows * PAD_BUTTON + (rows - 1) * PAD_GAP))
			if s > best + 0.01 then
				best, bestColumns = s, columns
			end
		end
		grid.FillDirectionMaxCells = bestColumns
		scale.Scale = math.max(best, 0.6)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	for _, child in pad:GetChildren() do
		if child:IsA("GuiButton") then
			child:GetPropertyChangedSignal("Visible"):Connect(fit)
		end
	end
	fit()

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end
local padGui: ScreenGui? = nil

local function updateVisibility()
	if UserInputService.TouchEnabled then
		if not padGui then
			padGui = buildPad()
		end
		local gui = padGui :: ScreenGui
		gui.Enabled = true
	elseif padGui then
		(padGui :: ScreenGui).Enabled = false
	end
end
updateVisibility()
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(updateVisibility)

print("[TouchControls] ready (keyboard + compact touch pad)")
