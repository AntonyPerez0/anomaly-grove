--!strict
-- Leaderboards (M3-06): writes each player's NetWorth / CoresStolen / NightStreak
-- to OrderedDataStores every 60 s (and on leave), then renders the top rows onto
-- the physical hub boards. Falls back to live-player-only boards with ONE warning
-- when DataStores are unavailable (Studio without API access).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Progression = require(game:GetService("ReplicatedStorage").Shared.Progression)

local LeaderboardBuilder = require(game.ServerStorage.Builders.LeaderboardBuilder)

local LeaderboardService = {}

-- M8: net worth outgrows OrderedDataStore's 64-bit integers late in the game, so
-- that board stores log10 scaled to an integer and decodes it for display.
local LOG_SCALE = 1e9
local LOG_KEYS: { [string]: boolean } = { NetWorth = true }

function LeaderboardService.encode(statKey: string, value: number): number
	if LOG_KEYS[statKey] then
		return math.floor(math.log10(math.max(value, 0) + 1) * LOG_SCALE)
	end
	return math.floor(value)
end

function LeaderboardService.decode(statKey: string, stored: number): number
	if LOG_KEYS[statKey] then
		return 10 ^ (stored / LOG_SCALE) - 1
	end
	return stored
end

local STORE_PREFIX = "AnomalyGroveLb"
local REFRESH_SECONDS = Config.Leaderboards.RefreshSeconds
local ROWS = Config.Leaderboards.Rows

local stores: { [string]: OrderedDataStore } = {}
local fallbackMode = false
local warned = false
local nameCache: { [string]: string } = {}

local function warnOnce(message: string)
	if not warned then
		warned = true
		warn(message)
	end
end

-- Resolve a display name for a board row. Keys are "Player_<userId>" or seeded
-- bot keys ("Bot_1") that skip lookup entirely.
local function displayName(key: string): string
	if nameCache[key] then
		return nameCache[key]
	end
	local name: string
	local userId = tonumber(string.match(key, "^Player_(%d+)$"))
	if string.match(key, "^Bot_") then
		name = string.gsub(key, "_", " ")
	elseif userId then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			name = player.Name
		else
			local ok, resolved = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			name = if ok and resolved then resolved else `Player_{userId}`
		end
	else
		name = key
	end
	nameCache[key] = name
	return name
end

-- Push one player's current stats into the ordered stores.
function LeaderboardService.writeNow(player: Player)
	if fallbackMode then
		return
	end
	for _, stat in LeaderboardBuilder.STATS do
		local value = LeaderboardService.encode(stat.key, (player:GetAttribute(stat.key) or 0) :: number)
		local store = stores[stat.key]
		if store then
			pcall(function()
				store:SetAsync(`Player_{player.UserId}`, value)
			end)
		end
	end
end

local function boardPanel(statKey: string): Model?
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local folder = root and root:FindFirstChild("Leaderboards")
	return folder and folder:FindFirstChild(`Leaderboard_{statKey}`)
end

-- Fill one board's rows from ranked entries (name + value), clearing the rest.
local function refreshBoard(statKey: string, entries: { { name: string, value: number } })
	local model = boardPanel(statKey)
	if not model or not model.PrimaryPart then
		return
	end
	local gui = model.PrimaryPart:FindFirstChild("BoardGui")
	if not gui then
		return
	end
	for i = 1, ROWS do
		local row = gui:FindFirstChild(`Row{i}`)
		if row and row:IsA("Frame") then
			local entry = entries[i]
			local nameLabel = row:FindFirstChild("Name")
			local valueLabel = row:FindFirstChild("Value")
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = if entry then entry.name else "—"
			end
			if valueLabel and valueLabel:IsA("TextLabel") then
				valueLabel.Text = if entry then Progression.format(entry.value) else ""
			end
		end
	end
end

-- Live-player fallback ranking (no DataStores): read attributes directly.
local function liveEntries(statKey: string): { { name: string, value: number } }
	local entries: { { name: string, value: number } } = {}
	for _, player in Players:GetPlayers() do
		table.insert(entries, {
			name = player.Name,
			value = math.floor((player:GetAttribute(statKey) or 0) :: number),
		})
	end
	table.sort(entries, function(a, b)
		return a.value > b.value
	end)
	return entries
end

local function refreshAll()
	for _, stat in LeaderboardBuilder.STATS do
		local entries: { { name: string, value: number } } = {}
		local store = stores[stat.key]
		if store and not fallbackMode then
			local ok, pages = pcall(function()
				return store:GetSortedAsync(false, ROWS) -- descending
			end)
			if ok then
				for _, entry in pages:GetCurrentPage() do
					table.insert(entries, {
						name = displayName(entry.key),
						value = LeaderboardService.decode(stat.key, entry.value :: number),
					})
				end
			else
				warnOnce(`[LeaderboardService] read failed for {stat.key}: {pages}`)
			end
		end
		if #entries == 0 then
			entries = liveEntries(stat.key)
		end
		refreshBoard(stat.key, entries)
	end
end

-- Seed obvious test entries so the ranking is visible in playtests (M3-06).
function LeaderboardService.seedTestEntries()
	if fallbackMode then
		return
	end
	local bots: { { key: string, value: number } } = {
		{ key = "Bot_1", value = 9500 },
		{ key = "Bot_2", value = 7200 },
		{ key = "Bot_3", value = 5100 },
		{ key = "Bot_4", value = 2600 },
		{ key = "Bot_5", value = 900 },
	}
	for _, stat in LeaderboardBuilder.STATS do
		local store = stores[stat.key]
		if not store then
			continue
		end
		for _, bot in bots do
			local scale = if stat.key == "NetWorth" then 1 elseif stat.key == "CoresStolen" then 0.02 else 0.01
			pcall(function()
				store:SetAsync(bot.key, LeaderboardService.encode(stat.key, bot.value * scale))
			end)
		end
	end
	refreshAll()
end

-- Studio-only launch cleanup: drop a player's rows and the seeded test bots
-- from every board (used by the data:wipe debug command).
function LeaderboardService.removeEntries(player: Player)
	for _, stat in LeaderboardBuilder.STATS do
		local store = stores[stat.key]
		if store then
			for _, key in { `Player_{player.UserId}`, "Bot_1", "Bot_2", "Bot_3", "Bot_4", "Bot_5" } do
				local ok, err = pcall(function()
					store:RemoveAsync(key)
				end)
				if not ok then
					warn(`[LeaderboardService] remove {key} from {stat.key} failed: {err}`)
				end
			end
		end
	end
	print(`[LeaderboardService] removed {player.Name} + test bots from all boards`)
end

-- Right-to-erasure (privacy requests): remove one user's rows from every board.
-- Returns how many removals succeeded.
function LeaderboardService.eraseUserId(userId: number): number
	local done = 0
	for _, stat in LeaderboardBuilder.STATS do
		local store = stores[stat.key]
		if store then
			local ok = pcall(function()
				store:RemoveAsync(`Player_{userId}`)
			end)
			if ok then
				done += 1
			end
		end
	end
	return done
end

-- Boot: probe stores, build boards if missing, write + refresh loop. Call once from Main.
function LeaderboardService.init()
	-- Boards are part of the world: self-heal when a fresh place lacks them.
	if not Workspace:FindFirstChild("AnomalyGrove") then
		warnOnce("[LeaderboardService] AnomalyGrove missing - run MapBuilder first")
		return
	end
	if not Workspace.AnomalyGrove:FindFirstChild("Leaderboards") then
		LeaderboardBuilder.build()
	end

	for _, stat in LeaderboardBuilder.STATS do
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(`{STORE_PREFIX}_{stat.key}`, "global")
		end)
		if ok then
			stores[stat.key] = store :: OrderedDataStore
		else
			fallbackMode = true
			warnOnce("[LeaderboardService] OrderedDataStores unavailable - live-player boards only")
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.writeNow(player)
	end)

	refreshAll()
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			for _, player in Players:GetPlayers() do
				LeaderboardService.writeNow(player)
			end
			refreshAll()
		end
	end)
end

return LeaderboardService
