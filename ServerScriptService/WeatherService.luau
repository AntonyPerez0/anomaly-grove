--!strict
-- Weather (M9-06). Rain and Aurora are pure multipliers read from EventService
-- (faster incubation / Celestial odds). The Thunderstorm is active: every few
-- seconds lightning strikes a random hatched core in a random claimed plot and
-- turns it SHOCKED (x15, storm-only) when that is an upgrade, plus some bolts into
-- the forest for show. Clients add rain / aurora visuals from WorldEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)
local CoreSystem = require(script.Parent.CoreSystem)
local EventService = require(script.Parent.EventService)
local FXService = require(script.Parent.FXService)

local WeatherService = {}

local BOLT_COLOR = Color3.fromRGB(170, 220, 255)

-- Pure: hatched cores a strike could upgrade to Shocked.
function WeatherService.strikeTargets(pedestals: { any }): { number }
	local out = {}
	for slot, pedestal in pedestals do
		if
			pedestal.rarity ~= nil
			and pedestal.hatchAt == nil
			and CoreSystem.isMutationUpgrade(pedestal.mutation, "Shocked")
		then
			table.insert(out, slot)
		end
	end
	return out
end

-- Zig-zag bolt from the sky to `target`, gone after a blink.
local function bolt(target: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = "LightningBolt"
	local rng = Random.new(os.clock() * 1e5)
	local from = target + Vector3.new(rng:NextNumber(-12, 12), 160, rng:NextNumber(-12, 12))
	local segments = 8
	local last = from
	for i = 1, segments do
		local alpha = i / segments
		local point = from:Lerp(target, alpha)
		if i < segments then
			point += Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6))
		end
		local length = (point - last).Magnitude
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon
		seg.Color = BOLT_COLOR
		seg.Size = Vector3.new(0.6, 0.6, length)
		seg.CFrame = CFrame.lookAt((last + point) / 2, point)
		seg.Parent = folder
		last = point
	end
	local flash = Instance.new("PointLight")
	flash.Color = BOLT_COLOR
	flash.Brightness = 8
	flash.Range = 60
	flash.Parent = folder:GetChildren()[segments] :: Instance
	folder.Parent = Workspace
	game:GetService("Debris"):AddItem(folder, 0.35)
	FXService.burstAt(target, BOLT_COLOR, 20)
end

local function pedestalPosition(plotIndex: number, slot: number): Vector3?
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	local plot = plots and plots:FindFirstChild("Plot" .. (plotIndex + 1))
	local model = plot and plot:FindFirstChild("Pedestal" .. slot)
	return if model and model:IsA("Model") and model.PrimaryPart then model.PrimaryPart.Position else nil
end

local function strike()
	local candidates: { Player } = {}
	for _, player in Players:GetPlayers() do
		local state = PlayerState.peek(player)
		if state and state.plotIndex ~= nil and #WeatherService.strikeTargets(state.pedestals) > 0 then
			table.insert(candidates, player)
		end
	end
	local rng = Random.new(os.clock() * 1e6)
	if #candidates > 0 then
		local player = candidates[rng:NextInteger(1, #candidates)]
		local state = PlayerState.get(player)
		local targets = WeatherService.strikeTargets(state.pedestals)
		local slot = targets[rng:NextInteger(1, #targets)]
		local position = pedestalPosition(state.plotIndex :: number, slot)
		if position then
			bolt(position + Vector3.new(0, 3, 0))
		end
		local rarity = state.pedestals[slot].rarity
		CoreSystem.applyMutation(state, slot, "Shocked")
		Remotes.get("TutorialToast"):FireClient(player, `Lightning struck your {rarity} core - SHOCKED x15!`)
		print(`[WeatherService] lightning shocked {player.Name}'s pedestal {slot}`)
	end
	-- Ambient bolt into the forest so the storm reads even with no targets.
	local a = rng:NextNumber(0, 2 * math.pi)
	local r = rng:NextNumber(20, Config.Map.ForestRadius * 0.9)
	bolt(Vector3.new(math.cos(a) * r, 2, math.sin(a) * r))
end

function WeatherService.init()
	EventService.onEventStarted(function(name)
		if name ~= "Thunderstorm" then
			return
		end
		task.spawn(function()
			while EventService.current() == "Thunderstorm" do
				task.wait(Config.Events.Thunderstorm.StrikeEvery)
				if EventService.current() == "Thunderstorm" then
					strike()
				end
			end
		end)
	end)
end

return WeatherService
