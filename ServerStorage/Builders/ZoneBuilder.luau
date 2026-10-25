--!strict
-- Wild zones past the ring wall (2026-10-18, human: "the map still seems small").
-- Three themed clearings in the backdrop hills, each reached through a stone gate
-- cut into the ring wall: Crystal Hollow, Spore Mire and Ruined Shrine.
-- Seed nodes and guardians are runtime (SeedSystem / MonsterAI); this is the world.
-- Edit mode: require(game.ServerStorage.Builders.ZoneBuilder).build()
-- Idempotent: wipes AnomalyGrove/Zones, then re-carves the same terrain.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Zones = require(game:GetService("ReplicatedStorage").Shared.Zones)
local CollisionGroups = require(script.Parent.CollisionGroups)
local AssetLibraryBuilder = require(script.Parent.AssetLibraryBuilder)

local ZoneBuilder = {}

local FOLDER_NAME = "Zones"
local DEPTH = 8 -- terrain slab thickness (matches TerrainBuilder)
local RING_R = Config.Map.RingRadius
local GATE_HALF_WIDTH = 13 -- studs either side of the gate centre line
local GATE_HEIGHT = 20
local STONE = Color3.fromRGB(128, 122, 116)
local DARK_STONE = Color3.fromRGB(92, 88, 84)

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = CollisionGroups.Decor -- players bump into it, monsters pass through
	p.Parent = parent
	return p
end

local function glow(p: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.5
	light.Range = range
	light.Shadows = false
	light.Parent = p
end

local function slab(center: Vector3, radius: number, material: Enum.Material)
	Workspace.Terrain:FillCylinder(CFrame.new(center.X, -DEPTH / 2, center.Z), DEPTH, radius, material)
end

-- Remove ring-wall pieces in the gate gap (works on an already built place too).
local function cutGate(angleDeg: number)
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local wall = root and root:FindFirstChild("RingWall")
	if not wall then
		return
	end
	local gate = math.rad(angleDeg)
	for _, child in wall:GetChildren() do
		local pivot = if child:IsA("BasePart")
			then child.Position
			elseif child:IsA("Model") then child:GetPivot().Position
			else nil
		if pivot then
			local a = math.atan2(pivot.Z, pivot.X)
			local diff = math.abs((a - gate + math.pi) % (2 * math.pi) - math.pi)
			if diff < math.rad(ZoneBuilder.GATE_HALF_ANGLE) then
				child:Destroy()
			end
		end
	end
end

-- Degrees either side of a zone angle that MapBuilder leaves open in the wall.
ZoneBuilder.GATE_HALF_ANGLE = 2.4

local function buildGate(zone: Zones.ZoneDef, folder: Folder)
	local dir = Zones.direction(zone)
	local tangent = Vector3.new(-dir.Z, 0, dir.X)
	local center = dir * RING_R
	local facing = CFrame.lookAt(center, Vector3.zero) -- -Z faces the map centre
	for side = -1, 1, 2 do
		local base = center + tangent * side * GATE_HALF_WIDTH
		local pillarFrame = CFrame.lookAt(base, base - dir) + Vector3.new(0, GATE_HEIGHT / 2, 0)
		part("GatePillar", Vector3.new(6, GATE_HEIGHT, 6), pillarFrame, STONE, folder, Enum.Material.Slate)
		part(
			"GatePillarCap",
			Vector3.new(7.5, 1.5, 7.5),
			pillarFrame * CFrame.new(0, GATE_HEIGHT / 2 + 0.75, 0),
			DARK_STONE,
			folder,
			Enum.Material.Slate
		)
		local ok, lantern = pcall(AssetLibraryBuilder.get, "Props", "Lantern")
		if ok then
			local model = lantern :: Model
			model:PivotTo(pillarFrame * CFrame.new(0, GATE_HEIGHT / 2 + 1.5, 0))
			model.Parent = folder
		end
	end
	local lintel = part(
		"GateLintel",
		Vector3.new(GATE_HALF_WIDTH * 2 + 8, 3, 5),
		facing + Vector3.new(0, GATE_HEIGHT - 1, 0),
		DARK_STONE,
		folder,
		Enum.Material.Slate
	)
	-- Name board on both faces of the lintel.
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = lintel
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = zone.color
		label.TextStrokeTransparency = 0.2
		label.Text = if face == Enum.NormalId.Front
			then `{string.upper(zone.name)} · Foraging {zone.foraging}`
			else "THE GROVE"
		label.Parent = gui
	end
end

-- Dirt road from the gate to the clearing, carved through the hills.
local function buildRoad(zone: Zones.ZoneDef)
	local dir = Zones.direction(zone)
	local from = dir * (RING_R - 4)
	local to = dir * (Config.Zones.CenterRadius - Config.Zones.Radius + 10)
	local terrain = Workspace.Terrain
	-- Round brushes every few studs: thin rotated blocks voxelize patchily on diagonals.
	local steps = math.ceil((to - from).Magnitude / 4)
	for i = 0, steps do
		local at = from:Lerp(to, i / steps)
		terrain:FillCylinder(CFrame.new(at.X, 40, at.Z), 80, GATE_HALF_WIDTH + 3, Enum.Material.Air)
		slab(at, GATE_HALF_WIDTH + 3, Enum.Material.Grass)
	end
	-- Dirt strip: axis-aligned blocks (small FillCylinders do not repaint full voxels).
	for i = 0, steps do
		local at = from:Lerp(to, i / steps)
		-- Up to y = 2: the visible surface is the half-full voxel row above y = 0.
		terrain:FillBlock(CFrame.new(at.X, -3, at.Z), Vector3.new(10, DEPTH + 2, 10), Enum.Material.Ground)
	end
end

-- Backdrop trees/rocks (ForestBuilder) must not stand in a clearing or on a road.
local function clearBackdrop(zone: Zones.ZoneDef)
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local decor = root and root:FindFirstChild("Decor")
	local backdrop = decor and decor:FindFirstChild("Backdrop")
	if not backdrop then
		return
	end
	local center = Zones.center(zone)
	local dir = Zones.direction(zone)
	for _, child in backdrop:GetChildren() do
		local pivot = if child:IsA("Model")
			then child:GetPivot().Position
			elseif child:IsA("BasePart") then child.Position
			else nil
		if pivot then
			local flat = Vector3.new(pivot.X, 0, pivot.Z)
			local along = flat:Dot(dir)
			local across = (flat - dir * along).Magnitude
			local onRoad = along > RING_R - 10 and along < Config.Zones.CenterRadius and across < GATE_HALF_WIDTH + 8
			if onRoad or (flat - center).Magnitude < Config.Zones.Radius + 8 then
				child:Destroy()
			end
		end
	end
end

-- Flat clearing ringed by rocky hills (open on the road side).
local function buildClearing(zone: Zones.ZoneDef, floor: Enum.Material)
	local terrain = Workspace.Terrain
	local center = Zones.center(zone)
	local radius = Config.Zones.Radius
	terrain:FillCylinder(CFrame.new(center.X, 50, center.Z), 100, radius + 4, Enum.Material.Air)
	slab(center, radius + 4, floor)
	local rng = Random.new(zone.angle * 31)
	local inward = math.atan2(-center.Z, -center.X) -- the road comes in from the map centre
	for k = 0, 23 do
		local a = (k / 24) * math.pi * 2
		local diff = math.abs((a - inward + math.pi) % (2 * math.pi) - math.pi)
		if diff > math.rad(16) then
			local r = radius + rng:NextNumber(12, 20)
			local size = rng:NextNumber(14, 22)
			terrain:FillBall(
				center + Vector3.new(math.cos(a) * r, -size * 0.25, math.sin(a) * r),
				size,
				if rng:NextNumber() < 0.6 then Enum.Material.Rock else Enum.Material.Grass
			)
		end
	end
end

-- Spots inside the clearing (deterministic per zone), kept off the central path.
local function scatter(zone: Zones.ZoneDef, count: number, minR: number, maxR: number, seed: number): { Vector3 }
	local rng = Random.new(zone.angle * 1000 + seed)
	local center = Zones.center(zone)
	local spots = {}
	for _ = 1, count do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(minR, maxR)
		table.insert(spots, center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end
	return spots
end

local function crystalCluster(at: Vector3, rng: Random, folder: Instance, lit: boolean)
	local palette = {
		Color3.fromRGB(120, 220, 255),
		Color3.fromRGB(170, 140, 255),
		Color3.fromRGB(200, 245, 255),
	}
	local shards = rng:NextInteger(3, 5)
	for i = 1, shards do
		local h = rng:NextNumber(4, 13)
		local w = rng:NextNumber(1.2, 2.6)
		local offset = Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))
		local tilt = CFrame.Angles(
			math.rad(rng:NextNumber(-25, 25)),
			rng:NextNumber(0, math.pi),
			math.rad(rng:NextNumber(-25, 25))
		)
		local shard = part(
			"Crystal",
			Vector3.new(w, h, w),
			CFrame.new(at + offset) * tilt * CFrame.new(0, h / 2 - 0.5, 0),
			palette[rng:NextInteger(1, #palette)],
			folder,
			Enum.Material.Glass
		)
		shard.Transparency = 0.15
		shard.CanCollide = h > 6
		if lit and i == 1 then
			shard.Material = Enum.Material.Neon
			glow(shard, shard.Color, 18)
		end
	end
end

local function buildCrystalHollow(zone: Zones.ZoneDef, folder: Folder)
	buildClearing(zone, Enum.Material.Slate)
	local rng = Random.new(1101)
	for i, spot in scatter(zone, 16, 14, Config.Zones.Radius - 6, 1) do
		crystalCluster(spot, rng, folder, i % 3 == 0)
	end
	-- Giant geode at the centre.
	crystalCluster(Zones.center(zone), Random.new(7), folder, true)
	crystalCluster(Zones.center(zone) + Vector3.new(4, 0, -3), Random.new(8), folder, false)
end

local function mushroom(at: Vector3, height: number, capColor: Color3, folder: Instance, lit: boolean)
	local stemRadius = math.max(0.8, height * 0.12)
	part(
		"MushroomStem",
		Vector3.new(height, stemRadius * 2, stemRadius * 2),
		CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(230, 220, 195),
		folder,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	local capWidth = height * 0.9
	local cap = part(
		"MushroomCap",
		Vector3.new(capWidth, height * 0.35, capWidth),
		CFrame.new(at + Vector3.new(0, height, 0)),
		capColor,
		folder,
		if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	if lit then
		glow(cap, capColor, 20)
	end
end

local function buildMire(zone: Zones.ZoneDef, folder: Folder)
	buildClearing(zone, Enum.Material.Mud)
	local terrain = Workspace.Terrain
	-- Murky pools (shallow, walkable).
	for _, spot in scatter(zone, 3, 22, 46, 2) do
		terrain:FillBall(spot + Vector3.new(0, -4, 0), 10, Enum.Material.Air)
		terrain:FillBall(spot + Vector3.new(0, -9, 0), 10, Enum.Material.Water)
	end
	local caps = {
		Color3.fromRGB(150, 90, 210),
		Color3.fromRGB(90, 200, 170),
		Color3.fromRGB(200, 110, 160),
	}
	local rng = Random.new(2202)
	for i, spot in scatter(zone, 12, 16, Config.Zones.Radius - 8, 3) do
		mushroom(spot, rng:NextNumber(8, 20), caps[(i % #caps) + 1], folder, false)
	end
	for i, spot in scatter(zone, 14, 6, Config.Zones.Radius - 4, 4) do
		mushroom(spot, rng:NextNumber(1.6, 3.2), caps[(i % #caps) + 1], folder, i % 2 == 0)
	end
	-- Low drifting spores.
	local emitterPart = part(
		"SporeHaze",
		Vector3.new(Config.Zones.Radius * 1.6, 1, Config.Zones.Radius * 1.6),
		CFrame.new(Zones.center(zone) + Vector3.new(0, 2, 0)),
		Color3.new(1, 1, 1),
		folder
	)
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	local spores = Instance.new("ParticleEmitter")
	spores.Color = ColorSequence.new(Color3.fromRGB(180, 255, 140))
	spores.LightEmission = 0.8
	spores.Size = NumberSequence.new(0.35)
	spores.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	spores.Lifetime = NumberRange.new(4, 7)
	spores.Rate = 30
	spores.Speed = NumberRange.new(0.5, 1.5)
	spores.SpreadAngle = Vector2.new(180, 180)
	spores.Acceleration = Vector3.new(0, 0.6, 0)
	spores.Parent = emitterPart
end

local function buildShrine(zone: Zones.ZoneDef, folder: Folder)
	buildClearing(zone, Enum.Material.Grass)
	local center = Zones.center(zone)
	slab(center, 26, Enum.Material.Cobblestone)
	-- Raised dais with a glowing rune circle.
	part(
		"Dais",
		Vector3.new(2, 30, 30),
		CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		folder,
		Enum.Material.Slate,
		Enum.PartType.Cylinder
	)
	local rune = part(
		"RuneCircle",
		Vector3.new(0.2, 22, 22),
		CFrame.new(center + Vector3.new(0, 1.65, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		zone.color,
		folder,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)
	rune.Transparency = 0.5
	rune.CanCollide = false
	glow(rune, zone.color, 26)
	part(
		"RuneInner",
		Vector3.new(0.25, 16, 16),
		CFrame.new(center + Vector3.new(0, 1.66, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		folder,
		Enum.Material.Slate,
		Enum.PartType.Cylinder
	)
	-- Ring of pillars: some whole, some broken, two toppled.
	local rng = Random.new(3303)
	for k = 0, 9 do
		local a = (k / 10) * math.pi * 2
		local at = center + Vector3.new(math.cos(a) * 24, 0, math.sin(a) * 24)
		if k == 3 or k == 7 then
			part(
				"FallenPillar",
				Vector3.new(16, 4, 4),
				CFrame.new(at + Vector3.new(0, 2, 0)) * CFrame.Angles(0, a + math.rad(70), 0),
				STONE,
				folder,
				Enum.Material.Slate,
				Enum.PartType.Cylinder
			)
		else
			local h = if k % 2 == 0 then 18 else rng:NextNumber(6, 11)
			part(
				"Pillar",
				Vector3.new(h, 4, 4),
				CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				STONE,
				folder,
				Enum.Material.Slate,
				Enum.PartType.Cylinder
			)
			part(
				"PillarBase",
				Vector3.new(5.5, 1.2, 5.5),
				CFrame.new(at + Vector3.new(0, 0.6, 0)),
				DARK_STONE,
				folder,
				Enum.Material.Slate
			)
		end
	end
	-- Two standing arches across the clearing.
	for _, a in { 0.6, 0.6 + math.pi } do
		local at = center + Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44)
		local frame = CFrame.lookAt(at, center)
		for side = -1, 1, 2 do
			part(
				"ArchPillar",
				Vector3.new(3.5, 16, 3.5),
				frame * CFrame.new(side * 6, 8, 0),
				STONE,
				folder,
				Enum.Material.Slate
			)
		end
		part("ArchTop", Vector3.new(16, 2.5, 4), frame * CFrame.new(0, 17, 0), DARK_STONE, folder, Enum.Material.Slate)
	end
	-- Rubble blocks.
	for _, spot in scatter(zone, 14, 30, Config.Zones.Radius - 6, 5) do
		local s = rng:NextNumber(2, 4.5)
		part(
			"Rubble",
			Vector3.new(s, s * 0.7, s * 1.2),
			CFrame.new(spot + Vector3.new(0, s * 0.3, 0))
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(rng:NextNumber(-12, 12))),
			STONE,
			folder,
			Enum.Material.Slate
		)
	end
end

-- M9-08 Frostfall: snowfield, frozen lake, ice spires and snow-capped boulders.
local function buildFrostfall(zone: Zones.ZoneDef, folder: Folder)
	buildClearing(zone, Enum.Material.Snow)
	local terrain = Workspace.Terrain
	local center = Zones.center(zone)
	-- Frozen lake (walkable ice) off-centre.
	local lake = center + (Zones.direction(zone) * 22)
	terrain:FillBlock(CFrame.new(lake.X, -3, lake.Z), Vector3.new(36, DEPTH + 2, 28), Enum.Material.Ice)
	local rng = Random.new(4404)
	local ice = { Color3.fromRGB(170, 225, 255), Color3.fromRGB(210, 240, 255), Color3.fromRGB(140, 200, 245) }
	for i, spot in scatter(zone, 14, 12, Config.Zones.Radius - 6, 6) do
		local h = rng:NextNumber(6, 18)
		local w = rng:NextNumber(2, 4)
		local spire = part(
			"IceSpire",
			Vector3.new(w, h, w),
			CFrame.new(spot)
				* CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, math.pi), 0)
				* CFrame.new(0, h / 2 - 0.5, 0),
			ice[(i % #ice) + 1],
			folder,
			Enum.Material.Glass
		)
		spire.Transparency = 0.2
		if i % 4 == 0 then
			glow(spire, spire.Color, 16)
		end
	end
	-- Snow-capped boulders.
	for _, spot in scatter(zone, 8, 20, Config.Zones.Radius - 10, 7) do
		local s = rng:NextNumber(4, 7)
		terrain:FillBall(spot + Vector3.new(0, s * 0.2, 0), s, Enum.Material.Rock)
		terrain:FillBall(spot + Vector3.new(0, s * 0.55, 0), s * 0.7, Enum.Material.Snow)
	end
	-- Falling snow over the clearing.
	local emitterPart = part(
		"Snowfall",
		Vector3.new(Config.Zones.Radius * 1.8, 1, Config.Zones.Radius * 1.8),
		CFrame.new(center + Vector3.new(0, 45, 0)),
		Color3.new(1, 1, 1),
		folder
	)
	emitterPart.Transparency = 1
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	local snow = Instance.new("ParticleEmitter")
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.Size = NumberSequence.new(0.3)
	snow.Lifetime = NumberRange.new(8, 10)
	snow.Rate = 60
	snow.Speed = NumberRange.new(4, 6)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.SpreadAngle = Vector2.new(20, 20)
	snow.Parent = emitterPart
end

local BUILDERS: { [string]: (Zones.ZoneDef, Folder) -> () } = {
	Crystal = buildCrystalHollow,
	Mire = buildMire,
	Shrine = buildShrine,
	Frostfall = buildFrostfall,
}

function ZoneBuilder.build(): string
	CollisionGroups.ensure()
	local root = Workspace:FindFirstChild("AnomalyGrove")
	if not root then
		error("MapBuilder.build() must run before ZoneBuilder.build()", 2)
	end
	local old = root:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = root

	local count = 0
	for _, zone in Zones.list() do
		local zoneFolder = Instance.new("Folder")
		zoneFolder.Name = zone.id
		zoneFolder.Parent = folder
		cutGate(zone.angle)
		clearBackdrop(zone)
		buildRoad(zone)
		local build = BUILDERS[zone.id]
		if build then
			build(zone, zoneFolder)
		else
			buildClearing(zone, Enum.Material.Grass)
		end
		buildGate(zone, zoneFolder)
		count += 1
		task.wait()
	end
	return `[ZoneBuilder] built {count} wild zones`
end

return ZoneBuilder
