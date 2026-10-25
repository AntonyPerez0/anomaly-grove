--!strict
-- Central place for every tunable number in the game (prices, speeds, cooldowns, rewards).
-- Shared by server and client. Read-only at runtime: the server is still the authority.
-- Every number here comes from docs/GDD.md; when tuning, update the GDD section too.

export type ZoneSeedDef = {
	id: string,
	name: string,
	odds: { [string]: number },
	boost: boolean,
}

export type ZoneDef = {
	id: string,
	name: string,
	angle: number,
	color: Color3,
	foraging: number,
	guardian: string,
	guardians: number,
	guardianName: string, -- shown on the zone banner
	blurb: string,
	seed: ZoneSeedDef,
}

local Config = {
	-- Monetization IDs are wired for launch (created on the Creator Dashboard,
	-- see docs/LAUNCH_CHECKLIST.md). 0 means "not created yet" — feature stays hidden.
	GamePasses = {
		VaultLock = 2038023414, -- grants 1 un-stealable pedestal slot (dashboard: 199 R$)
		OfflineMutationLuck = 2040164994, -- 2x offline mutation roll luck (dashboard: 149 R$)
		StealTrails = 2036199548, -- cosmetic (dashboard: 49 R$)
		BaseAlarmSirens = 2039961292, -- cosmetic (dashboard: 49 R$)
		DoubleCash = 2038359527, -- M7: x2 core income forever (dashboard: 99 R$)
	},
	DoubleCashMultiplier = 2,
	Products = {
		InstantLockdown = 3719351008, -- consumable: 60 s plot shield, max 3/night (dashboard: 49 R$)
	},

	Server = {
		MaxPlayers = 8,
	},

	Map = {
		Plots = 8,
		-- M5-03: map scaled ~1.4x (was plot 70 / ring 260 / forest 140).
		PlotSize = 90,
		PlotSpacingDegrees = 45,
		RingRadius = 360, -- outer stone ring wall
		ForestRadius = 200, -- central contested forest
		OuterCorridor = 50, -- walkable ring between the plots' outer walls and the ring wall
		GroveHeartRadius = 12, -- night-only mutated node circle at exact center
		HubSize = 40, -- spawn platform on the ring wall
		WallHeight = 12, -- ring wall + hub platform height
		ClaimDistance = 45, -- server-side reach gate for the ClaimPlot remote (to the plot centre)
		TerrainRadius = 620, -- smooth terrain extent (backdrop hills live past the wall)
		PathWidth = 10, -- dirt paths from plot gates to the Grove Heart
		Pond = { X = 46, Z = 111, Radius = 16 }, -- between two paths; seed nodes avoid it
	},

	-- Physical leaderboards on the hub (M3-06).
	Leaderboards = {
		RefreshSeconds = 60, -- write + re-read cadence
		Rows = 10, -- top N shown per board
	},

	Cycle = {
		DayLength = 240,
		NightLength = 120,
	},

	Seeds = {
		HarvestTime = 1.5, -- proximity prompt hold
		HarvestDistance = 10, -- server-side distance gate for the mobile-button remote path
		MaxCarriedSeeds = 3,
		NodeRespawnSeconds = 30,
		MinNodes = 8, -- M5-03: bigger forest keeps the same node density
		MaxNodes = 14,
		GroveHeartNodes = 3, -- night-only mutated nodes at map center
	},

	Incubation = {
		Duration = 60,
		PlaceHoldTime = 0.5, -- pedestal prompt hold to place a seed
		PedestalCycleBonus = 0.1, -- +10% cash rate per completed incubation cycle on that pedestal
	},

	-- chance values must sum to 1. `tier` orders rarities (Rebirth keeps Ember and above).
	-- `heavy` = slow carry multiplier while being carried (GDD 5.3).
	Rarities = {
		Sprout = {
			chance = 0.62,
			cashPerSecond = 1,
			tier = 1,
			heavy = false,
			color = Color3.fromRGB(85, 255, 120), -- green
		},
		Amber = {
			chance = 0.25,
			cashPerSecond = 3,
			tier = 2,
			heavy = false,
			color = Color3.fromRGB(255, 170, 60), -- orange
		},
		Frost = {
			chance = 0.09,
			cashPerSecond = 8,
			tier = 3,
			heavy = false,
			color = Color3.fromRGB(90, 225, 255), -- cyan
		},
		Ember = {
			chance = 0.032,
			cashPerSecond = 20,
			tier = 4,
			heavy = false,
			color = Color3.fromRGB(255, 80, 70), -- red
		},
		Void = {
			chance = 0.007,
			cashPerSecond = 50,
			tier = 5,
			heavy = true,
			color = Color3.fromRGB(170, 80, 255), -- purple
		},
		Celestial = {
			chance = 0.001,
			cashPerSecond = 120,
			tier = 6,
			heavy = true,
			color = Color3.fromRGB(255, 245, 200), -- white/gold
		},
		-- M8-05: crate-only rarities (forest chance 0), gated by RarityUnlocks.
		Prismatic = {
			chance = 0,
			cashPerSecond = 400,
			tier = 7,
			heavy = true,
			color = Color3.fromRGB(120, 255, 255), -- prism cyan
		},
		Nebula = {
			chance = 0,
			cashPerSecond = 1600,
			tier = 8,
			heavy = true,
			color = Color3.fromRGB(255, 110, 200), -- nebula pink
		},
		Singularity = {
			chance = 0,
			cashPerSecond = 7000,
			tier = 9,
			heavy = true,
			color = Color3.fromRGB(70, 60, 140), -- deep indigo
		},
		Eternal = {
			chance = 0,
			cashPerSecond = 30000,
			tier = 10,
			heavy = true,
			color = Color3.fromRGB(255, 230, 120), -- eternal gold
		},
	},

	-- Roll / display order of every rarity (low -> high).
	RarityOrder = {
		"Sprout",
		"Amber",
		"Frost",
		"Ember",
		"Void",
		"Celestial",
		"Prismatic",
		"Nebula",
		"Singularity",
		"Eternal",
	},
	-- M8-05: a rarity can only hatch once BOTH gates are met; otherwise the roll
	-- drops to the best unlocked rarity. Rebirth tier = floor(rebirths / Rebirth.TierEvery).
	RarityUnlocks = {
		Prismatic = { rebirthTier = 1, cultivation = 50 },
		Nebula = { rebirthTier = 2, cultivation = 65 },
		Singularity = { rebirthTier = 3, cultivation = 80 },
		Eternal = { rebirthTier = 4, cultivation = 95 },
	},

	-- Mutations multiply a core's cash rate. `weight` splits a successful roll
	-- (GDD names the multipliers but not the split; 70/25/5 keeps high tiers rare).
	Mutations = {
		Gold = { multiplier = 2, weight = 0.7, color = Color3.fromRGB(255, 210, 90) },
		Void = { multiplier = 10, weight = 0.25, color = Color3.fromRGB(170, 80, 255) },
		Celestial = { multiplier = 30, weight = 0.05, color = Color3.fromRGB(255, 245, 200) },
		-- M9-06: storm-only. Never rolled normally (weight 0): lightning strikes give it.
		Shocked = { multiplier = 15, weight = 0, color = Color3.fromRGB(120, 210, 255) },
		-- M9-09: LIMITED - only rolls during the weekly Eclipse event. Limited
		-- mutations count as Index entries but are not needed to complete a row.
		Eclipse = { multiplier = 25, weight = 0, color = Color3.fromRGB(255, 120, 90), limited = true },
	} :: { [string]: { multiplier: number, weight: number, color: Color3, limited: boolean? } },
	MutationChance = 0.02, -- per roll, per core, during the day
	MutationNightChance = 0.04, -- during the night
	MutationRollInterval = 300, -- one roll per core per 300 s of incubation

	-- M7-01 first five minutes: a brand-new player's very first seed hatches fast
	-- and is never a plain Sprout, so the opening loop pays off quickly.
	Onboarding = {
		FirstHatchSeconds = 20,
		FirstMinTier = 2, -- Amber or better
	},

	-- M7-03/04 social feedback toasts.
	Notify = {
		AnnounceMinTier = 5, -- Void / Celestial hatches are announced server-wide
		TeaserMaxSeconds = 3600, -- offline popup shows "next hatch in" only when sooner than this
	},

	-- M7-05 one-time milestone badges (cash reward x (1 + 0.5 * rebirths)).
	-- metric: coresStolen | nightStreak | rebirths | discovered (index entries).
	Milestones = {
		{ id = "firstSteal", metric = "coresStolen", goal = 1, title = "First Heist", reward = 500, seconds = 600 },
		{ id = "stealer10", metric = "coresStolen", goal = 10, title = "Master Thief", reward = 5000, seconds = 1800 },
		{ id = "streak3", metric = "nightStreak", goal = 3, title = "Night Owl", reward = 1500, seconds = 900 },
		{ id = "streak10", metric = "nightStreak", goal = 10, title = "Nightwalker", reward = 10000, seconds = 2400 },
		{ id = "rebirth1", metric = "rebirths", goal = 1, title = "Reborn", reward = 3000, seconds = 900 },
		{ id = "discover5", metric = "discovered", goal = 5, title = "Collector", reward = 2500, seconds = 900 },
		{ id = "discover9", metric = "discovered", goal = 9, title = "Curator", reward = 15000, seconds = 3600 },
	},

	Steal = {
		InteractDistance = 12, -- server-side reach gate for StealCore (latency margin over the 10-stud prompt)
		RipTime = 2, -- proximity prompt hold to rip a core off a pedestal
		CarrySpeedMultiplier = 0.65, -- -35% walk speed while carrying
		HeavyCarrySpeedMultiplier = 0.5, -- Void/Celestial cores
		DropDespawnSeconds = 10, -- dropped core becomes a wild claimable drop, then vanishes
		OwnerLockSeconds = 3, -- after a voluntary drop only the dropper may pick it up
		StealImmunitySeconds = 30, -- victim immunity after reclaiming a dropped core on their plot
		CancelMoveDistance = 4, -- moving this far cancels a rip in progress
	},

	Zapper = {
		Range = 6,
		Cooldown = 1.2,
		KnockbackSpeed = 20, -- studs/s push on the tagged player
	},

	Monsters = {
		Fogling = {
			Health = 12,
			Speed = 22,
			AggroRange = 40,
			Damage = 15,
			AttackCooldown = 1,
			PackMin = 2,
			PackMax = 3,
			RespawnSeconds = 20,
			MaxAlive = 6,
			SpawnDelay = 0,
		},
		Stalker = {
			Health = 150,
			Speed = 12,
			Damage = 40,
			LungeWindup = 2, -- telegraphed red glow before the lunge
			LungeRange = 26, -- starts winding up from this distance
			LungeSpeedMultiplier = 4, -- speed burst while lunging
			LungeDuration = 0.6, -- seconds of boosted speed after the windup
			SpawnDelay = 30, -- after night starts
		},
		-- 2026-10-18 variety pass. Each kind plays differently:
		-- Wisp: fast, fragile flier; a touch snatches your best carried seed, then it vanishes.
		Wisp = {
			Health = 8,
			Speed = 20, -- under sprint speed (24): you can outrun one with your seed
			AggroRange = 45,
			Damage = 5,
			AttackCooldown = 1.5,
			NightMax = 3, -- alive at once in the forest at night
			RespawnSeconds = 25,
			SpawnDelay = 15,
		},
		-- Moss Golem: slow tank; winds up (orange glow) then slams everyone close by.
		Golem = {
			Health = 400,
			Speed = 9,
			AggroRange = 40,
			Damage = 45,
			SlamRange = 9, -- starts the windup from this distance
			SlamRadius = 13, -- everyone inside takes the hit (walk out during the windup!)
			SlamWindup = 1.3,
			SlamCooldown = 3,
			NightMax = 1,
			RespawnSeconds = 60,
			SpawnDelay = 50,
		},
		-- Mire Spitter: slow; lobs a spore glob where you stand, leaving a toxic puddle.
		Spitter = {
			Health = 60,
			Speed = 6,
			AggroRange = 55,
			Damage = 12, -- direct splash
			ShotRange = 50,
			ShotCooldown = 3.5,
			ShotFlightTime = 1.1, -- keep moving and it misses
			SplashRadius = 6,
			PuddleSeconds = 3,
			PuddleDps = 8,
			NightMax = 2,
			RespawnSeconds = 40,
			SpawnDelay = 25,
		},
		-- M9-03 boss: the Grove Warden (a giant Moss Golem). Cannot be killed: the
		-- server banishes it by lighting every beacon. Same slam rules as the Golem.
		Warden = {
			Health = 5000,
			Speed = 11,
			AggroRange = 90,
			Damage = 60,
			SlamRange = 12,
			SlamRadius = 18,
			SlamWindup = 1.6,
			SlamCooldown = 4,
			SlowPerBeacon = 0.15, -- each lit beacon slows it 15%
		},
		Bounty = 10, -- cash for killing a monster (at least BountySeconds of income)
		BountySeconds = 15,
		StalkerTelegraphColor = Color3.fromRGB(255, 60, 60), -- windup glow (GDD: red telegraph)
	},

	-- M9-04 Traveling Market (Grow a Garden restocking shop / Brainrot conveyor):
	-- a hub stall whose 4 offers re-roll every RestockSeconds on a clock shared by
	-- every server (same offers everywhere), with limited stock PER SERVER, so rare
	-- offers are a race. Prices = at least priceSeconds of your income.
	Market = {
		RestockSeconds = 300,
		Slots = 4,
		MinPrice = 500, -- x rebirth multiplier
		Offers = {
			{
				id = "Seeds3",
				name = "Seed Bundle",
				give = "regular",
				count = 3,
				priceSeconds = 20,
				weight = 30,
				stock = 12,
				perPlayer = 3,
			},
			{
				id = "GroveSeed",
				name = "Grove Heart Seed",
				give = "grove",
				count = 1,
				priceSeconds = 120,
				weight = 24,
				stock = 6,
				perPlayer = 2,
			},
			{
				id = "CrystalSeed",
				name = "Crystal Seed",
				give = "CrystalSeed",
				count = 1,
				priceSeconds = 240,
				weight = 18,
				stock = 4,
				perPlayer = 1,
			},
			{
				id = "SporeSeed",
				name = "Spore Seed",
				give = "SporeSeed",
				count = 1,
				priceSeconds = 240,
				weight = 14,
				stock = 4,
				perPlayer = 1,
			},
			{
				id = "RelicSeed",
				name = "Relic Seed",
				give = "RelicSeed",
				count = 1,
				priceSeconds = 600,
				weight = 9,
				stock = 2,
				perPlayer = 1,
			},
			{
				id = "StarfallSeed",
				name = "Starfall Seed",
				give = "StarfallSeed",
				count = 1,
				priceSeconds = 1800,
				weight = 3,
				stock = 1,
				perPlayer = 1,
			},
		} :: {
			{
				id: string,
				name: string,
				give: string,
				count: number,
				priceSeconds: number,
				weight: number,
				stock: number,
				perPlayer: number,
			}
		},
		-- Market-only seeds (planted like zone seeds; same rarity gates apply).
		SpecialSeeds = {
			{
				id = "StarfallSeed",
				name = "Starfall Seed",
				odds = { Void = 0.55, Celestial = 0.35, Prismatic = 0.10 },
				boost = true,
				color = Color3.fromRGB(255, 225, 120),
			},
		} :: { { id: string, name: string, odds: { [string]: number }, boost: boolean, color: Color3 } },
	},

	-- M9-05 Fuse Machine (Steal An Egg / Brainrot): 3 cores of one rarity -> a chance
	-- at the next rarity. Uses your 3 weakest cores of that rarity; the result lands
	-- on the highest-level pedestal of the three and keeps the best mutation. A fail
	-- still returns one core of the same rarity. Fee = FeeSeconds of income.
	Fuse = {
		Count = 3,
		-- success chance by the INPUT rarity tier (1 = Sprout ...)
		ChanceByTier = { 0.8, 0.65, 0.55, 0.45, 0.35, 0.25, 0.18, 0.12, 0.08 },
		FeeSeconds = 60,
		MinFee = 200, -- x rebirth multiplier
		Xp = 60, -- Alchemy, + 20 per input tier
	},

	-- M9-07 companions (Grow a Garden pets / Steal An Egg mounts): one equipped at a
	-- time, unlocked by a skill level (RuneScape-style), floating next to you. Each
	-- adds perk stats; every companion flashes red when a monster is close.
	Companions = {
		{
			id = "Sprite",
			name = "Seed Sprite",
			skill = "Foraging",
			level = 1, -- free starter companion
			color = Color3.fromRGB(110, 255, 140),
			stats = { seedBag = 1, xpBoost = 0.05 },
			text = "+1 seed bag · +5% skill XP",
		},
		{
			id = "Firefly",
			name = "Night Firefly",
			skill = "Survival",
			level = 10,
			color = Color3.fromRGB(255, 230, 110),
			stats = { monsterSight = 0.1 },
			text = "Monsters notice you 10% later · lights the dark",
		},
		{
			id = "Moth",
			name = "Prism Moth",
			skill = "Alchemy",
			level = 15,
			color = Color3.fromRGB(200, 120, 255),
			stats = { mutationChance = 0.05 },
			text = "+5% mutation chance",
		},
		{
			id = "Beetle",
			name = "Golden Beetle",
			skill = "Cultivation",
			level = 25,
			color = Color3.fromRGB(255, 190, 60),
			stats = { income = 0.03, hatchSpeed = 0.05 },
			text = "+3% income · +5% hatch speed",
		},
	} :: {
		{
			id: string,
			name: string,
			skill: string,
			level: number,
			color: Color3,
			stats: { [string]: number },
			text: string,
		}
	},

	-- M9-09 weekly scheduled event (top games run Saturday "admin" events with a
	-- Roblox Events "Notify me" listing). Eclipse: every Saturday 19:00-22:00 UTC,
	-- mutation chance x2 and a share of successful rolls become the LIMITED Eclipse
	-- mutation. Same clock in every server.
	Weekly = {
		Name = "Eclipse Event",
		Weekday = 7, -- os.date("!*t").wday: 1 = Sunday ... 7 = Saturday
		StartHour = 19, -- UTC
		DurationHours = 3,
		MutationMultiplier = 2,
		EclipseShare = 0.3, -- of successful mutation rolls during the event
	},

	-- M9-10 free rewards: codes (one claim per account, case-insensitive) and a
	-- one-time reward for joining the creator's Roblox group. Cash rewards are at
	-- least `seconds` of income. GroupId 0 = no group yet (the panel hides it).
	FreeRewards = {
		GroupId = 482081508, -- "Anomaly Grove Studios" (created 2026-10-18)
		Group = { base = 5000, seconds = 900, groveSeeds = 1 },
		Codes = {
			GROVE = { base = 2000, seconds = 300, groveSeeds = 0 },
			ZONES = { base = 2000, seconds = 300, groveSeeds = 1 },
			ECLIPSE = { base = 3000, seconds = 600, groveSeeds = 0 },
		} :: { [string]: { base: number, seconds: number, groveSeeds: number } },
		RedeemCooldown = 2, -- seconds between tries (brute-force guard)
	},

	-- M9-01 core sizes (Steal An Egg / Grow a Garden style): rolled at every hatch.
	-- `mult` multiplies income, `scale` the gem on the pedestal. nil size = Normal.
	-- Expected income x1.22 overall; Huge+ hatches are announced to the server.
	Sizes = {
		Order = { "Tiny", "Normal", "Big", "Huge", "Titanic" },
		Defs = {
			Tiny = { chance = 0.20, mult = 0.75, scale = 0.75, color = Color3.fromRGB(190, 190, 200) },
			Normal = { chance = 0.55, mult = 1, scale = 1, color = Color3.fromRGB(255, 255, 255) },
			Big = { chance = 0.18, mult = 1.5, scale = 1.25, color = Color3.fromRGB(120, 220, 255) },
			Huge = { chance = 0.065, mult = 3, scale = 1.6, color = Color3.fromRGB(255, 170, 60) },
			Titanic = { chance = 0.005, mult = 10, scale = 2.2, color = Color3.fromRGB(255, 80, 200) },
		} :: { [string]: { chance: number, mult: number, scale: number, color: Color3 } },
		AnnounceFrom = "Huge",
	},

	-- 2026-10-18 wild zones past the ring wall (human: "map still seems small"). Each
	-- has a gate in the ring wall, special seed nodes that need a Foraging level, and
	-- resident guardians that stay inside the zone day AND night. Zone seeds are
	-- session-only (like Grove Heart seeds) and plant with their own hatch odds.
	Zones = {
		CenterRadius = 485, -- zone centre distance from the map centre
		Radius = 72, -- flat clearing radius
		GuardianRespawnSeconds = 45,
		NodeRespawnSeconds = 90,
		NodesPerZone = 3,
		List = {
			{
				id = "Crystal",
				name = "Crystal Hollow",
				angle = 112.5, -- degrees; between plots 3 and 4
				color = Color3.fromRGB(120, 220, 255),
				foraging = 10,
				guardian = "Golem",
				guardians = 2,
				guardianName = "Moss Golems",
				blurb = "Crystal Seeds hatch rarer cores",
				seed = {
					id = "CrystalSeed",
					name = "Crystal Seed",
					odds = { Amber = 0.40, Frost = 0.38, Ember = 0.17, Void = 0.04, Celestial = 0.01 },
					boost = false,
				},
			},
			{
				id = "Mire",
				name = "Spore Mire",
				angle = 202.5,
				color = Color3.fromRGB(150, 230, 90),
				foraging = 20,
				guardian = "Spitter",
				guardians = 3,
				guardianName = "Mire Spitters",
				blurb = "Spore Seeds mutate around the clock",
				seed = {
					id = "SporeSeed",
					name = "Spore Seed",
					odds = { Sprout = 0.40, Amber = 0.36, Frost = 0.17, Ember = 0.07 },
					boost = true, -- night mutation chance around the clock (like Grove Heart)
				},
			},
			{
				id = "Shrine",
				name = "Ruined Shrine",
				angle = 292.5,
				color = Color3.fromRGB(255, 200, 110),
				foraging = 35,
				guardian = "Wisp",
				guardians = 4,
				guardianName = "seed-stealing Wisps",
				blurb = "Relic Seeds hatch the rarest cores",
				seed = {
					id = "RelicSeed",
					name = "Relic Seed",
					odds = { Frost = 0.45, Ember = 0.35, Void = 0.15, Celestial = 0.05 },
					boost = false,
				},
			},
			-- M9-08: the endgame zone, opposite the hub.
			{
				id = "Frostfall",
				name = "Frostfall",
				angle = 157.5,
				color = Color3.fromRGB(190, 235, 255),
				foraging = 50,
				guardian = "Stalker",
				guardians = 3,
				guardianName = "Grove Stalkers",
				blurb = "Glacial Seeds hatch Ember or better",
				seed = {
					id = "GlacialSeed",
					name = "Glacial Seed",
					odds = { Ember = 0.45, Void = 0.35, Celestial = 0.17, Prismatic = 0.03 },
					boost = false,
				},
			},
		} :: { ZoneDef },
	},

	NightStreakBonus = 25, -- cash per survived night (at least NightStreakSeconds of income)
	NightStreakSeconds = 60,
	RespawnDelay = 5,

	Prices = {
		-- Pedestal 2..8, in claim order. Pedestal 1 is free with the plot.
		-- 9..12 (M8-07) need the Rebirth Tree "Expansion" node first.
		Pedestals = { 150, 300, 600, 1200, 2500, 5000, 10000, 25000, 60000, 150000, 400000 },
		Turret = 2500,
		LaserDoor = 1000,
		TrapTile = 500,
		MaxTrapsPerPlot = 3,
		DashBoots = 4000,
		SmokeBomb = 6000,
		Grapple = 10000,
		Lantern = 15000, -- M9-02
	},

	-- M8-06 rebirth: the requirement grows faster than the bonus, but every rebirth
	-- also raises pedestal level caps (per tier), pays Rebirth Tokens and unlocks
	-- rarities, so each climb is longer yet clearly stronger.
	Rebirth = {
		NetWorthRequired = 300000, -- rebirth 0 -> 1 (M8-12 pacing sim: config K)
		RequirementGrowth = 2.6, -- requirement x2.6 per rebirth
		IncomeGrowth = 1.75, -- cash multiplier x1.75 per rebirth (compounding)
		TokensPerRebirth = 1,
		BonusTokenEvery = 5, -- +1 extra token on every 5th rebirth
		TierEvery = 5, -- rebirth tier = floor(rebirths / 5): level caps, rarity gates
		KeepRarityTier = 4, -- Ember and above survive the reset (Sprout/Amber/Frost are removed)
		KeepMutated = true, -- 2026-10-18 review: mutated cores always survive (they are rare)
		MaxDefenseSlotBonus = 5,
		StealSpeedBonus = 0.1, -- +10% steal speed per rebirth
	},

	-- Net-worth contribution per rarity (Rebirth gate = cash + sum of core values).
	NetWorth = {
		Sprout = 50,
		Amber = 150,
		Frost = 400,
		Ember = 1000,
		Void = 2500,
		Celestial = 6000,
		Prismatic = 20000,
		Nebula = 80000,
		Singularity = 350000,
		Eternal = 1500000,
	},

	-- M8-04 pedestal levels: income x IncomeGrowth^(level - 1) (compounding); cost
	-- grows a little faster (CostGrowth). Levels reset on rebirth, but prices do NOT
	-- scale with rebirths (2026-10-18 review), so the re-climb after a rebirth takes
	-- minutes, and money spent on levels counts toward net worth. Every rebirth
	-- tier raises the cap. Tuned with scripts/pacing_sim.py.
	PedestalUpgrade = {
		BaseCost = 200,
		CostGrowth = 1.11,
		SlotCostStep = 0.15, -- pedestal N costs x (1 + 0.15 * (N - 1))
		IncomeGrowth = 1.08,
		BaseCap = 50,
		CapPerTier = 10,
		MaxCap = 10000, -- effectively uncapped: tiers keep raising it
		-- Upgrades unlock at Cultivation 10 (~20-30 min in) so the opening is about
		-- harvesting, pedestals, defenses, gadgets and raids, not tapping Upgrade.
		UnlockCultivation = 10,
		UpgradeAllMax = 200, -- levels bought per "Upgrade All" tap
	},

	-- M8-05 seed crates: bought in the shop and planted into your first empty
	-- pedestal, or replacing your weakest unmutated core that is at most one tier
	-- above the crate's floor. Price = max(price x rebirth multiplier, incomeSeconds
	-- of your income) so crates stay a real purchase all game. Locked rarities fall
	-- to the best unlocked one.
	Crates = {
		{
			id = "Fertile",
			name = "Fertile Crate",
			price = 2000,
			incomeSeconds = 60,
			cultivation = 20,
			color = Color3.fromRGB(140, 230, 110),
			odds = { Amber = 0.55, Frost = 0.30, Ember = 0.12, Void = 0.025, Celestial = 0.005 } :: { [string]: number },
		},
		{
			id = "Ancient",
			name = "Ancient Crate",
			price = 250000,
			incomeSeconds = 300,
			cultivation = 45,
			color = Color3.fromRGB(110, 200, 255),
			odds = { Frost = 0.50, Ember = 0.32, Void = 0.13, Celestial = 0.045, Prismatic = 0.005 } :: { [string]: number },
		},
		{
			id = "Mythic",
			name = "Mythic Crate",
			price = 50000000,
			incomeSeconds = 900,
			cultivation = 70,
			color = Color3.fromRGB(200, 110, 255),
			odds = { Void = 0.50, Celestial = 0.35, Prismatic = 0.12, Nebula = 0.03 } :: { [string]: number },
		},
		{
			id = "Cosmic",
			name = "Cosmic Crate",
			price = 10000000000,
			incomeSeconds = 1800,
			cultivation = 90,
			color = Color3.fromRGB(255, 225, 120),
			odds = { Celestial = 0.45, Prismatic = 0.35, Nebula = 0.15, Singularity = 0.049, Eternal = 0.001 } :: { [string]: number },
		},
	},

	-- M8-02/03 skills: levels 1-99 on the RuneScape XP table (Shared/Progression).
	Skills = {
		Order = { "Foraging", "Cultivation", "Alchemy", "Thievery", "Guarding", "Survival", "Commerce" },
		Meta = {
			Foraging = { icon = "🌿", color = Color3.fromRGB(110, 230, 120), verb = "Harvest seeds" },
			Cultivation = { icon = "🌱", color = Color3.fromRGB(90, 200, 255), verb = "Plant and hatch cores" },
			Alchemy = { icon = "⚗️", color = Color3.fromRGB(190, 110, 255), verb = "Mutate and infuse cores" },
			Thievery = { icon = "🦝", color = Color3.fromRGB(255, 120, 90), verb = "Rip, carry and grab cores" },
			Guarding = { icon = "🛡️", color = Color3.fromRGB(150, 170, 190), verb = "Defend your plot" },
			Survival = { icon = "🌙", color = Color3.fromRGB(120, 130, 255), verb = "Survive the nights" },
			Commerce = { icon = "💰", color = Color3.fromRGB(255, 205, 70), verb = "Spend cash and claim rewards" },
		},
		-- Better "training methods" as you level, like RuneScape: action XP x (1 + 0.03 * (level - 1)).
		LevelXpFactor = 0.03,
		-- Per-skill XP scale (pacing sim): evens out skills with fewer actions.
		XpScale = {
			Foraging = 1,
			Cultivation = 1,
			Alchemy = 1.2,
			Thievery = 1.3,
			Guarding = 1.3,
			Survival = 1,
			Commerce = 2.5,
		},
		Xp = {
			harvest = 20,
			groveHarvest = 100,
			meteorHarvest = 150,
			zoneHarvest = 120, -- wild-zone seed node (Foraging)
			dodge = 25, -- Survival: a Golem slam or Spitter glob missed you (you were its target)
			lanternStun = 15, -- Survival: per monster stunned with the Lantern
			plant = 5,
			feed = 15, -- seed fed to a hatched core
			hatchByTier = { 10, 25, 60, 150, 400, 1100, 3000, 8000, 22000, 60000 },
			mutationRoll = 3, -- x core tier, every passive mutation roll
			mutation = { Gold = 100, Void = 400, Celestial = 1500 },
			infuse = 40, -- + 10 x core tier per infuse
			rip = 120,
			securePerTier = 80,
			grab = 30,
			tag = 25,
			defenseHit = 30, -- per hit on a raider (max 1 per raider per second)
			nightPerDefense = 40, -- per owned defense when a night ends
			nightSurvived = 250,
			nightStreakBonus = 15, -- per streak night (capped at 20)
			nightOutsidePerSecond = 1.5, -- alive outside your own plot at night
			bloodMoonMultiplier = 2,
			commerceFlat = 5, -- per purchase: 5 + 40 x min(1, price / one minute of income)
			commerceScale = 40,
			questClaim = 200,
			dailyClaim = 250,
			lockdown = 100,
		},
		-- Every `every` levels a track grows by `per` (33 steps to 99 per track).
		Tracks = {
			Foraging = {
				{ stat = "doubleSeed", per = 0.006, every = 3, text = "double seed chance" },
				{ stat = "harvestCash", per = 1, every = 3, text = "harvest bonus (s of income)" },
			},
			Cultivation = {
				{ stat = "hatchSpeed", per = 0.0075, every = 3, text = "hatch speed" },
				{ stat = "rarityLuck", per = 0.015, every = 3, text = "rarity luck" },
			},
			Alchemy = {
				{ stat = "mutationChance", per = 0.02, every = 3, text = "mutation chance" },
				{ stat = "infuseChance", per = 0.005, every = 3, text = "infuse success" },
			},
			Thievery = {
				{ stat = "carrySpeed", per = 0.01, every = 3, text = "carry speed" },
				{ stat = "ripSpeed", per = 0.01, every = 3, text = "rip speed" },
			},
			Guarding = {
				{ stat = "defenseDamage", per = 0.02, every = 3, text = "defense damage" },
				{ stat = "trapRecharge", per = 0.01, every = 3, text = "trap recharge" },
			},
			Survival = {
				{ stat = "maxHealth", per = 2, every = 3, text = "max health" },
				{ stat = "nightIncome", per = 0.01, every = 3, text = "night income" },
			},
			Commerce = {
				{ stat = "discount", per = 0.003, every = 3, text = "shop discount" },
				{ stat = "income", per = 0.005, every = 3, text = "income" },
			},
		},
		-- One-off rewards at exact levels (text-only entries announce a gate).
		Unlocks = {
			Foraging = {
				{ level = 10, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 25, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 40, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 55, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 70, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 85, stat = "seedBag", value = 1, text = "Seed bag +1" },
				{ level = 99, stat = "seedBag", value = 1, text = "Seed bag +1 (10 total)" },
			},
			Cultivation = {
				{ level = 10, text = "Pedestal upgrades unlocked!" },
				{ level = 20, text = "Fertile Crates unlocked" },
				{ level = 45, text = "Ancient Crates unlocked" },
				{ level = 50, text = "Prismatic cores can hatch (rebirth tier 1)" },
				{ level = 65, text = "Nebula cores can hatch (rebirth tier 2)" },
				{ level = 70, text = "Mythic Crates unlocked" },
				{ level = 80, text = "Singularity cores can hatch (rebirth tier 3)" },
				{ level = 90, text = "Cosmic Crates unlocked" },
				{ level = 95, text = "Eternal cores can hatch (rebirth tier 4)" },
			},
			Alchemy = {
				{ level = 40, stat = "celestialWeight", value = 0.5, text = "Celestial mutations +50% likely" },
				{ level = 75, stat = "celestialWeight", value = 0.5, text = "Celestial mutations +50% likely" },
				{ level = 99, stat = "voidWeight", value = 0.5, text = "Void mutations +50% likely" },
			},
			Thievery = {
				{ level = 30, stat = "zapperCooldown", value = 0.15, text = "Zapper cooldown -15%" },
				{ level = 60, stat = "zapperCooldown", value = 0.15, text = "Zapper cooldown -15%" },
				{ level = 90, stat = "carrySpeed", value = 0.1, text = "Carry speed +10%" },
			},
			Guarding = {
				{ level = 30, stat = "defenseSlots", value = 1, text = "Defense slot +1" },
				{ level = 60, stat = "defenseSlots", value = 1, text = "Defense slot +1" },
				{ level = 90, stat = "defenseSlots", value = 1, text = "Defense slot +1" },
			},
			Survival = {
				{ level = 50, stat = "monsterSight", value = 0.15, text = "Monsters notice you 15% later" },
				{ level = 75, stat = "monsterSight", value = 0.15, text = "Monsters notice you 15% later" },
				{ level = 99, stat = "maxHealth", value = 34, text = "Max health +34" },
			},
			Commerce = {
				{ level = 25, stat = "offlineHours", value = 1, text = "Offline cap +1 h" },
				{ level = 40, stat = "questBonus", value = 0.25, text = "Quest rewards +25%" },
				{ level = 50, stat = "offlineHours", value = 1, text = "Offline cap +1 h" },
				{ level = 75, stat = "offlineHours", value = 1, text = "Offline cap +1 h" },
				{ level = 80, stat = "questBonus", value = 0.25, text = "Quest rewards +25%" },
				{ level = 99, stat = "offlineHours", value = 1, text = "Offline cap +1 h" },
			},
		},
		CapeLevel = 99,
		AnnounceLevels = { 50, 75, 99 }, -- server-wide shout
		MaxDiscount = 0.3, -- all discounts combined are capped
	},

	-- M8-07 Rebirth Tree: token-priced permanent perks. cost[i] = tokens for level i.
	RebirthTree = {
		{
			id = "QuickSprouts",
			branch = "Growth",
			name = "Quick Sprouts",
			stat = "hatchSpeed",
			per = 0.03,
			costs = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 },
		},
		{
			id = "LuckyRoots",
			branch = "Luck",
			name = "Lucky Roots",
			stat = "rarityLuck",
			per = 0.05,
			costs = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 },
		},
		{
			id = "UnstableSoil",
			branch = "Mutation",
			name = "Unstable Soil",
			stat = "mutationChance",
			per = 0.05,
			costs = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 },
		},
		{
			id = "ShadowStep",
			branch = "Thief",
			name = "Shadow Step",
			stat = "carrySpeed",
			per = 0.03,
			costs = { 1, 1, 2, 2, 3 },
		},
		{
			id = "QuickHands",
			branch = "Thief",
			name = "Quick Hands",
			stat = "ripSpeed",
			per = 0.04,
			costs = { 1, 1, 2, 2, 3 },
		},
		{ id = "Bulwark", branch = "Guardian", name = "Bulwark", stat = "defenseSlots", per = 1, costs = { 2, 3, 4 } },
		{
			id = "IronWill",
			branch = "Guardian",
			name = "Iron Will",
			stat = "maxHealth",
			per = 10,
			costs = { 1, 1, 2, 2, 3 },
		},
		{
			id = "Expansion",
			branch = "Expansion",
			name = "Expansion",
			stat = "pedestalSlots",
			per = 1,
			costs = { 2, 3, 4, 5 },
		},
		{
			id = "GoldenTouch",
			branch = "Fortune",
			name = "Golden Touch",
			stat = "income",
			per = 0.05,
			costs = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 },
		},
		{
			id = "NestEgg",
			branch = "Fortune",
			name = "Nest Egg",
			stat = "startCash",
			per = 1,
			costs = { 1, 1, 2, 2, 3 },
		},
		{
			id = "LongNap",
			branch = "Fortune",
			name = "Long Nap",
			stat = "offlineHours",
			per = 1,
			costs = { 1, 2, 2, 3 },
		},
		{
			id = "Scholar",
			branch = "Wisdom",
			name = "Scholar",
			stat = "xpBoost",
			per = 0.03,
			costs = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 },
		},
		{
			id = "Bounty",
			branch = "Wisdom",
			name = "Bounty",
			stat = "questBonus",
			per = 0.1,
			costs = { 1, 1, 2, 2, 3 },
		},
	},
	-- Nest Egg: start each rebirth with StartCashBase x 4^(level - 1) x rebirth multiplier.
	StartCashBase = 1000,

	-- M8-08 defense + gadget upgrades (kept through rebirth). cost = base x growth^(level - 1).
	Upgrades = {
		{
			id = "TurretPower",
			name = "Turret Power",
			tab = "Defenses",
			stat = "turretDamage",
			per = 0.15,
			max = 20,
			base = 3000,
			growth = 1.6,
		},
		{
			id = "LaserPower",
			name = "Laser Power",
			tab = "Defenses",
			stat = "laserDamage",
			per = 0.15,
			max = 20,
			base = 2000,
			growth = 1.6,
		},
		{
			id = "TrapGrip",
			name = "Trap Grip",
			tab = "Defenses",
			stat = "trapRoot",
			per = 0.1,
			max = 20,
			base = 1500,
			growth = 1.6,
		},
		{
			id = "DashTuning",
			name = "Dash Tuning",
			tab = "Gadgets",
			stat = "dashCooldown",
			per = 0.05,
			max = 10,
			base = 8000,
			growth = 1.8,
		},
		{
			id = "SmokeTuning",
			name = "Smoke Tuning",
			tab = "Gadgets",
			stat = "smokeCooldown",
			per = 0.05,
			max = 10,
			base = 10000,
			growth = 1.8,
		},
		{
			id = "GrappleTuning",
			name = "Grapple Tuning",
			tab = "Gadgets",
			stat = "grappleCooldown",
			per = 0.05,
			max = 10,
			base = 15000,
			growth = 1.8,
		},
	},

	-- M8-09 Index: every discovered rarity x mutation combo adds income.
	IndexIncomePerEntry = 0.01,
	IndexRowTokens = 1, -- completing a rarity row (plain + all 3 mutations)

	-- M8 Feed: planting a seed on a hatched core adds +1 growth cycle (+10% income
	-- each, Incubation.PedestalCycleBonus) up to BaseCap + CapPerLevel x pedestal level.
	Feed = {
		-- 2026-10-18 review: was 8 + 2/level (+4,000% at Lv 200 from free seeds).
		BaseCap = 10,
		CapPerLevel = 0.1, -- +1 cycle per 10 pedestal levels
		CompostSeconds = 20, -- a seed on a FULLY fed core pays 20 s of its income + XP
	},

	-- M8-04 alchemy infuse: pay cash to roll a mutation on your own hatched core.
	Infuse = {
		CostSeconds = 90, -- price = that core's income over 90 s (min $100)
		MinCost = 100,
		BaseChance = 0.12,
	},

	-- M8-10 Grove Pass (free track). Pass XP = PassXpShare of all skill XP earned.
	Pass = {
		Season = 1,
		SeasonName = "Season 1: First Bloom",
		Levels = 50,
		PassXpShare = 0.1,
		XpBase = 1500, -- level n needs XpBase + XpStep * (n - 1) pass XP
		XpStep = 150,
		CashSecondsBase = 120, -- level n pays income x (120 + 20 n) seconds (min $500)
		CashSecondsStep = 20,
		TokenEvery = 5, -- +1 Rebirth Token every 5th level
		FinalTokens = 3, -- level 50 bonus
	},

	Offline = {
		-- 2026-10-18 human feedback "afk money is a bit much": was 50% for 8 h
		-- (a night away = ~4 h of play). Now 25% for 4 h (= ~1 h of play); Commerce
		-- unlocks and the Long Nap tree node extend the cap up to 12 h.
		Efficiency = 0.25,
		CapSeconds = 4 * 60 * 60,
		MaxMutationRollsPerCore = 20,
		RollInterval = 300,
		Chance = 0.02,
		MinOfflineSeconds = 60, -- shorter absences get no popup
		LuckMultiplier = 2, -- "2x Offline Mutation Luck" pass doubles the roll chance
	},

	-- Daily quests (M6-02): PerDay rolled per UTC day from the pool (deterministic per
	-- player + day). Rewards grow with rebirths so late-game quests still matter.
	Quests = {
		PerDay = 3,
		RebirthRewardBonus = 0.5, -- +50% reward per rebirth
		Pool = {
			{ id = "harvest", text = "Harvest {n} seeds", goal = 10, reward = 300, seconds = 240 },
			{ id = "plant", text = "Plant {n} seeds", goal = 5, reward = 300, seconds = 240 },
			{ id = "earn", text = "Earn ${n} from cores", goal = 2500, reward = 500, seconds = 300, goalSeconds = 600 },
			{ id = "night", text = "Survive {n} night", goal = 1, reward = 500, seconds = 300 },
			{ id = "buy", text = "Buy {n} upgrades", goal = 2, reward = 400, seconds = 240 },
			{ id = "hatchRare", text = "Hatch {n} Frost-or-better core", goal = 1, reward = 600, seconds = 360 },
		},
	},

	-- Daily login streak (M6-03): day N of a 7-day cycle pays Rewards[N]; day 7 also
	-- grants a Grove Heart seed. Missing a UTC day resets the streak to day 1.
	Daily = {
		Rewards = { 100, 250, 500, 800, 1200, 2000, 4000 },
		-- Each day pays at least this many seconds of your income (2026-10-18 review:
		-- flat rewards were worth under a second of income by mid-game).
		RewardSeconds = { 180, 300, 420, 600, 900, 1200, 2400 },
		GroveSeedDay = 7,
	},

	-- Friend boost (M6-05): +10% core cash per friend in the same server, capped.
	FriendBoost = {
		PerFriend = 0.1,
		Max = 0.4,
	},

	-- World events (M6-04).
	Events = {
		BloodMoonEvery = 5, -- every 5th night is a Blood Moon
		BloodMoon = {
			MutationMultiplier = 2, -- mutation roll chance x2 (stacks on the night chance)
			MonsterMultiplier = 1.5, -- Fogling cap x1.5
			StreakBonusMultiplier = 2, -- surviving pays double
		},
		MeteorChance = 0.3, -- chance a day gets a Meteor Shower
		MeteorDelay = 25, -- seconds into the day before meteors fall
		MeteorCount = 5, -- boosted (Grove Heart) seeds left by meteors
		MeteorFallSeconds = 1.6,
		MeteorEventSeconds = 60, -- how long the "Meteor Shower" event flag stays up
		-- M9-03 boss night: every WardenEvery-th night (a Blood Moon takes priority).
		WardenEvery = 3,
		-- M9-06 weather (Grow a Garden style). Day roll: Meteor < MeteorChance, then
		-- Rain, then Thunderstorm; other nights may get an Aurora.
		RainChance = 0.2,
		StormChance = 0.12,
		AuroraChance = 0.25,
		Rain = { IncubationMultiplier = 0.5, Seconds = 150 }, -- seeds hatch twice as fast
		Thunderstorm = { Seconds = 120, StrikeEvery = 20 }, -- ~6 strikes; each shocks a core somewhere
		Aurora = { MutationMultiplier = 1.5, CelestialBonus = 2 }, -- Celestial weight x3
	},

	-- M9-03 Grove Warden boss night: four beacons in the forest; light them all
	-- (hold the prompt) to banish the Warden. Everyone in the server is paid; the
	-- players who lit a beacon get the lighter bonus on top.
	Boss = {
		SpawnDelay = 8, -- seconds into the night
		Beacons = 4,
		BeaconRadius = 135, -- from the map centre
		BeaconHold = 2.5,
		RewardBase = 5000, -- floor (x rebirth multiplier)
		RewardSeconds = 600, -- at least 10 minutes of income each
		LighterBonus = 0.5, -- +50% for players who lit a beacon
		RewardXp = 400, -- Survival
	},

	-- Instant Base Lockdown dev product (M3-05): full plot shield, max 3/night.
	Lockdown = {
		Seconds = 60,
		MaxPerNight = 3,
	},

	Plot = {
		ResetGraceSeconds = 60, -- owner leaves server -> plot wipes after this
		PedestalSlots = 8, -- base max; the Rebirth Tree Expansion node adds up to 4 more
		MaxPedestalSlots = 12, -- anchors built per plot (3 rows of 4)
		DefenseBaseSlots = 1, -- turret/trap capacity before rebirth bonuses
	},

	-- Turret tuning (M3-01).
	Turret = {
		Range = 30,
		DamagePerSecond = 10,
		StunSeconds = 1.5,
		TickSeconds = 0.5,
		MaxPerPlot = 2, -- corner anchor count
	},

	-- Defense tuning (M3-02): laser door + trap tiles.
	LaserDoor = {
		DamagePerSecond = 15,
		TickSeconds = 0.5,
		Thickness = 0.6, -- spans the threshold gap
	},
	TrapTile = {
		RootSeconds = 2,
		Damage = 10,
		RechargeSeconds = 30,
		TriggerRadius = 3.5,
		MaxPerPlot = 3,
	},

	-- Night-only "Grove Heart" mutated seed nodes (M3-03): exact map center.
	GroveHeart = {
		NodeCount = 3, -- spawn 3 nodes at night, despawn at day
		SpreadRadius = 6, -- nodes ring around the exact center
		BeaconHeight = 60, -- beacon beam reaches into the sky
	},

	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 24,
		SlideSpeed = 30,
		SlideDuration = 0.6,
		SlideCooldown = 2,
	},

	-- Gadget tuning (prices live in Config.Prices). Server applies the effects.
	Gadgets = {
		DashBoots = {
			burstBonus = 20, -- +20 speed on top of the current walk speed (GDD)
			burstSeconds = 4,
			cooldown = 20,
		},
		SmokeBomb = {
			duration = 3, -- monsters and turrets ignore you for 3 s (GDD)
			cooldown = 45,
		},
		Grapple = {
			range = 60, -- hook length in studs (GDD)
			cooldown = 25,
		},
		-- M9-02 (99 Nights-style flashlight): a flash that stuns every monster close
		-- by and cancels their windups. Counterplay at night; Survival XP per stun.
		Lantern = {
			radius = 26,
			stunSeconds = 3,
			cooldown = 30,
		},
	},

	HUD = {
		CashBlipSeconds = 10, -- soft coin blip on aggregated cash ticks
	},

	FxMix = {
		SfxVolume = 0.35, -- SFX SoundGroup cap (spot-check: always above ambience)
		AmbienceVolume = 0.15, -- night ambience loop (Music group) stays under SFX
		ChordGap = 0.07, -- seconds between stacked notes (chords/arpeggios)
		LoginChordSpeeds = { 0.75, 1, 1.25 }, -- stacked pings form a warm chord
		ArpeggioSpeeds = { 0.8, 1, 1.25, 1.5 }, -- rising mutation arpeggio
	},

	-- Engine-shipped sounds + (M5-10) Roblox-licensed library audio (ProSoundEffects /
	-- APM Music, free for any experience). Every ID is recorded in docs/ASSETS.md.
	FX = {
		HarvestSound = "rbxassetid://9116394545", -- Magic Glows Soft Clusters Of Chiming Hits 1
		UIClickSound = "rbxassetid://9119717529", -- Switch Click Toggle Button 1
		PurchaseSound = "rbxassetid://9113849492", -- Coins Or Keys Jingle 6
		SparkleSound = "rbxassetid://9126073001", -- Synth Sparkle Bell Tone Ding (hatch)
		AlarmSound = "rbxassetid://9113083860", -- Alarm Beeps 1 (base hit)
		RebirthSting = "rbxassetid://9047103106", -- APM "All It Takes Sting 2"
		NightMusicId = "rbxassetid://139190190976686", -- APM "Halloween Music Box"
		NightAmbienceId = "rbxassetid://9112764546", -- Crickets Night 1
		NightWhoosh = "rbxassetid://9125805579", -- Rising Whoosh (night start)
		PlaceSound = "rbxasset://sounds/bass.mp3",
		RipSound = "rbxasset://sounds/snap.mp3",
		TagSound = "rbxasset://sounds/snap.mp3",
		DeathSound = "rbxasset://sounds/uuhhh.mp3",
		DayMusicId = "rbxassetid://140195397978848", -- "Moonlit Meadow Whisper", free Creator Store track (see docs/ASSETS.md)
		CashBlipSound = "rbxasset://sounds/electronicpingshort.wav",
		FxVolume = 0.35,
		ShakeSeconds = 0.3,
		BurstParticles = 14,
	},
}

return table.freeze(Config)
