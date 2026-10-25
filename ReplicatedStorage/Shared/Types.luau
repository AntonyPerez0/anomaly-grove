--!strict
-- Shared Luau types for game state. Require only for `Types.X` in annotations;
-- the module exports no runtime values.

export type Rarity =
	"Sprout"
	| "Amber"
	| "Frost"
	| "Ember"
	| "Void"
	| "Celestial"
	| "Prismatic" -- M8-05: crate-only rarities above Celestial
	| "Nebula"
	| "Singularity"
	| "Eternal"
export type SkillName = "Foraging" | "Cultivation" | "Alchemy" | "Thievery" | "Guarding" | "Survival" | "Commerce"
-- Grove Pass progress (M8-10): season id, XP, claimed level rewards ("12" = level 12).
export type PassState = { season: number, xp: number, claimed: { [string]: boolean } }
export type Mutation = "Gold" | "Void" | "Celestial" | "Shocked" | "Eclipse"

-- Shape of one entry in Config.Rarities.
export type RarityInfo = {
	chance: number,
	cashPerSecond: number,
	tier: number,
	heavy: boolean,
	color: Color3,
}

-- Shape of one entry in Config.Mutations.
export type MutationInfo = {
	multiplier: number,
	weight: number,
	color: Color3,
}
export type Phase = "Day" | "Night"
export type Gadget = "DashBoots" | "SmokeBomb" | "Grapple" | "Lantern"
export type DefenseKind = "Turret" | "LaserDoor" | "TrapTile"

-- Onboarding toasts (M3-10): each flag flips once, ever.
export type TutorialFlags = {
	claimed: boolean,
	harvested: boolean,
	placed: boolean,
	stealHint: boolean,
}

-- One pedestal on a plot. Empty = rarity is nil.
export type PedestalState = {
	rarity: Rarity?, -- nil = empty; set when the seed hatches
	mutation: Mutation?,
	hatchAt: number?, -- os.clock() time the incubating seed hatches; nil = not incubating
	tickFrac: number, -- accumulated fractional cash between whole-second ticks
	completedCycles: number, -- each completed incubation adds Incubation.PedestalBonus rate
	vaultLocked: boolean, -- Vault Lock slot: cannot be stolen
	mutationProgress: number, -- seconds of incubation accumulated toward the next mutation roll
	mutationBoost: boolean, -- planted with a Grove Heart seed: night mutation chance around the clock
	level: number, -- M8-04 upgrade level (1+); resets on rebirth
	crate: string?, -- M8-05 crate planted here (decides the hatch odds); nil = forest seed
	size: string?, -- M9-01 Tiny/Big/Huge/Titanic (Config.Sizes); nil = Normal
}

-- What a player is physically carrying (seeds and cores only move by hand).
export type CarriedItem = {
	kind: "Seed" | "Core",
	rarity: Rarity?, -- cores only
	mutation: Mutation?, -- cores only
	size: string?, -- cores only (M9-01)
}

-- Daily quests (M6-02): three rolled per UTC day.
export type Quest = { id: string, goal: number, progress: number, claimed: boolean }
export type QuestState = { day: number, list: { Quest } }
-- Daily login streak (M6-03).
export type DailyState = { lastClaimDay: number, streak: number }

-- Live server-side state for one player (runtime only; Profile is the saved shape).
export type PlayerState = {
	player: Player?, -- nil on createDefault (spec testing); set by createState
	plotIndex: number?, -- 0..7, nil until claimed
	cash: number,
	carried: CarriedItem?,
	seedsCarried: number, -- 0..Seeds.MaxCarriedSeeds; seeds stack, cores carry one at a time
	groveSeeds: number, -- seeds from Grove Heart night nodes; plant into boosted cores (session-only)
	zoneSeeds: { [string]: number }, -- wild-zone seeds by seed id, e.g. CrystalSeed = 1 (session-only)
	companion: string?, -- M9-07 equipped companion id (saved)
	codes: { [string]: boolean }, -- M9-10 redeemed codes (+ "group")
	pedestals: { PedestalState },
	defenses: { { kind: DefenseKind, slot: number } },
	gadgets: { [Gadget]: boolean },
	zapperReadyAt: number, -- os.clock cooldown gate
	stealImmuneUntil: number,
	lockdownUntil: number, -- os.clock when the plot shield expires (0 = none)
	lockdownsUsed: number, -- lockdown purchases this night (max Lockdown.MaxPerNight)
	rebirths: number,
	indexDiscovered: { [string]: boolean },
	coresStolen: number,
	nightStreak: number,
	tutorial: TutorialFlags,
	milestones: { [string]: boolean }, -- M7-05 claimed badges
	skills: { [string]: number }, -- M8-02 XP per SkillName (never reset)
	tokens: number, -- M8-06 unspent Rebirth Tokens
	tree: { [string]: number }, -- M8-07 Rebirth Tree node levels
	upgrades: { [string]: number }, -- M8-08 defense/gadget upgrade levels
	pass: PassState, -- M8-10 Grove Pass
	cape: string?, -- M8-03 worn 99 cape (SkillName or "Max"); nil = none
	quests: QuestState?, -- M6-02 (nil until the profile loads)
	daily: DailyState?, -- M6-03
}

-- Persistent shape saved to the DataStore (GDD section 7). Keep schemaVersion first.
export type Profile = {
	schemaVersion: number,
	plotIndex: number?, -- nil = plot released between sessions
	cash: number,
	pedestals: { PedestalState },
	defenses: { { kind: DefenseKind, slot: number } },
	gadgets: { Gadget },
	rebirths: number,
	indexDiscovered: { [string]: boolean },
	coresStolen: number,
	nightStreak: number,
	tutorial: TutorialFlags,
	lastSeen: number, -- os.time at last logout, drives offline growth
	quests: QuestState, -- schema v2
	daily: DailyState, -- schema v2
	milestones: { [string]: boolean }, -- schema v3
	skills: { [string]: number }, -- schema v4 (M8)
	tokens: number,
	tree: { [string]: number },
	upgrades: { [string]: number },
	pass: PassState,
	cape: string?,
	companion: string?, -- M9-07 (optional field, no schema bump)
	codes: { [string]: boolean }?, -- M9-10 redeemed codes (+ "group" for the group reward)
}

local Types = {}

return Types
