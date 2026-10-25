# Assets

Every asset inserted or generated for the game. Builders insert assets by the IDs listed here.

**Policy (updated M5-01, 2026-10-17):** world art is procedural parts PLUS free Creator Store
models. Free models cannot be loaded by ID at runtime, so `AssetLibraryBuilder` loads them once in
Edit mode into `ServerStorage.AssetLibrary/<Category>/<Name>` (saved with the place), strips every
Script/LocalScript/ModuleScript, anchors and normalizes them (pivot = bottom-center at origin,
decoration non-colliding). World builders only clone from the library. The library is fully
rebuildable from `ServerStorage/Builders/AssetManifest.luau`:
`require(game.ServerStorage.Builders.AssetLibraryBuilder).build()` (Edit mode).
SEO-spam marketplace names are ignored; no reference-game names ship in the game.

## Free Creator Store models (AssetManifest.luau → ServerStorage.AssetLibrary)

| Asset ID | Name / creator | Library entries | Used in |
|---|---|---|---|
| 79689531752352 | Yasu's Stylized Tree Pack (mvyasu) | Trees/Tree_01..19, Landmarks/GiantTree (Tree_20), Bushes/Bush_01..03 | Forest, plot surroundings, Grove Heart landmark |
| 2128776869 | Low Poly Rock Pack [FREE] (FracturedSkies) | Rocks/Rock_01..10 | Forest, paths, backdrop |
| 4644085527 | Low Poly Mushrooms (CyrilTBFD) | Props/Mushrooms (x1.4) | Forest floor |
| 11312714034 | Low Poly Log (osddxx) | Props/Log | Forest floor |
| 15147571772 | market stall (Quantaily) | Props/MarketStall (x1.3) | Hub shop stalls |
| 84518243975474 | Free Low Poly Wooden Bench Stylized (Ramonzinhuh) | Props/Bench | Hub plaza |
| 285454336 | Dynamically Lit Lantern (EndorsedModel) | Props/Lantern (x3) | Plot fence posts, hub lamps |
| 139945645606198 | Fogling imp — AI-generated mesh (Roblox generate_mesh, M5-08), published to the owner's account | Monsters/Fogling (x1.15) | MonsterBuilder visual |
| 84743741590314 | Grove Stalker (bark + moss) — AI-generated mesh (generate_mesh, M5-08), owner's account | Monsters/Stalker (x1.7) | MonsterBuilder visual |
| 107656745575725 | Wisp - AI-generated mesh (generate_mesh, 2026-10-18), owner's account | Monsters/Wisp | MonsterBuilder visual |
| 138148830066144 | Moss Golem - AI-generated mesh (generate_mesh, 2026-10-18), owner's account | Monsters/Golem (x1.5) | MonsterBuilder visual |
| 105803933146803 | Mire Spitter mushroom creature - AI-generated mesh (generate_mesh, 2026-10-18), owner's account | Monsters/Spitter (x1.15) | MonsterBuilder visual |
| 14665403907 | Hilly Green Stylized Mountains SkyBox (Callme_jj) | Skies/DaySky | LightingBuilder day preset |
| 125829675338379 | Classic Night Skybox Stars (Chr1st1an302AlphaDaw) | Skies/NightSky | LightingBuilder night preset |

## Engine-shipped sounds (Config.FX / `ReplicatedStorage/Shared/Config.luau`)

| Asset ID | What it is | Source | Used in |
|---|---|---|---|
| `rbxasset://sounds/electronicpingshort.wav` | Harvest + cash blip ping (also the chord/arp tone layered by playback speed) | Roblox engine built-in | FXService.harvestAt, FxSounds notes, cash blip |
| `rbxasset://sounds/bass.mp3` | Place thud (and the streak stinger's low layer at 0.7 speed) | Roblox engine built-in | FXService.placeAt, FxSounds.stinger |
| `rbxasset://sounds/snap.mp3` | Steal rip tear | Roblox engine built-in | FXService.ripAt |
| `rbxasset://sounds/snap.mp3` (shared) | Tag zap | Roblox engine built-in | FXService.tagAt |
| `rbxasset://sounds/uuhhh.mp3` | Death groan; pitched to 0.55 speed and looped it is the night ambience | Roblox engine built-in | RespawnSystem death, FxSounds.setNightAmbience |
| `rbxassetid://140195397978848` | "Moonlit Meadow Whisper" — the day music loop | Creator Store, free (DistrokidOfficial) | FxSounds.setDayMusic (Music SoundGroup) |

## Roblox-licensed library audio (M5-10, `Config.FX`) — ProSoundEffects / APM Music, free for any experience

All verified loading in the launch experience (IsLoaded + TimeLength) on 2026-10-17.
User-uploaded marketplace audio was deliberately avoided (many are rips from other games).

| Asset ID | Name / library | Config key | Used in |
|---|---|---|---|
| 9116394545 | Magic Glows Soft Clusters Of Chiming Hits 1 (ProSoundEffects) | HarvestSound | Harvest, discovery chime |
| 9119717529 | Switch Click On Or Off Toggle Button 1 (ProSoundEffects) | UIClickSound | Every UITheme button |
| 9113849492 | Coins Or Keys Jingle 6 (ProSoundEffects) | PurchaseSound | Purchase juice (+ confetti) |
| 9126073001 | Synth Sparkle Tone High Pitch Bell Tone Ding (ProSoundEffects) | SparkleSound | Core hatch |
| 9113083860 | Alarm Beeps 1 (ProSoundEffects) | AlarmSound | Base-hit alarm |
| 9047103106 | All It Takes Sting 2 (APM Music) | RebirthSting | Rebirth (+ big confetti) |
| 139190190976686 | Halloween Music Box (APM Music) | NightMusicId | Night music loop (Music group) |
| 9112764546 | Crickets Night 1 (ProSoundEffects) | NightAmbienceId | Night ambience loop (Music group) |
| 9125805579 | Rising Whoosh Hissing Build Up (ProSoundEffects) | NightWhoosh | Night-start cue |

## Procedural world art (no asset IDs — built from parts in code)

| What | Where built | Notes |
|---|---|---|
| Ring map, plots, walls, hub, ramp, spawn | `MapBuilder.luau` | Parts only, deterministic RNG |
| Seed nodes + Grove Heart nodes (beacon beams) | `SeedNodeBuilder.luau` | Neon balls + ProximityPrompts; beacons are `Beam` instances |
| Pedestals + Vault Shield dome | `PedestalBuilder.luau` | Slate/Neon parts; shield uses ForceField material |
| Cores / seed orbs | `CoreSystem.setOrb` | Neon spheres + PointLight (GDD "neon core glows") |
| Turrets, laser door, trap tiles | `TurretBuilder.luau`, `DefenseBuilder.luau` | Procedural models + neon beams |
| Monsters (Fogling, Grove Stalker) with glowing eyes | `MonsterBuilder.luau` | Neon eye parts + PointLights |
| Leaderboard boards | `LeaderboardBuilder.luau` | Parts + SurfaceGui text |
| Lighting/fog/color-correction presets | `LightingBuilder.luau` | Engine lighting objects only |

## Monetization IDs (Config)

| Item | Current value | Status |
|---|---|---|
| `Config.GamePasses.VaultLock` | 2038023414 | Done (wired 2026-10-17) |
| `Config.GamePasses.OfflineMutationLuck` | 2040164994 | Done (wired 2026-10-17) |
| `Config.GamePasses.StealTrails` | 2036199548 | Done (49 R$, wired 2026-10-17) |
| `Config.GamePasses.BaseAlarmSirens` | 2039961292 | Done (49 R$, wired 2026-10-17) |
| `Config.GamePasses.DoubleCash` | 2038359527 | Done (99 R$, wired 2026-10-17) |
| Private servers | n/a | On, 50 R$/month (dashboard > Audience > Advanced settings) |
| `Config.Products.InstantLockdown` | 3719351008 | Done (wired 2026-10-17) |

Agent-uploaded 2026-10-17 (drawn in code / captured in Studio): pass icons `docs/icons/double-cash.png`,
`steal-trails.png`, `base-alarm-sirens.png`; place icon `docs/icons/game-icon.png`; thumbnails
`docs/screenshots/thumb-base.jpg`, `thumb-aerial.jpg`, `thumb-night.jpg` (Home Page + Experience Detail Page).

Dashboard icon images (made by the agent, uploaded by the human): `docs/icons/vault-lock.png`,
`docs/icons/offline-mutation-luck.png`, `docs/icons/instant-lockdown.png`.
