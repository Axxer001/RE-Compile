# RE:Compile: architecture and rehaul plan (bullet-time action shooter)

Status: draft 1, 2026-11-09. Supersedes `design-brief.md` (scavenging-quota horror) for all new work.
Engine: Godot 4.7.2, GDScript only, Forward+ (desktop) and Mobile renderers, 60 Hz physics.

## 1. What changes

| | Current FPS build (M0–M5b) | Final plan |
|---|---|---|
| Genre | Slow scavenging horror, quota loop (Lethal Company feel) | Fast arena shooter with bullet time (Doom, Ultrakill, Severed Steel, Superhot, Beyond Citadel) |
| Player speed | Walk 3.5 / sprint 6 m/s, weight slows you | Run ~10 m/s; dash, slide, double jump; no weight penalty |
| Goal | Meet a money quota over nights | Hack every computer and retrieve all research files |
| Loop | Van → night → extract → bank | Enter → fight → hack → objective complete |
| Pressure | Building "pressure", darkness, stealth | Enemy waves and placement; speed and skill |

About 60% of the code survives: inventory, health, damage, the action clock, weapon data, hack terminals, pickups, navigation, SFX, input routing, the viewmodel springs and the test harness. The horror and economy layer is retired.

## 2. Feasibility

**Verdict: feasible.** Every mechanic is standard first-person-shooter work in Godot; nothing needs an engine change.

| Area | Difficulty | Main risk | Mitigation |
|---|---|---|---|
| Movement (dash, slide, double jump) | Medium | Collision edge cases (slide under ledges, dash into walls) | Shape-cast before the dash; a slide-height capsule; unit tests on each state |
| **Bullet time** | **High (the core feel)** | Slowing the world but not the player, without breaking physics or the audio pitch | Our own `TimeService` scale on simulation deltas, never `Engine.time_scale` (see §4.2) |
| Guns (recoil, ADS, reload, spread) | Medium | Tuning, not code | Data-driven `WeaponDefinition`, with a tuning scene |
| Visible bullets in bullet time | Medium | Hitscan is invisible when slowed | Pooled fast projectiles (tracers) with swept raycasts |
| Starter zombies | Medium | Many CharacterBody3Ds slow the frame | Navigation grid, a capped count, pooling, LOD on animation |
| Hack questions (Python) | Low code, **content heavy** | Writing 40–60 good questions | JSON question bank with a validator in the Content suite |
| HUD, inventory, menu | Low–medium | | Godot Control nodes, one theme |
| Grey-box arena | Low | | Reuse `greybox.gd` |
| Art (weapons, arms, zombies) | Medium | Licence-safe first-person gun models | CC0 packs (see §9) or blockout guns at first |

**Estimate:** 6 milestones (R0–R5) to the 50% MVP. At the current pace of the agent sessions (M0–M5b took about a day of sessions), that's roughly **5–8 working days**, plus tuning and playtests. Tuning the bullet-time feel is the part most likely to run long.

## 3. Folder layout (target)

```
scripts/
  core/        game_session, time_service*, objectives*, input_router, save_settings*
  player/      player_controller (rework), movement_states*/, player_stats*
  combat/      combat_controller, weapon_controller*, projectile_pool*, recoil*, damage_packet,
               health_component, hitbox*, spring, weapon_view, bullet_time* (ability)
  items/       item_definition, weapon_definition (+recoil/ads), weapon_instance, inventory (rework)
  enemies/     enemy_base*, shambler (rework), runner*, spitter*, enemy_director*
  world/       greybox, terminal3d (rework), pickup3d, door, navigation_grid, noise_service
  hack/        hack_session*, question_bank*  (data/hack/questions.json)
  ui/          hud*, inventory_panel (rework), pause_menu*, hack_panel* (replaces terminal_panel)
  audio/       sfx (+ bullet-time pitch bus)
data/  weapons/*.tres  items/*.tres  enemies/*.tres*  hack/questions.json*  levels/greybox.json*
tests/ simulation/ render/ performance/   (verify.ps1 stays the gate)
```
`*` = new. Retired: `career.gd`, `van_panel.gd`, `phone_*`, `proctor.gd`, `blackout.gd`, `tracer.gd` (the 3D stalker),
the quota and "pressure" parts of `run_state`/`main`. Move them to `reference/` rather than deleting them.

## 4. Systems

### 4.1 Player movement: `player_controller.gd` + state machine
States: `Ground`, `Air`, `Dash`, `Slide`. Each state is one small script; the controller owns the velocity and `move_and_slide()`.

| Action | Rule (starting numbers; tune in playtests) |
|---|---|
| Run (WASD) | 10 m/s, accel 80 m/s² ground, 25 air; momentum kept from dash and slide |
| Jump (Space) | 5.5 m/s up; coyote time 0.1 s; jump buffer 0.1 s |
| Double jump | One extra jump in the air; resets on landing |
| Dash (Shift) | 18 m/s burst for 0.15 s in the move direction (forward if none); 0.6 s cooldown, or 2 charges (decide in tuning); shape-cast stops it at walls |
| Slide (Ctrl) | Capsule drops to 1.0 m; keeps speed (and gains on slopes), ground friction 2; ends on Ctrl again, a jump (slide-jump keeps momentum), a stop, or 1.2 s; stand-up probe already exists (`can_stand`) |
| ADS (RMB) | FOV 90 → 65, move ×0.7, spread ×0.3, viewmodel to its ADS pose |

Gravity 18 m/s² (snappier than the current 12). Mouse look stays on `_unhandled_input`.

### 4.2 Bullet time: `time_service.gd` (autoload) + `bullet_time.gd` (player ability)
**Design:** pressing Q drains a meter and slows the **world** to ×0.25. The player moves and aims at ×0.75, and fires and reloads at full rate (Severed Steel / Max Payne style). Superhot's "time moves when you move" is an optional later mode.

```
TimeService.world_scale  (1.0 normally, 0.25 in bullet time; eased over 0.15 s)
TimeService.player_scale (1.0 normally, 0.75 in bullet time)
world_dt  = delta * world_scale    -> enemies, projectiles, hazards, particles, animation speed_scale
player_dt = delta * player_scale   -> player movement; weapon clock uses delta (full rate)
```
- **Not `Engine.time_scale`:** that would slow the player, the physics tick and UI tweens too.
- Everything that simulates takes its delta from `TimeService`. `move_and_slide()` uses the physics delta internally, so enemies scale their velocity by `world_scale` before calling it.
- Meter: max 100; drains 25/s while active; recharges 10/s after a 1.5 s delay; can't start below 15. These are `PlayerStats` values, so upgrades later are just data.
- Feedback: desaturate and add a vignette with a post-process shader, low-pass and pitch-down the SFX/music bus, and slow (still visible) tracers. Entering and leaving bullet time each play a sound.
- Tests: an enemy moves 0.25× as far in bullet time; a projectile covers 0.25× the distance; player speed is 0.75×; fire interval is unchanged; the meter drains and recharges; you can't start below 15.

### 4.3 Weapons: `weapon_controller.gd`, `projectile_pool.gd`, `recoil.gd`
The existing `combat_controller` action clock (windup → active → recovery, with hits resolved once) is kept for melee and as the fire/reload timer.

| Weapon | Slot | Type | Key stats (first pass) |
|---|---|---|---|
| Kitchen Knife | 3 Melee | melee | 20 dmg, 0.35 s cycle, reach 1.6 m, 70° arc |
| Baseball Bat | 3 Melee | melee | 55 dmg, 0.9 s cycle, reach 2.0 m, 100° arc, knockback |
| Glock | 2 Secondary | semi | 22 dmg, 0.15 s, mag 17, reload 1.3 s, low recoil, falloff from 25 m |
| AK47 | 1 Primary | auto | 30 dmg, 600 rpm, mag 30, reload 2.2 s, moderate climbing recoil, falloff from 45 m |
| 12 Gauge | 1 Primary | pellets | 9 × 12 dmg, 0.8 s, 6 shells, one-at-a-time reload (0.5 s each, cancellable), 7° spread, falloff from 10 m |
| Frag / molotov | 4 Throwable | throw | reuse `hazards.gd` |

New `WeaponDefinition` fields: `recoil_pattern` (array of Vector2 per shot), `recoil_recovery`, `ads_fov`, `ads_spread_mult`, `falloff_start/end`, `projectile_speed`, `pellet_damage`, `reload_style` (mag or per-shell), `slot` (primary/secondary/melee/throwable).

- **Bullets:** pooled projectiles, 300 by default. Speed 250 m/s at normal time, so a bullet looks hitscan-like at 1× and becomes a visible tracer at 0.25×. Each tick sweeps a raycast from its last position (no tunnelling), hits a `Hitbox` (head ×2, body ×1, limbs ×0.75) and applies a `DamagePacket` once.
- **Recoil:** a camera kick from the pattern plus a spring return (`spring.gd`); visual kick on the viewmodel spring.
- **Drop (G):** spawns a `pickup3d` carrying the `WeaponInstance` (it keeps its ammo); the slot is emptied.
- **Switching (1–4):** a 0.25 s raise, cancels a reload, can't happen mid-melee-swing.

### 4.4 Inventory: `inventory.gd` (rework)
- 3 weapon slots (primary, secondary, melee) + 1 throwable selector + **12 general slots** (ammo, throwables, consumables, research files).
- Ammo stacks per type (9 mm, 7.62, 12 ga) in the general slots; reload pulls from them.
- Keep the existing guarantees: nothing duplicates, nothing is lost silently, and `snapshot()` gives a checkpoint.
- **Tab** opens the panel: Max HP, Max Bullet Time, the 3 weapon slots and 12 slots. Drag to swap or drop. **Decision: the game pauses while it's open** (recommended for a fast shooter).

### 4.5 Enemies: `enemy_base.gd` + 3 starter types + `enemy_director.gd`
States: `Idle → Alert → Chase → Attack → Stagger → Dead`. Senses: sight cone plus line of sight, and gunshot noise (`noise_service`).

| Type | Role | Numbers |
|---|---|---|
| Shambler | Fodder; teaches aim | 60 HP, 3 m/s, bite 15 dmg / 1.2 s |
| Runner | Rushes you; teaches dash and slide | 40 HP, 9 m/s, lunge 20 dmg, 0.4 s wind-up tell |
| Spitter | Ranged; teaches bullet-time dodging | 70 HP, keeps 12–18 m away, an acid glob projectile (slow, visible) for 18 dmg |

- Hit reactions: stagger at a damage threshold, knockback from the bat, a headshot kill pops the head (for Ultrakill-style feedback).
- `enemy_director`: spawns from markers per room/trigger, caps the number alive at 24, and pools dead bodies.
- Animation: Quaternius UAL clips (already in the project), `play(clip, 0.2)` crossfade, random idle phase, `speed_scale = world_scale`.

### 4.6 Hacking: `hack_session.gd`, `question_bank.gd`, `hack_panel.gd`, `terminal3d.gd`
- A computer needs power (a lit `powered` flag; generators and breakers can come later) and shows a prompt when you're in range. **E** opens the monitor overlay.
> **Superseded 2026-11-14 [Sir]:** the hack-question bank below belongs to the archived shooter; the Grimoire game teaches **C++** (see `pivot-grimoire-plan.md`, "Teaching language: C++").

- **Question types (Python):**
  - `complete_line`: a code snippet with one blank line; free-text answer, compared after normalising whitespace, with accepted alternatives.
  - `multiple_choice`: 4 options, one correct.
- `data/hack/questions.json`: `{id, type, difficulty, prompt, code[], blank_line, answers[] | options[] + answer, explanation}`. A terminal draws 1–3 questions by difficulty with a seeded RNG, with no repeats within a run.
- Wrong answer: a 3 s lockout and an alarm noise that pulls nearby enemies. Success: the file is retrieved (+1 objective) and the screen shows "FILE RECOVERED".
- **Decision: the world keeps running while you hack.** That keeps the pressure on, and bullet time can't be used while the panel is open. The alternative is to pause.
- The Content suite validates every question: schema, the answer exists, and for `complete_line` the snippet *with the answer filled in* is valid Python, checked offline by `tools/validate_questions.py`.

### 4.7 Objectives: `objectives.gd`
A data list per level: `{id, text, kind: hack|reach|kill, targets[], count}`. The HUD (top right) shows the current one ("Recover research files 2/6"). All files retrieved → "Reach the exit" → level complete screen (time, kills, accuracy, bullet time used).

### 4.8 HUD and UI: `hud.gd`, `pause_menu.gd`
| Position | Content |
|---|---|
| Top left | HP bar + number; bullet-time meter (pulses when full, greys out below 15) |
| Bottom right | Weapon or throwable icon and name; `mag / reserve` for guns |
| Top right | Current objective |
| Centre | Dynamic crosshair (spread), hit marker, kill marker |
| Edges | Damage direction indicator; low-HP vignette |

Esc menu: Resume, Settings (mouse sensitivity, FOV, the viewmodel-feel toggle `feel_enabled`, volume, key rebinding), Restart, Quit. Settings saved to `user://settings.cfg`.

### 4.9 Greybox level: `data/levels/greybox.json` + `greybox.gd`
One wide arena about 120 × 80 m built from blocks:
- a spawn room;
- 3 combat zones (an open courtyard, a pillar hall, a corridor maze with cover);
- slide gaps, double-jump ledges, 6 powered PCs and an exit door.

Each zone has trigger volumes that wake its spawns (`Triggerable` pattern). Lighting is plain (the flashlight is still on F), and the lo-fi filter is dropped by default.

### 4.10 Audio
Reuse `sfx.gd`. Add a bullet-time bus (low-pass + pitch 0.6) and per-weapon fire, reload and empty sounds. Gunshots also emit `noise_service` events, which wake enemies.

## 5. Data flow (one frame)

```
input_router -> intent {move, look, jump, dash, slide, fire, ads, reload, slot, bt, interact}
TimeService.tick(delta)                       -> world_scale, player_scale
player_controller.simulate(intent, player_dt) -> movement state machine
bullet_time.simulate(intent, delta)           -> meter, TimeService target scale
weapon_controller.simulate(intent, delta)     -> fire -> projectile_pool.spawn / melee hit query
projectile_pool.tick(world_dt)                -> swept rays -> Hitbox -> HealthComponent.apply(DamagePacket)
enemy_director.tick(world_dt) -> enemies (senses -> state -> nav velocity * world_scale)
objectives / hack_session                     -> events -> HUD
publish(): HUD, viewmodel springs, post-process, audio bus
```
Simulation stays deterministic and testable without rendering (the current `simulate()`/`publish()` split is kept).

## 6. Milestones to the 50% MVP

| # | Milestone | Deliverables | Gate (`verify.ps1`) |
|---|---|---|---|
| **R0** | Pivot | Retire the quota, van, phone, proctor, blackout and tracer code to `reference/`; new `design-brief`; `TimeService` autoload; key map per spec; all suites green on the slimmed project | Content + Simulation + Render PASS |
| **R1** | Movement | Ground/Air/Dash/Slide states, double jump, coyote time and jump buffer, ADS FOV | Movement tests: dash distance, slide cancel, double-jump reset, stand-up probe |
| **R2** | Guns and bullet time | `weapon_controller`, projectile pool, recoil, ADS, reload (mag and per shell), Glock/AK/12 Gauge data, drop/switch, bullet-time ability with meter, shader and audio bus | Fire rate, falloff, pellets, no tunnelling, bullet-time scale tests; Performance p95 with 300 bullets |
| **R3** | Melee + inventory + HUD | Knife and bat on the action clock; 3+1+12 inventory; Tab panel; HUD layout; pause menu + settings | Inventory invariants; HUD render captures |
| **R4** | Enemies | `enemy_base`, Shambler/Runner/Spitter, director, hitboxes/headshots, stagger, spitter projectiles in bullet time | AI state tests; 24 enemies + 300 bullets perf budget |
| **R5** | Hack + objectives + greybox | Question bank (≥ 40 Python questions), hack panel, terminals, objectives, the arena with 6 PCs and an exit, level complete screen | Question validator; full-run simulation (spawn → 6 hacks → exit) |
| R6 (50% done) | Tune and optimise | Playtest passes on feel numbers; 144 FPS target on your PC, 60 FPS floor; encrypted export | Performance + Mobile PASS; manual playtest checklist |

Each milestone ends with every suite green and a session log in Irminsul.

## 7. Performance budget

| Item | Budget |
|---|---|
| Frame (desktop, Forward+) | ≤ 6.9 ms (144 FPS); p95 ≤ 10 ms. **Superseded 2026-11-13 [Sir]:** the stress suite's p95 budget is 7.7 ms measured on the real clock (Time.get_ticks_usec), not the smoothed delta |
| Live enemies | 24 (pooled); animation only for enemies on screen or within 30 m |
| Projectiles | 300 pooled; each tick is one ray per bullet |
| Draw calls | Greybox uses MultiMesh for repeated blocks |
| Physics | 60 Hz; enemies on layer-masked collisions (enemies don't collide with each other's hitboxes) |

## 8. Testing (unchanged gate, new suites)
- Simulation: movement, bullet time, weapons, inventory, enemies, hack and objectives. All headless and deterministic (seeded).
- Render: HUD captures, viewmodel poses, the bullet-time shader on/off.
- Performance: the stress scene with 24 enemies, 300 bullets and bullet time toggling.
- Content: weapon, enemy and question data validation.

## 9. What we need

| Need | Source / owner | Notes |
|---|---|---|
| First-person gun models (pistol, AK-type, pump shotgun), knife, bat | CC0 packs (Quaternius, Kenney, Poly Pizza CC0) or the current code-built blockouts until then | Check each licence in `asset-licenses.md` |
| First-person arms/hands | CC0, or keep the code-built hand | |
| Zombie models + animations | Already have Quaternius UAL + outfit builder | Runner/Spitter as recoloured and rescaled variants |
| SFX (guns, reloads, impacts, bullet time, UI) | CC0 (Kenney, freesound CC0) | |
| Python question bank (40–60) | **You**, with Claude drafting and you reviewing | You know your target players best |
| Feel tuning playtests | **You** | 15-minute sessions after R1, R2 and R4 |
| Agent split | Opus: TimeService, weapons, enemies, integration. Astra: HUD, menus, inventory panel, question validator, asset import | Matches the existing Opus/Astra split |

## 10. Decisions to confirm
1. Bullet time: player at ×0.75 and full fire rate (recommended) vs. a full Superhot "time moves when you move" mode.
2. The world keeps running while hacking (recommended) vs. pausing.
3. Tab inventory pauses the game (recommended) vs. real-time.
4. Dash: cooldown vs. 2 charges.
5. **Weapon names:** "Glock" is a registered trademark (and "AK47" is generic but often avoided too). Shipping real brand names can need a licence, so the plan uses in-game names such as "G17 Pistol", "AKM Rifle" and "12 Gauge". Confirm or choose others.
6. Horror and darkness: keep the flashlight and some dark rooms for atmosphere, or go fully lit arena style.

## 11. Art direction (decided 2026-11-10)

**Base look: Left 4 Dead 2-style lighting and grading over low-poly characters.**
We copy techniques and values (fog colours, light temperatures, grading), never assets.

| Layer | Approach | Godot implementation |
|---|---|---|
| Colour grading | Muddy, slightly desaturated: warm sodium orange highlights, cold blue-green shadows | `Environment.adjustment_color_correction` (a LUT), saturation about 0.85, contrast curve |
| Fog | Thick, distance-hiding, per-zone colour | Volumetric fog (Forward+) plus depth fog; reduce it or turn it off on Mobile |
| Lights | Strong practical lights: fluorescents (some flicker), emergency red/orange, fire; the shadowed flashlight on F | `OmniLight3D`/`SpotLight3D` with shadows only on key lights; SDFGI or baked `LightmapGI` for the static arena |
| Environment textures | Grimy, worn 512–1k textures; decals for blood, dirt, graffiti, posters | CC0 from ambientCG / Poly Haven; `Decal` nodes |
| Characters and entities | **Low-poly kept** (Quaternius/Kenney), with grimy, desaturated albedo (dirt, blood) | The same lit `StandardMaterial3D` as the world, so fog and lights tie them in; a faint rim light for readability |
| Post-process | Film grain, slight vignette, full resolution | One full-screen shader; the `lofi_view.gd` low-res filter is retired |
| Feedback | Blood bursts, wound decals, hit sparks | GPU particles plus decals; dismemberment later |
| Bullet time | Desaturate the world further; enemies, bullets and pickups keep full colour | A grade blend in the bullet-time shader |

**Later option (from Outlast):** a grainy, green night-vision "camera" mode (noise, scanlines, a recording overlay) as a short-duration ability or hacking-terminal camera effect. Not in the 50% MVP.

**Performance:**
- Volumetric fog and shadowed lights are the main cost.
- Budget: at most 4 shadowed lights visible at once; fog at half resolution.
- Must hold the 6.9 ms frame budget (§7).
- Mobile: no volumetrics, at most 1 shadowed light (the flashlight).

**Reference process:**
- Optionally install L4D2 plus its official Authoring Tools.
- Read the fog, colour-correction, tonemap and light entity values from 2–3 chosen maps in Hammer.
- Match a lit grey-box mock-up against the user's screenshots.
- No L4D2 files (textures, models, LUTs, sounds) enter this project.
