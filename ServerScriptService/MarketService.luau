--!strict
-- Traveling Market (M9-04): a hub stall with 4 rotating offers. The offer roll is
-- seeded by the restock window number, so every server shows the same offers and
-- the same countdown; stock is per server, so a rare offer is a race. Prices scale
-- with the buyer's income (server-side, never trusted from the client).
-- Replicated on Workspace: MarketWindow, MarketRestockAt (os.time), MarketStock
-- (JSON list of { id, left }).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Perks = require(ReplicatedStorage.Shared.Perks)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerState = require(script.Parent.PlayerState)
local SkillService = require(script.Parent.SkillService)
local FXService = require(script.Parent.FXService)
local QuestService = require(script.Parent.QuestService)

local MarketService = {}

export type Offer = typeof(Config.Market.Offers[1])
type Slot = { offer: Offer, left: number }

local window = -1
local slots: { Slot } = {}
local bought: { [number]: { [number]: number } } = {} -- UserId -> slot -> count (this window; survives rejoin)

-- Pure: the restock window an os.time() falls in.
function MarketService.windowAt(now: number): number
	return math.floor(now / Config.Market.RestockSeconds)
end

-- Pure: the offers for a window (weighted, no repeats). Same on every server.
function MarketService.rollOffers(windowNumber: number): { Offer }
	local rng = Random.new(windowNumber * 7919 + 17)
	local pool = table.clone(Config.Market.Offers)
	local picked: { Offer } = {}
	for _ = 1, math.min(Config.Market.Slots, #pool) do
		local total = 0
		for _, offer in pool do
			total += offer.weight
		end
		local roll = rng:NextNumber() * total
		local cumulative = 0
		for index, offer in pool do
			cumulative += offer.weight
			if roll < cumulative or index == #pool then
				table.insert(picked, offer)
				table.remove(pool, index)
				break
			end
		end
	end
	return picked
end

-- Pure: what an offer costs this player (before the Commerce discount).
function MarketService.priceFor(offer: Offer, rebirths: number, income: number): number
	return Perks.scaledReward(Config.Market.MinPrice, rebirths, income, offer.priceSeconds)
end

local function publish()
	local list = {}
	for _, slot in slots do
		table.insert(list, { id = slot.offer.id, left = slot.left })
	end
	Workspace:SetAttribute("MarketWindow", window)
	Workspace:SetAttribute("MarketRestockAt", (window + 1) * Config.Market.RestockSeconds)
	Workspace:SetAttribute("MarketStock", HttpService:JSONEncode(list))
end

local function restock(windowNumber: number, announce: boolean)
	window = windowNumber
	table.clear(slots)
	table.clear(bought)
	local rare = false
	for _, offer in MarketService.rollOffers(windowNumber) do
		table.insert(slots, { offer = offer, left = offer.stock })
		rare = rare or offer.id == "StarfallSeed" or offer.id == "RelicSeed"
	end
	publish()
	if announce then
		Remotes.get("TutorialToast"):FireAllClients(
			if rare
				then "The Traveling Merchant restocked - something RARE is on sale at the hub!"
				else "The Traveling Merchant restocked at the hub"
		)
	end
	print(`[MarketService] window {windowNumber} restocked{if rare then " (rare offer)" else ""}`)
end

-- Give the goods; false when the seed bag has no room.
local function deliver(player: Player, offer: Offer): boolean
	local state = PlayerState.get(player)
	local capacity = Config.Seeds.MaxCarriedSeeds + math.floor(Perks.get(SkillService.stats(state), "seedBag"))
	if PlayerState.seedCount(state) + offer.count > capacity then
		return false
	end
	if offer.give == "regular" then
		state.seedsCarried += offer.count
		player:SetAttribute("SeedsCarried", state.seedsCarried)
	elseif offer.give == "grove" then
		state.groveSeeds += offer.count
		player:SetAttribute("GroveSeedsCarried", state.groveSeeds)
	else
		PlayerState.addZoneSeed(state, offer.give, offer.count)
	end
	return true
end

function MarketService.buy(player: Player, slotIndex: number): boolean
	local slot = slots[slotIndex]
	if not slot then
		return false
	end
	local state = PlayerState.get(player)
	if player:GetAttribute("ProfileLoaded") ~= true then
		return false
	end
	local mine = bought[player.UserId] or {}
	if slot.left <= 0 then
		Remotes.get("TutorialToast"):FireClient(player, "Sold out! Wait for the next restock")
		return false
	end
	if (mine[slotIndex] or 0) >= slot.offer.perPlayer then
		Remotes.get("TutorialToast"):FireClient(player, "You already bought your share of that one")
		return false
	end
	local stats = SkillService.stats(state)
	local price =
		Perks.discounted(MarketService.priceFor(slot.offer, state.rebirths, PlayerState.incomeRate(state)), stats)
	if state.cash < price then
		Remotes.get("TutorialToast"):FireClient(player, "Not enough cash")
		return false
	end
	if not deliver(player, slot.offer) then
		Remotes.get("TutorialToast"):FireClient(player, "Your seed bag is full")
		return false
	end
	PlayerState.spendCash(state, price)
	slot.left -= 1
	mine[slotIndex] = (mine[slotIndex] or 0) + 1
	bought[player.UserId] = mine
	SkillService.addCommerceXp(player, price)
	FXService.purchase(player)
	QuestService.record(player, "buy")
	publish()
	print(`[MarketService] {player.Name} bought {slot.offer.id} for {price} ({slot.left} left)`)
	return true
end

function MarketService.init()
	restock(MarketService.windowAt(os.time()), false)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = MarketService.windowAt(os.time())
			if now ~= window then
				restock(now, true)
			end
		end
	end)
	task.spawn(function()
		Remotes.get("MarketBuy").OnServerEvent:Connect(function(player, slotIndex)
			if type(slotIndex) == "number" and slotIndex == math.floor(slotIndex) then
				MarketService.buy(player, slotIndex)
			end
		end)
	end)
end

return MarketService
