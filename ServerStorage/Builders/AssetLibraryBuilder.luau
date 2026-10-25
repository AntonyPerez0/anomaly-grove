--!strict
-- Builds ServerStorage.AssetLibrary from AssetManifest (M5-01). Edit mode only:
--   require(game.ServerStorage.Builders.AssetLibraryBuilder).build()
-- Free Creator Store models cannot be loaded by ID at runtime, so they are loaded
-- here once and saved with the place; world builders clone from the library.
-- Idempotent: wipes the library and rebuilds it from the manifest.

local ServerStorage = game:GetService("ServerStorage")
local AssetManifest = require(script.Parent.AssetManifest)

local AssetLibraryBuilder = {}

local LIBRARY_NAME = "AssetLibrary"
-- Leaf / canopy meshes never collide, even on colliding entries (trees keep trunks solid).
local SOFT_PART_PATTERNS = { "canopy", "leaves", "leaf", "foliage" }

-- AGENTS.md section 9: never keep scripts from a free model.
local function stripScripts(root: Instance): number
	local removed = 0
	for _, d in root:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
			removed += 1
		end
	end
	return removed
end

local function isSoft(part: BasePart): boolean
	local lower = string.lower(part.Name)
	for _, pattern in SOFT_PART_PATTERNS do
		if string.find(lower, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Anchor everything, set collision, and put the pivot at the bottom-center at the origin.
local function normalize(model: Model, collide: boolean, scale: number?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanCollide = collide and not isSoft(d)
			d.CanQuery = d.CanCollide
		end
	end
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
	model:PivotTo(CFrame.new())
end

local function asModel(instance: Instance, name: string): Model?
	if instance:IsA("Model") then
		instance.Name = name
		return instance
	elseif instance:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = name
		instance.Parent = model
		model.PrimaryPart = instance
		return model
	elseif instance:IsA("Folder") then
		local model = Instance.new("Model")
		model.Name = name
		for _, child in instance:GetChildren() do
			child.Parent = model
		end
		return model
	end
	return nil
end

local loadCache: { [number]: Instance } = {}

local function load(assetId: number): Instance?
	if loadCache[assetId] then
		return loadCache[assetId]
	end
	local ok, objects = pcall(function()
		return (game :: any):GetObjects(`rbxassetid://{assetId}`)
	end)
	if not ok or type(objects) ~= "table" or #objects == 0 then
		warn(`[AssetLibrary] could not load {assetId}: {objects}`)
		return nil
	end
	local root = objects[1]
	stripScripts(root)
	loadCache[assetId] = root
	return root
end

function AssetLibraryBuilder.build(): string
	local old = ServerStorage:FindFirstChild(LIBRARY_NAME)
	if old then
		old:Destroy()
	end
	table.clear(loadCache)
	local library = Instance.new("Folder")
	library.Name = LIBRARY_NAME

	local count, missing = 0, 0
	local function categoryFolder(name: string): Folder
		local existing = library:FindFirstChild(name)
		if existing and existing:IsA("Folder") then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = library
		return folder
	end

	for _, entry in AssetManifest do
		local root = load(entry.assetId)
		if not root then
			missing += 1
			continue
		end
		local folder = categoryFolder(entry.category)
		local collide = entry.collide == true

		local function add(source: Instance, name: string)
			local copy = source:Clone()
			stripScripts(copy)
			if copy:IsA("Sky") then
				copy.Name = name
				copy.Parent = folder
				count += 1
				return
			end
			local model = asModel(copy, name)
			if not model then
				warn(`[AssetLibrary] {name}: unsupported class {copy.ClassName}`)
				missing += 1
				return
			end
			normalize(model, collide, entry.scale)
			model.Parent = folder
			count += 1
		end

		if entry.picks then
			for libraryName, descendantName in entry.picks do
				local found = root:FindFirstChild(descendantName, true)
				if found then
					add(found, libraryName)
				else
					warn(`[AssetLibrary] {entry.assetId} has no '{descendantName}'`)
					missing += 1
				end
			end
		elseif entry.eachPart then
			local n = 0
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
					add(d, string.format("%s_%02d", entry.eachPart, n))
				end
			end
		elseif entry.whole then
			add(root, entry.whole)
		end
	end

	library.Parent = ServerStorage
	return `[AssetLibrary] built {count} assets ({missing} missing)`
end

-- Clone a library asset (errors loudly if the library was never built).
function AssetLibraryBuilder.get(category: string, name: string): Instance
	local library = ServerStorage:FindFirstChild(LIBRARY_NAME)
	local folder = library and library:FindFirstChild(category)
	local asset = folder and folder:FindFirstChild(name)
	assert(asset, `[AssetLibrary] missing {category}/{name} - run AssetLibraryBuilder.build() in Edit mode`)
	return asset:Clone()
end

-- Names in a category, sorted (deterministic for seeded placement).
function AssetLibraryBuilder.list(category: string): { string }
	local library = ServerStorage:FindFirstChild(LIBRARY_NAME)
	local folder = library and library:FindFirstChild(category)
	local names = {}
	if folder then
		for _, child in folder:GetChildren() do
			table.insert(names, child.Name)
		end
	end
	table.sort(names)
	return names
end

return AssetLibraryBuilder
