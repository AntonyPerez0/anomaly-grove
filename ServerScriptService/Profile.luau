--!strict
-- Schema-versioned player profile (GDD section 7). Pure logic: default schema,
-- default-merge for partial data, and stepwise migrations. DataService (M2-02)
-- owns DataStore I/O and calls in here.

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Profile = {}

local SCHEMA_VERSION: number = 4 -- v4 (M8): skills, tokens, tree, upgrades, pass, pedestal levels/crates

-- The current default profile (GDD section 7).
function Profile.newDefault(): Types.Profile
	return {
		schemaVersion = SCHEMA_VERSION,
		plotIndex = nil,
		cash = 0,
		pedestals = {
			{
				rarity = nil,
				mutation = nil,
				hatchAt = nil,
				tickFrac = 0,
				completedCycles = 0,
				vaultLocked = false,
				mutationProgress = 0,
				mutationBoost = false,
				level = 1,
				crate = nil,
			},
		},
		defenses = {},
		gadgets = {},
		rebirths = 0,
		indexDiscovered = {},
		coresStolen = 0,
		nightStreak = 0,
		tutorial = {
			claimed = false,
			harvested = false,
			placed = false,
			stealHint = false,
		},
		lastSeen = os.time(),
		quests = { day = -1, list = {} }, -- day -1 = roll on first load
		daily = { lastClaimDay = -1, streak = 0 },
		milestones = {},
		skills = {},
		tokens = 0,
		tree = {},
		upgrades = {},
		pass = { season = 0, xp = 0, claimed = {} },
		cape = nil,
	}
end

local function isProfileLike(raw: any): boolean
	return type(raw) == "table"
end

-- Merge a (possibly partial or foreign) table into a valid v1 profile.
local function mergeV1(raw: { [string]: any }): Types.Profile
	local profile = Profile.newDefault()
	if type(raw.cash) == "number" and raw.cash >= 0 then
		profile.cash = math.floor(raw.cash)
	end
	if raw.plotIndex == nil or (type(raw.plotIndex) == "number" and raw.plotIndex >= 0 and raw.plotIndex <= 7) then
		profile.plotIndex = raw.plotIndex :: number?
	end
	if type(raw.pedestals) == "table" then
		local pedestals: { Types.PedestalState } = {}
		for _, p in raw.pedestals :: { any } do
			if type(p) == "table" then
				table.insert(pedestals, {
					rarity = p.rarity,
					mutation = p.mutation,
					hatchAt = if type(p.hatchAt) == "number" then p.hatchAt else nil,
					tickFrac = if type(p.tickFrac) == "number" then p.tickFrac else 0,
					completedCycles = if type(p.completedCycles) == "number" then p.completedCycles else 0,
					vaultLocked = p.vaultLocked == true,
					mutationProgress = if type(p.mutationProgress) == "number" then p.mutationProgress else 0,
					mutationBoost = p.mutationBoost == true,
					level = if type(p.level) == "number" then math.clamp(math.floor(p.level), 1, 1000) else 1,
					crate = if type(p.crate) == "string" then p.crate else nil,
					size = if type(p.size) == "string" and (Config.Sizes.Defs :: any)[p.size] then p.size else nil,
				})
				-- Incubating seeds carry their remaining seconds through the merge (FIX M8:
				-- this field used to be dropped here, so seeds growing at logout vanished).
				if type(p.incubateRemaining) == "number" then
					(pedestals[#pedestals] :: any).incubateRemaining = p.incubateRemaining
				end
			end
		end
		if #pedestals > 0 then
			profile.pedestals = pedestals
		end
	end
	if type(raw.defenses) == "table" then
		-- Keep only well-formed defense entries; corrupt ones are dropped.
		local defenses: { { kind: Types.DefenseKind, slot: number } } = {}
		for _, d in raw.defenses :: { any } do
			if
				type(d) == "table"
				and (d.kind == "Turret" or d.kind == "LaserDoor" or d.kind == "TrapTile")
				and type(d.slot) == "number"
				and (d.slot :: number) >= 1
				and (d.slot :: number) <= 32
			then
				table.insert(defenses, { kind = d.kind :: Types.DefenseKind, slot = math.floor(d.slot :: number) })
			end
		end
		profile.defenses = defenses
	end
	if type(raw.gadgets) == "table" then
		-- Known gadget names only (a corrupt entry must never grant anything).
		local gadgets: { Types.Gadget } = {}
		for _, g in raw.gadgets :: { any } do
			if g == "DashBoots" or g == "SmokeBomb" or g == "Grapple" or g == "Lantern" then
				table.insert(gadgets, g :: Types.Gadget)
			end
		end
		profile.gadgets = gadgets
	end
	if type(raw.rebirths) == "number" and raw.rebirths >= 0 then
		profile.rebirths = math.floor(raw.rebirths)
	end
	if type(raw.indexDiscovered) == "table" then
		profile.indexDiscovered = raw.indexDiscovered :: { [string]: boolean }
	end
	if type(raw.coresStolen) == "number" and raw.coresStolen >= 0 then
		profile.coresStolen = math.floor(raw.coresStolen)
	end
	if type(raw.nightStreak) == "number" and raw.nightStreak >= 0 then
		profile.nightStreak = math.floor(raw.nightStreak)
	end
	if type(raw.tutorial) == "table" then
		profile.tutorial = {
			claimed = raw.tutorial.claimed == true,
			harvested = raw.tutorial.harvested == true,
			placed = raw.tutorial.placed == true,
			stealHint = raw.tutorial.stealHint == true,
		}
	end
	if type(raw.lastSeen) == "number" then
		profile.lastSeen = math.floor(raw.lastSeen)
	end
	-- v2 fields: keep only well-formed quest rows / daily streak.
	if type(raw.quests) == "table" and type(raw.quests.day) == "number" and type(raw.quests.list) == "table" then
		local list: { Types.Quest } = {}
		for _, q in raw.quests.list :: { any } do
			if
				type(q) == "table"
				and type(q.id) == "string"
				and type(q.goal) == "number"
				and type(q.progress) == "number"
			then
				table.insert(list, {
					id = q.id,
					goal = math.max(1, math.floor(q.goal)),
					progress = math.max(0, q.progress),
					claimed = q.claimed == true,
				})
			end
		end
		profile.quests = { day = math.floor(raw.quests.day), list = list }
	end
	if
		type(raw.daily) == "table"
		and type(raw.daily.lastClaimDay) == "number"
		and type(raw.daily.streak) == "number"
	then
		profile.daily = {
			lastClaimDay = math.floor(raw.daily.lastClaimDay),
			streak = math.clamp(math.floor(raw.daily.streak), 0, 1e6),
		}
	end
	-- v3: claimed milestone ids (booleans only; unknown ids are harmless).
	if type(raw.milestones) == "table" then
		local milestones: { [string]: boolean } = {}
		for id, claimed in raw.milestones :: { [any]: any } do
			if type(id) == "string" and claimed == true then
				milestones[id] = true
			end
		end
		profile.milestones = milestones
	end
	-- v4 (M8): numeric maps are copied key by key; anything malformed is dropped.
	local function numberMap(source: any, maxValue: number): { [string]: number }
		local out: { [string]: number } = {}
		if type(source) == "table" then
			for key, value in source :: { [any]: any } do
				if type(key) == "string" and type(value) == "number" and value == value and value >= 0 then
					out[key] = math.min(value, maxValue)
				end
			end
		end
		return out
	end
	profile.skills = numberMap(raw.skills, 2e9)
	profile.tree = numberMap(raw.tree, 100)
	profile.upgrades = numberMap(raw.upgrades, 1000)
	if type(raw.tokens) == "number" and raw.tokens >= 0 then
		profile.tokens = math.floor(raw.tokens)
	end
	if type(raw.pass) == "table" and type(raw.pass.season) == "number" and type(raw.pass.xp) == "number" then
		local claimed: { [string]: boolean } = {}
		if type(raw.pass.claimed) == "table" then
			for key, value in raw.pass.claimed :: { [any]: any } do
				if type(key) == "string" and value == true then
					claimed[key] = true
				end
			end
		end
		profile.pass = { season = math.floor(raw.pass.season), xp = math.max(0, raw.pass.xp), claimed = claimed }
	end
	if type(raw.codes) == "table" then
		local codes: { [string]: boolean } = {}
		for key, value in raw.codes :: { [any]: any } do
			if type(key) == "string" and value == true and #key <= 32 then
				codes[key] = true
			end
		end
		profile.codes = codes -- M9-10
	end
	if type(raw.companion) == "string" then
		profile.companion = raw.companion -- M9-07 (validated against Config on use)
	end
	if type(raw.cape) == "string" then
		profile.cape = raw.cape
	end
	return profile
end

-- Stepwise migrations from any historical version to the current one.
local MIGRATIONS: { [number]: (raw: { [string]: any }) -> { [string]: any } } = {
	-- v0 -> v1: pre-schema saves had no version marker and possibly missing fields.
	[0] = function(raw)
		raw.schemaVersion = 1
		return raw
	end,
	-- v1 -> v2 (M6): add daily quests + login streak (fresh; first load rolls quests).
	[1] = function(raw)
		raw.quests = { day = -1, list = {} }
		raw.daily = { lastClaimDay = -1, streak = 0 }
		raw.schemaVersion = 2
		return raw
	end,
	-- v2 -> v3 (M7): milestone badges start empty.
	[2] = function(raw)
		raw.milestones = {}
		raw.schemaVersion = 3
		return raw
	end,
	-- v3 -> v4 (M8): progression fields start empty (merge fills defaults;
	-- existing pedestals become level 1, nothing a player owns is touched).
	[3] = function(raw)
		raw.schemaVersion = 4
		return raw
	end,
}

-- Normalize any deserialized payload into a current-schema profile.
-- Unknown/corrupt payloads fall back to a fresh default (never lose the player).
function Profile.migrate(raw: any): Types.Profile
	if not isProfileLike(raw) then
		return Profile.newDefault()
	end
	local data = raw :: { [string]: any }
	local version = data.schemaVersion
	if type(version) ~= "number" then
		version = 0 -- pre-schema data
	end
	while version < SCHEMA_VERSION do
		local migrate = MIGRATIONS[version]
		if not migrate then
			break -- unknown gap: stop and merge below
		end
		local ok, result = pcall(migrate, data)
		if not ok then
			break
		end
		data = result
		version = data.schemaVersion
		if type(version) ~= "number" then
			break
		end
	end
	-- Even at the current version, merge defaults over partial payloads.
	return mergeV1(data)
end

function Profile.currentVersion(): number
	return SCHEMA_VERSION
end

return Profile
