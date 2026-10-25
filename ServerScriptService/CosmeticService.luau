--!strict
-- Cosmetic gamepass effects (M4 polish): StealTrails and BaseAlarmSirens.
-- Both are gated by pass ownership via MonetizationService.isPassOwner, and
-- both are silent no-ops while the placeholder IDs stay 0 in Config.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local MonetizationService = require(script.Parent.MonetizationService)

local CosmeticService = {}

-- Steal Trail: a light ribbon streams down the carrier's back while they carry
-- a core, tinted with the core's rarity (mutation color wins — it is rarer).
function CosmeticService.attachTrail(character: Model, core: Types.CarriedItem)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	task.spawn(function()
		if not MonetizationService.isPassOwner(player, Config.GamePasses.StealTrails) then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then
			return
		end
		CosmeticService.detachTrail(character) -- idempotent
		local color = Config.Rarities[core.rarity :: Types.Rarity].color
		if core.mutation ~= nil then
			color = Config.Mutations[core.mutation :: Types.Mutation].color
		end
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, 1, 0)
		top.Parent = root
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -1, 0)
		bottom.Parent = root
		local trail = Instance.new("Trail")
		trail.Name = "StealTrail"
		trail.Attachment0 = top
		trail.Attachment1 = bottom
		trail.Color = ColorSequence.new(color)
		trail.LightEmission = 1
		trail.Transparency = NumberSequence.new(0.2, 1)
		trail.Lifetime = 0.8
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Parent = root
	end)
end

function CosmeticService.detachTrail(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local trail = root:FindFirstChild("StealTrail")
	if trail then
		trail:Destroy()
	end
	local top = root:FindFirstChild("TrailTop")
	if top then
		top:Destroy()
	end
	local bottom = root:FindFirstChild("TrailBottom")
	if bottom then
		bottom:Destroy()
	end
end

-- Base Alarm Sirens: when a raider rips a core off your pedestal, you get a
-- siren + red screen flash so you know exactly what happened.
function CosmeticService.onRip(victimState: Types.PlayerState, thief: Player)
	local victim = victimState.player
	if not victim or victim == thief then
		return
	end
	task.spawn(function()
		if MonetizationService.isPassOwner(victim, Config.GamePasses.BaseAlarmSirens) then
			Remotes.get("Juice"):FireClient(victim, "Alarm", thief.Name)
		end
	end)
end

-- Boot: nothing persistent to wire (hooks are call-based); kept for symmetry
-- with the other services and future cosmetics.
function CosmeticService.init() end

return CosmeticService
