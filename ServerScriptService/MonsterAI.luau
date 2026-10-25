--!strict
-- Monster AI (M1-12, variety pass 2026-10-18). Night forest: Fogling packs, one
-- Grove Stalker, Wisps, Spitters and a Moss Golem; they chase players outside their
-- plot safe zone and despawn at dawn. Wild zones past the ring wall keep resident
-- guardians day AND night that never leave their zone.
-- Single loop (performance): re-target and MoveTo every 0.3 s per monster.
--   Fogling  melee chaser             Stalker  telegraphed lunge
--   Wisp     snatches a carried seed  Golem    telegraphed area slam
--   Spitter  lobs spore globs that leave a toxic puddle

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Zones = require(ReplicatedStorage.Shared.Zones)

local PlayerState = require(script.Parent.PlayerState)
local DayNightCycle = require(script.Parent.DayNightCycle)
local GadgetSystem = require(script.Parent.GadgetSystem)
local FXService = require(script.Parent.FXService)
local EventService = require(script.Parent.EventService)
local PerfBudget = require(script.Parent.PerfBudget)
local SkillService = require(script.Parent.SkillService)
local CoreSystem = require(script.Parent.CoreSystem)
local MonsterBuilder = require(game.ServerStorage.Builders.MonsterBuilder)

local MonsterAI = {}

local ATTACK_RANGE = 5
local SLAM_COLOR = Color3.fromRGB(255, 150, 40)
local GLOB_COLOR = Color3.fromRGB(150, 255, 90)
local STUN_COLOR = Color3.fromRGB(255, 240, 170)

type Kind = MonsterBuilder.MonsterKind

type Monster = {
	model: Model,
	kind: Kind,
	humanoid: Humanoid,
	root: BasePart,
	lastAttack: number,
	attackCooldown: number,
	lastBountyGiven: boolean,
	lungeState: "none" | "windup" | "lunge",
	lungeUntil: number,
	baseSpeed: number,
	baseColor: Color3,
	home: Vector3?, -- zone guardians stay within the zone clearing around this point
	zoneId: string?,
	wanderAt: number,
	slamTarget: Player?,
	slamRing: BasePart?,
	stunnedUntil: number, -- M9-02 Lantern
}

local monsters: { Monster } = {}
local nightActive = false
local nightStartedAt = 0
local lastRespawnAt = 0
local stalkerSpawnedThisNight = false
local running = false
local lastKindSpawn: { [string]: number } = {}
local lastZoneSpawn: { [string]: number } = {}

local function spec(kind: Kind): any
	return (Config.Monsters :: any)[kind]
end

-- Pure helper (spec-testable): is a position inside a plot's interior?
-- The plot floor is PlotSize x PlotSize centered on the plot frame.
function MonsterAI.isInsidePlot(position: Vector3, plotCenterXZ: Vector3, plotSize: number): boolean
	local dx = math.abs(position.X - plotCenterXZ.X)
	local dz = math.abs(position.Z - plotCenterXZ.Z)
	return dx <= plotSize / 2 and dz <= plotSize / 2
end

-- Pure: is `position` inside a guardian's leash (its zone clearing plus a margin)?
function MonsterAI.inLeash(position: Vector3, home: Vector3): boolean
	local flat = Vector3.new(position.X - home.X, 0, position.Z - home.Z)
	return flat.Magnitude <= Config.Zones.Radius + 8
end

-- Pure: launch velocity that lands a free-falling glob on `to` after `flightTime`.
function MonsterAI.lobVelocity(from: Vector3, to: Vector3, flightTime: number, gravity: number): Vector3
	return (to - from) / flightTime + Vector3.new(0, 0.5 * gravity * flightTime, 0)
end

local function plotCenters(): { Vector3 }
	local centers = {}
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			if plot:IsA("Folder") and plot:FindFirstChild("Floor") then
				local pos = plot.Floor.Position
				table.insert(centers, Vector3.new(pos.X, 0, pos.Z))
			end
		end
	end
	return centers
end

-- A player is SAFE if they are inside their own plot's interior (GDD 5.6).
local function isPlayerSafe(player: Player, centers: { Vector3 }): boolean
	local state = PlayerState.peek(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or state.plotIndex == nil or not (root and root:IsA("BasePart")) then
		return false
	end
	local center = centers[(state.plotIndex :: number) + 1]
	if not center then
		return false
	end
	return MonsterAI.isInsidePlot(root.Position, center, Config.Map.PlotSize)
end

local function rootOf(player: Player): BasePart?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Closest valid target within `aggro`. Zone guardians (home set) only see players
-- inside their zone.
local function nearestTarget(from: Vector3, aggro: number, home: Vector3?): (Player?, number)
	local centers = plotCenters()
	local now = os.clock()
	local best: Player? = nil
	local bestDist = aggro
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if
			root
			and not isPlayerSafe(player, centers)
			and not GadgetSystem.isSmokeActive(player, now)
			and (home == nil or MonsterAI.inLeash(root.Position, home :: Vector3))
		then
			-- Survival unlocks (M8-03): monsters notice the player later. The
			-- effective distance grows, so they must come closer before chasing.
			local sight = player:GetAttribute("MonsterSight")
			local dist = (root.Position - from).Magnitude
				/ (1 - math.min(if type(sight) == "number" then sight else 0, 0.5))
			if dist <= bestDist then
				bestDist = dist
				best = player
			end
		end
	end
	return best, bestDist
end

-- Players hit by an area attack at `center` (alive, outside their own plot).
local function playersInRadius(center: Vector3, radius: number): { Player }
	local centers = plotCenters()
	local hit = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if
			root
			and humanoid
			and humanoid.Health > 0
			and (root.Position - center).Magnitude <= radius
			and not isPlayerSafe(player, centers)
		then
			table.insert(hit, player)
		end
	end
	return hit
end

local function damage(player: Player, amount: number)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(amount)
	end
end

local function toast(player: Player, text: string)
	Remotes.get("TutorialToast"):FireClient(player, text)
end

local function despawn(monster: Monster)
	if monster.slamRing then
		monster.slamRing:Destroy()
		monster.slamRing = nil
	end
	if monster.model.Parent then
		monster.model:Destroy()
	end
end

-- Wisp touch: a little damage and it snatches your best carried seed, then vanishes.
local function wispTouch(monster: Monster, player: Player)
	damage(player, spec("Wisp").Damage)
	monster.lastAttack = os.clock()
	local state = PlayerState.get(player)
	local taken = CoreSystem.consumeSeed(state)
	if taken == nil then
		return
	end
	local seedDef = Zones.seed(taken)
	local name = if seedDef then seedDef.name elseif taken == "grove" then "Grove Heart Seed" else "seed"
	toast(player, `A Wisp snatched your {name}!`)
	FXService.burstAt(monster.root.Position, Color3.fromRGB(170, 240, 255), 18)
	print(`[MonsterAI] Wisp stole a {taken} seed from {player.Name}`)
	despawn(monster)
end

local function meleeAttack(monster: Monster, player: Player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:TakeDamage(spec(monster.kind).Damage)
		-- Stalker recovery includes the windup (it re-lunges from a standstill).
		monster.lastAttack = os.clock()
		monster.attackCooldown = if monster.kind == "Stalker"
			then Config.Monsters.Stalker.LungeWindup + 1.5
			else Config.Monsters.Fogling.AttackCooldown
		print(`[MonsterAI] {monster.kind} hit {player.Name} ({math.floor(humanoid.Health)} HP left)`)
	end
end

-- Pure (spec-testable): the Stalker's next lunge transition. "windup" starts the
-- red telegraph (frozen in place); "lunge" starts the speed burst. nil = keep
-- the current behavior.
function MonsterAI.stalkerLungeStep(
	monsterLike: {
		kind: any,
		lungeState: any,
		lungeUntil: number,
		lastAttack: number,
		attackCooldown: number,
	},
	now: number,
	dist: number
): string?
	if monsterLike.kind ~= "Stalker" then
		return nil
	end
	local stalker = Config.Monsters.Stalker
	if
		monsterLike.lungeState == "none"
		and dist <= stalker.LungeRange
		and now - monsterLike.lastAttack >= monsterLike.attackCooldown
	then
		return "windup"
	end
	if monsterLike.lungeState == "windup" and now >= monsterLike.lungeUntil then
		return "lunge"
	end
	return nil
end

-- Pure (spec-testable): the Golem's slam. "windup" freezes it with an orange glow
-- and a ground ring; "slam" hits everyone inside the ring.
function MonsterAI.golemSlamStep(
	monsterLike: { kind: any, lungeState: any, lungeUntil: number, lastAttack: number },
	now: number,
	dist: number
): string?
	if monsterLike.kind ~= "Golem" and monsterLike.kind ~= "Warden" then
		return nil
	end
	local golem = spec(monsterLike.kind) -- the Warden boss slams by the same rules
	if
		monsterLike.lungeState == "none"
		and dist <= golem.SlamRange
		and now - monsterLike.lastAttack >= golem.SlamCooldown
	then
		return "windup"
	end
	if monsterLike.lungeState == "windup" and now >= monsterLike.lungeUntil then
		return "slam"
	end
	return nil
end

local function groundY(monster: Monster): number
	return monster.root.Position.Y - monster.humanoid.HipHeight - monster.root.Size.Y / 2
end

local function startSlam(monster: Monster, target: Player?, now: number)
	local golem = spec(monster.kind)
	monster.lungeState = "windup"
	monster.lungeUntil = now + golem.SlamWindup
	monster.slamTarget = target
	monster.humanoid:MoveTo(monster.root.Position)
	MonsterBuilder.setTelegraph(monster.model, true, SLAM_COLOR)
	local ring = Instance.new("Part")
	ring.Name = "SlamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, golem.SlamRadius * 2, golem.SlamRadius * 2)
	local pos = monster.root.Position
	ring.CFrame = CFrame.new(pos.X, groundY(monster) + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = SLAM_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.65
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = Workspace
	monster.slamRing = ring
	FXService.soundAt(pos, Config.FX.TagSound, 0.5)
end

local function finishSlam(monster: Monster, now: number)
	local golem = spec(monster.kind)
	monster.lungeState = "none"
	monster.lastAttack = now
	MonsterBuilder.setTelegraph(monster.model, false)
	if monster.slamRing then
		monster.slamRing:Destroy()
		monster.slamRing = nil
	end
	local hit = playersInRadius(monster.root.Position, golem.SlamRadius)
	local targetHit = false
	for _, player in hit do
		damage(player, golem.Damage)
		targetHit = targetHit or player == monster.slamTarget
	end
	FXService.burstAt(monster.root.Position - Vector3.new(0, 2, 0), SLAM_COLOR, 30)
	local target = monster.slamTarget
	if target and not targetHit and target.Parent then
		SkillService.addXp(target, "Survival", Config.Skills.Xp.dodge)
	end
	monster.slamTarget = nil
	print(`[MonsterAI] {monster.kind} slams ({#hit} hit)`)
end

-- Toxic puddle: damages players standing in it for a few seconds.
local function spawnPuddle(position: Vector3)
	local spitter = Config.Monsters.Spitter
	local puddle = Instance.new("Part")
	puddle.Name = "SporePuddle"
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Size = Vector3.new(0.3, spitter.SplashRadius * 2, spitter.SplashRadius * 2)
	puddle.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	puddle.Color = GLOB_COLOR
	puddle.Material = Enum.Material.Neon
	puddle.Transparency = 0.5
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CanQuery = false
	puddle.CanTouch = false
	puddle.CastShadow = false
	puddle.Parent = Workspace
	task.spawn(function()
		local ticks = math.floor(spitter.PuddleSeconds / 0.5)
		for _ = 1, ticks do
			task.wait(0.5)
			for _, player in playersInRadius(position + Vector3.new(0, 2.5, 0), spitter.SplashRadius) do
				damage(player, spitter.PuddleDps * 0.5)
			end
		end
		puddle:Destroy()
	end)
end

-- Spitter shot: a glob arcs to where the target stands NOW; keep moving to dodge.
local function lobGlob(monster: Monster, target: Player, targetRoot: BasePart)
	local spitter = Config.Monsters.Spitter
	local from = monster.root.Position + Vector3.new(0, 2, 0)
	local landing = Vector3.new(targetRoot.Position.X, groundY(monster) + 0.3, targetRoot.Position.Z)
	local glob = Instance.new("Part")
	glob.Name = "SporeGlob"
	glob.Shape = Enum.PartType.Ball
	glob.Size = Vector3.new(1.6, 1.6, 1.6)
	glob.Color = GLOB_COLOR
	glob.Material = Enum.Material.Neon
	glob.CanCollide = false
	glob.CanQuery = false
	glob.CanTouch = false
	glob.CFrame = CFrame.new(from)
	glob.AssemblyLinearVelocity = MonsterAI.lobVelocity(from, landing, spitter.ShotFlightTime, Workspace.Gravity)
	glob.Parent = Workspace
	glob:SetNetworkOwner(nil)
	monster.lastAttack = os.clock()
	task.delay(spitter.ShotFlightTime, function()
		glob:Destroy()
		local hit = playersInRadius(landing + Vector3.new(0, 2.5, 0), spitter.SplashRadius * 0.6)
		local targetHit = false
		for _, player in hit do
			damage(player, spitter.Damage)
			targetHit = targetHit or player == target
		end
		if not targetHit and target.Parent then
			SkillService.addXp(target, "Survival", Config.Skills.Xp.dodge)
		end
		FXService.burstAt(landing + Vector3.new(0, 1, 0), GLOB_COLOR, 14)
		spawnPuddle(landing)
	end)
end

local function clearMonsters(includeGuardians: boolean)
	for index = #monsters, 1, -1 do
		local monster = monsters[index]
		if includeGuardians or monster.home == nil then
			despawn(monster)
			table.remove(monsters, index)
		end
	end
end

local function spawnMonster(kind: Kind, position: Vector3, home: Vector3?, zoneId: string?): Monster
	local model = MonsterBuilder.create(kind, position)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local monster: Monster = {
		model = model,
		kind = kind,
		humanoid = humanoid,
		root = root,
		lastAttack = 0,
		attackCooldown = if kind == "Stalker"
			then Config.Monsters.Stalker.LungeWindup + 1.5
			else spec(kind).AttackCooldown or 1,
		lastBountyGiven = false,
		lungeState = "none",
		lungeUntil = 0,
		baseSpeed = spec(kind).Speed,
		baseColor = root.Color,
		home = home,
		zoneId = zoneId,
		wanderAt = 0,
		slamTarget = nil,
		slamRing = nil,
		stunnedUntil = 0,
	}
	table.insert(monsters, monster)
	return monster
end

local function forestPoint(rng: Random, minFrac: number, maxFrac: number): Vector3
	local angle = rng:NextNumber(0, 2 * math.pi)
	local radius = Config.Map.ForestRadius * rng:NextNumber(minFrac, maxFrac)
	return Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
end

local function zonePoint(rng: Random, zone: Zones.ZoneDef): Vector3
	local angle = rng:NextNumber(0, 2 * math.pi)
	local radius = Config.Zones.Radius * 0.7 * math.sqrt(rng:NextNumber())
	return Zones.center(zone) + Vector3.new(math.cos(angle) * radius, 5, math.sin(angle) * radius)
end

local function countAlive(kind: Kind?, zoneId: string?): number
	local n = 0
	for _, monster in monsters do
		if monster.model.Parent and (kind == nil or monster.kind == kind) and monster.zoneId == zoneId then
			n += 1
		end
	end
	return n
end

local function spawnFoglingPack()
	local rng = Random.new(os.clock() * 1000 + math.random(0, 1000))
	local packSize = rng:NextInteger(Config.Monsters.Fogling.PackMin, Config.Monsters.Fogling.PackMax)
	local cap = math.floor(Config.Monsters.Fogling.MaxAlive * EventService.monsterMultiplier())
	for _ = 1, packSize do
		if countAlive("Fogling", nil) >= cap then
			break
		end
		spawnMonster("Fogling", forestPoint(rng, 0.7, 0.95), nil, nil)
	end
	print(`[MonsterAI] spawned Fogling pack ({countAlive("Fogling", nil)} alive)`)
end

-- Night forest spawns: Fogling packs, one Stalker, and the variety kinds.
local function nightSpawns(now: number)
	if
		countAlive("Fogling", nil) < math.floor(Config.Monsters.Fogling.MaxAlive * EventService.monsterMultiplier())
		and now - lastRespawnAt >= Config.Monsters.Fogling.RespawnSeconds
	then
		lastRespawnAt = now
		spawnFoglingPack()
	end
	if not stalkerSpawnedThisNight and now - nightStartedAt >= Config.Monsters.Stalker.SpawnDelay then
		stalkerSpawnedThisNight = true
		local rng = Random.new(os.clock() * 1e4)
		spawnMonster("Stalker", forestPoint(rng, 0.85, 0.85), nil, nil)
		print("[MonsterAI] Grove Stalker emerges")
	end
	for _, kind: Kind in { "Wisp", "Spitter", "Golem" } :: { Kind } do
		local s = spec(kind)
		if
			now - nightStartedAt >= s.SpawnDelay
			and now - (lastKindSpawn[kind] or 0) >= s.RespawnSeconds
			and countAlive(kind, nil) < s.NightMax
		then
			lastKindSpawn[kind] = now
			spawnMonster(kind, forestPoint(Random.new(os.clock() * 1e5), 0.3, 0.9), nil, nil)
			print(`[MonsterAI] a {kind} prowls the forest`)
		end
	end
end

-- Zone guardians: always topped up (one per respawn interval), day and night.
local function zoneSpawns(now: number)
	for _, zone in Zones.list() do
		local last = lastZoneSpawn[zone.id]
		if
			countAlive(nil, zone.id) < zone.guardians
			and (last == nil or now - last >= Config.Zones.GuardianRespawnSeconds or countAlive(nil, zone.id) == 0)
		then
			lastZoneSpawn[zone.id] = now
			local rng = Random.new(os.clock() * 1e5 + zone.angle)
			-- Boot: fill the zone at once; later one at a time.
			local toSpawn = if last == nil then zone.guardians else 1
			for _ = 1, toSpawn do
				spawnMonster(zone.guardian :: Kind, zonePoint(rng, zone), Zones.center(zone), zone.id)
			end
		end
	end
end

-- Pure (M9-02): is a monster at `position` caught by a Lantern flash at `origin`?
function MonsterAI.inLanternRange(position: Vector3, origin: Vector3): boolean
	return (position - origin).Magnitude <= Config.Gadgets.Lantern.radius
end

-- Lantern flash: stun every monster in range, cancelling windups. Returns the count.
local function stunAround(_player: Player, origin: Vector3): number
	local now = os.clock()
	local count = 0
	for _, monster in monsters do
		if monster.model.Parent and MonsterAI.inLanternRange(monster.root.Position, origin) then
			monster.stunnedUntil = now + Config.Gadgets.Lantern.stunSeconds
			if monster.lungeState ~= "none" then
				monster.lungeState = "none"
				monster.humanoid.WalkSpeed = monster.baseSpeed
				monster.slamTarget = nil
				if monster.slamRing then
					monster.slamRing:Destroy()
					monster.slamRing = nil
				end
			end
			monster.humanoid:MoveTo(monster.root.Position)
			MonsterBuilder.setTelegraph(monster.model, true, STUN_COLOR)
			count += 1
		end
	end
	return count
end

-- One monster's tick: telegraphs, movement and its attack.
local function stepMonster(monster: Monster, now: number)
	if monster.stunnedUntil > 0 then
		if now < monster.stunnedUntil then
			return -- dazzled: frozen, no attacks
		end
		monster.stunnedUntil = 0
		MonsterBuilder.setTelegraph(monster.model, false)
	end
	local aggro = spec(monster.kind).AggroRange or Config.Monsters.Fogling.AggroRange
	local target, dist = nearestTarget(monster.root.Position, aggro, monster.home)

	-- Stalker lunge state machine (GDD 5.6): windup freezes + glows red, then a
	-- speed burst; the loop re-targets every tick during the burst.
	local transition = MonsterAI.stalkerLungeStep(monster, now, dist)
	if transition == "windup" then
		monster.lungeState = "windup"
		monster.lungeUntil = now + Config.Monsters.Stalker.LungeWindup
		MonsterBuilder.setTelegraph(monster.model, true)
		FXService.soundAt(monster.root.Position, Config.FX.TagSound, 0.6) -- telegraph beep
		print(`[MonsterAI] Grove Stalker telegraphs a lunge`)
	elseif transition == "lunge" then
		monster.lungeState = "lunge"
		monster.lungeUntil = now + Config.Monsters.Stalker.LungeDuration
		monster.humanoid.WalkSpeed = monster.baseSpeed * Config.Monsters.Stalker.LungeSpeedMultiplier
		MonsterBuilder.setTelegraph(monster.model, false)
		print(`[MonsterAI] Grove Stalker lunges!`)
	end
	local slam = MonsterAI.golemSlamStep(monster, now, dist)
	if slam == "windup" then
		startSlam(monster, target, now)
	elseif slam == "slam" then
		finishSlam(monster, now)
	end
	if monster.lungeState == "windup" then
		return -- frozen while telegraphing
	end

	local targetRoot = target and rootOf(target)
	if target and targetRoot then
		-- Never chase INTO a plot interior: stop at the plot edge instead.
		local chasePoint = targetRoot.Position
		for _, center in plotCenters() do
			if MonsterAI.isInsidePlot(chasePoint, center, Config.Map.PlotSize) then
				local dir = (chasePoint - center) * Vector3.new(1, 0, 1)
				dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
				chasePoint = center + dir * (Config.Map.PlotSize / 2 + 2)
				chasePoint = Vector3.new(chasePoint.X, monster.root.Position.Y, chasePoint.Z)
				break
			end
		end
		if monster.kind == "Spitter" then
			-- Keeps its distance: closes in only when out of range, then lobs.
			local spitter = Config.Monsters.Spitter
			if dist > spitter.ShotRange * 0.6 then
				monster.humanoid:MoveTo(chasePoint)
			else
				monster.humanoid:MoveTo(monster.root.Position)
			end
			if dist <= spitter.ShotRange and now - monster.lastAttack >= spitter.ShotCooldown then
				lobGlob(monster, target, targetRoot)
			end
		else
			monster.humanoid:MoveTo(chasePoint)
			if dist <= ATTACK_RANGE and now - monster.lastAttack >= monster.attackCooldown then
				if monster.kind == "Wisp" then
					wispTouch(monster, target)
				elseif monster.kind ~= "Golem" and monster.kind ~= "Warden" then -- slammers only slam
					meleeAttack(monster, target)
				end
			end
		end
	elseif monster.home and now >= monster.wanderAt then
		-- Guardians idle around their zone (and walk home after a chase).
		monster.wanderAt = now + Random.new(os.clock() * 1e4):NextNumber(3, 6)
		local rng = Random.new(os.clock() * 1e5)
		local angle = rng:NextNumber(0, 2 * math.pi)
		local radius = Config.Zones.Radius * 0.6 * math.sqrt(rng:NextNumber())
		monster.humanoid:MoveTo(
			(monster.home :: Vector3) + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		)
	end
	if monster.lungeState == "lunge" and now >= monster.lungeUntil then
		monster.lungeState = "none"
		monster.humanoid.WalkSpeed = monster.baseSpeed
	end

	-- Dead monsters pay a proximity bounty to the closest player (M1 placeholder).
	if monster.humanoid.Health <= 0 and not monster.lastBountyGiven then
		monster.lastBountyGiven = true
		local proximityPlayer = target
		if not proximityPlayer then
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root and (root.Position - monster.root.Position).Magnitude < 40 then
					proximityPlayer = player
					break
				end
			end
		end
		if proximityPlayer then
			local state = PlayerState.get(proximityPlayer :: Player)
			local bounty = Perks.scaledReward(
				Config.Monsters.Bounty,
				state.rebirths,
				PlayerState.incomeRate(state),
				Config.Monsters.BountySeconds
			)
			PlayerState.addCash(state, bounty)
			print(`[MonsterAI] {proximityPlayer.Name} earned a {bounty} cash bounty`)
		end
		task.delay(1, function()
			despawn(monster)
		end)
	end
end

-- M9-03 boss API (BossService): one Grove Warden at a time.
local warden: Monster? = nil

function MonsterAI.spawnWarden(position: Vector3)
	if warden and warden.model.Parent then
		return
	end
	warden = spawnMonster("Warden", position, nil, nil)
	print("[MonsterAI] THE GROVE WARDEN RISES")
end

function MonsterAI.wardenAlive(): boolean
	return warden ~= nil and (warden :: Monster).model.Parent ~= nil
end

-- Each lit beacon slows the Warden a little more.
function MonsterAI.setWardenBeacons(lit: number)
	local w = warden
	if w and w.model.Parent then
		w.baseSpeed = Config.Monsters.Warden.Speed * math.max(0.3, 1 - Config.Monsters.Warden.SlowPerBeacon * lit)
		if w.lungeState ~= "lunge" then
			w.humanoid.WalkSpeed = w.baseSpeed
		end
	end
end

function MonsterAI.banishWarden()
	local w = warden
	warden = nil
	if w and w.model.Parent then
		FXService.burstAt(w.root.Position, Color3.fromRGB(190, 90, 255), 60)
		despawn(w)
	end
end

-- Main loop: spawn control, every monster's step, dead-model cleanup.
local function loop()
	while running do
		task.wait(0.3)
		local spotStart = os.clock()
		local now = os.clock()
		for index = #monsters, 1, -1 do
			if not monsters[index].model.Parent then
				table.remove(monsters, index)
			end
		end
		if nightActive then
			nightSpawns(now)
		end
		zoneSpawns(now)
		for _, monster in monsters do
			if monster.model.Parent then
				stepMonster(monster, now)
			end
		end
		PerfBudget.spot("MonsterAI", os.clock() - spotStart)
	end
end

function MonsterAI.init()
	running = true
	GadgetSystem.onLantern(stunAround)
	DayNightCycle.onPhaseStarted(function(phase)
		if phase == "Night" then
			nightActive = true
			nightStartedAt = os.clock()
			stalkerSpawnedThisNight = false
			lastRespawnAt = 0
			table.clear(lastKindSpawn)
			spawnFoglingPack()
		else
			nightActive = false
			print("[MonsterAI] dawn: forest monsters fade away (zone guardians stay)")
			clearMonsters(false)
		end
	end)

	task.spawn(loop)

	Players.PlayerRemoving:Connect(function(player)
		-- Drop their state references; monsters re-target naturally.
		local state = PlayerState.peek(player)
		if state then
			state.carried = nil
		end
	end)
end

return MonsterAI
