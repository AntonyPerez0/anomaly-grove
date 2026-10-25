--!strict
-- Seed node world builder + shared node factory.
-- build() is idempotent: wipes the SeedNodes folder and rebuilds the starting nodes
-- at deterministic positions. Runtime respawns reuse createNode() from SeedSystem.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local TerrainBuilder = require(script.Parent.TerrainBuilder)

local SeedNodeBuilder = {}

local FOLDER_NAME = "SeedNodes"
local NODE_Y = 3.5 -- nodes float above the forest floor
local CORE_CLEARANCE = 20 -- keep nodes out of the Grove Heart circle at the exact center

local function nodesFolder(): Folder
	local root = Workspace:FindFirstChild("AnomalyGrove")
	if not root then
		error("MapBuilder.build() must run before SeedNodeBuilder.build()", 2)
	end
	local folder = root:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = root
	return folder
end

-- Sparkle aura + a glow ring on the ground under a node (M5-04). Children of the
-- node part, so they vanish with it on harvest.
local function dressNode(node: BasePart, color: Color3)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = 8
	sparkles.Speed = NumberRange.new(1.5, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, 2, 0)
	sparkles.Parent = node

	local ring = Instance.new("Part")
	ring.Name = "GlowRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 6, 6)
	ring.CFrame = CFrame.new(node.Position.X, 0.15, node.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.6
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = node
end

-- Floating glowing seed pod. The ProximityPrompt instance is created here; SeedSystem
-- connects its behavior (builders stay behavior-free).
function SeedNodeBuilder.createNode(position: Vector3): BasePart
	local node = Instance.new("Part")
	node.Name = "SeedNode"
	node.Shape = Enum.PartType.Ball
	node.Size = Vector3.new(2.5, 2.5, 2.5)
	node.CFrame = CFrame.new(position)
	node.Color = Color3.fromRGB(70, 240, 200)
	node.Material = Enum.Material.Neon
	node.Transparency = 0.1
	node.Anchored = true
	node.CanCollide = false
	node.CanQuery = true

	local light = Instance.new("PointLight")
	light.Color = node.Color
	light.Brightness = 1
	light.Range = 12
	light.Parent = node

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Harvest"
	prompt.ObjectText = "Anomaly Seed"
	prompt.HoldDuration = Config.Seeds.HarvestTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = node
	dressNode(node, node.Color)

	node.Parent = nodesFolder()
	return node
end

-- Grove Heart node (M3-03): a mutation-flavored seed pod at the exact map center
-- with a beacon beam into the sky. Night-only; SeedSystem spawns/despawns the cohort.
function SeedNodeBuilder.createGroveNode(position: Vector3, flavor: string): BasePart
	local node = Instance.new("Part")
	node.Name = "GroveHeartNode"
	node.Shape = Enum.PartType.Ball
	node.Size = Vector3.new(2.5, 2.5, 2.5)
	node.CFrame = CFrame.new(position)
	node:SetAttribute("GroveHeart", true)
	node:SetAttribute("MutationFlavor", flavor)
	local info = Config.Mutations[flavor :: string]
	node.Color = if info then info.color else Color3.fromRGB(255, 200, 60)
	node.Material = Enum.Material.Neon
	node.Transparency = 0.05
	node.Anchored = true
	node.CanCollide = false
	node.CanQuery = true

	local light = Instance.new("PointLight")
	light.Color = node.Color
	light.Brightness = 2
	light.Range = 16
	light.Parent = node

	-- Beacon: one part, two attachments (base + sky), camera-facing beam.
	local base = Instance.new("Attachment")
	base.Name = "BeaconBase"
	base.Position = Vector3.zero
	base.Parent = node
	local sky = Instance.new("Attachment")
	sky.Name = "BeaconSky"
	sky.Position = Vector3.new(0, Config.GroveHeart.BeaconHeight, 0)
	sky.Parent = node
	local beam = Instance.new("Beam")
	beam.Name = "Beacon"
	beam.Attachment0 = base
	beam.Attachment1 = sky
	beam.Color = ColorSequence.new(node.Color)
	beam.Width0 = 1.4
	beam.Width1 = 0.25
	beam.Transparency = NumberSequence.new(0.35)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = node

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Harvest"
	prompt.ObjectText = "Grove Heart Seed"
	prompt.HoldDuration = Config.Seeds.HarvestTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = node
	dressNode(node, node.Color)

	node.Parent = nodesFolder()
	return node
end

-- Wild-zone seed node (2026-10-18): a faceted gem in the zone colour with a short
-- beacon, so it reads as rarer than a forest pod. SeedSystem respawns these.
function SeedNodeBuilder.createZoneNode(position: Vector3, zone: Config.ZoneDef): BasePart
	local node = Instance.new("Part")
	node.Name = "ZoneSeedNode"
	node.Size = Vector3.new(2.2, 2.2, 2.2)
	node.CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), math.rad(45), 0)
	node:SetAttribute("ZoneSeed", zone.seed.id)
	node.Color = zone.color
	node.Material = Enum.Material.Neon
	node.Transparency = 0.05
	node.Anchored = true
	node.CanCollide = false
	node.CanQuery = true

	local light = Instance.new("PointLight")
	light.Color = node.Color
	light.Brightness = 2
	light.Range = 14
	light.Parent = node

	local base = Instance.new("Attachment")
	base.Name = "BeaconBase"
	base.Parent = node
	local sky = Instance.new("Attachment")
	sky.Name = "BeaconSky"
	sky.WorldPosition = position + Vector3.new(0, 24, 0)
	sky.Parent = node
	local beam = Instance.new("Beam")
	beam.Name = "Beacon"
	beam.Attachment0 = base
	beam.Attachment1 = sky
	beam.Color = ColorSequence.new(node.Color)
	beam.Width0 = 0.9
	beam.Width1 = 0.1
	beam.Transparency = NumberSequence.new(0.45, 1)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Parent = node

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Harvest"
	prompt.ObjectText = `{zone.seed.name} (Foraging {zone.foraging})`
	prompt.HoldDuration = Config.Seeds.HarvestTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = node
	dressNode(node, node.Color)

	node.Parent = nodesFolder()
	return node
end

-- Random spot in the forest that is not in the pond and not inside a tree/rock/node
-- (M5-03/04: the forest is dense now). Falls back to the last candidate after N tries.
local PLACEMENT_TRIES = 16
local CLEARANCE = 3.5

function SeedNodeBuilder.randomForestPosition(rng: Random): Vector3
	local candidate = Vector3.zero
	for _ = 1, PLACEMENT_TRIES do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = rng:NextNumber(CORE_CLEARANCE, Config.Map.ForestRadius - 8)
		candidate = Vector3.new(math.cos(angle) * radius, NODE_Y, math.sin(angle) * radius)
		if not TerrainBuilder.inPond(candidate.X, candidate.Z, 4) then
			local blocking = Workspace:GetPartBoundsInRadius(candidate, CLEARANCE)
			if #blocking == 0 then
				return candidate
			end
		end
	end
	return candidate
end

function SeedNodeBuilder.digest(): string
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local folder = root and root:FindFirstChild(FOLDER_NAME)
	if not folder then
		return "MISSING"
	end
	local entries: { string } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			local p = child.Position
			table.insert(entries, string.format("%.1f,%.1f,%.1f", p.X, p.Y, p.Z))
		end
	end
	table.sort(entries)
	return table.concat(entries, ";")
end

function SeedNodeBuilder.build(): string
	local folder = nodesFolder()
	folder:ClearAllChildren()
	local rng = Random.new(4242)
	for _ = 1, Config.Seeds.MinNodes do
		SeedNodeBuilder.createNode(SeedNodeBuilder.randomForestPosition(rng))
	end
	return `[SeedNodeBuilder] built {Config.Seeds.MinNodes} seed nodes`
end

return SeedNodeBuilder
