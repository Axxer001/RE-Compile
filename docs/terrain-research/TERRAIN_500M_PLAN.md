# RE:Compile — 500 m terrain and 200-plus hostile plan

> Execution update: [first three task results](FIRST_THREE_RESULTS.md). The 20–300 active-hostile count sweep, projectile prewarming and final-position spawn validation are implemented. All 18 dense-combat captures are valid but exceed the frame budget. T01 remains open for finer physics/residency instrumentation and other workloads; the 500 m / 250-active target is not achieved.

Prepared: 2026-11-14. Status: implementation queue; no gameplay changes made by this document.

## Goal and acceptance contract

Expand the Dark Forest from **150 × 150 m to 500 × 500 m**, improve nature placement, create distinct areas within one forest identity, add playable hills, improve hostile placement/behavior, and support **more than 200 hostiles** while preserving performance and gameplay.

The map grows from 22,500 to 250,000 square metres: **11.11 times the area**. Enlarging constants and multiplying object counts will not establish the requested result. Preserve local vegetation density, encounter richness, visibility settings and gameplay responsiveness; make the work performed near the player bounded where appropriate.

Treat hostile capacity as two independent requirements:

1. **World population:** at least 250 living hostile records distributed across the map, with correct activation, movement/state retention and encounter availability.
2. **Active combat:** at least 250 simultaneously active hostiles, including a concentrated chase/combat scenario. Sleeping or reserved actors do not count toward this test. Also measure 50, 100, 200 and 300 to expose the scaling curve.

250 is the proposed first acceptance workload, not a replacement for the user's open-ended capacity goal. A world-population PASS must never be presented as an active-combat PASS. If the hardware cannot meet the active-combat target, report the measured limit and remaining cost rather than quietly lowering AI fidelity, enemy counts or visual quality.

**Performance acceptance:** retain the existing 7.7 ms p95 frame target on the recorded reference machine/settings. Compare at least three sequential trials for each before/after case and report variation, p99/max, simulation cost, generation/load time, memory and content counts. “Without losing performance” means meeting that budget and showing no repeatable regression beyond baseline trial variation at matched workload/settings. The enlarged-content tests must independently pass; matched-content microbenchmarks alone are insufficient. Record cold startup separately from warm generation. Keep the existing 200 ms generation/build test's actual scope intact; report full time-to-playable separately. Do not silently revise thresholds.

## Current project evidence — use the latest results

Read [completed performance work](../queued-performance-2026-11-14.md) before the older [queue](../QUEUED_PERFORMANCE_WORK.md). The older queue still lists work subsequently completed.

- The project already has separate data generation, validation and scatter/build stages, bounded retries, failure handling, tree MultiMeshes, tree impostors, nearby grass generation, an enemy reserve pool and projectile/VFX pooling. Extend these rather than introducing duplicate systems.
- Navigation rebuild optimization is already applied. The later report records 19 equivalence cases with zero mismatches.
- Casting's 100 m capsule query has already been optimized and checked against 4,000 randomized reference segments. Do not queue this fix again. Reported normal-combat p95 after the fix: **6.86 / 7.20 / 6.70 ms**, with **20 live enemies**, not 200.
- Chronological frame CSVs, warmed counters, capture-versus-budget reporting and profiling-copy consistency checks are already implemented.
- Later verification reports Content 131 and Simulation 687 checks passing. These are historical results, not newly rerun tests or fixed future expected counts. Audio shutdown leaks were fixed. Vendor UID warnings remain documented.
- Warm generation CPU total was 114–135 ms; scatter took 59–67 ms, the largest measured stage. This points toward object construction/scatter investigation before speculative worker scheduling.
- Remaining recorded issues include first-cast visual allocation spikes up to 25 ms, overloaded detonation effects, traversal sensitivity to machine load, and vendor UID references.

### Code constraints that expansion must address

| Area | Observed implementation | Consequence |
|---|---|---|
| Layout | `scripts/world/dark_forest.gd`: SIZE/BOUNDS 150 m; fixed clearing/path coordinates; six zones; jittered tree grid; clearing-based rocks | Map size is not a single safe constant edit; topology and content must fill the expanded bounds meaningfully |
| Ground | Page/zone positions, tree/rock placement and grass transforms commonly use y=0 | Hills require consistent ground sampling for visuals, collision, pickups and actors |
| Navigation | `navigation_grid.gd`: 0.25 m cells, y=0 path centres and absolute vertical obstacle filtering | 600×600 becomes 2000×2000: 360,000 to 4,000,000 cells per grid; two grids total 8,000,000 cells, before overhead |
| Climbing | `main.gd::_rebuild_navs` filters obstacles using absolute `box.end.y` against CLIMB_MAX | Elevated ground would be misclassified unless climbability is measured relative to local ground |
| Vegetation | Trees already use 10 m render groups/visibility ranges; grass uses 8 m chunks and four new chunks per update budget | Render grouping already exists; it is not equivalent to bounded residency of world collision or navigation |
| Grass residency | `grass_field.gd::update` hides distant chunks but retains them in `chunks` for the run, and visits that dictionary | Long traversal can increase retained memory and cache-iteration work; bound and measure residency |
| Enemy capacity | `main.gd`: MAX_ALIVE=20, TARGET_ALIVE=8; actor loop visits the pool; reserve actors return early inside tick | 250 active actors requires workload, AI, physics, animation and rendering changes, not just a spawn-count increase |
| Spawn placement | `_free_zone` filters by player distance; `_respawn` then adds ±2 m jitter without a final placement check there | Validate the final candidate against ground, clearance, navigation and occupancy; zone validity alone is insufficient |
| AI | `blighted_sprite.gd::_walk_to` replans when path is empty or its timer expires | Failed paths can be requested repeatedly while empty; profile and add bounded retries with correct invalidation |
| Player movement | `fps_controller.gd` already handles slope normals, ground snap, steps, slide, mantle and climb | Preserve those systems; test terrain against movement tuning rather than flattening or replacing player behavior |

## Source study: findings worth applying

**Evidence levels:** observed means read in the installed artifact; proposed means an independent project adaptation; measured means a recorded project benchmark. These labels are not interchangeable.

Primary local reports:

- [DST mechanism study](C:/Users/Axxer/Documents/Codex/terrain-study/DST-MECHANISMS-2026-11-14.md)
- [Initial artifact findings](C:/Users/Axxer/Documents/Codex/terrain-study/FINDINGS-2026-11-14.md)
- [46-file source verification](C:/Users/Axxer/Documents/Codex/terrain-study/dst-source-verification-2026-11-14.json)
- [C2ME replacement metadata](C:/Users/Axxer/Documents/Codex/terrain-study/c2me-recheck-2026-11-14.json)

DST references below are relative to `terrain-study/dst-scripts/scripts/`, from installed build **761239**. The source report records the original archive hash. Keep commercial scripts outside the Godot export tree; independently implement ideas, not copied game code/assets.

| Source-backed finding | Project application | Limits and checks |
|---|---|---|
| `worldgen_main.lua:401,418`: task/set-piece selection followed by bounded five-attempt generation, reset on failure and nil on exhaustion | Keep the existing validated-generation contract; add chunk-job cancellation/cleanup when applicable and retain the playable previous map on failure | Already partly implemented. Do not copy DST's retry count blindly or publish partially invalid terrain |
| `storygen.lua:86`, `forest_map.lua:495,842`: topology precedes geometry and population passes | Generate connected playable areas and reserved routes before nature decoration; separate data preparation from scene construction | WorldSim/Voronoi internals were not reconstructed; no evidence for adopting that native algorithm |
| `tasks/forest.lua` and `storygen.lua:501-627`: lock/key metadata informs task attachment and branching | Give areas gameplay roles and connect objectives intentionally | LinkNodesByKeys has a random-task fallback at :596. Explicit final reachability tests are still required |
| `rooms/forest/spider.lua`: authored room recipes combine counted resources/dens, weighted nature and growth-stage data | Use forest-area recipes combining vegetation, rocks, a landmark/structure, reward and threat-source rules | Relative weights are not guaranteed counts; placed hostile sources are not live hostile population |
| `childspawner.lua:196-258`: conditional regeneration/release work, ordinary periodic bookkeeping at 5–10 seconds, idle task cancellation | Schedule reserve regeneration/spawn eligibility only when needed; spread source updates over time | This is population bookkeeping, **not** a recommendation to update combat AI once every 5–10 seconds |
| `childspawner.lua:579-601,717-728`: wake/offscreen gating, queued spawn and source validity/capacity checks | Preserve dormant source state, wake with hysteresis, validate a final spawn before materializing an actor | Do not use camera visibility alone for simulation activation; threats behind the player still matter |
| `spiderden.lua:146,449-460,535-550,736`: capacity/stage/timer configuration and day/freeze gates | Data-driven encounter caps, cooldowns and source-specific eligibility | Destruction can release remaining inhabitants (:326); budget exceptional bursts as well as normal release |
| `childspawner.lua:332-378,407,483`: inside counts, outside references, flags and timers saved, ownership restored in a post-load pass | Keep stable IDs and explicit reserve/active ownership when unloading/reactivating areas | Full persistent-world saves are not a prerequisite. Run restart, unload and duplicate-activation tests are required |
| `childspawner.lua:819`: LongUpdate forwards elapsed time; OnUpdate is not a missed-interval replay loop | Define a bounded dormant catch-up policy deliberately | Do not claim exact offline replay; avoid thousands of queued spawns after a long absence |
| `lootdropper.lua:99,186,415`: weighted draws, chance/fixed/fallback loot and event-time spawning | Separate required rewards from optional rolls; roll on a specified event and track consumed state | No exactly-once or persistence guarantee follows from lootdropper alone |
| `spiderden.lua:181,197,213,337`; `spider.lua:645-650`; `SGspider.lua:126`; `entityscript.lua:2181`: loot owned by specific entities/death events, including corpse-storage branch | Keep reward ownership attached to the encounter/entity, not visual chunk recreation | Spider weights are not independent probabilities. Corpse persistence/duplicate prevention was not fully audited |
| C2ME root/nested metadata exposes scheduling, chunk rewrite, serialization and lighting modules | Treat job scheduling and preparation as later targeted research questions | Class names do not establish algorithms, thread safety, queue limits or speedups. No method-level scheduler reconstruction completed |
| Replacement C2ME 0.4 matches the three OpenCL-required module versions | Earlier 0.3.6-versus-0.4 mismatch is resolved at metadata level | Java 25+ for OpenCL and loader >=0.18.3 still need runtime verification; no Minecraft performance result exists |
| Other installed mods were inventoried, including Sodium/Lithium and generation/lighting mods | Study a particular exact-version subsystem only when it answers a measured project problem | No source-backed Sodium/Lithium rendering or AI optimization should be claimed from inventory alone |

**Main lesson:** retain a rich world through structured placement and explicit population state, while bounding expensive active work. DST's source shows mechanisms, not proof that these mechanisms achieve RE:Compile's frame budget.

## Terrain and local identity design

Use several **area profiles within the same forest**, initially: dense pine grove, deadwood hollow, rocky rise, open fern clearing, and ruined campsite. These are proposed art/gameplay profiles, not new biome systems or required new asset packs. Vary existing tree ratios/scale, cluster spacing, rock groups, grass density, ground tint, elevation and landmarks. Blend profiles across boundaries; avoid repeated rectangular patches and identical encounter arrangements.

Placement order:

1. Pick a deterministic area/route graph with the camp, required page objectives and encounter locations.
2. Produce low-frequency terrain heights and flatten/blend safe camp, structure footprints and required approach routes.
3. Validate slope, route widths, entrances, connectivity and reachable objectives for the appropriate agent capabilities.
4. Place guaranteed structures/resources/threat sources with bounded attempts and explicit failure reasons.
5. Decorate using clustered density fields and minimum spacing. Use a local placement grid for neighbor checks if measurements justify it. Preserve corridor clearances and silhouettes.
6. Build/render nearby data within a measured budget; activate collision/navigation before the player or enemies can enter an area.

Use a stable seed split by map version, spatial cell and feature type. Adding a decorative rock should not reroll all rewards or hostile sources. Record the generator version and seed. Adjacent cells must agree on edge samples and spacing; generation order must not change their content. Start with existing assets and a small recipe set, then judge distinctness through screenshots and playthroughs.

## Hills without breaking gameplay

Start with a bounded heightfield: no caves, overhangs or stacked walkable floors in the first slice. One ground sample/normal definition must drive terrain mesh, collision, vegetation roots, structure grounding, pages, spawn positions and navigation. Ground collision stays authoritative; sampled visual heights must agree with it.

Read slope, step, mantle and climbing limits from current tuning. Keep mandatory routes within supported limits, provide walkable alternatives to optional climb challenges, and preserve the existing 1/2/3 m mantle-course intent. Do not solve traversal failures by raising movement limits globally.

Replace absolute-height obstacle/climb assumptions with local clearance and traversable edge rules. A path is valid only if each edge satisfies height/slope/collision limits, not merely because its XZ cells are free. Test player and hostile capabilities separately. Heightfield navigation is a candidate; compare it with a small region/portal graph plus local pathfinding before committing to a whole-map replacement. Bridges/stacked floors would require a later representation change.

Test uphill/downhill movement, steps, ground snap, dash, slide, mantle, fall damage, landing effects, enemy climbing/pounce/vertical melee reach, projectile ground impact, AoE vertical range, grass grounding and pickups. Include chunk seams, steep boundaries, high-speed crossing and teleport/reset paths.

## Scaling strategy

**Rendering:** retain current tree MultiMeshes/impostors and grass settings. Use spatially bounded batches and measured residency; do not assume smaller chunks always win. Tree-render groups, terrain tiles, collision regions, navigation regions and encounter areas need not share a size. Benchmark candidate region sizes instead of imposing one global CHUNK constant.

**Residency:** first cap grass residency because it already builds deterministically on demand. Then measure tree/collision residency at enlarged bounds. Use a retention margin to avoid rebuild thrashing. Never unload geometry needed by active projectiles, actors, encounters or an imminent high-speed crossing. Queued work must be invalidated on map replacement so stale nodes cannot enter the new world.

**Navigation:** avoid blindly allocating two 4-million-cell global grids. Prototype local fine grids connected by an area/portal graph, or a height-aware alternative, against the existing pathfinder on a small controlled slice. Preserve no-corner-cutting, collision clearance, reachable objectives and climb rules. Compare path correctness and memory before selecting it. Stagger/budget expensive path requests, maintain usable existing paths, and prioritize nearby threats. Shared routes/flow fields are conditional experiments for common-goal crowds, not a requirement before profiling.

**Hostiles:** keep reserve and active state separate, use distance/state hysteresis and stagger perception/path decisions. Full-rate motion, hit detection, committed attacks and active effects remain responsive. Do not sleep aggroed, nearby, airborne or recently damaged enemies simply because they are offscreen. Establish a maximum perception/replan delay and assert it. Test 250 active actors without counting reserve records as active.

**Combat queries:** the capsule-query fix already exists. If 250 actors expose linear target enumeration as a cost, add a shared spatial candidate query used consistently by targeting, projectiles, AoE and spawn occupancy. Compare results to brute force, including high-speed segments and large radii. Do not add it without an actual scaling profile.

**Allocation:** prewarm existing projectile visuals during controlled loading, then measure first cast and loading cost. Reuse current pools; do not create a generic pooling framework. Profile active enemy animation, health/status UI, physics, effects and draw cost separately before considering lower-detail presentation.

## Work I can apply now

These are implementation-ready tasks, not claims that they have been applied in this planning turn:

| Priority | Work | Files / scope | Verification and risk |
|---|---|---|---|
| 1 | Extend the existing benchmark to map size and live-hostile sweeps, with subsystem counters | `tests/performance/baseline.gd`, profiling runner, `scripts/main.gd` test setup | Count actual active/aggroed/reserve actors throughout samples; preserve normal gameplay defaults and saving isolation |
| 2 | Prewarm the existing projectile visual pool during loading | `scripts/combat/projectile_service.gd`, main loading setup | Compare cold first cast and load time; reset counters; no phantom projectiles, lights or damage |
| 3 | Validate final jittered spawn positions | `main.gd::_respawn/_free_zone`, relevant simulation tests | Capsule clearance, terrain support, navigation, safe distance and occupancy after jitter; bounded retries defer safely when no location works |
| 4 | Add failed-path retry backoff and stagger replans | `actors/blighted_sprite.gd`, AI tests | Retry when nav revision/goal meaningfully changes; no per-tick failed query storm, starvation or delayed committed attacks |
| 5 | Bound grass cache residency using existing deterministic rebuilds | `world/grass_field.gd`, grass/traversal tests | Full-map traversal shows bounded resident chunks/memory; revisit reproduces placement with no visible holes or repeated churn |
| 6 | Prototype one forest-area recipe on the current 150 m map | `world/dark_forest.gd`, `tests/simulation/test_forest.gd` | Different local identity with unchanged required pages/routes and nature/threat counts; captures and fixed-seed checks |

The first three are the recommended immediate batch: capture the scaling limit, remove the known allocation hitch, and close the final-spawn validation gap. The failed-path and grass changes are also grounded in current code, but their performance benefit must be measured. Do not present any as sufficient to guarantee 500 m or 250-active-hostile performance.

## Ordered implementation queue

Use this checklist for the new terrain work; do not replace the legacy `tasks/todo.md` milestones. Re-read callers and current source before each implementation. Preserve existing working changes.

- [ ] **T01 — Capture current scaling.** Extend existing runner with live-count history, actor/path/LOS/physics/presentation timings and resident chunk counts. Run 20/50/100/200/250/300 active-hostile scenarios at current size. Dependencies: none. Gate: intended workload really runs; failures and bottlenecks are recorded.
- [x] **T02 — Prewarm projectile visuals.** Reuse pool and loading path; compare first-cast spikes and startup. Dependencies: T01 capture support. Gate: unchanged gameplay, bounded added memory, no first-use allocation for the warmed workload.
- [x] **T03 — Make spawn candidates valid.** Validate after jitter, keep safe distance, defer with bounded retries when full/blocked. Dependencies: none. Gate: dense obstacles, occupied zones, no-space and map restart tests pass without spawn loss/overlap.
- [ ] **T04 — Bound path-request work.** Add failed-path retry/invalidation and stagger ordinary replans; profile before broader pathfinding changes. Dependencies: T01. Gate: unreachable goals do not trigger per-tick requests; newly reachable goals recover; combat response remains within an explicit bound.
- [ ] **T05 — Bound grass residency.** Add eviction/retention to the existing cache. Dependencies: T01. Gate: memory/chunk count plateaus over repeated traversal; same seed/cell rebuild matches; reset cancels obsolete work.
- [ ] **T06 — Ship one distinctive encounter-area slice.** Use current map/assets for nature + landmark/structure + threat + reachable reward, with guaranteed placements before decoration. Dependencies: T03. Gate: fixed-seed tests, route validation, visual acceptance and unchanged mission accessibility. Reuse page rewards unless a different reward has an explicit gameplay specification.
- [ ] **T07 — Ship one hilly area slice.** Add shared ground sampling and matching mesh/collision; ground its content. Dependencies: T06. Gate: full movement/combat regression on slopes/seams, safe start and required routes.
- [ ] **T08 — Make navigation height-aware and bounded.** Prototype regional/local pathfinding with cross-region connections; replace absolute-height climb filtering. Dependencies: T04,T07. Gate: path/clearance/climb equivalence on flat maps, valid height edges on hills, recorded memory and path latency. T07 remains a test slice until this gate passes.
- [ ] **T09 — Expand to 250 m, then 500 m.** Extend topology and recipes, then add bounded scene/collision construction only where profiles require it. Dependencies: T05,T06,T08. Gate at each size: populated coverage, safe routes, deterministic edges, fast crossing, cancellation and no unloaded-ground falls. Stop expansion to fix regressions before the next size.
- [ ] **T10 — Support 250 distributed hostiles.** Extend existing pool/state ownership and region activation with hysteresis and source cooldowns. Dependencies: T03,T09. Gate: counts conserved over activation, deaths, rewards, restart and revisits; dormant counts are labelled separately.
- [ ] **T11 — Meet 250 active-hostile combat target.** Profile the actual active crowd; optimize only dominant actor, physics, query, animation or effects costs. Dependencies: T01,T04,T10. Gate: same attack/motion rules, actual 250-active workload, no hidden sleep/count substitution and frame budget met. Split any cross-system implementation into independently verified changes.
- [ ] **T12 — Full acceptance and evidence.** Dependencies: all earlier tasks. Run generation/loading, full-map traversal and normal-rate dense combat sequentially; label projectile saturation separately. Run Content, Simulation, Render and applicable performance checks, update evidence/plan and export only when part of the requested implementation delivery.

## Required acceptance matrix

| Test group | Cases / evidence |
|---|---|
| Generation | Existing known seeds 60, 7, 4242, 123, 999 plus at least 100 deterministic seeds at each size; explicit retry-exhaustion and invalid-layout tests; same-version replay and shuffled region-generation order |
| Content | Per-area and whole-map nature/structure/reward/threat counts; spacing, overlap, slope eligibility, safe camp, entrances and paths; reject missing required objectives |
| Distinctness | Captures of each area profile, transitions, hilltops/hollows and landmarks; visually distinct composition within one forest, no abrupt seams or obvious placement grid |
| Navigation/movement | All required objectives and zones reachable by the intended agent; obstacle boundaries, diagonal corners, local heights, climb limits, route invalidation and cross-region paths; current movement suite retained |
| Hostile lifecycle | 250 world population, 250 active combat, 300 stress; wake/sleep, aggro, behind-camera threats, concurrent source releases, blocked spawn, death/respawn and restart; count/ID conservation |
| Rewards/combat | No duplicated reward on region revisit or repeated death callback; fixed/random distinction; projectile and AoE comparison against reference candidates; vertical attacks and effects remain correct |
| Residency | Traverse all 500 m bounds and revisit; resident memory plateau after steady state, no stale job results, collision before entry, deterministic rebuild, no missing trees/grass seams |
| Performance | Three sequential trials minimum; cold start and warm generation separate; baseline-equivalent quality; p50/p95/p99/max, ticks, casts, live/active/reserve history, path requests/latency, physics, rendering, allocations and process memory |
| Long-run behavior | At least one 10-minute full-map traversal/combat soak after functional gates; no rising resident memory trend or actor/reward duplication; longer run if the retention policy has a longer cycle |

Reference setup from latest report: Ryzen 5 6600H / RTX 2050, Godot 4.7.2 Forward+, internal 640×360, recorded viewport/window settings, grass 25 m, AC power, Vsync off. Re-record actual settings and background load at execution. Do not compare different visual quality or thermally constrained runs as if controlled.

## Deferred work and honest limits

No infinite world, voxel rewrite, multiplayer conversion, new save architecture, universal job framework or new dependency is required. Worker threads remain a conditional experiment for measured pure-data preparation; scene/physics publication must respect engine thread constraints verified at implementation time. Rendering/culling is not a substitute for gameplay lifecycle handling.

The Minecraft study established package architecture/dependencies, not usable decompiled optimization algorithms. DST supplied readable generation/population/loot mechanisms, not native renderer or WorldSim internals. Neither game has supplied runtime benchmark proof in this study. A 500 m map with 250 active hostiles remains a target to demonstrate on the user's hardware, not a performance guarantee already earned.
