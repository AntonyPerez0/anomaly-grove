--!strict
-- HUD controller: binds live values (cash, seeds, carried core, phase timer) to the
-- ScreenGui built by UIBuilders.HUDBuilder. All values are replicated attributes;
-- the phase countdown is display-only (the server owns the real clock).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Zones = require(ReplicatedStorage.Shared.Zones)

local HUDBuilder = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("HUDBuilder"))
local UITheme = require(script.Parent:WaitForChild("UIBuilders"):WaitForChild("UITheme"))

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once
-- (respawn/clone); every run after the first must be a no-op.
if player:GetAttribute("HUDInitialized") then
	return
end
player:SetAttribute("HUDInitialized", true)
local hud = HUDBuilder.build()
hud.gui.Parent = player:WaitForChild("PlayerGui")
hud.phaseGui.Parent = player:WaitForChild("PlayerGui")

local function relayout()
	local camera = workspace.CurrentCamera
	if camera then
		HUDBuilder.layout(hud, camera.ViewportSize)
	end
end
game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(relayout)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)
end
relayout()

-- Cash count-up (GDD 9): the label rolls to the new value instead of snapping.
local displayCash = Instance.new("NumberValue")
displayCash.Value = 0
local cashTween: Tween? = nil
displayCash.Changed:Connect(function(value)
	-- Full digits while they fit the pill; K/M/B... beyond (M8 numbers get huge).
	hud.cashLabel.Text = if value < 1e9 then `${UITheme.commas(value)}` else `${UITheme.short(value)}`
end)

-- Live income line under the cash pill (server sums every core's $/s at 1 Hz).
local function updateIncome()
	local rate = player:GetAttribute("IncomeRate") or 0
	hud.incomeLabel.Text = if rate >= 1000
		then `+${UITheme.short(rate)}/s`
		else string.format("+$%s/s", if rate % 1 == 0 then tostring(rate) else string.format("%.1f", rate))
	hud.incomeLabel.Visible = rate > 0
	-- Friend boost (M6-05) rides along on the income line.
	if player:GetAttribute("DoubleCash") == true then
		hud.incomeLabel.Text ..= " (x2)"
	end
	local boost = player:GetAttribute("FriendBoost") or 0
	if boost > 0 then
		hud.incomeLabel.Text ..= ` (+{boost}% 👥)`
	end
end
player:GetAttributeChangedSignal("IncomeRate"):Connect(updateIncome)
player:GetAttributeChangedSignal("FriendBoost"):Connect(updateIncome)
player:GetAttributeChangedSignal("DoubleCash"):Connect(updateIncome)
updateIncome()

local function updateCash()
	local cash = player:GetAttribute("Cash") or 0
	local pending = cashTween
	if pending then
		pending:Cancel()
	end
	local start = displayCash.Value
	-- Small deltas snap; big jumps (steals, offline) roll over ~0.5 s.
	local duration = if math.abs(cash - start) <= 50 then 0.1 else 0.5
	local roll = TweenService:Create(
		displayCash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = cash }
	)
	cashTween = roll
	roll:Play()
end
player:GetAttributeChangedSignal("Cash"):Connect(updateCash)
updateCash()

local function updateCarried()
	local seeds = player:GetAttribute("SeedsCarried") or 0
	local grove = player:GetAttribute("GroveSeedsCarried") or 0
	local zone = player:GetAttribute("ZoneSeedsCarried") or 0
	local coreRarity = player:GetAttribute("CarriedCore") -- set later by StealSystem (M1-09)
	if coreRarity ~= nil and coreRarity ~= "" then
		local info = Config.Rarities[coreRarity :: string]
		hud.carriedIcon.BackgroundColor3 = if info then info.color else Color3.new(1, 1, 1)
		hud.carriedLabel.Text = `{coreRarity} Core`
		hud.carriedIcon.BackgroundTransparency = 0
	elseif zone > 0 then
		-- Wild-zone seeds (2026-10-18): the best one decides the icon colour.
		-- Zone and market seeds, best first; the best one colours the icon.
		local bestColor: Color3? = nil
		local names = {}
		local summary: string = player:GetAttribute("ZoneSeeds") or ""
		for _, seedId in Zones.seedOrder() do
			local n = string.match(summary, seedId .. "=(%d+)")
			local def = Zones.seed(seedId)
			if n and def then
				bestColor = bestColor or Zones.seedColor(seedId)
				local short = string.gsub(def.name, " Seed", "")
				table.insert(names, `{n} {short}`)
			end
		end
		hud.carriedIcon.BackgroundColor3 = bestColor or Color3.fromRGB(255, 200, 60)
		hud.carriedIcon.BackgroundTransparency = 0
		hud.carriedLabel.Text = `Seeds x {seeds + grove + zone} ({table.concat(names, ", ")})`
	elseif grove > 0 then
		-- Grove Heart seeds (boosted mutation) show in gold with their count.
		hud.carriedIcon.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		hud.carriedIcon.BackgroundTransparency = 0
		hud.carriedLabel.Text = `Seeds x {seeds + grove} ({grove} Heart)`
	elseif seeds > 0 then
		hud.carriedIcon.BackgroundColor3 = Color3.fromRGB(70, 240, 200)
		hud.carriedIcon.BackgroundTransparency = 0
		hud.carriedLabel.Text = `Seeds x {seeds}`
	else
		hud.carriedIcon.BackgroundTransparency = 0.7
		hud.carriedLabel.Text = "Empty"
	end
end
player:GetAttributeChangedSignal("SeedsCarried"):Connect(updateCarried)
player:GetAttributeChangedSignal("GroveSeedsCarried"):Connect(updateCarried)
player:GetAttributeChangedSignal("ZoneSeeds"):Connect(updateCarried)
player:GetAttributeChangedSignal("CarriedCore"):Connect(updateCarried)
updateCarried()

-- Phase display: the server fires (phase, secondsRemaining) at each transition and
-- the client counts down locally between broadcasts.
local phaseEndsAt = 0
local phaseLength = 1
local phaseName = "Day"

local function updatePhase()
	local remaining = math.max(0, phaseEndsAt - os.clock())
	hud.phaseFill.Size = UDim2.fromScale(remaining / phaseLength, 1)
	local minutes = math.floor(remaining / 60)
	local seconds = math.floor(remaining % 60)
	hud.phaseLabel.Text = `{string.upper(phaseName)} {minutes}:{string.format("%02d", seconds)}`
	-- World events (M6-04) swap the phase icon while they run.
	local event = workspace:GetAttribute("WorldEvent")
	if event == "BloodMoon" then
		hud.phaseIcon.Text = "🌕"
		hud.phaseIcon.TextColor3 = Color3.fromRGB(255, 90, 90)
		hud.phaseFill.BackgroundColor3 = Color3.fromRGB(230, 60, 60)
	elseif event == "MeteorShower" then
		hud.phaseIcon.Text = "☄"
		hud.phaseIcon.TextColor3 = Color3.fromRGB(255, 170, 60)
	end
end

Remotes.get("PhaseChanged").OnClientEvent:Connect(function(phase: string, secondsRemaining: number)
	phaseEndsAt = os.clock() + secondsRemaining
	phaseLength = math.max(1, secondsRemaining)
	phaseName = phase
	hud.phaseFill.BackgroundColor3 = if phase == "Night"
		then Color3.fromRGB(150, 90, 255)
		else Color3.fromRGB(255, 200, 90)
	hud.phaseIcon.Text = if phase == "Night" then "🌙" else "☀"
	hud.phaseIcon.TextColor3 = if phase == "Night" then Color3.fromRGB(200, 180, 255) else Color3.fromRGB(255, 205, 70)
	updatePhase()
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		if phaseEndsAt > 0 then
			updatePhase()
		end
	end
end)
