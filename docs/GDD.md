# Game Design Document

> Source of truth for WHAT to build. The builder follows this file and `docs/TASKS.md`.

## 1. Pitch

- **Working title:** Anomaly Grove
- **One sentence:** Players scavenge a glowing wilderness for Anomaly Seeds, incubate them into cash-ticking Cores on their base pedestals, and raid rival bases to steal those Cores — while surviving monster-filled nights.
- **Genre and reference games:** PvPvE extraction-idle tycoon. Feel references only (never copy names/assets): *Steal An Egg* / *Grow a Garden* (passive pedestal income, offline growth, base stealing), *99 Nights in the Forest* (nocturnal PvE threat, fog), *RIVALS* (responsive sprint/slide movement, tagging).
- **Target players and age:** 9+ broad audience; mobile-first. Fans of steal-a-base and idle-grow games.
- **Session length:** 6-minute day/night cycles; satisfying session of 15–30 minutes; infinite idle retention via offline incubation.

## 2. Core loop

1. **Day (240 s): Sprint into the central forest.** Harvest glowing Anomaly Seed nodes (hold interact 1.5 s → seed flies to backpack, max 3 seeds carried). Seeds respawn every 30 s at 6–10 active nodes.
2. **Return & incubate.** Cross your own plot threshold, walk to a pedestal, press Place → seed becomes an incubating Core. After 60 s it hatches into a rarity (see 5.3) and ticks cash into your plot vault **every second** (rarity rate × 1 + 0.1 per completed incubation cycle on that pedestal).
3. **Raid rivals (also Day).** Walk into an enemy plot, hold interact 2 s on their pedestal to rip a Core off, carry it home (carry speed −35%, rare/heavy −50%). Getting tagged by any player's zapper melee drops the Core on the ground where anyone can grab it. Cross YOUR threshold to secure it onto a free pedestal.
4. **Night (120 s): Survive.** Toxic fog rolls in; Foglings (fast, 15 dmg hit) and a Grove Stalker (slow, 40 dmg, 60 s cooldown between spawns) hunt players outside their plot walls. Mutated Cores (Gold ×2, Void ×5, Celestial ×12 rate) spawn 3 nodes at map center only at night. Death drops your carried seed/core at death spot and respawns you at your plot after 5 s.
5. **Spend & grow.** Cash from vault → buy pedestals (price table 6), turrets, laser doors, trap tiles. Repeat. Offline: cores keep ticking (see 5.5), mutations roll on login.

## 3. Player experience

- **Player fantasy:** "My glowing grove prints money while I go on heists" → tension when raiding, dread at night, dopamine on login return.
- **First 60 seconds:** Spawn on a hub platform above the ring. Camera pans once over the map (3 s, skippable). Click/tap a glowing "Claim Plot" marker or any empty plot → dropped onto your plot with 1 pedestal pre-installed. HUD shows cash 0, phase timer, one tutorial toast: "Harvest seeds in the glowing forest!" A seeded freebie: first forest node the player approaches is always a Sprout seed.
- **Win / fail conditions:** No hard win. Fail states per raid: tagged → drop carried core; killed at night → drop carried item + 5 s respawn. Session goals: net worth, cores stolen, night streak.
- **Solo or multiplayer:** 8 players/server, 8 plots in a ring facing a central forest. Free-for-all stealing; no trading GUI (transfers only by physical drops).

## 4. Controls

| Action | PC | Mobile | Console |
|---|---|---|---|
| Move / jump | WASD / Space | Thumbstick / Jump button | Stick / A |
| Sprint | Shift (toggle) | Auto-sprint when stick pushed fully | Auto-sprint |
| Slide | C or Ctrl while sprinting | Slide button (ContextActionService) | B |
| Interact (harvest / place / steal) | Hold E (proximity prompt) | Hold prompt button | Hold X |
| Zapper tag melee | F / left-click swing | Tag button | RT |
| Gadget slot 1 (M1: none; M2: Dash Boots) | Q | Gadget button 1 | LB |
| Gadget slot 2 (M2: Smoke Bomb) | R | Gadget button 2 | RB |

All interactions use ProximityPrompts (touch-friendly default size ×1.5). Every core action has an on-screen button on mobile.

## 5. Systems

### 5.1 Map & plots (ServerStorage/Builders/MapBuilder)
- Ring map (scaled ~1.4x in M5-03): outer cobblestone ring wall with lantern pillars (radius 360 studs), 8 plots on the ring at 45° spacing, each plot 90×90 studs facing inward, central forest radius 200 studs with 8–14 seed nodes, night-only "Grove Heart" spawn circle at exact center on a cobble plaza. Smooth terrain: grass with animated blades, leafy forest floor, dirt paths from every plot gate to the plaza, a pond, rolling backdrop hills, and an ocean coastline around the island.
- Each plot: threshold line (glowing strip), 8 pedestal anchor points, wall with 1 laser-door gap slot, plot sign (owner name + net worth, updated live).
- Claim: first player to touch an unclaimed plot marker owns it. On leave (server empty of that player), plot resets after 60 s grace unless they rebased; pedestals/cores/cash saved first.
- Edge cases: 8 players max → all plots claimed → new joiners spectate hub with "Server full" toast (M2: rebalance to bigger plot count? No—cap server at 8).

### 5.2 Day/Night cycle (ServerScriptService/DayNightCycle)
- Server-authoritative clock: 240 s day + 120 s night = 360 s loop, driven by workspace `ClockTime` tween + `Lighting` presets (Day: Bright 14:00 ambient; Night: 0:00 + fog `Density 0.6`, `FogColor` deep purple, moon light).
- Night: spawn 4–6 Foglings at forest edge points; 1 Grove Stalker after 30 s; mutated seed nodes (3) at Grove Heart; all players' mutation tick rate ×2. Day: monsters despawn (fade + dissolve particles), fog lifts.
- Edge: server start = Day; timer persists in memory only (no need to save mid-cycle).

### 5.3 Cores, seeds & pedestals (ServerScriptService/CoreSystem + ReplicatedStorage/Shared/Config)
- Seed → incubation 60 s → rarity roll: Sprout 62%, Amber 25%, Frost 9%, Ember 3.2%, Void 0.7%, Celestial 0.1%.
- Cash/s by rarity: Sprout 1, Amber 3, Frost 8, Ember 20, Void 50, Celestial 120.
- Mutation: once per core per 300 s of accumulated incubation, roll 2% (night: 4%) → Gold ×2, Void ×10 rate, Celestial ×30 rate (multiplies the core's cash/s).
- Carried core: Welds to player's back with glow beam trail; WalkSpeed multiplier 0.65 (heavy rarity Void/Celestial: 0.5). Taking any damage (tag or monster) drops it at your feet; 10 s despawn → becomes claimable "wild drop".
- Physical carry only: no GUI transfers. Dropped items sit in `Workspace.Drops` folder; anyone holds interact 2 s to pick up (owner has 3 s owner-lock after a voluntary drop).

### 5.4 Stealing & tagging (ServerScriptService/StealSystem)
- Steal: enter rival plot → hold 2 s on pedestal (progress ring UI; cancels if you move >4 studs or get tagged) → core rips off with sound + shake → carried state.
- Securing: cross own threshold while carrying → core auto-snaps to a free pedestal (or drops in plot if none free).
- Zapper melee: 6 studs range, 1.2 s cooldown, 0 damage, applies Tag (drops carried item) + knockback 20 studs/s + screen flash on victim. Server validates range/cooldown; client sends hit request only.
- Vault Lock pedestal (monetization 11): one pedestal flagged un-stealable.
- Anti-grief: you cannot steal from your own plot; 30 s steal-immunity on a plot for the victim after reclaiming a dropped core there.

### 5.5 Offline growth (ServerScriptService/OfflineGrowth)
- On logout save `lastSeen = os.time()` + pedestal states (rarity, mutation, accumulated tick fraction).
- On login: elapsed = clamp(now − lastSeen, 0, 8 h). Award each core's cash/s × elapsed × 0.5 offline efficiency (cap 8 h). Roll mutations: floor(elapsed / 300) rolls per core at 2% each (max 20 rolls/core).
- Show "While you were away" popup: cash earned, mutations gained (rarity icons).
- DataStores unavailable → in-memory fallback with ONE console warning (AGENTS.md rule).

### 5.6 Monsters (ServerScriptService/MonsterAI)
- Fogling: 12 HP, WalkSpeed 22, aggro 40 studs, attack 15 dmg (1 s cooldown), spawns in packs of 2–3 at 3 forest points, respawns every 20 s at night (cap 6 alive). Flees in day (despawn).
- Grove Stalker: 150 HP, WalkSpeed 12, glowing eyes beam, 40 dmg lunge (2 s windup, telegraphed red glow), ignores players inside their plot walls (safe zone = inside own threshold).
- Monsters can't enter plot interiors (pathfinding + collision wall). Monster kill = 10 cash bounty + night streak counter.

### 5.7 Rebirth & Index (ServerScriptService/RebirthSystem, /CollectionIndex)
- Rebirth cost: 100,000 net worth. Resets: cash to 0, all Sprout/Amber/Frost cores removed. Keeps: Ember+, mutations, index. Grants: +1 defense slot (max +5), +10% steal speed, +5% cash/s global (stacking).
- Collection Index (book UI): grid of 6 rarities × discovered mutations; each new discovery = chime + confetti + index points; index points are cosmetic title unlocks only (M3).

### 5.8 Leaderboards (ServerScriptService/LeaderboardService)
- In-place physical boards (2 × 3 boards on hub platform), OrderedDataStore-backed, refresh 60 s: Most Net Worth, Most Cores Stolen, Longest Night Streak (consecutive nights surviving ≥50% of night outside plot... simplified: nights ending alive).

## 6. Progression and economy

- **Currency: Cash.** Earned: core ticks (main), monster bounties (10), night streak bonus (25/night). Spent: pedestals, defenses, gadgets, rebirth.
- **Prices (Config):**

| Item | Cost | Effect |
|---|---|---|
| Pedestal 2–8 (each) | 150 / 300 / 600 / 1200 / 2500 / 5000 / 10000 | +1 incubation slot |
| Turret | 2500 | 10 dmg/s, 30 stud range, shoots raiders, 1.5 s stun tag |
| Laser Door (plot gap) | 1000 | 15 dmg/s to non-owners crossing your threshold gap |
| Trap Tile | 500 | Root 2 s + 10 dmg, 30 s recharge, max 3/plot |
| Dash Boots (gadget) | 4000 | 4 s burst +20 speed, 20 s cooldown |
| Smoke Bomb (gadget) | 6000 | 3 s invisibility to monsters & turrets, 45 s cooldown |
| Grapple (gadget) | 10000 | 60 stud hook, 25 s cooldown |
| Rebirth | 100,000 net worth | See 5.7 |

- **Pacing target:** first placed Sprout earning within 2 min; first pedestal upgrade within 5; first successful steal attempt affordable risk-wise immediately; first gadget by ~10 min.

## 7. Data that saves between sessions

| Field | Type | Default | Notes |
|---|---|---|---|
| plotIndex | int? | nil | 0–7 or nil |
| cash | number | 0 | floor on save |
| pedestals | array | 1 slot | {rarity, mutation, incubationStart, tickFrac, vaultLocked} |
| defenses | array | {} | turrets/lasers/traps placed (type + position slot) |
| gadgets | array | {} | owned gadget ids |
| rebirths | int | 0 | |
| indexDiscovered | map | {} | rarity/mutation → true |
| coresStolen | int | 0 | |
| nightStreak | int | 0 | |
| lastSeen | int | os.time() | offline math |
| schemaVersion | int | 1 | migrations |

Single DataStore key per player (`Player_<UserId>`), UpdateAsync, save on PlayerRemoving + BindToClose. No trading data — nothing transferable via GUI.

## 8. World and art direction

- **Setting:** A stylized low-poly grove ring: pastel mossy greens and warm wood tones by day; saturated purple/teal neon Core glows always (PointLights + Beam trails per rarity color: Sprout green, Amber orange, Frost cyan, Ember red, Void purple, Celestial white/gold).
- **Night:** high-contrast spooky — dark blue fog, hazard-orange plot thresholds, glowing monster eyes (SpotLight billboards), 3D vignette via `Lighting.ColorCorrection` (contrast +0.15).
- **Built with (updated M5, 2026-10-17):** procedural parts PLUS free Creator Store models (stylized trees, bushes, rocks, props, skyboxes) loaded once into `ServerStorage.AssetLibrary` by `AssetLibraryBuilder` from `AssetManifest` (scripts stripped, listed in docs/ASSETS.md). Look target: bright stylized "top-chart sim" days, cozy-spooky nights, dense props, chunky readable UI. Idempotent `MapBuilder`, `PlotBuilder` (per-plot from code), `CoreBuilder` (procedural core meshes = Neon sphere + inner MeshPart-free geometry + ParticleEmitter), `LightingBuilder` (day/night presets). All world geometry from builder code; any generated assets recorded in docs/ASSETS.md.
- **No terrain sculpting requirements; terrain optional for forest floor (grass + decorative rocks as parts).**

## 9. UI screens

| Screen | Purpose | Key elements | Mobile notes |
|---|---|---|---|
| HUD | Always on | Cash (top-left, count-up), phase + timer bar (top-center), carried item icon (bottom-left) | Scale-based, safe-inset aware |
| Plot panel | Manage own plot | Pedestal list, buy pedestal/defense buttons | Big buttons ≥64 px |
| Index book | Collection | Rarity grid, mutation badges, discovered % | Scrollable vertical list |
| Away popup | Login reward | Cash earned, mutations, "Collect" | Center modal |
| Leaderboards | Hub boards | 3 physical boards + hover/tap detail | World-space SurfaceGui |
| Shop | Gadgets/defenses | Cards with cost + effect | 2-column grid |
| Toasts | Tutorials/events | Top stack, 4 s fade | Max 2 visible |

All GUI built in code from client scripts (no hand-placed UI). Text ≥14 pt equivalent, mobile layout checked at 360×640.

## 10. Audio and feedback

- Harvest: rising chime + node dissolve particles. Place: thud + pedestal ring pulse. Cash tick: soft coin blip every 10 s aggregate (not every core). Steal rip: metallic tear + screen shake 0.3 s. Tag hit: electric zap + victim white flash + knockback. Night start: fog whoosh + distant groan ambience loop; monster lunge: red telegraph beep. Mutation: triumphant arpeggio + confetti particles. Login popup: warm chord.
- Music: two ambient loops (day groove, night dread) from free Creator Store audio or generated placeholders; volume −12 dB under SFX.

## 11. Monetization (hooks only)

- Gamepass "Vault Lock" (Config placeholder ID 0): 1 un-stealable pedestal per plot.
- Gamepass "2x Offline Mutation Luck" (ID 0).
- Dev Product "Instant Base Lockdown" (ID 0): 60 s full plot shield, max 3/night.
- Cosmetic trails/sirens (M4 ideas, IDs 0).
Builder only adds placeholder IDs in Config + purchase validation plumbing. Human creates real products.

## 12. Milestones

- **M1 — Core loop playable:** ring map, plot claim, harvest→place→earn, steal & tag, day/night with basic monsters, mobile HUD. Placeholder art.
- **M2 — Progression and saving:** DataStore persistence, offline growth, mutations, gadgets, rebirth, index book.
- **M3 — Content, polish and mobile tuning:** turrets/lasers/traps, mutated night nodes, leaderboards, juice pass, mobile/low-end tuning, monetization placeholders.
- **M4 — Launch prep:** performance, onboarding polish, analytics, LAUNCH_CHECKLIST handoff.

## 12b. Milestones 5–6 additions (2026-10-17, human request: "professional, fun")

- **Look:** smooth terrain island (grass blades, leafy forest floor, dirt paths, pond, ocean coast, backdrop hills), dense stylized forest + anomaly crystals + fireflies, Grove Heart standing stones, stone ring wall with lantern pillars, hub plaza with "ANOMALY GROVE" arch, shop stalls and notice-board leaderboards, Atmosphere/Bloom/SunRays lighting with library skyboxes.
- **Bases:** cobblestone base + glass energy fence (12-stud block kept), entrance arch with owner avatar nameplate, restyled pedestals, claim beacon.
- **Cores:** rarity gems (spin/bob client-side) with overhead labels: rarity, mutation tag, live $/s (or hatch countdown).
- **Monsters:** AI-generated Fogling imp + Grove Stalker models with outline glow; red windup telegraph.
- **UI:** UITheme (FredokaOne, outlined text, gradient buttons, click sound), HUD (cash + income line + friend boost, carried slot, day/night/event pill), left side menu (Shop / Index / Quests / Daily / Settings), tabbed shop modal (Base / Defense / Gadgets / Premium — Offline Mutation Luck now buyable in-game), Lockdown quick-buy that pulses at night.
- **Guidance:** goal pill + guide beam driven by the pure `Shared/Objectives` chain (skips the raid goal when nobody has a core to steal).
- **Retention:** 3 daily quests (UTC reset, rewards scale with rebirths), 7-day login calendar (day 7 = Grove Heart seed), schema v2 profile.
- **Events:** Blood Moon every 5th night (x2 mutation chance, x1.5 Foglings, x2 survival bonus, red sky); Meteor Shower on 30% of days (5 meteors leave boosted seeds).
- **Social:** +10% core cash per friend in the server (max +40%).
- **Feel:** speed FOV kick, tag punch, purchase confetti + coin jingle, licensed SFX/music.

## 12c. Milestone 8: RuneScape-depth progression (2026-10-17, human request: "almost RuneScape levels of grinding but still rewarding")
- **Skills** (never reset): Foraging, Cultivation, Alchemy, Thievery, Guarding, Survival, Commerce, each 1-99 on the real RuneScape XP table (99 = 13,034,431 XP). Action XP x (1 + 0.03 x (level - 1)) x per-skill scale (Config.Skills.XpScale) x Scholar. Every skill gives a perk every 3 levels (two tracks each) plus one-off unlocks (seed bag 3->10, crate/rarity gates, defense slots, offline hours...). Level-up banner + confetti, server shout at 50/75/99, RS-style XP drops, wearable 99 capes + max cape, total level on the plot sign and a hub leaderboard.
- **Pedestal levels**: income x1.08 per level (compounding), cost x1.11 per level x slot x rebirth multiplier; cap 50 + 10 per rebirth tier; reset on rebirth. Upgrade / Infuse prompts on your own pedestals (U / I), "Best upgrade" in the shop.
- **Feed + compost**: a seed on a hatched core adds a growth cycle (+10%) up to 8 + 2 x level; on a fully fed core it is composted for 20 s of that core's income + XP. Seeds are never useless.
- **Crates + 4 new rarities** (Prismatic, Nebula, Singularity, Eternal; 400-30,000 $/s): Fertile/Ancient/Mythic/Cosmic crates unlock at Cultivation 20/45/70/90; price = max(base x rebirth multiplier, 1-30 min of income). A crate takes an empty pedestal or the weakest unmutated core near its floor. New rarities need rebirth tier 1-4 AND Cultivation 50/65/80/95.
- **Rebirth**: requirement 300K x 2.6^n, income x1.75^n (compounding), 1 Rebirth Token (+1 every 5th). Skills, tree, Index, gadgets, defenses are kept.
- **Rebirth Tree**: 13 token nodes (hatch speed, luck, mutation, thief, guardian, pedestal slots 9-12, income, Nest Egg, offline, Scholar XP, quest bounty), ~151 tokens to max.
- **Upgrades**: turret/laser/trap power and gadget cooldowns (Lv 10-20, cash).
- **Index**: 10 rarities x (plain + 3 mutations) = 40 entries, +1% income each; full row = +1 token.
- **Grove Pass** (free): 50 levels/season from 10% of all skill XP; every level pays minutes of income, every 5th a token.
- **Always a next step**: the GOAL pill shows the cheapest pedestal/upgrade with an ETA; SHOP shows "!" when something is affordable.
- **Pacing** (scripts/pacing_sim.py, idealised active player): rebirth 1 at ~30 min, ~13 at 5 h, ~26 at 10 h, ~52 at 50 h, ~64 at 100 h, then long climbs; first 99 ~460 h; six skills 99 by ~1,200-1,700 h, max cape ~1,700-2,000 h. Real players are slower.
- Economy review (2026-10-18): rebirth resets pedestal levels but level prices no longer scale with rebirths, and cash sunk into levels counts toward net worth (re-climb after a rebirth: ~1-25 min in the sim); mutated cores survive rebirth; UPGRADE ALL / GOAL pill buy the best income-per-dollar level on hatched cores only; quests, dailies, milestones, night bonus and bounties pay at least N seconds of income (Config `seconds` fields); feed cap 10 + 1 per 10 levels; crates replace your weakest core only when the crate's expected income beats it (late-game sink); day-7 seed respects the Foraging seed bag.
- Offline earnings (2026-10-18 retune): 25% of income for up to 4 h (was 50% / 8 h); Commerce + Long Nap extend the cap to 12 h.
- Plot furniture (FurnitureBuilder): stone patio under the pedestals, seed workshop, lounge, fountain, picnic table, planters, stepping-stone path; decorative only, Decor collision group, no lights.
- Profile schema v4 (skills, tokens, tree, upgrades, pass, cape, pedestal level/crate). Net worth leaderboard is log-encoded (int64 limit).
## 12d. Wild zones and monster variety (2026-10-18, human: "map still seems a little small", "more variety than the small purple demon")
- Three wild zones past the ring wall (gates cut into the wall between plots at 112.5, 202.5 and 292.5 degrees; dirt road to a flat clearing of radius 72 centred 485 studs out). Plots and the forest are unchanged, so basic walks stay short.
  - Crystal Hollow: slate floor, glowing crystal clusters. Crystal Seeds (Foraging 10) hatch Amber 40 / Frost 38 / Ember 17 / Void 4 / Celestial 1 %. Guarded by 2 Moss Golems.
  - Spore Mire: mud, pools, giant mushrooms, drifting spores. Spore Seeds (Foraging 20) hatch Sprout 40 / Amber 36 / Frost 17 / Ember 7 % and mutate at the night chance around the clock. Guarded by 3 Mire Spitters.
  - Ruined Shrine: rune dais, pillar ring, arches. Relic Seeds (Foraging 35) hatch Frost 45 / Ember 35 / Void 15 / Celestial 5 %. Guarded by 4 Wisps.
- Zone seeds: 3 nodes per zone, 90 s respawn, session-only like Grove Heart seeds, share the seed bag. Planting spends the best seed first; feeding spends the plainest. Harvest gives 120 Foraging XP.
- Guardians live in their zone day and night and never leave it (leash = clearing + 8 studs); 45 s respawn.
- New monsters (all also roam the forest at night): Wisp (fast flier, 5 dmg, snatches your best carried seed then vanishes; speed 20 < sprint), Moss Golem (slow tank, 1.3 s orange windup + ground ring, 45 dmg slam in 13 studs), Mire Spitter (keeps distance, lobs a glob at where you stand, 12 dmg splash + 3 s toxic puddle). Dodging a slam or glob aimed at you gives 25 Survival XP.
- Fix: passive and offline mutation rolls no longer downgrade a core (a Gold roll used to overwrite Void).
## 12e. Milestone 9: ideas from the top Roblox games (2026-10-18, human: "do all the recommended")
Researched Steal An Egg, 99 Nights in the Forest, Grow a Garden, Steal a Brainrot, Fisch, Pet Simulator 99.
- Core sizes: every hatch rolls Tiny 20% x0.75 / Normal 55% / Big 18% x1.5 / Huge 6.5% x3 / Titanic 0.5% x10 (gem scale + title; Huge+ announced; kept through steals).
- Lantern gadget (15K, [G]): stuns monsters within 26 studs for 3 s, cancels windups; Survival XP per stun.
- Grove Warden boss night: every 3rd night (Blood Moon wins ties) a giant Golem-kind boss; light 4 forest beacons together to banish it; everyone online is paid >= 10 min of income, lighters +50%, 400 Survival XP.
- Traveling Market (hub, left): 4 offers every 5 min, same offers in every server, per-server stock; zone seeds without the Foraging gate and the market-only Starfall Seed (Void .55 / Celestial .35 / Prismatic .10).
- Fuse Machine (hub, right): 3 weakest cores of a rarity -> next rarity (80% Sprout ... 8%), fail keeps one; best mutation kept, size best-of-2; fee 60 s of income.
- Weather: day Meteor 30% / Rain 20% (hatch x2 speed) / Thunderstorm 12% (lightning gives the storm-only SHOCKED x15 mutation); non-event nights Aurora 25% (mutations x1.5, Celestial x3).
- Companions: Seed Sprite (free), Night Firefly (Survival 10), Prism Moth (Alchemy 15), Golden Beetle (Cultivation 25); perk stats; flash red near monsters.
- Frostfall: 4th wild zone (157.5 deg), Glacial Seeds (Foraging 50: Ember .45 / Void .35 / Celestial .17 / Prismatic .03), 3 Grove Stalker guardians.
- Weekly Eclipse Event: Saturdays 19:00-22:00 UTC, mutations x2, 30% of mutations are the LIMITED Eclipse x25 (bonus Index entry, never needed for a row).
- Free rewards: codes (GROVE, ZONES, ECLIPSE; once per account) + a one-time group-join reward (needs the group ID).
- Fixes found on the way: Index now backfills owned cores (offline mutations were never recorded); Index rows include Shocked.
## 13. Out of scope for the agent

- Publishing the place, game settings, icons/thumbnails, real game passes/products (IDs in Config stay 0), Robux anything, ads, external servers. All in docs/LAUNCH_CHECKLIST.md.
- No copyrighted content; all original names/art.

## 14. Assumptions I made

- Title "Anomaly Grove"; original names (no reference-game terms).
- 6 rarities with rates/cash values as in 5.3 (human gave none).
- Incubation 60 s, seed cap 3, node respawn 30 s, 6–10 nodes.
- Mutation 2% (night 4%), Gold ×2 / Void ×10 / Celestial ×30, roll every 300 s per core; night spawns = Grove Heart nodes with those mutation flavors (human said "high-tier Mutated Cores spawn at center" — interpreted as boosted mutation-rate seed nodes).
- Tag = knockback + drop, 0 damage (RIVALS-style); zapper 6 studs, 1.2 s cooldown.
- Monster stats: Fogling 12 HP/15 dmg; Stalker 150 HP/40 dmg telegraphed lunge; night caps as in 5.6.
- Offline: 50% efficiency, 8 h cap, max 20 mutation rolls per core.
- Prices/costs table in section 6 (human gave none); rebirth 100k, +1 defense slot max +5, +10% steal speed, +5% cash per rebirth.
- Gadgets: Dash Boots, Smoke Bomb, Grapple (human named grapples/dash boots/smoke bombs); no other gadget trees.
- Plot reset 60 s after owner leaves server (cores saved first).
- Day 240 s / Night 120 s exactly as specified; monsters cannot enter plots.
- Leaderboards = 3 boards on the hub platform per human's "hub" mention (hub = spawn platform on ring wall).
- 8 players = 8 plots, no overflow handling beyond "server full" toast.
- Server size 8 in settings (human sets it; noted in LAUNCH_CHECKLIST).