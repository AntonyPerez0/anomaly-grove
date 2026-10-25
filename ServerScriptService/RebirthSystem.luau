--!strict
-- Rebirth (M2-09, reworked M8-06): reset cash, pedestal levels and Sprout-Frost
-- cores for a COMPOUNDING cash multiplier (x1.75 per rebirth) plus Rebirth Tokens
-- for the Rebirth Tree. The requirement grows x2.6 per rebirth, so each climb is
-- longer; rebirth tiers (every 5) raise pedestal level caps and unlock rarities.
-- Skills, the tree, the Index, gadgets and owned defenses are never reset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local CoreSystem = require(script.Parent.CoreSystem)
local SkillService = require(script.Parent.SkillService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local FXService = require(script.Parent.FXService)

local RebirthSystem = {}

-- Pure: cash + core values + cash sunk into pedestal levels (2026-10-18 review:
-- upgrading must never push the rebirth goal further away).
function RebirthSystem.netWorth(state: Types.PlayerState): number
	local total = math.floor(state.cash)
	for slot, pedestal in state.pedestals do
		if pedestal.rarity ~= nil then
			total += (Config.NetWorth :: any)[pedestal.rarity :: string] :: number
		end
		total += Perks.levelInvestment(slot, pedestal.level or 1)
	end
	return total
end

-- Pure: does this core survive a rebirth? Ember+ always; mutated cores too.
function RebirthSystem.keepsCore(pedestal: Types.PedestalState): boolean
	if pedestal.rarity == nil then
		return true
	end
	if Config.Rebirth.KeepMutated and pedestal.mutation ~= nil then
		return true
	end
	return Config.Rarities[pedestal.rarity :: Types.Rarity].tier >= Config.Rebirth.KeepRarityTier
end

function RebirthSystem.requirement(rebirths: number): number
	return Perks.rebirthRequirement(rebirths)
end

-- Pure: gate check.
function RebirthSystem.canRebirth(state: Types.PlayerState): (boolean, string, number)
	local worth = RebirthSystem.netWorth(state)
	local need = RebirthSystem.requirement(state.rebirths)
	if worth < need then
		return false, `need {need} net worth (have {worth})`, worth
	end
	return true, "ok", worth
end

-- Pure: steal speed scales 1 - 0.1 per rebirth, floored at 0.5 (max +5 bonus slots).
function RebirthSystem.stealSpeedMultiplier(rebirths: number): number
	local bonus = math.min(rebirths, Config.Rebirth.MaxDefenseSlotBonus)
	return 1 - Config.Rebirth.StealSpeedBonus * bonus
end

-- Pure: compounding cash multiplier (x1.75 per rebirth).
function RebirthSystem.cashMultiplier(rebirths: number): number
	return Perks.rebirthMultiplier(rebirths)
end

-- Pure: Nest Egg starting cash for the climb that is about to begin.
function RebirthSystem.startCash(state: Types.PlayerState, newRebirths: number): number
	local level = state.tree.NestEgg or 0
	if level <= 0 then
		return 0
	end
	return math.floor(Config.StartCashBase * 4 ^ (level - 1) * Perks.rebirthMultiplier(newRebirths))
end

-- Pure state mutation: reset cash + pedestal levels, clear cores below the keep
-- tier, count it and pay the tokens. Returns the tokens paid.
function RebirthSystem.applyRebirth(state: Types.PlayerState): number
	for _, pedestal in state.pedestals do
		pedestal.level = 1
		if pedestal.rarity ~= nil then
			if not RebirthSystem.keepsCore(pedestal) then
				pedestal.rarity = nil
				pedestal.mutation = nil
				pedestal.size = nil
				pedestal.hatchAt = nil
				pedestal.tickFrac = 0
				pedestal.completedCycles = 0
				pedestal.mutationProgress = 0
			end
		end
	end
	state.rebirths += 1
	state.cash = RebirthSystem.startCash(state, state.rebirths)
	local tokens = Perks.tokensForRebirth(state.rebirths)
	state.tokens += tokens
	return tokens
end

-- Server-authoritative rebirth (live state + visuals). Returns false (logged) when
-- the gate fails.
function RebirthSystem.rebirth(player: Player): boolean
	local state = PlayerState.get(player)
	local ok, reason, worth = RebirthSystem.canRebirth(state)
	if not ok then
		print(`[RebirthSystem] {player.Name} rebirth rejected: {reason}`)
		return false
	end
	-- Snapshot the cleared slots so their visuals can be wiped after the reset.
	local clearedSlots: { number } = {}
	for slot, pedestal in state.pedestals do
		if not RebirthSystem.keepsCore(pedestal) then
			table.insert(clearedSlots, slot)
		end
	end
	local tokens = RebirthSystem.applyRebirth(state)
	player:SetAttribute("Cash", state.cash)
	player:SetAttribute("Rebirths", state.rebirths)
	SkillService.publish(player, state) -- tokens, defense slots
	AnalyticsService.onRebirth(player)
	if state.plotIndex ~= nil then
		local grove = game.Workspace:FindFirstChild("AnomalyGrove")
		local plots = grove and grove:FindFirstChild("Plots")
		local plot = plots and plots:FindFirstChild("Plot" .. ((state.plotIndex :: number) + 1))
		for _, slot in clearedSlots do
			local model = plot and plot:FindFirstChild("Pedestal" .. slot)
			local orb = model and model:FindFirstChild("CoreOrb")
			if orb then
				orb:Destroy()
			end
		end
		-- Kept cores drop back to level 1: refresh their labels.
		for slot in state.pedestals do
			CoreSystem.refreshPedestalVisual(state, slot)
		end
	end
	local multiplier = RebirthSystem.cashMultiplier(state.rebirths)
	Remotes.get("TutorialToast"):FireClient(
		player,
		`Rebirth #{state.rebirths}! Income x{string.format("%.1f", multiplier)} · +{tokens} Rebirth Token{if tokens
				== 1
			then ""
			else "s"}`
	)
	if state.rebirths % Config.Rebirth.TierEvery == 0 then
		Remotes.get("TutorialToast")
			:FireAllClients(`{player.Name} reached rebirth tier {Perks.rebirthTier(state.rebirths)}!`)
	end
	print(
		`[RebirthSystem] {player.Name} rebirth #{state.rebirths} (was {worth} net worth; +{tokens} tokens; x{multiplier})`
	)
	FXService.rebirth(player)
	return true
end

-- Wire the remote + the NetWorth / RebirthCost attribute feed for the shop offer.
-- Call once from Main.server.
function RebirthSystem.init()
	task.spawn(function()
		local rebirthRemote = Remotes.get("Rebirth")
		rebirthRemote.OnServerEvent:Connect(function(player)
			RebirthSystem.rebirth(player)
		end)
	end)

	-- 1 Hz NetWorth attribute update (drives the Rebirth offer button).
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in game:GetService("Players"):GetPlayers() do
				local state = PlayerState.peek(player)
				if state then
					local worth = RebirthSystem.netWorth(state)
					if player:GetAttribute("NetWorth") ~= worth then
						player:SetAttribute("NetWorth", worth)
					end
					local cost = RebirthSystem.requirement(state.rebirths)
					if player:GetAttribute("RebirthCost") ~= cost then
						player:SetAttribute("RebirthCost", cost)
					end
				end
			end
		end
	end)
end

return RebirthSystem
