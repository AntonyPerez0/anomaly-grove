--!strict
-- Death, respawn and night-streak counting (GDD 5.6 / core loop step 4).
-- Death drops carried items at the death spot, respawns the player at their plot
-- after RespawnDelay seconds, and surviving a full night increments nightStreak.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(game:GetService("ReplicatedStorage").Shared.Perks)

local PlayerState = require(script.Parent.PlayerState)
local DayNightCycle = require(script.Parent.DayNightCycle)
local StealSystem = require(script.Parent.StealSystem)
local StatsService = require(script.Parent.StatsService)
local EventService = require(script.Parent.EventService)

local RespawnSystem = {}

-- Pure logic (spec-testable): does this night count as survived?
-- Rule: alive at the moment the night ends.
function RespawnSystem.survivedNight(health: number): boolean
	return health > 0
end

-- os.time-based streak logic for the spec (server uses os.time at phase flips).
function RespawnSystem.streakAfterNight(streak: number, alive: boolean, _survivedNightLength: number): number
	if not alive then
		return 0 -- dying resets the streak
	end
	return streak + 1
end

local function respawnAtPlot(player: Player)
	local state = PlayerState.peek(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	-- The hub spawn lives inside AnomalyGrove.Hub, so search recursively.
	local hubSpawn = game.Workspace:FindFirstChild("SpawnLocation", true)
	local targetCFrame: CFrame
	local grove = game.Workspace:FindFirstChild("AnomalyGrove")
	local plots = grove and grove:FindFirstChild("Plots")
	local plot = if state and state.plotIndex ~= nil
		then plots and plots:FindFirstChild("Plot" .. ((state.plotIndex :: number) + 1))
		else nil
	local floor = plot and plot:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		targetCFrame = floor.CFrame * CFrame.new(0, 4, 0)
	elseif hubSpawn and hubSpawn:IsA("BasePart") then
		targetCFrame = hubSpawn.CFrame * CFrame.new(0, 4, 0)
	else
		return
	end
	-- PivotTo works on live characters only; protected so edit-mode calls are safe.
	pcall(function()
		local liveCharacter = player.Character
		if liveCharacter then
			liveCharacter:PivotTo(targetCFrame)
		end
	end)
end

-- Wire death hooks + night streak counting. Call once from Main.server.
function RespawnSystem.init()
	Players.RespawnTime = Config.RespawnDelay -- Roblox respawn matches our design delay

	local function hookPlayer(player: Player)
		local function hookCharacter(character: Model)
			character:WaitForChild("Humanoid", 10)
			local hum = character:FindFirstChildOfClass("Humanoid")
			if not hum then
				return
			end
			hum.Died:Connect(function()
				-- Drop carried items at the death spot.
				StealSystem.dropCarried(player, false)
				-- Mark the death so CharacterAdded teleports to the plot, not the hub.
				player:SetAttribute("DiedLastLife", true)
				print(`[RespawnSystem] {player.Name} died; respawn in {Config.RespawnDelay}s`)
			end)
		end
		player.CharacterAdded:Connect(function(character)
			if player:GetAttribute("DiedLastLife") == true then
				player:SetAttribute("DiedLastLife", nil)
				task.delay(0.3, function() -- let physics settle
					respawnAtPlot(player)
				end)
			end
			hookCharacter(character)
		end)
		if player.Character then
			hookCharacter(player.Character :: Model)
		end
	end
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	-- Streak: survive a full night = alive at the moment night ends.
	DayNightCycle.onPhaseStarted(function(phase)
		if phase ~= "Day" then
			return
		end
		-- Night just ended: count survivors, pay the streak bonus.
		for _, player in Players:GetPlayers() do
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local alive = humanoid and humanoid.Health > 0
			local state = PlayerState.get(player)
			local streak = StatsService.resolveNight(state, alive == true)
			if alive then
				local bonus = Perks.scaledReward(
					Config.NightStreakBonus,
					state.rebirths,
					PlayerState.incomeRate(state),
					Config.NightStreakSeconds
				) * EventService.streakMultiplier() -- Blood Moon pays double
				PlayerState.addCash(state, bonus)
				print(`[RespawnSystem] {player.Name} survived the night (streak {streak}, +{bonus} cash)`)
			else
				print(`[RespawnSystem] {player.Name} did not survive the night - streak reset`)
			end
		end
	end)
end

return RespawnSystem
