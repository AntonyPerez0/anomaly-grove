--!strict
-- Grove Warden boss night (M9-03, inspired by 99 Nights / Steal An Egg boss
-- events). On a WardenNight event a giant Moss Golem rises at the Grove Heart and
-- four beacons appear in the forest. The Warden cannot be killed: the server
-- banishes it together by lighting every beacon (hold the prompt). Each lit beacon
-- slows it; banishing pays everyone online, lighters get a bonus. If dawn comes
-- first the Warden simply retreats (no penalty).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)
local DayNightCycle = require(script.Parent.DayNightCycle)
local EventService = require(script.Parent.EventService)
local MonsterAI = require(script.Parent.MonsterAI)
local SkillService = require(script.Parent.SkillService)
local FXService = require(script.Parent.FXService)

local BossService = {}

local FOLDER_NAME = "WardenBeacons"
local UNLIT = Color3.fromRGB(70, 60, 90)
local LIT = Color3.fromRGB(255, 190, 90)

local active = false
local lit = 0
local lighters: { [Player]: boolean } = {}

-- Pure: beacon positions on the forest ring, between the plot paths.
function BossService.beaconPositions(): { Vector3 }
	local out = {}
	local count = Config.Boss.Beacons
	for i = 0, count - 1 do
		local a = math.rad(22.5 + i * (360 / count))
		table.insert(out, Vector3.new(math.cos(a), 0, math.sin(a)) * Config.Boss.BeaconRadius)
	end
	return out
end

-- Pure: one player's banish reward.
function BossService.rewardFor(rebirths: number, income: number, litOne: boolean): number
	local base = Perks.scaledReward(Config.Boss.RewardBase, rebirths, income, Config.Boss.RewardSeconds)
	return math.floor(base * (if litOne then 1 + Config.Boss.LighterBonus else 1))
end

local function publish()
	Workspace:SetAttribute("WardenActive", active)
	Workspace:SetAttribute("WardenLit", lit)
	Workspace:SetAttribute("WardenTotal", Config.Boss.Beacons)
end

local function groundY(position: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local hit = Workspace:Raycast(position + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position.Y else 0
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.Slate
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function clearBeacons()
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local old = root and root:FindFirstChild(FOLDER_NAME)
	if old then
		old:Destroy()
	end
end

local function banish()
	if not active then
		return
	end
	active = false
	MonsterAI.banishWarden()
	for _, player in Players:GetPlayers() do
		local state = PlayerState.peek(player)
		if state then
			local cash = BossService.rewardFor(state.rebirths, PlayerState.incomeRate(state), lighters[player] == true)
			PlayerState.addCash(state, cash)
			SkillService.addXp(player, "Survival", Config.Boss.RewardXp)
			Remotes.get("TutorialToast"):FireClient(player, `The Grove Warden is banished! +${cash}`)
		end
	end
	print(`[BossService] Grove Warden banished ({lit} beacons)`)
	table.clear(lighters)
	task.delay(4, clearBeacons)
	publish()
end

local function lightBeacon(player: Player, beacon: Model)
	if not active or beacon:GetAttribute("Lit") == true then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local pivot = beacon:GetPivot().Position
	if not (root and root:IsA("BasePart")) or (root.Position - pivot).Magnitude > 14 then
		return -- server-side reach check (prompts can be fired from far away by exploiters)
	end
	beacon:SetAttribute("Lit", true)
	lit += 1
	lighters[player] = true
	local bowl = beacon:FindFirstChild("Bowl")
	if bowl and bowl:IsA("BasePart") then
		bowl.Color = LIT
		bowl.Material = Enum.Material.Neon
		local fire = Instance.new("Fire")
		fire.Size = 9
		fire.Heat = 12
		fire.Color = Color3.fromRGB(255, 170, 60)
		fire.SecondaryColor = Color3.fromRGB(255, 240, 160)
		fire.Parent = bowl
		local light = Instance.new("PointLight")
		light.Color = LIT
		light.Brightness = 3
		light.Range = 30
		light.Parent = bowl
	end
	local beam = beacon:FindFirstChild("Beacon", true)
	if beam and beam:IsA("Beam") then
		beam.Color = ColorSequence.new(LIT)
		beam.Enabled = true
	end
	local prompt = beacon:FindFirstChild("LightPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	FXService.burstAt(pivot + Vector3.new(0, 6, 0), LIT, 30)
	MonsterAI.setWardenBeacons(lit)
	Remotes.get("TutorialToast"):FireAllClients(`{player.Name} lit a beacon! ({lit}/{Config.Boss.Beacons})`)
	print(`[BossService] {player.Name} lit beacon {beacon.Name} ({lit}/{Config.Boss.Beacons})`)
	publish()
	if lit >= Config.Boss.Beacons then
		banish()
	end
end

local function buildBeacons()
	clearBeacons()
	local root = Workspace:FindFirstChild("AnomalyGrove")
	if not root then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = root
	for index, flat in BossService.beaconPositions() do
		local y = groundY(flat)
		local model = Instance.new("Model")
		model.Name = `Beacon{index}`
		local base = part(
			"Base",
			Vector3.new(4, 6, 6),
			CFrame.new(flat.X, y + 2, flat.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(110, 104, 98),
			model,
			Enum.PartType.Cylinder
		)
		local bowl = part(
			"Bowl",
			Vector3.new(1.4, 7, 7),
			CFrame.new(flat.X, y + 4.6, flat.Z) * CFrame.Angles(0, 0, math.rad(90)),
			UNLIT,
			model,
			Enum.PartType.Cylinder
		)
		model.PrimaryPart = base
		local top = Instance.new("Attachment")
		top.Name = "Top"
		top.Parent = bowl
		local sky = Instance.new("Attachment")
		sky.Name = "Sky"
		sky.WorldPosition = Vector3.new(flat.X, y + 80, flat.Z)
		sky.Parent = bowl
		local beam = Instance.new("Beam")
		beam.Name = "Beacon"
		beam.Attachment0 = top
		beam.Attachment1 = sky
		beam.Color = ColorSequence.new(Color3.fromRGB(170, 120, 255))
		beam.Width0 = 2
		beam.Width1 = 0.4
		beam.Transparency = NumberSequence.new(0.3, 0.9)
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Parent = bowl
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LightPrompt"
		prompt.ActionText = "Light Beacon"
		prompt.ObjectText = "Banish the Warden"
		prompt.HoldDuration = Config.Boss.BeaconHold
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = base
		prompt.Triggered:Connect(function(player)
			lightBeacon(player, model)
		end)
		model.Parent = folder
	end
end

function BossService.start()
	if active then
		return
	end
	active = true
	lit = 0
	table.clear(lighters)
	buildBeacons()
	publish()
	task.delay(Config.Boss.SpawnDelay, function()
		if active then
			MonsterAI.spawnWarden(Vector3.new(0, 10, 0))
		end
	end)
	print("[BossService] Warden night: beacons placed")
end

local function retreat()
	if not active then
		return
	end
	active = false
	MonsterAI.banishWarden()
	clearBeacons()
	table.clear(lighters)
	Remotes.get("TutorialToast"):FireAllClients("Dawn breaks - the Grove Warden retreats into the trees")
	publish()
end

function BossService.init()
	publish()
	EventService.onEventStarted(function(name)
		if name == "WardenNight" then
			BossService.start()
		end
	end)
	DayNightCycle.onPhaseStarted(function(phase)
		if phase == "Day" then
			retreat()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lighters[player] = nil
	end)
end

return BossService
