--!strict
-- Wild zones past the ring wall (2026-10-18): lookups and geometry shared by the
-- server (seeds, guardians) and the client (zone title banner).

local Config = require(script.Parent.Config)

local Zones = {}

export type ZoneDef = Config.ZoneDef
export type ZoneSeedDef = Config.ZoneSeedDef

function Zones.list(): { ZoneDef }
	return Config.Zones.List
end

function Zones.get(id: string): ZoneDef?
	for _, zone in Config.Zones.List do
		if zone.id == id then
			return zone
		end
	end
	return nil
end

-- The special seed with this id (zone seeds like "CrystalSeed", or market-only
-- seeds like "StarfallSeed") and the zone it comes from (nil for market seeds).
function Zones.seed(seedId: string): (ZoneSeedDef?, ZoneDef?)
	for _, zone in Config.Zones.List do
		if zone.seed.id == seedId then
			return zone.seed, zone
		end
	end
	for _, def in Config.Market.SpecialSeeds do
		if def.id == seedId then
			return def :: any, nil
		end
	end
	return nil, nil
end

-- Colour shown for a special seed (zone colour, or the market seed's own).
function Zones.seedColor(seedId: string): Color3?
	local def, zone = Zones.seed(seedId)
	if zone then
		return zone.color
	end
	return if def then (def :: any).color else nil
end

-- Every special seed id, best first (expected base income of its odds).
function Zones.seedOrder(): { string }
	local scored: { { id: string, score: number } } = {}
	local function add(id: string, odds: { [string]: number })
		local score = 0
		for rarity, chance in odds do
			local info = (Config.Rarities :: any)[rarity]
			score += (if info then info.cashPerSecond else 0) * chance
		end
		table.insert(scored, { id = id, score = score })
	end
	for _, zone in Config.Zones.List do
		add(zone.seed.id, zone.seed.odds)
	end
	for _, def in Config.Market.SpecialSeeds do
		add(def.id, def.odds)
	end
	table.sort(scored, function(a, b)
		return a.score > b.score
	end)
	local out = {}
	for _, entry in scored do
		table.insert(out, entry.id)
	end
	return out
end

-- Unit vector from the map centre towards the zone (y = 0).
function Zones.direction(zone: ZoneDef): Vector3
	local a = math.rad(zone.angle)
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

function Zones.center(zone: ZoneDef): Vector3
	return Zones.direction(zone) * Config.Zones.CenterRadius
end

-- The zone whose clearing contains `position` (flat distance, plus `margin`).
function Zones.at(position: Vector3, margin: number?): ZoneDef?
	local flat = Vector3.new(position.X, 0, position.Z)
	for _, zone in Config.Zones.List do
		if (flat - Zones.center(zone)).Magnitude <= Config.Zones.Radius + (margin or 0) then
			return zone
		end
	end
	return nil
end

-- Can a player with this Foraging level harvest the zone's seeds?
function Zones.canHarvest(zone: ZoneDef, foragingLevel: number): boolean
	return foragingLevel >= zone.foraging
end

return Zones
