--!strict
-- Juice pass 1 (M1-15): spatial sounds, particle bursts and screen shake hooks.
-- Server-owned effects replicate to every client automatically. Sounds and burst
-- parts are temporary and self-clean (Debris), so no orphans accumulate.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local FXService = {}

local BURST_LIFETIME = 2

local function tempPart(position: Vector3, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	return part
end

-- Spatial one-shot sound at a world position.
function FXService.soundAt(position: Vector3, soundId: string, volume: number?)
	local part = tempPart(position, "FXSound")
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or Config.FX.FxVolume
	sound.RollOffMaxDistance = 120
	sound.Parent = part
	sound:Play()
	Debris:AddItem(part, math.max(1, sound.TimeLength + 1))
end

-- One-shot neon burst (harvest, hatch, drop...). Distance-culled for low-end
-- devices (M4-01): no burst spawns when no player is within BURST_CULL_DISTANCE.
local BURST_CULL_DISTANCE = 160

local function anyPlayerNear(position: Vector3): boolean
	local Players = game:GetService("Players")
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude <= BURST_CULL_DISTANCE then
			return true
		end
	end
	return false
end

function FXService.burstAt(position: Vector3, color: Color3, count: number?)
	if not anyPlayerNear(position) then
		return
	end
	local part = tempPart(position, "FXBurst")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(0.3, 0.7)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = part
	emitter:Emit(count or Config.FX.BurstParticles)
	Debris:AddItem(part, BURST_LIFETIME)
end

-- Screen shake hook: fires the client Juice event.
function FXService.shake(player: Player)
	Remotes.get("Juice"):FireClient(player, "Shake", Config.FX.ShakeSeconds)
end

-- Juice pass 2 (M3-08): named event sounds played client-side per player.
function FXService.loginChord(player: Player)
	Remotes.get("Juice"):FireClient(player, "LoginChord")
end

function FXService.mutation(player: Player, position: Vector3?)
	if position then
		FXService.burstAt(position, Color3.fromRGB(255, 215, 90), Config.FX.BurstParticles * 2)
	end
	Remotes.get("Juice"):FireClient(player, "MutationArpeggio")
end

function FXService.streakStinger(player: Player)
	Remotes.get("Juice"):FireClient(player, "StreakStinger")
end

-- Named hooks used by game systems.
function FXService.harvestAt(position: Vector3)
	FXService.burstAt(position, Color3.fromRGB(70, 240, 200))
	FXService.soundAt(position, Config.FX.HarvestSound)
end

-- Pedestal ring pulse (GDD 10): a neon ring that expands and fades on placement.
local RING_LIFETIME = 0.7

function FXService.placeRing(position: Vector3)
	local part = tempPart(position, "FXRing")
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 1.6, 1.6)
	ring.Color = Color3.fromRGB(200, 255, 210)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	-- Cylinders extend along X; stand it upright and lay the face flat.
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = part
	TweenService:Create(
		ring,
		TweenInfo.new(RING_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 7, 7), Transparency = 1 }
	):Play()
	Debris:AddItem(part, RING_LIFETIME + 0.1)
end

function FXService.placeAt(position: Vector3)
	FXService.soundAt(position, Config.FX.PlaceSound, 0.5)
	FXService.burstAt(position, Color3.fromRGB(200, 255, 210), 8)
	FXService.placeRing(position)
end

function FXService.hatchAt(position: Vector3, color: Color3)
	FXService.burstAt(position, color, Config.FX.BurstParticles * 2)
	FXService.soundAt(position, Config.FX.SparkleSound, 0.6)
end

function FXService.ripAt(position: Vector3, thief: Player)
	FXService.burstAt(position, Color3.fromRGB(255, 200, 90))
	FXService.soundAt(position, Config.FX.RipSound, 0.6)
	FXService.shake(thief)
end

function FXService.tagAt(position: Vector3, victim: Player)
	FXService.soundAt(position, Config.FX.TagSound, 0.6)
	FXService.shake(victim)
end

function FXService.dropAt(position: Vector3, color: Color3)
	FXService.burstAt(position, color, 6)
end

-- M5-10: purchase "cha-ching" + confetti and the rebirth sting, played client-side.
function FXService.purchase(player: Player)
	Remotes.get("Juice"):FireClient(player, "Purchase")
end

function FXService.rebirth(player: Player)
	Remotes.get("Juice"):FireClient(player, "Rebirth")
end

function FXService.cashBlip(player: Player, amount: number)
	Remotes.get("Juice"):FireClient(player, "CashBlip", amount)
end

return FXService
