> **Superseded (2026-11-09, R0):** this salvage-horror brief is replaced by `docs/architecture-rehaul.md` (bullet-time arena shooter). Kept for history; the retired code is in `reference/legacy-horror/`.

# RE:Compile: first-person design brief

Status: draft 1, 2026-11-09. Supersedes the isometric 2D design for new work; the 2D project (`outputs/RECompile-Campus`) stays frozen at T23 as a rules reference.

## 1. Pitch

A single-player first-person scavenging horror game set on the WMSU campus after a quarantine. You work night shifts for a salvage contractor. Each night you enter the locked-down College of Computing Studies, recover research and equipment worth enough to meet the contractor's quota, and get out before the building turns on you. You're always choosing between going one more room deeper and leaving with what you have.

Inspiration: the scavenging-quota loop and lo-fi dread of the co-op horror genre (Lethal Company is the reference for *feel and mechanics only*). All characters, monsters, setting, items, art, audio and interface are original or licensed (see `asset-licenses.md`).

## 2. Pillars

| Pillar | Meaning in play |
|---|---|
| **Greed against survival** | Every item is weight, noise and risk. Leaving early is always an option, and always costs you |
| **Read the building** | Enemies follow learnable rules (sound, light, line of sight). Knowledge, not reflexes, keeps you alive |
| **Lo-fi dread** | Low-resolution render, fog, a weak flashlight, flickering fluorescents, sparse music |
| **Fair systems** | The rules proven in the 2D project: nothing duplicates, nothing is lost silently, every attack resolves once |

## 3. Core loop

| Step | What happens |
|---|---|
| 1. Briefing (van terminal) | Night number, days left before the quota is due, quota target, the contractor's tip about a high-value room. Buy and repair gear with the money banked so far |
| 2. Entry | Choose an entrance: main hall, service door or roof access, each with a different start and risk |
| 3. Scavenge | Explore the building with a flashlight. Find loot (research drives, lab instruments, faculty laptops, keycards). Heavier loot slows you and makes noise |
| 4. Threat escalates | The building's "pressure" rises with time and noise: more enemies wake, lights fail, doors lock |
| 5. Extract | Carry loot back to the van. Anything carried out is banked; anything dropped stays inside |
| 6. Quota check | After the last night of the cycle, meet the quota or the run ends. Meet it and the next cycle starts with a higher quota |
| Death | You lose what you were carrying that night. The run continues if days remain, with a cost for the lost shift |

**Run length:** a night is 12–15 minutes; a cycle is 3 nights; a full run is open-ended (quota rises each cycle).

## 4. Setting and level

- **Location:** the WMSU College of Computing Studies, a fictionalised version based on the 2D project's Classroom 104 and east corridor.
- **Layout:** one building on two floors to start.
  - Ground floor: lobby, two classrooms, computer lab, faculty offices, server room, restrooms, stairwell.
  - Upper floor: lecture hall, research lab, dean's office.
- **Building it:** hand-made rooms (modules) joined in a fixed plan for M1–M3. Room *contents*, such as loot, locked doors and enemy spawns, are shuffled each night from data. A procedurally generated layout is a later option, not MVP.
- **Story:** the lecturer's research (the 2D project's goal) becomes the long arc. Notes and terminals across nights reveal what happened. Collecting the research drives is the cycle-end goal.

## 5. Player

| System | Rule (proposed starting values) | Carried from 2D project |
|---|---|---|
| Health | 100 HP; no regeneration during a night; first-aid items heal | HealthComponent rules (one hit per attack, faction checks, immunity windows, death latched once) |
| Stamina | Sprint and melee cost endurance; regenerates after 1 s | EnduranceComponent |
| Movement | Walk 3.5 m/s, sprint 6 m/s, crouch 1.8 m/s (quiet); carried weight slows walk and sprint | Locomotion rules adapted to 3D |
| Inventory | 4 quick slots (keys 1–4) + two-handed heavy items held one at a time; backpack upgrade to 8 | Item definitions, per-run items, all-or-nothing transfers, monotonic upgrades, drop-before-remove |
| Flashlight | Battery drains; swap batteries; shining it on some enemies provokes or repels them | New |
| Scanner | Press to ping nearby loot value and doors (short cooldown, makes a small noise) | New |
| Noise | Footsteps, sprint, doors, dropped heavy loot, gunshots emit noise events by radius | NoiseService (origin-based, hearing not tied to audio) |

## 6. Combat and tools

Combat is a last resort: weapons are rare, ammo scarce, and noise draws more threats.

| Item | Role | Notes |
|---|---|---|
| Fire extinguisher / mop handle / bat | Starting melee | Wind-up/commit/recovery clock, swing arc, one hit per swing |
| Knife | Quiet melee | Short reach, low stamina |
| Pistol | Rare | Magazine per gun, reload transfers once at commit |
| Shotgun | Rare, very loud | 6 pellets, one shell |
| Assault rifle | Rare, automatic | Fixed 0.1 s interval while held; stops on release or focus loss |
| Noise maker / bottle | Distraction | Throw rules from 2D: aim, cancel, release, swept landing, consumed once |
| Flashbang | Escape tool | Short stun; blast rules from the 2D T24 plan |

## 7. Enemies (original)

| Enemy | Behaviour rules | Counter |
|---|---|---|
| **Shambler** (infected student) | Wanders; hears noise and goes to where it came from; attacks on contact. Slow but relentless | Stay quiet, close doors, melee one at a time |
| **Tracer** (crawls in ceiling ducts) | Moves through vents above you; drops behind a player who stands still under lit ceiling tiles too long | Keep moving; listen for scraping above |
| **The Proctor** (faculty silhouette) | Patrols one floor along a fixed route. If it sees you carrying research loot, it follows and locks doors ahead | Hide loot, break line of sight, take another route |
| **Blackout** (night shift's end) | Arrives late in the night: all lights fail floor by floor; it hunts within the dark but avoids the flashlight beam | Leave before it arrives, or keep a charged flashlight |

Each enemy has a written perception rule (sight cone, hearing radius, light response), so it can be tested headlessly like the 2D shambler.

## 8. Look and sound

| Element | Direction |
|---|---|
| Render | Godot 4.7.2 Forward+ renderer; render at low internal resolution (about 480p) scaled up with nearest-neighbour pixels; affine-style texture wobble optional |
| Lighting | Dark baseline; fluorescent tubes that flicker and fail; flashlight as the main light; volumetric fog in corridors |
| Post | Colour grading toward sickly green/amber, film grain, slight vignette, chromatic shift on damage |
| Models | Low-poly Quaternius/Kenney packs with downsampled CC0 textures, so mixed packs look consistent |
| Audio | Positional sound for footsteps, doors and enemies; fluorescent hum; almost no music during a night; a van radio between nights |
| Interface | Minimal: no health bar (screen effects instead), quota and clock on the van terminal and wristwatch |

## 9. Technical plan

| Area | Decision |
|---|---|
| Engine | Godot 4.7.2, GDScript, typed |
| Project | `outputs/RECompile-FPS` (this folder), separate from the 2D project |
| Reused code | Port and adapt: `run_state`, `input_router`, `game_session` tick order, `health_component`, `damage_packet`, `endurance_component`, `combat_controller` (3D aim and rays), item definition/stack/weapon instance, `inventory`, `noise_service`, throw rules. Each reused file comes with its tests |
| Not reused | Isometric projection, room tiles, wall cutaway, 2D movement, actor views, PZ assets |
| Verification | `verify.ps1` with Content / Simulation / Render / Performance suites, headless where possible, evidence folders, mutation checks |
| Performance target | 60 FPS at 1080p output (480p internal) on the RTX 2050; p95 frame time under 16.7 ms with 6 active enemies |
| Data | Items, weapons, enemies, rooms and loot tables as `.tres` resources; content validated by the Content suite |

## 10. Milestones (dates to be set after M0)

**Target:** the 50% MVP (2D ARCHITECTURE §1): four rooms with doors and extraction, three melee, three ranged and two throwable weapons, HP/dodge/4-8-12 inventory, two hacking terminals with research gating, the phone, and verified animations. Its mapping onto these milestones is in `tasks/todo.md`; quota/night loop and the extra enemies come after it.

| Milestone | Contents | Done when |
|---|---|---|
| **M0 Foundation** | Project, `verify.ps1`, ported core rules with their tests, first-person controller in a greybox room | All four suites run; walk, sprint, crouch, collide, open a door |
| **M1 Scavenge** | Flashlight, scanner, pickups, inventory, carry weight, extraction van, money banked | Pick up loot, carry it out, see the money banked |
| **M2 Threat** | Shambler with hearing and navigation, noise events, player death, night restart | A night can be lost to a Shambler driven by noise |
| **M3 Building** | Ground floor rooms with first asset pass and the lo-fi render look | Full ground floor walkable and lit; licence list up to date |
| **M4 Loop** | Quota, 3-night cycle, van terminal shop, night shuffle of loot and spawns | A full cycle can be won or lost |
| **M5 Roster** | Tracer, Proctor, Blackout; melee, pistol, throwables | Each enemy has tested rules and a counter |
| **M6 Slice** | Upper floor, story notes, audio pass, performance pass, launcher | A fresh run is playable start to quota without the editor |

## 11. Decisions (Sir, 2026-11-09)

1. **Names:** keep the real WMSU / College of Computing Studies names.
2. **Rifle:** keep the automatic assault rifle (28 HP, 30 rounds, fixed 0.1 s interval from the 2D rules); no taser.
3. **Death penalty:** lose the loot carried that night **and** pay a money fine from the banked total (amount to tune in M4).
4. **Platforms:** Windows first. Mobile (Android) is a stretch target: needs touch controls (virtual stick, look-drag, context buttons), the Mobile renderer and a lower effects tier. Checked at M3 with a test export; not a blocker for the slice.
