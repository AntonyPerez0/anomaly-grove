--!strict
-- Objective tracker (M6-01): a pill at the bottom-centre with the next goal (and a
-- progress bar for "save up" goals) plus a glowing guide beam from the player to the
-- goal's target with a bouncing marker. Pure client visuals: the chain itself is
-- the shared, spec-tested Objectives module fed by replicated attributes.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Objectives = require(ReplicatedStorage.Shared.Objectives)
local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local HttpService = game:GetService("HttpService")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))

local player = Players.LocalPlayer

if player:GetAttribute("ObjectiveControllerInitialized") then
	return
end
player:SetAttribute("ObjectiveControllerInitialized", true)

local BEAM_COLOR = Color3.fromRGB(90, 255, 220)
local HIDE_WITHIN = 9 -- studs: close enough, the beam just gets in the way

-- Pill UI -------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ObjectiveHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11
local pill = UITheme.panel(gui, "Pill", UITheme.COLORS.panelDeep)
pill.AnchorPoint = Vector2.new(0.5, 1)
pill.Position = UDim2.new(0.5, 0, 1, -14)
pill.Size = UDim2.fromOffset(300, 46)
pill.BackgroundTransparency = 0.1
local badge = UITheme.label(pill, "Badge", "GOAL", UITheme.COLORS.gold)
badge.Position = UDim2.fromOffset(8, 6)
badge.Size = UDim2.fromOffset(46, 18)
local text = UITheme.label(pill, "Text", "", UITheme.COLORS.text)
text.Position = UDim2.fromOffset(8, 22)
text.Size = UDim2.new(1, -16, 0, 20)
text.TextXAlignment = Enum.TextXAlignment.Left
local bar = Instance.new("Frame")
bar.Name = "Progress"
bar.AnchorPoint = Vector2.new(1, 0)
bar.Position = UDim2.new(1, -10, 0, 9)
bar.Size = UDim2.new(1, -72, 0, 10)
bar.BackgroundColor3 = UITheme.COLORS.panel
bar.Parent = pill
UITheme.corner(bar, 5)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = UITheme.COLORS.green
fill.Parent = bar
UITheme.corner(fill, 5)
gui.Parent = player:WaitForChild("PlayerGui")

-- Beam + marker (client-only parts) -------------------------------------------
local anchor = Instance.new("Part")
anchor.Name = "ObjectiveAnchor"
anchor.Size = Vector3.new(0.2, 0.2, 0.2)
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Parent = Workspace
local targetAttachment = Instance.new("Attachment")
targetAttachment.Parent = anchor
local marker = Instance.new("BillboardGui")
marker.Name = "Marker"
marker.Size = UDim2.fromOffset(44, 44)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
marker.Parent = anchor
local arrow = UITheme.label(marker, "Arrow", "▼", BEAM_COLOR)
arrow.Size = UDim2.fromScale(1, 1)

local beam = Instance.new("Beam")
beam.Name = "GuideBeam"
beam.Attachment1 = targetAttachment
beam.Color = ColorSequence.new(BEAM_COLOR, Color3.new(1, 1, 1))
beam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.7),
	NumberSequenceKeypoint.new(0.15, 0.25),
	NumberSequenceKeypoint.new(1, 0.25),
})
beam.Width0 = 0.6
beam.Width1 = 0.6
beam.FaceCamera = true
beam.LightEmission = 1
beam.Segments = 1
beam.Parent = anchor

local function attachToCharacter(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root then
		local a = Instance.new("Attachment")
		a.Name = "GuideOrigin"
		a.Position = Vector3.new(0, -1.5, 0)
		a.Parent = root
		beam.Attachment0 = a
	end
end
player.CharacterAdded:Connect(attachToCharacter)
if player.Character then
	task.spawn(attachToCharacter, player.Character)
end

-- Target lookup -----------------------------------------------------------------
local function grove(): Instance?
	return Workspace:FindFirstChild("AnomalyGrove")
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function nearest(candidates: { BasePart }, from: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, part in candidates do
		local d = (part.Position - from).Magnitude
		if d < bestDistance then
			best, bestDistance = part, d
		end
	end
	return best
end

local function ownPlot(): Instance?
	local index = player:GetAttribute("PlotIndex")
	local root = grove()
	local plots = root and root:FindFirstChild("Plots")
	return if index ~= nil and plots then plots:FindFirstChild("Plot" .. (index + 1)) else nil
end

local function children(instance: Instance?): { Instance }
	if instance then
		return instance:GetChildren()
	end
	return {}
end

local function findTarget(kind: Objectives.Target, from: Vector3): BasePart?
	local root = grove()
	if not root then
		return nil
	end
	local candidates: { BasePart } = {}
	if kind == "claim" then
		local plots = root:FindFirstChild("Plots")
		for _, plot in children(plots) do
			local m = plot:FindFirstChild("ClaimMarker")
			if m and m:IsA("BasePart") and m.Transparency < 1 then
				table.insert(candidates, m)
			end
		end
	elseif kind == "seed" then
		local nodes = root:FindFirstChild("SeedNodes")
		for _, node in children(nodes) do
			if node:IsA("BasePart") then
				table.insert(candidates, node)
			end
		end
	elseif kind == "ownPedestal" then
		local plot = ownPlot()
		for _, child in children(plot) do
			if child:IsA("Model") and string.match(child.Name, "^Pedestal%d+$") then
				local empty = not child:FindFirstChild("CoreOrb") and not child:FindFirstChild("SeedOrb")
				if empty and child.PrimaryPart then
					table.insert(candidates, child.PrimaryPart)
				end
			end
		end
	elseif kind == "rivalCore" then
		local mine = ownPlot()
		local plots = root:FindFirstChild("Plots")
		for _, plot in children(plots) do
			if plot ~= mine then
				for _, child in plot:GetChildren() do
					local orb = if child:IsA("Model") then child:FindFirstChild("CoreOrb") else nil
					if orb and orb:IsA("BasePart") then
						table.insert(candidates, orb)
					end
				end
			end
		end
	elseif kind == "home" then
		local plot = ownPlot()
		local threshold = plot and plot:FindFirstChild("Threshold")
		if threshold and threshold:IsA("BasePart") then
			table.insert(candidates, threshold)
		end
	end
	return nearest(candidates, from)
end

-- Update loop -----------------------------------------------------------------
local night = false
Remotes.get("PhaseChanged").OnClientEvent:Connect(function(phase: string)
	night = phase == "Night"
end)

local currentId = ""

local function rivalCoresExist(): boolean
	local from = rootPosition() or Vector3.zero
	return findTarget("rivalCore", from) ~= nil
end

local function skillsTable(): { [string]: number }
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Skills") or "{}")
	end)
	return if ok and type(decoded) == "table" then decoded else {}
end

-- M8-11 economy fields from the server mirrors (shared Perks math = same prices).
local function economy(): (number, number?, { slot: number, level: number, price: number }?)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Stats") or "{}")
	end)
	local stats: Perks.Stats = if ok and type(decoded) == "table" then decoded else {}
	local rebirths = player:GetAttribute("Rebirths") or 0
	local slots = player:GetAttribute("PedestalSlots") or 1
	local maxPedestals = Perks.maxPedestals(stats)
	local nextPrice = if slots + 1 <= maxPedestals then Perks.discounted(Config.Prices.Pedestals[slots], stats) else nil
	local cap = Perks.pedestalCap(rebirths)
	local best: { slot: number, level: number, price: number }? = nil
	if not Perks.upgradesUnlocked(skillsTable()) then
		cap = 0 -- locked until Cultivation 10: no upgrade goals
	end
	-- Best income per dollar on hatched cores (same rule as UPGRADE ALL).
	local cores = Perks.coresFromSummary(player:GetAttribute("PedestalSummary") or "")
	local slot = 0
	local bestValue = 0
	for level in string.gmatch(player:GetAttribute("PedestalLevels") or "", "[^,]+") do
		slot += 1
		local lvl = tonumber(level) or 1
		local core = cores[slot]
		if core and lvl < cap then
			local value = Perks.upgradeValue(core.rarity, core.mutation, slot, lvl, core.size)
			if value > bestValue then
				bestValue = value
				best = {
					slot = slot,
					level = lvl,
					price = Perks.discounted(Perks.pedestalUpgradeCost(slot, lvl, rebirths), stats),
				}
			end
		end
	end
	return maxPedestals, nextPrice, best
end

local function snapshot(): Objectives.Snapshot
	local carried = player:GetAttribute("CarriedCore")
	local maxPedestals, nextPrice, best = economy()
	return {
		maxPedestals = maxPedestals,
		defenseCount = player:GetAttribute("DefenseCount"),
		hasGadget = player:GetAttribute("Gadget_DashBoots") == "owned"
			or player:GetAttribute("Gadget_SmokeBomb") == "owned"
			or player:GetAttribute("Gadget_Grapple") == "owned",
		cultivationLevel = Perks.skillLevel(skillsTable(), "Cultivation"),
		nextPedestalPrice = nextPrice,
		bestUpgrade = best,
		rebirthCost = player:GetAttribute("RebirthCost"),
		incomeRate = player:GetAttribute("IncomeRate"),
		hasPlot = player:GetAttribute("PlotIndex") ~= nil,
		seeds = (player:GetAttribute("SeedsCarried") or 0)
			+ (player:GetAttribute("GroveSeedsCarried") or 0)
			+ (player:GetAttribute("ZoneSeedsCarried") or 0),
		carryingCore = carried ~= nil and carried ~= "",
		summary = player:GetAttribute("PedestalSummary") or "",
		pedestalSlots = player:GetAttribute("PedestalSlots") or 1,
		cash = player:GetAttribute("Cash") or 0,
		coresStolen = player:GetAttribute("CoresStolen") or 0,
		netWorth = player:GetAttribute("NetWorth") or 0,
		night = night,
		rivalCores = rivalCoresExist(),
	}
end

local function update()
	local objective = Objectives.next(snapshot())
	if objective.id ~= currentId then
		currentId = objective.id
		UITheme.popIn(pill)
	end
	text.Text = objective.text -- ETAs tick even when the goal is unchanged
	bar.Visible = objective.progress ~= nil
	badge.Visible = objective.progress == nil
	if objective.progress then
		fill.Size = UDim2.fromScale(objective.progress :: number, 1)
	end
	local from = rootPosition()
	local target = if from and objective.target then findTarget(objective.target, from) else nil
	if target and from and (target.Position - from).Magnitude > HIDE_WITHIN then
		anchor.CFrame = CFrame.new(target.Position)
		beam.Enabled = true
		marker.Enabled = true
	else
		beam.Enabled = false
		marker.Enabled = false
	end
end

task.spawn(function()
	while true do
		update()
		task.wait(0.4)
	end
end)

-- Marker bob (cheap: one billboard offset per frame).
RunService.RenderStepped:Connect(function()
	if marker.Enabled then
		marker.StudsOffsetWorldSpace = Vector3.new(0, 6 + math.sin(os.clock() * 4) * 0.6, 0)
	end
end)

-- Layout: bottom-centre on landscape/desktop (thumbstick left, jump right);
-- portrait phones put it under the HUD stack so it never covers the thumbstick.
local function layout()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	if viewport.X < 600 then
		-- Portrait: under the side-menu grid (it shares the top-left with the HUD).
		local side = player.PlayerGui:FindFirstChild("SideMenu")
		local column = side and side:FindFirstChild("Column")
		local top = 124
		if column and column:IsA("GuiObject") then
			top = math.max(top, column.AbsolutePosition.Y + column.AbsoluteSize.Y + 6)
		end
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, top)
		pill.Size = UDim2.fromOffset(math.min(300, viewport.X - 24), 46)
	else
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Size = UDim2.fromOffset(300, 46)
		pill.Position = UDim2.new(0.5, 0, 1, -14)
		-- Short landscape phones: the side-menu grid reaches the bottom, so centre
		-- the pill in the free span between it and the jump button / touch pad.
		local side = player.PlayerGui:FindFirstChild("SideMenu")
		local column = side and side:FindFirstChild("Column")
		if column and column:IsA("GuiObject") then
			local guiHeight = (side :: ScreenGui).AbsoluteSize.Y
			local menuBottom = column.AbsolutePosition.Y + column.AbsoluteSize.Y
			if menuBottom > guiHeight - 70 then
				local left = column.AbsolutePosition.X + column.AbsoluteSize.X + 8
				local right = viewport.X - (if UserInputService.TouchEnabled then 170 else 12)
				local span = right - left
				if span > 120 then
					pill.Size = UDim2.fromOffset(math.min(300, span), 46)
					pill.Position = UDim2.new(0, left + span / 2, 1, -14)
				end
			end
		end
	end
end
-- The menu reflows as buttons join it; re-fit a few times while the HUD settles.
task.spawn(function()
	for _ = 1, 10 do
		task.wait(1)
		layout()
	end
end)
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end
layout()
