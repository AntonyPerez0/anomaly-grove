--!strict
-- Main HUD (M5-09 restyle): cash pill with a coin + live income line (top-left),
-- carried-item slot under it (clear of the mobile thumbstick), and a day/night pill
-- with icon + progress bar (top-centre). Built in code with UITheme; returns the
-- named widgets HUDController drives (field names kept from M1-07).

local GuiService = game:GetService("GuiService")
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local HUDBuilder = {}

export type HUD = {
	gui: ScreenGui,
	phaseGui: ScreenGui, -- ignores the top-bar inset: the timer sits IN the top bar
	cashLabel: TextLabel,
	incomeLabel: TextLabel,
	phaseBar: Frame,
	phaseFill: Frame,
	phaseLabel: TextLabel,
	phaseIcon: TextLabel,
	phasePill: Frame,
	carriedIcon: Frame,
	carriedLabel: TextLabel,
}

local C = UITheme.COLORS

function HUDBuilder.build(): HUD
	local gui = Instance.new("ScreenGui")
	gui.Name = "AnomalyHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = false

	-- Cash pill (top-left).
	local cash = UITheme.panel(gui, "CashBadge", C.panelDeep)
	cash.AnchorPoint = Vector2.new(0, 0)
	cash.Position = UDim2.fromOffset(12, 10)
	cash.Size = UDim2.fromOffset(196, 46)
	cash.BackgroundTransparency = 0.1
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, -6, 0.5, 0)
	coin.Size = UDim2.fromOffset(46, 46)
	coin.BackgroundColor3 = Color3.new(1, 1, 1)
	coin.Parent = cash
	UITheme.corner(coin, 23)
	UITheme.gradient(coin, C.gold, C.goldDark)
	UITheme.stroke(coin, 3)
	local coinMark = UITheme.label(coin, "Mark", "$", C.text)
	coinMark.Size = UDim2.fromScale(0.7, 0.7)
	coinMark.Position = UDim2.fromScale(0.15, 0.12)
	local cashLabel = UITheme.label(cash, "CashLabel", "$0", C.text)
	cashLabel.Position = UDim2.fromOffset(48, 4)
	cashLabel.Size = UDim2.new(1, -56, 1, -8)
	cashLabel.TextXAlignment = Enum.TextXAlignment.Left

	local incomeLabel = UITheme.label(gui, "IncomeLabel", "+$0/s", C.green)
	incomeLabel.Position = UDim2.fromOffset(62, 58)
	incomeLabel.Size = UDim2.fromOffset(220, 20)
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Carried slot (under the cash pill; the mobile thumbstick owns bottom-left).
	local carried = UITheme.panel(gui, "CarriedBadge", C.panelDeep)
	carried.Position = UDim2.fromOffset(12, 82)
	carried.Size = UDim2.fromOffset(176, 34)
	carried.BackgroundTransparency = 0.25
	local carriedIcon = Instance.new("Frame")
	carriedIcon.Name = "CarriedIcon"
	carriedIcon.AnchorPoint = Vector2.new(0, 0.5)
	carriedIcon.Position = UDim2.new(0, 8, 0.5, 0)
	carriedIcon.Size = UDim2.fromOffset(20, 20)
	carriedIcon.BackgroundColor3 = C.teal
	carriedIcon.Rotation = 45 -- little gem diamond
	carriedIcon.Parent = carried
	UITheme.corner(carriedIcon, 4)
	UITheme.stroke(carriedIcon, 2)
	local carriedLabel = UITheme.label(carried, "CarriedLabel", "Empty", C.text)
	carriedLabel.Position = UDim2.fromOffset(36, 4)
	carriedLabel.Size = UDim2.new(1, -44, 1, -8)
	carriedLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Day/night pill: a slim pill up in the Roblox top-bar strip (2026-10-18: it
	-- used to hang below the top bar and hide the world). The progress bar runs
	-- along its bottom edge instead of under it.
	local phaseGui = Instance.new("ScreenGui")
	phaseGui.Name = "PhaseHUD"
	phaseGui.ResetOnSpawn = false
	phaseGui.DisplayOrder = 10
	phaseGui.IgnoreGuiInset = true
	local phase = UITheme.panel(phaseGui, "PhasePill", C.panelDeep)
	phase.AnchorPoint = Vector2.new(0.5, 0)
	phase.Position = UDim2.new(0.5, 0, 0, 6)
	phase.Size = UDim2.fromOffset(150, 32)
	phase.BackgroundTransparency = 0.1
	local phaseIcon = UITheme.label(phase, "Icon", "☀", C.gold)
	phaseIcon.Position = UDim2.fromOffset(6, 3)
	phaseIcon.Size = UDim2.fromOffset(22, 22)
	local phaseLabel = UITheme.label(phase, "PhaseLabel", "DAY", C.text)
	phaseLabel.Position = UDim2.fromOffset(32, 3)
	phaseLabel.Size = UDim2.new(1, -40, 1, -11)
	local phaseBar = Instance.new("Frame")
	phaseBar.Name = "PhaseBar"
	phaseBar.AnchorPoint = Vector2.new(0.5, 1)
	phaseBar.Position = UDim2.new(0.5, 0, 1, -3)
	phaseBar.Size = UDim2.new(1, -16, 0, 4)
	phaseBar.BackgroundColor3 = C.panelDeep
	phaseBar.Parent = phase
	UITheme.corner(phaseBar, 2)
	local phaseFill = Instance.new("Frame")
	phaseFill.Name = "Fill"
	phaseFill.Size = UDim2.fromScale(1, 1)
	phaseFill.BackgroundColor3 = C.gold
	phaseFill.Parent = phaseBar
	UITheme.corner(phaseFill, 2)

	return {
		gui = gui,
		phaseGui = phaseGui,
		cashLabel = cashLabel,
		incomeLabel = incomeLabel,
		phaseBar = phaseBar,
		phaseFill = phaseFill,
		phaseLabel = phaseLabel,
		phaseIcon = phaseIcon,
		phasePill = phase,
		carriedIcon = carriedIcon,
		carriedLabel = carriedLabel,
	}
end

-- The timer lives in the free part of the Roblox top bar (GuiService.TopbarInset),
-- vertically centred there: screen centre on wide screens, the right end of the
-- free strip on narrow (portrait) ones so it never meets the Roblox buttons.
HUDBuilder.NARROW_WIDTH = 700
function HUDBuilder.layout(hud: HUD, viewport: Vector2)
	local pill = hud.phasePill
	local inset = GuiService.TopbarInset
	local barHeight = if inset.Height > 0 then inset.Height else 36
	local height = math.clamp(barHeight - 8, 26, 32)
	local y = math.max(2, math.floor((barHeight - height) / 2))
	pill.Size = UDim2.fromOffset(if viewport.X < HUDBuilder.NARROW_WIDTH then 128 else 150, height)
	local halfWidth = pill.Size.X.Offset / 2
	local centreFits = inset.Width <= 0
		or (inset.Min.X <= viewport.X / 2 - halfWidth and inset.Max.X >= viewport.X / 2 + halfWidth)
	if viewport.X >= HUDBuilder.NARROW_WIDTH and centreFits then
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.new(0.5, 0, 0, y)
	else
		local right = if inset.Width > 0 then inset.Max.X else viewport.X
		pill.AnchorPoint = Vector2.new(1, 0)
		pill.Position = UDim2.fromOffset(right - 8, y)
	end
end

return HUDBuilder
