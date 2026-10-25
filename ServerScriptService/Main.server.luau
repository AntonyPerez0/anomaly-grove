--!strict
-- Server bootstrap: wire every system's lifecycle in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Config = require(ReplicatedStorage.Shared.Config)

local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local SeedSystem = require(script.Parent.SeedSystem)
local CoreSystem = require(script.Parent.CoreSystem)
local DayNightCycle = require(script.Parent.DayNightCycle)
local StealSystem = require(script.Parent.StealSystem)
local MonsterAI = require(script.Parent.MonsterAI)
local RespawnSystem = require(script.Parent.RespawnSystem)
local OfflineGrowth = require(script.Parent.OfflineGrowth)
local GadgetSystem = require(script.Parent.GadgetSystem)
local DefenseSystem = require(script.Parent.DefenseSystem)
local RebirthSystem = require(script.Parent.RebirthSystem)
local CollectionIndex = require(script.Parent.CollectionIndex)
local MonetizationService = require(script.Parent.MonetizationService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local TutorialService = require(script.Parent.TutorialService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local CosmeticService = require(script.Parent.CosmeticService)
local PerfBudget = require(script.Parent.PerfBudget)
local QuestService = require(script.Parent.QuestService)
local FriendBoostService = require(script.Parent.FriendBoostService)
local DailyRewardService = require(script.Parent.DailyRewardService)
local MilestoneService = require(script.Parent.MilestoneService)
local SkillService = require(script.Parent.SkillService)
local EconomyService = require(script.Parent.EconomyService)
local PassService = require(script.Parent.PassService)
local EventServiceForSkills = require(script.Parent.EventService)
local DataService = require(script.Parent.DataService)
local DebugBridge = require(script.Parent.DebugBridge)

PlayerState.init()
PlotSystem.init()
SeedSystem.init()
CoreSystem.init()
DayNightCycle.init()
StealSystem.init()
MonsterAI.init()
RespawnSystem.init()
GadgetSystem.init()
DefenseSystem.init()
RebirthSystem.init()
MonetizationService.init()
LeaderboardService.init()
TutorialService.init()
AnalyticsService.init()
CosmeticService.init()
CollectionIndex.init()
QuestService.init()
FriendBoostService.init()
DailyRewardService.init()
MilestoneService.init()
-- M8: skills (night/Blood Moon injected to keep SkillService free of system requires),
-- purchases (upgrades, crates, infuse, tree), Grove Pass.
SkillService.init(function()
	return DayNightCycle.getPhase() == "Night"
end, function()
	return EventServiceForSkills.current() == "BloodMoon"
end)
EconomyService.init()
PassService.init()
-- DataService boots LAST so its PlayerRemoving handler is connected last.
-- PlayerRemoving handlers fire in REVERSE connection order, so the leave
-- save runs FIRST and captures the pristine state (plotIndex still set)
-- before release clears it. PlotSystem has no leave handler of its own.
DataService.onLeaving = function(player)
	StealSystem.dropCarried(player, false)
end
DataService.init()
DebugBridge.init()

-- World events (M6-04): injected hooks keep EventService free of system requires.
local EventService = require(script.Parent.EventService)
local FXService = require(script.Parent.FXService)
local SeedNodeBuilder = require(game:GetService("ServerStorage").Builders.SeedNodeBuilder)
local LightingBuilder = require(game:GetService("ServerStorage").Builders.LightingBuilder)
EventService.init({
	spawnBoostedSeed = SeedSystem.spawnMeteorNode,
	randomForestPosition = function()
		return SeedNodeBuilder.randomForestPosition(Random.new(os.clock() * 1e6))
	end,
	burstAt = function(position, color)
		FXService.burstAt(position, color, 30)
	end,
	setBloodMoonLighting = function(on)
		if on then
			LightingBuilder.applyBloodMoon(3)
		end
	end,
})
DayNightCycle.onPhaseStarted(EventService.onPhaseStarted)
-- M9-03 Grove Warden boss nights (subscribes to EventService).
require(script.Parent.BossService).init()
-- M9-04 Traveling Market (hub stall, rotating stock).
require(script.Parent.MarketService).init()
-- M9-05 Fuse Machine.
require(script.Parent.FuseService).init()
-- M9-06 weather (Thunderstorm lightning; Rain/Aurora are EventService multipliers).
require(script.Parent.WeatherService).init()
-- M9-07 companions.
require(script.Parent.CompanionService).init()
-- M9-10 codes + group reward.
require(script.Parent.RewardService).init()

-- Studio-only debug commands for playtest scenarios.
DebugBridge.register("event:trigger", function(_player, args)
	if args[1] == "BloodMoon" then
		EventService.startBloodMoon()
	elseif args[1] == "WardenNight" then
		EventService.startWardenNight()
	elseif args[1] == "Weekly" then
		EventService.forceWeekly(args[2] ~= false and args[2] ~= "false")
	elseif args[1] == "Rain" or args[1] == "Thunderstorm" or args[1] == "Aurora" then
		EventService.startWeather(args[1], tonumber(args[2]) or 60)
	else
		EventService.startMeteorShower()
	end
end)
DebugBridge.register("steal:debugCarry", function(player, args)
	if not player then
		return
	end
	local rarity = (args[1] :: any) or "Sprout"
	StealSystem.debugCarry(player, rarity :: any)
end)

-- M8 test helpers (Studio-only via DebugBridge).
DebugBridge.register("skill:setLevel", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local skill = tostring(args[1])
	local level = tonumber(args[2]) or 1
	local Progression = require(ReplicatedStorage.Shared.Progression)
	state.skills[skill] = Progression.xpForLevel(level)
	SkillService.publish(player, state)
	print(`[DebugBridge] {player.Name} {skill} set to level {level}`)
end)
-- Exact skill XP (Studio-only): restores a snapshot after a playtest.
DebugBridge.register("skill:setXp", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.skills[tostring(args[1])] = math.max(0, math.floor(tonumber(args[2]) or 0))
	SkillService.publish(player, state)
	print(`[DebugBridge] {player.Name} {args[1]} XP set to {state.skills[tostring(args[1])]}`)
end)
-- Grant/revoke a gadget (Studio-only): gadget:set Lantern true|false.
DebugBridge.register("gadget:set", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local gadget = tostring(args[1])
	local owned = args[2] ~= false and args[2] ~= "false"
	local gadgets: { [string]: boolean? } = state.gadgets :: any
	gadgets[gadget] = if owned then true else nil
	player:SetAttribute(`Gadget_{gadget}`, if owned then "owned" else nil)
	print(`[DebugBridge] {player.Name} gadget {gadget} owned={owned}`)
end)
-- Undo test artefacts (Studio-only): state:forget index <key> | milestone <id>.
DebugBridge.register("state:forget", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local key = tostring(args[2])
	if args[1] == "index" then
		local discovered: { [string]: boolean? } = state.indexDiscovered :: any
		discovered[key] = nil
		CollectionIndex.syncAttribute(player, state)
	elseif args[1] == "milestone" then
		local milestones: { [string]: boolean? } = state.milestones :: any
		milestones[key] = nil
	elseif args[1] == "code" then
		local codes: { [string]: boolean? } = state.codes :: any
		codes[key] = nil
	end
	print(`[DebugBridge] {player.Name} forgot {args[1]} {key}`)
end)
-- Privacy request (Studio-only, run in a playtest): data:erase <userId> deletes
-- the profile and leaderboard rows of that user.
DebugBridge.register("data:erase", function(_player, args)
	local userId = tonumber(args[1])
	if not userId or userId <= 0 or userId ~= math.floor(userId) then
		warn("[DebugBridge] data:erase needs a numeric userId")
		return
	end
	local profileOk = DataService.eraseUserId(userId)
	local boards = LeaderboardService.eraseUserId(userId)
	print(`[DebugBridge] data:erase {userId}: profile={profileOk} boards={boards}`)
end)
-- Give seeds (Studio-only): kind "regular" | "grove" | a zone seed id ("RelicSeed").
DebugBridge.register("seeds:add", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local kind = tostring(args[1])
	local count = math.floor(tonumber(args[2]) or 1)
	if kind == "regular" then
		state.seedsCarried = math.max(0, state.seedsCarried + count)
		player:SetAttribute("SeedsCarried", state.seedsCarried)
	elseif kind == "grove" then
		state.groveSeeds = math.max(0, state.groveSeeds + count)
		player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
	else
		PlayerState.addZoneSeed(state, kind, count)
	end
	print(`[DebugBridge] {player.Name} seeds:add {kind} x{count} (total {PlayerState.seedCount(state)})`)
end)
-- Exact state repair (Studio-only): pedestal level and absolute cash.
DebugBridge.register("pedestal:setLevel", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local pedestal = state.pedestals[tonumber(args[1]) or 0]
	if pedestal then
		pedestal.level = math.max(1, math.floor(tonumber(args[2]) or 1))
		CoreSystem.refreshPedestalVisual(state, tonumber(args[1]) :: number)
	end
end)
DebugBridge.register("state:setCash", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.cash = math.max(0, math.floor(tonumber(args[1]) or state.cash))
	player:SetAttribute("Cash", state.cash)
	print(`[DebugBridge] {player.Name} cash set to {state.cash}`)
end)
DebugBridge.register("tokens:add", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.tokens += tonumber(args[1]) or 1
	SkillService.publish(player, state)
end)
DebugBridge.register("rebirths:set", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.rebirths = tonumber(args[1]) or 0
	player:SetAttribute("Rebirths", state.rebirths)
	SkillService.publish(player, state)
end)
DebugBridge.register("pass:addXp", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.pass.xp += tonumber(args[1]) or 0
	player:SetAttribute("PassXp", math.floor(state.pass.xp))
end)

-- Launch cleanup (human-approved): reset this player's profile to a brand-new
-- one, save it, and clear their leaderboard rows + the seeded test bots.
-- Stop the playtest right after; the world visuals are left stale.
DebugBridge.register("data:wipe", function(player)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	-- Release the plot first (wipes its pedestals/defenses), then reset. Fields
	-- whose default is nil are skipped by the copy loop, so clear them explicitly
	-- (fix 2026-10-18: plotIndex and cape survived a wipe).
	PlotSystem.release(player)
	for key, value in PlayerState.createDefault() :: any do
		if key ~= "player" then
			(state :: any)[key] = value
		end
	end
	state.plotIndex = nil
	state.carried = nil
	state.cape = nil
	state.companion = nil
	player:SetAttribute("Companion", nil)
	player:SetAttribute("PlotIndex", nil)
	SkillService.refreshCape(player, state)
	state.quests = { day = -1, list = {} }
	state.daily = { lastClaimDay = -1, streak = 0 }
	for _, attribute in { "Cash", "CoresStolen", "NightStreak", "NetWorth", "IncomeRate" } do
		player:SetAttribute(attribute, 0)
	end
	print(`[Main] data:wipe {player.Name} -> {DataService.save(player)}`)
	LeaderboardService.removeEntries(player)
end)
DebugBridge.register("data:save", function(player)
	if not player then
		for _, p in game:GetService("Players"):GetPlayers() do
			DataService.save(p)
		end
		return
	end
	DataService.save(player)
end)

DebugBridge.register("offline:simulate", function(player)
	if not player then
		return
	end
	-- Pretend the player left 2 hours ago with their current pedestals.
	OfflineGrowth.applyToState(player, os.time() - 7200)
end)

DebugBridge.register("core:forceMutation", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local slot = tonumber(args[1]) or 1
	local mutation = (args[2] :: any) or "Gold"
	CoreSystem.applyMutation(state, slot, mutation :: any)
end)

-- Put a hatched core (optionally mutated) on an owned pedestal: (slot, rarity, mutation?).
DebugBridge.register("core:set", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local slot = tonumber(args[1]) or 1
	local pedestal = state.pedestals[slot]
	if not pedestal or state.plotIndex == nil then
		warn(`[DebugBridge] core:set: no pedestal {slot}`)
		return
	end
	pedestal.rarity = (args[2] :: any) or "Sprout"
	pedestal.mutation = args[3] :: any
	pedestal.hatchAt = nil
	-- Optional 4th arg: a size name ("Normal" clears it). M9-01.
	if args[4] == "Normal" then
		pedestal.size = nil
	elseif args[4] and Config.Sizes.Defs[tostring(args[4])] then
		pedestal.size = tostring(args[4])
	end
	CoreSystem.setPedestalCore(
		state.plotIndex :: number,
		slot,
		pedestal.rarity :: any,
		pedestal.mutation :: any,
		pedestal.level,
		pedestal.size
	)
end)

-- Fill quest `index` to its goal (claim then goes through the real remote).
DebugBridge.register("quest:complete", function(player, args)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	local quest = state.quests and (state.quests :: any).list[tonumber(args[1]) or 1]
	if quest then
		QuestService.record(player, quest.id, quest.goal)
	end
end)

-- Make today's daily reward claimable again (tests the auto-open popup on rejoin).
DebugBridge.register("daily:reset", function(player)
	if not player then
		return
	end
	local state = PlayerState.get(player)
	state.daily = { lastClaimDay = -1, streak = 0 }
	DailyRewardService.publishNow(player)
end)

DebugBridge.register("state:addCash", function(player, args)
	if not player then
		return
	end
	local amount = tonumber(args[1]) or 0
	local state = PlayerState.get(player)
	print(`[DebugBridge] addCash {amount} to {player.Name} (now {PlayerState.addCash(state, amount)})`)
end)

DebugBridge.register("plot:simulateLeave", function(player)
	if not player then
		return
	end
	-- Runs the real release path (schedules the 60 s wipe) without ending the session.
	PlotSystem.release(player)
end)

DebugBridge.register("defense:forceTick", function(player, args)
	if not player then
		return
	end
	-- One manual turret hit for verification (bypasses range/targeting sweep).
	local damage = tonumber(args[1]) or 10
	DefenseSystem.applyHit(player, damage, 1.5)
end)

DebugBridge.register("defense:forceRoot", function(player, args)
	if not player then
		return
	end
	-- One manual trap root for verification (bypasses the radius sweep).
	local seconds = tonumber(args[1]) or 2
	DefenseSystem.rootPlayer(player, seconds)
end)

DebugBridge.register("grove:set", function(_player, args)
	-- Force the Grove Heart cohort for verification: "on" spawns at center,
	-- anything else despawns (normally driven by the day/night phase).
	local mode = tostring(args[1])
	local count = if mode == "on" then SeedSystem.spawnGroveNodes() else SeedSystem.despawnGroveNodes()
	print(`[DebugBridge] grove:set {mode} -> {count}`)
end)

DebugBridge.register("monetization:vault", function(player, _args)
	if not player then
		return
	end
	-- Test-only ownership stub: pretend the Vault Lock pass is owned, apply the
	-- grant, then restore the real ownership path (placeholder ID 0 = not owned).
	MonetizationService.setOwnershipProvider(function()
		return true
	end)
	local ok = MonetizationService.applyVaultLock(player)
	MonetizationService.setOwnershipProvider(nil)
	print(`[DebugBridge] monetization:vault -> {ok}`)
end)

DebugBridge.register("monetization:lockdown", function(player, _args)
	if not player then
		return
	end
	-- Fires the same grant the dev product would (playtest path, no receipt).
	local ok = MonetizationService.applyLockdown(player)
	print(`[DebugBridge] monetization:lockdown -> {ok}`)
end)

DebugBridge.register("leaderboard:seed", function(_player, _args)
	-- Seeds ranked bot entries into the ordered stores and refreshes the boards.
	LeaderboardService.seedTestEntries()
	print(`[DebugBridge] leaderboard:seed done`)
end)

DebugBridge.register("cosmetic:simulate", function(player, _args)
	if not player then
		return
	end
	-- Pretend the player owns BOTH cosmetic passes, attach the trail now, and
	-- fire one alarm so the pass effects can be verified before launch.
	MonetizationService.setOwnershipProvider(function()
		return true
	end)
	if player.Character then
		CosmeticService.attachTrail(player.Character, { kind = "Core", rarity = "Amber", mutation = nil })
	end
	Remotes.get("Juice"):FireClient(player, "Alarm", "TestRaider")
	MonetizationService.setOwnershipProvider(nil)
	print(`[DebugBridge] cosmetic:simulate applied to {player.Name}`)
end)

DebugBridge.register("tutorial:reset", function(player, _args)
	if not player then
		return
	end
	-- Fresh-player simulation: clear every toast flag so the sequence replays.
	local state = PlayerState.get(player)
	state.tutorial = { claimed = false, harvested = false, placed = false, stealHint = false }
	print(`[DebugBridge] tutorial flags reset for {player.Name}`)
end)

DebugBridge.register("perf:report", function(_player, _args)
	-- Rolling worst-case loop timings (M4-01 heartbeat budget check), then a
	-- fresh window so consecutive reports show separate periods.
	print(`[DebugBridge] perf:report {PerfBudget.report()}`)
	PerfBudget.reset()
end)

DebugBridge.register("perf:bench", function(_player, _args)
	-- Synthetic per-player cost: 64 hatched pedestals (8 players x 8 slots),
	-- 1000 1-second ticks each. Reports per-player ms per second.
	local benches = {}
	for _ = 1, 64 do
		local pedestal = PlayerState.newPedestal()
		pedestal.rarity = "Amber"
		table.insert(benches, pedestal)
	end
	local state = PlayerState.createDefault()
	local t0 = os.clock()
	for _, pedestal in benches do
		for _ = 1, 1000 do
			CoreSystem.tickPedestal(state, pedestal, 1)
		end
	end
	local ms = (os.clock() - t0) * 1000
	print(
		string.format(
			"[DebugBridge] perf:bench 64 pedestals x 1000 ticks = %.1fms total (%.3fms per player-second)",
			ms,
			ms / 64 / 1000
		)
	)
end)

DebugBridge.register("perf:memory", function(_player, _args)
	-- Luau heap trend sample (KB) for the 10-minute growth check.
	local kb = gcinfo()
	print(string.format("[DebugBridge] perf:memory luau heap = %.0f KB", kb))
end)
DebugBridge.register("steal:tagPhantom", function(player, args)
	if not player then
		return
	end
	local offset = tonumber(args[1]) or 4
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local phantomPos = root.Position + Vector3.new(offset, 0, 0)
	StealSystem.resolveTag("PhantomRaider", phantomPos, player)
end)
DebugBridge.register("steal:setZapperCooldown", function(player, args)
	if not player then
		return
	end
	local seconds = tonumber(args[1]) or 5
	PlayerState.get(player).zapperReadyAt = os.clock() + seconds
	print(`[StealSystem] debug: zapper cooldown set to {seconds}s for {player.Name}`)
end)

print("[Main] server systems initialized")
