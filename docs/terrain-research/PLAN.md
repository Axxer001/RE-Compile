# Minecraft Java + Don't Starve Together → RE:Compile terrain research plan

Prepared: 2026-11-14, Asia/Manila. Status: planned; no game benchmark or source audit completed by this document.

## Objective and scope

Study Minecraft Java, selected mods, and Don't Starve Together (DST) to improve RE:Compile's procedural environments without losing hostile populations, vegetation, structures, loot, accessibility, or predictable performance. Turn findings into independently implemented Godot/GDScript changes, supported by before/after evidence.

“Modes” is interpreted as mods; benchmark game modes are specified below too. The target is the existing finite 150×150 m Dark Forest, not a Minecraft clone, voxel engine, engine migration, multiplayer rewrite, or infinite world. Study streaming only if future measured map requirements justify it. New structures and loot are proposed content work; first confirm how they fit the current Grimoire design. Existing page pickups must remain usable.

Project: `C:\Users\Axxer\Documents\Codex\2026-11-08\how\outputs\RECompile-FPS`
Archive: `C:\Users\Axxer\Downloads\Don't Starve Together.rar`
Minecraft access: user reports Java through SKlauncher; actual version/profile path must be discovered before choosing mod versions. Do not assume launcher availability proves a runnable game or any particular authentication state.

This is a queue document, not an instruction to run the archive, install mods, or modify gameplay immediately.

## Established facts versus hypotheses

Established locally:
- DST archive exists, 3,504,011,295 bytes. A read-only `tar -tf` listing found `bin64/dontstarve_steam_x64.exe`, `bin64/dontstarve_dedicated_server_nullrenderer_x64.exe`, `data/databundles/scripts.zip`, and `version.txt` under `Don't Starve Together/`.
- The listing also includes nonstandard-named DLLs/configuration. Provenance, build version, completeness, and runtime behavior are unverified; do not assume this archive is equivalent to a current unmodified official build.
- [Archive inventory](dst-archive-inventory.txt) records names only. Neither binaries nor the inner script bundle have been executed or inspected.
- RE:Compile already has seeded data generation, authored clearings/paths, scatter construction, pooled enemies, tree MultiMeshes/LOD, rule checks and a finite navigation grid.
- Navigation rebuilding was already optimized by about 74% in a paired seed-60 test, with equivalent cells. Movement profiling did not show movement as the dominant player cost; casting did. Do not discard these findings in pursuit of an unrelated rewrite.

Hypotheses to investigate, not established implementations:
- A constrained layout graph could improve variety while preserving progression and traversability.
- Separate random streams could prevent vegetation changes from unexpectedly moving critical loot.
- Placement validation and region-level navigation updates may scale better than rebuilding all content.
- Job scheduling, batching, visibility and simulation activation may help at larger scales; each needs a measured bottleneck.

Existing project evidence: [baseline](../performance-baseline-2026-11-14.md), [latest optimization](../priority-profile-2026-11-14.md), [existing queue](../QUEUED_PERFORMANCE_WORK.md). This plan supplements that queue; it does not replace casting profiling or claim that terrain is the cause of combat stalls.

## Research targets and boundaries

| Target | Verified public purpose | Questions to answer | Priority |
|---|---|---|---|
| Minecraft Java vanilla | Reference runtime, established experimentally here | Fresh generation vs revisits; chunk/simulation boundaries; terrain, vegetation, structure and loot placement ordering | Required baseline |
| C2ME | Chunk generation, I/O and loading optimization | Task dependencies, worker scheduling, bounded queues, determinism and main-thread handoff | High if generation/loading stalls matter |
| Sodium | Rendering replacement | Mesh batching, visibility decisions, resource reuse and upload scheduling | High only for measured rendering costs |
| Lithium | General simulation optimization | Spatial queries, avoiding repeated work, preserving AI behavior | Medium; separate from terrain timing |
| Distant Horizons | Distant terrain representations | Near/far representation transitions, cache invalidation, visual-only distant state | Optional; current map may not need it |
| Terralith | Terrain/biome and structure content | Data-driven placement and biome composition, not an assumed speed improvement | Optional content study |
| DST shipped scripts/modding API | Worldgen rules, locations/set pieces and creature modifications are supported modding areas | Layout constraints, population rules, authored motifs, resource distribution and persistence | High for finite-world design |

Primary sources: [C2ME repository](https://github.com/RelativityMC/C2ME-fabric), [Sodium repository](https://github.com/CaffeineMC/sodium), [Lithium repository](https://github.com/CaffeineMC/lithium), [Distant Horizons project](https://modrinth.com/mod/distanthorizons), [Terralith project](https://modrinth.com/datapack/terralith), [Klei modding guidance](https://support.klei.com/hc/en-us/articles/360029555992-Modding-Don-t-Starve-and-Don-t-Starve-Together).

### Source and reuse policy

Read published source before decompiling a mod. For DST, inspect shipped readable scripts and supported modding hooks before considering native code. Use REA only for a specific unresolved shipped-artifact question; record the question, target hash, tool, relevant evidence, and confidence. Do not decompile entire games just because a tool is available.

For every pinned version, record the actual license and file notices. Prior checks found C2ME's inspected 1.21.1 branch under MIT, Lithium under LGPLv3, Distant Horizons labelled LGPL-3.0-only, Sodium's inspected dev license under PolyForm Shield, and Terralith labelled Stardust Labs License. These are not blanket reuse permissions for all releases/dependencies. Verify the exact commit before reuse. [C2ME license](https://github.com/RelativityMC/C2ME-fabric/blob/ver/1.21.1/LICENSE), [Sodium license](https://github.com/CaffeineMC/sodium/blob/dev/LICENSE.md), [Lithium](https://github.com/CaffeineMC/lithium), [Distant Horizons](https://modrinth.com/mod/distanthorizons), [Terralith](https://modrinth.com/datapack/terralith).

Keep proprietary scripts/assets and extracted binaries outside RE:Compile's distributable content. Record mechanisms in plain language and implement against RE:Compile's own interfaces. Any actual source adaptation requires a provenance/license entry and the applicable notices/obligations; translation to GDScript is not automatically independent code. Do not bypass ownership checks, DRM or account requirements to obtain benchmarks. If the archive cannot run normally, source study and the other research tracks can still proceed. Klei's modding guidance explicitly distinguishes supported modifications from entitlement circumvention and unauthorized reuse; it does not grant a general license to transplant game code.

## Phase A — Inventory and isolate inputs

### A1. Pin the project and research environment
- Record current source hashes/commit, engine, OS, CPU/GPU, drivers, power mode and free disk space.
- Create separate research/output folders outside `res://` for downloads, extracted content and benchmark saves. Keep only reports/manifests in project docs.
- Record a test settings sheet and unique run identifiers. Never reuse the user's ordinary worlds or profile for destructive/resetting tests.
- Read applicable project rules and current runtime contracts before planning edits.
Acceptance: reproducible project manifest and artifact locations; no production gameplay changes.

### A2. Inspect the DST archive without running it
- Hash the RAR and save the full inventory (inventory already created; do not redo unnecessarily).
- Check extraction paths for absolute paths/traversal and inspect free disk requirements. Extract only `version.txt`, relevant license/readme material and `data/databundles/scripts.zip` initially.
- List the inner ZIP before selectively extracting Lua/configuration. Determine whether code is readable Lua, bytecode, or absent. Record exact build evidence; do not guess from filenames.
- Identify client/server executables and their provenance for a later runtime test. If this is a modified build, label measurements as that build; do not generalize to official DST performance.
Acceptance: archive hash, version evidence, script inventory and runtime eligibility notes. No executable launch required.

### A3. Discover Minecraft and select compatible profiles
- Locate SKlauncher and its configured game directory, Java runtime, installed Minecraft versions, saves and settings. Do not expose account tokens in logs.
- Choose one Minecraft version with verified matching loader/mod releases; prefer the user's working version when supported. Pin loader, Java, every dependency and mod hash.
- Create separate vanilla and mod-test profiles/directories, identical memory allocation and graphics settings, no shaders/resource packs at baseline.
- Keep the ordinary game profile untouched. Download only from the project's official release links.
Acceptance: vanilla launches, test world can be created, mods are compatible, all versions/hashes recorded. If access is unavailable, mark runtime tests blocked and continue source analysis.

## Phase B — Capture comparable behavior and performance

### Shared protocol

Within-game comparisons only: Minecraft FPS does not rank DST or predict Godot performance. World size, enemy behavior, rendering and simulation differ.

- Use the same hardware, renderer/settings per comparison, stable power mode and visible game window. Record physical/internal resolution, Vsync/cap, temperatures when available and background processes.
- No simultaneous benchmark, import, update, download or verification jobs. Run trials sequentially.
- Retain raw chronological frame times, process memory, scenario settings, seed/save snapshot, route and entity counts. Record client frame time separately from server simulation/tick time.
- Use an available validated frame capture tool or engine instrumentation. A FPS overlay screenshot is not frame-time evidence. If capture tools need installation/privileged access, prepare that explicitly rather than silently substituting estimates.
- Three trials minimum; proposed protocol: at least 10 s settled warm-up then 60 s sampling for traversal/combat, plus explicit cold-start/generation runs. Keep the existing RE:Compile 3 s/20 s historical measurements separate if the sample duration changes.
- Report average, p50/p95/p99, frames above 16.7/33.3/100 ms, actual duration, live entity counts and memory definition. Low-FPS runs remain valid if workload was valid; tail statistics from very few frames must be labelled coarse.
- Alternate baseline/candidate order where practical. Use unchanged paired settings and a fixed route. Separate OS cache, JVM warm-up, shader/LOD cache and fresh-world effects.
- Diagnose failed workload assertions before timing conclusions. Retain excluded logs with a reason; never mix dead-player or stationary-traversal fixtures into the valid sample.

### B1. Minecraft scenarios and game modes

| Scenario | Setup | Measurements and validity |
|---|---|---|
| First world generation | New world from a fixed seed, fixed world settings; repeat in independent fresh saves | Time to playable world; main-thread stall evidence; generated-area counts when observable |
| Fresh exploration | Creative flight or spectator on a fixed-speed recorded route through verified ungenerated chunks | Frame times, new chunks completed/time, chunk latency if observable, integrated-server tick cost; mode explicitly recorded |
| Revisit | Same route on a cloned save whose route was fully generated beforehand | Frame times/loading cost; prove no new terrain generation along the route |
| Dense combat | Survival, fixed difficulty/time/weather, fixed loaded structures and enemy count; controlled health handling documented | Frame times, tick times, AI/population, deaths and casts/attacks; validate it actually stays in combat |

Use creative/spectator only for generation/traversal reproducibility; those modes are not hostile-combat benchmarks. Chunk pregeneration can move work earlier; do not call it a faster generator unless actual generation throughput improves. Generated does not mean currently loaded: distinguish disk loading from generation on revisits.

### B2. Minecraft comparison matrix

Start with required dependencies only; “+ mod” always means its required dependencies are recorded too.

1. Vanilla control.
2. Loader-only control (separates loader/dependency overhead).
3. Loader + C2ME: prioritize generation/fresh exploration.
4. Loader + Sodium: prioritize revisit/rendering.
5. Loader + Lithium: prioritize dense combat/simulation.
6. Compatible combination of demonstrated winners: retest all affected scenarios; individual gains are not additive by assumption.
7. Optional Distant Horizons: compare both matched visible-distance settings and explicitly expanded-distance settings; report LOD detail, cache state and whether background generation is active.
8. Optional Terralith: a separate content workload, fresh saves and its own baseline; do not treat changed terrain complexity as a like-for-like optimizer comparison. Its current project page warns against removing it from existing worlds and notes mod/datapack differences; verify pinned-version guidance before setup.

Acceptance: at least the controls and individually relevant candidates have valid paired runs and an interpretation per scenario. Do not install an all-in-one optimization pack that prevents attribution.

### B3. DST scenarios

Pin the archive/installed build. Start with an unmodified local world if the build supports normal access; record survival mode, world size, season, character, surface/caves configuration and seed or reproducible world snapshot mechanism actually supported by that build.

- Generation: separate initial world creation from loading an existing save. Confirm whether this build generates the whole map up front; do not invent Minecraft-style fresh-chunk tests if it does not.
- Traversal: repeat a route spanning dense vegetation, authored/generated landmarks and populated regions. Record camera zoom, entity counts and whether simulation is client/server/local-host.
- Dense encounter: use a test world and supported console/mod hooks where available to create a reproducible threat count. Document all overrides, invulnerability and their effects on AI. Capture client and local server costs separately when possible.
- Compare surface-only and caves-enabled configurations only as separately labelled workloads; do not present their difference as an optimization.
- Only after baseline: a minimal diagnostic mod to collect counts/timers or expose generation phases. Compare instrumented versus uninstrumented runs to estimate overhead.
Acceptance: three reproducible scenarios appropriate to DST's actual generation model, or an explicit runtime blocker plus completed source-only findings. Do not claim the RAR is a playable benchmark until verified.

## Phase C — Study mechanisms with evidence

### C1. Minecraft mods

For each selected mod, pin a commit/release and follow a single relevant execution path. Record source files/symbols, inputs, outputs, scheduling, data ownership and a trace or test confirming the interpretation.

- C2ME: generation dependency order; queue bounds/backpressure; cancellation; synchronization; disk/load stages; worker-to-main-thread handoff. Determine which ideas remain useful for a small finite world.
- Sodium: visible section selection, mesh generation/upload work, batching/material grouping, rebuild invalidation and memory limits. Compare against Godot features already used before proposing custom renderer work.
- Lithium: one measured simulation issue only, such as query reuse or spatial indexing. Verify preserved behavior; avoid assuming reduced hostile counts are an acceptable optimization.
- Distant Horizons: representations, transitions and cache invalidation only if RE:Compile needs longer sightlines. Far visuals must not become authoritative collision/AI state.
- Terralith: biome/structure definitions and placement constraints. Separate content quality from compute cost.

Acceptance: one evidence-backed mechanism note per studied target, plus “adopt / experiment / reject” reasoning. Stop after answering the specific question; no entire-engine reconstruction.

### C2. DST script map

Search the extracted bundle for worldgen entry points and terms such as task, taskset, room, layout, setpiece, prefab, population, loot, respawn and sleep. These are search hypotheses, not verified paths or claims about this archive.

Trace:
1. World settings and seeded randomness into high-level topology.
2. Required progression/landmarks into region or room selection.
3. Terrain/biome assignment into vegetation and resource placement.
4. Authored set pieces into collision/clearance and connectivity checks.
5. Loot rules into containers, drops and persistence.
6. Initial hostile placement versus runtime respawning, activation and AI updates.
7. Failure/retry behavior when constraints cannot be satisfied.
8. Save/load behavior for harvested resources, killed enemies and looted containers.

Acceptance: diagram and evidence table with exact bundle paths/symbols. Clearly separate directly read script behavior, runtime observations and inference. A visual resemblance is not evidence of shared algorithms.

## Phase D — Translate findings to RE:Compile

Create a decision table before implementation:

| Candidate idea | Existing seam | Required proof before adoption |
|---|---|---|
| Constraint-guided layout variation | `dark_forest.gd` generation/rule checks | Existing fixed routes are the limiting content issue; all required locations stay reachable |
| Independent seeded streams/stable IDs | Generation output and spawn RNG | Reproducible output, migration/version policy, no duplicate persistent items |
| Region-based placement occupancy | Scatter/obstacle definitions | Measured repeated queries or placement conflicts justify it |
| Incremental navigation update | `navigation_grid.gd`, `_rebuild_navs` | Actual change workload benefits beyond the existing optimization; cell equivalence maintained |
| Bounded preparation jobs | Pure generator → main-thread scene construction | Measured stalls justify concurrency; no unsafe scene/resource mutation from workers |
| Spatial render batching/LOD | Existing tree chunks/MultiMeshes | GPU/rendering evidence, no lost visibility or collision |
| Distant simulation reduction | Existing enemy pool and actor tick | Measured CPU benefit; no pop-in attacks, lost timers or broken respawns |
| Authored structure templates + loot | New validated content definitions | Current design explicitly includes them; placement, navigation and persistence contracts defined |

Default architecture proposal, subject to evidence: generate deterministic data → validate topology and reservations → place structures and critical loot → scatter nature → place hostile zones → create scenes/collision → build/update navigation → activate gameplay. Avoid adding streaming merely to imitate Minecraft. Reserve critical routes before scatter. Treat generation, rendering, collision and AI as separate costs.

## Phase E — Implementation slices

Implement only approved/adopted findings, in this order. Preserve the current playable forest as a regression fixture.

### E1. Generation observability and failure contracts
- Add missing per-stage timing, counts, retry reasons and seed/version evidence using existing tools.
- Retain rejection of invalid maps and previous-map recovery. Do not return unchecked output on retry exhaustion.
- Make profiling optional or test-only; measure its overhead.
Acceptance: reproducible diagnostics, no partial world swap, no profiler-driven behavior change.

### E2. One complete placement slice
- Start with one existing biome/forest area, one authored structure motif if design-approved, one reachable loot/pickup placement, and one valid hostile zone.
- Reuse existing generation/scene interfaces; add only required data fields and stable IDs.
- Validate player and enemy traversal, doorway/entrance clearances, vertical surfaces and placement bounds before committing the layout.
Acceptance: playable start → explore → encounter → obtain reward → return/restart path across multiple seeds. Do not add many structure variants before the first works.

### E3. Nature and content density
- Add deliberate distribution by region/slope/clearance rather than independent uniform scatter everywhere.
- Preserve route readability, critical pickup visibility and tree/rock collider alignment.
- Use actual geometry/footprints and density counts; keep authored motifs distinct from random placement.
Acceptance: specified density and variety without blocked routes, overlap bugs or empty threat/resource regions.

### E4. Population and loot lifecycle
- Separate initial placement from respawn/activation.
- Preserve hostile caps and measurable encounter density; performance gains cannot come from silently removing enemies.
- Define whether ordinary loot persists, resets per run or respawns. Maintain current permanent-page progression semantics.
- If new persistent loot is approved, store depletion/ownership state so save/load cannot duplicate rewards; version saved layouts and handle generation changes explicitly.
Acceptance: no spawn inside solid geometry, no immediate attacks on spawn, no duplicate rewards, predictable death/restart/save/load.

### E5. Measured optimization
- Choose one bottleneck at a time: preparation, scene creation, navigation, draw/mesh work, or AI.
- Keep the simplest complete change; compare against existing engine facilities.
- If using asynchronous preparation, bound jobs/memory and reject stale results after restart/cancellation; scene mutation remains on the supported main-thread route.
Acceptance: matched-workload benefit without correctness loss. Revert complexity with no repeatable gain.

### E6. Expansion only after gates pass
- Expand authored templates, biomes or map size one dimension at a time.
- Streaming, persistent regions and long-distance LOD are optional later milestones requiring explicit scale needs and measured justification.
Acceptance: each expansion retains the reference tests and meets the same quality bar; no unbounded roadmap presented as completed implementation.

## Required tests and acceptance gates

### Generation correctness
- Same seed + generator/content version + settings produces identical canonical data/hash.
- Different seeds produce meaningful, bounded variety; record distributions rather than a single attractive map.
- Run the existing 1,000-seed content sweep, plus adversarial seeds/density limits and repeated generation.
- Required pages/loot/structures/spawn zones exist, lie within bounds, satisfy minimum distances and are reachable using real collision/navigation.
- No protected-route vegetation, collider/visual disagreement, structure entrances blocked by scatter, or impossible elevation transitions.
- Test retry exhaustion, cancellation, corrupted/missing definition and invalid candidate recovery.
- If independent RNG streams are adopted, verify unrelated decoration changes do not move gameplay-critical content unintentionally.

### Simulation and persistence
- Full existing Simulation suite (latest verified count 685; do not hardcode that as future expected count).
- Navigation old/new equivalence including boundaries, heights, overlap, emptied/replaced regions and standing/climbing paths.
- Hostile activation/deactivation, offscreen timers, respawn cooldown, crowd navigation, death/restart and spawning under pressure.
- Inventory/reward conservation for any new loot integration; permanent pages and profile backup recovery remain correct.
- Save/load equivalence only for state that is actually supported; do not invent a full persistent-world feature as a prerequisite for a per-run prototype.

### Visual and performance
- Rendered captures of representative dense/sparse seeds, structures, entrances, loot visibility, hostile approach, LOD transitions and collision contacts.
- Current renderer targets only; retain configured quality, draw distance and content counts across comparisons.
- Three sequential trials each for generation/loading, traversal and normal-rate dense combat, plus separately labelled overload where relevant.
- Keep existing 7.7 ms p95 gameplay/stress target; define which suite applies it. A capture PASS is not a budget PASS.
- Existing forest test has a 200 ms generation/build check; do not silently redefine it to include/exclude navigation. Record it separately from full time-to-playable and propose any additional total-load budget explicitly.
- No observed cell/rule/behavior regressions; no new script/resource errors. Existing warnings are tracked separately, not ignored or relabelled.
- Require a repeatable gain larger than trial variation before accepting optimization claims. Report CPU/GPU/memory tradeoffs.

## Queue, dependencies and deliverables

| ID | Work | Depends on | Deliverable / completion gate |
|---|---|---|---|
| Q01 | Environment/project/archive manifests | None | Versions, hashes, inventory; no launches assumed |
| Q02 | DST script extraction/map | Q01 | Verified entry points and unanswered questions |
| Q03 | Minecraft profiles and compatibility | Q01 | Working isolated control profiles |
| Q04 | Shared capture validation | Q01 | Raw frame/tick data and workload checks |
| Q05 | Minecraft individual-mod experiments | Q03,Q04 | Paired scenario results |
| Q06 | DST creation/traversal/encounter experiments | Q02,Q04 + runnable build | Build-specific results or documented blocker |
| Q07 | Source mechanism notes | Q02,Q03 | File/symbol evidence; no speculative algorithms |
| Q08 | Adoption and license/provenance matrix | Q05–Q07 (or explicit missing evidence) | Adopt/experiment/reject per technique |
| Q09 | One complete RE:Compile placement slice | Q08 + content design decision | Reachable structure/reward/threat loop |
| Q10 | Seed/navigation/lifecycle regressions | Q09 | Correctness gates pass |
| Q11 | One measured optimization | Q08,Q10 | Paired benefit, preserved behavior |
| Q12 | Render/playthrough/performance acceptance | Q11 | Complete evidence, honest failed gates |
| Q13 | Documentation and delivery | Q12 | Current README, queue status, Irminsul log; exported build only if requested/authorized |

Proceed sequentially by default. Source-only work can continue if a game cannot launch. Do not treat unavailable game measurements as successful validation of a Godot change. No fixed completion date is promised before inventory and baseline capture are measured.

Recommended outputs outside distributable content: input manifest, pinned-source license ledger, Minecraft trial manifest/results, DST script map/results, mechanism notes, adoption decision table, raw logs/CSV, generation seed corpus, before/after screenshots and final acceptance report. Keep summaries and links in this folder; never bundle commercial game content in a game export.

## Completion definition

The work is complete only when selected techniques are either implemented and verified in RE:Compile or explicitly rejected with evidence; the target content remains populated with nature, meaningful structures/rewards and hostiles; current gameplay tests pass; before/after results are reproducible; rights/provenance are recorded; and remaining limitations are stated. A list of mods, a successful archive extraction, or faster FPS in Minecraft alone is not completion.

## Execution handoff

> Read this plan and the existing queued performance work. Start at Q01. Do not rerun completed inventory work without a reason. Pin source/build versions, keep game worlds isolated, and validate capture correctness before timing. Study available source/scripts before native reverse engineering. Implement only the smallest evidence-supported Godot change, preserve gameplay and thresholds, and record the result in Irminsul. Report blockers precisely and continue independent work where possible.
