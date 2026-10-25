--!strict
-- Plot furniture (2026-10-18, human: "the houses seem pretty empty"). Idempotent:
-- each plot gets a "Furniture" folder that is wiped and rebuilt. Layout uses the
-- plot floor's local frame (-Z = gate, +Z = back wall) and keeps clear of every
-- gameplay spot: pedestal grid (x -22..23, z 7..39), turret corners (+-30.6,
-- +-30.6), trap tiles (z -20, x -8..8), the gate path and the claim marker.
-- Everything is anchored, in the Decor collision group (monsters pass through),
-- small pieces are non-collidable, and no lights are added (perf budget).

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local CollisionGroups = require(script.Parent.CollisionGroups)

local FurnitureBuilder = {}

local FOLDER = "Furniture"

local C = {
	wood = Color3.fromRGB(150, 104, 62),
	woodDark = Color3.fromRGB(98, 66, 40),
	metal = Color3.fromRGB(70, 72, 80),
	soil = Color3.fromRGB(82, 56, 38),
	stem = Color3.fromRGB(70, 160, 70),
	leaf = Color3.fromRGB(95, 190, 90),
	rugRed = Color3.fromRGB(150, 50, 60),
	rugGold = Color3.fromRGB(225, 175, 80),
	patio = Color3.fromRGB(214, 204, 186),
	water = Color3.fromRGB(90, 190, 255),
	stone = Color3.fromRGB(150, 150, 158),
	cushion = Color3.fromRGB(90, 120, 210),
	glow = Color3.fromRGB(120, 255, 220),
}
local FLOWERS = {
	Color3.fromRGB(255, 120, 160),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(160, 120, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 140, 70),
}

type Ctx = { folder: Folder, frame: CFrame, top: number }

local function part(
	ctx: Ctx,
	name: string,
	size: Vector3,
	at: Vector3, -- local x, BOTTOM y above the floor top, z
	color: Color3,
	material: Enum.Material,
	collide: boolean?,
	rotY: number?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.CastShadow = collide == true
	p.CollisionGroup = CollisionGroups.Decor
	local height = if shape == Enum.PartType.Cylinder then size.X else size.Y
	local cf = ctx.frame
		* CFrame.new(at.X, ctx.top + at.Y + height / 2, at.Z)
		* CFrame.Angles(0, math.rad(rotY or 0), 0)
	if shape then
		p.Shape = shape
		if shape == Enum.PartType.Cylinder then
			cf *= CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> world up
		end
	end
	p.CFrame = cf
	p.Parent = ctx.folder
	return p
end

-- Upright cylinder: height h, diameter d.
local function cyl(
	ctx: Ctx,
	name: string,
	h: number,
	d: number,
	at: Vector3,
	color: Color3,
	mat: Enum.Material,
	collide: boolean?
)
	return part(ctx, name, Vector3.new(h, d, d), at, color, mat, collide, 0, Enum.PartType.Cylinder)
end

local function flower(ctx: Ctx, x: number, y: number, z: number, index: number)
	local h = 0.9 + (index % 3) * 0.25
	cyl(ctx, "Stem", h, 0.15, Vector3.new(x, y, z), C.stem, Enum.Material.SmoothPlastic)
	part(
		ctx,
		"Bloom",
		Vector3.new(0.6, 0.6, 0.6),
		Vector3.new(x, y + h - 0.1, z),
		FLOWERS[(index % #FLOWERS) + 1],
		Enum.Material.SmoothPlastic,
		false,
		0,
		Enum.PartType.Ball
	)
end

-- Wooden planter box (length along local X unless rotated) full of flowers.
local function planter(ctx: Ctx, x: number, z: number, length: number, rotY: number)
	local box = part(
		ctx,
		"Planter",
		Vector3.new(length, 1.3, 1.8),
		Vector3.new(x, 0, z),
		C.woodDark,
		Enum.Material.Wood,
		true,
		rotY
	)
	local soil = part(
		ctx,
		"Soil",
		Vector3.new(length - 0.4, 0.1, 1.4),
		Vector3.new(x, 1.3, z),
		C.soil,
		Enum.Material.Ground,
		false,
		rotY
	)
	soil.CastShadow = false
	local axis = (CFrame.Angles(0, math.rad(rotY), 0)).RightVector
	local count = math.max(2, math.floor(length / 1.6))
	for i = 1, count do
		local t = (i - 0.5) / count - 0.5
		local offset = axis * (t * (length - 1))
		flower(ctx, x + offset.X, 1.35, z + offset.Z + (if i % 2 == 0 then 0.3 else -0.3), i)
	end
	return box
end

local function pottedPlant(ctx: Ctx, x: number, z: number)
	cyl(ctx, "Pot", 1.4, 1.8, Vector3.new(x, 0, z), Color3.fromRGB(190, 110, 70), Enum.Material.Slate, true)
	cyl(ctx, "Trunk", 1.6, 0.3, Vector3.new(x, 1.4, z), C.woodDark, Enum.Material.Wood)
	part(
		ctx,
		"Leaves",
		Vector3.new(2.6, 2.2, 2.6),
		Vector3.new(x, 2.6, z),
		C.leaf,
		Enum.Material.Grass,
		false,
		0,
		Enum.PartType.Ball
	)
end

local function barrel(ctx: Ctx, x: number, z: number)
	cyl(ctx, "Barrel", 3.2, 2.6, Vector3.new(x, 0, z), C.wood, Enum.Material.WoodPlanks, true)
	for _, y in { 0.5, 2.5 } do
		cyl(ctx, "Band", 0.2, 2.7, Vector3.new(x, y, z), C.metal, Enum.Material.Metal)
	end
end

local function crate(ctx: Ctx, size: number, x: number, y: number, z: number, rotY: number)
	part(
		ctx,
		"Crate",
		Vector3.new(size, size, size),
		Vector3.new(x, y, z),
		C.wood,
		Enum.Material.WoodPlanks,
		true,
		rotY
	)
end

-- Wall shelf: back against the side wall (local X = wallX), running along Z.
local function shelf(ctx: Ctx, wallX: number, z: number, length: number, books: boolean)
	local inward = if wallX < 0 then 1 else -1
	local x = wallX + inward * 0.7
	for _, dz in { -length / 2 + 0.2, length / 2 - 0.2 } do
		part(
			ctx,
			"ShelfSide",
			Vector3.new(1.4, 6, 0.3),
			Vector3.new(x, 0, z + dz),
			C.woodDark,
			Enum.Material.Wood,
			true
		)
	end
	part(
		ctx,
		"ShelfBack",
		Vector3.new(0.2, 6, length),
		Vector3.new(wallX + inward * 0.1, 0, z),
		C.woodDark,
		Enum.Material.Wood,
		true
	)
	for level = 0, 3 do
		local y = 0.3 + level * 1.85
		part(ctx, "ShelfBoard", Vector3.new(1.4, 0.2, length), Vector3.new(x, y, z), C.wood, Enum.Material.Wood, true)
		if level < 3 then
			local slots = math.floor(length / 0.9) - 1
			for i = 1, slots do
				local zz = z - length / 2 + 0.5 + i * ((length - 1) / slots)
				if books then
					if (i + level) % 4 ~= 0 then
						part(
							ctx,
							"Book",
							Vector3.new(1, 1.2 + ((i * 7 + level) % 3) * 0.15, 0.45),
							Vector3.new(x, y + 0.2, zz),
							FLOWERS[((i + level * 2) % #FLOWERS) + 1]:Lerp(C.woodDark, 0.35),
							Enum.Material.SmoothPlastic
						)
					end
				elseif (i + level) % 3 == 0 then
					cyl(ctx, "Jar", 0.9, 0.7, Vector3.new(x, y + 0.2, zz), C.glow, Enum.Material.Glass).Transparency =
						0.35
				elseif (i + level) % 3 == 1 then
					part(
						ctx,
						"Crystal",
						Vector3.new(0.4, 0.9, 0.4),
						Vector3.new(x, y + 0.2, zz),
						C.glow,
						Enum.Material.Neon,
						false,
						30
					)
				end
			end
		end
	end
end

local function workbench(ctx: Ctx, x: number, z: number)
	part(ctx, "BenchTop", Vector3.new(4, 0.4, 9), Vector3.new(x, 3, z), C.wood, Enum.Material.WoodPlanks, true)
	for _, d in { Vector2.new(-1.6, -4), Vector2.new(1.6, -4), Vector2.new(-1.6, 4), Vector2.new(1.6, 4) } do
		part(
			ctx,
			"Leg",
			Vector3.new(0.5, 3, 0.5),
			Vector3.new(x + d.X, 0, z + d.Y),
			C.woodDark,
			Enum.Material.Wood,
			true
		)
	end
	part(ctx, "SeedTray", Vector3.new(2.4, 0.3, 3), Vector3.new(x, 3.4, z - 2), C.woodDark, Enum.Material.Wood)
	for i = 1, 6 do
		part(
			ctx,
			"Seed",
			Vector3.new(0.45, 0.45, 0.45),
			Vector3.new(x - 0.7 + (i % 3) * 0.7, 3.7, z - 2.6 + math.floor((i - 1) / 3) * 1.2),
			C.glow,
			Enum.Material.Neon,
			false,
			0,
			Enum.PartType.Ball
		)
	end
	for i, color in { C.glow, Color3.fromRGB(255, 140, 220), Color3.fromRGB(255, 210, 90) } do
		local jar = cyl(
			ctx,
			"Jar",
			1.1,
			0.8,
			Vector3.new(x - 0.6 + (i % 2) * 1.2, 3.4, z + 0.5 + i * 0.9),
			color,
			Enum.Material.Glass
		)
		jar.Transparency = 0.3
	end
end

local function lounge(ctx: Ctx, x: number, z: number)
	-- Rug with a gold border.
	part(ctx, "RugEdge", Vector3.new(12, 0.06, 16), Vector3.new(x, 0, z), C.rugGold, Enum.Material.Fabric).CastShadow =
		false
	part(ctx, "Rug", Vector3.new(10.6, 0.07, 14.6), Vector3.new(x, 0, z), C.rugRed, Enum.Material.Fabric).CastShadow =
		false
	-- Library bench against the wall, facing into the plot.
	local library = ServerStorage:FindFirstChild("AssetLibrary")
	local props = library and library:FindFirstChild("Props")
	local benchTemplate = props and props:FindFirstChild("Bench")
	if benchTemplate and benchTemplate:IsA("Model") then
		local bench = benchTemplate:Clone()
		bench:PivotTo(ctx.frame * CFrame.new(x + 3.5, ctx.top, z) * CFrame.Angles(0, math.rad(90), 0))
		for _, d in bench:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CollisionGroup = CollisionGroups.Decor
			end
		end
		bench.Parent = ctx.folder
	end
	-- Side table + glowing orb lamp, floor cushions.
	cyl(ctx, "TableTop", 0.3, 3.2, Vector3.new(x - 1, 2.2, z - 6), C.wood, Enum.Material.WoodPlanks, true)
	cyl(ctx, "TableLeg", 2.2, 0.5, Vector3.new(x - 1, 0, z - 6), C.woodDark, Enum.Material.Wood, true)
	part(
		ctx,
		"OrbLamp",
		Vector3.new(1, 1, 1),
		Vector3.new(x - 1, 2.5, z - 6),
		C.glow,
		Enum.Material.Neon,
		false,
		0,
		Enum.PartType.Ball
	)
	for _, dz in { -2.5, 2.5 } do
		cyl(ctx, "Cushion", 0.6, 2.4, Vector3.new(x - 3, 0.07, z + dz), C.cushion, Enum.Material.Fabric).CastShadow =
			false
	end
end

local function steppingPath(ctx: Ctx)
	-- Stepping stones from the gate to the pedestal grid (walk-through, decorative).
	local z = -41
	local i = 0
	while z < 5 do
		local stone = part(
			ctx,
			"PathStone",
			Vector3.new(4.2 - (i % 2) * 0.6, 0.12, 2.4),
			Vector3.new(if i % 2 == 0 then -0.4 else 0.4, 0, z),
			C.stone,
			Enum.Material.Slate,
			false,
			(i % 3 - 1) * 6
		)
		stone.CastShadow = false
		z += 3.4
		i += 1
	end
end

local function stageRug(ctx: Ctx)
	-- Light stone patio under the pedestal grid (3 rows x 4 slots), dark wood trim.
	local edge =
		part(ctx, "PatioTrim", Vector3.new(52, 0.08, 36), Vector3.new(0.5, 0, 23), C.woodDark, Enum.Material.Wood)
	edge.CastShadow = false
	local patio =
		part(ctx, "Patio", Vector3.new(50.4, 0.12, 34.4), Vector3.new(0.5, 0, 23), C.patio, Enum.Material.Slate)
	patio.CastShadow = false
end

local function libraryProp(ctx: Ctx, category: string, name: string, x: number, z: number, rotY: number)
	local library = ServerStorage:FindFirstChild("AssetLibrary")
	local folder = library and library:FindFirstChild(category)
	local template = folder and folder:FindFirstChild(name)
	if template and template:IsA("Model") then
		local model = template:Clone()
		model:PivotTo(ctx.frame * CFrame.new(x, ctx.top, z) * CFrame.Angles(0, math.rad(rotY), 0))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CollisionGroup = CollisionGroups.Decor
			elseif d:IsA("Light") then
				d:Destroy() -- perf: plot lanterns already light the floor
			end
		end
		model.Parent = ctx.folder
	end
end

local function fountain(ctx: Ctx, x: number, z: number)
	cyl(ctx, "FountainRim", 1.2, 8, Vector3.new(x, 0, z), C.stone, Enum.Material.Cobblestone, true)
	local water = cyl(ctx, "FountainWater", 0.1, 7, Vector3.new(x, 1.1, z), C.water, Enum.Material.Glass)
	water.Transparency = 0.25
	cyl(ctx, "FountainPillar", 2.6, 1.2, Vector3.new(x, 1.2, z), C.stone, Enum.Material.Cobblestone, true)
	cyl(ctx, "FountainBowl", 0.5, 3.2, Vector3.new(x, 3.8, z), C.stone, Enum.Material.Cobblestone, true)
	part(ctx, "FountainCore", Vector3.new(1.2, 1.2, 1.2), Vector3.new(x, 4.3, z), C.glow, Enum.Material.Neon, false, 45)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(C.water)
	spray.LightEmission = 0.4
	spray.Size = NumberSequence.new(0.25, 0.05)
	spray.Lifetime = NumberRange.new(0.8, 1.1)
	spray.Rate = 14
	spray.Speed = NumberRange.new(5, 7)
	spray.SpreadAngle = Vector2.new(18, 18)
	spray.Acceleration = Vector3.new(0, -18, 0)
	spray.Parent = ctx.folder:FindFirstChild("FountainCore", true) :: Instance
end

local function picnicTable(ctx: Ctx, x: number, z: number)
	part(ctx, "TableTop", Vector3.new(4, 0.35, 7), Vector3.new(x, 2.6, z), C.wood, Enum.Material.WoodPlanks, true)
	for _, dz in { -2.8, 2.8 } do
		part(
			ctx,
			"TableLeg",
			Vector3.new(3.2, 2.6, 0.4),
			Vector3.new(x, 0, z + dz),
			C.woodDark,
			Enum.Material.Wood,
			true
		)
	end
	for _, dx in { -3, 3 } do
		part(ctx, "Seat", Vector3.new(1.2, 0.3, 7), Vector3.new(x + dx, 1.5, z), C.wood, Enum.Material.WoodPlanks, true)
		for _, dz in { -2.8, 2.8 } do
			part(
				ctx,
				"SeatLeg",
				Vector3.new(0.4, 1.5, 0.4),
				Vector3.new(x + dx, 0, z + dz),
				C.woodDark,
				Enum.Material.Wood,
				true
			)
		end
	end
	cyl(ctx, "Basket", 0.8, 1.4, Vector3.new(x, 2.95, z + 1.5), Color3.fromRGB(200, 160, 90), Enum.Material.Fabric)
	part(
		ctx,
		"Fruit",
		Vector3.new(0.6, 0.6, 0.6),
		Vector3.new(x, 3.6, z + 1.5),
		Color3.fromRGB(230, 70, 70),
		Enum.Material.SmoothPlastic,
		false,
		0,
		Enum.PartType.Ball
	)
end

local function furnish(plot: Folder)
	local floor = plot:FindFirstChild("Floor")
	if not (floor and floor:IsA("BasePart")) then
		return 0
	end
	local old = plot:FindFirstChild(FOLDER)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	local ctx: Ctx = { folder = folder, frame = floor.CFrame, top = floor.Size.Y / 2 }

	stageRug(ctx)
	steppingPath(ctx)
	-- Left: the seed workshop.
	shelf(ctx, -42.6, 2, 8, false)
	workbench(ctx, -39, -10)
	barrel(ctx, -40.2, 12)
	barrel(ctx, -37.4, 14.2)
	crate(ctx, 3, -40, 0, -21, 8)
	crate(ctx, 2.4, -40, 3, -21, -12)
	crate(ctx, 2.6, -36.6, 0, -22.5, 20)
	pottedPlant(ctx, -40.5, 21)
	-- Right: the lounge.
	lounge(ctx, 37.5, -2)
	shelf(ctx, 42.6, 14, 8, true)
	pottedPlant(ctx, 40.5, -15)
	pottedPlant(ctx, 40.5, 22)
	-- Gate side and back wall planters.
	planter(ctx, -14, -41.4, 12, 0)
	planter(ctx, 14, -41.4, 12, 0)
	planter(ctx, 0, 41.8, 54, 0)
	-- Front half: fountain + picnic table either side of the path, garden bushes.
	fountain(ctx, 22, -10)
	picnicTable(ctx, -22, -9)
	libraryProp(ctx, "Bushes", "Bush_03", -21, -33, 0)
	libraryProp(ctx, "Bushes", "Bush_03", 21, -33, 140)
	-- Front corners.
	libraryProp(ctx, "Props", "Mushrooms", -38, -37, 30)
	libraryProp(ctx, "Rocks", "Rock_04", 38.5, -37.5, 0)
	pottedPlant(ctx, 35, -40)

	folder.Parent = plot
	return #folder:GetDescendants()
end

function FurnitureBuilder.build(): string
	CollisionGroups.ensure()
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if not plots then
		return "[FurnitureBuilder] no AnomalyGrove.Plots - run MapBuilder first"
	end
	local total, count = 0, 0
	for _, plot in plots:GetChildren() do
		if plot:IsA("Folder") then
			total += furnish(plot)
			count += 1
		end
	end
	return `[FurnitureBuilder] furnished {count} plots ({total} instances)`
end

return FurnitureBuilder
