# Starwright — Game Design Document

> **Status:** Draft v0.1 · **Working title:** *Starwright* (placeholder)
> **Genre:** Peaceful voxel space exploration & ship-building sandbox
> **Platforms:** Desktop (Windows / macOS / Linux) and Web (browser), as two separate builds of one codebase
> **Players:** Single-player and online co-op (2–4)
> **Scope:** Multi-month project

---

## 1. Pitch

Build a spaceship one block at a time, walk around inside it, and fly it across a procedurally generated galaxy of blocky planets. There are no enemies and no weapons. The challenge comes from **engineering, the environment, and the urge to see what's past the next star**. Your ship is your home, your workshop, and your main creative project.

It is a **pure sandbox**: no story or scripted quests. Players set their own goals, such as building the biggest hauler, landing on the heaviest planet, cataloging every species in a system, or building an outpost on an ice moon with friends.

## 2. Design pillars

1. **Your ship is you.** Every block you place changes how the ship flies, what it can reach, and how it feels to live in.
2. **Peaceful but not easy.** No combat. Challenge comes from physics (mass, thrust, gravity), hazards (heat, cold, radiation, toxic air), and logistics (fuel, cargo, range).
3. **Curiosity is the reward.** Every planet should have something worth landing for, such as a strange creature, a rare mineral, a derelict wreck, or an odd landscape.
4. **Better together, fine alone.** Everything works solo, and co-op adds crew roles (pilot, builder, explorer) without needing them.
5. **Runs in a browser.** Every system is designed with the web build's limits in mind from day one.

## 3. Game modes

| Mode | Description |
|---|---|
| **Explorer** (default) | Blocks cost resources and credits. Hazards are on. Better blocks are unlocked by exploring and scanning. |
| **Creative** | All blocks unlocked, unlimited resources, hazards toggleable, free flight on foot. For pure building. |

Both modes are open-ended sandboxes with no win state. A world's mode and its hazard and economy settings are chosen at world creation (and can be changed later in Creative).

## 4. Core loop

```
 ┌──────────────► Pick a destination (star map)
 │                        │
 │                        ▼
 │            Plan: fuel, cargo, can my ship
 │            take off from that gravity?
 │                        │
 │                        ▼
 │            Fly: cruise in-system, jump between systems,
 │            avoid asteroid fields / solar flares
 │                        │
 │                        ▼
 │            Land & explore on foot: scan flora/fauna,
 │            mine resources, salvage derelicts, build outposts
 │                        │
 │                        ▼
 │            Return to a station: sell, trade, unlock blocks
 │                        │
 └──────── Rebuild / expand the ship to reach farther ◄─┘
```

**Session goal:** a satisfying 20–40 minute loop of "go somewhere new → bring something back → improve the ship."

## 5. Ship building

### 5.1 Grid & scale
- **1 block = 1 m.** The player is ~1.8 m tall (fits a 1×2 opening; 3-block-tall rooms feel roomy).
- Ships are their own **voxel grid**, separate from the terrain, so a ship can move as one rigid body.
- **Block shapes:** cube, slope, corner, inverted corner, half-block. Slopes are what make ships look like ships and not boxes.
- **Paint:** every block can take a color from a palette; some blocks have emissive (glowing) variants.

### 5.2 Block categories

| Category | Examples | Affects |
|---|---|---|
| Structure | Hull (light / heavy / insulated), windows, frames | Mass, hazard protection |
| Command | Cockpit, bridge console, nav computer | Required to fly; jump range bonus |
| Propulsion | Main engines, maneuvering thrusters, landing thrusters | Thrust, turn rate, max liftoff gravity |
| Power | Reactors, batteries, solar panels | Power budget for everything else |
| Fuel | Fuel tanks (small / large) | Range, jump count |
| Utility | Scanner array, mining laser, cargo bay, tractor beam, landing gear | Exploration & hauling ability |
| Life support | Oxygen generator, heater / cooler, radiation shielding | What environments the ship can sit in |
| Interior | Doors, airlocks, ladders, beds, seats, lights, storage, galley, greenhouse | Livability, respawn point (bed), co-op crew stations |

### 5.3 Ship stats (derived from blocks)
- **Mass** = sum of block masses + cargo.
- **Thrust-to-weight ratio** determines the **maximum gravity you can take off from**. This is the central engineering puzzle: a huge cargo hauler may be able to land on a heavy planet but never leave.
- **Power budget**: reactors and batteries must cover engines, life support, and utilities.
- **Jump range**: depends on the nav computer, fuel, and mass.
- **Hazard rating**: insulation, shielding, and life support decide which environments the ship can safely sit in.

The builder shows live stats and **warnings** (for example, "Cannot take off above 1.4 g", "Power deficit: −120 kW", "No airlock").

### 5.4 Builder UX
- Build mode uses a **free orbit camera** around the ship, with symmetry mirroring (X/Y/Z), fill/box tools, undo/redo, and copy/paste of sections.
- You can also build **in place** in first person while walking around the ship.
- **Blueprints**: save, load, and share ships as files or text strings.
- Ships are built and edited only when **docked at a station** or **landed**. Small repairs work anywhere.

### 5.5 Damage & repair (non-combat)
- Hard landings, asteroid collisions, and some hazards (for example, a solar flare without shielding) damage or destroy blocks.
- Repairs use a hand tool plus resources. Nothing is ever permanently lost: a stranded ship can call a tow (costs credits in Explorer, free in Creative).

## 6. Flight

### 6.1 Space flight
- **Newtonian with flight assist.** Flight assist on (default) gives arcade-friendly handling; flight assist off gives full inertia for experts.
- **In-system cruise:** a cruise drive covers planetary distances quickly. Space distances are scaled down for fun.
- **Between systems:** a **jump drive** consumes fuel; range comes from ship stats. Jumps play a short transition, which also hides loading.
- **Space hazards:** asteroid fields (navigate or mine them), solar flares (find shelter or have shielding), radiation belts, gravity wells near massive bodies.

### 6.2 Landing & takeoff (landing-zone model)
1. In orbit, open the planet map and pick a landing site.
2. The game checks the ship against the planet's gravity and hazards and **warns** if takeoff would be impossible or the environment is dangerous.
3. A short descent sequence plays while the landing zone generates and loads.
4. The player flies the **final approach and touchdown manually** (with landing-assist optional).
5. To take off, climb above the zone's ceiling to transition back to orbit.

> **Why landing zones?** Seamless orbit-to-surface descent onto round voxel planets is the riskiest possible feature, especially in a browser. Landing zones keep the game achievable and fast on the web build. See §15 for stretch options.

## 7. Planets & the galaxy

### 7.1 Galaxy structure
- Procedurally generated from a **world seed**, effectively endless.
- **Star system:** 1 star, 2–8 planets, moons, 0–2 asteroid belts, 0–2 stations, and the occasional derelict or anomaly.
- **Star map:** shows discovered systems, known resources, scan completion, and your outposts.

### 7.2 Planet types

| Type | Gravity | Hazards | Highlights |
|---|---|---|---|
| Rocky / temperate | 0.6–1.2 g | Mild | Lush flora, many fauna; good starter worlds |
| Desert | 0.5–1.5 g | Heat, sandstorms | Ruins, rare minerals |
| Ice | 0.3–1.0 g | Extreme cold | Crystal formations, subsurface caves |
| Jungle | 0.8–1.6 g | Toxic air | Densest flora & fauna variety |
| Volcanic | 1.0–2.5 g | Heat, lava, toxic air | High-value ores, hard to leave |
| Ocean | 0.7–1.3 g | Storms | Archipelagos, sea creatures |
| Barren moon | 0.05–0.4 g | Radiation, vacuum | Low gravity, great for big ships, derelicts |
| Gas giant | — | — | Can't land; orbit-only (stretch: fuel skimming) |

### 7.3 Landing zone generation
- A landing zone is a large bounded voxel area (see §11 for sizes per platform) generated from `world seed + planet + coordinates`.
- Terrain comes from layered noise (height, biome, caves, ore veins), using palettes and block sets per planet type.
- **Edits are saved as diffs** against the seed, so revisiting a zone restores your mining and outposts without storing the whole zone.

### 7.4 Life (non-hostile)
- **Flora:** procedural blocky plants built from part kits (stalks, leaves, bulbs, crystals) with colors per planet. Some can be harvested, and some react to the player (close up, glow, release spores).
- **Fauna:** procedural blocky creatures assembled from body-part kits. Behaviors include grazing, herding, fleeing, curiosity, and flying. **None attack.** At worst a creature is skittish or blocks your path.
- **Scanning** a species adds it to your **catalog** and earns research data, with a bonus for being the first to scan it in that world.

### 7.5 Points of interest
- **Derelict ships:** explore them and **salvage blocks** (a key source of rare blocks).
- **Ruins and anomalies:** environmental curiosities with no story attached, such as strange geometry, gravity quirks, or glowing monoliths that reveal resource locations.
- **Resource deposits:** found with the scanner; rarer deposits are on more hostile worlds.

## 8. On foot

- **Camera:** first person by default, toggle to third person any time (on foot, inside ships, and when piloting).
- **Suit:** oxygen, temperature, and radiation meters. Upgradable.
- **Jetpack:** short boosts; stronger in low gravity.
- **Multitool:** scan, mine (break blocks), place blocks, repair. Modes are switched with a radial menu.
- **Failure:** if suit integrity runs out you **respawn at your ship's bed** (or the last station). There is no item loss in Creative and a small resource penalty in Explorer.

## 9. Progression & economy (Explorer mode)

There is no story and no required path. Progression only widens what you can build and where you can go.

- **Credits:** earned by selling resources, trading between stations, completing optional station contracts (delivery, survey, passenger transport), and selling catalog data.
- **Research data:** earned by scanning species, minerals, and anomalies, and spent to **unlock block types** (better engines, shielding, bigger tanks).
- **Salvage:** rare blocks from derelicts that can't be bought.
- **Natural difficulty curve:** starter systems are gentle. Farther systems have higher gravity, harsher hazards, and better rewards, so you need a better ship to reach them.

## 10. Co-op multiplayer

- **2–4 players**, drop-in/drop-out, joined via a **room code**.
- **Crossplay:** desktop and web players can play together.
- **Host-authoritative:** the host's world and save are the source of truth.
- **Shared ships:** one player pilots while others walk around inside, run a scanner station, or build. Each player can also own separate ships.
- **Optional crew roles:** pilot, engineer (power and repairs), surveyor (scanner and catalog), with no hard role locks.
- **Bandwidth trick:** terrain is generated locally from the seed on every client, so only **edits, ship state, players, and creatures** go over the network.

> Co-op ships in a later milestone (M6), but the code is **structured for networking from day one** (see §12.4). Retrofitting multiplayer onto a finished single-player game is far more expensive.

## 11. Desktop vs. Web builds

One codebase, two export targets with different presets. Numbers are **initial targets to validate in M0**.

| Aspect | Desktop | Web |
|---|---|---|
| Renderer | Godot Forward+ (dynamic lights, better shadows) | Godot Compatibility (WebGL 2) |
| Landing zone size | ~512 × 512 blocks, ~256 tall | ~256 × 256 blocks, ~128 tall |
| View distance | 12–16 chunks | 6–8 chunks |
| Max ship size | ~64 × 32 × 64 bounding box | ~32 × 16 × 32 bounding box |
| Fauna active at once | ~40 | ~15 |
| Meshing | Background threads | Time-sliced on main thread (or threads if cross-origin isolation headers are available on the host) |
| Saves | Files in the user data folder | Browser storage (IndexedDB) **plus** export/import of save files |
| Input | Keyboard + mouse, gamepad | Keyboard + mouse (pointer lock), gamepad |
| Distribution | Itch.io / Steam (TBD) | Itch.io / own website |

Ships and blueprints built on desktop may exceed web limits. The game flags those blueprints as "desktop only" rather than failing silently.

## 12. Technical architecture

### 12.1 Engine & language
- **Godot 4.x (latest stable), GDScript.** GDScript is chosen because Godot's C# cannot export to the web.
- **Escape hatch:** if GDScript meshing is too slow (decided in M0), move only the hot path (chunk meshing and terrain generation) to a GDExtension or a compiled voxel module, and keep gameplay in GDScript.

### 12.2 Voxels
- **Chunks:** 16³ or 32³ blocks (decided in M0). Block data is stored as packed byte or int arrays per chunk.
- **Greedy meshing** for cubes plus special-case geometry for slopes and corners. A small texture atlas with flat palette colors.
- **Collision:** generated only for chunks near players and ships.
- **Ships:** a separate voxel grid parented to a physics body. Re-meshed only around edited blocks.

### 12.3 Walking inside moving ships
- When the player is inside a ship's interior volume, they are **re-parented into the ship's local space** and simulated relative to it, with artificial gravity "down" the ship's floor. Leaving through an airlock returns them to world space.
- This is a known-hard problem and is prototyped early (M2).

### 12.4 Network-ready from day one
- All world-changing actions (place block, mine, take off, scan) go through a **command layer** that can run locally or be sent to the host.
- Game state is separated from presentation, so clients can render state the host sends.
- **Transport:** Godot's high-level multiplayer API over **WebRTC** (with a small signaling server, plus a relay fallback) to allow desktop↔web crossplay, since browsers can't use ENet or host plain sockets. Validate in M6; fallback is a hosted relay server.

### 12.5 Space scale & precision
- **Floating origin:** the world recenters around the player to avoid float-precision jitter far from the origin.
- Each star system has its own coordinate space, and distances are compressed for gameplay.

### 12.6 Saves
- World seed + settings + **per-zone edit diffs** + ship blueprints and states + player inventories + catalog.
- A versioned save format with migrations from the start.

## 13. Art & audio direction

- **Visual style:** clean, **flat-colored blocks** with subtle edge darkening and ambient occlusion, not pixel-art textures. The look is bright and readable with strong palette identities per planet (for example, teal jungle with magenta flora, or orange desert under a blue sun). Emissive blocks make ships glow at night.
- **Space:** colorful nebula skyboxes per system; planets from orbit are stylized low-poly spheres.
- **UI:** diegetic where possible (cockpit screens, suit HUD), clean and minimal otherwise.
- **Audio:** ambient synth soundtrack that shifts by planet type; ship hum that changes with engine and reactor count; procedural creature calls; satisfying block place/break sounds.

## 14. Controls (default, keyboard + mouse)

| Context | Controls |
|---|---|
| On foot | WASD move · Space jump / jetpack · Mouse look · LMB use tool · RMB alt use · Q radial tool menu · V toggle 1st/3rd person · E interact |
| Piloting | W/S throttle · A/D yaw · Mouse pitch/roll · Shift boost · Z flight assist · C cruise · J jump drive · M star map |
| Builder | RMB-drag orbit · Scroll zoom · LMB place · Shift+LMB remove · R rotate block · X/Y/Z symmetry · Ctrl+Z / Ctrl+Y undo/redo |

Full gamepad support is planned. Controls are rebindable.

## 15. Scope control

### In scope (v1.0)
Everything in §§3–14 with landing-zone planets.

### Stretch goals (only after v1.0 is solid)
- **Cube planets:** small planets that are literally giant cubes, fully walkable with gravity per face and no loading. A blocky signature feature.
- **Seamless descent** from orbit onto planets.
- Gas giant fuel skimming.
- Planetary vehicles (rovers built from blocks).
- Logic blocks (sensors, switches, automation).
- Steam Workshop / blueprint sharing site.
- Mod support.

### Explicitly out of scope
Combat and weapons, hostile creatures, story campaign, NPC crew AI, MMO-scale servers.

## 16. Roadmap

Durations assume a small team (1–3 developers) and are rough.

| Milestone | Duration | Goal | Exit criteria |
|---|---|---|---|
| **M0 — Tech spike** | 2–3 wks | Prove voxels perform on both targets | Chunked terrain with greedy meshing streams around a walking player at a smooth 60 fps on desktop and an acceptable rate in browser; web export hosted and playable; chunk size and meshing language decided |
| **M1 — Ship builder** | 4–6 wks | Build ships | Place, remove, and paint all block shapes; symmetry and undo; live stats and warnings; save/load blueprints |
| **M2 — On foot & interiors** | 3–4 wks | Live in your ship | 1st/3rd person switching; walk inside a moving ship; doors, airlocks, beds; suit meters |
| **M3 — Flight** | 4–6 wks | Fly what you built | Thrust and mass from blocks; flight assist; cruise drive; landing-zone transition; manual touchdown; takeoff gravity check |
| **M4 — Planets** | 6–8 wks | Worlds worth landing on | 5+ planet types; biomes, caves, ores; procedural flora and fauna; scanning and catalog; hazards; edit-diff saves |
| **M5 — Galaxy & sandbox** | 4–6 wks | A reason to keep going | Star systems, star map, jump drive, stations, trading, contracts, research unlocks, derelicts; Explorer and Creative modes |
| **M6 — Co-op** | 6–8 wks | Play together | 2–4 player host-authoritative co-op; desktop↔web crossplay; shared ships; room codes |
| **M7 — Polish & release** | 4–6 wks | Ship it | Tutorial hints, audio pass, settings, gamepad, performance tuning per platform, save migration, release builds |

**Total:** roughly 8–12 months to v1.0.

## 17. Key risks

| Risk | Impact | Mitigation |
|---|---|---|
| Voxel meshing too slow in GDScript / on web | High | M0 spike decides first; escape hatch to compiled extension for hot paths; time-sliced meshing |
| Walking inside moving ships | High | Prototype in M2 with ship-local physics space |
| Desktop↔web crossplay networking | High | Network-ready command layer from M1; WebRTC + signaling validated early in M6; relay fallback |
| Float precision at space scale | Medium | Floating origin and per-system coordinates from M3 |
| Web memory and download size | Medium | Strict web presets, compressed assets, budgets tracked per milestone |
| Scope creep (it's a sandbox!) | High | Stretch list in §15 is frozen until v1.0 ships |

## 18. Open questions

- Final game name?
- Team size and roles (affects roadmap durations)?
- Distribution and pricing (free web demo + paid desktop? fully free?)
- Gamepad parity on web vs. desktop?
- Should Explorer mode support optional permadeath or "hardcore" hazard settings?
