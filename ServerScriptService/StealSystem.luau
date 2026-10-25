--!strict
-- Carrying, stealing and securing cores (GDD 5.3/5.4).
-- A carrying player moves slower, drops what they carry when damaged, and secures
-- stolen cores by physically crossing their own plot threshold. Server-authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local StatsService = require(script.Parent.StatsService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local CosmeticService = require(script.Parent.CosmeticService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)
local CoreModelBuilder = require(game:GetService("ServerStorage").Builders.CoreModelBuilder)

local StealSystem = {}

local DROP_FOLDER_NAME = "Drops"

local function dropsFolder(): Folder
	local folder = Workspace:FindFirstChild(DROP_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = DROP_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

-- Pure helpers (spec-testable).

-- Walk speed multiplier while carrying (rarity weight + mutation weight).
function StealSystem.carrySpeedMultiplier(core: Types.CarriedItem): number
	local base = Config.Steal.CarrySpeedMultiplier
	local heavy: { [string]: boolean } = { Void = true, Celestial = true }
	if core.rarity and (heavy :: { [string]: boolean })[core.rarity] then
		base = Config.Steal.HeavyCarrySpeedMultiplier
	end
	return base
end

function StealSystem.canStealFrom(
	plots: { { index: number, owner: Player?, pendingReleaseAt: number? } },
	thiefState: Types.PlayerState,
	plotIndex: number,
	victimState: Types.PlayerState?,
	slot: number
): (boolean, string)
	if thiefState.plotIndex == nil then
		return false, "claim a plot first"
	end
	if thiefState.plotIndex == plotIndex then
		return false, "you cannot steal from your own plot"
	end
	if victimState == nil then
		return false, "that plot is not owned"
	end
	if thiefState.carried ~= nil then
		return false, "you are already carrying a core"
	end
	local pedestal = victimState.pedestals[slot]
	if not pedestal then
		return false, "no such pedestal"
	end
	if pedestal.rarity == nil or pedestal.hatchAt ~= nil then
		return false, "no secured core on that pedestal"
	end
	if pedestal.vaultLocked then
		return false, "that pedestal is vault locked"
	end
	if os.clock() < victimState.stealImmuneUntil then
		return false, "that core was just secured - steal immunity"
	end
	if victimState.lockdownUntil > os.clock() then
		return false, "that plot is locked down"
	end
	local plot = plots[plotIndex + 1]
	if plot and plot.owner ~= nil and victimState.player ~= nil and plot.owner ~= victimState.player then
		return false, "ownership mismatch"
	end
	return true, "ok"
end

-- World helpers.

local function plotFolder(index: number): Folder?
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if not plots then
		return nil
	end
	local folder = plots:FindFirstChild("Plot" .. (index + 1))
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function thresholdCFrame(plotIndex: number): CFrame?
	local folder = plotFolder(plotIndex)
	local threshold = folder and folder:FindFirstChild("Threshold")
	if threshold and threshold:IsA("BasePart") then
		return threshold.CFrame
	end
	return nil
end

local function pedestalModel(plotIndex: number, slot: number): Model?
	local folder = plotFolder(plotIndex)
	local model = folder and folder:FindFirstChild("Pedestal" .. slot)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

-- Visuals.

local function attachCarryVisual(character: Model, core: Types.CarriedItem)
	local rarity = core.rarity
	local head = character:FindFirstChild("Head")
	if not rarity or not head or not head:IsA("BasePart") then
		return
	end
	local info = Config.Rarities[rarity]
	local orb = Instance.new("Part")
	orb.Name = "CarriedOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2, 2, 2)
	orb.Color = info.color
	orb.Material = Enum.Material.Neon
	orb.Transparency = 0.15
	orb.CanCollide = false
	orb.CanQuery = false
	orb.Massless = true
	orb.CFrame = head.CFrame * CFrame.new(0, 2.5, 0)
	orb.Parent = character
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = head
	weld.Part1 = orb
	weld.Parent = orb
	local light = Instance.new("PointLight")
	light.Color = info.color
	light.Brightness = 1.2
	light.Range = 10
	light.Parent = orb
end

local function detachCarryVisual(character: Model)
	local orb = character:FindFirstChild("CarriedOrb")
	if orb then
		orb:Destroy()
	end
end

-- Core logic.

-- Applies (or clears) the carry state on a player: HUD attribute, orb, walk speed.
local function applyCarry(player: Player, state: Types.PlayerState, core: Types.CarriedItem?)
	state.carried = core
	if core and core.rarity ~= nil then
		player:SetAttribute("CarriedCore", core.rarity)
	else
		player:SetAttribute("CarriedCore", nil) -- removes the attribute
	end
	local character = player.Character
	if character then
		if core then
			attachCarryVisual(character, core)
			CosmeticService.attachTrail(character, core) -- StealTrails pass (M4)
		else
			detachCarryVisual(character)
			CosmeticService.detachTrail(character)
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.Movement.WalkSpeed
				* (
					if core
						then StealSystem.carrySpeedMultiplier(core) * (1 + math.min(
							Perks.get(SkillService.stats(state), "carrySpeed"),
							0.8
						))
						else 1
				)
		end
	end
end

-- Spawns a grabbable dropped core (wild drop) at a position.
local function spawnDrop(position: Vector3, core: Types.CarriedItem, ownerLockPlayer: Player?)
	local rarity = core.rarity
	if not rarity then
		return
	end
	local info = Config.Rarities[rarity]
	local drop = Instance.new("Part")
	drop.Name = "DroppedCore"
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(2.4, 2.4, 2.4)
	drop.Color = info.color
	drop.Material = Enum.Material.Neon
	drop.Transparency = 0.1
	drop.CFrame = CFrame.new(position)
	drop:SetAttribute("Rarity", rarity)
	drop:SetAttribute("Mutation", core.mutation)
	drop:SetAttribute("Size", core.size)
	-- Owner-lock only applies to VOLUNTARY drops (GDD 5.4): damage/tag drops are free for all.
	if ownerLockPlayer then
		drop:SetAttribute("LockUntil", os.clock() + Config.Steal.OwnerLockSeconds)
		drop:SetAttribute("LockOwner", ownerLockPlayer.Name)
	else
		drop:SetAttribute("LockUntil", 0)
		drop:SetAttribute("LockOwner", "")
	end
	local light = Instance.new("PointLight")
	light.Color = info.color
	light.Brightness = 1.2
	light.Range = 12
	light.Parent = drop
	drop.Parent = dropsFolder()

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Grab Core"
	prompt.ObjectText = "Dropped Core"
	prompt.HoldDuration = Config.Incubation.PlaceHoldTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = drop
	prompt.Triggered:Connect(function(player: Player)
		StealSystem.tryGrab(player, drop)
	end)

	task.delay(Config.Steal.DropDespawnSeconds, function()
		if drop.Parent then
			drop:Destroy()
		end
	end)
	return drop
end

-- Drops whatever the player carries at their feet (tagged, damaged, or death).
-- `lockTo` (optional) gives that player the owner-lock instead (tag drops go to
-- the player who made the tag; 2026-10-18 audit: they used to lock to the thief).
function StealSystem.dropCarried(player: Player, ownerLock: boolean?, lockTo: Player?): boolean
	local state = PlayerState.get(player)
	local core = state.carried
	if not core then
		return false
	end
	applyCarry(player, state, nil)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local position = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else Vector3.new(0, 3, 0)
	spawnDrop(position + Vector3.new(0, 1.5, 0), core, if lockTo then lockTo elseif ownerLock then player else nil)
	print(`[StealSystem] {player.Name} dropped a {core.rarity} core`)
	return true
end

-- The carried core snaps onto a free pedestal in the owner's own plot.
local function secureCore(player: Player, state: Types.PlayerState, core: Types.CarriedItem)
	local rarity = core.rarity
	if not rarity then
		return
	end
	local plotIndex = state.plotIndex :: number
	for slot, pedestal in state.pedestals do
		if pedestal.rarity == nil and pedestal.hatchAt == nil then
			pedestal.rarity = rarity :: any
			pedestal.mutation = core.mutation :: any
			pedestal.size = core.size -- M9-01: a stolen Huge core stays Huge
			pedestal.hatchAt = nil
			pedestal.completedCycles = 1 -- a stolen core counts as one completed cycle
			StatsService.addCoreStolen(state)
			SkillService.addXp(player, "Thievery", Config.Skills.Xp.securePerTier * Config.Rarities[rarity].tier)
			-- Restore the core visual on the destination pedestal.
			local model = pedestalModel(plotIndex, slot)
			if model and model.PrimaryPart then
				local info = Config.Rarities[rarity]
				local mutationInfo = if core.mutation ~= nil then Config.Mutations[core.mutation :: any] else nil
				CoreModelBuilder.attach(model, {
					kind = "core",
					color = if mutationInfo then mutationInfo.color else info.color,
					rarity = rarity :: any,
					mutation = core.mutation :: any,
					rate = info.cashPerSecond
						* (if mutationInfo then mutationInfo.multiplier else 1)
						* Perks.sizeMultiplier(core.size),
					size = core.size,
				})
			end
			-- 30 s steal immunity for the victim plot core (GDD 5.4).
			state.stealImmuneUntil = os.clock() + Config.Steal.StealImmunitySeconds
			print(`[StealSystem] {player.Name} secured a {core.rarity} core on pedestal {slot}`)
			return
		end
	end
	-- No free pedestal: drop it inside the plot instead.
	print(`[StealSystem] {player.Name} has no free pedestal - core dropped in plot`)
	local folder = plotFolder(plotIndex)
	local floor = folder and folder:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		spawnDrop(floor.Position + Vector3.new(0, 3, 0), core, player)
	end
end

-- Pure reach gate (spec-testable): the thief must be physically close to the
-- pedestal they are ripping from, so the remote can't steal across the map.
function StealSystem.isWithinInteract(rootPosition: Vector3, pedestalPosition: Vector3): boolean
	return (rootPosition - pedestalPosition).Magnitude <= Config.Steal.InteractDistance
end

-- Server-timed rip (2026-10-18 audit: the 2 s hold only existed on the client, so
-- an exploit could rip instantly). The client reports when the hold BEGINS; the
-- finish is only accepted on the same pedestal after most of the hold time.
type RipStart = { plot: number, slot: number, at: number }
local ripStarts: { [Player]: RipStart } = {}
local RIP_LATENCY_GRACE = 0.75 -- fraction of the hold the server insists on

function StealSystem.beginRip(player: Player, plotIndex: number, slot: number)
	ripStarts[player] = { plot = plotIndex, slot = slot, at = os.clock() }
end

-- Pure: has a rip that began at `start` lasted long enough for (plot, slot)?
function StealSystem.ripHeldLongEnough(
	start: RipStart?,
	plotIndex: number,
	slot: number,
	now: number,
	ripSeconds: number
): boolean
	return start ~= nil
		and start.plot == plotIndex
		and start.slot == slot
		and now - start.at >= ripSeconds * RIP_LATENCY_GRACE
end

-- Server-authoritative steal attempt (rip a core off a rival pedestal).
function StealSystem.trySteal(player: Player, plotIndex: number, slot: number): boolean
	local thief = PlayerState.get(player)
	local victim = if plotIndex >= 0 and plotIndex <= 7 then PlotSystem.stateAt(plotIndex) else nil
	local ok, reason = StealSystem.canStealFrom(PlotSystem.plots(), thief, plotIndex, victim, slot)
	if not ok then
		print(`[StealSystem] {player.Name} steal rejected: {reason}`)
		return false
	end
	local victimState = victim :: Types.PlayerState
	local pedestal = victimState.pedestals[slot]
	local ripSeconds = Config.Steal.RipTime * (1 - math.min(Perks.get(SkillService.stats(thief), "ripSpeed"), 0.6))
	if not StealSystem.ripHeldLongEnough(ripStarts[player], plotIndex, slot, os.clock(), ripSeconds) then
		print(`[StealSystem] {player.Name} steal rejected: hold not long enough`)
		return false
	end
	ripStarts[player] = nil
	-- Reach gate (M4-02): the client prompt is proximity-based; so is the server.
	local model = pedestalModel(plotIndex, slot)
	local thiefRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not (thiefRoot and thiefRoot:IsA("BasePart"))
		or not (model and model.PrimaryPart)
		or not StealSystem.isWithinInteract(thiefRoot.Position, model.PrimaryPart.Position)
	then
		print(`[StealSystem] {player.Name} steal rejected: too far from that pedestal`)
		return false
	end
	local core: Types.CarriedItem =
		{ kind = "Core", rarity = pedestal.rarity :: any, mutation = pedestal.mutation :: any, size = pedestal.size }
	-- Rip it off the victim pedestal.
	pedestal.rarity = nil
	pedestal.mutation = nil
	pedestal.size = nil
	pedestal.hatchAt = nil
	pedestal.completedCycles = 0
	pedestal.tickFrac = 0
	if model then
		local orb = model:FindFirstChild("CoreOrb")
		if orb then
			orb:Destroy()
		end
	end
	applyCarry(player, thief, core)
	AnalyticsService.onSteal(player)
	SkillService.addXp(player, "Thievery", Config.Skills.Xp.rip)
	CosmeticService.onRip(victimState, player) -- BaseAlarmSirens pass (M4)
	-- M7-04: tell the victim who did it and how to fight back (tag drops the core).
	if victimState.player then
		Remotes.get("TutorialToast")
			:FireClient(victimState.player, `{player.Name} stole your {core.rarity} core! Zap them to get it back!`)
	end
	print(`[StealSystem] {player.Name} ripped a {core.rarity} core from plot {plotIndex}!`)
	return true
end

-- Grab a dropped core (respecting owner-lock).
function StealSystem.tryGrab(player: Player, drop: BasePart): boolean
	local state = PlayerState.get(player)
	if state.carried ~= nil then
		print(`[StealSystem] {player.Name} grab rejected: already carrying`)
		return false
	end
	if not drop.Parent then
		return false
	end
	-- Reach (2026-10-18 audit): prompts can be fired from anywhere by exploits.
	local reachRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not (reachRoot and reachRoot:IsA("BasePart"))
		or (reachRoot.Position - drop.Position).Magnitude > Config.Seeds.HarvestDistance + 4
	then
		return false
	end
	local now = os.clock()
	local grabOk, grabReason = StealSystem.canGrabDrop(drop, player, now)
	if not grabOk then
		print(`[StealSystem] {player.Name} grab rejected: {grabReason}`)
		return false
	end
	local rarity = drop:GetAttribute("Rarity") :: any
	local core: Types.CarriedItem = {
		kind = "Core",
		rarity = rarity :: any,
		mutation = drop:GetAttribute("Mutation") :: any,
		size = drop:GetAttribute("Size") :: any,
	}
	drop:Destroy()
	applyCarry(player, state, core)
	print(`[StealSystem] {player.Name} picked up a dropped core`)
	SkillService.addXp(player, "Thievery", Config.Skills.Xp.grab)
	return true
end

-- Wire remotes + damage hooks + threshold monitoring. Call once from Main.server.
function StealSystem.init()
	task.spawn(function()
		local stealRemote = Remotes.get("StealCore")
		local lastBadLog: { [Player]: number } = {}
		stealRemote.OnServerEvent:Connect(function(player, plotIndex, slot, phase)
			if
				type(plotIndex) ~= "number"
				or type(slot) ~= "number"
				or plotIndex ~= plotIndex
				or slot ~= slot
				or math.abs(plotIndex) > 100
				or math.abs(slot) > 100
			then
				-- Malformed request (M4-02): drop it, but log at most once per 5 s
				-- per player so an exploiter can't spam the console.
				local now = os.clock()
				if now - (lastBadLog[player] or 0) >= 5 then
					lastBadLog[player] = now
					print(`[StealSystem] {player.Name} sent a malformed StealCore request - dropped`)
				end
				return
			end
			if phase == "begin" then
				StealSystem.beginRip(player, math.floor(plotIndex), math.floor(slot))
				return
			end
			StealSystem.trySteal(player, math.floor(plotIndex), math.floor(slot))
		end)
		local grabRemote = Remotes.get("GrabCore")
		grabRemote.OnServerEvent:Connect(function(player)
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart or not rootPart:IsA("BasePart") then
				return
			end
			local best: BasePart? = nil
			local bestDist = math.huge
			for _, drop in dropsFolder():GetChildren() do
				if drop:IsA("BasePart") then
					local dist = (drop.Position - rootPart.Position).Magnitude
					if dist < bestDist then
						bestDist = dist
						best = drop
					end
				end
			end
			if best and bestDist <= Config.Seeds.HarvestDistance then
				StealSystem.tryGrab(player, best)
			end
		end)
		local tagRemote = Remotes.get("TagHit")
		tagRemote.OnServerEvent:Connect(function(attacker, victim)
			if typeof(victim) == "Instance" and victim:IsA("Player") then
				StealSystem.tryTag(attacker, victim :: Player)
			end
		end)
	end)

	-- Any damage while carrying drops the core (tag hits land here too).
	for _, player in Players:GetPlayers() do
		StealSystem.watchPlayer(player)
	end
	Players.PlayerAdded:Connect(function(player)
		StealSystem.watchPlayer(player)
	end)

	-- Threshold monitoring: carrying players crossing their own threshold secure the core.
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, player in Players:GetPlayers() do
				local state = PlayerState.peek(player)
				if not state or state.carried == nil or state.plotIndex == nil then
					continue
				end
				local character = player.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				local frame = thresholdCFrame(state.plotIndex :: number)
				if rootPart and rootPart:IsA("BasePart") and frame then
					-- The threshold strip lies along the plot frame's local X axis.
					local offset = frame:PointToObjectSpace(rootPart.Position)
					if math.abs(offset.X) <= 5 and math.abs(offset.Z) <= 2.5 then
						local core = state.carried :: Types.CarriedItem
						applyCarry(player, state, nil)
						secureCore(player, state, core)
					end
				end
			end
		end
	end)
end

-- Pure tag rules (spec-testable).
function StealSystem.checkTagReady(state: Types.PlayerState, now: number): (boolean, string)
	if now < state.zapperReadyAt then
		return false, "zapper on cooldown"
	end
	return true, "ok"
end

function StealSystem.tagInRange(attackerPos: Vector3, victimPos: Vector3): boolean
	return (victimPos - attackerPos).Magnitude <= Config.Zapper.Range + 2
end

-- Whether a player may grab a dropped core right now (owner-lock window).
function StealSystem.canGrabDrop(drop: BasePart, player: Player, now: number): (boolean, string)
	local lockOwner = drop:GetAttribute("LockOwner")
	local lockUntil = drop:GetAttribute("LockUntil")
	if type(lockUntil) == "number" and now < lockUntil and lockOwner ~= player.Name then
		return false, `locked for {string.format("%.1f", lockUntil - now)}s`
	end
	return true, "ok"
end

-- Shared tag resolution: knockback + drop with owner-lock + victim notify. Used by
-- the real remote path and Studio debug scenarios (phantom attacker).
function StealSystem.resolveTag(
	attackerName: string,
	attackerPos: Vector3,
	victimPlayer: Player,
	attacker: Player?
): boolean
	local victimChar = victimPlayer.Character
	local vRoot = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
	if not (vRoot and vRoot:IsA("BasePart")) then
		return false
	end
	local dir = (vRoot.Position - attackerPos) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 0, 1)
	end
	vRoot.AssemblyLinearVelocity = dir.Unit * Config.Zapper.KnockbackSpeed + Vector3.new(0, 12, 0)
	local victimState = PlayerState.peek(victimPlayer)
	if victimState and victimState.carried then
		StealSystem.dropCarried(victimPlayer, false, attacker)
	end
	Remotes.get("TagHit"):FireClient(victimPlayer, attackerName)
	print(`[StealSystem] {attackerName} tagged {victimPlayer.Name}`)
	return true
end

-- Real remote path: validates cooldown, self-tag and range before resolving.
function StealSystem.tryTag(attacker: Player, victimPlayer: Player): boolean
	local state = PlayerState.get(attacker)
	local now = os.clock()
	local readyOk, readyReason = StealSystem.checkTagReady(state, now)
	if not readyOk then
		print(`[StealSystem] {attacker.Name} tag rejected: {readyReason}`)
		return false
	end
	if victimPlayer == attacker then
		print(`[StealSystem] {attacker.Name} tag rejected: you cannot tag yourself`)
		return false
	end
	local attackerChar = attacker.Character
	local aRoot = attackerChar and attackerChar:FindFirstChild("HumanoidRootPart")
	local victimChar = victimPlayer.Character
	local vRoot = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
	if not (aRoot and vRoot and aRoot:IsA("BasePart") and vRoot:IsA("BasePart")) then
		return false
	end
	if not StealSystem.tagInRange(aRoot.Position, vRoot.Position) then
		print(
			`[StealSystem] {attacker.Name} tag rejected: out of range ({string.format(
				"%.1f",
				(vRoot.Position - aRoot.Position).Magnitude
			)} studs)`
		)
		return false
	end
	-- Thievery unlocks shorten the zapper cooldown (M8-03).
	local cooldownCut = math.min(Perks.get(SkillService.stats(state), "zapperCooldown"), 0.5)
	state.zapperReadyAt = now + Config.Zapper.Cooldown * (1 - cooldownCut)
	SkillService.addXp(attacker, "Thievery", Config.Skills.Xp.tag)
	return StealSystem.resolveTag(attacker.Name, aRoot.Position, victimPlayer, attacker)
end

-- Studio-only debug helper: hand a core to a player directly (skips the victim side,
-- which needs a second real client). Used by playtest scenarios via DebugBridge.
function StealSystem.debugCarry(player: Player, rarity: Types.Rarity): boolean
	if not RunService:IsStudio() then
		return false
	end
	local state = PlayerState.get(player)
	if state.carried ~= nil then
		return false
	end
	local core: Types.CarriedItem = { kind = "Core", rarity = rarity :: any, mutation = nil :: any }
	applyCarry(player, state, core)
	print(`[StealSystem] debug: {player.Name} now carries a {rarity} core`)
	return true
end

-- Watches a player's character for damage while carrying.
-- Watches a player's character for damage while carrying. Roblox regenerates
-- health passively, so only an actual DECREASE drops the core.
local function watchHumanoid(player: Player, humanoid: Humanoid)
	local lastHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health: number)
		local damaged = health < lastHealth - 0.01
		lastHealth = health
		if not damaged then
			return
		end
		local state = PlayerState.peek(player)
		if state and state.carried then
			StealSystem.dropCarried(player, false)
		end
	end)
end

function StealSystem.watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		watchHumanoid(player, humanoid)
	end)
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			watchHumanoid(player, humanoid)
		end
	end
end

return StealSystem
