--!strict
-- Monetization placeholders (M3-04/M3-05). All gamepass/product IDs stay 0 in
-- Config until the human creates real ones (docs/LAUNCH_CHECKLIST.md); an ID of
-- 0 is NEVER treated as owned, so nothing grants or prompts for real.
-- Ownership checks run through an injectable provider so specs can stub them
-- without touching MarketplaceService.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local PedestalBuilder = require(game.ServerStorage.Builders.PedestalBuilder)
local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local DayNightCycle = require(script.Parent.DayNightCycle)
local SkillService = require(script.Parent.SkillService)

local MonetizationService = {}

-- Injectable ownership provider (test hook). Production path uses MarketplaceService.
local ownershipProvider: ((player: Player, passId: number) -> boolean)? = nil

-- Specs stub ownership with this; never call from production code.
function MonetizationService.setOwnershipProvider(provider: ((player: Player, passId: number) -> boolean)?)
	ownershipProvider = provider
end

-- Session ownership cache (M4 cosmetic passes): avoids a DataStore call on
-- every carry toggle. Primed by the purchase-finished hook below.
local passCache: { [Player]: { [number]: boolean } } = {}

-- Cached ownership check. May yield once per player+pass per session (real API);
-- the test provider path is instant.
function MonetizationService.isPassOwner(player: Player, passId: number): boolean
	local cache: { [number]: boolean }? = passCache[player]
	if cache and cache[passId] ~= nil then
		return cache[passId] :: boolean
	end
	local owned = MonetizationService.ownsPass(player, passId)
	local refreshed: { [number]: boolean } = cache or {}
	refreshed[passId] = owned
	passCache[player] = refreshed
	return owned
end

function MonetizationService.ownsPass(player: Player, passId: number): boolean
	-- Test mode: the injected stub decides ownership (production never sets one,
	-- so the placeholder-ID guard below always applies in production).
	if ownershipProvider then
		return ownershipProvider(player, passId)
	end
	if passId <= 0 then
		return false -- placeholder ID: never owned, never granted
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	return ok and owns == true
end

-- M3-04: the Vault Lock pass makes pedestal 1 un-stealable (state + visual).
-- Core grant as a state function so specs can run it without a real Player.
function MonetizationService.applyVaultLockToState(state: Types.PlayerState): boolean
	local pedestal = state.pedestals[1]
	if not pedestal then
		return false
	end
	local passId = Config.GamePasses.VaultLock
	local owned: boolean
	if ownershipProvider then
		owned = ownershipProvider(state.player :: any, passId)
	elseif state.player then
		owned = MonetizationService.ownsPass(state.player, passId)
	else
		owned = false
	end
	if not owned then
		if state.player then
			print(`[Monetization] {state.player.Name} vault lock unavailable: pass not owned (id {passId})`)
		end
		return false
	end
	if pedestal.vaultLocked then
		return false -- already locked
	end
	pedestal.vaultLocked = true
	if state.plotIndex ~= nil then
		PedestalBuilder.setVaultLockVisual(state.plotIndex :: number, 1, true)
	end
	if state.player then
		print(`[Monetization] {state.player.Name}'s pedestal 1 is now VAULT LOCKED (un-stealable)`)
	end
	return true
end

function MonetizationService.applyVaultLock(player: Player): boolean
	return MonetizationService.applyVaultLockToState(PlayerState.get(player))
end

-- Best effort: mark the vault visual when the plot/model exists (restores and grants).
function MonetizationService.syncVaultVisual(player: Player)
	local state = PlayerState.peek(player)
	if not state or state.plotIndex == nil then
		return
	end
	local pedestal = state.pedestals[1]
	if pedestal and pedestal.vaultLocked then
		PedestalBuilder.setVaultLockVisual(state.plotIndex :: number, 1, true)
	end
end

-- Paid random items policy (2026-10-18): the luck pass is a paid probability
-- modifier, so it must not apply where Roblox restricts paid random items. Cached
-- per player and mirrored as "PaidRandomRestricted" for the shop UI.
local restricted: { [Player]: boolean } = {}
function MonetizationService.paidRandomRestricted(player: Player): boolean
	if typeof(player) ~= "Instance" then
		return false -- spec stub players (no PolicyService for them)
	end
	if restricted[player] == nil then
		local ok, info = pcall(function()
			return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
		end)
		-- On error, fail safe: treat as restricted.
		restricted[player] = not ok or (type(info) == "table" and info.ArePaidRandomItemsRestricted == true)
		player:SetAttribute("PaidRandomRestricted", restricted[player])
	end
	return restricted[player]
end

-- M3-05: "2x Offline Mutation Luck" pass doubles the offline roll chance.
function MonetizationService.offlineMutationChance(player: Player, baseChance: number): number
	if
		not MonetizationService.paidRandomRestricted(player)
		and MonetizationService.ownsPass(player, Config.GamePasses.OfflineMutationLuck)
	then
		return baseChance * Config.Offline.LuckMultiplier
	end
	return baseChance
end

-- M7: "2x Cash" pass. Ownership (may yield) lands in a server-set DoubleCash
-- attribute so the 1 Hz income loop can read it without yielding.
function MonetizationService.syncDoubleCash(player: Player)
	local owned = MonetizationService.isPassOwner(player, Config.GamePasses.DoubleCash)
	player:SetAttribute("DoubleCash", if owned then true else nil)
	if owned then
		print(`[Monetization] {player.Name} has 2x Cash`)
	end
end

-- Pure: income multiplier from the 2x Cash pass.
function MonetizationService.doubleCashMultiplier(owned: boolean): number
	return if owned then Config.DoubleCashMultiplier else 1
end

-- M3-05: Instant Base Lockdown product - a 60 s full plot shield, max 3/night.
-- Core grant as a state function so specs can run it without a real Player.
function MonetizationService.applyLockdownToState(state: Types.PlayerState): boolean
	if state.plotIndex == nil then
		if state.player then
			print(`[Monetization] {state.player.Name} lockdown rejected: claim a plot first`)
		end
		return false
	end
	if state.lockdownsUsed >= Config.Lockdown.MaxPerNight then
		if state.player then
			print(`[Monetization] {state.player.Name} lockdown rejected: nightly limit reached`)
		end
		return false
	end
	state.lockdownsUsed += 1
	state.lockdownUntil = os.clock() + Config.Lockdown.Seconds
	PlotSystem.setLockdownVisual(state.plotIndex :: number, true)
	task.delay(Config.Lockdown.Seconds, function()
		-- The state stays the authority; the walls are cosmetic.
		if state.lockdownUntil ~= 0 and os.clock() >= state.lockdownUntil then
			PlotSystem.setLockdownVisual(state.plotIndex or 0, false)
		end
	end)
	if state.player then
		print(
			`[Monetization] {state.player.Name}'s plot is LOCKED DOWN for {Config.Lockdown.Seconds}s (uses {state.lockdownsUsed}/{Config.Lockdown.MaxPerNight} tonight)`
		)
	end
	return true
end

function MonetizationService.applyLockdown(player: Player): boolean
	return MonetizationService.applyLockdownToState(PlayerState.get(player))
end

-- Nightly reset: every night start everyone gets their 3 lockdowns back.
local function resetNightlyLockdowns()
	for _, player in Players:GetPlayers() do
		local state = PlayerState.peek(player)
		if state then
			state.lockdownsUsed = 0
		end
	end
end

function MonetizationService.isLockdownActive(state: Types.PlayerState, now: number): boolean
	return state.lockdownUntil > now
end

-- Boot: wires the nightly lockdown reset and the dev-product receipt path.
-- Call once from Main.server.
function MonetizationService.init()
	DayNightCycle.onPhaseStarted(function(phase)
		if phase == "Night" then
			resetNightlyLockdowns()
		end
	end)

	-- Dev product receipt (single assignment). With placeholder ID 0 no real
	-- receipt ever matches, so nothing grants in production until launch.
	local granted: { [string]: boolean } = {} -- PurchaseIds granted this server
	MarketplaceService.ProcessReceipt = function(receipt)
		if granted[receipt.PurchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted -- retry of a granted receipt
		end
		if receipt.ProductId == Config.Products.InstantLockdown then
			local player = Players:GetPlayerByUserId(receipt.PlayerId)
			if player and MonetizationService.applyLockdown(player) then
				granted[receipt.PurchaseId] = true
				SkillService.addXp(player, "Guarding", Config.Skills.Xp.lockdown)
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet -- unknown product: retry + warn, never grant blindly
	end

	local function onPlayer(player: Player)
		task.spawn(MonetizationService.paidRandomRestricted, player)
		MonetizationService.applyVaultLock(player)
		MonetizationService.syncVaultVisual(player)
		MonetizationService.syncDoubleCash(player)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	-- A pass bought mid-session (prompt from any client UI) grants immediately
	-- and primes the cosmetic-ownership cache (M4 cosmetics).
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and type(passId) == "number" then
			-- Security (2026-10-18 audit): this signal can be faked by exploits, so
			-- confirm with Roblox (UserOwnsGamePassAsync) before granting anything.
			local cache = passCache[player]
			if cache then
				local entries: { [number]: boolean? } = cache :: any
				entries[passId] = nil -- forget any cached "not owned" and ask Roblox
			end
			if not MonetizationService.isPassOwner(player, passId) then
				return
			end
			if passId == Config.GamePasses.VaultLock then
				MonetizationService.applyVaultLock(player)
			end
			if passId == Config.GamePasses.DoubleCash then
				MonetizationService.syncDoubleCash(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		restricted[player] = nil
	end)
end

return MonetizationService
