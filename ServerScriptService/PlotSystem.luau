--!strict
-- Plot ownership: walk into an unclaimed plot's marker to claim it. The server is
-- the sole owner of plot state; the ClaimPlot remote runs the same server checks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local PlayerState = require(script.Parent.PlayerState)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)
local SkillService = require(script.Parent.SkillService)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local PedestalBuilder = require(game.ServerStorage.Builders.PedestalBuilder)

local PlotSystem = {}

local TOUCH_DEBOUNCE = 0.5 -- seconds between touch-claim attempts per player

type Plot = {
	index: number,
	owner: Player?,
	pendingReleaseAt: number?,
}

local plots: { Plot } = {}
local lastTouchAt: { [Player]: number } = {}

local function plotFolder(index: number): Folder?
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plotsRoot = root and root:FindFirstChild("Plots")
	if not plotsRoot then
		return nil
	end
	local folder = plotsRoot:FindFirstChild("Plot" .. (index + 1))
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function setSign(plotIndex: number, text: string)
	local folder = plotFolder(plotIndex)
	if not folder then
		return
	end
	local sign = folder:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("SignLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

PlotSystem.setSign = setSign

-- Owner headshot on the nameplate (rbxthumb URLs load client-side, no yield here).
local function setSignAvatar(plotIndex: number, userId: number?)
	local folder = plotFolder(plotIndex)
	local sign = folder and folder:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("SignGui")
	local avatar = gui and gui:FindFirstChild("Avatar")
	local label = gui and gui:FindFirstChild("SignLabel")
	if avatar and avatar:IsA("ImageLabel") then
		avatar.Visible = userId ~= nil
		avatar.Image = if userId then `rbxthumb://type=AvatarHeadShot&id={userId}&w=150&h=150` else ""
	end
	-- Make room for the headshot on the left when it shows.
	if label and label:IsA("TextLabel") then
		label.Position = if userId then UDim2.fromOffset(200, 10) else UDim2.fromOffset(20, 10)
		label.Size = if userId then UDim2.new(1, -220, 1, -20) else UDim2.new(1, -40, 1, -20)
	end
end

-- Live sign text: owner name + current cash (refreshed by the income tick).
function PlotSystem.refreshSign(player: Player)
	local state = PlayerState.peek(player)
	if not state or state.plotIndex == nil then
		return
	end
	-- Total skill level (M8-03) + short cash so huge late-game numbers still fit.
	setSign(
		state.plotIndex :: number,
		`{player.Name}'s Grove\nLv {Perks.totalLevel(state.skills)} · ${Progression.format(state.cash)}`
	)
	setSignAvatar(state.plotIndex :: number, player.UserId)
end

local function setMarker(plotIndex: number, visible: boolean)
	local folder = plotFolder(plotIndex)
	local marker = folder and folder:FindFirstChild("ClaimMarker")
	if marker and marker:IsA("BasePart") then
		marker.Transparency = if visible then 0 else 1
		local gui = marker:FindFirstChild("ClaimGui")
		if gui and gui:IsA("BillboardGui") then
			gui.Enabled = visible
		end
		local pillar = marker:FindFirstChild("ClaimPillar")
		if pillar and pillar:IsA("Beam") then
			pillar.Enabled = visible
		end
	end
end

-- Server-authoritative claim rules. Pure so specs can test them without touching
-- world instances. Returns ok + rejection reason.
function PlotSystem.checkClaim(plotsList: { Plot }, state: Types.PlayerState, plotIndex: number): (boolean, string)
	if plotIndex < 0 or plotIndex >= #plotsList then
		return false, "invalid plot index"
	end
	if state.plotIndex ~= nil then
		return false, `already owns plot {state.plotIndex}`
	end
	local plot = plotsList[plotIndex + 1]
	if plot.owner ~= nil then
		return false, `plot owned by {plot.owner.Name}`
	end
	return true, "ok"
end

-- Server-authoritative claim. Returns false (and logs why) on rejection.
function PlotSystem.claim(player: Player, plotIndex: number): boolean
	local state = PlayerState.get(player)
	local ok, reason = PlotSystem.checkClaim(plots, state, plotIndex)
	if not ok then
		print(`[PlotSystem] {player.Name} claim rejected: {reason}`)
		return false
	end
	local plot = plots[plotIndex + 1]
	plot.owner = player
	state.plotIndex = plotIndex
	player:SetAttribute("PlotIndex", plotIndex) -- replicated live state (readable from any VM)
	setSign(plotIndex, `{player.Name}'s Grove`)
	setSignAvatar(plotIndex, player.UserId)
	setMarker(plotIndex, false)
	print(`[PlotSystem] {player.Name} claimed plot {plotIndex}`)
	return true
end

-- Frees the plot when its owner leaves: the wipe happens after the grace period
-- (profile save already ran at leave time; the log line in DataService confirms it).
function PlotSystem.release(player: Player)
	local state = PlayerState.peek(player)
	if not state then
		return
	end
	local plotIndex = state.plotIndex
	if plotIndex == nil then
		return
	end
	local plot = plots[plotIndex + 1]
	if plot and plot.owner == player then
		plot.pendingReleaseAt = os.clock() + Config.Plot.ResetGraceSeconds
	end
	state.plotIndex = nil
	player:SetAttribute("PlotIndex", nil) -- removes the attribute
	print(`[PlotSystem] {player.Name} left plot {plotIndex} - wipe in {Config.Plot.ResetGraceSeconds}s`)
end

-- Drops per-player touch bookkeeping on leave (called by DataService's leave handler).
function PlotSystem.forget(player: Player)
	lastTouchAt[player] = nil
end

-- Lockdown shield visual (M3-05): four low forcefield walls ringing the plot.
-- Purely cosmetic (CanCollide off); the steal gate is the server state.
function PlotSystem.setLockdownVisual(plotIndex: number, locked: boolean): boolean
	local folder = plotFolder(plotIndex)
	if not folder then
		return false
	end
	for _, child in folder:GetChildren() do
		if child.Name == "LockdownWall" then
			child:Destroy()
		end
	end
	if not locked then
		return true
	end
	local floor = folder:FindFirstChild("Floor")
	if not floor or not floor:IsA("BasePart") then
		return false
	end
	local half = Config.Map.PlotSize / 2
	local wallColor = Color3.fromRGB(120, 90, 255)
	for i = 1, 4 do
		local wall = Instance.new("Part")
		wall.Name = "LockdownWall"
		wall.Size = if i % 2 == 1
			then Vector3.new(Config.Map.PlotSize, 5, 1)
			else Vector3.new(1, 5, Config.Map.PlotSize)
		local offset = if i <= 2 then (if i == 1 then half else -half) else 0
		local offsetZ = if i <= 2 then 0 else (if i == 3 then half else -half)
		wall.CFrame = floor.CFrame * CFrame.new(offset, 2.5, offsetZ)
		wall.Color = wallColor
		wall.Material = Enum.Material.ForceField
		wall.Transparency = 0.35
		wall.Anchored = true
		wall.CanCollide = false
		wall.CanQuery = false
		wall.Parent = folder
	end
	return true
end

-- Clears purchased pedestals (slots 2..8), defense models, runtime anchors,
-- resets the sign and re-shows the marker.
function PlotSystem.wipePlot(plotIndex: number)
	local plot = plots[plotIndex + 1]
	if not plot then
		return
	end
	plot.owner = nil
	plot.pendingReleaseAt = nil
	local folder = plotFolder(plotIndex)
	local plotsRoot = folder and folder.Parent
	if folder and plotsRoot then
		for _, child in folder:GetChildren() do
			local pedestalSlot = tonumber(string.match(child.Name, "^Pedestal(%d+)$"))
			local turretSlot = tonumber(string.match(child.Name, "^Turret(%d+)$"))
			local trapSlot = tonumber(string.match(child.Name, "^TrapTile(%d+)$"))
			local runtimeAnchor = string.match(child.Name, "^TurretSlot%d+$") ~= nil
				or string.match(child.Name, "^TrapSlot%d+$") ~= nil
			local removable = (child:IsA("Model") and pedestalSlot ~= nil and pedestalSlot >= 2)
				or (child:IsA("Model") and turretSlot ~= nil)
				or (child:IsA("Model") and trapSlot ~= nil)
				or child.Name == "LaserDoor"
				or child.Name == "LockdownWall"
				or runtimeAnchor
			if removable then
				child:Destroy()
			end
		end
	end
	setSign(plotIndex, "Unclaimed")
	setSignAvatar(plotIndex, nil)
	setMarker(plotIndex, true)
	print(`[PlotSystem] plot {plotIndex} wiped and re-listed`)
end

local function playerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	for _ = 1, 2 do
		if character then
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				return player
			end
			character = character.Parent
		end
	end
	return nil
end

-- Live lookups for other systems (server modules only; PlotSystem owns these tables).

-- Runtime plot table (index 0-based keys 1..8 entries with owner).
function PlotSystem.plots(): { Plot }
	return plots
end

-- Pedestal purchases (M2-06).

-- Pure rules for buying the next pedestal. nextSlot = #state.pedestals + 1.
function PlotSystem.checkPedestalPurchase(state: Types.PlayerState, nextSlot: number): (boolean, string, number?)
	if state.plotIndex == nil then
		return false, "claim a plot first", nil
	end
	local stats = SkillService.stats(state)
	if nextSlot > Perks.maxPedestals(stats) then
		return false, "plot is full", nil
	end
	local price = Perks.discounted(Config.Prices.Pedestals[nextSlot - 1], stats)
	if state.cash < price then
		return false, `not enough cash (need {price})`, price
	end
	return true, "ok", price
end

-- Next pedestal price for UI; nil when the plot is full.
function PlotSystem.nextPedestalPrice(state: Types.PlayerState): number?
	local nextSlot = #state.pedestals + 1
	local stats = SkillService.stats(state)
	if nextSlot > Perks.maxPedestals(stats) then
		return nil
	end
	return Perks.discounted(Config.Prices.Pedestals[nextSlot - 1], stats)
end

-- Server-authoritative pedestal purchase.
function PlotSystem.buyPedestal(player: Player): boolean
	local state = PlayerState.get(player)
	local nextSlot = #state.pedestals + 1
	local ok, reason = PlotSystem.checkPedestalPurchase(state, nextSlot)
	if not ok then
		print(`[PlotSystem] {player.Name} pedestal purchase rejected: {reason}`)
		return false
	end
	local price = PlotSystem.nextPedestalPrice(state) :: number
	if not PlayerState.spendCash(state, price) then
		print(`[PlotSystem] {player.Name} pedestal purchase rejected: cash changed mid-purchase`)
		return false
	end
	table.insert(state.pedestals, PlayerState.newPedestal())
	player:SetAttribute("PedestalSlots", #state.pedestals)
	SkillService.addCommerceXp(player, price)
	local built = PedestalBuilder.buildForPlot(state.plotIndex :: number, nextSlot)
	if not built then
		warn(`[PlotSystem] pedestal {nextSlot} model failed to build for plot {state.plotIndex}`)
	end
	print(`[PlotSystem] {player.Name} bought pedestal {nextSlot} for {price} ({#state.pedestals} slots now)`)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	return true
end

-- Live PlayerState of the player who owns a plot (nil = unclaimed).
function PlotSystem.stateAt(plotIndex: number): Types.PlayerState?
	local plot = plots[plotIndex + 1]
	local owner = plot and plot.owner
	return owner and PlayerState.peek(owner) or nil
end

-- Wire touches, the ClaimPlot remote and leave handling. Call once from Main.server.
function PlotSystem.init()
	table.clear(plots)
	for i = 0, Config.Map.Plots - 1 do
		plots[i + 1] = { index = i, owner = nil }
	end

	for index = 0, Config.Map.Plots - 1 do
		local folder = plotFolder(index)
		local zone = folder and folder:FindFirstChild("ClaimZone")
		if zone and zone:IsA("BasePart") then
			zone.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if not player then
					return
				end
				local now = os.clock()
				if lastTouchAt[player] and now - lastTouchAt[player] < TOUCH_DEBOUNCE then
					return
				end
				lastTouchAt[player] = now
				local state = PlayerState.get(player)
				if state.plotIndex ~= nil then
					return -- already owns a plot; no log spam while walking around
				end
				PlotSystem.claim(player, index)
			end)
		else
			warn(`[PlotSystem] missing ClaimZone for plot {index} - run MapBuilder.build()`)
		end
	end

	-- Remote fallback (server-validated like the touch path, plus a reach gate
	-- so a remote call can't claim a plot from across the map - M4-02).
	task.spawn(function()
		local claimRemote = Remotes.get("ClaimPlot")
		claimRemote.OnServerEvent:Connect(function(player, plotIndex)
			if type(plotIndex) ~= "number" then
				return
			end
			local index = math.floor(plotIndex)
			local folder = plotFolder(index)
			local zone = folder and folder:FindFirstChild("ClaimZone")
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if
				not (zone and zone:IsA("BasePart"))
				or not (root and root:IsA("BasePart"))
				or (root.Position - zone.Position).Magnitude > Config.Map.ClaimDistance
			then
				print(`[PlotSystem] {player.Name} claim rejected: too far from that plot`)
				return
			end
			PlotSystem.claim(player, index)
		end)
		local buyRemote = Remotes.get("BuyPedestal")
		buyRemote.OnServerEvent:Connect(function(player)
			PlotSystem.buyPedestal(player)
		end)
	end)

	-- Pending-release checker: wipes plots whose grace period elapsed.
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, plot in plots do
				if plot.pendingReleaseAt ~= nil and now >= plot.pendingReleaseAt then
					PlotSystem.wipePlot(plot.index)
				end
			end
		end
	end)

	-- NOTE: no PlayerRemoving connection here. PlayerRemoving handlers fire in
	-- reverse connection order, so the LEAVE SAVE (DataService, connected last)
	-- must run before anything mutates the state. DataService's leave handler
	-- calls PlotSystem.release after saving. lastTouchAt cleanup rides along there.
end

return PlotSystem
