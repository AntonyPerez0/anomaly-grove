--!strict
-- Defenses (M3-01): auto-turrets that shoot rival raiders. Server-authoritative
-- targeting: the owner is never a target, smoke clouds blind the turret, players
-- inside their own plot are safe.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local PlotSystem = require(script.Parent.PlotSystem)
local GadgetSystem = require(script.Parent.GadgetSystem)
local PerfBudget = require(script.Parent.PerfBudget)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)
local TurretBuilder = require(game.ServerStorage.Builders.TurretBuilder)
local DefenseBuilder = require(game.ServerStorage.Builders.DefenseBuilder)

local DefenseSystem = {}

-- (player) -> { { kind, slot } } mirror comes from state.defenses.

-- Count defenses of one kind in a state.
local function countKind(state: Types.PlayerState, kind: Types.DefenseKind): number
	local count = 0
	for _, defense in state.defenses do
		if defense.kind == kind then
			count += 1
		end
	end
	return count
end

local function plotFolder(index: number): Folder?
	local grove = Workspace:FindFirstChild("AnomalyGrove")
	local plots = grove and grove:FindFirstChild("Plots")
	local folder = plots and plots:FindFirstChild("Plot" .. (index + 1))
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

-- Pure targeting rule: can a turret owned by `owner` shoot `target` right now?
-- (Character presence is the caller's feasibility check; this is the policy.)
function DefenseSystem.canTarget(
	target: Player,
	owner: Player,
	targetState: Types.PlayerState?,
	plotIndex: number?,
	smokeActive: boolean,
	_now: number
): (boolean, string)
	if target == owner then
		return false, "owner"
	end
	if smokeActive then
		return false, "smoked"
	end
	if targetState and targetState.plotIndex ~= nil and targetState.plotIndex == plotIndex then
		return false, "inside own plot"
	end
	return true, "ok"
end

-- Total defense capacity: base slots + rebirth bonus, capped by the slot bonus cap.
local function defenseCapacity(state: Types.PlayerState): number
	return Config.Plot.DefenseBaseSlots
		+ math.min(state.rebirths, Config.Rebirth.MaxDefenseSlotBonus)
		+ math.floor(Perks.get(SkillService.stats(state), "defenseSlots")) -- Guarding + Bulwark (M8)
end

-- Owner's defense multipliers (Guarding skill + upgrades), or neutral without a state.
local function ownerStats(owner: Player): Perks.Stats
	local state = PlayerState.peek(owner)
	return if state then SkillService.stats(state) else {}
end

-- Guarding XP for a hit on a raider: at most once per raider per second per owner.
local lastGuardXp: { [Player]: { [Player]: number } } = {}
local function guardXp(owner: Player, target: Player, now: number)
	local perOwner = lastGuardXp[owner] or {}
	lastGuardXp[owner] = perOwner
	if now - (perOwner[target] or 0) >= 1 then
		perOwner[target] = now
		SkillService.addXp(owner, "Guarding", Config.Skills.Xp.defenseHit)
	end
end

-- Discounted charge + Commerce XP for a defense purchase. Returns the price paid or nil.
local function charge(player: Player, state: Types.PlayerState, basePrice: number): number?
	local price = Perks.discounted(basePrice, SkillService.stats(state))
	if not PlayerState.spendCash(state, price) then
		return nil
	end
	SkillService.addCommerceXp(player, price)
	return price
end

-- Corner anchor: invisible part created on demand (purchase and restore share this).
local function ensureCornerAnchor(folder: Folder, slot: number): BasePart
	local anchorName = "TurretSlot" .. slot
	local floor = folder:FindFirstChild("Floor") :: BasePart
	local existing = folder:FindFirstChild(anchorName)
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local created = Instance.new("Part")
	created.Name = anchorName
	created.Size = Vector3.new(2, 0.4, 2)
	created.Transparency = 1
	created.Anchored = true
	created.CanCollide = false
	created.CanQuery = false
	-- Corners: alternate between the two rear corners of the plot.
	local inset = Config.Map.PlotSize * 0.34 -- ~30 studs on a 90-stud plot
	local offsetX = if slot % 2 == 0 then inset else -inset
	local offsetZ = if slot <= 2 then inset else -inset
	created.CFrame = floor.CFrame * CFrame.new(offsetX, 0.5, offsetZ)
	created.Parent = folder
	return created
end

-- Purchase a turret for the caller's plot (placed on the next free corner).
function DefenseSystem.buyTurret(player: Player): boolean
	local state = PlayerState.get(player)
	if state.plotIndex == nil then
		print(`[DefenseSystem] {player.Name} turret purchase rejected: claim a plot first`)
		return false
	end
	local owned = 0
	for _, defense in state.defenses do
		if defense.kind == "Turret" then
			owned += 1
		end
	end
	if owned >= Config.Turret.MaxPerPlot then
		print(`[DefenseSystem] {player.Name} turret purchase rejected: turret limit reached`)
		return false
	end
	if #state.defenses >= defenseCapacity(state) then
		print(`[DefenseSystem] {player.Name} turret purchase rejected: no free defense slot (rebirth for more)`)
		return false
	end
	local price = charge(player, state, Config.Prices.Turret)
	if not price then
		print(`[DefenseSystem] {player.Name} turret purchase rejected: not enough cash`)
		return false
	end
	local slot = #state.defenses + 1
	table.insert(state.defenses, { kind = "Turret", slot = slot })
	player:SetAttribute("DefenseCount", #state.defenses)
	local plotFolderInst = plotFolder(state.plotIndex :: number)
	if not plotFolderInst then
		return false
	end
	TurretBuilder.create(ensureCornerAnchor(plotFolderInst :: any, slot), slot)
	print(`[DefenseSystem] {player.Name} placed turret {owned + 1} for {price} (capacity {defenseCapacity(state)})`)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Shared purchase gate for the gap/approach defenses (laser, traps).
local function buyGapDefense(player: Player, kind: Types.DefenseKind): boolean
	local state = PlayerState.get(player)
	if state.plotIndex == nil then
		print(`[DefenseSystem] {player.Name} {kind} purchase rejected: claim a plot first`)
		return false
	end
	local maxForKind = if kind == "LaserDoor" then 1 else Config.TrapTile.MaxPerPlot
	if countKind(state, kind) >= maxForKind then
		print(`[DefenseSystem] {player.Name} {kind} purchase rejected: limit ({maxForKind}) reached`)
		return false
	end
	if #state.defenses >= defenseCapacity(state) then
		print(`[DefenseSystem] {player.Name} {kind} purchase rejected: no free defense slot (rebirth for more)`)
		return false
	end
	local price = charge(player, state, (Config.Prices :: any)[kind :: string] :: number)
	if not price then
		print(`[DefenseSystem] {player.Name} {kind} purchase rejected: not enough cash`)
		return false
	end
	local slot = #state.defenses + 1
	table.insert(state.defenses, { kind = kind, slot = slot })
	player:SetAttribute("DefenseCount", #state.defenses)
	DefenseSystem.spawnDefense(state.plotIndex :: number, kind, slot)
	print(`[DefenseSystem] {player.Name} placed {kind} for {price} (capacity {defenseCapacity(state)})`)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Corner anchors: invisible anchor parts created on demand (purchase + restore share this).
function DefenseSystem.spawnDefense(plotIndex: number, kind: Types.DefenseKind, slot: number)
	local folder = plotFolder(plotIndex)
	if not folder then
		return
	end
	if kind == "Turret" then
		TurretBuilder.create(ensureCornerAnchor(folder :: any, slot), slot)
	elseif kind == "LaserDoor" then
		local threshold = folder:FindFirstChild("Threshold")
		if threshold and threshold:IsA("BasePart") and not folder:FindFirstChild("LaserDoor") then
			DefenseBuilder.createLaserDoor(threshold :: BasePart)
		end
	elseif kind == "TrapTile" then
		-- Traps spread across the approach edge so several don't stack.
		local anchorName = "TrapSlot" .. slot
		local anchor = folder:FindFirstChild(anchorName)
		local anchorPart: BasePart
		if anchor and anchor:IsA("BasePart") then
			anchorPart = anchor
		else
			local created = Instance.new("Part")
			created.Name = anchorName
			created.Size = Vector3.new(5, 0.3, 5)
			created.Anchored = true
			created.CanCollide = false
			created.CanQuery = false
			local spreadX = (slot - 2) * 8 -- slots 1..3 -> x -8, 0, 8
			created.CFrame = (folder :: any).Floor.CFrame * CFrame.new(spreadX, 0.4, -20)
			created.Parent = folder
			anchorPart = created
		end
		DefenseBuilder.createTrapTile(anchorPart, slot)
	end
end

-- Apply one damage/stun hit from a turret to a target player.
function DefenseSystem.applyHit(target: Player, damage: number, stunSeconds: number)
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid:TakeDamage(damage)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		-- Stun: zero the speed briefly, then restore (skip if already stunned).
		if root:GetAttribute("StunnedUntil") == nil or os.clock() >= (root:GetAttribute("StunnedUntil") :: number) then
			local base = humanoid.WalkSpeed
			root:SetAttribute("StunnedUntil", os.clock() + stunSeconds)
			root:SetAttribute("PreStunSpeed", base)
			humanoid.WalkSpeed = 0
			task.delay(stunSeconds, function()
				local liveCharacter = target.Character
				local liveRoot = liveCharacter and liveCharacter:FindFirstChild("HumanoidRootPart")
				if liveRoot and liveRoot:GetAttribute("StunnedUntil") ~= nil then
					liveRoot:SetAttribute("StunnedUntil", nil)
					local liveHumanoid = liveCharacter and liveCharacter:FindFirstChildOfClass("Humanoid")
					if liveHumanoid then
						liveHumanoid.WalkSpeed = liveRoot:GetAttribute("PreStunSpeed") :: number
					end
				end
			end)
		end
	end
	print(`[DefenseSystem] turret hit {target.Name} ({damage} dmg, {stunSeconds}s stun)`)
end

-- Turret tick: aim + shoot. Runs on the 0.5 s cadence per turret.
local function turretTick(turretModel: Model, owner: Player, now: number)
	local head = turretModel.PrimaryPart
	if not head then
		return
	end
	local best: Player? = nil
	local bestDist = Config.Turret.Range
	for _, target in Players:GetPlayers() do
		local targetState = PlayerState.peek(target)
		local ok = DefenseSystem.canTarget(
			target,
			owner,
			targetState,
			targetState and targetState.plotIndex or nil,
			GadgetSystem.isSmokeActive(target, now),
			now
		)
		if ok then
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local dist = (root.Position - head.Position).Magnitude
				if dist <= bestDist then
					bestDist = dist
					best = target
				end
			end
		end
	end
	if best then
		local root = best.Character and best.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			TurretBuilder.aim(turretModel, root.Position)
			local stats = ownerStats(owner)
			DefenseSystem.applyHit(
				best :: Player,
				Config.Turret.DamagePerSecond
					* Config.Turret.TickSeconds
					* (1 + Perks.get(stats, "defenseDamage") + Perks.get(stats, "turretDamage")),
				Config.Turret.StunSeconds
			)
			guardXp(owner, best :: Player, now)
		end
	end
end

-- Root a player in place for `seconds` (trap mechanic): zero speed, then restore.
function DefenseSystem.rootPlayer(target: Player, seconds: number)
	local character = target.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then
		return
	end
	if root:GetAttribute("RootedUntil") ~= nil and os.clock() < (root:GetAttribute("RootedUntil") :: number) then
		return -- already rooted
	end
	local base = humanoid.WalkSpeed
	root:SetAttribute("RootedUntil", os.clock() + seconds)
	root:SetAttribute("PreRootSpeed", base)
	humanoid.WalkSpeed = 0
	task.delay(seconds, function()
		local liveCharacter = target.Character
		local liveRoot = liveCharacter and liveCharacter:FindFirstChild("HumanoidRootPart")
		if liveRoot and liveRoot:GetAttribute("RootedUntil") ~= nil then
			liveRoot:SetAttribute("RootedUntil", nil)
			local liveHumanoid = liveCharacter and liveCharacter:FindFirstChildOfClass("Humanoid")
			if liveHumanoid then
				liveHumanoid.WalkSpeed = liveRoot:GetAttribute("PreRootSpeed") :: number
			end
		end
	end)
end

-- Laser door damage tick: hurts non-owner players crossing the owner's gap.
-- Pure geometry gate, unit-testable without a world:
function DefenseSystem.isInLaserBeam(beam: BasePart, worldPos: Vector3): boolean
	local offset = beam.CFrame:PointToObjectSpace(worldPos)
	return math.abs(offset.X) <= 1.5 and math.abs(offset.Y) <= 3 and math.abs(offset.Z) <= 4.5
end

local function laserTick(owner: Player, beam: BasePart, now: number)
	local tuning = Config.LaserDoor
	for _, target in Players:GetPlayers() do
		if target == owner then
			continue
		end
		if GadgetSystem.isSmokeActive(target, now) then
			continue
		end
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			continue
		end
		if DefenseSystem.isInLaserBeam(beam, root.Position) then
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local stats = ownerStats(owner)
				humanoid:TakeDamage(
					tuning.DamagePerSecond
						* tuning.TickSeconds
						* (1 + Perks.get(stats, "defenseDamage") + Perks.get(stats, "laserDamage"))
				)
				guardXp(owner, target, now)
				print(`[DefenseSystem] laser burned {target.Name} ({math.floor(humanoid.Health)} HP left)`)
			end
		end
	end
end

-- Trap trigger: root + damage the first non-owner player in radius, then recharge.
-- Pure geometry gate, unit-testable without a world:
function DefenseSystem.isInTrapRadius(platePos: Vector3, rootPos: Vector3): boolean
	return (rootPos - platePos).Magnitude <= Config.TrapTile.TriggerRadius
end

local function trapTick(owner: Player, trapModel: Model, now: number)
	if trapModel:GetAttribute("Recharging") == true then
		return
	end
	local plate = trapModel.PrimaryPart
	if not plate then
		return
	end
	for _, target in Players:GetPlayers() do
		if target == owner then
			continue
		end
		local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			continue
		end
		if DefenseSystem.isInTrapRadius(plate.Position, root.Position) then
			local stats = ownerStats(owner)
			DefenseSystem.rootPlayer(target, Config.TrapTile.RootSeconds * (1 + Perks.get(stats, "trapRoot")))
			local humanoid = target.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:TakeDamage(Config.TrapTile.Damage * (1 + Perks.get(stats, "defenseDamage")))
			end
			guardXp(owner, target, now)
			local recharge = Config.TrapTile.RechargeSeconds * (1 - math.min(Perks.get(stats, "trapRecharge"), 0.5))
			trapModel:SetAttribute("Recharging", true)
			trapModel:SetAttribute("RechargeUntil", now + recharge)
			DefenseBuilder.setTrapRecharging(trapModel, true)
			task.delay(recharge, function()
				if trapModel.Parent then
					trapModel:SetAttribute("Recharging", false)
					DefenseBuilder.setTrapRecharging(trapModel, false)
				end
			end)
			print(
				`[DefenseSystem] trap rooted {target.Name} ({Config.TrapTile.RootSeconds}s, {Config.TrapTile.Damage} dmg)`
			)
			return
		end
	end
end

-- Boot: remotes + all defense loops. Call once from Main.server.
function DefenseSystem.init()
	task.spawn(function()
		local buyRemote = Remotes.get("BuyTurret")
		buyRemote.OnServerEvent:Connect(function(player)
			DefenseSystem.buyTurret(player)
		end)
		local laserRemote = Remotes.get("BuyLaserDoor")
		laserRemote.OnServerEvent:Connect(function(player)
			buyGapDefense(player, "LaserDoor")
		end)
		local trapRemote = Remotes.get("BuyTrapTile")
		trapRemote.OnServerEvent:Connect(function(player)
			buyGapDefense(player, "TrapTile")
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Turret.TickSeconds)
			local spotStart = os.clock()
			local now = os.clock()
			local grove = Workspace:FindFirstChild("AnomalyGrove")
			local plots = grove and grove:FindFirstChild("Plots")
			if not plots then
				continue
			end
			for _, plot in plots:GetChildren() do
				local plotIndex = plot:GetAttribute("PlotIndex")
				if type(plotIndex) ~= "number" then
					continue
				end
				local ownerState = PlotSystem.stateAt(plotIndex :: number)
				if not ownerState or not ownerState.player then
					continue
				end
				for _, child in plot:GetChildren() do
					if child:IsA("Model") and string.match(child.Name, "^Turret%d+$") then
						turretTick(child, ownerState.player :: Player, now)
					end
				end
			end
			PerfBudget.spot("TurretSweep", os.clock() - spotStart)
		end
	end)

	-- Laser + trap sweep: same cadence, shared with the turret heartbeat.
	task.spawn(function()
		while true do
			task.wait(Config.LaserDoor.TickSeconds)
			local spotStart = os.clock()
			local now = os.clock()
			local grove = Workspace:FindFirstChild("AnomalyGrove")
			local plots = grove and grove:FindFirstChild("Plots")
			if not plots then
				continue
			end
			for _, plot in plots:GetChildren() do
				local plotIndex = plot:GetAttribute("PlotIndex")
				if type(plotIndex) ~= "number" then
					continue
				end
				local ownerState = PlotSystem.stateAt(plotIndex :: number)
				if not ownerState or not ownerState.player then
					continue
				end
				local owner = ownerState.player :: Player
				local laserModel = plot:FindFirstChild("LaserDoor")
				if laserModel then
					local beam = laserModel.PrimaryPart
					if beam and beam:IsA("BasePart") then
						laserTick(owner, beam, now)
					end
				end
				for _, child in plot:GetChildren() do
					if child:IsA("Model") and string.match(child.Name, "^TrapTile%d+$") then
						trapTick(owner, child, now)
					end
				end
			end
			PerfBudget.spot("GapSweep", os.clock() - spotStart)
		end
	end)
end

return DefenseSystem
