# First three terrain-preparation tasks — results

2026-11-14. Implementation, repeated GPU measurements and verification complete. Measurements describe their pinned source snapshot; later shared changes have not been rebenchmarked. Normal gameplay retains the 20-enemy pool and target of eight alive. No map expansion or production-cap increase is included.

## Implemented

1. **Hostile scaling benchmark:** `tests/performance/baseline.gd` accepts `--enemies=20|50|100|200|250|300`. It records chronological frames, active/reserve/aggro counts on every sampled tick, casts, memory, path requests/failures/time, LOS cost and simulation stages. `tools/benchmark_terrain.py` runs sequential repetitions, pins source hashes and stops on invalid captures or source changes. A source consistency check guards the copied simulation method.
2. **Projectile prewarming:** `projectile_service.gd::prewarm_visuals` prepares 24 basic and two special visuals during loading, after the VFX service is ready. It creates no live shots, damage or rings. Calls are idempotent and reset returns visuals to the existing pool. Higher sustained workloads can still grow that pool normally.
3. **Final-position spawn validation:** `_respawn` checks the position after jitter: safe player distance, navigation cell and local route, ground/footprint support, floor normal, capsule clearance against world geometry and current live-actor occupancy. Eight attempts maximum. Failure keeps the actor in reserve and waits the normal four-second interval before retrying.

The [Godot direct-space-state documentation](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate3d.html) describes the shape/ray query APIs used. The candidate uses the actual actor capsule and world collision mask. Height-aware navigation remains future work; spawning currently accepts only near-flat support around the zone height.

## Verification

- Initial focused tests failed for the two missing features. Final focused regression: **17 checks PASS**, including benchmark-copy consistency, no-root/idempotent prewarm, allocation-free reuse, hidden pooled visuals, unsupported/blocked/occupied candidates, player distance and bounded failure retries.
- Content: **175 checks PASS**.
- Render: **102 checks PASS**; camp screenshot inspected, no prewarmed projectiles visible.
- Full Simulation recheck: **788 checks PASS** (`simulation-final.log`). An earlier run failed the existing 200 ms map-build gate at **280 ms** (data generation 72.4 ms), showing load sensitivity; that failed result is retained. The passing recheck reported **four audio objects leaked at shutdown**: two AudioStreamWAV and two AudioStreamPlaybackWAV instances. These warnings remain unresolved; a passing assertion suite is not a clean-release claim.
- Existing normal spawn, combat, movement and pool checks ran in the recorded simulation suite. Concurrent spell-system changes were preserved. After subsequent shared changes, the current focused suite again passed **17 checks** with unchanged sources during that test (`focused-current.log`). The full suite and rendering results above are recorded runs, not a claim that every later shared change was revalidated.
- No release executable was rebuilt. Use the updated source project to exercise these changes.

## Measurement method

This is a **dense, sustained combat stress fixture**: enemies begin near camp, have very high health to retain population and use their normal AI. The player is immune and fires at normal attack speed. One persistent zero-damage Ring of Fire remains from the established harness, and the entire crowd can burn. This is not dispersed-world population or ordinary traversal. Placements differ from the historical 20-enemy fixture, so its old 6–7 ms results are not a direct before/after comparison.

Each valid capture needs more than 300 frames, at least 20 seconds after warm-up, over 100 simulation ticks, the requested active population throughout the sample, no reserve substitution, a living player and normal-rate firing. Slow runs extend until enough frames are collected, subject to a 150-second sample deadline and 210-second process timeout. **Capture validity and the unchanged 7.7 ms p95 budget are separate gates.**

First-cast comparison uses identical pinned sources for both modes in the benchmark with `--cold-pool`, which disables only loading prewarm in a benchmark subclass. Visual allocation is moved into loading, not eliminated. Hidden preparation does not guarantee all first-use GPU shader/pipeline hitches disappear. Special-shot reuse is functionally tested; it has no separate rendered timing comparison here.

### First-cast visual creation

Three cold-pool trials allocated a visual on the first cast, taking **29.34 / 32.40 / 31.11 ms**. All three prewarmed trials created **zero** visuals on that cast (0 ms in the visual-creation counter).

Loading-time preparation of the 26 visuals took **1304.95 / 729.17 / 465.45 ms** in the three 20-enemy trials. This is an explicit startup-time/memory tradeoff, not a claim that every frame hitch is eliminated.

### Active-hostile sweep — three valid trials per count

| Active hostiles | p95 frame ms, trials 1 / 2 / 3 | Median simulation ms/tick | Effective simulation ticks/s range | 7.7 ms budget passes |
|---|---|---|---|---|
| 20 | 72.06 / 15.72 / 14.88 | 2.66 | 60.0–60.0 | 0/3 |
| 50 | 196.85 / 29.73 / 17.73 | 4.89 | 54.8–60.1 | 0/3 |
| 100 | 304.97 / 110.88 / 53.50 | 8.78 | 42.2–58.9 | 0/3 |
| 200 | 337.42 / 258.39 / 273.48 | 15.44 | 40.2–49.2 | 0/3 |
| 250 | 465.78 / 298.68 / 285.40 | 18.66 | 30.6–40.8 | 0/3 |
| 300 | 536.58 / 340.14 / 359.41 | 22.81 | 27.0–34.4 | 0/3 |

Every capture retained the requested active population and verified normal-rate casts. No inert or reserve enemies were counted as active. Effective simulation frequency is sampled ticks divided by wall time; the configured target is 60 Hz. Slow simulation is an additional overload symptom, even when population validity passes.

**All eighteen captures failed the frame-time budget.** This demonstrates the current dense-crowd limitation, not a universal limit on geographically distributed enemies. Close-range crowding produces relatively few path requests; it does not establish long-distance navigation scalability. Additional fixture actors use normal actor setup and combat behavior, but persistent progression is outside this benchmark.

Raw results: [scaling summary](../../evidence/terrain-three/verified-sweep/summary.json), [cold-pool summary](../../evidence/terrain-three/cold-pool/summary.json), [pinned sources](../../evidence/terrain-three/verified-sweep/sources.json).

Reproduce from the project root, sequentially, with normal GPU/cache access and no other tests running:

```powershell
python tools/benchmark_terrain.py --out evidence/terrain-repeat
python tools/benchmark_terrain.py --counts 20 --cold-pool --out evidence/terrain-cold-repeat
godot_console --headless --path . -s res://tests/simulation/run_terrain_ready.gd
```

Output directories must be new; existing evidence is not overwritten. Source drift or a failed workload capture stops the runner. A failed frame budget remains recorded independently of capture validity.


## Conditions, exclusions and limits

RTX 2050 / Ryzen 5 6600H; Godot 4.7.2 Forward+; internal 640×360; grass 25 m. Full graphics settings are recorded per capture. Ultimate Performance power plan observed. A separate Godot editor stayed open to preserve shared work; the console wrapper and its GUI child are one benchmark, not two parallel trials. Thermals and background load were not controlled. Large variation across repetitions prevents treating these timings as an isolated hardware limit or claiming a small FPS gain.

Initial `smoke`, `before-*`, and `final-sweep` captures were diagnostic/invalid because of sandbox cache denial, too few frames, or a duplicated spell-input line in the profiler copy. They are excluded. The duplicate was corrected and consistency rechecked. Source changes invalidate a capture instead of silently mixing versions.

Evidence: `evidence/terrain-three/verified-sweep/` and `cold-pool/`, each with `summary.json`, `sources.json` and per-trial logs/metrics/chronological frame CSVs/population CSVs. Functional logs: `focused-current.log`, `content-authorized.log`, `simulation-final.log`, `render/run.log`. `current-verification.json` records 22 changed and two added source files since the benchmark snapshot; those later changes have not been rebenchmarked. Save/load tests required normal temporary user-data access after sandbox denial; test worlds disable player-profile saving.

## Next work

These fixes do not establish 500 m terrain or performant 250-hostile combat. Use the recorded stage costs to choose the next optimization. Compare the same crowd with controlled burning presentation and actor animation/rendering diagnostics. A large gap outside measured simulation is a profiling lead, not proof of a specific GPU bottleneck. Preserve active counts and gameplay rules during comparisons.

Map expansion, height-aware navigation, grass residency, failed-path retry backoff and vendor UID cleanup remain outside these three tasks. The earlier map-build budget failure and shutdown audio leaks remain follow-up items; no green release claim is made.
