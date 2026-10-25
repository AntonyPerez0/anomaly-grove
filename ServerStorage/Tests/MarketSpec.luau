--!strict
-- M9-04 Traveling Market.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage.Shared.Config)
local Zones = require(ReplicatedStorage.Shared.Zones)
local MarketService = require(ServerScriptService.MarketService)

local TestKit = require(script.Parent.TestKit)

return function(t: TestKit.Context)
	t.describe("Traveling Market (M9-04)", function()
		t.it("each window rolls Slots different offers, the same on every server", function()
			for w = 1, 50 do
				local offers = MarketService.rollOffers(w)
				t.equal(#offers, Config.Market.Slots)
				local seen = {}
				for _, offer in offers do
					t.equal(seen[offer.id], nil)
					seen[offer.id] = true
				end
				t.deepEqual(MarketService.rollOffers(w), offers)
			end
		end)

		t.it("every offer gives something real", function()
			for _, offer in Config.Market.Offers do
				t.truthy(offer.give == "regular" or offer.give == "grove" or Zones.seed(offer.give) ~= nil, offer.id)
			end
			for _, def in Config.Market.SpecialSeeds do
				local total = 0
				for _, chance in def.odds do
					total += chance
				end
				t.near(total, 1, 1e-6)
			end
		end)

		t.it("prices scale with income and have a floor", function()
			local offer = Config.Market.Offers[1]
			t.equal(MarketService.priceFor(offer, 0, 1000), 1000 * offer.priceSeconds)
			t.equal(MarketService.priceFor(offer, 0, 0), Config.Market.MinPrice)
		end)

		t.it("the Starfall Seed ranks as the best special seed", function()
			t.equal(Zones.seedOrder()[1], "StarfallSeed")
			t.equal(MarketService.windowAt(Config.Market.RestockSeconds * 10 + 5), 10)
		end)
	end)
end
