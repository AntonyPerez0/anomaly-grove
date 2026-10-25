--!strict
-- Traveling Market modal (M9-04): opened from the hub stall. Shows the 4 current
-- offers, what each seed does, your price (income-scaled, Commerce discount),
-- stock left and the restock countdown. Purchases go through MarketBuy; the server
-- re-checks everything.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Zones = require(ReplicatedStorage.Shared.Zones)

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

if player:GetAttribute("MarketControllerInitialized") then
	return
end
player:SetAttribute("MarketControllerInitialized", true)

local C = UITheme.COLORS
local WIDTH, HEIGHT = 440, 340

local DESCRIPTIONS: { [string]: string } = {
	regular = "3 forest seeds",
	grove = "Mutates at the night chance all day",
}

local function describe(give: string): string
	if DESCRIPTIONS[give] then
		return DESCRIPTIONS[give]
	end
	local def, zone = Zones.seed(give)
	if zone then
		return zone.blurb
	end
	if def then
		return "Void or better · Prismatic after rebirths"
	end
	return ""
end

local function offerColor(give: string): Color3
	if give == "grove" then
		return Config.Mutations.Gold.color
	end
	return Zones.seedColor(give) or C.teal
end

local gui = Instance.new("ScreenGui")
gui.Name = "MarketModal"
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
local title = UITheme.label(root, "Title", "TRAVELING MARKET", Color3.fromRGB(210, 150, 255))
title.Position = UDim2.fromOffset(16, 8)
title.Size = UDim2.new(1, -80, 0, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local timer = UITheme.label(root, "Timer", "", C.muted)
timer.Position = UDim2.fromOffset(16, 44)
timer.Size = UDim2.new(1, -32, 0, 18)
timer.TextXAlignment = Enum.TextXAlignment.Left
local close = UITheme.button(root, "Close", "X", "red")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, 8, 0, -8)
close.Size = UDim2.fromOffset(48, 48)

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(12, 70)
grid.Size = UDim2.new(1, -24, 1, -82)
grid.Parent = root
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.new(0.5, -5, 0.5, -5)
layout.CellPadding = UDim2.fromOffset(10, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

type Card = { frame: Frame, name: TextLabel, desc: TextLabel, left: TextLabel, buy: TextButton }
local cards: { Card } = {}
for index = 1, Config.Market.Slots do
	local frame = UITheme.panel(grid, "Offer" .. index, C.panel)
	frame.LayoutOrder = index
	local name = UITheme.label(frame, "Name", "", C.text)
	name.Position = UDim2.fromOffset(8, 6)
	name.Size = UDim2.new(1, -16, 0, 24)
	local desc = UITheme.label(frame, "Desc", "", C.muted)
	desc.Position = UDim2.fromOffset(8, 32)
	desc.Size = UDim2.new(1, -16, 0, 16)
	local left = UITheme.label(frame, "Left", "", C.muted)
	left.Position = UDim2.fromOffset(8, 50)
	left.Size = UDim2.new(1, -16, 0, 14)
	local buy = UITheme.button(frame, "Buy", "BUY", "green")
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -6)
	buy.Size = UDim2.new(1, -16, 0, 40)
	local slotIndex = index
	buy.Activated:Connect(function()
		Remotes.get("MarketBuy"):FireServer(slotIndex)
	end)
	cards[index] = { frame = frame, name = name, desc = desc, left = left, buy = buy }
end

local function stats(): Perks.Stats
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Stats") or "{}")
	end)
	return if ok and type(value) == "table" then value :: any else {} :: any
end

local function offerById(id: string): typeof(Config.Market.Offers[1])?
	for _, offer in Config.Market.Offers do
		if offer.id == id then
			return offer
		end
	end
	return nil
end

local function refresh()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(Workspace:GetAttribute("MarketStock") or "[]")
	end)
	local stock: { { id: string, left: number } } = if ok and type(list) == "table" then list else {}
	local income = player:GetAttribute("IncomeRate")
	local rebirths = player:GetAttribute("Rebirths") or 0
	local current = stats()
	local cash = player:GetAttribute("Cash") or 0
	for index, card in cards do
		local entry = stock[index]
		local offer = entry and offerById(entry.id)
		card.frame.Visible = offer ~= nil
		if offer then
			local price = Perks.discounted(
				Perks.scaledReward(
					Config.Market.MinPrice,
					rebirths,
					if type(income) == "number" then income else 0,
					offer.priceSeconds
				),
				current
			)
			card.name.Text = offer.name
			card.name.TextColor3 = offerColor(offer.give)
			card.desc.Text = describe(offer.give)
			card.left.Text = if entry.left > 0 then `{entry.left} left in this server` else "SOLD OUT"
			card.buy.Text = if entry.left > 0 then `BUY ${Progression.format(price)}` else "SOLD OUT"
			UITheme.setStyle(card.buy, if entry.left > 0 and cash >= price then "green" else "grey")
		end
	end
end

local function updateTimer()
	local restockAt = Workspace:GetAttribute("MarketRestockAt")
	if type(restockAt) == "number" then
		local left = math.max(0, restockAt - os.time())
		timer.Text =
			`New stock in {math.floor(left / 60)}:{string.format("%02d", left % 60)} · same offers in every server`
	end
end

Workspace:GetAttributeChangedSignal("MarketStock"):Connect(function()
	if gui.Enabled then
		refresh()
	end
end)
player:GetAttributeChangedSignal("Cash"):Connect(function()
	if gui.Enabled then
		refresh()
	end
end)

UIRouter.register("Market", {
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
		updateTimer()
		gui.Enabled = true
		UITheme.popIn(root)
	end,
	close = function()
		gui.Enabled = false
	end,
})
close.Activated:Connect(function()
	UIRouter.close("Market")
end)

gui.Parent = player:WaitForChild("PlayerGui")

task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled then
			updateTimer()
		end
	end
end)
