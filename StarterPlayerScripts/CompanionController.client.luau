--!strict
-- Companions (M9-07), client side:
--  * renders every player's companion (Companion attribute) as a small glowing
--    creature that floats beside them and bobs; it flashes red when a monster is
--    within WARN_RANGE of its owner (the "wisp warning");
--  * a PETS side-menu button + modal to equip / put away companions.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("CompanionControllerInitialized") then
	return
end
player:SetAttribute("CompanionControllerInitialized", true)

local C = UITheme.COLORS
local WARN_RANGE = 35
local WARN_COLOR = Color3.fromRGB(255, 60, 60)

-- Visuals ---------------------------------------------------------------------------
type Pet = { model: Model, body: BasePart, light: PointLight, color: Color3, id: string, phase: number }
local pets: { [Player]: Pet } = {}
local folder = Instance.new("Folder")
folder.Name = "Companions"
folder.Parent = Workspace

local function makePart(name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function buildPet(def: Perks.CompanionDef): Pet
	local model = Instance.new("Model")
	model.Name = def.id
	-- Solid body (Neon blooms into a blob), glowing wings, small light.
	local body = makePart("Body", Vector3.new(1.3, 1.3, 1.3), def.color, Enum.PartType.Ball)
	body.Material = Enum.Material.SmoothPlastic
	body.Parent = model
	for side = -1, 1, 2 do
		local wing = makePart("Wing", Vector3.new(0.1, 0.9, 1.3), def.color:Lerp(Color3.new(1, 1, 1), 0.35))
		wing.Material = Enum.Material.Glass -- Neon wings bloomed into a white box
		wing.Transparency = 0.35
		wing:SetAttribute("Side", side)
		wing.Parent = model
	end
	local eye = makePart("Eyes", Vector3.new(0.7, 0.2, 0.1), Color3.fromRGB(30, 20, 40))
	eye.Material = Enum.Material.SmoothPlastic
	eye.Parent = model
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Brightness = if def.id == "Firefly" then 2 else 0.6
	light.Range = if def.id == "Firefly" then 22 else 6
	light.Shadows = false
	light.Parent = body
	model.PrimaryPart = body
	model.Parent = folder
	return { model = model, body = body, light = light, color = def.color, id = def.id, phase = math.random() * 6 }
end

local function sync(owner: Player)
	local id = owner:GetAttribute("Companion")
	local current = pets[owner]
	if current and (type(id) ~= "string" or current.id ~= id) then
		current.model:Destroy()
		pets[owner] = nil
	end
	if pets[owner] == nil and type(id) == "string" then
		local def = Perks.companion(id)
		if def then
			pets[owner] = buildPet(def)
		end
	end
end

local function watch(owner: Player)
	owner:GetAttributeChangedSignal("Companion"):Connect(function()
		sync(owner)
	end)
	sync(owner)
end
for _, other in Players:GetPlayers() do
	watch(other)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(owner)
	local pet = pets[owner]
	if pet then
		pet.model:Destroy()
		pets[owner] = nil
	end
end)

-- Monster proximity check (cheap: 4 Hz).
local danger: { [Player]: boolean } = {}
task.spawn(function()
	while true do
		task.wait(0.25)
		for owner in pets do
			local root = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
			local near = false
			if root and root:IsA("BasePart") then
				for _, child in Workspace:GetChildren() do
					if child:IsA("Model") and child:GetAttribute("Kind") ~= nil then
						local pivot = child:GetPivot().Position
						if (pivot - root.Position).Magnitude <= WARN_RANGE then
							near = true
							break
						end
					end
				end
			end
			danger[owner] = near
		end
	end
end)

RunService.RenderStepped:Connect(function(dt: number)
	local t = os.clock()
	for owner, pet in pets do
		local root = owner.Character and owner.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local bob = math.sin(t * 2.5 + pet.phase) * 0.35
			local goal = root.CFrame * CFrame.new(2.4, 2.2 + bob, -0.8) -- front-right, out of the camera line
			local current = pet.body.CFrame
			local alpha = math.clamp(dt * 6, 0, 1)
			local cf = current:Lerp(CFrame.lookAt(goal.Position, goal.Position + root.CFrame.LookVector), alpha)
			pet.body.CFrame = cf
			local flap = math.sin(t * 14 + pet.phase) * 0.6
			for _, part in pet.model:GetChildren() do
				if part:IsA("BasePart") and part.Name == "Wing" then
					local side = part:GetAttribute("Side") :: number
					part.CFrame = cf * CFrame.new(side * 0.6, 0.2, 0) * CFrame.Angles(0, 0, side * (0.5 + flap))
				elseif part:IsA("BasePart") and part.Name == "Eyes" then
					part.CFrame = cf * CFrame.new(0, 0.12, -0.62)
				end
			end
			local warn = danger[owner] == true and math.floor(t * 6) % 2 == 0
			local color = if warn then WARN_COLOR else pet.color
			if pet.body.Color ~= color then
				pet.body.Color = color
				pet.light.Color = color
			end
		end
	end
end)

-- Menu + modal ----------------------------------------------------------------------
local WIDTH, HEIGHT = 420, 330
local gui = Instance.new("ScreenGui")
gui.Name = "CompanionModal"
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
root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "COMPANIONS", Color3.fromRGB(150, 255, 170))
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local sub = UITheme.label(root, "Sub", "One follows you · flashes red when a monster is near", C.muted)
sub.Position = UDim2.fromOffset(16, 44)
sub.Size = UDim2.new(1, -32, 0, 16)
sub.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)
local list = Instance.new("Frame")
list.BackgroundTransparency = 1
list.Position = UDim2.fromOffset(12, 68)
list.Size = UDim2.new(1, -24, 1, -80)
list.Parent = root
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function skills(): { [string]: number }
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Skills") or "{}")
	end)
	return if ok and type(value) == "table" then value else {}
end

local function refresh()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local owned = skills()
	local equipped = player:GetAttribute("Companion")
	for index, def in Config.Companions do
		local row = UITheme.panel(list, def.id, C.panel)
		row.LayoutOrder = index
		row.Size = UDim2.new(1, 0, 0, 52)
		local name = UITheme.label(row, "Name", def.name, def.color)
		name.Position = UDim2.fromOffset(10, 5)
		name.Size = UDim2.new(1, -150, 0, 22)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local unlocked = Perks.companionUnlocked(def, owned)
		local text = UITheme.label(
			row,
			"Perk",
			if unlocked then def.text else `{def.text} · needs {def.skill} {def.level}`,
			C.muted
		)
		text.Position = UDim2.fromOffset(10, 28)
		text.Size = UDim2.new(1, -150, 0, 16)
		text.TextXAlignment = Enum.TextXAlignment.Left
		local isOn = equipped == def.id
		local button = UITheme.button(
			row,
			"Equip",
			if isOn then "PUT AWAY" elseif unlocked then "EQUIP" else "LOCKED",
			if isOn then "gold" elseif unlocked then "green" else "grey"
		)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(124, 40)
		local id = def.id
		button.Activated:Connect(function()
			if isOn then
				Remotes.get("SetCompanion"):FireServer("None")
			elseif unlocked then
				Remotes.get("SetCompanion"):FireServer(id)
			end
		end)
	end
end

player:GetAttributeChangedSignal("Companion"):Connect(function()
	if gui.Enabled then
		refresh()
	end
end)

UIRouter.register("Companions", {
	open = function()
		local camera = Workspace.CurrentCamera
		if camera then
			fit.Scale = math.clamp(
				math.min(camera.ViewportSize.X * 0.94 / WIDTH, camera.ViewportSize.Y * 0.8 / HEIGHT),
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
	UIRouter.close("Companions")
end)
gui.Parent = player:WaitForChild("PlayerGui")

-- Side-menu button (joins the SideMenu grid; SideMenu compacts its caption).
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	if not column then
		return
	end
	local b = UITheme.button(column, "Companions", "🐾", "teal")
	b.LayoutOrder = 8
	local cap = UITheme.label(b, "Caption", "PETS", Color3.new(1, 1, 1))
	cap.AnchorPoint = Vector2.new(0.5, 1)
	b.Activated:Connect(function()
		UIRouter.toggle("Companions")
	end)
end)
