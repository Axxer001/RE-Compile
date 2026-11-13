# RE:Compile FPS: task record

Target: the **50% MVP** from `RECompile-Campus/ARCHITECTURE.md` §1 (the vault's "What 50% Looks Like" entry), carried into first person. `C:\Users\Axxer\Desktop\Plan.txt` was empty (0 bytes) on 2026-11-09, so that definition governs.

## 50% MVP -> first-person milestones

| MVP requirement (2D definition) | First-person meaning | Milestone |
|---|---|---|
| Human models and skins (PZ in 2D) | Infected models from licensed packs (Kenney/Quaternius), first-person arms | M2, M5 |
| 3-4 room test map, doors, routes, extraction | Classroom 104, east corridor, computer lab, faculty office; hinged doors; van extraction | M0 (2 rooms + door), M3 (4 rooms), M1 (extraction) |
| Locomotion/combat/death/stagger animations | First-person arm animations per weapon; enemy walk/attack/stagger/death | M2, M5 |
| 3 melee: knife, bat, katana | Same, first-person swings | M5 |
| 3 ranged: pistol, shotgun, assault rifle | Same, 3D rays | M5 |
| 2 throwables: molotov, frag | Same, 3D arcs | M5 |
| HP 100, dodge, inventory 4/8/12 | Same rules; dodge = Alt dash | M0 (HP, bag rules ported), M1 (pickups), M5 (dodge) |
| Two hacking terminals, research reward, extraction gating | Two in-world terminals; research drives gate the van | M4 |
| Phone: map, clue journal, intel, hacking hints | Same (P key) | M4 |

Quota loop, night shuffle and extra enemies (Tracer, Proctor, Blackout) are **beyond 50%** and follow the slice.

## M0 — Foundation

- [x] Done 2026-11-09.
- Files: `project.godot` (Forward+ desktop, Mobile renderer override, 24 first-person actions, 60 Hz), `verify.ps1` (ported harness), `scripts/main.gd`, `scenes/main.tscn`, `scenes/player/player.tscn`, `scripts/player/fps_controller.gd`, `scripts/world/greybox.gd`, `scripts/world/door.gd`, ported rules (`run_state`, `input_router` adapted, `game_session` adapted, `damage_packet`, `health_component`, `endurance_component`, items x4, `inventory`, `noise_service`, 13 item / 8 weapon definitions), `tools/validate_content.gd`, `tests/simulation/{run_simulation,test_fps}.gd` + ported `test_health`, `test_item_instances`, `test_inventory` (bag rules), `tests/render/{run_render.gd,baseline.tscn}`, `tests/performance/{stress.gd,stress.tscn}`.
- Result: first-person controller (walk 3.5, sprint 6 with endurance drain, crouch 1.8 with 1.1 m capsule and headroom check, jump, pitch clamp ±89°), all state changed inside the session tick. Greybox Classroom 104 + east corridor with a hinged door (E on the crosshair, one toggle per press, refuses to close on a body) and a fallen duct that must be crouched under. Flashlight on F. Pause freezes clock and body and disables mouse look; held keys are flushed across context changes.
- Evidence: C `evidence/20261109-042551` (128), S `evidence/20261109-042601` (120), R `evidence/20261109-042611` (12; captures `fp-*.png`), F `evidence/20261109-042625` (p95 1.39 ms at 1920x1080, 14,880 frames); main scene 240 frames clean. Harness self-tests: fail / missing-pass / hang all reported FAIL.
- Mutations caught: standing up under the duct, sprinting while crouched, door trap check using the open pose, no input flush on pause.
- Bug found by test: the door's "something in the doorway" check used the open hinge pose, so an open door could close on the player. Fixed (closed-yaw transform).
- Asset fix (2026-11-09, Sir approved the download): re-downloaded Building Kit 1.0, Survival Kit 2.0, Car Kit 3.1 and City Kit (Roads) 2.2 from kenney.nl (11.2 MB). All 304 textured models matched byte-for-byte; the mixed furniture folder was split into `car/` and `roads/`; each kit folder now has its `colormap.png` and `License.txt`; no `.gdignore` left. Import has 0 errors. Evidence: C `evidence/20261109-043044` (130), S `evidence/20261109-043105` (120), R `evidence/20261109-043112` (12), F `evidence/20261109-043119`.
- Test note: moved bodies (doors, teleports) are visible to physics only after a physics frame; tests `await physics_frame` after them, play gets this from `_physics_process`.

## M1 — Scavenge

- [x] Done 2026-11-09, split by the five-file rule: **M1a** data/rules (`scripts/items/item_definition.gd` loot category + `value`/`weight_kg`/`model_path`, `scripts/items/inventory.gd` carried weight/loot/unload, `scripts/core/career.gd`, 4 loot items + weights on all items, `scripts/world/noise_service.gd` 3D) and **M1b** world/tests (`scripts/world/pickup3d.gd`, `scripts/world/greybox.gd` loot spawns + loading bay, `scripts/main.gd`, `scripts/player/fps_controller.gd` carry factor, `scripts/core/input_router.gd` + `project.godot` X = drop, `tests/simulation/test_scavenge.gd`, `tests/render/run_render.gd`).
- Result:
  - Loot: research drive PHP 120 / 0.2 kg, faculty laptop 150 / 2.5 kg (Kenney model), signal analyser 90 / 4 kg (radio), CRT monitor 60 / 8 kg (x2), plus a sling bag on the floor.
  - E on the crosshair takes the item looked at (one per press); a full bag leaves it; bags upgrade capacity.
  - X drops the last item in front (pulled back from walls), same instance.
  - Carry weight: free to 5 kg, then -2%/kg (floor 50%); below 75% no sprint.
  - C scanner: loot within 12 m through walls, nearest first, total value, 2 s cooldown, 4 m noise, tags shown 3 s.
  - Van loading bay at the corridor's north end: hold E 1 s to bank all loot; weapons/ammo stay.
  - Career money survives restarts; death loses carried loot and fines 10% of the bank (rounded down).
- Evidence: C `evidence/20261109-044041` (145), S `evidence/20261109-044056` (147, +27), R `evidence/20261109-044110` (16, +4; captures `fp-loot.png`, `fp-scan.png`), F `evidence/20261109-044144`; main scene 240 frames clean.
- Mutations caught: instant banking, van taking ammo, weight ignored, no scan cooldown, no death fine, drop through walls.
- Not yet: inventory screen (Tab) for choosing what to drop; money has no use until the van terminal shop (M4).

## M2 — Threat

- [x] Done 2026-11-09, split by the five-file rule: **M2a** AI (`scripts/actors/shambler.gd`, `scripts/world/navigation_grid.gd`, `scripts/world/noise_service.gd` `last_id`, `scripts/world/greybox.gd` solids + enemy spawns, `scripts/world/door.gd` `panel_aabb`) and **M2b** look/wiring/tests (`scripts/actors/outfit_builder.gd`, `scripts/ui/death_panel.gd`, `scripts/main.gd`, `scenes/player/player.tscn` collides with enemies, `tests/simulation/test_threat.gd`, `tests/render/run_render.gd`, `tests/performance/stress.gd`).
- Result:
  - Shambler (80 HP): IDLE -> INVESTIGATE (noise in radius, goes to where it was heard) -> ALERT (0.5 s grace) -> CHASE (2.6 m/s, slower than a 3.5 m/s walk; loses you after 3 s unseen) -> ATTACK (0.45 s windup, 15 HP bite only if still in reach, in front and in sight; 0.8 s recovery) ; DEAD latched (collision off, death clip).
  - Sight: 14 m, 110 deg cone, walls/closed doors/duct block; noticed within 1.5 m regardless of facing.
  - Hearing: footsteps every 0.45 s at 4 m (walk) / 9 m (sprint), none when crouched; doors 5 m; scanner 4 m.
  - Navigation: 0.25 m grid from the level's solid boxes plus door panels (analytic, no physics timing), no corner cutting, rebuilt when a door toggles; duct blocks standing walkers.
  - Death: panel takes focus; loot lost + 10% fine (M1); "Start the next night" restarts the run, `career.nights` +1, enemies back at spawn.
  - Look (Sir: no big-head models): realistic-proportion Quaternius base bodies (free edition = Superhero builds only) animated by the Universal Animation Library (same 65-bone rig: Idle, Walk, Jog_Fwd, Punch_Jab bite, Death01), grey-green skin tint, and clothes built in code from the body's own skinned mesh (polo/blouse, trousers, shoes; noise grime and sparse dried blood). Clips are speed-matched to ground speed; the bite strike lands on the gameplay commit. Previews: `docs/previews/shamblers-dressed.png`, `docs/previews/shambler-in-corridor.png`.
- Evidence: C `evidence/20261109-053103` (147), S `evidence/20261109-053119` (179, +32), R `evidence/20261109-053132` (22, +6; captures `fp-shambler*.png`), F `evidence/20261109-053155` (6 Shamblers, p95 3.03 ms at 1080p). Mutation runs `20261109-053305`..`053420` are the expected FAILs.
- Bugs found by tests: (1) each bite landed twice (30 HP): the commit window test fired on two ticks because 60 Hz timers land at 0.4499... then 0.4666...; now one commit per attack via a flag. (2) A reset Shambler re-heard old noise; resets now skip every noise id already issued.
- Mutations caught: no grace, hearing ignores radius, sight through walls, the old double-bite window, navigation ignoring doors, crouching making noise.
- Provenance fix: the old project's "Mixamo" animations were Kenney Animated Characters clips (now `assets/kenney/animations/`, unused).
- Not yet: hair (Quaternius hairstyles not imported), female skirt option, Shambler can be killed only by damage packets until weapons arrive (M5).

## M3 — Building

- [x] Done 2026-11-09, split by the five-file rule: **M3a** level (`scripts/world/greybox.gd` rewritten as data: rooms, walls, doors, furniture, desktop props, lamps, loot) and **M3b** look/tests (`scripts/render/lofi_view.gd`, `scripts/main.gd` lo-fi + grading + lamp flicker, `verify.ps1` Mobile suite, `tests/simulation/test_building.gd`, `tests/simulation/test_scavenge.gd` counts, `tests/render/run_render.gd`).
- Result:
  - Four rooms (50% MVP count): Classroom 104, east corridor, **Computer Lab 2** (8 x 6 m, two rows of workstations) and **Faculty Office** (6 x 4 m, desk, bookcases, drawers, coat rack), with three hinged doors. The office door is past the duct: the player crouches to reach it, standing Shamblers cannot.
  - Kenney furniture scaled to real size (x2), each solid piece with a box collider that also blocks enemy navigation; 33 solid pieces.
  - Look: tiled floor and ceiling textures generated in code, cream walls with a green wainscot band, whiteboard, room signs, ceiling fixtures, two flickering fluorescent lights, colour grading.
  - Lo-fi render: the world is drawn at 1/3 resolution (640x360 at 1080p) and scaled up with nearest filtering, with film grain and a vignette; the HUD stays full resolution.
  - Loot: 8 floor items now (lab laptop on a workstation, research drive on the office desk).
- Android: **blocked on this machine**: no Android SDK and no Godot export templates (Java 21 present). Covered instead by the new **Mobile** suite: the full render suite under the Mobile renderer (what Android uses), all 26 checks pass.
- Evidence: C `evidence/20261109-055259` (147), S `evidence/20261109-055307` (204, +25), R `evidence/20261109-055317` (26, +4), Mobile `evidence/20261109-055330` (26), F `evidence/20261109-055347` (4 rooms + 6 Shamblers, p95 3.7 ms; an earlier M3 run measured 2.38 ms, so run-to-run variance is about 1 ms; all far under the 16.7 ms budget). Main scene 240 frames clean. Previews: `docs/previews/computer-lab.png`, `faculty-office.png`, `classroom-104.png`.
- Layout bug found by tests: the first classroom desk layout blocked the lane to the corridor door; the right side now has one row.
- Weak test found by mutation: the lo-fi size check compared against the node's own setting, so turning lo-fi off still passed; it now checks the absolute target (<= 1/3 of the window).
- Mutations caught: duct raised, furniture not solid, lab doorway removed, lo-fi off.

## M4 — Loop

- [x] Done 2026-11-09, split by the five-file rule: **M4a** rules (`scripts/core/career.gd` cycle/quota/shop/research, `scripts/core/phone_state.gd`, `scripts/world/hack_puzzles.gd`, `scripts/world/terminal3d.gd`, `scripts/world/interactable3d.gd`) and **M4b** screens/wiring/tests (`scripts/ui/terminal_panel.gd`, `scripts/ui/phone_panel.gd`, `scripts/ui/van_panel.gd`, `scripts/ui/death_panel.gd` button text, `scripts/main.gd`, `scripts/core/input_router.gd` P = phone, `scripts/core/game_session.gd` overlays, `scripts/world/greybox.gd` spots, `tests/simulation/test_loop.gd`, `tests/simulation/test_threat.gd`, `tests/render/run_render.gd`).
- Result:
  - Two hacking terminals (50% MVP): **Lab 2 admin** (password `CCS-xxxx`, fixed per career seed, written on the Classroom 104 whiteboard) and **Faculty PC** (one of three original "which line is wrong?" grading/attendance scripts). 3 wrong answers: 15 s lockout and a 10 m alarm noise. Solving copies a research file and adds a journal entry; the lab also unlocks phone intel.
  - Research is carried like loot: delivered at the van (hold E) or when ending the night; lost on death. Chapter 01 completes when a night ends with both files delivered.
  - Phone (P): Map (rooms, visited tonight, terminals, van, player arrow; with intel also loot and living Shamblers), Journal (notes and terminal finds, unique), Hints (from the lab sticky note or the shop). Unlocks persist across nights.
  - Van terminal (E on the laptop crate in the loading bay): quota/bank/research status, shop (sling PHP 250 -> 8 slots, backpack PHP 500 -> 12, hacking hints PHP 150; never downgrades, never twice, needs funds) and "End the night".
  - Quota cycle: 3 nights per cycle; quota PHP 600, x1.5 per cycle; judged only on the cycle's last night; missing it = FIRED and a new career. Death also ends the night (counts toward the cycle).
- Evidence: C `evidence/20261109-070242` (147), S `evidence/20261109-070258` (251, +47), R `evidence/20261109-070318` (36, +10), Mobile `evidence/20261109-070345` (36), F `evidence/20261109-070428` (p95 3.7 ms). Main scene 240 frames clean. Previews: `docs/previews/terminal-office.png`, `phone-map.png`, `van-terminal.png`.
- Problems found: (1) the panels were not centred (anchors do not apply directly under a CanvasLayer); now centred on open, with a render check against the screen centre. (2) Test-setup errors of mine: the M2 death check ran on the cycle's last night and so correctly got FIRED; the Shambler I "parked" faced the player and killed them during the lockout wait.
- Mutations caught: silent lockout, case-sensitive password, research counted before the van, quota judged every night, shop ignoring funds, death keeping research. The silent-lockout case first surfaced as a script crash; the check now fails cleanly.
- Not yet: the death/night panel itself is still positioned by fixed offsets (not re-checked for centring); no audio for the alarm yet; the 2D project's "two terminal sessions" each have one puzzle, not multi-step sessions.

## M5a — Weapons

- [x] Done 2026-11-09 (M5 split: **M5a** weapons now, **M5b** the three new enemies next). Files: `scripts/combat/combat_controller.gd` (3D port of the 2D action clock), `scripts/combat/player_combat.gd`, `scripts/combat/weapon_view.gd`, `scripts/combat/hazards.gd`, `scripts/main.gd` (targets, weapon ray, effects step, equip/HUD), `scripts/actors/shambler.gd` (`alert_to`), `scripts/world/pickup3d.gd` (weapon models on the floor), `scripts/world/greybox.gd` (weapon/ammo/throwable placements), `tests/simulation/test_weapons.gd`, `tests/simulation/test_scavenge.gd` (counts from level data), `tests/render/run_render.gd`.
- Result (50% MVP weapon set, all usable in first person):
  - Melee: knife, bat, katana. Wind-up/commit/recovery from the 2D build; every living target in reach (horizontal, at body height) and arc is hit once per swing; walls block.
  - Ranged: pistol, shotgun (6 pellets for 1 shell, each pellet its own hit), assault rifle (automatic every 0.1 s, frame-rate independent). Instant rays from the eye; walls stop them; magazines live on each gun; reload moves rounds once at 80% of the reload.
  - Throwables: hold G to aim (landing marker), release to throw (leaves the hand at 0.44 s; one item used; RMB cancels before that), Q cycles. Frag: 2 s fuse, one blast, 4 m reach, 120 HP falling to 25% at the edge, walls shield, hurts everyone. Molotov: 1.6 m fire for 6 s, 8 HP per 0.5 s per body at most.
  - Dodge (Alt): 2 m along the movement input in 0.28 s, 20 endurance, 0.5 s cooldown, bite/melee immunity for 0.15 s (not fire or blast); slides along surfaces.
  - Hit Shamblers turn on the player at once. Weapons lie on the floor as their models; the HUD shows the weapon, magazine/reserve and the selected throwable.
  - Placement: bat (classroom), knife (corridor), katana and rifle (office), pistol, shotgun and frags (lab), molotovs (classroom), with 9 mm / shells / 5.56 ammo.
- Evidence: C `evidence/20261109-075105` (147), S `evidence/20261109-075112` (307, +45), R `evidence/20261109-075124` (52, +16), Mobile `evidence/20261109-075141` (52), F `evidence/20261109-075200` (p95 2.78 ms). Preview: `docs/previews/weapons-first-person.png`.
- Bugs found by tests: the molotov pickup was placed inside the potted plant; the dodge stopped at floor contact instead of sliding (now slides).
- Test-setup errors of mine corrected: shotgun fired at head height (narrowest part of the body); dodge started 1.6 m from a wall; the burning Shambler correctly walked out of the fire (fire timing now tested on a stationary dummy); the katana miss margin was smaller than the distance the noise-drawn Shambler closes during the swing.
- Mutations caught: swings through walls, bullets through walls, pellets sharing one hit id, blasts ignoring walls, fire without a rate limit, dodge without immunity.
- Not yet: first-person arms are a simple hand block (no rigged arms); the fire is a flat glowing disc; no weapon sounds; no shove.

## M5b — Enemy roster

- [x] Done 2026-11-09. Files: `scripts/actors/body_model.gd` (shared Quaternius body + clothes + clips), `scripts/actors/tracer.gd`, `scripts/actors/proctor.gd`, `scripts/actors/blackout.gd`, `scripts/world/door.gd` (`locked`), `scripts/main.gd` (lamp power, blackout schedule, night clock, staff navigation, lock/unlock, beam test, targets/rays/phone), `tests/simulation/test_roster.gd`, `tests/simulation/test_loop.gd` (Tracer parked; phone now shows the Proctor).
- Result (three original enemies, each with a learnable rule and counter):
  - **Tracer** (ceiling ducts): unseen and unhurtable up there. Standing still under a working light: scraping warning at 4 s, drop 1.5 m behind the player at 6 s, one 20 HP bite after 0.8 s (step away to dodge), climbs back, rests 20 s. 60 HP while down.
  - **Proctor** (faculty silhouette): patrols the ground floor on a fixed route with its own door-ignoring "staff" navigation, opening doors as it goes. Seeing you with research (terminal file or research drive), it follows at 3 m and locks the door nearest you (never on someone in the doorway). Never attacks, cannot be targeted. Out of sight 5 s or no research: back to patrol, its doors unlocked.
  - **Blackout**: at 9 minutes into the night the lights fail room by room every 15 s (corridor, lab, office, classroom) and it arrives in the corridor. It only moves through dark places, recoils from the flashlight beam (20 deg cone, 14 m, line of sight) for 1.5 s, strikes for 35 in the dark (0.5 s windup). 150 HP.
  - HUD night clock (22:00 + 1 night minute per 10 s). A new night restores lights and unlocks every door.
- Evidence: C `evidence/20261109-082338` (147), S `evidence/20261109-082350` (348: 307 + 31 roster + 10 viewmodel tests from the peer session), R `evidence/20261109-082416` (52), Mobile `evidence/20261109-082440` (52), F `evidence/20261109-082502` (p95 3.06 ms).
- Found by tests: the Tracer rightly drops on a player idling at a lit terminal (closing the terminal), which broke the M4 test's 15 s lockout wait; the test now parks it. Good tension for play: hack fast or in the dark.
- Mutations caught: Tracer ignoring light, Tracer never resting, Proctor ignoring research entirely, Proctor keeping doors locked, Blackout entering lit rooms, Blackout ignoring the beam. "Proctor follows anyone" alone is an equivalent mutant (it gives up on the next tick without research), noted rather than counted.
- Honesty fix: the test helper first "parked" the Proctor with set_physics_process(false), which does nothing (it runs on the session tick); a real `enabled` switch replaced it.
- Concurrent work: a peer Claude session (the ProjectZomboid/T09 one) edited this project at the same time: `scripts/combat/spring.gd`, viewmodel sway/bob in `weapon_view.gd`, `tests/simulation/test_viewmodel.gd`, `docs/fps-series-lessons.md` and one line in `run_simulation.gd`. Coordinated by message; file sets did not overlap; the combined run above is green.
- Not yet: no render/screenshot check of the three new enemies; no sounds (the scrape is a text notice); the Blackout's dark look is a plain black body.

## M6a — Slice closeout (50% MVP)

- [x] Done 2026-11-09 (M6 split: **M6a** MVP closeout now, **M6b** polish next). Files: `tests/playthrough/run_playthrough.gd` (new), `verify.ps1` (Playthrough suite live), `scripts/world/navigation_grid.gd` (`body_high` per grid), `tests/render/run_render.gd` (roster captures, grain calibration, real `distinct`), `scripts/actors/proctor.gd` / `tracer.gd` (idle pose on reset), `scripts/main.gd` (Tab lists the bag), `Launch.cmd`, `README.md`.
- Result:
  - **Playthrough suite**: a bot plays a fresh run through the real loop and input path (main drives its own physics; `--fixed-fps 60` runs it unthrottled): read the whiteboard, take the desk drive, open the classroom and lab doors, type the password into the lab terminal, take the lab laptop, crouch under the duct, open the office door, pick the right line on the faculty PC, deliver at the van, end the night -> CHAPTER 01 COMPLETE in 18.6 s of game time, alive. Enemies are parked (their rules are covered by Simulation); it proves the route and loop can be completed.
  - **First full `verify.ps1 -Suite All` PASS**: C 147, S 348, R 68, Mobile 68, Playthrough 15, F p95 1.67 ms (`evidence/20261109-094701`).
  - Roster on screen: Tracer, Proctor and Blackout captures (`docs/previews/enemy-roster.png`).
  - `Launch.cmd` (encrypted build if present, else Godot on PATH) and `README.md` (controls, what is in the slice, verify, licences, known gaps).
- **Test weakness found and fixed (important):** since M3 the lo-fi film grain changes every frame, and `distinct()` compared pixels exactly, so **every "these two captures differ" render check since M3 passed no matter what**. Now: render tests run with grain off; a calibration check proves an unchanged view captures identically and that grain animates when on; `distinct()` needs 20+ samples changing luminance by > 0.025.
- **Bugs this exposed:** (1) the Proctor stood in a **T-pose** at night start until its first tick (now starts idle; Tracer too); (2) the M2 Shambler shot was blocked by the Proctor standing at its route start, so the Shambler was not visible at all; (3) the first Proctor shot was hidden behind the open classroom door.
- Bot development found: doors must be judged a few path cells ahead; open door panels are obstacles in the bot's map; a switched-off Proctor is still a solid body in the corridor.
- **UX gap fixed:** Tab opened an invisible inventory overlay that froze movement (no inventory screen in this build); it now lists the bag as a notice.
- Mutations caught: wrong lab password check (Playthrough), office doorway walled up (Playthrough), Proctor T-pose (Render).
- Not yet (M6b): audio, camera kicks, muzzle flash, animation crossfades and random phase, story notes, inventory screen, rigged arms, death/end panel centring.

## M6b — Polish

- [x] Done 2026-11-09. Files: `scripts/audio/sfx.gd` (new), `scripts/ui/inventory_panel.gd` (new), `scripts/render/lofi_view.gd` (view-only kick), `scripts/main.gd` (sound hooks, muzzle flash, landing kick, inventory screen, drop by id, note visuals, reset of flash/fall state), `scripts/combat/player_combat.gd` (weapon/reload/hit sounds, flash), `scripts/actors/shambler.gd` / `proctor.gd` / `blackout.gd` (0.2 s animation blends, random idle phase), `scripts/world/hack_puzzles.gd` + `greybox.gd` (3 story notes), `scripts/ui/death_panel.gd` (centred), `tests/simulation/test_polish.gd`, `tests/render/run_render.gd`, `README.md`.
- Result:
  - **Sound**: 18 effects synthesised in code (footsteps, swing, pistol, shotgun, rifle, reload, door, scanner, alarm, blast, fire, throw, Tracer scrape, hit, bite, pickup, van, click), rendered once into 16-bit clips, played from a pool of 16 positional 3D voices. Driven by the same NoiseService events the AI hears, plus weapon commits, hits and player damage. Gameplay never depends on audio.
  - **Feel**: muzzle-flash light for 0.06 s on every shot; view-only camera kick on damage (scaled, max 0.12 rad) and on hard landings, applied to the lo-fi display camera only, so aim never moves; decays in about 0.5 s. Enemy animations blend over 0.2 s; idle loops start at a random point (lessons from `docs/fps-series-lessons.md`).
  - **Story**: three new journal notes, original text: corridor bulletin (classes suspended), dean's memo to Dr. Ramos (samples leave tonight; copy the research to the lab server and the office PC), Lab 2 sign-out log (Dr. Ramos never signed out).
  - **Inventory screen** (Tab): rows with slot, label, quantity or magazine/reserve and [EQUIPPED]; click/Enter equips, Drop/Delete drops in front; centred; damage and Esc close it. Replaces the M6a stopgap.
  - The death / end-of-night panel is now centred.
- Evidence: full `verify.ps1 -Suite All` PASS `evidence/20261109-095944`: C 147, S 386 (+38), R 72 (+4), Mobile 72, Playthrough 15, F p95 2.38 ms. Preview: `docs/previews/inventory-and-end-panel.png`.
- Small bug found: the muzzle-flash time survived a restart (the run clock restarts at 0); now reset with the fall state and sound log.
- Test errors of mine corrected: the sound log is scene-wide history (compare before/after, not "== 1"); checked the pistol before its 0.05 s commit; a landing test dropped the player from inside the 3 m ceiling; and I removed a check I had written that could never fail ("... or true").
- Mutations caught: kick moving the aim, silent footsteps, inventory drop deleting the item, shamblers in lockstep.
- Not done: music and voices; rigged first-person arms; the molotov fire is still a flat disc; Android export.

## Rehaul (docs/architecture-rehaul.md)

Sir chose (2026-11-09): do R0 before R1; dash = 2 charges; starting tuning = `docs/movement-reference.md` §5.

### R0 — Pivot

- [x] Done 2026-11-09.
- Retired to `reference/legacy-horror/` (with `.gdignore`): `career.gd`, `phone_state.gd`, `phone_panel.gd`, `van_panel.gd`, `tracer.gd`, `proctor.gd`, `blackout.gd`, tests `test_roster`, `test_loop`, `test_scavenge`, and the pre-R0 `main.gd`. Removed from `main.gd`: quota/shop/money/death fine, van terminal and banking, phone, scanner, carry-weight penalty, blackout lights/night clock, the three night enemies. Money loot removed from the level.
- New: `scripts/core/objectives.gd` (recover every research file by hacking, then reach the exit; restart resets the level), `scripts/core/time_service.gd` (world/player scales, eased; owned by GameSession rather than an autoload, so each test session gets a fresh one), session passes `player_dt` to the player and `world_dt` to actors and effects. The loading bay is now the EXIT. Death/complete panel: "Restart level".
- New tests: `tests/simulation/test_objectives.gd` (objectives rules, time service, terminals -> files, exit gating, pickups, restart). Playthrough rewritten: whiteboard -> lab hack -> duct -> office hack -> exit -> LEVEL COMPLETE.
- Not done in R0 (moved): the key map change happened in R1 with the movement; `design-brief.md` is marked superseded rather than rewritten (the rehaul doc is the brief).
- Evidence: full `verify.ps1 -Suite All` PASS `evidence/20261109-214646` (C 147, S 301, R/Mobile 53, Playthrough 11).

### R1 — Movement

- [x] Done 2026-11-09. Files: `scripts/player/fps_controller.gd` (state machine GROUND/AIR/DASH/SLIDE), `scripts/player/movement_tuning.gd` (new), `project.godot` + `scripts/core/input_router.gd` (key map), `scripts/combat/player_combat.gd` (Alt dodge removed, RMB = aim), `scripts/main.gd` (footstep radii), `tests/simulation/test_movement.gd` (new), `test_fps.gd`, `test_threat.gd`, `test_weapons.gd`, `test_item_instances.gd`, `tests/render/run_render.gd`, `README.md`.
- Result: run 10 m/s (Quake-style accel/friction/stop speed 10/6/3), air strafing (accel 12, cap 0.76), gravity 20, jump 7 m/s (~1.2 m), double jump 6.5 m/s (once, cancels the fall, resets on landing), coyote 0.1 s, jump buffer 0.1 s, dash 25 m/s x 0.15 s (3.75 m) with 2 charges recharging 1.2 s each and 0.1 s bite/melee i-frames, slide on Ctrl at >= 6 m/s (+2 m/s boost, friction 1, 0 downhill, max 18 m/s, 1.2 s; ends on release; slide-jump keeps speed), crouch 3 m/s (silent), ADS FOV 90 -> 65 and x0.7 speed. Footsteps: run 6 m, dash/slide 10 m, crouch silent. move_and_slide is scaled so movement honours the player's scaled delta (bullet time, R2).
- Key map: Shift dash, Ctrl slide/crouch, Space jump, RMB aim, Q bullet time (reserved), T cycle throwable; removed sprint, Alt dodge, RMB shove, C scan, P phone.
- Decision: own controller instead of the `dot_player_controller` add-on motor (1,900 lines with its own body/command layers, lightly playtested upstream; would replace the collision/crouch/duct behaviour every test relies on). The add-ons stay in `addons/`, unused, for wall-run/wall-jump reference later.
- Evidence: full `verify.ps1 -Suite All` PASS `evidence/20261109-220443`: C 141, S 322 (31 movement), R/Mobile 53, Playthrough 11 (10.3 s game time, was 18.6 s at the old walk), F p95 2.07 ms.
- Mutations caught (7/7): unlimited dashes, no slide boost, infinite double jump, no coyote time, no jump buffer, ADS at full speed, slide-jump losing speed. The jump-buffer test first passed with the buffer removed: it left fresh coyote time and a stale `is_on_floor()` from the teleport, so the press was a (correct) coyote jump. Fixed by stepping once after the teleport and then setting the air state; found by tracing ticks, after two wrong guesses.
- Render check moved closer to the Shambler: FOV 80 -> 90 made it smaller than the 20-sample "visible" threshold.
- Not yet: step height (move_and_slide has no stair stepping; greybox is flat), wall run/jump, feel playtest by Sir.

### R1.5 — Grey-box movement arena

- [x] Done 2026-11-09 (Sir: "trash the classroom and just put the player in a big and wide gray box to simulate the movements"). The campus layout is kept at `reference/legacy-horror/scripts/greybox_campus.gd`, `test_building.gd` retired beside it.
- `scripts/world/greybox.gd` rewritten: 120 x 80 m floor with a 1 m / 5 m grid, 8 m perimeter walls, spawn in the middle (60, 40) facing north. Props: slide-gap wall at z 30 (opening x 58-62, 1.25 m high), ledges 1 / 2 / 3 m, ramps 30 and 45 deg with 2 m platforms, 0.3 m stairs, 4 pillars. A small roofless lab (x 10-26, z 8-20, door in the east wall) holds both terminals and the notes; weapons in a row south of spawn; one Shambler at (60, 62); exit on the south wall. Sun light, light haze (fog 0.004), grey sky.
- `navigation_grid.gd` rebuild now marks cells per solid instead of every cell x every solid (the grid is 480 x 320 cells).
- Tests moved to arena coordinates: test_fps (slide gap replaces the duct), test_movement, test_threat (lab door, desk, gap routing), test_objectives, test_weapons (lab wall), test_polish, render shots (adds ledges and ramps), playthrough (slide gap, lab, exit), performance path. New `tests/simulation/test_arena.gd`: size, walls, spawn, dash into the wall, slide through the gap, 1 m single jump, 2 m double jump only, 3 m out of reach, both ramps walkable.
- Evidence: Content 141, Simulation 305, Render and Mobile 54, Playthrough 10 (22.6 s game time), Performance p95 2.78 ms. Mutations caught (7/7): gap 1.9 m high, 2 m ledge at 1 m, 3 m ledge at 2.2 m, max slope 40, walls 3 m (first survived: the check read the constant it mutated; now a literal), nav never solid, infinite air jumps.
- Known: the stairs cannot be walked up (no step-up; the test prints the measured height, it does not assert it). Performance exited silently once in 4 runs (no RESULT, no error, 5 s in); it passed the other 3 times.

### R1.6 — Playtest 1 fixes (Sir, 2026-11-09)

- [x] Done 2026-11-09. Feedback: double jump too low, dash a bit short, slide feels like crouching, wants Source-style strafing (Titanfall / CS2 / Apex), more obstacles, stuck on the stairs.
- Tuning: double jump 6.5 -> 8 m/s (+1.6 m; reach 2.8 m, so 3 m stays out of reach); dash 25 x 0.15 s -> 30 x 0.2 s (6 m); slide boost 2 -> 5 m/s with a 2 s cooldown, slide friction 1 -> 0.4.
- Slide: Ctrl held through a landing at speed now slides (was a crouch at 3 m/s).
- Strafing: the air-accel maths was already Quake/Source (cap 0.76, accel 12). The landing tick applied friction before a buffered jump, so every bunny hop lost about 10%; a jump on the landing tick now skips friction.
- Step-up (`_step_up`, step_height 0.35): probes the step top one radius ahead (a capsule lowered onto the edge rolled back), then moves across at that height; camera eases the rise. Ledges and the 0.6 m jump blocks still block.
- Bug found by the new dash test: the last dash tick moved at run speed (every dash was one tick short since R1). Fixed.
- Arena obstacles: 12 crates (1-2 m), 3 low cover walls (1 m), a 4-block jump course (0.6-2.4 m; 5 m blocks, 1.5 m gaps, sized for 10 m/s hops), two 6 m parallel walls 4 m apart (for wall running later).
- Evidence: full verify PASS `evidence/20261109-231431`: C 141, S 314, R/Mobile 54, Playthrough 10 (23.0 s), F p95 2.38 ms. Mutations caught (9/9): no step-up, step-up over walls, no landing slide, no boost cooldown, air cap 0, uncapped air, friction on the hop tick, dash one tick short, plus the earlier set. Three first survived: a redundant check (removed) and two tests left a stale is_on_floor() after the teleport (the strafe test was measuring coyote-time ground acceleration).
- Encrypted Windows build re-exported (`../RECompile-FPS-build/RECompile.exe`, 23:16), headless smoke run clean.
- Not yet: wall run / wall jump, Sir's second playtest.

### R1b — Source rules + Apex General Tech (movement-reference §7)

- [x] Done 2026-11-09 (Sir via the peer session: "follow movement rules from Source Engine"; dash and double jump removed to abilities; Shift = sprint).
- §7.1 Source core: tick order half gravity -> jump check -> friction -> accelerate -> move -> half gravity; air gain on the uncapped wishspeed (cap 0.76 along wishdir); bunny hop keeps 100%; clip via move_and_slide (max_slides 4); step-up 0.35; ground snap 0.35; walkable normal.y >= 0.7 (a 55 deg ramp added to the arena as the wall case).
- §7.5: walk 7, sprint 10 forward-only (±45°), toggle (default) or hold, cancelled by crouch/ADS/reload/fire/stopping; slide entry 8 m/s.
- §7.2: lurch (0.2 s, strength 1, <=10% loss), tap strafe (a new forward press inside the window restarts it), back+side = pure sideways; mantle 0.5-2.2 m in 0.45 s; mantle jump (pushes off), gorilla x1.3; superglide (last 150 ms, jump then crouch <= 1 tick, 1.5x walk/sprint, airborne); wall bounce (0.1 s window, >= 6 m/s, reflect x0.9 + jump); wall climb (4 m/s, <= 1.5 m, <= 0.4 s, once per airtime, then mantle).
- §7.4 abilities: dash_charges 0 (request_dash()), air_jumps_max 0; their tests run with the ability switched on.
- Input: action `dash` renamed `sprint` (Shift).
- Evidence: full verify PASS `evidence/20261109-234003`: C 141, S 342, R/Mobile 54, Playthrough 10, F PASS. Mutations caught 16 of 17 (survivor: the lurch window's early return, equivalent because the blend fades to 0 at the window's end). Found by tests: climb overshot its 1.5 m cap by a tick (clamped); three tests had been reading the tuning value they checked (now literal 0.7 / 45.6°); test spot sat inside a crate.
- Build re-exported 23:41, headless smoke clean.
- Gaps: superglide timing uses session ticks, not timestamped OS input events (§7.2 asks for _unhandled_input timestamps; same result at a fixed 60 Hz, differs at low frame rates); surf not done (optional); feel not yet tuned with Sir.

### R1c — Aligned to apex-study (Sir: "Rules + Apex numbers", 2026-11-10)

- Source: `C:/Users/Axxer/Documents/Codex/apex-study/movement-reconstruction.md` (community measurements, NOT extracted Apex constants), converted at 1 hu = 0.0254 m. Every tuning value is now labelled [study], [study fit], [Source] or [design] in `movement_tuning.gd`.
- Numbers: walk 4.4069, sprint 6.604, crouch 2.032 m/s; jump 7.239 m/s (1.42 m) with gravity 18.42 (fit of height 56 hu + impulse 285 hu/s; airtime 0.79 s vs the measured 0.74); coyote 0.2 s; air cap 1.524; stop speed 2.54 (Source 100 hu/s; was 3, which stopped crouch-walk reaching 2 m/s).
- Rules: slide entry ground > 5.08 m/s, landing > 2.286 across and falling > 5.08 (pre-landing speed); boost +3.81 to 10.16 the tick after entry, faster speed kept; cooldown 2 s from every entry; no slide lifetime. Lurch 0.4 s (full 0.2 s, then linear), only newly pressed keys, none above 29.2 m/s; tap-strafe restart removed. Jump fatigue (0.41 m within 0.15 s of landing from a jump, full by 0.75 s; plain falls exempt). Superglide needs sprint and slide off cooldown, crouch exactly 1 tick after the jump, 13.716 m/s total (4 up [design]), counts as a slide entry. Climb: attach facing within 45.57°, 2.54 m budget, 5.715 m/s, stall check after 1 s only when slower than 0.254 m/s, same wall again only 3.25 m below the last attach (one 128 hu baseline drop) or a wall differing by dot <= 0.9.
- Design changes: mantle_min_h 0.5 -> 0.35 = step height, so no ledge height is neither stepped nor mantled (fatigued hops on the jump course hit that gap).
- Kept as [design] (study has no equation): ground/air accel form and rates, lurch turn/loss law, mantle 0.45 s, wall bounce, slide friction.
- Evidence: full verify PASS `evidence/20261110-052906`: C 141, S 355, R/Mobile 54, Playthrough 10, F PASS. Mutations: 14 caught; 2 equivalent (superglide 2-tick and same-tick variants are already mantle jumps; the tuning-level 2-tick gap is caught). First round found 3 missing tests: cooldown checked a tick before the boost, unboosted entries restarting it, the lurch speed cutoff.
- Build re-exported, headless smoke clean.
- Not done (study scope): ziplines, mantle boost, surf/trimp/edge tech, item interactions, holster multiplier, fall stun, climb zones and the wall-jump impulse curve, raw input-frame timestamps.

### R1d — Gun handling (Sir: "Yes, add them", 2026-11-10)

- Compared our guns with apex-study weapon definitions (R-301, P2020, Mastiff, Peacekeeper, frag). Ours hit harder with bigger magazines and had no per-gun handling. Values below are ours, in proportion to those counterparts (not copied); damage, fire rate, range and recoil left for R2.
- `weapon_definition.gd`: draw_s, ads_s (aim out 0.85x), ads_move_scale, reload_empty_s, headshot_mult, spread_hip_deg / spread_ads_deg; reload_time(), spread_at().
- Values: rifle draw 0.55 / ADS 0.28 / x0.55 / head x1.4 / hip 2.5 deg / reload 2.0-2.7; pistol 0.25 / 0.16 / x0.95 / x1.5 / 3.5-0.3 deg / 1.5-1.8; shotgun 0.5 / 0.24 / x0.85 / x1.0 / 0 deg / 2.4-2.4; knife 0.2, bat 0.4, katana 0.45 draw.
- Wiring: player aim_t (linear in/out, eased FOV) with per-weapon ADS time and aimed move scale set by main each tick; draw starts on any equip change (keys, inventory screen, pickup) and blocks attack and reload; shots take a seeded random cone (hip -> ADS by aim_t; shotgun fan moves with it); head hits are the top 0.3 m of a Shambler.
- Evidence: full verify PASS `evidence/20261110-054734`: C 150, S 368, R/Mobile 54, Playthrough 10, F PASS. Mutations 9 of 10 caught at first; the survivor (cone computed but not used by real shots) is now caught by a 15 m hip-vs-aimed burst (hip misses, aimed 10/10).
- Build re-exported, headless smoke clean.
- Not yet: a draw/aim pose on the view model (draw has no animation), HUD hit/headshot markers, per-shell shotgun reload, bullet travel time, damage falloff, recoil.

### R-art — §11 art direction hooked up (peer's scripts/render/art_direction.gd, 2026-11-10)

- main._ready applies ArtDirection after the world, the view and the HUD: night grade, filmic tonemap, fog (+ volumetric on Forward+), moonlight sun 0.35, lamps sodium/fluorescent at 3.0 (<= 3 shadowed), post layer (split tone, grain, vignette).
- Fixes on hookup: the post layer was CanvasLayer 50, above the HUD (1) and panels (6, 10), so it would have tinted and grained all text; now layer 0 (world view is -1). Added a `grain` uniform + set_grain() so render captures stay deterministic. LOFI_SHRINK 3 -> 1 (full resolution, §11) and the old grain layer off; lofi_view stays for camera kicks. Lamp flicker and reset scale from the lamp's `base_energy` meta (3.0) instead of fixed 0.15/0.7.
- Render checks re-based: full-resolution view, post layer between the world and the HUD/panels, night lights. All suites PASS `evidence/20261110-060343`: C 150, S 368, R/Mobile 56, Playthrough 10; F p95 5.0 ms / p99 6.12 ms (was 2.4; budget 6.9). Layer mutation (back to 50) caught.
- Found, not caused by this change: the terminal-panel capture showed an empty column. FIXED 2026-11-10 (see below).
- Build re-exported 06:06, headless smoke clean.

### First-person arms hooked up (peer's arms_rig.gd, WRAD ARMS CC0, 2026-11-10)

- `player_combat.gd` puts an ArmsRig on the camera beside the WeaponView; `_sync_arms()` (after pose) shows it only for models with a Grip marker (pistol, rifle, shotgun, knife), hides the old hand block there, keeps the code-built bat/katana/throwables as they were. Knife one-handed (left weight 0); the support hand lets go by the reload dip.
- `weapon_view.gd`: real gun models rest at the rig's tuning hold point GUN_REST (0.12, -0.13, -0.24); code-built ones keep HIP_REST. `reload_dip` exposed.
- Tests: peer's test_arms_rig (12) registered; 4 hookup checks in test_gun_models. Full verify PASS `evidence/20261110-113131` (S 482). Mutations 4/4 caught (one first run was an invalid mutation: a dangling elif).
- Visual state (fp-weapon-*.png): hands on the guns, but rough: rifle tilted, pistol support hand and fingers distorted, right elbow low (peer's known list). Tuning is in arms_rig.gd.
- Mantle/climb hands (2026-11-10): `fps_controller.hand_contact()` gives the ledge top edge (mantle, normal up) or the wall in front of the eyes (climb, wall normal); `_sync_arms` plants both palms there with the peer's `plant_hand()` each frame and hides the gun, releases on exit. Test: mantle with the rifle out, contact on the 1 m ledge's top edge every planted tick, back on the gun after. 4/4 mutations (two test fixes needed: the first compared the contact with itself, the second took the best tick instead of the worst). S 488 PASS, build re-exported.
- Build re-exported.

### Mouse wheel and extra buttons as held actions (Sir: "Allow ability to bind mouse wheel and additional mouse buttons", 2026-11-10)

- Peer: the settings panel captures any mouse button (wheel 4/5, tilt 6/7, side 8/9+). Here: `input_router.gd` turns wheel and tilt notches into one-tick pulses (`note_event()`, fed from main's `_unhandled_input`; `down()` sees the pulse; `sample()` clears it), so a wheel-bound jump, crouch or forward fires once per notch: a forward wheel is a tap strafe (each notch is a new forward press for the lurch). Side buttons are real buttons and stay held.
- Tests (test_pause_menu): one notch = one tick, two notches in a tick = one press, forward on the wheel feeds the move vector, tilt binds, side button held. Full verify PASS `evidence/20261110-105030` (C 152, S 466). Mutations 4/4 caught. Build re-exported.

### Real gun models in the view (peer's Quaternius viewmodels, 2026-11-10)

- `weapon_view.gd` builds pistol / assault rifle / shotgun / knife from `assets/quaternius/guns/viewmodels/*.tscn` (true length, anchors); bat, katana and throwables stay code-built. The hand block stays child 0 (floor pickups drop it); real models keep true size on the floor (`pickup3d.gd`).
- ADS: the view blends by the player's aim progress to a pose that puts the Sight marker on the camera axis 0.3 m ahead (keeps 40% of the recoil kick); bob and sway x0.15 when fully aimed. The muzzle-flash light moves to the Muzzle marker.
- Tests: new test_gun_models (5) + render captures (rifle hip vs aimed). Full verify PASS `evidence/20261110-102954` (S 461, R/Mobile 65 after the capture). Mutations 4/4 caught (sight off axis, aimed bob unchanged, muzzle off the marker, floor gun oversized).
- Note: aimed, the AK receiver fills much of the lower view; the Sight anchor height is a build-tool setting (tools/build_viewmodels.gd).
- Build re-exported.

### Settings menu hookup (peer's settings.gd / pause_menu.gd / settings_panel.gd, 2026-11-10)

- GameSession owns `settings` (path "" = never saved); main sets the real path and loads `user://settings.cfg` only when it is the current scene (the game, not a test runner), so a player's file cannot change what the suites press, and tests never overwrite it.
- InputRouter: `refresh()` re-reads the InputMap on `settings.changed`; every binding slot counts (keys and mouse buttons, for held and discrete actions; `keys`/`buttons` keep the first binding).
- Player look goes through `look_from_mouse()` -> settings (hip, ADS x zoom ratio, invert Y); sprint mode copied from the setting (`apply_settings`).
- Pause menu replaces the PAUSED label: Esc opens it; Esc in Settings goes back to the menu; Resume / Restart / Quit; while the panel captures a key, Esc belongs to the capture.
- Fixes on the way: a session <-> settings lambda cycle leaked objects (now a method connection; leaks at exit down from 31 to 14, all older); Settings got an instance `path` so the session copy saves nothing under tests.
- Tests: peer's test_settings (21) registered; new test_pause_menu (17); render captures of the menu and panel with a layer check. Full verify PASS (C 151, S 455, R/Mobile 63, Playthrough 10). Hookup mutations 6/6 caught (the first look test excused headless and let one through; now tested via look_from_mouse).
- Open: `user://settings.cfg` written at 06:43 by an earlier test run has jump slot 2 = F9; Sir to decide whether to delete it. Mouse-wheel binds register for discrete actions only: a wheel bound to forward (tap strafe) needs event-driven input, not done.
- Build re-exported.

### R1e — Remaining Apex General Tech (Sir, 2026-11-10)

- Scope: every General Tech move except ziplines, superglide variants, item interactions and skydive. Spec and sources: `docs/r1e-remaining-movement.md` (wiki pages saved in apex-study; 1 hu = 0.0254 m). Skipped with reasons: wall bug, infinite climb (collision bugs), analog climb, climb lock (analog stick / unmeasured curve), slidehop heal (needs healing items).
- Existing rules changed by the pages: step height 0.5588 (22 hu); ground acceleration constant 50 m/s² for crouch/walk/sprint (fit; 40 could not beat friction at the holstered sprint); bunny-hop penalty above sprint (100 hu/s within 1 s of landing); slide jump only from a boosted slide below 350 hu/s or after 0.24 s, else deadslide; slide friction 1.3 (fit); lurch = combined held direction, per-lurch turn capped by speed (stacks); wall bounce = climb-zone jump; mantle = grab 0.45 s + pull 0.3 s.
- New: fall stun (impact along the contact normal, 300-800 hu, squared) with edge (an edge/slope contact counts as the ground), corner, climb, mantle cancels and wallhop; holster x1.15; damage slow; melee lunge + punch boost; sprint buffer 3 s; edge slide; quick slide; skip jump; ghost strafe; mantle hang/cancel/hop/boost, slide surf, auto/insta mantle, no-ma climb, clamber; climb space (baseline, zones, attach offset, cutoff, drops, reattach), mini-bounce, wallbounce, wall push, wallrun, end boost/end strafe, U-bounce baseline; surf, trimp, geo jump (Godot's grounded mover slides steep surfaces as vertical walls, so the controller clips velocity against the real plane, Source-style).
- Arena: 20.9 m drop tower + 41° ramp, 60° surf wedge (south wall), two-tier clamber block, 0.4 m curb.
- Evidence: full verify PASS `evidence/20261110-070314`: C 150, S 416 (new test_r1e.gd), R/Mobile 57 (60 with prop captures), Playthrough 10, F PASS. Mutations: 30 of 30 meaningful caught. Test bug found on the way: r1e's steps() counts ticks; arm() passed seconds (0.43 -> 0 ticks), so a swing came mid-draw.
- Supported by the rules but not scripted end to end: bounce chain, jump-fatigue wallbounce, no-ma-bounce, U-bounce (the baseline drag is tested), wall walking, lurch strafing chains, momentum shift.
- Build re-exported, headless smoke clean.

### Fix — faculty PC terminal empty on first open (2026-11-10)

- Real bug, in play since M4: the first time the faculty PC (code listing) opened, its wrapped labels measured their height at width ~0, so the panel laid out 5875 px tall from y -2398. The player saw an empty green column; the code and the answer buttons were off-screen. A re-open was fine (labels kept their width). The bot never saw it: it presses the answer button by signal. The old check passed too: a giant panel is still centred.
- Fix (`scripts/ui/terminal_panel.gd`): wrapped labels get the content width (724 px) up front; refresh() re-centres when the text changes while open. Faculty PC now 760 x 479 at y 300.
- Test: render checks the FIRST open fits on screen with the listing inside the panel. The first version checked a re-open and let the mutation through; moved to the first open, removing the fix now fails (5439 px panel at y -2180).
- Full verify PASS; build re-exported.

### Grimoire pivot P0 + P1 (Sir approved docs/pivot-grimoire-plan.md §8, 2026-11-11)

- P0 input map (plan §3): Shift dash, Ctrl crouch/slide, Space jump/double jump, LMB attack, RMB special, E/Q skill_1/skill_2, 1-3 spells, F interact, Tab grimoire, Esc, Enter. Retired: sprint, aim, reload, drop, throw, cycle_throwable, flashlight key, bullet_time, slot_4, inventory. InputRouter/Settings ACTIONS and LABELS follow; sprint toggle gone.
- P0 retirement: guns, ammo, items, inventory, bag, pickups, weapon view and their tests moved to `reference/shooter/` (with `.gdignore`), plus copies of the shooter controller, tuning, player_combat, main and the old movement tests. Session owns a StatContainer (`session.stats`) instead of an inventory; player_combat is now a casting layer (action clock + arms rig).
- P1 movement (Tech Spec §2.1): run = Mov Spd (stat, 10 base), accel 45, friction 12 with no input or above top speed; dash 20 m/s (x Mov Spd/10) decaying linearly to run over 0.25 s, 0.15 s i-frames against every damage kind (`"*"`), 1 charge / 1.2 s; slide 1.4 x Mov Spd decaying linearly to crouch speed over 1.2 s, Ctrl again cancels, 0.9 m hitbox; jump +8.5 under gravity 22, double jump +7.0 keeping the horizontal vector. Apex tech kept (D1) behind 8 `apex_*` switches; values rescaled (horizontal x1.514, vertical x1.174, heights unchanged).
- Dropped with the shooter slide model: slide boost/cooldown, deadslide, skip jump, ghost strafe, sprint buffer, holster bonus, melee lunge/punch boost. Restored after a test caught it: slide surf (Ctrl held out of a mantle boost slides on landing).
- Fixes on the way: the climb's wall probe (0.1 m) missed for one tick at the faster climb speed and dropped the player off the wall; now 0.15 m. Settings files from the shooter layout (interact on E) collided with the new E = skill_1 and logged "no default" errors for new actions: saved files now carry `[meta] layout=2`; an older file keeps the mouse settings, takes the new default binds and is rewritten.
- Tests: test_movement rewritten for the spec (shooter version kept in reference), test_r1e adapted, test_grimoire_core (peer) registered; fps/arena/objectives/polish/threat/pause/settings, render, playthrough and the content validator updated. Full verify PASS `evidence/20261111-022056`: C 91, S 365, R/Mobile 45, Playthrough 10, F PASS. Mutations 15/15 caught (2 first survived: Tab did nothing untested, and the bhop-switch check passed on a double jump; both tightened).
- Design note for the peer: a jump press in the air spends the double jump, so a press just before landing is a double jump, not a buffered bunny hop (the Source hop checks run with the double jump off).
- Build re-exported (encrypted), headless smoke clean.

### Grimoire P2 — combat core (2026-11-11)

- Sir: keep the double jump on every air press (no buffered landing hop) — unchanged.
- `scripts/combat/projectile_service.gd` (new, world-owned like hazards): fireballs sweep their path each tick (world ray + enemy capsules), detonate on first contact; one DamagePacket id per blast (dedup), flat damage to every target whose surface is within the radius and in line of sight from the blast; the page's effect (Burn) on each target hit. Basic: 45 m/s, 3.5 m AOE [spec], fizzles past 60 m. Special: 32 m/s, 7 m AOE [design], flies to the crosshair point (<= 40 m [S7]) and bursts there, also at max range.
- `player_combat.gd` is the spellcaster: equipped attack page (Scorch and Burn built in code until the PageDatabase lands: 10% / 50% Pow, Burn 5 s / 10 s, special 15 s); LMB held fires on 1 / Atk Spd with the fractional interval carried (no banking while idle); RMB special on a Spell-Mastery cooldown; MP pool (Max MP, `spend_mp` for P4 spells); no casting while mantling/climbing; casting hands (right palm out on a basic, both on a special).
- main: EffectSystem instance; Burn ticks become "fire" DamagePackets (one id per tick); enemy death clears its effects; `world_ray()`; combat targets now carry the capsule axis (a sphere at the chest missed eye-level shots); restart clears fireballs, effects, MP, cooldowns; a placeholder HUD line (MP, special cooldown) until P7.
- Tests: new test_spellcasting (31 checks: detonation rules on dummies, Burn rate/refresh/expiry through the world, Atk Spd 5 and 8, click spam, special point/cooldown/mastery 12 s, Pow scaling, MP, hands, restart); render: fireball and special burst captures. Full verify PASS `evidence/20261111-063705`: C 91, S 396, R/Mobile 50, Playthrough 10, F PASS. Mutations 17/17 caught (the crosshair-target one survived first: on a floor aim it is equivalent; a target-moved-away case now separates it).
- Placeholder visuals: unlit sphere + light per fireball, a translucent sphere at the real blast radius for 0.15 s. Enemies are still 80 HP shamblers (P3 makes them 120 HP Sprites).
- Build re-exported, smoke clean.

### Sir's answers via the peer (2026-11-11)

- Buffered bunny hop [Sir: "Yes it'll be a buffed bunnyhp"]: a jump press while falling within 0.3 m of walkable ground, or under 0.1 s to impact, waits for touchdown (`time_to_ground()`, the buffer stretched to the impact time) and becomes a ground jump with no friction tick; the double jump stays for after takeoff. Rising, or higher up, a press is the double jump. Tuning `hop_buffer_h` 0.3, `hop_buffer_s` 0.1.
- Fireballs fly at about run speed, 10 m/s (basic and special); special blast 15 x 15 m (radius 7.5).
- For later: Tab does not pause; damage applied while the Grimoire or chant panel is open force-closes it (dash-immune hits do not) — P5. EXP comes straight from kills, no orbs (peer is confirming "skills" = kills) — P3.
- Tests: 6 new hop checks (near floor, double jump after, high press, fast fall, slow fall past the 0.1 s buffer, rising press). Full verify PASS `evidence/20261111-064845`: S 402, R/Mobile 50. Mutations 6/6 new + 17/17 P2 still caught. Build re-exported, smoke clean.

- **Overruled (Sir, final: "No, keep double jump"):** the landing-hop buffer is now behind `hop_buffer_enabled` (default false): every air press spends the double jump. The buffer code and its tests stay, run with the flag on; new default checks assert there is no buffer. EXP straight from kills confirmed; fireballs fixed 10 m/s (no Mov Spd scaling) confirmed. Full verify PASS `evidence/20261111-065225` (S 404), mutations 6/6, build re-exported.

### Grimoire P3 — enemy and director (2026-11-11)

- `scripts/actors/blighted_sprite.gd` (new, from the Shambler; the Shambler moved to `reference/shooter/scripts/actors/`): Tech Spec §4 state machine IDLE_ROAM (within 4 m of its origin) -> CHASE at <= 16 m whatever its facing -> WINDUP at 1.8 m (0.35 s telegraph) -> STRIKE (12 damage if still within 2.2 m, in front, in sight) -> again every 1.2 s while in contact; past 24 m DISENGAGE back to its origin; hurt from anywhere it gives chase. 120 HP, 5.5 m/s; bare Quaternius body tinted blighted violet.
- `scripts/core/combat_director.gd` (new, AggroTracker): in combat while any Sprite is aggroed, out 10 s after the last drops (`countdown()` for Sage Arts, P4).
- Session owns `progression` (peer's Progression, recreated on restart). A Sprite's death calls `progression.on_kill()` (25 EXP, kill count, 20 kills -> Rank D +5 points +300 EXP) [Sir: no orbs]; it respawns at its spot after 12 s [design], never inside the player's 16 m aggro range.
- Greybox: six Sprite spots round the arena, each over 30 m from the player spawn. HUD (placeholder for P7): top-left "Lvl | Rank  HP", top-right "Mission: Defeat 20 enemies (n/20)" + IN COMBAT countdown; rank-up and level notices.
- Tests: test_threat rewritten for the Sprite (26 checks: roam bound, aggro 16 m, chase speed, telegraph + 12 dmg, 1.2 s cycle, dodge, disengage home, 10 s combat countdown, provoked from 30 m, kill EXP, respawn rule, 20 kills -> D, restart, overlay close, pause, death); other suites park the Sprites with `main.park_enemies(keep)` (kept ids become inert target dummies). Render: Sprite capture + skin check. Stress: the six Sprites chasing.
- Full verify PASS `evidence/20261111-230105`: C 91, S 405, R/Mobile 50, Playthrough 10, F PASS. Mutations 13/13 caught. Build re-exported, smoke clean.
- Note: the playthrough bot still runs with the Sprites parked (it cannot fight yet); a combat playthrough fits P7 with the forest.

### Grimoire P4 — abilities (2026-11-11)

- `scripts/core/page_library.gd` (new): the five MVP pages built in code with AbilityPage fields only, so the P5 swap to `data/pages/<id>.tres` is one load per page. Ability constants without a page field live with their code (orbit radius/speed, teleport distance, buff sizes, Sage rates).
- Spellcaster loadout (GDD §3.1.3): attack, skill_1 (E), skill_2 (Q), spell_1-3 (1-3), passive. `equip(slot, page)` refuses a wrong slot kind, a rank too low, the same page twice; `use_slot` checks rank, per-slot cooldown, MP (spells only). Skills ignore Spell Mastery; spells take it. `remaining(slot)` / `fraction(slot)` for the HUD. Start loadout: Scorch and Burn, Cultivate (E), Quick Step (Q, until page pickups in P5).
- Cultivate: Pow x1.10, Mastery +0.20, Atk Spd x1.15 for 10 s (modifiers refresh by id), 20 s cooldown, a hand glow. Quick Step: 5 m along the held move, normalised, forward if none; a capsule cast_motion stops it short of walls and enemies; 10 s; a flash at both ends. Ring of Fire (rank D): 30 MP, 4 orbs 90° apart on a 3 m ring at chest height following the player, 20 m/s along the ring (2x the fireball [Sir]), 15% Pow per hit, each orb re-hits an enemy at most every 0.5 s, 10 s, 15 s x Mastery. Sage Arts (rank D, passive): +3% max HP/s, +5% max MP/s only while the AggroTracker says out of combat.
- The Max HP stat now sizes the player's HP pool (clamped when it shrinks). HUD: a bottom-centre action bar `[E] … [Q] … [1] [2] [3] [P]` with cooldowns, rank locks and MP shortfalls.
- Tests: new test_abilities (35 checks); render: a Ring of Fire capture. Full verify PASS `evidence/20261111-232821`: C 91, S 440, R/Mobile 52, Playthrough 10, F PASS. Mutations 15/15 caught (the duplicate-slot mutant first left an empty `for` loop: a parse error that hung the suite, not a survivor).
- Gaps against the Codex handoff (noted, not done): projectile pool of 64 and a 3 s basic lifetime (ours fizzles at 60 m), enemy HP bars, an enemy director with an alive cap of 24, aggro needing line of sight (ours is distance-only per the Tech Spec), particles/decals.
- Build re-exported, smoke clean.

### Grimoire P5 — the Grimoire (2026-11-11; Sir: build everything here, not Codex)

- Death model [Sir R5, "knowledge is permanent"]: `scripts/core/meta_profile.gd` (unlocked pages, rank once earned, chant tiers; `user://profile.cfg` only when main is the running game, "" under tests) outlives restarts; the session rebuilds stats, progression (rank carried over) and the grimoire each run. Lost on death: level, EXP, points, loadout, kills, found-but-locked pages.
- `scripts/core/grimoire.gd`: per run found/unlocked (unlocked from the profile); `find`, `unlock` (once), `listed()` (unfound pages never shown). World pages (Greybox.PAGE_SPOTS): Quick Step, Ring of Fire, Sage Arts as glowing leaves; F picks up ("New page: ... open the Grimoire (Tab) to unlock"); a pickup shows only while its page is unfound.
- Code Assembly [Sir R2]: `data/puzzles/code_assembly.json` (from `tools/make_code_assembly_bank.py`, which ast-parses every variant): 8 topic-bound variants per page, variant 0 = the Tech Spec block shown on the page; `swap` groups mark independent lines that may come in any order. `code_assembly.gd` draws a fresh variant each attempt (never the previous one) and a shuffle that never starts solved; `code_order_validator.gd` returns {ok, wrong_indices}.
- `scripts/ui/grimoire_panel.gd` (Tab overlay, world keeps running): Grimoire tab (page list, page view with code/lesson/tip/effective cooldown, Solve to unlock -> click-pick-click-swap puzzle, Submit flags wrong lines with no penalty; correct -> unlock, +3 points, +150 EXP once; click-to-equip slots with the loadout's refusals) and Player ID (level, EXP, rank, stats, [+] allocate). Hits [Sir R1]: browsing -> closes; mid-unlock -> restarts with a fresh question, stays open; dash-immune hits do nothing.
- Start loadout each run: Scorch and Burn + Cultivate; equip now needs the page unlocked.
- Bugs caught on the way: JSON numbers load as floats, so `2 in [2.0]` failed and swap groups never matched (fixed with int()); the panel rebuilt with queue_free() alone and laid out old + new children (1284 px tall), now detached first.
- Tests: new test_grimoire (34 checks); Content: pages and banks validated (116); render: Grimoire, Code Assembly, Player ID captures. Full verify PASS `evidence/20261111-234810`: C 116, S 478, R/Mobile 57, Playthrough 10, F PASS. Mutations 15/15 caught (two first slipped past my runner as SCRIPT ERRORs, which verify fails but the runner did not count; it counts them now).
- Pending Sir (R3 unit for "+5"): stat-point value, chant reward, Reset stats (R4). Chant UI is P6.
- Build re-exported, smoke clean.

### Sir's R6-R8 (2026-11-11/12, via the peer)

- R8 Sprite: a fixed 8 m/s (Sir's correction from 10). Pounce: in CHASE at <= 10 m (> 1.8 m), in sight, off its 6 s cooldown -> CHARGE (stands 0.5 s) -> DIVE at 18 m/s up to 12 m toward where the player stood; touching the player is 20 damage (one action id per dive) and Concuss (Mov Spd and Atk Spd x0.2 for 1.5 s via `stats.add_modifier("concuss", ...)`, refresh not stack); dash i-frames dodge both. The dive speed, distance, cooldown, sight rule and 1.5 s are the peer's proposed defaults pending Sir.
- R6 cap: a pool of 20 Sprites (never more alive); the six zones start occupied; the spawner keeps 8 [design] in play, one every 4 s, only at zones over 20 m from the player; the dead go back to the pool after 12 s, so 20 kills stay reachable. Performance runs all 20 chasing: p95 5.0 ms.
- R7 audio: buses Master / Music / Ambience / SFX / UI; `scripts/audio/audio_mix.gd` synthesises a 16 s forest loop (wind, leaves, distant birds and insects, a creak) and an 8 s 120 bpm combat loop (no files to license); music fades in over 1.5 s when in combat, holds the 10 s grace, fades out over 3 s; ambience ducks to 40% under it. Settings: per-bus volumes (saved under [audio]) with sliders in the settings panel.
- Tests: pounce/concuss (8), pool/spawner (4), audio (8). Full verify PASS `evidence/20261112-000244`: C 109 (the peer archived unused asset folders), S 499, R/Mobile 57, Playthrough 10, F PASS. Mutations 16/16 caught (two first survived: the duck was only read through a helper, and spawn zones were never near the test player).
- Build re-exported, smoke clean.

### Grimoire P6 — Spell Chanting + R3/R4 (2026-11-12)

- R3 [Sir: "Flat 5"]: Max HP, Max MP and Magic Pow +5 per point or chant (PER_POINT 15/10 -> 5); Mov Spd, Atk Spd and Mastery keep their per-point values. A chant gives one point's worth, no level, no stat point (`on_chant_success` without `_level_up`; EXP may still level). `stat_container.chant_points` tracks chant gains per stat.
- R4: `stats.reset_stats()` puts every stat at base and refunds allocated points plus one point per chant gain; Player ID has Reset stats (press twice to confirm). The chant tier survives a reset.
- `scripts/core/chant_engine.gd`: tiers 1 numbers/operators (Scorch and Burn code), 2 methods/keywords (Cultivate), 3 loop syntax (Ring of Fire), 4 conditionals (Quick Step + Sage Arts); per stat tier = min(1 + level/2, what the unlocked pages allow), blanks = 1 + level%2; plateau hint past the guardrail. Problems are blanked straight out of the Code Assembly bank (so every filled problem is ast-checked Python), never inside strings, never the last attempt's; the answer check ignores whitespace and surrounding quotes, accepts equal numbers, stays case-sensitive.
- Player ID: a Chant button per stat (only at 0 unspent); wrong = fizzle, streak reset, same problem; right = +1 point's worth, EXP 60 + 5 x streak, the stat's chant tier +1 (kept in the profile across deaths); a hit mid-chant restarts it with a fresh problem.
- Tests: new test_chant (19 checks), test_grimoire_core updated for R3/R4; render: the chant view. Full verify PASS `evidence/20261112-001234`: C 109, S 522, R/Mobile 59, Playthrough 10, F PASS. Mutations 16/16 caught (two first survived: a topic check that read the engine's own table, and string literals that no bank line happened to hit).
- Build re-exported, smoke clean.

- **R9 (Sir, supersedes the chant parts of R3):** a chant gives no EXP at all, no level, no stat point; its gain is a flat `CHANT_GAIN` per stat (HP +5, MP +5, Pow +3, Mov Spd +2, Atk Spd +2, Mastery +0.5%), stored as `chant_points` and added after the points, capped; a capped stat refuses the chant before it starts. Player ID: one [+] per stat (spends a point; with none it starts a Spell Chant); the Chant buttons are gone. Reset still turns each chant into 1 point. Full verify PASS `evidence/20261112-003550` (S 525); mutations 6/7 (the survivor, dropping the cap inside base_value, is equivalent: value() caps again). The peer flagged to Sir that +2 Mov/Atk Spd per chant reaches the caps in a few chants (constants, easy to retune).

- **R10 (Sir, "go with recommended"; replaces the R9 gains):** chant gain = CHANT_GAIN x TIER_MULT[the chant's tier] (HP/MP/Pow 5, Mov Spd 0.4, Atk Spd 0.25, Mastery 1.5%; x1.0/1.15/1.3/1.5), accumulated per stat in `chant_gain` so each chant keeps its own tier's gain; 30 tier-1 chants take Mov Spd from 10 to its 22 cap. Full verify PASS `evidence/20261112-004113` (S 527); mutations 6/6.
- **Blocked: export.** The Godot export templates folder (`%APPDATA%/Godot/export_templates/4.7.2.stable/`) disappeared between 00:37 and 00:41; the encrypted export now fails with "No export template found". Not deleted by this session; asked the peer. The last good build (R9 state, 00:37) is in RECompile-FPS-build. Re-installing the templates is a download: waiting for Sir.

Next: **P7 — HUD bars, Dark Forest (replaces the campus/lab; archive kenney/furniture), tuning, a full-loop playthrough.**

## MVP close-out (2026-11-13): GDD §6.1 "What Done Looks Like"

Against `RE_Compile_GDD.md` §6.1, in the Dark Forest build. Evidence = the test that proves it.

| GDD §6.1 row | Status | Notes / evidence |
|---|---|---|
| Movement: run, dash, crouch, slide, jump, double jump | Done | Plus the Apex tech set and R13 ledge rules (hang, shimmy, Shift superglide). `test_movement`, `test_r1e`, `test_r13` |
| Basic & Special Attack: Scorch and Burn, AOE, Burn refresh; special cooldown indicator | Done | RMB tile on the action bar shows the special's cooldown (R12). Fireball trail, blast burst, scorch mark, larger special blast (VFX). `test_spellcasting`, `test_hud`, `test_vfx` |
| Skill pre-equipped (Cultivate) with cooldown indicator | Done | [E] tile sweep + seconds; Cultivate hand embers. `test_abilities`, `test_hud` |
| Obtainable skill (Quick Step): pickup + code puzzle | Done | Flash at both ends (pooled). `test_grimoire`, Playthrough |
| Obtainable spell (Ring of Fire, rank D): pickup + puzzle | Done | 6 orbs, Scorched Slow, glowing pooled orbs. `test_abilities`, Playthrough |
| Obtainable passive (Sage Arts, rank D): pickup + puzzle | Done | 3% HP / 5% MP per s out of combat (3 s grace). `test_abilities`, Playthrough |
| Hostile entity: aggro, damage, EXP on death, mission kills; HP bar | Done | Blighted Sprite: LOS aggro, 3D melee, ballistic pounce, climbing, HP bar, effect icons, Burn embers. `test_threat`, `test_r12` |
| Grimoire: browse, unlock, equip; solved pages show name, description, code, explanation, hints | Done | Book UI: loadout page, Table of Contents with search, one ability per page with live numbers. `test_grimoire`, `test_book_card` |
| Player ID: all stats, update when points are spent | Done | Academy ID card: front records, back stats with [+] and chant tiers, Reset. `test_book_card`, `test_chant` |
| Spell Chanting: fill-in-the-blank, progressive, Grimoire-correlated, guardrail | Done | Syntax-only blanks, hint after 10 s, scrollable question, survives a Grimoire visit. `test_chant`, `test_book_card` |
| Leveling: EXP from all 4 sources; level-up points; level-up notification | Done, by ruling | 3 sources (kill, page unlock, rank up): Sir's R9 removed chant EXP on purpose. Level/rank banner (R15). `test_grimoire_core`, `test_r15` |
| Adventurer Rank: E -> D on 20 kills, points, rank gates; mission tracker | Done | Rank banner; rank kept across deaths (R5). `test_threat`, Playthrough |
| HUD: player info, action bar, mission tracker | Done | Bars, status icons, LMB..RMB bar, notices, banner, Effects on T. `test_hud`, `test_r14` |
| §6.2 content: 5 pages, 1 enemy type, rank cap D, 1 region | Done | Dark Forest, seeded per run (R11), 1,000 seeds valid |
| Full loop (Playthrough) | Done | New game -> Quick Step -> 20 live kills, rank D -> Ring + Sage -> chant (no EXP) -> Reset refund -> death (R5 split) -> camp respawn, new forest. 24 checks |
| Death and respawn | Done | Panel lists lost/kept; full HP/MP at camp; new seed; overlays and effects cleared. `test_forest`, Playthrough |

### Gaps and open items

| Item | State |
|---|---|
| Performance budget (p95 <= 7.7 ms, real clock) | **Passed 7.57 ms on a quiet machine (2026-11-13 20:38).** The stress test now times frames with Time.get_ticks_usec: Godot delta smoothing had snapped every reading to refresh intervals (p95 stuck at 6.94). Sir set the budget to 7.7 ms on the real clock (was 6.9 on the smoothed delta). Costs (real clock, p95): grass at 25 m ~0.9 ms, Binbun effects ~0.5 ms, Nature-kit models ~1.6 ms. |
| Institutional logos (WMMA seal, House of the Pythons crest) | Re-lettered marks from WMSU / CCS images; permission to be confirmed before any public release (ledgered). |
| Akami icons | CC0, but the source page discloses AI-assisted art; note for release. |
| Balance | A dodging bot still died on ~2 of 12 random forests when 3-4 Sprites converged (before the R12 pounce changes); worth a playtest pass. |
| Render flake | One run had a 1-sample difference in the grain-off check; two reruns clean. Watch. |

### Performance close-out (2026-11-13)

| Run | p50 | p95 | Load |
|---|---|---|---|
| Before VFX (2026-11-12 11:01) | 4.55 | 6.69 | quiet |
| VFX off, today | 4.55 | 6.38 / 7.14 | 1-7% |
| VFX on, before trims | 5.56 | 7.58 | 5% |
| Trim 1: volumetric fog 64 -> 48 | 5.49 | 7.31 | 8-35% |
| Trim 2: campfire shadow off | 5.0 | 7.58 | 22% |
| Trim 3: bursts 6/12, pools 6, scorches 6 | 5.0 | 6.25 / 7.58 / 7.43 / 6.94 / 7.41 | 5-32% |

Run-to-run noise is about ±0.6 ms at p95; even with the VFX off the scene sits on the 6.9 ms line. Open for Sir: accept, or trim further (the 64 per-fireball lights are the biggest GPU item, pre-existing).
