# 500 m forest implementation — 2026-11-15

Architecture was recorded in [ARCHITECTURE_500M.md](ARCHITECTURE_500M.md) before implementation. This is a working source implementation, **not performance acceptance**. No release executable has been exported.

## Implemented

- Finite **500 × 500 m** forest with 25 clearings and connected routes. The original camp, page progression and introductory area remain level.
- Seeded hills, approximately 0–8 m high, blended into clearings and routes. Mesh triangles, physical ground, navigation heights, grass and object placement share one sampled surface. Collision tests caught and fixed triangle winding before acceptance.
- Jittered, spaced trees with three regional density profiles; stratified rocks across 50 m sectors. After the generation prefilter, seed 60 has 7,178 trees and 317 rocks, with at least 185 trees in each 100 m sector. Required content is rejected before generating expensive decoration when its routes are invalid. Changing the generation draw order changes layouts for existing seeds.
- **256 pooled forest enemies; 224 initial/maintained residents across 64 spawn zones.** Four nominal slots per zone support the initial population. Placement checks the built navigation grid and earlier occupants, using a nearby free cell when necessary. This fixed a blocked initial slot exposed by the final seed-60 integration test. The arena retains its 20-capacity/8-target rules.
- Distant idle residents pause AI and animation beyond 64 m; nearby enemies and combat states continue full-rate simulation. Identity, health and effects are retained. Reserve actors stop animating. Reset and approach wake actors; damage changes state and wakes them on the next actor update. Dormancy does not substitute for active actors in the combat benchmark.
- Static-ground motion is reused only when grounded, stationary, at the previous physics position and on the same navigation revision. Reset, movement, teleport and world rebuild invalidate reuse.
- Forest navigation uses 1 m cells (250,000 per grid versus the old 360,000); the arena stays at 0.25 m. Expanded obstacle margins conservatively cover coarse-cell footprints, and clearance is ground-relative.
- Path proximity uses spatial bins; route validation uses exact segment clearance. Seed-independent terrain flattening masks are cached. Near/far trees use matching spatial batches; grass is grounded and its cache evicts distant chunks.
- Benchmarks retain **7.7 ms p95** and **200 ms generation/build** gates. Active, reserved and dormant counts are separate. The expanded traversal route reaches the southern forest; `--residents` retains the normal 224 residents.

## Source-study ideas actually used

The DST study informed connected topology before decoration, mandatory population placement, bounded retries, and separating world residents from active simulation. Existing Godot MultiMeshes, grids, effect rules and object pools were reused. No commercial source was copied. No C2ME scheduling algorithm or Minecraft rendering implementation was reconstructed or imported.

## Evidence

All artifacts are under `evidence/terrain-500/`. Earlier captures are retained rather than overwritten when a source change requires remeasurement. The `crowd-initial` captures pin their own source snapshot and precede the final generation prefilter.

| Check | Recorded result |
|---|---|
| Terrain sampler/mesh/determinism | 4 checks pass |
| Spatial query reference, coverage across 100 seeds, all terrain triangle slopes for seed 60 | 8 checks pass |
| Runtime population, spawn clearance/non-overlap, 64 connected zones, wake-up, hill collision, player grounding, bounded grass | 9 checks pass after the initial-slot correction (`runtime-verified.log`) |
| Content, including 1,000 seeds | 200 checks pass |
| Full simulation, first integration | 878/879 pass; only 200 ms build gate fails (1,176 ms rebuild; 434.6 ms mean data generation) |
| Full simulation after generation prefilter | 878/879 pass; only build gate fails (944 ms rebuild; 239.6 ms mean data generation). The subsequent initial-slot correction has the focused runtime recheck above. |
| GPU render regression | 120 checks pass |
| Additional expanded-region render checks | 8 checks pass; hill and southern screenshots inspected |
| Initial active combat, 20 enemies | Valid capture; p95 14.066 ms; budget fails |
| Initial active combat, 250 enemies | Valid capture; p95 212.304 ms; budget fails |

The dense combat fixture uses immortal enemies, an immune firing player and a persistent ring; it is intentionally harsher than distributed forest play. These measurements do not establish a causal speedup over earlier source snapshots containing different spell/graphics changes. Static engine memory measurements are not process RSS. Background activity, thermals and power state are not fully controlled.

### Final GPU measurements

Ryzen 5 6600H / RTX 2050, Godot 4.7.2 Forward+, high preset, 640×360 internal rendering, grass 25 m, tree detail 40 m, VSync disabled. The selected dense map is now **seed 1, with 10,299 trees**, determined by generating and counting the first 64 seeds instead of assuming the first random spacing draw survives retries.

| Workload | p95 frame time | Result |
|---|---:|---|
| Populated traversal, 224 residents, one capture | 15.983 ms | Valid workload; 7.7 ms budget fails |
| 20 active enemies, trial 1 / 2 / 3 | 14.544 / 13.816 / 14.043 ms | All valid; all fail budget |
| 250 active enemies, trial 1 / 2 / 3 | 202.613 / 212.770 / 198.707 ms | All valid; all fail budget |

Traversal covered **186.9 m**, retained 224 residents throughout, simulated **17–41** at a time and kept **183–207** dormant. All 1,690 recorded navigation queries succeeded. This is a normal populated-world capture, not a claim that 224 enemies were simultaneously fighting or on screen.

Each dense-crowd capture retained exactly the requested actively simulated population throughout. Average simulation cost was 3.65–3.76 ms/tick for 20 and 14.50–15.23 ms/tick for 250. Peak tracked engine static allocations were about 430 MiB and 488–489 MiB respectively. These numbers exclude untracked process/GPU memory.

The corrected dense-map warm rebuild took **1,356.988 ms CPU**, comprising 227.961 ms data generation, 549.979 ms scene construction and 579.048 ms for both navigation grids. First drawn frame arrived after 1,583.258 ms. **The 200 ms build gate fails.** Process-launch timing includes a benchmark-only density scan and is not a valid game cold-start measurement.

Evidence: `crowd-final/summary.json`, per-trial metrics and population CSVs, `final-validated-captures.json`, and `generation-corrected/validation.json`. All six crowd captures passed source-hash stability checks. The only later source change was in the generation branch of `tests/performance/baseline.gd`: it now rebuilds the selected seed and reports its build budget explicitly. Production scripts are unchanged from those captures. `generation-final` is superseded because it rebuilt hard-coded seed 60 while its settings described seed 1; retain it for audit, do not use it as dense-map acceptance evidence.

## Remaining acceptance work

The performance targets remain unmet. The forest keeps its complete terrain and static collision resident; collision streaming was not introduced because missing collision would compromise gameplay. Large-map construction and memory therefore still scale with total geometry. Higher-density animation/rendering and presentation/effect CPU costs need separate profiling before claiming smooth 250-enemy combat.

Next optimization work should target the measured costs: scene construction plus two navigation rebuilds during loading; actor, effect and presentation CPU costs under dense combat; and renderer/skinning costs measured separately from simulation. Coalescing redundant presentation work and testing actor render/animation LOD are candidates to measure, not established fixes. Keep combat timing, collision correctness and active-population accounting intact.

The full-map 10-minute soak and a release export are still outstanding; performance acceptance has already failed. No infinite terrain, worker-job framework, new loot system or new dependency was added. Asset UID fallback warnings remain in the Godot logs; the recorded final functional and GPU checks contain no engine/script error lines.

## Reproduction

From the project directory:

```powershell
godot_console --headless --path . -s res://tests/simulation/test_terrain_surface.gd
godot_console --headless --path . -s res://tests/simulation/test_forest_expansion.gd
godot_console --headless --path . -s res://tests/simulation/test_forest_runtime.gd
godot_console --headless --path . -s res://tests/simulation/run_simulation.gd
godot_console --headless --path . -s res://tools/validate_content.gd
godot_console --path . res://tests/render/terrain_500.tscn -- --out=res://evidence/terrain-500/render
python tools/benchmark_terrain.py --counts 20 250 --trials 3 --out evidence/terrain-500/crowd-final
```

GPU generation/traversal captures use `res://tests/performance/baseline.tscn` with `--scenario=generation` or `--scenario=traversal --residents`. Create a separate output directory before each run. Run timing captures sequentially, after functional suites finish.
