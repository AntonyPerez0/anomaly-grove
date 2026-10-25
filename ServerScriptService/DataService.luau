--!strict
-- DataStore persistence (M2-02): load on join (with migration), save on demand,
-- on leave and on shutdown; falls back to in-memory with ONE clear warning when
-- DataStores are unavailable (Studio without API access).
--
-- Session locking (2026-10-18, game went public): the profile carries
-- `_lock = { job, at }`. A server only loads a profile that is unlocked, locked by
-- itself, or whose lock is stale (LOCK_TTL; autosave refreshes it every 60 s), and
-- only saves while it still owns the lock. Leaving / shutdown releases it. So a
-- player who hops servers can never be loaded from (or overwritten by) a save the
-- old server has not finished, and a profile is never saved before it loaded.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Profile = require(script.Parent.Profile)
local QuestService = require(script.Parent.QuestService)
local DailyRewardService = require(script.Parent.DailyRewardService)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local CoreSystem = require(script.Parent.CoreSystem)
local PedestalBuilder = require(game.ServerStorage.Builders.PedestalBuilder)
local DefenseSystem = require(script.Parent.DefenseSystem)
local CollectionIndex = require(script.Parent.CollectionIndex)
local OfflineGrowth = require(script.Parent.OfflineGrowth)
local SkillService = require(script.Parent.SkillService)
local PassService = require(script.Parent.PassService)

local DataService = {}

-- Optional hook run when a player leaves, before the final save (Main wires it).
DataService.onLeaving = nil :: ((Player) -> ())?

local STORE_NAME = "AnomalyGroveProfiles"
local AUTO_SAVE_SECONDS = 60
local MAX_SAVE_ATTEMPTS = 3
local LOCK_TTL = 150 -- seconds; > 2 autosaves, so a live server never looks stale
local LOAD_RETRY_SECONDS = 4
local LOAD_MAX_WAIT = 40 -- then the lock is treated as abandoned... unless fresh: kick

-- This server's lock id (game.JobId is "" in Studio).
local JOB_ID = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

-- Players whose profile finished loading here (only those may be saved).
local loaded: { [Player]: boolean? } = {}

-- Pure: may server `job` load a profile whose current value is `old` at `now`?
function DataService.canTakeLock(old: any, job: string, now: number): boolean
	local lock = type(old) == "table" and old._lock or nil
	if type(lock) ~= "table" or lock.job == job then
		return true
	end
	return type(lock.at) ~= "number" or now - lock.at > LOCK_TTL
end

-- Pure: the value a save writes (nil = abort, another server owns the lock).
function DataService.saveValue(old: any, payload: { [string]: any }, job: string, now: number, release: boolean): any
	local lock = type(old) == "table" and old._lock or nil
	if type(lock) == "table" and lock.job ~= job then
		return nil
	end
	local value = table.clone(payload)
	value._lock = if release then nil else { job = job, at = now }
	return value
end

-- Test hook: mark a stub player as loaded so save() will write it.
function DataService.setLoadedForTests(player: Player, on: boolean)
	loaded[player] = if on then true else nil
end

local store: DataStore? = nil
local fallbackMode = false
local warned = false

local stateKey = function(player: Player): string
	return `Player_{player.UserId}`
end

-- Save-safety counters (M4-03): retries and failures are counted and logged so
-- a flaky DataStore day is visible in the console instead of silently losing data.
local saveStats = { attempts = 0, failures = 0, sessions = 0 }

-- Test hook (M4-03): specs inject a fake store to drive the retry path without
-- touching real DataStores.
function DataService.setStoreForTests(fake: DataStore?)
	store = fake
	fallbackMode = if fake then false else fallbackMode
end

-- Serialize live state into a storable profile table (schema v1).
function DataService.serialize(state: Types.PlayerState): { [string]: any }
	local pedestals: { any } = {}
	for _, pedestal in state.pedestals do
		table.insert(pedestals, {
			rarity = pedestal.rarity,
			mutation = pedestal.mutation,
			-- Incubating seeds keep their remaining seconds (session clock is not storable).
			incubateRemaining = if pedestal.hatchAt ~= nil
				then math.max(0, (pedestal.hatchAt :: number) - os.clock())
				else nil,
			tickFrac = pedestal.tickFrac,
			completedCycles = pedestal.completedCycles,
			vaultLocked = pedestal.vaultLocked,
			mutationProgress = pedestal.mutationProgress,
			mutationBoost = pedestal.mutationBoost == true,
			level = pedestal.level or 1,
			crate = pedestal.crate,
			size = pedestal.size,
		})
	end
	local defenses: { any } = {}
	for _, defense in state.defenses do
		table.insert(defenses, { kind = defense.kind, slot = defense.slot })
	end
	-- Owned gadgets (FIX M6-02 session: these were never saved before).
	local gadgets: { string } = {}
	for name, owned in state.gadgets do
		if owned then
			table.insert(gadgets, name :: string)
		end
	end
	table.sort(gadgets)
	local quests = state.quests
	local daily = state.daily
	return {
		schemaVersion = Profile.currentVersion(),
		plotIndex = state.plotIndex,
		cash = math.floor(state.cash),
		pedestals = pedestals,
		defenses = defenses,
		gadgets = gadgets,
		quests = if quests then { day = quests.day, list = quests.list } else { day = -1, list = {} },
		daily = if daily
			then { lastClaimDay = daily.lastClaimDay, streak = daily.streak }
			else { lastClaimDay = -1, streak = 0 },
		rebirths = state.rebirths,
		indexDiscovered = state.indexDiscovered,
		coresStolen = state.coresStolen,
		nightStreak = state.nightStreak,
		milestones = state.milestones,
		skills = state.skills,
		tokens = state.tokens,
		tree = state.tree,
		upgrades = state.upgrades,
		pass = state.pass,
		cape = state.cape,
		companion = state.companion,
		codes = state.codes,
		tutorial = {
			claimed = state.tutorial.claimed == true,
			harvested = state.tutorial.harvested == true,
			placed = state.tutorial.placed == true,
			stealHint = state.tutorial.stealHint == true,
		},
		lastSeen = os.time(),
	}
end

-- Push a loaded profile into the live state (and restore the plot + core visuals).
local function applyProfile(player: Player, profile: Types.Profile)
	local state = PlayerState.get(player)
	state.cash = profile.cash
	player:SetAttribute("Cash", state.cash)
	state.pedestals = {}
	for _, pedestal in profile.pedestals do
		table.insert(state.pedestals, {
			rarity = pedestal.rarity,
			mutation = pedestal.mutation,
			-- Incubating seeds resume with their remaining time (FIX M8: the remaining
			-- seconds used to be read from this fresh copy, which never had them).
			hatchAt = if type((pedestal :: any).incubateRemaining) == "number"
				then os.clock() + math.max(0, (pedestal :: any).incubateRemaining)
				else nil,
			tickFrac = pedestal.tickFrac,
			completedCycles = pedestal.completedCycles,
			vaultLocked = pedestal.vaultLocked,
			mutationProgress = pedestal.mutationProgress,
			mutationBoost = pedestal.mutationBoost == true,
			level = pedestal.level or 1,
			crate = pedestal.crate,
			size = pedestal.size,
		})
	end
	-- Purchased defenses (M3-02): validated entries only; the restore loop below
	-- respawns their models once the plot is re-claimed.
	state.defenses = {}
	for _, defense in profile.defenses do
		if type(defense) == "table" and type(defense.kind) == "string" and type(defense.slot) == "number" then
			table.insert(state.defenses, { kind = defense.kind :: Types.DefenseKind, slot = math.floor(defense.slot) })
		end
	end
	-- Owned gadgets come back with their HUD/touch-pad ownership attributes.
	state.gadgets = {}
	for _, gadget in profile.gadgets do
		if gadget == "DashBoots" or gadget == "SmokeBomb" or gadget == "Grapple" or gadget == "Lantern" then
			state.gadgets[gadget :: Types.Gadget] = true
			player:SetAttribute(`Gadget_{gadget}`, "owned")
		end
	end
	state.quests = profile.quests
	state.daily = profile.daily
	state.milestones = profile.milestones
	state.skills = profile.skills
	state.tokens = profile.tokens
	state.tree = profile.tree
	state.upgrades = profile.upgrades
	state.pass = profile.pass
	state.cape = profile.cape
	state.companion = profile.companion
	state.codes = profile.codes or {}
	player:SetAttribute("Companion", profile.companion)
	state.rebirths = profile.rebirths
	state.indexDiscovered = profile.indexDiscovered
	state.tutorial = {
		claimed = profile.tutorial.claimed == true,
		harvested = profile.tutorial.harvested == true,
		placed = profile.tutorial.placed == true,
		stealHint = profile.tutorial.stealHint == true,
	}
	state.coresStolen = profile.coresStolen
	player:SetAttribute("CoresStolen", state.coresStolen)
	state.nightStreak = profile.nightStreak
	player:SetAttribute("NightStreak", state.nightStreak)
	-- Re-assign the plot if it is still free, then restore core visuals.
	if profile.plotIndex ~= nil then
		local plot = PlotSystem.plots()[(profile.plotIndex :: number) + 1]
		if plot and plot.owner == nil then
			PlotSystem.claim(player, profile.plotIndex :: number)
			-- Spawn the purchased pedestal models (slots 2..N), defenses, then cores.
			for slot = 2, #state.pedestals do
				PedestalBuilder.buildForPlot(profile.plotIndex :: number, slot)
			end
			for _, defense in state.defenses do
				DefenseSystem.spawnDefense(profile.plotIndex :: number, defense.kind, defense.slot)
			end
			for slot, pedestal in state.pedestals do
				if pedestal.rarity ~= nil then
					CoreSystem.setPedestalCore(
						profile.plotIndex :: number,
						slot,
						pedestal.rarity :: Types.Rarity,
						pedestal.mutation,
						pedestal.level,
						pedestal.size
					)
				elseif pedestal.hatchAt ~= nil then
					-- Seeds / crates still incubating come back visibly (M8 fix).
					CoreSystem.setPedestalSeed(
						profile.plotIndex :: number,
						slot,
						pedestal.mutationBoost == true,
						pedestal.crate
					)
				end
				if pedestal.vaultLocked then
					PedestalBuilder.setVaultLockVisual(profile.plotIndex :: number, slot, true)
				end
			end
		end
	end
	player:SetAttribute("PedestalSlots", #state.pedestals)
	-- Initial pedestal summary (the 1 Hz CoreSystem loop refreshes it).
	local summaryParts: { string } = {}
	for slot, pedestal in state.pedestals do
		local entry: string = if pedestal.rarity ~= nil then pedestal.rarity :: string else "empty"
		if pedestal.mutation ~= nil then
			entry = `{entry}+{pedestal.mutation}`
		end
		if pedestal.size ~= nil and pedestal.rarity ~= nil then
			entry = `{entry}~{pedestal.size}`
		end
		table.insert(summaryParts, `{slot}={entry}`)
	end
	player:SetAttribute("PedestalSummary", table.concat(summaryParts, "|"))
	CollectionIndex.backfill(state) -- cores you own always count as discovered
	CollectionIndex.syncAttribute(player, state)
	QuestService.publishNow(player)
	DailyRewardService.publishNow(player)
	-- M8: skills / perks / tree / tokens mirrors, the Grove Pass, the worn cape.
	PassService.onProfileLoaded(player, state)
	SkillService.publish(player, state)
	SkillService.refreshCape(player, state)
	print(`[DataService] loaded profile for {player.Name} (cash {state.cash})`)
	-- Offline growth runs against the loaded lastSeen (GDD 5.5).
	OfflineGrowth.applyToState(player, profile.lastSeen)
end

-- Save one player with bounded retries. Returns "committed" | "fallback" |
-- "error" | "not-loaded" | "lock-lost". `release` drops the session lock (leave).
function DataService.save(player: Player, release: boolean?): string
	local state = PlayerState.peek(player)
	if not state then
		return "no-state"
	end
	if fallbackMode or store == nil then
		print(`[DataService] manual save (in-memory): {player.Name} cash={math.floor(state.cash)}`)
		return "fallback"
	end
	if not loaded[player] then
		-- Never write a profile that did not load: it would wipe the real save.
		print(`[DataService] skip save for {player.Name}: profile not loaded on this server`)
		return "not-loaded"
	end
	local payload = DataService.serialize(state)
	print(
		`[DataService] save payload: cash={payload.cash} defenses={#payload.defenses} pedestals={#payload.pedestals} plotIndex={tostring(
			payload.plotIndex
		)}`
	)
	local attempts = 0
	saveStats.sessions += 1
	while attempts < MAX_SAVE_ATTEMPTS do
		attempts += 1
		saveStats.attempts += 1
		local lockLost = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(stateKey(player), function(old)
				-- Pure transform: no yielding, no side effects (may run more than once).
				local value = DataService.saveValue(old, payload, JOB_ID, os.time(), release == true)
				lockLost = value == nil
				return value
			end)
		end)
		if ok and lockLost then
			warn(`[DataService] {player.Name}: another server owns this profile now - save skipped`)
			loaded[player] = nil
			return "lock-lost"
		end
		if ok then
			print(
				`[DataService] saved {player.Name} (cash {math.floor(state.cash)}, attempt {attempts})`
					.. ` | session totals: attempts={saveStats.attempts} failures={saveStats.failures}`
			)
			return "committed"
		end
		saveStats.failures += 1
		warn(`[DataService] save failed for {player.Name} (attempt {attempts}): {err}`)
		task.wait(attempts) -- bounded backoff
	end
	print(
		`[DataService] save summary: {player.Name} gave up after {attempts} attempts ({saveStats.failures} lifetime failures)`
	)
	return "error"
end

-- Load with the session lock: retry while another server holds a fresh lock.
-- Returns ("ok", data) | ("locked", nil) | ("error", err). `data` is nil for a
-- brand-new player.
local function acquire(player: Player): (string, any)
	local started = os.clock()
	while player.Parent do
		local taken, isNew = false, false
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(stateKey(player), function(old)
				taken = DataService.canTakeLock(old, JOB_ID, os.time())
				if not taken then
					return nil -- cancel: keep waiting for the other server
				end
				isNew = type(old) ~= "table"
				local value: { [string]: any } = if isNew then {} else table.clone(old)
				value._lock = { job = JOB_ID, at = os.time() }
				return value
			end)
		end)
		if not ok then
			return "error", result
		end
		if taken then
			return "ok", if isNew then nil else result
		end
		if os.clock() - started > LOAD_MAX_WAIT then
			return "locked", nil
		end
		print(`[DataService] {player.Name}: profile still open on another server, waiting...`)
		task.wait(LOAD_RETRY_SECONDS)
	end
	return "left", nil
end

-- Right-to-erasure (Roblox privacy requests): delete a user's saved profile.
-- Run from a Studio playtest: DebugCommand "data:erase" {userId}. See
-- docs/LAUNCH_CHECKLIST.md "Data deletion requests".
function DataService.eraseUserId(userId: number): boolean
	if store == nil then
		return false
	end
	local ok, err = pcall(function()
		(store :: DataStore):RemoveAsync(`Player_{userId}`)
	end)
	if not ok then
		warn(`[DataService] erase {userId} failed: {err}`)
	end
	return ok
end

function DataService.init()
	-- Probe DataStore availability once; a single clear warning if unavailable.
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result :: DataStore
	else
		fallbackMode = true
		if not warned then
			warned = true
			warn("[DataService] DataStores unavailable - running in-memory only (enable Studio API access to persist)")
		end
	end

	local function hookPlayer(player: Player)
		task.spawn(function()
			local probeOk = fallbackMode
			if not fallbackMode and store ~= nil then
				local outcome, data = acquire(player)
				if outcome == "ok" then
					local profile = Profile.migrate(data)
					applyProfile(player, profile)
					loaded[player] = true
					player:SetAttribute("ProfileLoaded", true)
					probeOk = true
				elseif outcome == "locked" then
					warn(`[DataService] {player.Name}: profile locked by another server - kicking to protect it`)
					player:Kick("Your progress is still saving from your last server. Please rejoin in a minute!")
				elseif outcome == "error" then
					-- Do NOT drop the whole server to in-memory (that was M2 behaviour,
					-- fine in Studio, dangerous live): this player just cannot be saved.
					warn(`[DataService] load failed for {player.Name}: {data}`)
					player:Kick("We couldn't load your save right now (Roblox data service). Please rejoin!")
				end
			end
			if probeOk and fallbackMode then
				-- Ensure the player still gets a state even in fallback mode.
				PlayerState.get(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	Players.PlayerRemoving:Connect(function(player)
		-- Order matters: PlayerRemoving handlers fire in REVERSE connection order,
		-- and this system is connected LAST in Main, so this save runs FIRST and
		-- captures the pristine state (plotIndex still set). Release + cleanup follow.
		-- A carried (stolen) core is dropped where the player stood, not deleted with
		-- them (2026-10-18 audit). Hook set by Main to avoid a require cycle.
		if DataService.onLeaving then
			pcall(DataService.onLeaving, player)
		end
		DataService.save(player, true) -- releases the session lock
		loaded[player] = nil
		PlotSystem.release(player)
		PlotSystem.forget(player)
		PlayerState.remove(player)
	end)

	game:BindToClose(function()
		-- Save-safety (M4-03): flush every player and prove it stayed inside the
		-- ~30 s shutdown budget.
		local t0 = os.clock()
		local count = 0
		for _, player in Players:GetPlayers() do
			task.spawn(function()
				DataService.save(player, true)
				count += 1
			end)
		end
		-- Saves run in parallel (8 players x a few seconds would not fit in series).
		local deadline = os.clock() + 25
		while count < #Players:GetPlayers() and os.clock() < deadline do
			task.wait(0.2)
		end
		print(string.format("[DataService] shutdown flush: %d player(s) in %.1fs (budget 30s)", count, os.clock() - t0))
	end)

	-- Auto-save loop.
	task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_SECONDS)
			for _, player in Players:GetPlayers() do
				DataService.save(player)
			end
		end
	end)
end

return DataService
