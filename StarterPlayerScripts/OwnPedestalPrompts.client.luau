--!strict
-- Prompts on YOUR pedestals (M8-04 + Alchemy): "Upgrade" shows the next level and
-- its price, "Infuse" (hatched cores) pays ~90 s of that core's income to roll a
-- mutation. Client-only prompts, same pattern as StealPrompts; the server checks
-- ownership, caps, prices and cash on every request.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

if player:GetAttribute("OwnPedestalPromptsInitialized") then
	return
end
player:SetAttribute("OwnPedestalPromptsInitialized", true)

local REFRESH_SECONDS = 0.25
local STACK_GAP = 95 -- px between stacked prompts (positive = upward)

local function stats(): Perks.Stats
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Stats") or "{}")
	end)
	return if ok and type(value) == "table" then value else {}
end

local function levels(): { number }
	local out: { number } = {}
	for level in string.gmatch(player:GetAttribute("PedestalLevels") or "", "[^,]+") do
		table.insert(out, tonumber(level) or 1)
	end
	return out
end

local function prompt(anchor: BasePart, name: string, action: string, key: Enum.KeyCode, hold: number, fire: () -> ())
	local existing = anchor:FindFirstChild(name)
	if existing and existing:IsA("ProximityPrompt") then
		return existing
	end
	local created = Instance.new("ProximityPrompt")
	created.Name = name
	created.ActionText = action
	created.KeyboardKeyCode = key
	created.HoldDuration = hold
	created.MaxActivationDistance = 10
	created.RequiresLineOfSight = false
	created.Triggered:Connect(fire)
	created.Parent = anchor
	return created
end

local function remove(anchor: BasePart, name: string)
	local existing = anchor:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local function refresh()
	local mine = player:GetAttribute("PlotIndex")
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if type(mine) ~= "number" or not plots then
		return
	end
	local plot = plots:FindFirstChild("Plot" .. (mine + 1))
	if not plot then
		return
	end
	local current = stats()
	local rebirths = player:GetAttribute("Rebirths") or 0
	local cap = Perks.pedestalCap(rebirths)
	local ok, skills = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Skills") or "{}")
	end)
	local unlocked = Perks.upgradesUnlocked(if ok and type(skills) == "table" then skills else {})
	local carrying = (player:GetAttribute("SeedsCarried") or 0)
			+ (player:GetAttribute("GroveSeedsCarried") or 0)
			+ (player:GetAttribute("ZoneSeedsCarried") or 0)
		> 0
	local levelList = levels()
	for slot, level in levelList do
		local model = plot:FindFirstChild("Pedestal" .. slot)
		local anchor = model and model:IsA("Model") and model.PrimaryPart
		if not anchor then
			continue
		end
		local slotNumber = slot
		-- Prompts on one part draw on top of each other, so only show what is
		-- usable and stack the rest upward: Place (only with seeds), Upgrade, Infuse.
		local stack = 0
		local place = anchor:FindFirstChild("PlacePrompt")
		if place and place:IsA("ProximityPrompt") then
			place.Enabled = carrying
			place.UIOffset = Vector2.zero
			if carrying then
				stack += 1
			end
		end
		-- Upgrade.
		if unlocked and level < cap then
			local p = prompt(anchor, "UpgradePrompt", "Upgrade", Enum.KeyCode.U, 0, function()
				Remotes.get("UpgradePedestal"):FireServer(slotNumber)
			end)
			local price = Perks.discounted(Perks.pedestalUpgradeCost(slot, level, rebirths), current)
			local text = `Lv {level} -> {level + 1} · ${Progression.format(price)}`
			if p.ObjectText ~= text then
				p.ObjectText = text
			end
			p.UIOffset = Vector2.new(0, STACK_GAP * stack)
			stack += 1
		else
			remove(anchor, "UpgradePrompt")
		end
		-- Infuse: hatched cores below Celestial.
		local core = model:FindFirstChild("CoreOrb")
		local label = core and core:FindFirstChild("CoreLabel")
		local mutation = label and label:FindFirstChild("Mutation")
		local isCelestial = mutation ~= nil
			and mutation:IsA("TextLabel")
			and string.find(mutation.Text, "CELESTIAL") ~= nil
		if core and not isCelestial then
			local p = prompt(anchor, "InfusePrompt", "Infuse", Enum.KeyCode.I, 0.4, function()
				Remotes.get("Infuse"):FireServer(slotNumber)
			end)
			local chance = Config.Infuse.BaseChance + Perks.get(current, "infuseChance")
			p.ObjectText = `Alchemy · {math.floor(chance * 100)}% · ~{Config.Infuse.CostSeconds}s of income`
			p.UIOffset = Vector2.new(0, STACK_GAP * stack)
		else
			remove(anchor, "InfusePrompt")
		end
	end
end

task.spawn(function()
	while true do
		refresh()
		task.wait(REFRESH_SECONDS)
	end
end)
