--!strict
-- Idempotent world builder: ground, central forest, ring wall, hub, 8 base plots.
-- Run in Edit mode: require(game.ServerStorage.Builders.MapBuilder).build()
-- Rerunning wipes the previous build and produces the identical map (deterministic RNG).

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local TerrainBuilder = require(script.Parent.TerrainBuilder)
local AssetLibraryBuilder = require(script.Parent.AssetLibraryBuilder)
local ZoneBuilder = require(script.Parent.ZoneBuilder)

local MapBuilder = {}

local ROOT_NAME = "AnomalyGrove"

-- Layout (GDD 5.1): forest inside, plots on a ring, wall around, hub on the wall.
local PLOT_COUNT = Config.Map.Plots -- 8
local PLOT_SIZE = Config.Map.PlotSize -- 90
local RING_R = Config.Map.RingRadius -- 360
local PLOT_CENTER_R = TerrainBuilder.plotCenterRadius() -- inner edge touches the forest
local HUB_ANGLE = math.rad(22.5) -- between plots 1 and 8, on the ring wall
local WALL_HEIGHT = Config.Map.WallHeight -- 12
local WALL_SEGMENTS = 96
local PILLAR_EVERY = 6 -- a stone pillar + lantern every N wall segments
local PEDESTAL_SPACING = 13 -- 4 x 2 pedestal grid in the back half of the plot

-- Colors (GDD section 8: pastel mossy greens, warm wood, stone gray)
local COLORS = {
	ground = Color3.fromRGB(122, 168, 100),
	forestFloor = Color3.fromRGB(88, 138, 76),
	plotFloor = Color3.fromRGB(160, 120, 84),
	wallWood = Color3.fromRGB(178, 132, 92),
	stoneBase = Color3.fromRGB(140, 134, 126),
	energy = Color3.fromRGB(70, 240, 210),
	post = Color3.fromRGB(122, 86, 58),
	signBoard = Color3.fromRGB(96, 64, 42),
	ringWall = Color3.fromRGB(150, 146, 140),
	ringCap = Color3.fromRGB(118, 112, 106),
	threshold = Color3.fromRGB(60, 255, 220),
	treeTrunk = Color3.fromRGB(110, 82, 60),
	treeLeaves = Color3.fromRGB(88, 158, 88),
	rock = Color3.fromRGB(140, 140, 146),
	hub = Color3.fromRGB(168, 168, 175),
	groveHeart = Color3.fromRGB(140, 80, 220),
}

local function makePart(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	if shape then
		part.Shape = shape
	end
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Canonical text of every built part; equal digests prove the build is idempotent.
function MapBuilder.digest(): string
	local root = Workspace:FindFirstChild(ROOT_NAME)
	if not root then
		return "MISSING"
	end
	local entries: { string } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local p = descendant.Position
			local s = descendant.Size
			table.insert(
				entries,
				string.format(
					"%s|%s|%.1f,%.1f,%.1f|%.1f,%.1f,%.1f",
					descendant.Name,
					descendant.ClassName,
					p.X,
					p.Y,
					p.Z,
					s.X,
					s.Y,
					s.Z
				)
			)
		end
	end
	table.sort(entries)
	return table.concat(entries, ";")
end

function MapBuilder.build(): string
	-- Wipe the previous build and the starter clutter this replaces.
	local old = Workspace:FindFirstChild(ROOT_NAME)
	if old then
		old:Destroy()
	end
	local starterBaseplate = Workspace:FindFirstChild("Baseplate")
	if starterBaseplate then
		starterBaseplate:Destroy()
	end
	local starterSpawn = Workspace:FindFirstChild("SpawnLocation")
	if starterSpawn then
		starterSpawn:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = Workspace

	-- Ground, forest floor, paths, pond and backdrop hills are smooth terrain (M5-03).
	TerrainBuilder.build()

	-- Grove Heart: night-only spawn circle marker at the exact center.
	local heart = makePart(
		"GroveHeart",
		Vector3.new(0.5, Config.Map.GroveHeartRadius * 2, Config.Map.GroveHeartRadius * 2),
		CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		COLORS.groveHeart,
		root,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	heart.CanCollide = false

	-- Ring wall (skip segments where the hub platform and the wild-zone gates sit).
	local ringWall = Instance.new("Folder")
	ringWall.Name = "RingWall"
	ringWall.Parent = root
	for k = 0, WALL_SEGMENTS - 1 do
		local a = (k / WALL_SEGMENTS) * math.pi * 2
		local diff = math.abs((a - HUB_ANGLE + math.pi) % (2 * math.pi) - math.pi)
		local atGate = false
		for _, zone in Config.Zones.List do
			local gateDiff = math.abs((a - math.rad(zone.angle) + math.pi) % (2 * math.pi) - math.pi)
			atGate = atGate or gateDiff < math.rad(ZoneBuilder.GATE_HALF_ANGLE)
		end
		if diff > math.rad(4) and not atGate then
			local pos = Vector3.new(math.cos(a) * RING_R, WALL_HEIGHT / 2, math.sin(a) * RING_R)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			local frame = CFrame.lookAt(pos, pos + tangent)
			local segLen = 2 * math.pi * RING_R / WALL_SEGMENTS + 1
			makePart(
				"WallSegment",
				Vector3.new(4, WALL_HEIGHT, segLen),
				frame,
				COLORS.ringWall,
				ringWall,
				Enum.Material.Cobblestone
			)
			makePart(
				"WallCap",
				Vector3.new(5, 1, segLen),
				frame * CFrame.new(0, WALL_HEIGHT / 2 + 0.5, 0),
				COLORS.ringCap,
				ringWall,
				Enum.Material.Slate
			)
			if k % PILLAR_EVERY == 0 then
				makePart(
					"WallPillar",
					Vector3.new(7, WALL_HEIGHT + 4, 7),
					frame * CFrame.new(0, 2, 0),
					COLORS.ringCap,
					ringWall,
					Enum.Material.Slate
				)
				local lantern = AssetLibraryBuilder.get("Props", "Lantern") :: Model
				lantern:PivotTo(frame * CFrame.new(0, WALL_HEIGHT / 2 + 4, 0))
				lantern.Parent = ringWall
			end
		end
	end

	-- Spawn plaza on the ring wall (M5-06).
	require(script.Parent.HubBuilder).build(root)

	-- The decorative forest is ForestBuilder's job (M5-04); it runs after the plots exist.

	-- 8 plots at 45 degree spacing, each facing the map center.
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = root
	for i = 0, PLOT_COUNT - 1 do
		local a = math.rad(i * (360 / PLOT_COUNT))
		local center = Vector3.new(math.cos(a) * PLOT_CENTER_R, 0, math.sin(a) * PLOT_CENTER_R)
		-- Frame with -Z (front) pointing at the map center.
		local frame = CFrame.lookAt(center, Vector3.new(0, 0, 0))

		local plot = Instance.new("Folder")
		plot.Name = "Plot" .. (i + 1)
		plot:SetAttribute("PlotIndex", i)
		plot.Parent = plots

		makePart(
			"Floor",
			Vector3.new(PLOT_SIZE, 0.5, PLOT_SIZE),
			frame * CFrame.new(0, 0.25, 0),
			COLORS.plotFloor,
			plot,
			Enum.Material.WoodPlanks
		)
		-- Solid foundation under the floor (terrain is carved out of the footprint).
		makePart(
			"Foundation",
			Vector3.new(PLOT_SIZE, 4, PLOT_SIZE),
			frame * CFrame.new(0, -2, 0),
			COLORS.ringCap,
			plot,
			Enum.Material.Slate
		)

		-- Walls (M5-05 look): a cobblestone base, then a shimmering energy fence. The
		-- energy panels keep the gameplay wall names and, with the base, block players
		-- to WALL_HEIGHT so the gate stays the only way in.
		local innerZ = -PLOT_SIZE / 2 + 1
		local gap = 8 -- gate width (threshold + laser door + secure check use this gap)
		local segW = (PLOT_SIZE - gap) / 2
		local baseH = 3
		local panelH = WALL_HEIGHT - baseH
		local walls = {
			{
				name = "WallInnerLeft",
				size = Vector3.new(segW, 0, 1.5),
				at = Vector3.new(-(gap / 2 + segW / 2), 0, innerZ),
			},
			{
				name = "WallInnerRight",
				size = Vector3.new(segW, 0, 1.5),
				at = Vector3.new(gap / 2 + segW / 2, 0, innerZ),
			},
			{ name = "WallLeft", size = Vector3.new(1.5, 0, PLOT_SIZE), at = Vector3.new(-PLOT_SIZE / 2 + 1, 0, 0) },
			{ name = "WallRight", size = Vector3.new(1.5, 0, PLOT_SIZE), at = Vector3.new(PLOT_SIZE / 2 - 1, 0, 0) },
			{ name = "WallOuter", size = Vector3.new(PLOT_SIZE, 0, 1.5), at = Vector3.new(0, 0, PLOT_SIZE / 2 - 1) },
		}
		for _, wall in walls do
			makePart(
				wall.name .. "Base",
				Vector3.new(wall.size.X + 1, baseH, wall.size.Z + 1),
				frame * CFrame.new(wall.at + Vector3.new(0, 0.5 + baseH / 2, 0)),
				COLORS.stoneBase,
				plot,
				Enum.Material.Cobblestone
			)
			local panel = makePart(
				wall.name,
				Vector3.new(wall.size.X, panelH, wall.size.Z),
				frame * CFrame.new(wall.at + Vector3.new(0, 0.5 + baseH + panelH / 2, 0)),
				COLORS.energy,
				plot,
				Enum.Material.Glass
			)
			panel.Transparency = 0.6
			panel.CastShadow = false
			-- Glowing top rail so the barrier height reads at a glance.
			local rail = makePart(
				"Rail",
				Vector3.new(math.max(wall.size.X, 0.5), 0.35, math.max(wall.size.Z, 0.5)),
				frame * CFrame.new(wall.at + Vector3.new(0, 0.5 + WALL_HEIGHT, 0)),
				COLORS.energy,
				plot,
				Enum.Material.Neon
			)
			rail.CanCollide = false
			rail.CanQuery = false
			rail.CastShadow = false
			-- Wooden posts along the wall, a lantern on every other one.
			local length = math.max(wall.size.X, wall.size.Z)
			local alongX = wall.size.X > wall.size.Z
			local posts = math.max(1, math.floor(length / 15))
			for k = 0, posts do
				local t = -length / 2 + (k / posts) * length
				local offset = if alongX then Vector3.new(t, 0, 0) else Vector3.new(0, 0, t)
				local postPos = wall.at + offset
				makePart(
					"Post",
					Vector3.new(1.8, WALL_HEIGHT + 1, 1.8),
					frame * CFrame.new(postPos + Vector3.new(0, 0.5 + (WALL_HEIGHT + 1) / 2, 0)),
					COLORS.post,
					plot,
					Enum.Material.Wood
				)
				local isCorner = (k == 0 or k == posts) and (wall.name == "WallLeft" or wall.name == "WallRight")
				if isCorner then
					local lantern = AssetLibraryBuilder.get("Props", "Lantern") :: Model
					lantern:PivotTo(frame * CFrame.new(postPos + Vector3.new(0, WALL_HEIGHT + 1.5, 0)))
					-- One light per lantern is plenty (8 plots x many posts).
					local keptLight = false
					for _, light in lantern:GetDescendants() do
						if light:IsA("Light") then
							if keptLight then
								light:Destroy()
							else
								keptLight = true
								light.Shadows = false
							end
						end
					end
					lantern.Parent = plot
				end
			end
		end

		makePart(
			"Threshold",
			Vector3.new(gap, 0.4, 3),
			frame * CFrame.new(0, 0.7, innerZ),
			COLORS.threshold,
			plot,
			Enum.Material.Neon
		)

		-- Entrance arch: two stone pillars and a beam carrying the owner nameplate.
		local pillarH = WALL_HEIGHT + 6
		for _, side in { -1, 1 } do
			makePart(
				"ArchPillar",
				Vector3.new(3, pillarH, 3),
				frame * CFrame.new(side * (gap / 2 + 1.5), 0.5 + pillarH / 2, innerZ),
				COLORS.stoneBase,
				plot,
				Enum.Material.Cobblestone
			)
			local lantern = AssetLibraryBuilder.get("Props", "Lantern") :: Model
			lantern:PivotTo(frame * CFrame.new(side * (gap / 2 + 1.5), 0.5 + pillarH, innerZ))
			lantern.Parent = plot
		end
		makePart(
			"ArchBeam",
			Vector3.new(gap + 8, 2, 3.4),
			frame * CFrame.new(0, 0.5 + pillarH - 3, innerZ),
			COLORS.post,
			plot,
			Enum.Material.Wood
		)

		-- Mounted on the beam's outer face (beam depth 3.4 -> face at innerZ - 1.7),
		-- so the 18-stud board sits IN FRONT of the pillars and their lanterns
		-- instead of behind them (they used to hide the owner's name and avatar).
		local sign = makePart(
			"Sign",
			Vector3.new(18, 5, 0.6),
			frame * CFrame.new(0, 0.5 + pillarH - 3 + 3.6, innerZ - 2.0),
			COLORS.signBoard,
			plot,
			Enum.Material.Wood
		)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignGui"
		gui.Face = Enum.NormalId.Front -- faces the forest
		gui.CanvasSize = Vector2.new(720, 200)
		gui.LightInfluence = 0
		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar" -- PlotSystem sets the owner's headshot (rbxthumb, no yield)
		avatar.Size = UDim2.fromOffset(170, 170)
		avatar.Position = UDim2.fromOffset(15, 15)
		avatar.BackgroundColor3 = Color3.fromRGB(40, 30, 25)
		avatar.BackgroundTransparency = 0.2
		avatar.Image = ""
		avatar.Visible = false
		avatar.Parent = gui
		local avatarCorner = Instance.new("UICorner")
		avatarCorner.CornerRadius = UDim.new(0.5, 0)
		avatarCorner.Parent = avatar
		local label = Instance.new("TextLabel")
		label.Name = "SignLabel"
		label.Size = UDim2.new(1, -40, 1, -20)
		label.Position = UDim2.fromOffset(20, 10)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = "Unclaimed"
		label.Parent = gui
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 4
		stroke.Color = Color3.fromRGB(40, 25, 15)
		stroke.Parent = label
		gui.Parent = sign

		local zone = Instance.new("Part")
		zone.Name = "ClaimZone"
		zone.Size = Vector3.new(PLOT_SIZE, 14, PLOT_SIZE)
		zone.CFrame = frame * CFrame.new(0, 0.5 + 7, 0)
		zone.Transparency = 1
		zone.CanCollide = false
		zone.CanTouch = true
		zone.CanQuery = false
		zone.Anchored = true
		zone.Parent = plot

		-- Floating marker: walk into it to claim the plot (hidden by PlotSystem once owned).
		local marker = makePart(
			"ClaimMarker",
			Vector3.new(8, 0.6, 8),
			frame * CFrame.new(0, 10, 0),
			COLORS.threshold,
			plot,
			Enum.Material.Neon
		)
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Shape = Enum.PartType.Cylinder
		marker.CastShadow = false
		marker.Size = Vector3.new(0.4, 12, 12)
		marker.CFrame = frame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
		-- Light pillar from the claim pad into the sky (toggled with the marker).
		local base = Instance.new("Attachment")
		base.Name = "PillarBase"
		base.Parent = marker
		local top = Instance.new("Attachment")
		top.Name = "PillarTop"
		top.Parent = marker -- parent first: WorldPosition is relative to the rotated disc
		top.WorldPosition = marker.Position + Vector3.new(0, 40, 0)
		local pillar = Instance.new("Beam")
		pillar.Name = "ClaimPillar"
		pillar.Attachment0 = base
		pillar.Attachment1 = top
		pillar.Width0 = 8
		pillar.Width1 = 2
		pillar.FaceCamera = true
		pillar.LightEmission = 1
		pillar.Color = ColorSequence.new(COLORS.threshold)
		pillar.Transparency = NumberSequence.new(0.55, 1)
		pillar.Parent = marker
		local markerGui = Instance.new("BillboardGui")
		markerGui.Name = "ClaimGui"
		markerGui.Size = UDim2.fromScale(14, 4)
		markerGui.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
		markerGui.MaxDistance = 260
		markerGui.LightInfluence = 0
		local markerLabel = Instance.new("TextLabel")
		markerLabel.Name = "ClaimLabel"
		markerLabel.Size = UDim2.fromScale(1, 1)
		markerLabel.BackgroundTransparency = 1
		markerLabel.Text = "FREE PLOT\nwalk in to claim!"
		markerLabel.TextColor3 = Color3.fromRGB(120, 255, 230)
		markerLabel.Font = Enum.Font.FredokaOne
		markerLabel.TextScaled = true
		markerLabel.Parent = markerGui
		local markerStroke = Instance.new("UIStroke")
		markerStroke.Thickness = 3
		markerStroke.Color = Color3.fromRGB(10, 50, 50)
		markerStroke.Parent = markerLabel
		markerGui.Parent = marker

		for slot = 1, Config.Plot.MaxPedestalSlots do
			local col = (slot - 1) % 4
			local row = math.floor((slot - 1) / 4)
			local anchor = Instance.new("Part")
			anchor.Name = "PedestalSlot" .. slot
			anchor.Size = Vector3.new(2, 1, 2)
			anchor.CFrame = frame
				* CFrame.new(-1.5 * PEDESTAL_SPACING + col * PEDESTAL_SPACING, 1, 10 + row * PEDESTAL_SPACING)
			anchor.Transparency = 1
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.Anchored = true
			anchor.Parent = plot
		end

		if i % 2 == 1 then
			task.wait()
		end
	end

	-- Dress the world last: the forest placement keeps paths, pond and plots clear.
	local forestReport = require(script.Parent.ForestBuilder).build()
	print(forestReport)
	print(require(script.Parent.FurnitureBuilder).build())
	print(ZoneBuilder.build()) -- 2026-10-18 wild zones past the ring wall

	local count = 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return `[MapBuilder] built {count} parts`
end

return MapBuilder
