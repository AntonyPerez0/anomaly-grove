--!strict
-- Shop modal (M5-09): tabs (Base / Defenses / Gadgets / Premium) of 2-column cards
-- - icon, name, effect, price button. Replaces the always-open plot panel. Pure
-- builder: ShopController fills prices/states and routes the buttons.

local UITheme = require(script.Parent:WaitForChild("UITheme"))
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ShopModal = {}

export type Card = {
	frame: Frame,
	title: TextLabel,
	desc: TextLabel,
	button: TextButton,
}

export type Modal = {
	gui: ScreenGui,
	root: Frame,
	scale: UIScale,
	tabs: { [string]: TextButton },
	pages: { [string]: ScrollingFrame },
	cards: { [string]: Card },
	info: TextLabel,
	closeButton: TextButton,
}

export type ItemDef = { id: string, tab: string, icon: string, name: string, desc: string, order: number }

ShopModal.TABS = { "Base", "Upgrades", "Crates", "Defenses", "Gadgets", "Rebirth", "Premium" }
ShopModal.TAB_LABELS = {
	Base = "🏠 Base",
	Upgrades = "⬆ Upgrades",
	Crates = "📦 Crates",
	Defenses = "🛡 Defense",
	Gadgets = "⚡ Gadgets",
	Rebirth = "🌀 Rebirth",
	Premium = "💎 Premium",
}
local TAB_WIDTH = 104

ShopModal.ITEMS = {
	{ id = "Pedestal", tab = "Base", icon = "🏛", name = "Pedestal", desc = "+1 core slot", order = 1 },
	{
		id = "Rebirth",
		tab = "Rebirth",
		icon = "🌀",
		name = "Rebirth",
		desc = "Bigger income multiplier + tokens",
		order = 0,
	},
	{ id = "Turret", tab = "Defenses", icon = "🗼", name = "Turret", desc = "Zaps raiders + 1.5s stun", order = 1 },
	{
		id = "LaserDoor",
		tab = "Defenses",
		icon = "⚡",
		name = "Laser Door",
		desc = "Burns rivals at your gate",
		order = 2,
	},
	{ id = "TrapTile", tab = "Defenses", icon = "🕸", name = "Trap Tile", desc = "Roots raiders for 2s", order = 3 },
	{ id = "DashBoots", tab = "Gadgets", icon = "👟", name = "Dash Boots", desc = "[Q] 4s speed burst", order = 1 },
	{
		id = "SmokeBomb",
		tab = "Gadgets",
		icon = "💨",
		name = "Smoke Bomb",
		desc = "[R] invisible to monsters",
		order = 2,
	},
	{
		id = "Lantern",
		tab = "Gadgets",
		icon = "🏮",
		name = "Lantern",
		desc = "[G] flash stuns monsters 3s",
		order = 4,
	},
	{ id = "Grapple", tab = "Gadgets", icon = "🪝", name = "Grapple", desc = "[T] 60-stud hook", order = 3 },
	{
		id = "VaultLock",
		tab = "Premium",
		icon = "🔒",
		name = "Vault Lock",
		desc = "Pedestal 1 can never be stolen",
		order = 1,
	},
	{
		id = "OfflineMutationLuck",
		tab = "Premium",
		icon = "🍀",
		name = "2x Offline Luck",
		desc = "Offline mutation chance 2% -> 4% per 5 min (Gold 70% · Void 25% · Celestial 5%)",
		order = 2,
	},
	{
		id = "InstantLockdown",
		tab = "Premium",
		icon = "🛡",
		name = "Instant Lockdown",
		desc = "60s plot shield (3/night)",
		order = 3,
	},
	{
		id = "DoubleCash",
		tab = "Premium",
		icon = "💰",
		name = "2x Cash",
		desc = "Double core income, forever",
		order = 0,
	},
	{
		id = "StealTrails",
		tab = "Premium",
		icon = "🌈",
		name = "Steal Trails",
		desc = "Rainbow trail on carried cores",
		order = 4,
	},
	{
		id = "BaseAlarmSirens",
		tab = "Premium",
		icon = "🚨",
		name = "Base Alarm",
		desc = "Siren + flash when raided",
		order = 5,
	},
} :: { ItemDef }

-- M8 cards generated from Config: pedestal levels, crates, upgrades, tree nodes.
table.insert(ShopModal.ITEMS, {
	id = "UpgradeBest",
	tab = "Upgrades",
	icon = "⬆",
	name = "Upgrade All",
	desc = "Buys every level you can afford",
	order = 0,
})
for slot = 1, Config.Plot.MaxPedestalSlots do
	table.insert(ShopModal.ITEMS, {
		id = "PedUp" .. slot,
		tab = "Upgrades",
		icon = "🏛",
		name = "Pedestal " .. slot,
		desc = "",
		order = slot,
	})
end
for index, crate in Config.Crates do
	table.insert(ShopModal.ITEMS, {
		id = "Crate_" .. crate.id,
		tab = "Crates",
		icon = "📦",
		name = crate.name,
		desc = "",
		order = index,
	})
end
local UPGRADE_ICONS: { [string]: string } = {
	TurretPower = "🗼",
	LaserPower = "⚡",
	TrapGrip = "🕸",
	DashTuning = "👟",
	SmokeTuning = "💨",
	GrappleTuning = "🪝",
}
for index, def in Config.Upgrades do
	table.insert(ShopModal.ITEMS, {
		id = "Up_" .. def.id,
		tab = def.tab,
		icon = UPGRADE_ICONS[def.id] or "⬆",
		name = def.name,
		desc = "",
		order = 10 + index,
	})
end
local BRANCH_ICONS: { [string]: string } = {
	Growth = "🌱",
	Luck = "🍀",
	Mutation = "🧪",
	Thief = "🦝",
	Guardian = "🛡",
	Expansion = "🏛",
	Fortune = "💰",
	Wisdom = "📚",
}
for index, node in Config.RebirthTree do
	table.insert(ShopModal.ITEMS, {
		id = "Tree_" .. node.id,
		tab = "Rebirth",
		icon = BRANCH_ICONS[node.branch] or "⭐",
		name = node.name,
		desc = "",
		order = index,
	})
end

local DESIGN = Vector2.new(400, 500)
local C = UITheme.COLORS

-- Fit the design size into the viewport (phones shrink, big screens grow a little).
function ShopModal.scaleFor(viewport: Vector2): number
	return math.clamp(math.min(viewport.X * 0.94 / DESIGN.X, viewport.Y * 0.86 / DESIGN.Y), 0.55, 1.25)
end

local function buildCard(page: ScrollingFrame, item: ItemDef): Card
	local frame = UITheme.panel(page, "Card_" .. item.id, C.panel)
	frame.LayoutOrder = item.order
	local icon = UITheme.label(frame, "Icon", item.icon, C.text)
	icon.Position = UDim2.fromOffset(0, 6)
	icon.Size = UDim2.new(1, 0, 0, 44)
	local title = UITheme.label(frame, "Title", item.name, C.text)
	title.Position = UDim2.fromOffset(6, 52)
	title.Size = UDim2.new(1, -12, 0, 24)
	local desc = UITheme.label(frame, "Desc", item.desc, C.muted)
	desc.Position = UDim2.fromOffset(8, 78)
	desc.Size = UDim2.new(1, -16, 0, 34)
	desc.TextWrapped = true
	-- Short texts must not balloon (TextScaled grows "+1 core slot" to fill the box).
	local descCap = Instance.new("UITextSizeConstraint")
	descCap.MaxTextSize = 15
	descCap.Parent = desc
	local titleCap = Instance.new("UITextSizeConstraint")
	titleCap.MaxTextSize = 22
	titleCap.Parent = title
	local button = UITheme.button(frame, "Buy", "...", "green")
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -8)
	button.Size = UDim2.new(1, -16, 0, 40)
	return { frame = frame, title = title, desc = desc, button = button }
end

function ShopModal.build(parent: Instance): Modal
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopModal"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	gui.Enabled = false

	-- Dim backdrop (tap outside does nothing; the X closes).
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.55
	dim.Parent = gui

	local root = UITheme.panel(gui, "Root", C.panelDeep)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = root

	local title = UITheme.label(root, "Title", "SHOP", C.gold)
	title.Position = UDim2.fromOffset(16, 8)
	title.Size = UDim2.new(1, -80, 0, 38)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeButton = UITheme.button(root, "Close", "X", "red")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, 8, 0, -8)
	closeButton.Size = UDim2.fromOffset(48, 48)

	-- Tabs row (scrolls sideways: 7 tabs do not fit a phone-width modal).
	local tabs: { [string]: TextButton } = {}
	local tabRow = Instance.new("ScrollingFrame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.BorderSizePixel = 0
	tabRow.Position = UDim2.fromOffset(10, 52)
	tabRow.Size = UDim2.new(1, -20, 0, 44)
	tabRow.ScrollBarThickness = 3
	tabRow.ScrollingDirection = Enum.ScrollingDirection.X
	tabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabRow.CanvasSize = UDim2.new()
	tabRow.Parent = root
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow
	for index, name in ShopModal.TABS do
		local tab = UITheme.button(tabRow, "Tab_" .. name, ShopModal.TAB_LABELS[name], "grey")
		tab.LayoutOrder = index
		tab.Size = UDim2.fromOffset(TAB_WIDTH, 40)
		tabs[name] = tab
	end

	-- Info strip (pedestal readout / defense slots / tab hints).
	local info = UITheme.label(root, "Info", "", C.muted)
	info.Position = UDim2.fromOffset(12, 98)
	info.Size = UDim2.new(1, -24, 0, 22)

	-- One scrolling page of cards per tab.
	local pages: { [string]: ScrollingFrame } = {}
	local cards: { [string]: Card } = {}
	for _, name in ShopModal.TABS do
		local page = Instance.new("ScrollingFrame")
		page.Name = "Page_" .. name
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.fromOffset(12, 126)
		page.Size = UDim2.new(1, -24, 1, -138)
		page.ScrollBarThickness = 6
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.CanvasSize = UDim2.new()
		page.Visible = false
		page.Parent = root
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(0.5, -6, 0, 170)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = page
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 4)
		pad.PaddingLeft = UDim.new(0, 2)
		pad.PaddingRight = UDim.new(0, 2)
		pad.Parent = page
		pages[name] = page
	end
	for _, item in ShopModal.ITEMS do
		cards[item.id] = buildCard(pages[item.tab], item)
	end

	gui.Parent = parent
	return {
		gui = gui,
		root = root,
		scale = scale,
		tabs = tabs,
		pages = pages,
		cards = cards,
		info = info,
		closeButton = closeButton,
	}
end

-- Show one tab page and highlight its tab button.
function ShopModal.showTab(modal: Modal, tabName: string)
	for name, page in modal.pages do
		page.Visible = name == tabName
	end
	for name, tab in modal.tabs do
		UITheme.setStyle(tab, if name == tabName then "teal" else "grey")
	end
end

return ShopModal
