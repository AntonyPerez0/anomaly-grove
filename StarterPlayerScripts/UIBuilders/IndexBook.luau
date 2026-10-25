--!strict
-- Collection Index book (M2-10, expanded M8-09): every rarity x (plain + Gold /
-- Void / Celestial mutation) = 40 entries. Each entry found adds permanent income
-- (Config.IndexIncomePerEntry); a full row pays Rebirth Tokens. Built in code.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)

local IndexBook = {}

export type Book = {
	gui: ScreenGui,
	toggleButton: TextButton,
	page: Frame,
	title: TextLabel,
	cells: { [string]: TextLabel }, -- key = Perks.indexKey(rarity, mutation?)
	rowNames: { [string]: TextLabel },
}

local COLORS = {
	panel = Color3.fromRGB(24, 20, 38),
	cell = Color3.fromRGB(36, 32, 54),
	found = Color3.fromRGB(60, 255, 220),
	missing = Color3.fromRGB(90, 96, 105),
	text = Color3.fromRGB(255, 255, 255),
}
local MUTATIONS = { "Gold", "Void", "Shocked", "Eclipse", "Celestial" } -- M9-06 Shocked, M9-09 Eclipse (limited)
local STEP = 0.64 / #MUTATIONS

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function textLabel(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(10, 8, 18)
	stroke.Parent = label
	return label
end

function IndexBook.build(): Book
	local gui = Instance.new("ScreenGui")
	gui.Name = "IndexBook"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Enabled = false

	local page = Instance.new("Frame")
	page.Name = "Page"
	page.AnchorPoint = Vector2.new(0.5, 0.5)
	page.Position = UDim2.fromScale(0.5, 0.52)
	page.Size = UDim2.fromScale(0.8, 0.8)
	page.BackgroundColor3 = COLORS.panel
	page.BackgroundTransparency = 0.05
	page.Parent = gui
	corner(page, 16)
	local pageStroke = Instance.new("UIStroke")
	pageStroke.Thickness = 3
	pageStroke.Color = Color3.fromRGB(16, 12, 26)
	pageStroke.Parent = page
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(560, 620)
	sizeCap.Parent = page

	local title = textLabel(page, "Title", "Anomaly Index", COLORS.found)
	title.Position = UDim2.fromScale(0.04, 0.015)
	title.Size = UDim2.fromScale(0.82, 0.08)
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- Column headers.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromScale(0.03, 0.1)
	header.Size = UDim2.fromScale(0.94, 0.05)
	header.Parent = page
	local headerName = textLabel(header, "Name", "Rarity", COLORS.text)
	headerName.Size = UDim2.fromScale(0.34, 1)
	for index, mutation in MUTATIONS do
		local h = textLabel(header, mutation, mutation, Config.Mutations[mutation].color)
		h.Position = UDim2.fromScale(0.34 + (index - 1) * STEP, 0)
		h.Size = UDim2.fromScale(STEP - 0.01, 1)
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromScale(0.03, 0.16)
	list.Size = UDim2.fromScale(0.94, 0.82)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local cells: { [string]: TextLabel } = {}
	local rowNames: { [string]: TextLabel } = {}
	for order, rarity in Config.RarityOrder do
		local info = Config.Rarities[rarity :: any]
		local row = Instance.new("Frame")
		row.Name = rarity
		row.LayoutOrder = order
		row.BackgroundColor3 = COLORS.cell
		row.Size = UDim2.new(1, -8, 0, 44)
		row.Parent = list
		corner(row, 10)
		local name = textLabel(row, "Plain", "???", info.color)
		name.Position = UDim2.fromScale(0.02, 0.1)
		name.Size = UDim2.fromScale(0.3, 0.8)
		rowNames[rarity] = name
		cells[rarity] = name
		for index, mutation in MUTATIONS do
			local cell = textLabel(row, mutation, "?", COLORS.missing)
			cell.Position = UDim2.fromScale(0.34 + (index - 1) * STEP, 0.15)
			cell.Size = UDim2.fromScale(STEP - 0.01, 0.7)
			cells[Perks.indexKey(rarity, mutation)] = cell
		end
	end

	-- Legacy toggle button (hidden; the side menu opens the book through the router).
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleIndex"
	toggleButton.Size = UDim2.fromOffset(88, 40)
	toggleButton.Visible = false
	toggleButton.Text = "Index"
	toggleButton.Parent = gui

	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	return {
		gui = gui,
		toggleButton = toggleButton,
		page = page,
		title = title,
		cells = cells,
		rowNames = rowNames,
	}
end

-- Refresh the book from the IndexKeys attribute ("Sprout,Sprout+Gold,mut:Gold,...").
function IndexBook.refresh(book: Book, indexKeys: string?)
	local discovered: { [string]: boolean } = {}
	for key in string.gmatch(indexKeys or "", "[^,]+") do
		discovered[key] = true
	end
	for _, rarity in Config.RarityOrder do
		local info = Config.Rarities[rarity :: any]
		local name = book.rowNames[rarity]
		local complete = Perks.indexRowComplete(discovered, rarity)
		name.Text = if discovered[rarity] then `{if complete then "★ " else ""}{rarity}` else "???"
		name.TextColor3 = if discovered[rarity] then info.color else COLORS.missing
		for _, mutation in MUTATIONS do
			local cell = book.cells[Perks.indexKey(rarity, mutation)]
			local found = discovered[Perks.indexKey(rarity, mutation)] == true
			cell.Text = if found then `✓ x{Config.Mutations[mutation].multiplier}` else "?"
			cell.TextColor3 = if found then Config.Mutations[mutation].color else COLORS.missing
		end
	end
	local entries = Perks.indexEntries(discovered)
	local total = #Config.RarityOrder * 4
	book.title.Text =
		`Anomaly Index {entries}/{total} · +{math.floor(entries * Config.IndexIncomePerEntry * 100)}% income`
end

return IndexBook
