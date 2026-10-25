--!strict
-- Settings controller (M4 polish): gear opens the audio menu; the toggles drive
-- the SFX / Music SoundGroups that FxSounds set up. Music off also silences the
-- night ambience (it lives on the Music group).

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local FxSounds = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("FxSounds"))
local SettingsPanel = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("SettingsPanel"))

local player = Players.LocalPlayer

if player:GetAttribute("SettingsInitialized") then
	return
end
player:SetAttribute("SettingsInitialized", true)

FxSounds.ensureGroups()
local ui = SettingsPanel.build()

local sfxOn = true
local musicOn = true

local function apply()
	local sfx = SoundService:FindFirstChild("SFX")
	local music = SoundService:FindFirstChild("Music")
	if sfx and sfx:IsA("SoundGroup") then
		sfx.Volume = if sfxOn then Config.FxMix.SfxVolume else 0
	end
	if music and music:IsA("SoundGroup") then
		music.Volume = if musicOn then Config.FxMix.AmbienceVolume else 0
	end
	SettingsPanel.paintToggle(ui.sfxToggle, sfxOn, "Sound effects")
	SettingsPanel.paintToggle(ui.musicToggle, musicOn, "Music/ambience")
end

-- M5-09: the side menu's Settings button opens the panel through the router.
local UIRouter = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("UIRouter"))
ui.gear.Visible = false
UIRouter.register("Settings", {
	open = function()
		SettingsPanel.setOpen(ui.panel, true)
	end,
	close = function()
		SettingsPanel.setOpen(ui.panel, false)
	end,
})

ui.sfxToggle.Activated:Connect(function()
	sfxOn = not sfxOn
	apply()
end)

ui.musicToggle.Activated:Connect(function()
	musicOn = not musicOn
	apply()
end)

apply()
