--!strict
-- Spawn plaza on the ring wall (M5-06): a stone-tower deck with railings, a wide ramp
-- into the grove under an "ANOMALY GROVE" title arch, two shop stalls (prompts carry
-- a ShopTab attribute the client UI opens), benches, planters and lanterns.
-- Called by MapBuilder.build(); LeaderboardBuilder places its boards from frame().
-- Local hub frame: X runs along the wall, -Z points at the map centre.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local AssetLibraryBuilder = require(script.Parent.AssetLibraryBuilder)

local HubBuilder = {}

local HUB_ANGLE = math.rad(22.5) -- between plots 1 and 8
local WIDTH = 64 -- along the wall
local DEPTH = 48 -- across the wall
local DECK_OFFSET_Z = -4 -- deck centre sits slightly inside the ring
local RAMP_WIDTH = 16

local COLORS = {
	deck = Color3.fromRGB(176, 132, 92),
	stone = Color3.fromRGB(140, 134, 126),
	trim = Color3.fromRGB(110, 104, 98),
	wood = Color3.fromRGB(122, 86, 58),
	banner = Color3.fromRGB(64, 40, 96),
	gold = Color3.fromRGB(255, 205, 90),
	teal = Color3.fromRGB(70, 240, 210),
}

-- Hub frame at deck-top height (y = top surface) and the deck top Y.
function HubBuilder.frame(): (CFrame, number)
	local dir = Vector3.new(math.cos(HUB_ANGLE), 0, math.sin(HUB_ANGLE))
	local top = Config.Map.WallHeight + 0.5
	local pos = dir * Config.Map.RingRadius + Vector3.new(0, top, 0)
	return CFrame.lookAt(pos, pos - dir), top
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function textGui(parent: BasePart, face: Enum.NormalId, text: string, color: Color3, strokeColor: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Text" .. face.Name
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = strokeColor
	stroke.Parent = label
	gui.Parent = parent
end

local function lanternPost(parent: Instance, cf: CFrame)
	part(parent, "LampPost", Vector3.new(1.2, 7, 1.2), cf * CFrame.new(0, 3.5, 0), COLORS.wood, Enum.Material.Wood)
	local lantern = AssetLibraryBuilder.get("Props", "Lantern") :: Model
	lantern:PivotTo(cf * CFrame.new(0, 7, 0))
	lantern.Parent = parent
end

local function stall(parent: Instance, cf: CFrame, title: string, tab: string, color: Color3, action: string?)
	local model = AssetLibraryBuilder.get("Props", "MarketStall") :: Model
	model:PivotTo(cf)
	model.Name = "Stall_" .. tab
	model.Parent = parent
	local _, size = model:GetBoundingBox()
	local sign = part(
		parent,
		"StallSign_" .. tab,
		Vector3.new(size.X * 0.8, 3, 0.4),
		cf * CFrame.new(0, size.Y + 1.6, -size.Z / 2 + 0.5),
		color,
		Enum.Material.SmoothPlastic
	)
	textGui(sign, Enum.NormalId.Front, title, Color3.new(1, 1, 1), Color3.fromRGB(30, 20, 10))
	-- Shop prompt: the client opens the matching shop tab (M5-09 UI).
	local promptPart = part(
		parent,
		"ShopPrompt_" .. tab,
		Vector3.new(4, 4, 4),
		cf * CFrame.new(0, 2.5, -size.Z / 2 - 1),
		color,
		Enum.Material.SmoothPlastic
	)
	promptPart.Transparency = 1
	promptPart.CanCollide = false
	promptPart:SetAttribute("ShopTab", tab)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = action or "Open Shop"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptPart
end

function HubBuilder.build(root: Instance): string
	local old = root:FindFirstChild("Hub")
	if old then
		old:Destroy()
	end
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = root

	local cf, top = HubBuilder.frame()
	local deckCenter = cf * CFrame.new(0, 0, DECK_OFFSET_Z)

	-- Stone tower + deck (named Platform for continuity).
	part(
		hub,
		"Tower",
		Vector3.new(WIDTH, top - 1, DEPTH),
		deckCenter * CFrame.new(0, -(top + 1) / 2, 0),
		COLORS.stone,
		Enum.Material.Cobblestone
	)
	part(
		hub,
		"Platform",
		Vector3.new(WIDTH, 2, DEPTH),
		deckCenter * CFrame.new(0, -1, 0),
		COLORS.deck,
		Enum.Material.WoodPlanks
	)

	-- Railings with a ramp opening at the front centre.
	local halfW, halfD = WIDTH / 2, DEPTH / 2
	local railY = 1.2
	local frontSeg = (WIDTH - RAMP_WIDTH) / 2
	part(
		hub,
		"RailBack",
		Vector3.new(WIDTH, railY, 1),
		deckCenter * CFrame.new(0, railY / 2, halfD - 0.5),
		COLORS.trim,
		Enum.Material.Slate
	)
	part(
		hub,
		"RailLeft",
		Vector3.new(1, railY, DEPTH),
		deckCenter * CFrame.new(-halfW + 0.5, railY / 2, 0),
		COLORS.trim,
		Enum.Material.Slate
	)
	part(
		hub,
		"RailRight",
		Vector3.new(1, railY, DEPTH),
		deckCenter * CFrame.new(halfW - 0.5, railY / 2, 0),
		COLORS.trim,
		Enum.Material.Slate
	)
	for _, side in { -1, 1 } do
		part(
			hub,
			"RailFront",
			Vector3.new(frontSeg, railY, 1),
			deckCenter * CFrame.new(side * (RAMP_WIDTH / 2 + frontSeg / 2), railY / 2, -halfD + 0.5),
			COLORS.trim,
			Enum.Material.Slate
		)
	end

	-- Ramp down into the grove (low edge toward the map centre).
	local rampLength = 38
	local ramp = Instance.new("WedgePart")
	ramp.Name = "Ramp"
	ramp.Size = Vector3.new(RAMP_WIDTH, top, rampLength)
	ramp.CFrame = deckCenter * CFrame.new(0, -top / 2, -halfD - rampLength / 2)
	ramp.Color = COLORS.deck
	ramp.Material = Enum.Material.WoodPlanks
	ramp.Anchored = true
	ramp.Parent = hub

	-- Title arch over the top of the ramp; text faces both the map and the spawn.
	local archZ = -halfD + 2
	local archH = 16
	for _, side in { -1, 1 } do
		part(
			hub,
			"ArchPillar",
			Vector3.new(3, archH, 3),
			deckCenter * CFrame.new(side * (RAMP_WIDTH / 2 + 1.5), archH / 2, archZ),
			COLORS.stone,
			Enum.Material.Cobblestone
		)
		local crystal = part(
			hub,
			"ArchCrystal",
			Vector3.new(1.6, 3, 1.6),
			deckCenter
				* CFrame.new(side * (RAMP_WIDTH / 2 + 1.5), archH + 1.8, archZ)
				* CFrame.Angles(0, math.rad(45), 0),
			COLORS.teal,
			Enum.Material.Neon
		)
		crystal.CanCollide = false
	end
	local banner = part(
		hub,
		"TitleBanner",
		Vector3.new(RAMP_WIDTH + 12, 5, 3.8), -- deeper than the pillars so both faces clear them
		deckCenter * CFrame.new(0, archH - 2.5, archZ),
		COLORS.banner,
		Enum.Material.SmoothPlastic
	)
	textGui(banner, Enum.NormalId.Front, "ANOMALY GROVE", COLORS.gold, Color3.fromRGB(40, 20, 10))
	textGui(banner, Enum.NormalId.Back, "ANOMALY GROVE", COLORS.gold, Color3.fromRGB(40, 20, 10))

	-- Spawn in the middle of the deck, facing the grove.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "SpawnLocation"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.CFrame = cf * CFrame.new(0, 0.5, 0)
	spawnLocation.Anchored = true
	spawnLocation.Color = Color3.fromRGB(70, 130, 120)
	spawnLocation.Material = Enum.Material.Slate
	spawnLocation.Duration = 0
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.Parent = hub
	local decal = spawnLocation:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- Shop stalls at the back corners.
	stall(hub, deckCenter * CFrame.new(-19, 0, halfD - 9), "GADGETS", "Gadgets", Color3.fromRGB(70, 150, 255))
	stall(hub, deckCenter * CFrame.new(19, 0, halfD - 9), "DEFENSES", "Defenses", Color3.fromRGB(255, 120, 80))
	-- M9-04 Traveling Market on the left side of the deck, facing the spawn.
	stall(
		hub,
		deckCenter * CFrame.new(-24, 0, -4) * CFrame.Angles(0, -math.pi / 2, 0),
		"TRAVELING MARKET",
		"Market",
		Color3.fromRGB(200, 120, 255),
		"Browse"
	)
	-- M9-05 Fuse Machine on the right side, mirroring the market.
	stall(
		hub,
		deckCenter * CFrame.new(24, 0, -4) * CFrame.Angles(0, math.pi / 2, 0),
		"FUSE MACHINE",
		"Fuse",
		Color3.fromRGB(80, 220, 200),
		"Fuse Cores"
	)

	-- Benches, planters and lamps.
	for _, x in { -5, 5 } do
		local bench = AssetLibraryBuilder.get("Props", "Bench") :: Model
		bench:PivotTo(deckCenter * CFrame.new(x, 0, halfD - 4) * CFrame.Angles(0, math.pi, 0))
		bench.Parent = hub
	end
	local bushNames = AssetLibraryBuilder.list("Bushes")
	-- Planters flank the ramp opening along the front rail.
	for k, x in { -halfW + 5, -14, 14, halfW - 5 } do
		for j, z in { -halfD + 4 } do
			part(
				hub,
				"Planter",
				Vector3.new(5, 1.6, 5),
				deckCenter * CFrame.new(x, 0.8, z),
				COLORS.wood,
				Enum.Material.Wood
			)
			local bush = AssetLibraryBuilder.get("Bushes", bushNames[((k + j) % #bushNames) + 1]) :: Model
			bush:ScaleTo(0.45)
			bush:PivotTo(deckCenter * CFrame.new(x, 1.6, z))
			bush.Parent = hub
		end
	end
	for _, corner in
		{
			Vector3.new(-halfW + 1.5, 0, -halfD + 1.5),
			Vector3.new(halfW - 1.5, 0, -halfD + 1.5),
			Vector3.new(-halfW + 1.5, 0, halfD - 1.5),
			Vector3.new(halfW - 1.5, 0, halfD - 1.5),
		}
	do
		lanternPost(hub, deckCenter * CFrame.new(corner))
	end

	return "[HubBuilder] plaza built"
end

return HubBuilder
