--!strict
-- "Steal Core" hold prompts (key X) on rival pedestals. Stealing used to need the touch
-- pad's Steal button or the B key, so desktop players had no visible way to do
-- it. These prompts are client-only (each player sees them on OTHER plots) and
-- fire the same StealCore remote; the server still checks ownership, reach,
-- vault, immunity and lockdown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

if player:GetAttribute("StealPromptsInitialized") then
	return
end
player:SetAttribute("StealPromptsInitialized", true)

local PROMPT_NAME = "StealPrompt"
local REFRESH_SECONDS = 0.5

-- Thievery + Quick Hands shorten the rip (M8), never below 40% of the base.
local function ripSeconds(): number
	local ok, stats = pcall(function()
		return game:GetService("HttpService"):JSONDecode(player:GetAttribute("Stats") or "{}")
	end)
	local cut = if ok and type(stats) == "table" and type(stats.ripSpeed) == "number" then stats.ripSpeed else 0
	return Config.Steal.RipTime * (1 - math.min(cut, 0.6))
end

local function wantsPrompt(model: Model, plotIndex: number): boolean
	local mine = player:GetAttribute("PlotIndex")
	return mine ~= nil
		and plotIndex ~= mine
		and player:GetAttribute("CarriedCore") == nil
		and model:FindFirstChild("CoreOrb") ~= nil
		and model:FindFirstChild("VaultShield") == nil
end

local function ensurePrompt(model: Model, plotIndex: number, slot: number)
	local anchor = model.PrimaryPart
	if not anchor then
		return
	end
	local prompt = anchor:FindFirstChild(PROMPT_NAME)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.HoldDuration = ripSeconds()
		return
	end
	local created = Instance.new("ProximityPrompt")
	created.Name = PROMPT_NAME
	created.ActionText = "Steal Core"
	created.ObjectText = "Rival core"
	created.HoldDuration = ripSeconds()
	created.MaxActivationDistance = 10 -- server reach gate is Config.Steal.InteractDistance (12)
	created.RequiresLineOfSight = false
	created.KeyboardKeyCode = Enum.KeyCode.X -- B is the shop hotkey
	-- The server times the hold too: report when it begins, then the finish.
	created.PromptButtonHoldBegan:Connect(function()
		Remotes.get("StealCore"):FireServer(plotIndex, slot, "begin")
	end)
	created.Triggered:Connect(function()
		Remotes.get("StealCore"):FireServer(plotIndex, slot)
	end)
	created.Parent = anchor
end

local function removePrompt(model: Model)
	local anchor = model.PrimaryPart
	local prompt = anchor and anchor:FindFirstChild(PROMPT_NAME)
	if prompt then
		prompt:Destroy()
	end
end

local function refresh()
	local root = Workspace:FindFirstChild("AnomalyGrove")
	local plots = root and root:FindFirstChild("Plots")
	if not plots then
		return
	end
	for _, plot in plots:GetChildren() do
		local plotIndex = plot:GetAttribute("PlotIndex")
		if not plot:IsA("Folder") or type(plotIndex) ~= "number" then
			continue
		end
		for _, child in plot:GetChildren() do
			local slot = tonumber(string.match(child.Name, "^Pedestal(%d+)$"))
			if slot and child:IsA("Model") then
				if wantsPrompt(child, plotIndex) then
					ensurePrompt(child, plotIndex, slot)
				else
					removePrompt(child)
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		refresh()
		task.wait(REFRESH_SECONDS)
	end
end)
