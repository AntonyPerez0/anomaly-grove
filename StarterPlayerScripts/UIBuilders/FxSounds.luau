--!strict
-- Client SFX helpers (M3-08): layered engine-tone chords/arpeggios, a streak
-- stinger, cash popups and the night ambience loop. Engine rbxasset sounds only
-- (GDD: no copyrighted audio). Music/ambience runs quieter than SFX by design.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local FxSounds = {}

local groupsReady = false

-- SoundGroup discipline: SFX stays above the ambience loop so the loop never
-- drowns feedback. One spot-check log per session (M3-08 done-when).
function FxSounds.ensureGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	local sfx = SoundService:FindFirstChild("SFX")
	if not sfx or not sfx:IsA("SoundGroup") then
		sfx = Instance.new("SoundGroup")
		sfx.Name = "SFX"
		sfx.Parent = SoundService
	end
	(sfx :: SoundGroup).Volume = Config.FxMix.SfxVolume
	local music = SoundService:FindFirstChild("Music")
	if not music or not music:IsA("SoundGroup") then
		music = Instance.new("SoundGroup")
		music.Name = "Music"
		music.Parent = SoundService
	end
	(music :: SoundGroup).Volume = Config.FxMix.AmbienceVolume
	print(
		`[FxSounds] mix spot-check: SFX {Config.FxMix.SfxVolume} >= ambience {Config.FxMix.AmbienceVolume} (music never louder than SFX)`
	)
end

-- One engine ping at a PlaybackSpeed offset; stacked offsets read as tones.
local function note(speed: number, volume: number, delay: number)
	task.delay(delay, function()
		local sound = Instance.new("Sound")
		sound.SoundId = Config.FX.CashBlipSound
		sound.PlaybackSpeed = speed
		sound.Volume = volume
		sound.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
		sound.Parent = SoundService
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
		task.delay(3, function()
			sound:Destroy()
		end)
	end)
end

-- Warm chord (login popup) or rising arpeggio (mutation) from Config speeds.
function FxSounds.layered(speeds: { number }, volume: number?)
	FxSounds.ensureGroups()
	local gap = Config.FxMix.ChordGap
	for i, speed in speeds do
		note(speed, volume or Config.FX.FxVolume * 0.5, (i - 1) * gap)
	end
end

-- Night-survived stinger: low bass hit with a bright ping on top.
function FxSounds.stinger()
	FxSounds.ensureGroups()
	task.delay(0, function()
		local bass = Instance.new("Sound")
		bass.SoundId = Config.FX.PlaceSound
		bass.PlaybackSpeed = 0.7
		bass.Volume = Config.FX.FxVolume * 0.7
		bass.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
		bass.Parent = SoundService
		bass:Play()
		bass.Ended:Connect(function()
			bass:Destroy()
		end)
		task.delay(4, function()
			bass:Destroy()
		end)
	end)
	note(1.5, Config.FX.FxVolume * 0.6, 0.12)
end

-- "+$N" popup that floats up beside the HUD cash badge and fades out.
function FxSounds.cashPopup(amount: number)
	local player = Players.LocalPlayer
	local hud = player:FindFirstChild("PlayerGui") and (player.PlayerGui :: PlayerGui):FindFirstChild("AnomalyHUD")
	local badge = hud and hud:FindFirstChild("CashBadge")
	if not badge or not badge:IsA("GuiObject") then
		return
	end
	local popup = Instance.new("TextLabel")
	popup.Name = "CashPopup"
	popup.BackgroundTransparency = 1
	popup.TextColor3 = Color3.fromRGB(120, 230, 120)
	popup.TextStrokeTransparency = 0.7
	popup.Font = Enum.Font.FredokaOne
	popup.TextScaled = true
	popup.Text = `+${math.floor(amount)}`
	popup.AnchorPoint = Vector2.new(1, 0.5)
	popup.Position = UDim2.new(1, -4, 0, -6)
	popup.Size = UDim2.fromScale(0.55, 0.9)
	popup.Parent = badge
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(popup, info, {
		Position = UDim2.new(1, -4, 0, -26),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(1.3, function()
		popup:Destroy()
	end)
end

-- One-shot 2D sound on the SFX group (M5-10 library audio).
function FxSounds.play(soundId: string, volume: number?, speed: number?)
	FxSounds.ensureGroups()
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or Config.FX.FxVolume
	sound.PlaybackSpeed = speed or 1
	sound.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(8, function()
		sound:Destroy()
	end)
end

-- Soft UI click for every themed button.
local lastClick = 0
function FxSounds.uiClick()
	local now = os.clock()
	if now - lastClick < 0.05 then
		return
	end
	lastClick = now
	FxSounds.play(Config.FX.UIClickSound, 0.5)
end

-- Screen confetti burst (purchases, rebirth): coloured flakes fall from the top.
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 205, 70),
	Color3.fromRGB(80, 220, 110),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(255, 90, 140),
	Color3.fromRGB(170, 110, 255),
}
function FxSounds.confetti(pieces: number?)
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Confetti"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.Parent = playerGui
	for _ = 1, pieces or 40 do
		local flake = Instance.new("Frame")
		flake.BorderSizePixel = 0
		flake.Size = UDim2.fromOffset(math.random(6, 11), math.random(10, 16))
		flake.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
		flake.AnchorPoint = Vector2.new(0.5, 0.5)
		local startX = math.random()
		flake.Position = UDim2.fromScale(startX, -0.05)
		flake.Rotation = math.random(0, 360)
		flake.Parent = gui
		local duration = 1.4 + math.random() * 1.1
		TweenService:Create(flake, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(startX + (math.random() - 0.5) * 0.3, 1.05),
			Rotation = flake.Rotation + math.random(-540, 540),
		}):Play()
	end
	task.delay(2.8, function()
		gui:Destroy()
	end)
end

-- World-event banner (M6-04): big title slides down from the top, holds, slides out.
local EVENT_BANNERS: { [string]: { title: string, sub: string, color: Color3 } } = {
	BloodMoon = {
		title = "🌕 BLOOD MOON RISES!",
		sub = "x2 mutations · more monsters · x2 survival bonus",
		color = Color3.fromRGB(255, 80, 80),
	},
	MeteorShower = {
		title = "☄ METEOR SHOWER!",
		sub = "Grab the glowing Meteor Seeds in the forest!",
		color = Color3.fromRGB(255, 170, 60),
	},
	Rain = {
		title = "🌧 IT'S RAINING!",
		sub = "Seeds planted now hatch twice as fast",
		color = Color3.fromRGB(110, 180, 255),
	},
	Thunderstorm = {
		title = "⛈ THUNDERSTORM!",
		sub = "Lightning can strike your cores - SHOCKED x15!",
		color = Color3.fromRGB(150, 210, 255),
	},
	Aurora = {
		title = "🌌 AURORA NIGHT!",
		sub = "More mutations · Celestial x3 more likely",
		color = Color3.fromRGB(140, 255, 200),
	},
	Eclipse = {
		title = "🌑 THE ECLIPSE EVENT BEGINS!",
		sub = "x2 mutations · the LIMITED Eclipse x25 mutation for 3 hours",
		color = Color3.fromRGB(255, 130, 90),
	},
	WardenNight = {
		title = "👹 THE GROVE WARDEN RISES!",
		sub = "Light all 4 forest beacons together to banish it",
		color = Color3.fromRGB(190, 110, 255),
	},
}
function FxSounds.eventBanner(name: string)
	local info = EVENT_BANNERS[name]
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not info or not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "EventBanner"
	gui.DisplayOrder = 55
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, -120)
	frame.Size = UDim2.new(0.9, 0, 0, 96)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(640, 96)
	sizeCap.Parent = frame
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = info.color
	title.Text = info.title
	title.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(20, 10, 20)
	stroke.Parent = title
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 62)
	sub.Size = UDim2.new(1, 0, 0, 28)
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Text = info.sub
	sub.Parent = frame
	local subStroke = Instance.new("UIStroke")
	subStroke.Thickness = 2.5
	subStroke.Color = Color3.fromRGB(20, 10, 20)
	subStroke.Parent = sub
	TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 130),
	}):Play()
	task.delay(4.5, function()
		TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -140),
		}):Play()
		task.delay(0.5, function()
			gui:Destroy()
		end)
	end)
	FxSounds.play(Config.FX.NightWhoosh, Config.FX.FxVolume)
	FxSounds.play(if name == "BloodMoon" then Config.FX.AlarmSound else Config.FX.SparkleSound, Config.FX.FxVolume)
end

-- Base alarm: library alarm beeps — reads as "your base was hit!".
function FxSounds.alarm()
	FxSounds.play(Config.FX.AlarmSound, Config.FX.FxVolume * 1.2)
end

-- Night-start cue (GDD 10 "fog whoosh"): two low dread hits before the groan
-- loop fades in. Engine tones only.
function FxSounds.nightStartCue()
	FxSounds.ensureGroups()
	local sound = Instance.new("Sound")
	sound.Name = "NightCue"
	sound.SoundId = Config.FX.PlaceSound -- bass hit, pitched way down
	sound.PlaybackSpeed = 0.4
	sound.Volume = Config.FX.FxVolume * 0.9
	sound.SoundGroup = SoundService:FindFirstChild("SFX") :: SoundGroup?
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	task.delay(4, function()
		sound:Destroy()
	end)
	FxSounds.play(Config.FX.NightWhoosh, Config.FX.FxVolume * 0.8) -- fog rolling in
end

-- Night bed (M5-10): crickets loop + an eerie music-box track, both on the quiet
-- Music group (replaces the pitched-down groan).
local ambience: { Sound } = {}

local function loop(name: string, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = volume
	sound.SoundGroup = SoundService:FindFirstChild("Music") :: SoundGroup?
	sound.Parent = SoundService
	sound:Play()
	return sound
end

function FxSounds.setNightAmbience(on: boolean)
	FxSounds.ensureGroups()
	if on then
		if #ambience > 0 then
			return
		end
		table.insert(ambience, loop("NightCrickets", Config.FX.NightAmbienceId, 0.7))
		table.insert(ambience, loop("NightMusic", Config.FX.NightMusicId, 0.5))
	else
		for _, sound in ambience do
			sound:Stop()
			sound:Destroy()
		end
		table.clear(ambience)
	end
end

-- Day music loop (GDD 10: "day groove") on the same quiet Music group; a free
-- Creator Store track recorded in docs/ASSETS.md.
local dayMusic: Sound? = nil

function FxSounds.setDayMusic(on: boolean)
	FxSounds.ensureGroups()
	if on then
		if dayMusic then
			return
		end
		local sound = Instance.new("Sound")
		sound.Name = "DayMusic"
		sound.SoundId = Config.FX.DayMusicId
		sound.Looped = true
		sound.Volume = 0.45 -- within the quiet Music group
		sound.SoundGroup = SoundService:FindFirstChild("Music") :: SoundGroup?
		sound.Parent = SoundService
		sound:Play()
		dayMusic = sound
	else
		local current = dayMusic
		if current then
			current:Stop()
			current:Destroy()
			dayMusic = nil
		end
	end
end

return FxSounds
