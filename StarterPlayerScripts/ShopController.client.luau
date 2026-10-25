--!strict
-- Shop controller (M5-09): drives the ShopModal from replicated attributes and routes
-- card buttons to the same server remotes / Marketplace prompts the old plot panel
-- used. Opens from the side menu, the hub stalls (ShopTab prompts) and the B key.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HttpService = game:GetService("HttpService")

local UIBuilders = script.Parent:WaitForChild("UIBuilders")
local ShopModal = require(UIBuilders:WaitForChild("ShopModal"))
local UITheme = require(UIBuilders:WaitForChild("UITheme"))
local UIRouter = require(UIBuilders:WaitForChild("UIRouter"))

local player = Players.LocalPlayer

-- Non-legacy client scripts in StarterPlayerScripts can run more than once.
if player:GetAttribute("ShopControllerInitialized") then
	return
end
player:SetAttribute("ShopControllerInitialized", true)

local modal = ShopModal.build(player:WaitForChild("PlayerGui"))
local currentTab = "Base"

-- Robux prices are read from the store once (yields), then cached for the cards.
local robuxPrice: { [string]: string } = {}
local ownedPass: { [string]: boolean } = {}

local PASS_IDS: { [string]: number } = {
	VaultLock = Config.GamePasses.VaultLock,
	OfflineMutationLuck = Config.GamePasses.OfflineMutationLuck,
	DoubleCash = Config.GamePasses.DoubleCash,
	StealTrails = Config.GamePasses.StealTrails,
	BaseAlarmSirens = Config.GamePasses.BaseAlarmSirens,
}
local PRODUCT_IDS: { [string]: number } = {
	InstantLockdown = Config.Products.InstantLockdown,
}

local GADGETS: { [string]: boolean } = { DashBoots = true, SmokeBomb = true, Grapple = true, Lantern = true }
local DEFENSE_REMOTES: { [string]: string } =
	{ Turret = "BuyTurret", LaserDoor = "BuyLaserDoor", TrapTile = "BuyTrapTile" }

local function cash(): number
	return player:GetAttribute("Cash") or 0
end

local function setPrice(card: ShopModal.Card, price: number)
	card.button.Text = `${UITheme.short(price)}`
	UITheme.setStyle(card.button, if cash() >= price then "green" else "grey")
end

local function pedestalReadout(): string
	local summary = player:GetAttribute("PedestalSummary") or ""
	local parts: { string } = {}
	for entry in summary:gmatch("[^|]+") do
		local slot, info = entry:match("(%d+)=(.+)")
		if slot then
			local label = (info:gsub("^seed$", "hatching"))
			local locked = label:sub(-1) == "V"
			if locked then
				label = label:sub(1, -2)
			end
			-- "Void+Gold~Tiny" -> "Tiny Void+Gold" (M9-01 size suffix, readable).
			local base, size = label:match("^(.-)~(%a+)$")
			if base and size then
				label = `{size} {base}`
			end
			if locked then
				label ..= " 🔒"
			end
			table.insert(parts, `P{slot} {label}`)
		end
	end
	return if #parts == 0 then "Claim a plot to build your base" else table.concat(parts, " · ")
end

-- Server mirrors (M8): JSON attributes decoded on demand.
local function decode(attribute: string): { [string]: any }
	local ok, value = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute(attribute) or "{}")
	end)
	return if ok and type(value) == "table" then value else {}
end

local function pedestalLevels(): { number }
	local levels: { number } = {}
	for level in string.gmatch(player:GetAttribute("PedestalLevels") or "", "[^,]+") do
		table.insert(levels, tonumber(level) or 1)
	end
	return levels
end

local function pct(value: number): string
	return `{string.format("%g", value * 100)}%`
end

-- Cheapest pedestal below the level cap: (slot, price) or nil.
local function bestUpgrade(stats: Perks.Stats, rebirths: number): (number?, number?)
	if not Perks.upgradesUnlocked(decode("Skills") :: any) then
		return nil, nil
	end
	-- Same rule as the server's UPGRADE ALL: best income per dollar, cores only.
	local cap = Perks.pedestalCap(rebirths)
	local cores = Perks.coresFromSummary(player:GetAttribute("PedestalSummary") or "")
	local bestSlot, bestPrice, bestValue = nil, nil, 0
	for slot, level in pedestalLevels() do
		local core = cores[slot]
		if core and level < cap then
			local value = Perks.upgradeValue(core.rarity, core.mutation, slot, level, core.size)
			if value > bestValue then
				bestSlot, bestValue = slot, value
				bestPrice = Perks.discounted(Perks.pedestalUpgradeCost(slot, level, rebirths), stats)
			end
		end
	end
	return bestSlot, bestPrice
end

local function refresh()
	local cards = modal.cards
	local stats: Perks.Stats = decode("Stats") :: any
	local rebirths = player:GetAttribute("Rebirths") or 0
	local tokens = player:GetAttribute("Tokens") or 0
	local tree = decode("Tree")
	local upgrades = decode("Upgrades")
	local cultivation = Perks.skillLevel(decode("Skills") :: any, "Cultivation")
	-- Base.
	local slots = player:GetAttribute("PedestalSlots") or 1
	local nextSlot = slots + 1
	if nextSlot > Perks.maxPedestals(stats) then
		cards.Pedestal.title.Text = "Pedestals"
		cards.Pedestal.desc.Text = if nextSlot <= Config.Plot.MaxPedestalSlots
			then "Expansion (Rebirth Tree) unlocks more"
			else "Plot is full"
		cards.Pedestal.button.Text = "MAXED"
		UITheme.setStyle(cards.Pedestal.button, "grey")
	else
		cards.Pedestal.title.Text = `Pedestal {nextSlot}`
		cards.Pedestal.desc.Text = "+1 core slot"
		setPrice(cards.Pedestal, Perks.discounted(Config.Prices.Pedestals[nextSlot - 1], stats))
	end
	-- Rebirth (M8-06): requirement grows; the card says what you gain.
	local netWorth = player:GetAttribute("NetWorth") or 0
	local need = player:GetAttribute("RebirthCost") or Perks.rebirthRequirement(rebirths)
	cards.Rebirth.title.Text = `Rebirth #{rebirths + 1}`
	cards.Rebirth.desc.Text =
		`x{string.format("%.2f", Perks.rebirthMultiplier(rebirths + 1))} income · +{Perks.tokensForRebirth(
			rebirths + 1
		)} token · keeps mutated cores`
	if netWorth >= need then
		cards.Rebirth.button.Text = "REBIRTH!"
		UITheme.setStyle(cards.Rebirth.button, "gold")
	else
		cards.Rebirth.button.Text = `{UITheme.short(netWorth)}/{UITheme.short(need)}`
		UITheme.setStyle(cards.Rebirth.button, "grey")
	end
	-- Upgrades (M8-04).
	local cap = Perks.pedestalCap(rebirths)
	local levels = pedestalLevels()
	local unlocked = Perks.upgradesUnlocked(decode("Skills") :: any)
	for slot = 1, Config.Plot.MaxPedestalSlots do
		local card = cards["PedUp" .. slot]
		local level = levels[slot]
		card.frame.Visible = level ~= nil
		if level then
			card.title.Text = `Pedestal {slot} · Lv {level}`
			if not unlocked then
				card.desc.Text = "Unlocks at Cultivation 10"
				card.button.Text = "🔒"
				UITheme.setStyle(card.button, "grey")
			elseif level >= cap then
				card.desc.Text = `Level cap {cap} (rebirth tier raises it)`
				card.button.Text = "MAX"
				UITheme.setStyle(card.button, "grey")
			else
				card.desc.Text = `-> Lv {level + 1}: x{Config.PedestalUpgrade.IncomeGrowth} income`
				setPrice(card, Perks.discounted(Perks.pedestalUpgradeCost(slot, level, rebirths), stats))
			end
		end
	end
	local _, bestPrice = bestUpgrade(stats, rebirths)
	if not unlocked then
		cards.UpgradeBest.desc.Text = `Plant & hatch to reach Cultivation {Config.PedestalUpgrade.UnlockCultivation}`
		cards.UpgradeBest.button.Text = `🌱 Cultivation {Config.PedestalUpgrade.UnlockCultivation}`
		UITheme.setStyle(cards.UpgradeBest.button, "grey")
	elseif bestPrice then
		cards.UpgradeBest.desc.Text = "Buys every level you can afford"
		cards.UpgradeBest.button.Text = if cash() >= bestPrice then "UPGRADE ALL" else `${UITheme.short(bestPrice)}`
		UITheme.setStyle(cards.UpgradeBest.button, if cash() >= bestPrice then "gold" else "grey")
	else
		cards.UpgradeBest.button.Text = "ALL MAX"
		UITheme.setStyle(cards.UpgradeBest.button, "grey")
	end
	-- Crates (M8-05).
	for _, crate in Config.Crates do
		local card = cards["Crate_" .. crate.id]
		-- Odds shown before buying (transparency; luck perks shift them upward).
		local parts = {}
		for _, rarity in Config.RarityOrder do
			local chance = (crate.odds :: { [string]: number })[rarity]
			if chance then
				table.insert(parts, `{rarity} {math.floor(chance * 1000 + 0.5) / 10}%`)
			end
		end
		card.desc.Text = table.concat(parts, " · ")
		if Perks.crateUnlocked(crate :: any, cultivation) then
			setPrice(
				card,
				Perks.discounted(
					Perks.cratePrice(crate :: any, rebirths, player:GetAttribute("IncomeRate") or 0),
					stats
				)
			)
		else
			card.button.Text = `🌱 Cultivation {crate.cultivation}`
			UITheme.setStyle(card.button, "grey")
		end
	end
	-- Defense + gadget upgrades (M8-08).
	for _, def in Config.Upgrades do
		local card = cards["Up_" .. def.id]
		local level = upgrades[def.id] or 0
		card.title.Text = `{def.name} {level}/{def.max}`
		card.desc.Text = `+{pct(def.per)} {Perks.statName(def.stat)} / level`
		local price = Perks.upgradeCost(def :: any, level)
		if price then
			setPrice(card, Perks.discounted(price, stats))
		else
			card.button.Text = "MAXED"
			UITheme.setStyle(card.button, "teal")
		end
	end
	-- Rebirth Tree (M8-07).
	for _, node in Config.RebirthTree do
		local card = cards["Tree_" .. node.id]
		local level = tree[node.id] or 0
		card.title.Text = `{node.name} {level}/{#node.costs}`
		card.desc.Text = if node.per < 1
			then `+{pct(node.per)} {Perks.statName(node.stat)} / level`
			else `+{node.per} {Perks.statName(node.stat)} / level`
		local cost = Perks.treeCost(node :: any, level)
		if cost then
			card.button.Text = `{cost} TOKEN{if cost == 1 then "" else "S"}`
			UITheme.setStyle(card.button, if tokens >= cost then "gold" else "grey")
		else
			card.button.Text = "MAXED"
			UITheme.setStyle(card.button, "teal")
		end
	end
	-- Defenses.
	for item in DEFENSE_REMOTES do
		setPrice(cards[item], Perks.discounted((Config.Prices :: any)[item] :: number, stats))
	end
	-- Gadgets.
	for item in GADGETS do
		if player:GetAttribute("Gadget_" .. item) == "owned" then
			cards[item].button.Text = "OWNED"
			UITheme.setStyle(cards[item].button, "teal")
		else
			setPrice(cards[item], Perks.discounted((Config.Prices :: any)[item] :: number, stats))
		end
	end
	-- Premium.
	for item, id in PASS_IDS do
		local card = cards[item]
		card.frame.Visible = id > 0
		if item == "OfflineMutationLuck" and player:GetAttribute("PaidRandomRestricted") ~= false then
			-- Paid random items policy: unavailable where restricted (or not yet known).
			card.button.Text = "Unavailable"
			UITheme.setStyle(card.button, "grey")
		elseif ownedPass[item] then
			card.button.Text = "OWNED"
			UITheme.setStyle(card.button, "teal")
		else
			card.button.Text = robuxPrice[item] or "R$"
			UITheme.setStyle(card.button, "gold")
		end
	end
	for item, id in PRODUCT_IDS do
		local card = cards[item]
		card.frame.Visible = id > 0
		card.button.Text = robuxPrice[item] or "R$"
		UITheme.setStyle(card.button, "gold")
	end
	-- Info strip per tab.
	if currentTab == "Base" then
		modal.info.Text = pedestalReadout()
	elseif currentTab == "Upgrades" then
		modal.info.Text =
			`Level cap {cap} · rebirth tier {Perks.rebirthTier(rebirths)} (every {Config.Rebirth.TierEvery} rebirths raises it)`
	elseif currentTab == "Crates" then
		modal.info.Text = `Cultivation {cultivation} · better crates unlock as it grows`
	elseif currentTab == "Rebirth" then
		modal.info.Text = `{tokens} token{if tokens == 1 then "" else "s"} · x{string.format(
			"%.2f",
			Perks.rebirthMultiplier(rebirths)
		)} · rebirth resets levels (rebuy fast, same price)`
	elseif currentTab == "Defenses" then
		modal.info.Text =
			`Defense slots: {Config.Plot.DefenseBaseSlots + (player:GetAttribute("DefenseSlots") or 0)} (rebirth for more)`
	elseif currentTab == "Gadgets" then
		modal.info.Text = "Gadgets are yours forever"
	else
		modal.info.Text = "Support the game & get perks"
	end
end

local function showTab(tab: string)
	if not modal.pages[tab] then
		tab = "Base"
	end
	currentTab = tab
	ShopModal.showTab(modal, tab)
	refresh()
end

local function fit()
	local camera = workspace.CurrentCamera
	if camera then
		modal.scale.Scale = ShopModal.scaleFor(camera.ViewportSize)
	end
end
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end
fit()

UIRouter.register("Shop", {
	open = function(tab: any?)
		showTab(if type(tab) == "string" then tab else currentTab)
		modal.gui.Enabled = true
		UITheme.popIn(modal.root)
	end,
	close = function()
		modal.gui.Enabled = false
	end,
})

modal.closeButton.Activated:Connect(function()
	UIRouter.close("Shop")
end)
for name, tab in modal.tabs do
	tab.Activated:Connect(function()
		showTab(name)
	end)
end

-- Card actions.
local cards = modal.cards
cards.Pedestal.button.Activated:Connect(function()
	Remotes.get("BuyPedestal"):FireServer()
end)
cards.Rebirth.button.Activated:Connect(function()
	local need = player:GetAttribute("RebirthCost") or Config.Rebirth.NetWorthRequired
	if (player:GetAttribute("NetWorth") or 0) >= need then
		Remotes.get("Rebirth"):FireServer()
	end
end)
-- M8 cards: the server re-validates every one of these.
cards.UpgradeBest.button.Activated:Connect(function()
	Remotes.get("UpgradeAll"):FireServer()
end)
for slot = 1, Config.Plot.MaxPedestalSlots do
	cards["PedUp" .. slot].button.Activated:Connect(function()
		Remotes.get("UpgradePedestal"):FireServer(slot)
	end)
end
for _, crate in Config.Crates do
	local id = crate.id
	cards["Crate_" .. id].button.Activated:Connect(function()
		Remotes.get("BuyCrate"):FireServer(id)
	end)
end
for _, def in Config.Upgrades do
	local id = def.id
	cards["Up_" .. id].button.Activated:Connect(function()
		Remotes.get("BuyUpgrade"):FireServer(id)
	end)
end
for _, node in Config.RebirthTree do
	local id = node.id
	cards["Tree_" .. id].button.Activated:Connect(function()
		Remotes.get("BuyTreeNode"):FireServer(id)
	end)
end
for item, remoteName in DEFENSE_REMOTES do
	cards[item].button.Activated:Connect(function()
		Remotes.get(remoteName :: any):FireServer()
	end)
end
for item in GADGETS do
	cards[item].button.Activated:Connect(function()
		if player:GetAttribute("Gadget_" .. item) ~= "owned" then
			Remotes.get("BuyGadget"):FireServer(item)
		end
	end)
end
for item, id in PASS_IDS do
	cards[item].button.Activated:Connect(function()
		local blocked = item == "OfflineMutationLuck" and player:GetAttribute("PaidRandomRestricted") ~= false
		if id > 0 and not ownedPass[item] and not blocked then
			MarketplaceService:PromptGamePassPurchase(player, id)
		end
	end)
end
for item, id in PRODUCT_IDS do
	cards[item].button.Activated:Connect(function()
		if id > 0 then
			MarketplaceService:PromptProductPurchase(player, id)
		end
	end)
end

-- Store data (prices + ownership) loads in the background.
task.spawn(function()
	for item, id in PASS_IDS do
		if id > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
			end)
			if ok and info and info.PriceInRobux then
				robuxPrice[item] = `R$ {info.PriceInRobux}`
			end
			local okOwned, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			ownedPass[item] = okOwned and owned == true
		end
	end
	for item, id in PRODUCT_IDS do
		if id > 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				robuxPrice[item] = `R$ {info.PriceInRobux}`
			end
		end
	end
	refresh()
end)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(who, passId, purchased)
	if who ~= player or not purchased then
		return
	end
	for item, id in PASS_IDS do
		if id == passId then
			ownedPass[item] = true
		end
	end
	refresh()
end)

for _, attribute in
	{
		"Cash",
		"PedestalSlots",
		"NetWorth",
		"DefenseSlots",
		"PedestalSummary",
		"Stats",
		"Tokens",
		"Tree",
		"Upgrades",
		"PedestalLevels",
		"Skills",
		"Rebirths",
		"RebirthCost",
	}
do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if modal.gui.Enabled then
			refresh()
		end
	end)
end
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 7) == "Gadget_" and modal.gui.Enabled then
		refresh()
	end
end)

-- M8-11: a "!" on the SHOP button whenever a pedestal / upgrade is affordable,
-- so there is always a visible next step without opening anything.
task.spawn(function()
	local side = player:WaitForChild("PlayerGui"):WaitForChild("SideMenu", 30)
	local column = side and side:WaitForChild("Column", 10)
	local shopButton = column and column:WaitForChild("Shop", 10)
	if not shopButton then
		return
	end
	local dot = UITheme.label(shopButton, "Badge", "!", Color3.new(1, 1, 1))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -2, 0, 2)
	dot.Size = UDim2.fromOffset(22, 22)
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = UITheme.COLORS.red
	UITheme.corner(dot, 11)
	while true do
		local stats: Perks.Stats = decode("Stats") :: any
		local rebirths = player:GetAttribute("Rebirths") or 0
		local slots = player:GetAttribute("PedestalSlots") or 1
		local cheapest = math.huge
		if slots + 1 <= Perks.maxPedestals(stats) then
			cheapest = Perks.discounted(Config.Prices.Pedestals[slots], stats)
		end
		local _, upgradePrice = bestUpgrade(stats, rebirths)
		if upgradePrice then
			cheapest = math.min(cheapest, upgradePrice)
		end
		local rebirthReady = (player:GetAttribute("NetWorth") or 0) >= (player:GetAttribute("RebirthCost") or math.huge)
		dot.Visible = player:GetAttribute("PlotIndex") ~= nil and (cash() >= cheapest or rebirthReady)
		task.wait(1)
	end
end)

-- Hub stalls: their prompts carry the tab to open.
ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who == player and prompt.Name == "ShopPrompt" and prompt.Parent then
		local tab = prompt.Parent:GetAttribute("ShopTab")
		-- M9-04/05: the Traveling Market and Fuse Machine stalls open their own modals.
		if tab == "Market" or tab == "Fuse" then
			UIRouter.open(tab)
		else
			UIRouter.open("Shop", tab)
		end
	end
end)

-- Desktop hotkey.
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B then
		UIRouter.toggle("Shop")
	end
end)

showTab("Base")
