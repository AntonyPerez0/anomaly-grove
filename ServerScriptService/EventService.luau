--!strict
-- World events (M6-04).
--   Blood Moon: every Events.BloodMoonEvery-th night - red sky, x2 mutation chance,
--     x1.5 Fogling cap, x2 night-streak bonus for surviving it.
--   Meteor Shower: Events.MeteorChance of days - meteors streak down into the forest
--     and leave boosted (Grove Heart) seeds where they land.
-- The active event is mirrored on Workspace attribute "WorldEvent" and announced to
-- every client with a banner (Juice "Event"). Multipliers are read by CoreSystem,
-- MonsterAI and RespawnSystem. Pure rules exported for EventSpec.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Weekly = require(ReplicatedStorage.Shared.Weekly)

local EventService = {}

export type EventName = "BloodMoon" | "MeteorShower" | "WardenNight" | "Rain" | "Thunderstorm" | "Aurora"

local current: EventName? = nil
local lastNightWasBloodMoon = false
local nightNumber = 0

-- Pure: which event (if any) starts with this phase.
function EventService.rollFor(phase: string, night: number, roll: number): EventName?
	if phase == "Night" then
		if night > 0 and night % Config.Events.BloodMoonEvery == 0 then
			return "BloodMoon"
		end
		if night > 0 and night % Config.Events.WardenEvery == 0 then
			return "WardenNight" -- M9-03 boss night
		end
		if roll < Config.Events.AuroraChance then
			return "Aurora" -- M9-06
		end
		return nil
	end
	local events = Config.Events
	if roll < events.MeteorChance then
		return "MeteorShower"
	elseif roll < events.MeteorChance + events.RainChance then
		return "Rain" -- M9-06
	elseif roll < events.MeteorChance + events.RainChance + events.StormChance then
		return "Thunderstorm" -- M9-06
	end
	return nil
end

function EventService.current(): EventName?
	return current
end

-- Multipliers other systems apply (1 when no event is running).
-- M9-09 weekly event: the shared clock, or a Studio debug override.
local weeklyForced = false

function EventService.weeklyActive(): boolean
	return weeklyForced or Weekly.isActive(os.time())
end

function EventService.forceWeekly(on: boolean)
	weeklyForced = on
end

function EventService.mutationMultiplier(): number
	local weekly = if EventService.weeklyActive() then Config.Weekly.MutationMultiplier else 1
	if current == "BloodMoon" then
		return Config.Events.BloodMoon.MutationMultiplier * weekly
	elseif current == "Aurora" then
		return Config.Events.Aurora.MutationMultiplier * weekly
	end
	return weekly
end

-- M9-06 weather multipliers (1 / 0 when no such event is running).
function EventService.incubationMultiplier(): number
	return if current == "Rain" then Config.Events.Rain.IncubationMultiplier else 1
end

function EventService.celestialBonus(): number
	return if current == "Aurora" then Config.Events.Aurora.CelestialBonus else 0
end

function EventService.monsterMultiplier(): number
	return if current == "BloodMoon" then Config.Events.BloodMoon.MonsterMultiplier else 1
end

-- Read at daybreak, so it looks at the night that just ended.
function EventService.streakMultiplier(): number
	return if lastNightWasBloodMoon then Config.Events.BloodMoon.StreakBonusMultiplier else 1
end

local startedCallbacks: { (EventName) -> () } = {}

-- Systems that run an event (BossService) subscribe here instead of being required.
function EventService.onEventStarted(callback: (EventName) -> ())
	table.insert(startedCallbacks, callback)
end

local function setCurrent(name: EventName?)
	current = name
	Workspace:SetAttribute("WorldEvent", name)
	if name then
		Remotes.get("Juice"):FireAllClients("Event", name)
		print(`[EventService] {name} begins!`)
		for _, callback in startedCallbacks do
			task.spawn(callback, name)
		end
	end
end

-- M9-03: start a Grove Warden night now (night rotation, or the debug command).
function EventService.startWardenNight()
	setCurrent("WardenNight")
end

-- Day weather: runs for `seconds`, then clears (unless something replaced it).
function EventService.startWeather(name: EventName, seconds: number)
	setCurrent(name)
	task.delay(seconds, function()
		if current == name then
			setCurrent(nil)
		end
	end)
end

-- Meteor visual: a glowing rock streaks down with a fire trail, bursts, leaves a seed.
local function dropMeteor(target: Vector3, onLanded: (Vector3) -> ())
	local start = target + Vector3.new(math.random(-60, 60), 220, math.random(-60, 60))
	local rock = Instance.new("Part")
	rock.Name = "Meteor"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(4, 4, 4)
	rock.Material = Enum.Material.Neon
	rock.Color = Color3.fromRGB(255, 140, 60)
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanQuery = false
	rock.CanTouch = false
	rock.CFrame = CFrame.new(start)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.5, 0)
	a0.Parent = rock
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.5, 0)
	a1.Parent = rock
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 60, 30))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = rock.Color
	light.Range = 30
	light.Brightness = 3
	light.Parent = rock
	rock.Parent = Workspace
	local tween = TweenService:Create(
		rock,
		TweenInfo.new(Config.Events.MeteorFallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(target + Vector3.new(0, 1, 0)) }
	)
	tween.Completed:Connect(function()
		rock:Destroy()
		onLanded(target)
	end)
	tween:Play()
end

-- Hooks injected by Main (keeps this module free of SeedSystem/FXService requires).
export type Hooks = {
	spawnBoostedSeed: (position: Vector3, flavor: string) -> (),
	randomForestPosition: () -> Vector3,
	burstAt: (position: Vector3, color: Color3) -> (),
	setBloodMoonLighting: (on: boolean) -> (),
}

local hooks: Hooks? = nil

function EventService.startMeteorShower()
	local h = hooks
	if not h then
		return
	end
	setCurrent("MeteorShower")
	local flavors = { "Gold", "Gold", "Void", "Celestial" }
	for i = 1, Config.Events.MeteorCount do
		task.delay((i - 1) * 0.7, function()
			local target = h.randomForestPosition()
			target = Vector3.new(target.X, 0, target.Z)
			dropMeteor(target, function(landed)
				h.burstAt(landed + Vector3.new(0, 2, 0), Color3.fromRGB(255, 160, 60))
				h.spawnBoostedSeed(landed + Vector3.new(0, 3.5, 0), flavors[math.random(1, #flavors)])
			end)
		end)
	end
	task.delay(Config.Events.MeteorEventSeconds, function()
		if current == "MeteorShower" then
			setCurrent(nil)
		end
	end)
end

function EventService.startBloodMoon()
	setCurrent("BloodMoon")
	lastNightWasBloodMoon = true
	if hooks then
		(hooks :: Hooks).setBloodMoonLighting(true)
	end
end

-- Phase hook (registered by Main after DayNightCycle exists).
function EventService.onPhaseStarted(phase: string)
	if phase == "Night" then
		nightNumber += 1
		lastNightWasBloodMoon = false
		if current == "MeteorShower" then
			setCurrent(nil) -- a day event never bleeds into the night
		end
		local nightEvent = EventService.rollFor("Night", nightNumber, math.random())
		if nightEvent == "BloodMoon" then
			-- Let the night lighting tween start first, then paint it red.
			task.delay(1, EventService.startBloodMoon)
		elseif nightEvent == "WardenNight" then
			task.delay(1, EventService.startWardenNight)
		elseif nightEvent == "Aurora" then
			task.delay(1, function()
				setCurrent("Aurora")
			end)
		end
	else
		if current == "BloodMoon" or current == "WardenNight" or current == "Aurora" then
			setCurrent(nil)
		end
		-- Keep lastNightWasBloodMoon through daybreak payouts, then forget it.
		task.delay(5, function()
			lastNightWasBloodMoon = false
		end)
		local dayEvent = EventService.rollFor("Day", nightNumber, math.random())
		if dayEvent == "MeteorShower" then
			task.delay(Config.Events.MeteorDelay, function()
				EventService.startMeteorShower()
			end)
		elseif dayEvent == "Rain" then
			task.delay(Config.Events.MeteorDelay, function()
				EventService.startWeather("Rain", Config.Events.Rain.Seconds)
			end)
		elseif dayEvent == "Thunderstorm" then
			task.delay(Config.Events.MeteorDelay, function()
				EventService.startWeather("Thunderstorm", Config.Events.Thunderstorm.Seconds)
			end)
		end
	end
end

function EventService.init(injected: Hooks)
	hooks = injected
	Workspace:SetAttribute("WorldEvent", nil)
	-- Weekly event mirror + start banner (M9-09).
	task.spawn(function()
		local was = false
		while true do
			local active = EventService.weeklyActive()
			Workspace:SetAttribute("WeeklyActive", active)
			Workspace:SetAttribute("WeeklySecondsLeft", Weekly.secondsLeft(os.time()))
			Workspace:SetAttribute("WeeklyStartsIn", Weekly.secondsUntilStart(os.time()))
			if active and not was then
				Remotes.get("Juice"):FireAllClients("Event", "Eclipse")
				print("[EventService] the weekly Eclipse Event begins")
			end
			was = active
			task.wait(5)
		end
	end)
end

return EventService
