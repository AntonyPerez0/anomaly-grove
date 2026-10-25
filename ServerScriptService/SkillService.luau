--!strict
-- Skills (M8-02/03): seven skills levelled 1-99 on the RuneScape XP table.
-- Systems call SkillService.addXp(player, skill, baseXp) for the actions they own;
-- this module scales the XP (level factor + Scholar), levels up, publishes the
-- client attributes, fires XP drops / level-up banners, announces big levels,
-- and owns the derived live stats (max health, defense slots, capes).
-- Skills are never reset by rebirth.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)

local SkillService = {}

local BASE_HEALTH = 100
local DROP_FLUSH_SECONDS = 0.5

-- XP gained listeners (Grove Pass hooks in here without a require cycle).
local xpListeners: { (Player, Types.PlayerState, string, number) -> () } = {}

function SkillService.onXpGained(callback: (Player, Types.PlayerState, string, number) -> ())
	table.insert(xpListeners, callback)
end

-- Every bonus in the game for this state (skills + tree + upgrades + Index).
function SkillService.stats(state: Types.PlayerState): Perks.Stats
	return Perks.compute({
		skills = state.skills,
		tree = state.tree,
		upgrades = state.upgrades,
		indexEntries = Perks.indexEntries(state.indexDiscovered),
		companion = state.companion,
	})
end

function SkillService.level(state: Types.PlayerState, skill: string): number
	return Perks.skillLevel(state.skills, skill)
end

-- Pure core of addXp (spec-testable): returns (gained, oldLevel, newLevel).
function SkillService.applyXp(state: Types.PlayerState, skill: string, baseXp: number): (number, number, number)
	local oldLevel = Perks.skillLevel(state.skills, skill)
	local gained = math.floor(baseXp * Perks.xpMultiplier(oldLevel, SkillService.stats(state), skill) + 0.5)
	if gained <= 0 then
		return 0, oldLevel, oldLevel
	end
	state.skills[skill] = (state.skills[skill] or 0) + gained
	return gained, oldLevel, Perks.skillLevel(state.skills, skill)
end

-- Client mirrors ------------------------------------------------------------

function SkillService.publish(player: Player, state: Types.PlayerState)
	local stats = SkillService.stats(state)
	player:SetAttribute("Skills", HttpService:JSONEncode(state.skills))
	player:SetAttribute("Stats", HttpService:JSONEncode(stats))
	player:SetAttribute("TotalLevel", Perks.totalLevel(state.skills))
	player:SetAttribute("Tokens", state.tokens)
	player:SetAttribute("Tree", HttpService:JSONEncode(state.tree))
	player:SetAttribute("Upgrades", HttpService:JSONEncode(state.upgrades))
	player:SetAttribute("Cape", state.cape)
	-- Derived gameplay attributes other systems already read.
	player:SetAttribute(
		"DefenseSlots",
		math.min(state.rebirths, Config.Rebirth.MaxDefenseSlotBonus) + math.floor(Perks.get(stats, "defenseSlots"))
	)
	player:SetAttribute("MonsterSight", Perks.get(stats, "monsterSight"))
	player:SetAttribute("DefenseCount", #state.defenses)
	SkillService.applyHealth(player, stats)
end

-- XP drops are batched per skill and flushed twice a second (one remote call).
local pendingDrops: { [Player]: { [string]: number } } = {}

-- Award XP for an action. Silent = no XP drop popup (per-second trickles).
function SkillService.addXp(player: Player?, skill: string, baseXp: number, silent: boolean?): number
	if not player then
		return 0
	end
	local state = PlayerState.peek(player)
	if not state or state.quests == nil then
		return 0 -- profile not loaded yet
	end
	local gained, oldLevel, newLevel = SkillService.applyXp(state, skill, baseXp)
	if gained <= 0 then
		return 0
	end
	if not silent then
		local drops = pendingDrops[player] or {}
		drops[skill] = (drops[skill] or 0) + gained
		pendingDrops[player] = drops
	end
	for _, listener in xpListeners do
		listener(player, state, skill, gained)
	end
	if newLevel > oldLevel then
		SkillService.onLevelUp(player, state, skill, oldLevel, newLevel)
	else
		player:SetAttribute("Skills", HttpService:JSONEncode(state.skills))
	end
	return gained
end

function SkillService.onLevelUp(
	player: Player,
	state: Types.PlayerState,
	skill: string,
	oldLevel: number,
	newLevel: number
)
	-- Collect every reward between the old and new level (multi-level jumps).
	local lines: { string } = {}
	for level = oldLevel + 1, newLevel do
		for _, line in Perks.rewardsAt(skill, level) do
			table.insert(lines, line)
		end
	end
	SkillService.publish(player, state)
	Remotes.get("SkillEvent"):FireClient(player, "level", skill, newLevel, lines)
	-- Confetti + jingle on every level; the big rebirth sting for a 99.
	Remotes.get("Juice"):FireClient(player, if newLevel >= Config.Skills.CapeLevel then "Rebirth" else "Purchase")
	for _, announce in Config.Skills.AnnounceLevels do
		if oldLevel < announce and newLevel >= announce then
			local meta = (Config.Skills.Meta :: any)[skill]
			Remotes.get("TutorialToast")
				:FireAllClients(`{meta and meta.icon or ""} {player.Name} reached {skill} level {announce}!`)
		end
	end
	if newLevel >= Config.Skills.CapeLevel and oldLevel < Config.Skills.CapeLevel then
		-- First 99 wears its cape automatically; all seven at 99 upgrades to the max cape.
		if Perks.totalLevel(state.skills) >= Config.Skills.CapeLevel * #Config.Skills.Order then
			state.cape = "Max"
		elseif state.cape == nil then
			state.cape = skill
		end
		SkillService.refreshCape(player, state)
	end
	print(`[SkillService] {player.Name} {skill} {oldLevel} -> {newLevel}`)
end

-- Live stats on the character --------------------------------------------------

function SkillService.applyHealth(player: Player, stats: Perks.Stats)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local maxHealth = BASE_HEALTH + math.floor(Perks.get(stats, "maxHealth"))
		if humanoid.MaxHealth ~= maxHealth then
			local wasFull = humanoid.Health >= humanoid.MaxHealth - 0.01
			humanoid.MaxHealth = maxHealth
			if wasFull then
				humanoid.Health = maxHealth
			end
		end
	end
end

-- Capes: a cloth panel welded to the back, tinted with the skill colour.
local MAX_CAPE_COLOR = Color3.fromRGB(255, 215, 90)

function SkillService.capeAvailable(state: Types.PlayerState, cape: string): boolean
	if cape == "Max" then
		return Perks.totalLevel(state.skills) >= Config.Skills.CapeLevel * #Config.Skills.Order
	end
	return (Config.Skills.Meta :: any)[cape] ~= nil and SkillService.level(state, cape) >= Config.Skills.CapeLevel
end

function SkillService.refreshCape(player: Player, state: Types.PlayerState)
	player:SetAttribute("Cape", state.cape)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("SkillCape")
	if old then
		old:Destroy()
	end
	local cape = state.cape
	if cape == nil or not SkillService.capeAvailable(state, cape) then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) then
		return
	end
	local meta = (Config.Skills.Meta :: any)[cape]
	local color = if cape == "Max" then MAX_CAPE_COLOR else meta.color
	local part = Instance.new("Part")
	part.Name = "SkillCape"
	part.Size = Vector3.new(1.9, 2.6, 0.12)
	part.Color = color
	part.Material = Enum.Material.Fabric
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = torso.CFrame * CFrame.new(0, -0.55, 0.62) * CFrame.Angles(math.rad(-8), 0, 0)
	local trim = Instance.new("SurfaceGui")
	trim.Face = Enum.NormalId.Back
	trim.CanvasSize = Vector2.new(190, 260)
	trim.LightInfluence = 0.3
	local emblem = Instance.new("TextLabel")
	emblem.Size = UDim2.fromScale(1, 0.45)
	emblem.Position = UDim2.fromScale(0, 0.12)
	emblem.BackgroundTransparency = 1
	emblem.TextScaled = true
	emblem.Font = Enum.Font.FredokaOne
	emblem.Text = if cape == "Max" then "★" else meta.icon
	emblem.TextColor3 = Color3.new(1, 1, 1)
	emblem.Parent = trim
	trim.Parent = part
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = part
	weld.Parent = part
	part.Parent = character
end

-- Is the player standing inside their own plot? (axis follows the plot frame)
local function insideOwnPlot(state: Types.PlayerState, position: Vector3): boolean
	if state.plotIndex == nil then
		return false
	end
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. ((state.plotIndex :: number) + 1))
	local floor = plot and plot:FindFirstChild("Floor")
	if not (floor and floor:IsA("BasePart")) then
		return false
	end
	local offset = floor.CFrame:PointToObjectSpace(position)
	local half = Config.Map.PlotSize / 2
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half
end

function SkillService.init(isNight: () -> boolean, bloodMoon: () -> boolean)
	-- Drop flusher: one SkillEvent "xp" per player per half second.
	task.spawn(function()
		while true do
			task.wait(DROP_FLUSH_SECONDS)
			for player, drops in pendingDrops do
				pendingDrops[player] = nil
				if player.Parent then
					Remotes.get("SkillEvent"):FireClient(player, "xp", drops)
				end
			end
		end
	end)

	-- Survival trickle: alive outside your own plot at night (risk = reward).
	task.spawn(function()
		while true do
			task.wait(1)
			if not isNight() then
				continue
			end
			local perSecond = Config.Skills.Xp.nightOutsidePerSecond
				* (if bloodMoon() then Config.Skills.Xp.bloodMoonMultiplier else 1)
			for _, player in Players:GetPlayers() do
				local state = PlayerState.peek(player)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if
					state
					and humanoid
					and humanoid.Health > 0
					and root
					and root:IsA("BasePart")
					and not insideOwnPlot(state, root.Position)
				then
					SkillService.addXp(player, "Survival", perSecond, true)
				end
			end
		end
	end)

	-- Capes + health come back with every new character.
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			local state = PlayerState.peek(player)
			if state and state.quests ~= nil then
				SkillService.applyHealth(player, SkillService.stats(state))
				SkillService.refreshCape(player, state)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		pendingDrops[player] = nil
	end)

	-- SetCape (validated: only capes you have earned, or "None").
	Remotes.get("SetCape").OnServerEvent:Connect(function(player, cape)
		local state = PlayerState.peek(player)
		if not state or type(cape) ~= "string" then
			return
		end
		if cape == "None" then
			state.cape = nil
		elseif SkillService.capeAvailable(state, cape) then
			state.cape = cape
		else
			return
		end
		SkillService.refreshCape(player, state)
	end)
end

-- Commerce XP for a purchase, sized against the player's current income.
function SkillService.addCommerceXp(player: Player, price: number)
	local rate = player:GetAttribute("IncomeRate")
	SkillService.addXp(player, "Commerce", Perks.commerceXp(price, if type(rate) == "number" then rate else 0))
end

-- Total XP for display / leaderboards.
function SkillService.totalXp(state: Types.PlayerState): number
	local total = 0
	for _, xp in state.skills do
		total += xp
	end
	return total
end

return SkillService
