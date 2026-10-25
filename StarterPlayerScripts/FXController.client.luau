--!strict
-- Client FX: camera shake on Juice("Shake") and a soft local cash blip.
-- Particle bursts and world sounds replicate from the server; this handles only
-- per-client screen feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local FxSounds = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("FxSounds"))

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once.
if player:GetAttribute("FXInitialized") then
	return
end
player:SetAttribute("FXInitialized", true)

-- Camera shake: oscillate the humanoid camera offset for the requested duration.
local function shake(seconds: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local startOffset = humanoid.CameraOffset
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime
		if elapsed >= seconds then
			humanoid.CameraOffset = startOffset
			connection:Disconnect()
			return
		end
		local decay = 1 - elapsed / seconds
		humanoid.CameraOffset = startOffset
			+ Vector3.new(math.sin(elapsed * 70) * 0.35 * decay, math.cos(elapsed * 63) * 0.25 * decay, 0)
	end)
end

-- Base-alarm red flash (BaseAlarmSirens pass): a vignette that fades out.
local function alarmFlash()
	local gui = player:FindFirstChild("PlayerGui") and (player.PlayerGui :: PlayerGui)
	local existing = gui and gui:FindFirstChild("AlarmFlash")
	if existing then
		existing:Destroy()
	end
	local frame = Instance.new("Frame")
	frame.Name = "AlarmFlash"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
	frame.BackgroundTransparency = 0.55
	frame.BorderSizePixel = 0
	frame.ZIndex = 50
	frame.Parent = gui
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		frame:Destroy()
	end)
end

-- Soft local cash blip (never spatial, plays only for this player).
local function cashBlip(soundId: string)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = Config.FX.FxVolume * 0.6
	sound.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	sound.PlayOnRemove = false
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(3, function()
		sound:Destroy()
	end)
end

Remotes.get("Juice").OnClientEvent:Connect(function(kind: string, arg)
	if kind == "Shake" then
		shake(arg :: number)
	elseif kind == "CashBlip" then
		FxSounds.ensureGroups()
		cashBlip(Config.FX.CashBlipSound)
		FxSounds.cashPopup(arg :: number) -- M3-08: amount popup beside the cash badge
	elseif kind == "LoginChord" then
		FxSounds.layered(Config.FxMix.LoginChordSpeeds)
	elseif kind == "MutationArpeggio" then
		FxSounds.layered(Config.FxMix.ArpeggioSpeeds)
	elseif kind == "StreakStinger" then
		FxSounds.stinger()
	elseif kind == "Event" then
		FxSounds.eventBanner(arg :: string)
	elseif kind == "Purchase" then
		FxSounds.play(Config.FX.PurchaseSound, Config.FX.FxVolume * 1.2)
		FxSounds.confetti(36)
	elseif kind == "Rebirth" then
		FxSounds.play(Config.FX.RebirthSting, Config.FX.FxVolume * 1.4)
		FxSounds.confetti(90)
	elseif kind == "Alarm" then
		-- BaseAlarmSirens pass: siren + a red flash so the raid registers.
		FxSounds.alarm()
		alarmFlash()
	end
end)

-- Phase music (GDD 10): day groove / night dread, both on the quiet Music group.
Remotes.get("PhaseChanged").OnClientEvent:Connect(function(phase: string)
	FxSounds.setNightAmbience(phase == "Night")
	FxSounds.setDayMusic(phase == "Day")
	if phase == "Night" then
		FxSounds.nightStartCue() -- dread hit as the fog rolls in
	end
end)

-- Away popup (M2-04): the AwayPopup module wires its own OfflineSummary listener.
require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("AwayPopup"))
