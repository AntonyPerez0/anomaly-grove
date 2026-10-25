--!strict
-- Settings menu (M4 polish): a gear button + a small panel with SFX and music
-- toggles. Drives the SoundService groups FxSounds creates, so the night
-- ambience obeys the music toggle automatically.

local TweenService = game:GetService("TweenService")

local SettingsPanel = {}

export type Settings = {
	gui: ScreenGui,
	panel: Frame,
	gear: TextButton,
	sfxToggle: TextButton,
	musicToggle: TextButton,
}

local COLORS = {
	panel = Color3.fromRGB(20, 24, 30),
	accent = Color3.fromRGB(60, 255, 220),
	text = Color3.fromRGB(255, 255, 255),
	off = Color3.fromRGB(90, 96, 105),
}

-- AnchorPoint is (1, 0), so X offset is the panel's RIGHT edge: closed must push
-- it a full panel width past the screen edge, or it stays visible at spawn.
local PANEL_WIDTH = 300
local OPEN_POS = UDim2.new(1, -10, 0, 62)
local CLOSED_POS = UDim2.new(1, PANEL_WIDTH + 20, 0, 62)

local function corner(parent: Instance, radius: number)
	local ui = Instance.new("UICorner")
	ui.CornerRadius = UDim.new(0, radius)
	ui.Parent = parent
	return ui
end

function SettingsPanel.build(): Settings
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsMenu"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 45

	-- Gear button: top-right, below the Roblox top bar.
	local gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -10, 0, 4)
	gear.Size = UDim2.fromOffset(52, 52)
	gear.BackgroundColor3 = COLORS.panel
	gear.BackgroundTransparency = 0.25
	gear.Font = Enum.Font.FredokaOne
	gear.TextColor3 = COLORS.accent
	gear.TextScaled = true
	gear.Text = "gear"
	gear.Parent = gui
	corner(gear, 12)

	-- Panel: slides from the right when the gear is pressed.
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = CLOSED_POS
	panel.Visible = false
	panel.Size = UDim2.fromOffset(PANEL_WIDTH, 132)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	corner(panel, 12)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 34)
	title.Position = UDim2.fromOffset(10, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = COLORS.accent
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Audio"
	title.Parent = panel

	local function toggle(name: string, label: string, y: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(1, -20, 0, 40)
		b.Position = UDim2.fromOffset(10, y)
		b.BackgroundColor3 = COLORS.accent
		b.Font = Enum.Font.FredokaOne
		b.TextColor3 = Color3.fromRGB(15, 20, 25)
		b.TextScaled = true
		b.Text = label
		b.Parent = panel
		corner(b, 10)
		return b
	end

	local sfxToggle = toggle("SfxToggle", "Sound effects: ON", 46)
	local musicToggle = toggle("MusicToggle", "Music/ambience: ON", 90)

	gui.Parent = game:GetService("Players") and game.Players.LocalPlayer:WaitForChild("PlayerGui")

	return {
		gui = gui,
		panel = panel,
		gear = gear,
		sfxToggle = sfxToggle,
		musicToggle = musicToggle,
	}
end

-- Slide the panel in/out.
function SettingsPanel.setOpen(panel: Frame, open: boolean)
	if open then
		panel.Visible = true
	end
	local tween = TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = if open then OPEN_POS else CLOSED_POS,
	})
	-- Hide once fully closed so the offscreen panel never eats taps.
	tween.Completed:Connect(function(state)
		if not open and state == Enum.PlaybackState.Completed then
			panel.Visible = false
		end
	end)
	tween:Play()
end

-- Reflect the on/off state on a toggle button.
function SettingsPanel.paintToggle(button: TextButton, on: boolean, label: string)
	button.Text = `{label}: {if on then "ON" else "OFF"}`
	button.BackgroundColor3 = if on then COLORS.accent else COLORS.off
	button.TextColor3 = if on then COLORS.text else Color3.fromRGB(230, 230, 235)
end

return SettingsPanel
