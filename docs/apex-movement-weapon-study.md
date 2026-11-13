# Apex movement, weapons, and animation study

Research date: 2026-11-09 (Asia/Manila). Scope: improve RE:Compile's responsiveness, movement decisions, weapon feel, and runtime cost. Research only; no gameplay changes made.

Concurrent-edit note: movement files changed during this research. Final inspection found 7 m/s walking, 10 m/s forward sprinting, new mantle/lurch/wall-movement code, and dash/double jump disabled by default. The movement comparison below reflects that final inspection, not the earlier R1 snapshot. This research did not implement or test those concurrent changes.

## Evidence boundaries

Update 2026-11-10: located Apex at `C:\Program Files (x86)\Steam\steamapps\common\Apex Legends`. The earlier location check missed the installation. Steam build 26174491, game version v3.0.4.24, build string `R5pc_r5-310_J24_CL11700487_FSv31_0_2026_10_23_17_04`. Offline package inventory and weapon-definition extraction now completed; see the installed-build findings below. No live process or executable was analyzed. Animation timing, runtime transition logic, effective recoil equations, and movement engine constants remain unverified.

Labels used below:

- **Official:** EA/Respawn descriptions and dated patch notes. Historical changes establish design decisions, not necessarily today's numerical balance.
- **Researcher observation:** original investigations/demonstrations published by the Apex Movement Wiki contributors or recoil-tool author. Useful hypotheses to reproduce; not our own measurements or developer confirmation.
- **Released code:** Valve/id source, useful for algorithm study; not Apex source code.
- **Local source:** directly inspected RE:Compile implementation.
- **Proposal:** our design for RE:Compile, not a claim about Apex internals.

The GDC 2022/2024 session listings were accessible. An attempted transcript retrieval for the 2022 talk failed: yt-dlp reported a broken site extractor and a DNS failure. No talk footage or transcript was obtained. Do not cite those listings as proof of specific rig/blend-tree internals.

## Installed-build findings (2026-11-10)

Used official RSX 2.4.1 release, verified archive SHA-256 `be44e47fe5edd45cbdb67e704134a4a6c6c66cbf77a2849e47dd1de84e9f3cd4`. Read `common.rpak`, `common_early.rpak`, and `common_mp.rpak`; RSX also loaded `patch_master.rpak` and referenced streaming packages. Exported only weapon-definition assets, not meshes/textures or the entire game. No Apex launch or live attachment.

Evidence directory: [apex-study](C:/Users/Axxer/Documents/Codex/apex-study). [Manifest and hashes](C:/Users/Axxer/Documents/Codex/apex-study/evidence/manifest.json), [full asset inventory](C:/Users/Axxer/Documents/Codex/apex-study/evidence/assets.csv), [selected animation names](C:/Users/Axxer/Documents/Codex/apex-study/evidence/selected-animation-inventory.csv), [weapon export log](C:/Users/Axxer/Documents/Codex/apex-study/evidence/weapon-export.log).

The inventory contains 324 `wepn`, 30,426 `aseq`, and 830 `arig` entries. These are asset entries, not counts of playable guns or unique visible animations. All 324 weapon-definition entries were exported as text. RSX reported one p2011_auto cosmetic animation with missing animdesc and skipped it. The inventory run also logged a cache reload despite `-nocachedb`; retain this tool limitation when reproducing results. Streaming-package hashes were not collected, so the manifest is not a hash of every referenced dependency.

### Stored weapon parameters

The table is transcribed from top-level definition fields, excluding nested modifier blocks. Times are presented as seconds according to their conventional field semantics; no in-game stopwatch verification was performed. Do not interpret a single field as complete input-to-fire latency.

| Raw field | R-301 (`mp_weapon_rspn101`) | Pistol (`mp_weapon_semipistol`, P2011 identifier) | Peacekeeper (`mp_weapon_energy_shotgun`) |
|---|---:|---:|---:|
| `zoom_time_in` | 0.270 | 0.180 | 0.220 |
| `zoom_time_out` | 0.230 | 0.160 | 0.200 |
| `ads_move_speed_scale` | 0.500 | 1.000 | 0.900 |
| `deploy_time` | 0.600 | 0.225 | 0.450 |
| `holster_time` | 0.550 | 0.180 | 0.400 |
| `raise_time` | 0.500 | 0.225 | 0.300 |
| `lower_time` | 0.400 | 0.180 | 0.250 |
| `reload_time` | 2.400 | 1.250 | 2.500 |
| `reloadempty_time` | 3.200 | 1.250 | 3.500 |

Identity evidence: the rifle and shotgun reference `weapon_r301` and `weapon_peacekeeper` icon paths respectively. The pistol uses P2011 localization IDs; do not assume the single-pistol definition represents every current akimbo/mode configuration.

Sources: [rifle definition](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/mp_weapon_rspn101.txt:236), [pistol definition](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/mp_weapon_semipistol.txt:232), [shotgun definition](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/mp_weapon_energy_shotgun.txt:296). Definitions also contain nested modifier blocks, including multiplied handling/reload values; those were deliberately not flattened into the table. Which blocks are active needs runtime/context verification.

### Recoil and weight evidence

The rifle references pattern `rspn101_2`, spring `rspn101_vkp`, and hot spring `rspn101_vkp_hot`. Its exported settings include heat-per-shot 1.0, cooldown hold 0.08, and cooldown fade 0.05. [Definition](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/mp_weapon_rspn101.txt:258).

The named pattern exists in the exported pattern library with indexed bullet records, four numeric components per record, and loop/start metadata. The component semantics and signedness of sentinel values have not been traced; no screen-space recoil graph is claimed. [Pattern library](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/viewkick_patterns.txt:1653).

The spring library contains separate hipfire/ADS and pitch/yaw/roll parameters. The rifle normal spring's ADS pitch spring constant is 115; its hot counterpart is 0. This proves separate stored profiles, not the engine's interpolation equation. [Spring library](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/springs.txt:639).

The empty-reference definition stores `move_speed_modifier = 1.15`. This supports investigating an unarmed/holstered modifier, but the filename alone does not establish when the engine equips it. [Empty-reference definition](C:/Users/Axxer/Documents/Codex/apex-study/exports/weapon/_empty_reference_weapon.txt:68). No single physical gun-mass interpretation is established.

### Animation evidence

The inventory contains rifle first-person sequence names for sprint, sprint-slide, sprint-raise, sprint-holster, sprint-draw, ADS-in/out, reload, empty reload, late reload stages, and one-handed variants. It separately contains character reload sequences, including crouching versions, under the light character core.

This demonstrates authored context-specific assets beyond a generic bob animation. It does not prove their blend graph, runtime use, duration, event frames, or root-motion behavior. A name containing `wallrun` is not evidence that ordinary Apex characters can wall-run. No animation clips were rendered in this pass.

### Consequence for RE:Compile

Prioritize independent ADS movement, ADS transition, deploy/holster/raise/lower timings, normal/hot recoil response, and reload stages. Build original poses for the relevant movement/action combinations. Preserve the existing simulation-authoritative action clock, and verify how multiple timing fields compose before copying any totals. The web-research proposals below remain proposals; the installed values above are a reference dataset, not an instruction to retune the game automatically.

## 1. Gun weight

**Finding:** treat weight as several independent controls: travel speed, ADS strafe speed, time until a weapon is ready, visual inertia, and recoil. A single mass scalar hides those decisions.

**Researcher observation:** the ground-movement investigators report armed sprint at 260 game units/s and holstered sprint at 299, a 1.15 ratio. Their page also contains a less clearly contextualized sprint figure; use the explicit holster comparison and verify in a named build. A 15% increase from armed speed equals approximately a 13.0% penalty measured against holstered speed; those percentages use different denominators. These are game units, not directly Godot metres. [Ground movement investigation](https://apexmovement.tech/wiki/tech/General%20Tech%3EFundamentals%3EGround%3EFundamental%20Ground%20Movement%20article).

**Official:** abilities can override armed movement and handling. EA describes Ballistic's ultimate as increasing armed movement speed and reload speed. A test must record Legend, ability state, class, mode, and attachments. [EA Legend guide](https://help.ea.com/en/articles/apex-legends/abilities/).

**Local source:** `fps_controller.gd::ground_speed()` selects walk/sprint/crouch speed, applies a global ADS factor, and multiplies the action movement factor. `main.gd::simulate()` explicitly omits inventory weight. Weapon definitions have no individual ADS-speed or draw/holster-time fields.

**Proposal:** preserve the current 7 m/s walk and 10 m/s sprint as the comparison baseline initially. Give each weapon its own ADS multiplier and handling times; express heavier weapons through slower settling and more deliberate raise/reload poses. Only add a holster speed tradeoff if playtests show it creates a useful decision. Do not reintroduce bag-weight slowdown by accident.

## 2. Gun recoil

**Official:** the Season 7 L-STAR notes explain that a winding recoil pattern and awkward heat recovery made short bursts unpleasant; Respawn adjusted both. This is evidence that pattern shape and recovery cadence matter together. The same notes distinguish raising/lowering, ADS timing, and hipfire spread. [Season 7 notes](https://forums.ea.com/blog/apex-legends-game-info-hub-en/season-7-ascension-patch-notes/9462737).

EA's current aiming guide explicitly describes reduced recoil while moving aim horizontally, and recommends wall firing to observe each gun. It does not disclose a smoothing threshold, curve, or algorithm. [EA aiming guide](https://help.ea.com/en/articles/apex-legends/best-settings-pc/).

**Researcher observation:** metaflow's recoil visualizer reports correcting an earlier pattern-scale error of roughly 15%, and testing its results across FOV/scope settings. Its service was discontinued in March 2026. Useful methodological evidence; not a current-build oracle. [Author's release notes](https://github.com/metaflow/apex-recoil/blob/main/docs/release-notes.md), [project status](https://github.com/metaflow/apex-recoil).

**Local source:** `weapon_view.gd::pose()` provides a visual backward/rotational kick. `combat_controller.gd::resolve_shot()` uses the action aim and deterministic pellet directions. There is no dedicated shot-index camera recoil pattern in the inspected path. Visual weapon recoil and ballistic recoil are therefore not equivalent here.

**Proposal:** separate three channels:

1. Aim recoil: pitch/yaw impulse per committed shot, with an explicit pattern index, reset delay, and recovery rule.
2. Visual recoil: stronger gun displacement/rotation and mechanical animation, independently reduced while ADS.
3. Spread: a separate cone or pellet pattern. Never use visual gun sway as the sole authority for shot direction.

Start with a reproducible authored pattern and optional seeded variation. Apply impulses once per shot, not once per rendered frame. Choose explicitly whether recoil affects the current projectile or the next one. Allow mouse compensation without automatically dragging aim back past the player's correction. Recoil smoothing is an optional later experiment, not a guessed copy of Apex's hidden implementation.

## 3. Gun handling

**Official:** Emergence moved reload-speed bonuses from magazines to stocks, separated stock stability/sway bonuses, and used barrels for L-STAR recoil reduction. This is a concrete example of independent tuning axes. These are historical patch semantics, not a universal statement about all current attachments. [Emergence notes](https://www.ea.com/ea-play/news/emergence-patch-notes).

**Local source:** `weapon_definition.gd` has fire/reload timings, but reload commits at a shared 80% of its duration. ADS FOV and movement factor are global. Crucially, `player_combat.gd::publish()` calls `view.pose(combat, aiming_throw)`: the pose function's `aiming` argument means throwable aiming, not gun ADS. RMB ADS currently lacks a dedicated aligned gun pose in this path.

**Proposal:** add per-weapon ADS-in/out, holster, draw, tactical reload, empty reload, and ready-to-fire timing. Keep ammo transfer and chamber readiness explicit. Allow interrupted reloads without duplicating ammo. Align a sight marker to the camera aim axis; lowering FOV alone is not ADS. Blend bob/sway down while aiming and preserve readable recoil feedback.

Prototype targets below are OUR trial values, not Apex measurements:

| Parameter | Pistol | Rifle | Shotgun |
|---|---:|---:|---:|
| ADS enter | 0.15 s | 0.22 s | 0.20 s |
| ADS movement multiplier | 0.90 | 0.70 | 0.80 |
| Holster | 0.12 s | 0.18 s | 0.20 s |
| Draw until ready | 0.18 s | 0.25 s | 0.28 s |

Test these against the present build, then keep or reject them based on accuracy, response time, and player preference. Changing multiple axes at once makes results difficult to interpret.

## 4. Weapon switching

**Official evidence:** Quickdraw's historical effects explicitly included faster weapon lowering and raising. This establishes distinct handling stages; it does not prove the exact runtime ordering or cancellation rules in today's Apex. [Season 7 notes](https://forums.ea.com/blog/apex-legends-game-info-hub-en/season-7-ascension-patch-notes/9462737).

**Local source:** `player_combat.gd::equip_slot()` immediately equips when the action clock is idle and rejects switching while busy. `weapon_view.gd::show_weapon()` frees and rebuilds the visible model when the weapon ID changes. There is no dedicated holster/raise state sequence.

**Proposal:** `Ready -> Lower current -> Change equipped instance -> Raise next -> Ready`. Approximate switch latency as outgoing holster time plus incoming ready time, unless we deliberately overlap phases. Keep one pending requested slot so a slightly early press is not discarded. Define cancellation rules for firing, ADS, reload, throw, melee, death, and a second switch request.

The authoritative timer enables firing; animation follows it. A decorative animation tail must not impose an accidental extra delay. Prebuild/cache the small equipped-weapon set if profiling shows a switch-time hitch; do not pool every asset preemptively.

## 5. Movement logic and movement animation

**Released code:** Valve's `AirAccelerate` projects velocity onto the requested direction and caps added speed; it is not a simple interpolation toward a target velocity. `StepMove` compares flat and stepped travel, while `StayOnGround` performs ground-following traces. These are inspectable reference algorithms, not evidence of Apex's present implementation. [Valve movement code](https://raw.githubusercontent.com/ValveSoftware/source-sdk-2013/master/src/game/shared/gamemovement.cpp). The [id Quake III movement source](https://raw.githubusercontent.com/id-Software/Quake-III-Arena/master/code/game/bg_pmove.c) is another original reference.

**Researcher observation:** the slide investigators distinguish ground entry (over 200 units/s horizontal) from landing entry (over 90 horizontal plus 200 downward). They report a two-second slide-boost cooldown, no fixed slide-duration timer, slope-dependent results, and limited steering. Exact values remain unverified for our target build. [Slide investigation](https://apexmovement.tech/wiki/tech/General_Tech%3EFundamentals%3ESlide%3EFundamental_Slide_Tech_Article).

The air-movement investigators distinguish sustained air strafing from input-edge lurch and describe no passive horizontal air friction. Their published constants should not be transplanted into Godot without matching the equations and units. [Air investigation](https://apexmovement.tech/wiki/tech/General%20Tech%3EFundamentals%3EAir%3EFundamental%20Air%20Tech%20article).

**Local source:** RE:Compile has projected acceleration, air strafing, coyote time, buffered jumps, a stand-up probe, step-up, and a two-second slide-boost cooldown. Its slide has a 1.2 s hard cutoff, no steering branch in the inspected slide state, and switches friction to zero downhill rather than explicitly accelerating along the slope. Concurrent changes added sprint, lurch, mantle, superglide, and wall-movement paths. Tuning now sets air jumps and dash charges to zero by default. These new paths need their own validation; their existence does not prove Apex-equivalent behavior.

**Proposal, in test order:**

1. Compare the existing slide with a speed/slope-driven slide that continues while crouch is held and sufficient speed remains. Keep boost eligibility separate from slide eligibility.
2. Add modest slide steering/braking with a defined angular limit. Looking around alone should not rotate the travel vector.
3. Prototype gravity projected onto the ground plane for downhill acceleration; cap intended speed and test steep transitions.
4. If dash is re-enabled as an ability, decide its exit momentum explicitly and test controlled preservation against a reset to ground speed.
5. Give landing-to-slide its own conditions and buffer, rather than requiring ground-entry speed in every case.
6. Validate the newly added mantle/lurch/wall paths against recordings and collision tests before tuning them further. Double jump/dash are currently disabled by default; any universal version would be a RE:Compile design choice, not a baseline Apex assumption.

Movement animation should consume actual velocity, local strafe direction, grounded state, landing impulse, and movement state. Run-cycle rate follows distance traveled; landing is a one-shot event. Smooth camera-height transitions separately from collision-capsule changes. Keep camera roll and bob adjustable.

## 6. Player character animations

**Primary sources found:** Respawn's [2022 animation session](https://www.gdcvault.com/play/1027904/Animation-Summit-Sustained-Animation-Excellence) and [2024 first-/third-person animation panel](https://gdcvault.com/play/1034518/Animation-Summit-The-Legends-Behind). Listings verified, footage not reviewed. Alejandro Potter's own [Ash demo description](https://vimeo.com/642542024) states it combines motion capture and keyframing; it does not disclose the runtime animation graph.

**Local source:** `scenes/player/player.tscn` contains a capsule, head/camera, flashlight, health, and endurance. It has no full-body player skeleton. `weapon_view.gd` builds blockout weapons/hand and applies shared springs, bob, look sway, roll, and vertical lag. Its bob amplitude normalization still uses `SPRINT_SPEED = 6.0` although walking/sprinting are now 7/10 m/s. Enemy animation is a different system and does not establish player animation capability.

**Proposal:** build two presentations driven by the same gameplay state:

- First-person arms/weapon: authored idle, ADS, fire, reload, draw, holster, throw, and melee clips; additive movement sway and recoil; grip targets where useful.
- Optional world body: locomotion blend space from local velocity, upper-body aiming/weapon action layer, and jump/fall/land/slide states. Add this only if visible legs, shadows, mirrors, or third-person views justify it.

Godot's AnimationTree supports blending, state machines, and filtered animation layers. Use the documented mechanisms for our implementation; do not describe this proposed graph as Respawn's. [Godot AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html).

The motor remains authoritative for movement; animation follows its result. Ammo and damage remain simulation events. This preserves the existing headless testability while giving an artist precise timings to animate against.

## File inspection route when an installation is available

RSX's own documentation lists support for weapon definitions (`wepn`), settings data/layout (`stgs`, `stlt`), rigs (`arig`), sequences (`aseq`), models, and other RPak assets. Support varies by asset/build; the detailed weapon/sequence pages are mostly placeholders. [RSX asset support](https://github.com/r-ex/rsx/blob/main/docs/AssetTypes.md). LegionPlus explicitly points to RSX as its replacement. [LegionPlus status](https://github.com/r-ex/LegionPlus).

Start with an offline, read-only package inventory. Record build ID, package names, SHA-256, extractor version, resolved patch dependencies, and export failures. Inspect one pistol, one rifle, one shotgun, and one character before expanding the scope.

Record available handling fields, recoil pattern references, movement settings, rig hierarchy, clip duration/sample rate, additive flags, root displacement, and event markers. Preserve raw names/units alongside interpretations. A field name or an exported clip alone does not establish how runtime code uses it. Follow up ambiguous fields with controlled observation or focused static analysis of the matching binary.

No live process attachment is needed for this first pass. No extracted Apex assets are required in RE:Compile; the deliverable is measurements and independently authored behavior.

## Measurement and optimization plan

Use a named build, identical equipment, fixed FOV/sensitivity, and a neutral Legend with abilities inactive. Repeat each condition at least ten times. Video at 120 fps gives 8.33 ms frame spacing, not perfect end-to-end input timing; mark onset/endpoint uncertainty. Never treat display pixels as recoil angles without projection calibration.

| Experiment | Record | What it resolves |
|---|---|---|
| Armed vs holstered traversal | Distance/time; acceleration curve | Speed penalty vs start responsiveness |
| Weapon ADS and switching | Input, first pose change, sight alignment, first accepted shot | Animation duration vs gameplay readiness |
| Full/partial reload, interrupted at several points | Ammo before/after, first accepted shot | Transfer/chamber/cancellation semantics |
| Repeated wall sprays | Weapon, attachments, shot order, reset interval, impact distribution | Pattern vs randomness vs spread |
| Stationary vs tracking fire | Angular aim speed and recoil displacement | Whether/when smoothing changes recoil |
| Flat/uphill/downhill slides | Entry speed, path, boost interval, steering, exit speed | Slope handling vs fixed timers |
| Jump/landing/slide chains | Horizontal/vertical velocity and input timestamps | Momentum retention and buffers |
| First-person vs body animation | Contact frames, pose/clip transitions, feet sliding | Visual coherence independent of movement speed |

For RE:Compile, run the same deterministic input traces at 60 Hz physics with 60/120/144/240 Hz rendering and with bullet time on/off. Record path length, jump apex, shot timestamps, ammo conservation, switch readiness, and p95/p99 frame time. These are proposed checks, not results from this research pass.

Keep player/world/weapon clocks explicit: the current session passes player-scaled delta into combat, which conflicts with the planned full-speed weapons during bullet time. Fix that contract before authoring precise reload animations.

Profile frame-time spikes when switching weapons and allocations in per-frame view updates. Cache scene-node references and reusable query objects only where measurements justify it. Treat render interpolation separately from physics correctness; Godot documents why fixed physics and variable rendering can produce visible jitter. [Godot interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).

Recommended first experiment: one rifle, a correctly aligned ADS pose, independent gameplay/visual recoil, explicit switch readiness, and a flat-to-downhill slide course. Compare against the current controller before scaling the animation/content workload.
