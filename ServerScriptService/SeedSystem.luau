--!strict
-- Forest seed nodes: harvesting (prompt hold on PC, HarvestSeed remote on mobile),
-- seed backpack with a cap, and node respawns at new spots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)
local SeedNodeBuilder = require(game.ServerStorage.Builders.SeedNodeBuilder)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)
local DayNightCycle = require(script.Parent.DayNightCycle)
local TutorialService = require(script.Parent.TutorialService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Zones = require(ReplicatedStorage.Shared.Zones)

local SeedSystem = {}

local FOLDER_NAME = "SeedNodes"

local function nodesFolder(): Folder
	local root = Workspace:FindFirstChild("AnomalyGrove")
	if not root then
		error("MapBuilder.build() must run before SeedSystem.init()", 2)
	end
	local folder = root:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = root
	return folder
end

local function normalizePrompt(prompt: ProximityPrompt)
	-- Builders run in Edit mode with a possibly stale cached Config; re-assert the
	-- current values at server boot so prompts are always live-correct.
	prompt.HoldDuration = Config.Seeds.HarvestTime
	prompt.MaxActivationDistance = Config.Seeds.HarvestDistance
	prompt.RequiresLineOfSight = false
end

local function wireNode(node: BasePart)
	local prompt = node:FindFirstChild("HarvestPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		normalizePrompt(prompt)
		prompt.Triggered:Connect(function(player)
			SeedSystem.tryHarvest(player, node)
		end)
	end
end

-- Server-authoritative harvest. The node must still exist (parented to SeedNodes).
function SeedSystem.tryHarvest(player: Player, node: BasePart): boolean
	if not node.Parent or node.Parent.Name ~= FOLDER_NAME then
		return false -- node already harvested this frame
	end
	local harvestPosition = node.Position
	-- Reach (2026-10-18 audit): prompts can be fired from anywhere by exploits.
	local reachRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if
		not (reachRoot and reachRoot:IsA("BasePart"))
		or (reachRoot.Position - harvestPosition).Magnitude > Config.Seeds.HarvestDistance + 4
	then
		return false
	end
	local state = PlayerState.get(player)
	local stats = SkillService.stats(state)
	-- Foraging grows the seed bag (M8-03): 3 -> 10 at level 99.
	local capacity = Config.Seeds.MaxCarriedSeeds + math.floor(Perks.get(stats, "seedBag"))
	if PlayerState.seedCount(state) >= capacity then
		print(`[SeedSystem] {player.Name} harvest rejected: seed backpack full`)
		return false
	end
	-- Wild-zone seeds need a Foraging level (2026-10-18).
	local zoneSeedId = node:GetAttribute("ZoneSeed")
	local zoneSeed, zone = Zones.seed(if type(zoneSeedId) == "string" then zoneSeedId else "")
	if zone and not Zones.canHarvest(zone, SkillService.level(state, "Foraging")) then
		Remotes.get("TutorialToast"):FireClient(player, `{zone.seed.name}s need Foraging {zone.foraging}`)
		return false
	end
	local prompt = node:FindFirstChild("HarvestPrompt")
	local isMeteor = prompt ~= nil and prompt:IsA("ProximityPrompt") and prompt.ObjectText == "Meteor Seed"
	node:Destroy()
	if zoneSeed and zone then
		PlayerState.addZoneSeed(state, zoneSeed.id, 1)
		print(`[SeedSystem] {player.Name} harvested a {zoneSeed.name} in {zone.name}`)
		task.delay(Config.Zones.NodeRespawnSeconds, function()
			SeedSystem.spawnZoneNode(zone)
		end)
	elseif node.Name == "GroveHeartNode" then
		-- Grove Heart seeds are the boosted kind: they plant into cores that roll
		-- mutations at the night chance around the clock (M3-03). Session-only.
		state.groveSeeds += 1
		player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
		print(`[SeedSystem] {player.Name} harvested a GROVE HEART seed ({state.groveSeeds} carried)`)
	else
		state.seedsCarried += 1
		player:SetAttribute("SeedsCarried", state.seedsCarried)
		print(`[SeedSystem] {player.Name} harvested a seed ({state.seedsCarried}/{Config.Seeds.MaxCarriedSeeds})`)
		-- The forest never runs dry: respawn this node at a new spot after the delay.
		-- Grove Heart nodes do not respawn: their cohort lives one night.
		task.delay(Config.Seeds.NodeRespawnSeconds, function()
			SeedSystem.spawnNode()
		end)
	end
	-- Foraging perks (M8-03): a chance of a free extra seed, and a cash bonus worth
	-- a few seconds of your income per harvest.
	if node.Name == "SeedNode" and PlayerState.seedCount(state) < capacity then
		if math.random() < Perks.get(stats, "doubleSeed") then
			state.seedsCarried += 1
			player:SetAttribute("SeedsCarried", state.seedsCarried)
		end
	end
	local bonusSeconds = Perks.get(stats, "harvestCash")
	if bonusSeconds > 0 then
		local rate = player:GetAttribute("IncomeRate")
		if type(rate) == "number" and rate > 0 then
			PlayerState.addCash(state, math.floor(rate * bonusSeconds))
		end
	end
	local xp = if zone
		then Config.Skills.Xp.zoneHarvest
		elseif isMeteor then Config.Skills.Xp.meteorHarvest
		elseif node.Name == "GroveHeartNode" then Config.Skills.Xp.groveHarvest
		else Config.Skills.Xp.harvest
	SkillService.addXp(player, "Foraging", xp)
	FXService.harvestAt(harvestPosition)
	TutorialService.onHarvested(player)
	QuestService.record(player, "harvest")
	return true
end

-- Wild-zone seed node at a random spot in the zone clearing (2026-10-18).
function SeedSystem.spawnZoneNode(zone: Zones.ZoneDef): BasePart
	local rng = Random.new(os.clock() * 1e5 + zone.angle)
	local angle = rng:NextNumber(0, 2 * math.pi)
	local radius = Config.Zones.Radius * math.sqrt(rng:NextNumber(0.05, 0.6))
	local position = Zones.center(zone) + Vector3.new(math.cos(angle) * radius, 3.5, math.sin(angle) * radius)
	local node = SeedNodeBuilder.createZoneNode(position, zone)
	wireNode(node)
	return node
end

function SeedSystem.spawnNode(): BasePart
	local node = SeedNodeBuilder.createNode(SeedNodeBuilder.randomForestPosition(Random.new(os.clock() * 1000)))
	wireNode(node)
	return node
end

-- Grove Heart cohort (M3-03): 3 mutation-flavored nodes at the exact map center.
local GROVE_FLAVORS: { string } = { "Gold", "Void", "Celestial" }

function SeedSystem.spawnGroveNodes(): number
	SeedSystem.despawnGroveNodes()
	local count = Config.GroveHeart.NodeCount
	local flavors = Config.Mutations
	local spawned = 0
	for i = 1, count do
		local angle = (i - 1) * (2 * math.pi / count)
		local radius = Config.GroveHeart.SpreadRadius
		local position = Vector3.new(math.cos(angle) * radius, 3.5, math.sin(angle) * radius)
		local flavor = GROVE_FLAVORS[((i - 1) % #GROVE_FLAVORS) + 1]
		if not flavors[flavor] then
			flavor = "Gold"
		end
		local node = SeedNodeBuilder.createGroveNode(position, flavor)
		wireNode(node)
		spawned += 1
	end
	print(`[SeedSystem] Grove Heart awakened: {spawned} mutated seed nodes at map center`)
	return spawned
end

-- Meteor Shower (M6-04): a boosted Grove Heart seed wherever a meteor lands. Same
-- node kind as the night cohort, so harvest/plant rules are unchanged; the next
-- night's Grove Heart refresh clears any left over.
function SeedSystem.spawnMeteorNode(position: Vector3, flavor: string)
	local node = SeedNodeBuilder.createGroveNode(position, if Config.Mutations[flavor] then flavor else "Gold")
	local prompt = node:FindFirstChild("HarvestPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ObjectText = "Meteor Seed"
	end
	wireNode(node)
end

function SeedSystem.despawnGroveNodes(): number
	local removed = 0
	for _, child in nodesFolder():GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("GroveHeart") == true then
			child:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		print(`[SeedSystem] Grove Heart faded: {removed} nodes despawned at daybreak`)
	end
	return removed
end

local function nearestNode(from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, child in nodesFolder():GetChildren() do
		if child:IsA("BasePart") then
			local dist = (child.Position - from).Magnitude
			if dist < bestDist then
				bestDist = dist
				best = child
			end
		end
	end
	return best
end

-- Wire prompt behavior on every existing node and keep the forest stocked.
-- Call once from Main.server.
function SeedSystem.init()
	for _, node in nodesFolder():GetChildren() do
		if node:IsA("BasePart") then
			wireNode(node)
		end
	end

	-- Mobile button path: harvest the nearest node the server can verify by distance.
	task.spawn(function()
		local harvestRemote = Remotes.get("HarvestSeed")
		harvestRemote.OnServerEvent:Connect(function(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				return
			end
			local node = nearestNode(root.Position)
			if node and (node.Position - root.Position).Magnitude <= Config.Seeds.HarvestDistance then
				SeedSystem.tryHarvest(player, node)
			end
		end)
	end)

	-- Self-heal: if fewer nodes exist than the minimum (builder not run, or stale place),
	-- top the forest up so "MinNodes active" always holds.
	local count = 0
	for _, child in nodesFolder():GetChildren() do
		if child:IsA("BasePart") then
			count += 1
		end
	end
	for _ = count, Config.Seeds.MinNodes - 1 do
		SeedSystem.spawnNode()
	end
	-- Wild zones: start each one stocked (boot only; harvests respawn their node).
	for _, child in nodesFolder():GetChildren() do
		if child:GetAttribute("ZoneSeed") ~= nil then
			child:Destroy() -- stale nodes saved into the place
		end
	end
	for _, zone in Zones.list() do
		for _ = 1, Config.Zones.NodesPerZone do
			SeedSystem.spawnZoneNode(zone)
		end
	end

	-- Grove Heart (M3-03): nodes exist at night only, with a beacon at map center.
	-- Registered before DayNightCycle.init announces "Day" in Main's order, so the
	-- boot "Day" call is a harmless no-op despawn.
	DayNightCycle.onPhaseStarted(function(phase)
		if phase == "Night" then
			SeedSystem.spawnGroveNodes()
		else
			SeedSystem.despawnGroveNodes()
		end
	end)
end

return SeedSystem
