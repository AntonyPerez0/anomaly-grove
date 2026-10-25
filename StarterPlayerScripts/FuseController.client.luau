--!strict
-- Fuse Machine modal (M9-05): opened from the hub stall. One row per rarity you
-- own: "3x Sprout -> Amber · 80% · fee $X" with a FUSE button (needs 3 hatched
-- cores of that rarity). The server picks your 3 weakest and re-checks everything.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Fuse = require(ReplicatedStorage.Shared.Fuse)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("FuseControllerInitialized") then
	return
end
player:SetAttribute("FuseControllerInitialized", true)

local C = UITheme.COLORS
local WIDTH, HEIGHT = 420, 330
local ROW = 52

local gui = Instance.new("ScreenGui")
gui.Name = "FuseModal"
gui.ResetOnSpawn = false
gui.DisplayOrder = 45
gui.Enabled = false
local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Parent = gui
local root = UITheme.panel(gui, "Root", C.panelDeep)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.fromScale(0.5, 0.5)
root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
local fit = Instance.new("UIScale")
fit.Parent = root
local title = UITheme.label(root, "Title", "FUSE MACHINE", Color3.fromRGB(110, 235, 215))
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local sub = UITheme.label(root, "Sub", "Fuse 3 of your weakest cores of a rarity for a shot at the next one", C.muted)
sub.Position = UDim2.fromOffset(16, 44)
sub.Size = UDim2.new(1, -32, 0, 16)
sub.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local list = Instance.new("ScrollingFrame")
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.Position = UDim2.fromOffset(12, 68)
list.Size = UDim2.new(1, -24, 1, -80)
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = root
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list
local empty = UITheme.label(list, "Empty", "You have no cores yet - hatch some first!", C.muted)
empty.Size = UDim2.new(1, 0, 0, 30)

local function decode(attribute: string): { [string]: any }
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute(attribute) or "{}")
	end)
	return if ok and type(value) == "table" then value else {}
end

local function cash(): number
	return player:GetAttribute("Cash") or 0
end

-- Which cores the server will use (same rule: the 3 weakest), as "Lv5 · Lv12 Gold".
local function usesText(cores: { [number]: any }, rarity: string): string
	local levels: { number } = {}
	for level in string.gmatch(player:GetAttribute("PedestalLevels") or "", "[^,]+") do
		table.insert(levels, tonumber(level) or 1)
	end
	local picks = {}
	for slot, core in cores do
		if core.rarity == rarity then
			local mutation = core.mutation and (Config.Mutations :: any)[core.mutation]
			local rate = (if mutation then mutation.multiplier else 1)
				* Perks.pedestalIncomeMultiplier(levels[slot] or 1)
				* Perks.sizeMultiplier(core.size)
			table.insert(
				picks,
				{ rate = rate, text = `Lv{levels[slot] or 1}{if core.mutation then " " .. core.mutation else ""}` }
			)
		end
	end
	table.sort(picks, function(a, b)
		return a.rate < b.rate
	end)
	local parts = {}
	for index = 1, math.min(Config.Fuse.Count, #picks) do
		table.insert(parts, picks[index].text)
	end
	return table.concat(parts, " · ")
end

local function refresh()
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local cores = Perks.coresFromSummary(player:GetAttribute("PedestalSummary") or "")
	local rebirths = player:GetAttribute("Rebirths") or 0
	local cultivation = Perks.skillLevel(decode("Skills") :: any, "Cultivation")
	local groups = Fuse.groups(cores :: any, rebirths, cultivation)
	empty.Visible = #groups == 0
	local income = player:GetAttribute("IncomeRate")
	local fee =
		Perks.discounted(Fuse.fee(rebirths, if type(income) == "number" then income else 0), decode("Stats") :: any)
	for index, group in groups do
		local row = UITheme.panel(list, "Row" .. index, C.panel)
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -8, 0, ROW)
		local info = (Config.Rarities :: any)[group.rarity]
		local text = UITheme.label(
			row,
			"Text",
			if group.result
				then `{group.count}x {group.rarity} -> {group.result} · {math.floor(group.chance * 100)}%`
				else `{group.count}x {group.rarity} · top rarity`,
			info and info.color or C.text
		)
		text.Position = UDim2.fromOffset(10, 6)
		text.Size = UDim2.new(1, -150, 0, 22)
		text.TextXAlignment = Enum.TextXAlignment.Left
		local note = UITheme.label(
			row,
			"Note",
			if group.locked and group.result
				then `{group.result} is locked (rebirth / Cultivation)`
				elseif group.count < Config.Fuse.Count then `need {Config.Fuse.Count}`
				else `uses {usesText(cores, group.rarity)} · fee ${Progression.format(fee)}`,
			C.muted
		)
		note.Position = UDim2.fromOffset(10, 28)
		note.Size = UDim2.new(1, -150, 0, 16)
		note.TextXAlignment = Enum.TextXAlignment.Left
		local ready = not group.locked and group.count >= Config.Fuse.Count
		local button = UITheme.button(row, "Fuse", "FUSE", if ready and cash() >= fee then "teal" else "grey")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -8, 0.5, 0)
		button.Size = UDim2.fromOffset(120, 40)
		local rarity = group.rarity
		button.Activated:Connect(function()
			if ready then
				Remotes.get("FuseCores"):FireServer(rarity)
			end
		end)
	end
end

player:GetAttributeChangedSignal("PedestalSummary"):Connect(function()
	if gui.Enabled then
		refresh()
	end
end)

UIRouter.register("Fuse", {
	open = function()
		local camera = Workspace.CurrentCamera
		if camera then
			fit.Scale = math.clamp(
				math.min(camera.ViewportSize.X * 0.94 / WIDTH, camera.ViewportSize.Y * 0.8 / HEIGHT),
				0.6,
				1.25
			)
		end
		refresh()
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Fuse")
end)

gui.Parent = player:WaitForChild("PlayerGui")
