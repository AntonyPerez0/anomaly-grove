--!strict
-- Smooth-terrain world base (M5-03): grass field with animated blades, leafy forest
-- floor, dirt paths from every plot gate into the forest, a cobble plaza around the
-- Grove Heart, a pond, and rolling hills outside the ring wall as a backdrop.
-- Edit mode: require(game.ServerStorage.Builders.TerrainBuilder).build()
-- Idempotent: Terrain:Clear() then a deterministic rebuild from Config.Map.

local Workspace = game:GetService("Workspace")
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TerrainBuilder = {}

local MAP = Config.Map
local DEPTH = 16 -- ground slab thickness; the top surface sits at y = 0

local COLORS = {
	grass = Color3.fromRGB(96, 158, 72),
	leafy = Color3.fromRGB(78, 140, 62),
	dirt = Color3.fromRGB(150, 112, 74),
	cobble = Color3.fromRGB(150, 146, 140),
	sand = Color3.fromRGB(226, 206, 150),
	rock = Color3.fromRGB(128, 126, 132),
	water = Color3.fromRGB(70, 185, 205),
}

-- Plot centre distance, shared with MapBuilder (inner plot edge touches the forest).
function TerrainBuilder.plotCenterRadius(): number
	return MAP.ForestRadius + (MAP.RingRadius - MAP.ForestRadius - MAP.OuterCorridor) / 2
end

local function slab(terrain: Terrain, center: Vector3, radius: number, material: Enum.Material)
	-- Cylinder axis is Y by default for FillCylinder.
	terrain:FillCylinder(CFrame.new(center.X, -DEPTH / 2, center.Z), DEPTH, radius, material)
end

local function path(terrain: Terrain, from: Vector3, to: Vector3, width: number, material: Enum.Material)
	local flatFrom = Vector3.new(from.X, -DEPTH / 2, from.Z)
	local flatTo = Vector3.new(to.X, -DEPTH / 2, to.Z)
	local length = (flatTo - flatFrom).Magnitude
	local cf = CFrame.lookAt((flatFrom + flatTo) / 2, flatTo)
	terrain:FillBlock(cf, Vector3.new(width, DEPTH, length), material)
end

function TerrainBuilder.build(): string
	local terrain = Workspace.Terrain
	terrain:Clear()

	terrain:SetMaterialColor(Enum.Material.Grass, COLORS.grass)
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, COLORS.leafy)
	terrain:SetMaterialColor(Enum.Material.Ground, COLORS.dirt)
	terrain:SetMaterialColor(Enum.Material.Cobblestone, COLORS.cobble)
	terrain:SetMaterialColor(Enum.Material.Sand, COLORS.sand)
	terrain:SetMaterialColor(Enum.Material.Rock, COLORS.rock)
	terrain.WaterColor = COLORS.water
	terrain.WaterTransparency = 0.55
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 8
	terrain.WaterReflectance = 0.6
	pcall(function()
		terrain.Decoration = true -- animated grass blades on Grass (quality-scaled by the engine)
		terrain.GrassLength = 0.6
	end)

	-- 0) Ocean ring so the island edge reads as a coastline, not the end of the world.
	terrain:FillCylinder(CFrame.new(0, -14, 0), 8, MAP.TerrainRadius + 500, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(0, -5, 0), 10, MAP.TerrainRadius + 500, Enum.Material.Water)
	slab(terrain, Vector3.zero, MAP.TerrainRadius + 30, Enum.Material.Sand) -- beach

	-- 1) Base field out to the backdrop.
	slab(terrain, Vector3.zero, MAP.TerrainRadius, Enum.Material.Grass)

	-- 2) Backdrop hills beyond the ring wall (deterministic), so the world never ends flat.
	local rng = Random.new(777)
	local hills = 0
	for k = 0, 47 do
		local a = (k / 48) * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		local r = MAP.RingRadius + rng:NextNumber(70, 190)
		local radius = rng:NextNumber(45, 95)
		local center = Vector3.new(math.cos(a) * r, -radius * rng:NextNumber(0.35, 0.6), math.sin(a) * r)
		local material = if rng:NextNumber() < 0.25 then Enum.Material.Rock else Enum.Material.Grass
		terrain:FillBall(center, radius, material)
		hills += 1
		if k % 8 == 0 then
			task.wait()
		end
	end
	-- 3) Keep everything inside the wall (plus a margin) flat at y = 0.
	terrain:FillCylinder(CFrame.new(0, 60, 0), 120, MAP.RingRadius + 10, Enum.Material.Air)
	slab(terrain, Vector3.zero, MAP.RingRadius + 10, Enum.Material.Grass)

	-- 4) Forest floor.
	slab(terrain, Vector3.zero, MAP.ForestRadius, Enum.Material.LeafyGrass)

	-- 5) Dirt paths: each plot gate straight into the Grove Heart plaza, plus the hub path.
	local plotR = TerrainBuilder.plotCenterRadius()
	local gateR = plotR - MAP.PlotSize / 2
	for i = 0, MAP.Plots - 1 do
		local a = math.rad(i * (360 / MAP.Plots))
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		path(terrain, dir * (gateR + 2), dir * (MAP.GroveHeartRadius + 10), MAP.PathWidth, Enum.Material.Ground)
	end
	local hubA = math.rad(22.5)
	local hubDir = Vector3.new(math.cos(hubA), 0, math.sin(hubA))
	path(terrain, hubDir * (MAP.RingRadius - 60), hubDir * (MAP.ForestRadius - 10), MAP.PathWidth, Enum.Material.Ground)

	-- Carve the plot footprints so terrain never pokes through plot floors
	-- (MapBuilder puts a solid Foundation part under each Floor).
	for i = 0, MAP.Plots - 1 do
		local a = math.rad(i * (360 / MAP.Plots))
		local center = Vector3.new(math.cos(a) * plotR, 0, math.sin(a) * plotR)
		local frame = CFrame.lookAt(center, Vector3.zero)
		-- Must clear the whole [-4, 0] voxel row (4-stud grid); the Foundation part fills it.
		terrain:FillBlock(frame * CFrame.new(0, 5, 0), Vector3.new(MAP.PlotSize, 18, MAP.PlotSize), Enum.Material.Air)
	end

	-- 6) Cobble plaza around the Grove Heart.
	slab(terrain, Vector3.zero, MAP.GroveHeartRadius + 14, Enum.Material.Cobblestone)

	-- 7) Pond: sand rim, carve, fill with water (seed nodes avoid it via Config.Map.Pond).
	local pond = MAP.Pond
	slab(terrain, Vector3.new(pond.X, 0, pond.Z), pond.Radius + 5, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(pond.X, -3, pond.Z), 6, pond.Radius, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(pond.X, -3.5, pond.Z), 5, pond.Radius, Enum.Material.Water)

	return `[TerrainBuilder] terrain built ({hills} backdrop hills)`
end

-- Pure check used by seed placement: is (x, z) inside the pond (plus margin)?
function TerrainBuilder.inPond(x: number, z: number, margin: number): boolean
	local pond = MAP.Pond
	local dx, dz = x - pond.X, z - pond.Z
	return dx * dx + dz * dz < (pond.Radius + margin) ^ 2
end

return TerrainBuilder
