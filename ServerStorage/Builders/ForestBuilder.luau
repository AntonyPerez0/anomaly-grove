--!strict
-- Dressed world (M5-04): a dense stylized forest (library trees, bushes, rocks,
-- mushrooms, logs), glowing anomaly crystal clusters, fireflies, the Grove Heart
-- standing-stone circle, a giant landmark tree, greenery between the plots and
-- trees on the backdrop hills.
-- Edit mode: require(game.ServerStorage.Builders.ForestBuilder).build()  (after MapBuilder)
-- Idempotent + deterministic: wipes AnomalyGrove.Decor and re-places from a fixed seed.
-- Paths, the plaza, the pond and plot footprints are kept clear.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local AssetLibraryBuilder = require(script.Parent.AssetLibraryBuilder)
local CollisionGroups = require(script.Parent.CollisionGroups)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local ForestBuilder = {}

local MAP = Config.Map
local FOLDER_NAME = "Decor"
ForestBuilder.DECOR_GROUP = CollisionGroups.Decor

local CRYSTAL_COLORS = {
	Color3.fromRGB(80, 255, 220),
	Color3.fromRGB(170, 100, 255),
	Color3.fromRGB(110, 190, 255),
}

-- Distance from (x, z) to the nearest radial path (plot gates + hub path), in studs.
local function pathDistance(x: number, z: number): number
	local best = math.huge
	local r = math.sqrt(x * x + z * z)
	local angles = {}
	for i = 0, MAP.Plots - 1 do
		table.insert(angles, math.rad(i * (360 / MAP.Plots)))
	end
	table.insert(angles, math.rad(22.5)) -- hub path
	for _, a in angles do
		local dx, dz = math.cos(a), math.sin(a)
		local along = x * dx + z * dz
		if along > 0 then
			best = math.min(best, math.abs(-x * dz + z * dx))
		end
	end
	if r < MAP.GroveHeartRadius + 14 then
		best = 0
	end
	return best
end

local function insidePlot(x: number, z: number, margin: number): boolean
	local plotR = TerrainBuilder.plotCenterRadius()
	local half = MAP.PlotSize / 2 + margin
	for i = 0, MAP.Plots - 1 do
		local a = math.rad(i * (360 / MAP.Plots))
		local center = Vector3.new(math.cos(a) * plotR, 0, math.sin(a) * plotR)
		local frame = CFrame.lookAt(center, Vector3.zero)
		local localPos = frame:PointToObjectSpace(Vector3.new(x, 0, z))
		if math.abs(localPos.X) < half and math.abs(localPos.Z) < half then
			return true
		end
	end
	return false
end

type Placer = {
	rng: Random,
	taken: { Vector3 },
}

-- Free spot test: off paths, out of pond/plots, and `spacing` from earlier props.
local function isFree(placer: Placer, pos: Vector3, pathMargin: number, spacing: number): boolean
	if pathDistance(pos.X, pos.Z) < MAP.PathWidth / 2 + pathMargin then
		return false
	end
	if TerrainBuilder.inPond(pos.X, pos.Z, 5) then
		return false
	end
	if insidePlot(pos.X, pos.Z, 4) then
		return false
	end
	-- Hub ramp + platform footprint.
	local hubA = math.rad(22.5)
	local hub = Vector3.new(math.cos(hubA), 0, math.sin(hubA)) * MAP.RingRadius
	if (Vector3.new(pos.X, 0, pos.Z) - hub).Magnitude < 70 then
		return false
	end
	for _, other in placer.taken do
		if (other - pos).Magnitude < spacing then
			return false
		end
	end
	return true
end

local function ringPoint(rng: Random, minR: number, maxR: number): Vector3
	local a = rng:NextNumber(0, math.pi * 2)
	-- sqrt for an even spread over the annulus area
	local r = math.sqrt(rng:NextNumber(minR * minR, maxR * maxR))
	return Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- Categories whose shadows add cost but no read on phones (M5-11 perf pass).
local NO_SHADOW = { Bushes = true, Rocks = true, Props = true, Backdrop = true, CorridorBushes = true }

local function tag(model: Instance, folderName: string)
	local noShadow = NO_SHADOW[folderName] == true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = ForestBuilder.DECOR_GROUP
			if noShadow then
				d.CastShadow = false
			end
		end
	end
end

local function placeAsset(
	parent: Instance,
	category: string,
	names: { string },
	rng: Random,
	pos: Vector3,
	scaleMin: number,
	scaleMax: number
): Model
	local name = names[rng:NextInteger(1, #names)]
	local model = AssetLibraryBuilder.get(category, name) :: Model
	local scale = rng:NextNumber(scaleMin, scaleMax)
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(scale)
	end
	model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	tag(model, parent.Name)
	if category == "Rocks" then
		-- The pack ships near-white; tint to mossy stone so rocks sit in the palette.
		local shade = rng:NextNumber(0.85, 1.1)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(118 * shade, 116 * shade, 112 * shade)
				d.Material = Enum.Material.Slate
			end
		end
	end
	model.Parent = parent
	return model
end

local function scatter(
	placer: Placer,
	parent: Instance,
	category: string,
	count: number,
	minR: number,
	maxR: number,
	pathMargin: number,
	spacing: number,
	scaleMin: number,
	scaleMax: number,
	yOffset: number?
): number
	local names = AssetLibraryBuilder.list(category)
	local placed = 0
	local attempts = 0
	while placed < count and attempts < count * 25 do
		attempts += 1
		local pos = ringPoint(placer.rng, minR, maxR)
		if isFree(placer, pos, pathMargin, spacing) then
			table.insert(placer.taken, pos)
			placeAsset(parent, category, names, placer.rng, pos + Vector3.new(0, yOffset or 0, 0), scaleMin, scaleMax)
			placed += 1
		end
	end
	return placed
end

-- Procedural anomaly crystal cluster: glassy shards around a neon core.
local function crystal(parent: Instance, rng: Random, pos: Vector3, withLight: boolean)
	local model = Instance.new("Model")
	model.Name = "AnomalyCrystal"
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local shards = rng:NextInteger(3, 5)
	for i = 1, shards do
		local h = rng:NextNumber(3, 7.5)
		local shard = Instance.new("Part")
		shard.Name = "Shard" .. i
		shard.Size = Vector3.new(rng:NextNumber(1, 1.8), h, rng:NextNumber(1, 1.8))
		shard.Color = color
		shard.Material = if i == 1 then Enum.Material.Neon else Enum.Material.Glass
		shard.Transparency = if i == 1 then 0.1 else 0.25
		shard.Anchored = true
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CanTouch = false
		shard.CastShadow = false
		local tiltX = rng:NextNumber(-0.45, 0.45)
		local tiltZ = rng:NextNumber(-0.45, 0.45)
		local offset = Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		shard.CFrame = CFrame.new(pos + offset)
			* CFrame.Angles(tiltX, rng:NextNumber(0, math.pi), tiltZ)
			* CFrame.new(0, h / 2 - 0.6, 0)
		shard.Parent = model
	end
	if withLight then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 14
		light.Brightness = 1.4
		light.Shadows = false
		light.Parent = model:FindFirstChild("Shard1")
	end
	model.Parent = parent
end

-- Firefly emitters (always on; only visible once the light drops at night).
local function fireflies(parent: Instance, pos: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "Fireflies"
	anchor.Size = Vector3.new(40, 10, 40)
	anchor.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(220, 255, 140))
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Rate = 3
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.2, 0)
	emitter.Brightness = 3
	emitter.Parent = anchor
	anchor.Parent = parent
end

-- Grove Heart: standing stones + glowing rune ring around the night node circle.
local function groveHeart(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "GroveHeartRing"
	folder.Parent = parent
	local stones = 8
	local radius = MAP.GroveHeartRadius + 6
	for i = 1, stones do
		local a = (i / stones) * math.pi * 2
		local pos = Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local stone = Instance.new("Part")
		stone.Name = "Monolith" .. i
		local h = if i % 2 == 0 then 11 else 8
		stone.Size = Vector3.new(3.2, h, 2.2)
		stone.CFrame = CFrame.lookAt(pos + Vector3.new(0, h / 2 - 0.5, 0), Vector3.new(0, h / 2, 0))
			* CFrame.Angles(math.rad(-6), 0, 0)
		stone.Material = Enum.Material.Slate
		stone.Color = Color3.fromRGB(105, 102, 115)
		stone.Anchored = true
		stone.CollisionGroup = ForestBuilder.DECOR_GROUP
		stone.Parent = folder
		local rune = Instance.new("Part")
		rune.Name = "Rune" .. i
		rune.Size = Vector3.new(1.2, 2.4, 0.2)
		rune.CFrame = stone.CFrame * CFrame.new(0, h * 0.15, -1.15)
		rune.Material = Enum.Material.Neon
		rune.Color = Color3.fromRGB(170, 110, 255)
		rune.Anchored = true
		rune.CanCollide = false
		rune.CanQuery = false
		rune.CanTouch = false
		rune.Parent = folder
	end
end

function ForestBuilder.build(): string
	local root = Workspace:FindFirstChild("AnomalyGrove")
	assert(root, "MapBuilder.build() must run before ForestBuilder.build()")
	CollisionGroups.ensure()
	local old = root:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
	local decor = Instance.new("Folder")
	decor.Name = FOLDER_NAME
	decor.Parent = root

	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = decor
		return f
	end

	local placer: Placer = { rng = Random.new(20261017), taken = {} }
	local forestR = MAP.ForestRadius
	local counts = {}

	-- Landmark giant tree opposite the pond, visible from every plot.
	local pond = MAP.Pond
	local giantPos = Vector3.new(-pond.X, 0, -pond.Z) * 0.9
	local giant = AssetLibraryBuilder.get("Landmarks", "GiantTree") :: Model
	giant:ScaleTo(0.55)
	giant:PivotTo(CFrame.new(giantPos) * CFrame.Angles(0, 1.1, 0))
	tag(giant, "Landmarks")
	giant.Parent = sub("Landmarks")
	table.insert(placer.taken, giantPos)

	-- Forest interior.
	local trees = sub("Trees")
	counts.trees = scatter(placer, trees, "Trees", 110, MAP.GroveHeartRadius + 24, forestR - 6, 7, 13, 0.42, 0.68)
	counts.bushes = scatter(placer, sub("Bushes"), "Bushes", 100, MAP.GroveHeartRadius + 18, forestR, 3, 5, 0.6, 1.2)
	counts.rocks = scatter(placer, sub("Rocks"), "Rocks", 40, MAP.GroveHeartRadius + 16, forestR, 2, 6, 0.8, 1.8, -0.4)
	local props = sub("Props")
	local propNames = { "Mushrooms", "Log" }
	local placedProps = 0
	for _ = 1, 40 do
		local pos = ringPoint(placer.rng, MAP.GroveHeartRadius + 18, forestR - 4)
		if isFree(placer, pos, 2, 5) then
			table.insert(placer.taken, pos)
			local name = propNames[placer.rng:NextInteger(1, #propNames)]
			local model = AssetLibraryBuilder.get("Props", name) :: Model
			model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, placer.rng:NextNumber(0, math.pi * 2), 0))
			tag(model, "Props")
			model.Parent = props
			placedProps += 1
		end
	end
	counts.props = placedProps

	-- Anomaly crystals (a few lit; lights are the expensive part on phones).
	local crystals = sub("Crystals")
	local placedCrystals = 0
	for i = 1, 60 do
		if placedCrystals >= 28 then
			break
		end
		local pos = ringPoint(placer.rng, MAP.GroveHeartRadius + 16, forestR - 4)
		if isFree(placer, pos, 2, 6) then
			table.insert(placer.taken, pos)
			crystal(crystals, placer.rng, pos, i % 3 == 0)
			placedCrystals += 1
		end
	end
	counts.crystals = placedCrystals

	-- Fireflies across the forest.
	local flies = sub("Fireflies")
	for k = 0, 9 do
		local a = (k / 10) * math.pi * 2 + 0.3
		local r = if k % 2 == 0 then forestR * 0.45 else forestR * 0.8
		fireflies(flies, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
	end

	-- Greenery between the plots and along the outer corridor.
	counts.corridorTrees =
		scatter(placer, sub("CorridorTrees"), "Trees", 26, forestR + 8, MAP.RingRadius - 12, 6, 18, 0.32, 0.48)
	counts.corridorBushes =
		scatter(placer, sub("CorridorBushes"), "Bushes", 40, forestR + 4, MAP.RingRadius - 8, 3, 7, 0.6, 1)

	-- Backdrop: trees on the hills outside the wall (raycast onto the terrain).
	local backdrop = sub("Backdrop")
	local treeNames = AssetLibraryBuilder.list("Trees")
	local backdropCount = 0
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	for _ = 1, 140 do
		local pos = ringPoint(placer.rng, MAP.RingRadius + 25, MAP.TerrainRadius - 30)
		local hit = Workspace:Raycast(pos + Vector3.new(0, 300, 0), Vector3.new(0, -400, 0), params)
		if hit and hit.Material ~= Enum.Material.Water and hit.Material ~= Enum.Material.Rock then
			placeAsset(backdrop, "Trees", treeNames, placer.rng, hit.Position - Vector3.new(0, 1, 0), 0.4, 0.75)
			backdropCount += 1
		end
	end
	counts.backdrop = backdropCount

	groveHeart(decor)

	-- The old flat Grove Heart disc becomes a subtle glowing rune floor.
	local heart = root:FindFirstChild("GroveHeart")
	if heart and heart:IsA("BasePart") then
		heart.Transparency = 0.55
		heart.Color = Color3.fromRGB(150, 90, 255)
		heart.Size = Vector3.new(0.2, heart.Size.Y, heart.Size.Z)
		heart.CFrame = CFrame.new(0, 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	end

	local parts = 0
	for _, d in decor:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return string.format(
		"[ForestBuilder] trees=%d bushes=%d rocks=%d props=%d crystals=%d corridor=%d/%d backdrop=%d parts=%d",
		counts.trees,
		counts.bushes,
		counts.rocks,
		counts.props,
		counts.crystals,
		counts.corridorTrees,
		counts.corridorBushes,
		counts.backdrop,
		parts
	)
end

return ForestBuilder
