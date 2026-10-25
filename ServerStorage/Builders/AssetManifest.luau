--!strict
-- Every free Creator Store asset the world uses (M5-01). AssetLibraryBuilder loads
-- these by ID in Edit mode into ServerStorage.AssetLibrary/<category>/<name>, strips
-- all scripts, and normalizes them; world builders only ever clone from there.
-- Keep docs/ASSETS.md in sync when adding an entry.

export type Entry = {
	assetId: number,
	category: string, -- AssetLibrary sub-folder
	-- What to take from the loaded asset:
	--   picks = { [libraryName] = descendantName }  -> named descendants
	--   eachPart = prefix                            -> every BasePart becomes <prefix>_<n>
	--   whole = libraryName                          -> the whole loaded root
	picks: { [string]: string }?,
	eachPart: string?,
	whole: string?,
	scale: number?, -- Model:ScaleTo after normalizing
	collide: boolean?, -- default false: decoration never blocks players or monsters
	source: string, -- human-readable credit for docs/ASSETS.md
}

local function range(prefix: string, from: number, to: number): { [string]: string }
	local picks = {}
	for i = from, to do
		local name = string.format("%s_%02d", prefix, i)
		picks[name] = name
	end
	return picks
end

local yasuTrees = range("Tree", 1, 19)

local AssetManifest: { Entry } = {
	{
		assetId = 79689531752352,
		category = "Trees",
		picks = yasuTrees,
		collide = true, -- trunks block (canopies are forced non-colliding)
		source = "Yasu's Stylized Tree Pack (mvyasu), free",
	},
	{
		assetId = 79689531752352,
		category = "Landmarks",
		picks = { GiantTree = "Tree_20" },
		collide = true,
		source = "Yasu's Stylized Tree Pack (mvyasu), free",
	},
	{
		assetId = 79689531752352,
		category = "Bushes",
		picks = range("Bush", 1, 3),
		source = "Yasu's Stylized Tree Pack (mvyasu), free",
	},
	{
		assetId = 2128776869,
		category = "Rocks",
		eachPart = "Rock",
		collide = true,
		source = "Low Poly Rock Pack [FREE] (FracturedSkies)",
	},
	{
		assetId = 4644085527,
		category = "Props",
		whole = "Mushrooms",
		scale = 1.4,
		source = "Low Poly Mushrooms (CyrilTBFD), free",
	},
	{
		assetId = 11312714034,
		category = "Props",
		whole = "Log",
		collide = true,
		source = "Low Poly Log (osddxx), free",
	},
	{
		assetId = 15147571772,
		category = "Props",
		whole = "MarketStall",
		scale = 1.3,
		collide = true,
		source = "market stall (Quantaily), free",
	},
	{
		assetId = 84518243975474,
		category = "Props",
		whole = "Bench",
		collide = true,
		source = "Free Low Poly Wooden Bench Stylized (Ramonzinhuh)",
	},
	{
		assetId = 285454336,
		category = "Props",
		whole = "Lantern",
		scale = 3,
		source = "Dynamically Lit Lantern (EndorsedModel), free",
	},
	{
		assetId = 139945645606198,
		category = "Monsters",
		whole = "Fogling",
		scale = 1.15,
		source = "AI-generated mesh (Roblox generate_mesh, M5-08), published to the owner's account",
	},
	{
		assetId = 84743741590314,
		category = "Monsters",
		whole = "Stalker",
		scale = 1.7,
		source = "AI-generated mesh (Roblox generate_mesh, M5-08), published to the owner's account",
	},
	-- 2026-10-18 monster variety pass (generate_mesh, published to the owner's account).
	{
		assetId = 107656745575725,
		category = "Monsters",
		whole = "Wisp",
		source = "AI-generated mesh (generate_mesh, 2026-10-18): seed-stealing forest wisp",
	},
	{
		assetId = 138148830066144,
		category = "Monsters",
		whole = "Golem",
		scale = 1.5,
		source = "AI-generated mesh (generate_mesh, 2026-10-18): Moss Golem",
	},
	{
		assetId = 105803933146803,
		category = "Monsters",
		whole = "Spitter",
		scale = 1.15,
		source = "AI-generated mesh (generate_mesh, 2026-10-18): Mire Spitter mushroom creature",
	},
	{
		assetId = 14665403907,
		category = "Skies",
		whole = "DaySky",
		source = "Hilly Green Stylized Mountains SkyBox (Callme_jj), free",
	},
	{
		assetId = 125829675338379,
		category = "Skies",
		whole = "NightSky",
		source = "Classic Night Skybox Stars (Chr1st1an302AlphaDaw), free",
	},
}

return AssetManifest
