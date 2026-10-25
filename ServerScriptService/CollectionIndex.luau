--!strict
-- Collection Index (M2-10 / GDD 5.7): tracks discovered rarities and mutation
-- traits per player; new discoveries notify the client (chime + badge).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)

local CollectionIndex = {}

-- The client reads discoveries through this replicated attribute (tables cannot
-- be attributes): "Sprout,mut:Gold,..."
function CollectionIndex.syncAttribute(player: Player, state: Types.PlayerState)
	local keys: { string } = {}
	for key in state.indexDiscovered do
		table.insert(keys, key)
	end
	table.sort(keys)
	local joined = table.concat(keys, ",")
	if player:GetAttribute("IndexKeys") ~= joined then
		player:SetAttribute("IndexKeys", joined)
	end
end

-- Marks a rarity discovered; returns true when it was NEW.
function CollectionIndex.markRarity(state: Types.PlayerState, rarity: Types.Rarity): boolean
	local key = rarity :: string
	if state.indexDiscovered[key] then
		return false
	end
	state.indexDiscovered[key] = true
	if state.player then
		CollectionIndex.syncAttribute(state.player, state)
	end
	return true
end

-- Marks a mutation trait discovered; returns true when it was NEW.
function CollectionIndex.markMutation(state: Types.PlayerState, mutation: Types.Mutation): boolean
	local key = "mut:" .. (mutation :: string)
	if state.indexDiscovered[key] then
		return false
	end
	state.indexDiscovered[key] = true
	if state.player then
		CollectionIndex.syncAttribute(state.player, state)
	end
	return true
end

-- Called by CoreSystem when a core hatches: rarity discovery (+mutation discovery
-- for already-mutated cores).
function CollectionIndex.onCoreHatched(
	player: Player,
	state: Types.PlayerState,
	rarity: Types.Rarity,
	mutation: Types.Mutation?
)
	local newRarity = CollectionIndex.markRarity(state, rarity)
	if newRarity then
		Remotes.get("Discovery"):FireClient(player, "Rarity", rarity)
		CollectionIndex.checkRow(state, rarity)
	end
	if mutation ~= nil then
		CollectionIndex.onMutation(state, mutation, rarity)
	end
end

-- M8-09: a rarity x mutation combo entry ("Ember+Gold"). Returns true when NEW.
function CollectionIndex.markCombo(state: Types.PlayerState, rarity: Types.Rarity, mutation: Types.Mutation): boolean
	local key = Perks.indexKey(rarity, mutation)
	if state.indexDiscovered[key] then
		return false
	end
	state.indexDiscovered[key] = true
	if state.player then
		CollectionIndex.syncAttribute(state.player, state)
	end
	return true
end

-- Completing a rarity row (plain + all 3 mutations) pays Rebirth Tokens, once.
function CollectionIndex.checkRow(state: Types.PlayerState, rarity: Types.Rarity): boolean
	local id = `indexRow:{rarity}`
	if state.milestones[id] or not Perks.indexRowComplete(state.indexDiscovered, rarity) then
		return false
	end
	state.milestones[id] = true
	state.tokens += Config.IndexRowTokens
	if state.player then
		state.player:SetAttribute("Tokens", state.tokens)
		Remotes.get("TutorialToast")
			:FireClient(state.player, `Index row complete: {rarity}! +{Config.IndexRowTokens} Rebirth Token`)
	end
	return true
end

-- Called when a core mutates (rarity known => the combo entry counts too).
function CollectionIndex.onMutation(state: Types.PlayerState, mutation: Types.Mutation, rarity: Types.Rarity?)
	local newMutation = CollectionIndex.markMutation(state, mutation)
	if state.player and newMutation then
		Remotes.get("Discovery"):FireClient(state.player, "Mutation", mutation)
	end
	if rarity ~= nil and CollectionIndex.markCombo(state, rarity, mutation) then
		if state.player then
			Remotes.get("Discovery"):FireClient(state.player, "Combo", Perks.indexKey(rarity, mutation))
		end
		CollectionIndex.checkRow(state, rarity)
	end
end

-- Boot: sync attributes for anyone already present.
-- Fix (2026-10-18): offline mutations, steals and debug edits never reached the
-- Index. On load, every core the player owns counts as discovered (silent: no
-- toasts; completed rows still pay their tokens once). Returns how many were new.
function CollectionIndex.backfill(state: Types.PlayerState): number
	local added = 0
	for _, pedestal in state.pedestals do
		local rarity: Types.Rarity? = pedestal.rarity :: any
		if rarity ~= nil and pedestal.hatchAt == nil then
			if CollectionIndex.markRarity(state, rarity) then
				added += 1
			end
			local mutation: Types.Mutation? = pedestal.mutation :: any
			if mutation ~= nil then
				if CollectionIndex.markMutation(state, mutation) then
					added += 1
				end
				if CollectionIndex.markCombo(state, rarity, mutation) then
					added += 1
				end
			end
			CollectionIndex.checkRow(state, rarity)
		end
	end
	return added
end

function CollectionIndex.init()
	for _, player in game:GetService("Players"):GetPlayers() do
		local state = PlayerState.peek(player)
		if state then
			CollectionIndex.syncAttribute(player, state)
		end
	end
end

return CollectionIndex
