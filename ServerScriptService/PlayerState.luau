--!strict
-- Per-player live state (cash, plot, carried item, pedestals). The server is the
-- only writer; clients see results through remotes and replication, never state tables.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = {}

local states: { [Player]: Types.PlayerState } = {}

-- Pure helpers (usable without a Player, so specs can test them).

function PlayerState.newPedestal(): Types.PedestalState
	return {
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
	}
end

function PlayerState.createDefault(): Types.PlayerState
	return {
		player = nil,
		plotIndex = nil,
		cash = 0,
		carried = nil,
		seedsCarried = 0,
		groveSeeds = 0,
		zoneSeeds = {},
		codes = {},
		pedestals = { PlayerState.newPedestal() },
		defenses = {},
		gadgets = {},
		zapperReadyAt = 0,
		stealImmuneUntil = 0,
		lockdownUntil = 0,
		lockdownsUsed = 0,
		rebirths = 0,
		indexDiscovered = {},
		coresStolen = 0,
		nightStreak = 0,
		milestones = {},
		skills = {},
		tokens = 0,
		tree = {},
		upgrades = {},
		pass = { season = 0, xp = 0, claimed = {} },
		cape = nil,
		tutorial = {
			claimed = false,
			harvested = false,
			placed = false,
			stealHint = false,
		},
	}
end

-- Current income per second as shown on the HUD (server-written attribute; it
-- includes every multiplier). 0 for spec states without a player.
function PlayerState.incomeRate(state: Types.PlayerState): number
	local rate = if state.player then state.player:GetAttribute("IncomeRate") else nil
	return if type(rate) == "number" then rate else 0
end

-- Every seed in the backpack: forest + Grove Heart + wild-zone seeds.
function PlayerState.seedCount(state: Types.PlayerState): number
	local total = state.seedsCarried + state.groveSeeds
	for _, count in state.zoneSeeds do
		total += count
	end
	return total
end

-- Adds (or with a negative delta removes) zone seeds and mirrors them to the
-- ZoneSeedsCarried (total) and ZoneSeeds ("CrystalSeed=1,RelicSeed=2") attributes.
function PlayerState.addZoneSeed(state: Types.PlayerState, seedId: string, delta: number)
	local count = math.max(0, (state.zoneSeeds[seedId] or 0) + delta)
	local seeds: { [string]: number? } = state.zoneSeeds :: any
	seeds[seedId] = if count > 0 then count else nil
	if state.player then
		local total, parts = 0, {}
		for id, n in state.zoneSeeds do
			total += n
			table.insert(parts, `{id}={n}`)
		end
		table.sort(parts)
		state.player:SetAttribute("ZoneSeedsCarried", total)
		state.player:SetAttribute("ZoneSeeds", table.concat(parts, ","))
	end
end

-- Adds cash; cash never goes negative. Returns the new value.
function PlayerState.addCash(state: Types.PlayerState, delta: number): number
	state.cash = math.max(0, state.cash + delta)
	if state.player then
		state.player:SetAttribute("Cash", state.cash)
	end
	return state.cash
end

-- Spends cash; fails (and changes nothing) when the balance is too low.
function PlayerState.spendCash(state: Types.PlayerState, amount: number): boolean
	if amount ~= amount or amount < 0 or amount == math.huge or state.cash < amount then
		return false
	end
	state.cash -= amount
	if state.player then
		state.player:SetAttribute("Cash", state.cash)
	end
	return true
end

-- Lifecycle (player-keyed).

function PlayerState.createState(player: Player): Types.PlayerState
	local state = PlayerState.createDefault()
	state.player = player
	player:SetAttribute("Cash", 0) -- replicated live state (readable from any VM)
	player:SetAttribute("SeedsCarried", 0)
	player:SetAttribute("GroveSeedsCarried", 0)
	player:SetAttribute("ZoneSeedsCarried", 0)
	player:SetAttribute("CoresStolen", 0)
	player:SetAttribute("PedestalSlots", 1)
	player:SetAttribute("DefenseSlots", 0)
	return state
end

-- Lazy accessor: creates state on first touch.
function PlayerState.get(player: Player): Types.PlayerState
	local state = states[player]
	if not state then
		state = PlayerState.createState(player)
		states[player] = state
	end
	return state
end

-- Non-creating accessor for cleanup paths (returns nil if the player has no state).
function PlayerState.peek(player: Player): Types.PlayerState?
	return states[player]
end

function PlayerState.remove(player: Player)
	states[player] = nil
end

-- Wires join/leave. Call once from the server bootstrap. The leave save lives in
-- DataService (save before remove); no removal here so leave ordering stays clean.
function PlayerState.init()
	for _, player in Players:GetPlayers() do
		PlayerState.get(player)
	end
	Players.PlayerAdded:Connect(PlayerState.get)
end

return PlayerState
