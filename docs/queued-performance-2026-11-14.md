# RE:Compile: queued performance and verification work (results, 2026-11-14)

Done in one session, in checklist order. Evidence: `evidence/queued-20261114/`. Per-trial
numbers are in `summary.json`, and that file also lists the SHA-256 hashes of the changed
sources and the exported executable. Each trial folder holds its `run.log`, its
`metrics.json`, and a chronological `frametimes.csv`. The project has no Git repository,
so the hashes are the version record.

## Setup (recorded by the runner in every `metrics.json`)

| Item | Value |
|---|---|
| Hardware | AMD Ryzen 5 6600H (12 threads); NVIDIA GeForce RTX 2050, driver 32.0.16.2114, Vulkan 1.4.357 |
| Engine and renderer | Godot 4.7.2-stable, Forward+ |
| Resolution | Viewport 1920×1080, window 1280×720, internal 3D 640×360 (pixel look); screen refresh 165 Hz |
| Frame rate | Vsync off, max_fps 0, physics at 60 Hz |
| Workload settings | Seed 60 (the dense seed); grass 25 m; 3 s warm-up, then a 20 s sample |
| Power | AC power, Ultimate Performance plan |
| Not controlled | Thermals and background load. CPU load was read at the start of each trial: 5–42%. |

Runs were sequential, with nothing else running alongside. The window stayed visible and
focused (`focused: true`). The runner never writes the player's profile, because session
saving is off in the benchmark world.

## 1. Benchmark correctness (`tests/performance/baseline.gd`)

- **Frame samples:** saved in chronological order (`index,ms_chronological`). Percentiles
  come from a sorted copy.
- **Workload counters:** basic and special casts against the Atk Spd schedule, live
  enemies, projectiles before and after each tick, visuals reused or created, simulation
  ticks, distance travelled, player alive, and input context.
- **Validity checks:** a trial is valid only when all of these hold:
  - enough frames (more than 300);
  - more than 100 simulation ticks;
  - the player is alive;
  - input stayed in gameplay;
  - traversal: moved more than 10 m with 0 casts;
  - combat: 20 live enemies and at least 80% of the scheduled casts;
  - the evidence was written.
- **Validity is reported separately from performance.** Status PASS means a valid
  capture. Whether it met the budget is reported on its own, as
  `metrics.performance = {p95_budget_ms: 7.7, p95_ms, within_budget}`.
- **Stage timers** (`main.costs`, `pcombat.prof`) are reset when the warm-up ends, so they
  cover the same window as the frame sample.
- **Profiling copy check:** `simulate_in_sync()` compares the profiling copy of
  `main.simulate` with the real method, ignoring the timing lines. The run fails if they
  have drifted apart.
- **Generation:** each stage is timed on its own (data, scatter, standing nav, climbing
  nav, physics frame, first draw). Cold launch (process start to first drawn world) is
  reported separately from the warm rebuild.

## 2. Casting profile: the hot path

`player_combat.prof` holds opt-in substage timers. When off, each costs one null check.
They record how many times each substage ran, its total time and its worst single time.

| Substage (normal combat, before the fix) | Calls / 20 s | Per call | Max |
|---|---|---|---|
| `cast.crosshair` (`crosshair_point` → `target_along`) | 100 | **14.1–15.8 ms** | 36.5 ms |
| `cast.launch` | 100 | ~0.8 ms | 25 ms (the first 4 casts create visuals) |
| `cast.hand_origin` | 100 | 0.03 ms | 0.08 ms |
| `advance` / `resources` / `slots` (every tick) | ~1,170 | < 0.03 ms | < 0.2 ms |

**Cause.** `ProjectileService.target_along` tests a line against a capsule by stepping
along it every 5 cm. That suits a projectile's per-tick path, which is under a metre.
`crosshair_point` calls it with the full 100 m aim range: about 2,000 steps × 20 enemies
for every cast.

**Fix.** The march now visits only the stretch of the same 5 cm grid that lies inside the
capsule's bounding sphere. Steps outside that sphere cannot hit, so the result is
identical. Callers searched: `crosshair_point`, used by both the basic and the special
cast, and `_first_contact` in projectile flight. Both get the same results.

**Regression.** `tests/simulation/test_target_along.gd` compares the culled march with the
full march on 4,000 random segments: 100 m and per-tick lengths, hits, misses, starts
inside a capsule, zero-length axes, and extra radius. Results must be exactly equal. It
also includes a speed check.

## 3. Before and after (normal combat, same seed and settings, 3 trials each)

| | Before | After |
|---|---|---|
| Aim query per cast | 14.1 / 14.6 / 15.8 ms | 0.19 / 0.20 / 0.19 ms (max 0.45) |
| Casting per tick | 1.25 / 1.29 / 1.40 ms | 0.09 / 0.10 / 0.09 ms |
| Simulation per tick | 3.40 / 3.42 / 3.72 ms | 2.32 / 2.37 / 2.33 ms |
| p95 frame | 8.80 / 7.19 / 7.25 ms | **6.86 / 7.20 / 6.70 ms** |
| p99 frame | 21.06 / 18.33 / 18.79 ms | **11.38 / 11.51 / 11.26 ms** |
| Within the 7.7 ms p95 budget | 2 of 3 | **3 of 3** |

In every trial: 100 casts out of about 100 scheduled, 20 live enemies, about 15
projectiles in flight, player alive. Disclosed setup: the player is immune, and there is
one persistent zero-damage Ring of Fire. Enemies crowd the player, so the player travels
only about 8.8 m. Content (131 checks) and Simulation (687) pass, with no SCRIPT ERROR or
ERROR lines. Render was not re-run because no visual code changed.

## 4. Navigation and loading

`tests/performance/navigation_compare.gd` (the original rebuild is kept as `Reference`):
**19 cases, 0 mismatches.**
- **Forest seeds:** 60, 7, 4242, 123 and 999, standing and climbing grids each.
- **Synthetic edge cases:** an exact agent-radius boundary (and 0.0001 m inside it),
  overlapping boxes, boxes past the map edges, the height-filter boundaries, a low
  `body_high` grid, thin and zero-size boxes.
- **Reuse:** a rebuild after a previous map equals a fresh reference rebuild.
- **Paths:** all 9 camp-to-page and camp-to-zone paths are identical and reachable, with
  the diagonal mode the same on both.
- **Empty rebuild:** clears every cell.
- **Paired timing:** standing grid old 83–135 ms, new 20–37 ms; climbing grid old 80–111 ms,
  new 20–23 ms.

**Generation**, warm rebuild with assets already loaded, 3 trials:

| Stage (ms) | Trial 1 | Trial 2 | Trial 3 |
|---|---|---|---|
| data | 20.8 | 30.9 | 20.5 |
| scatter | 66.7 | 65.7 | 59.2 |
| nav standing | 21.4 | 17.6 | 17.6 |
| nav climbing | 21.0 | 20.9 | 16.8 |
| CPU total | 130.0 | 135.1 | 114.1 |
| through the first drawn frame | 184.6 | 181.8 | 157.7 |
| cold launch, process start to first world draw | 11,027 | 8,033 | 8,919 |

- **Where the time goes now:** scatter is the largest stage. Navigation fell from 65–75% of
  rebuild CPU overnight to about 30%.
- **First-draw figures aren't comparable with the overnight ones** (2,287–3,674 ms). Those
  included the process's first frame (shader warm-up). This runner waits for one frame
  before timing, and reports cold launch separately.
- **The 74% navigation gain does not carry over** to total load time or to FPS.

## 5. Gameplay acceptance (3 trials each, all kept)

| Scenario | avg / p95 / p99 ms | Within 7.7 ms |
|---|---|---|
| Traversal (197 m, no enemies) | 3.10 / 5.56 / 7.78; 3.05 / 5.17 / 8.19; 4.09 / **7.90** / 11.20 | 2 of 3 (trial 3 started at 42% CPU) |
| Dense normal combat (after the fix) | 4.07 / 6.86 / 11.38; 4.15 / 7.20 / 11.51; 3.99 / 6.70 / 11.26 | 3 of 3 |
| Overload (saturation, not normal combat) | 349 / 676 / 823, only 58 frames | Invalid capture (fewer than 300 frames) |

**Measurement notes.**
- **CPU vs GPU:** the stage timers are CPU wall time. GPU time was not measured
  separately, so no GPU bottleneck is claimed.
- **Memory:** `Performance.MEMORY_STATIC` peak (engine static allocations, not process RSS).
- **Overload:** 35.8 ms of simulation per tick, dominated by effects (detonations). It is
  still slow and was out of scope here.

## 6. Warnings and leaks

**Exit leaks: fixed.** `--verbose` named an `AudioStreamWAV` and its playing
`AudioStreamPlaybackWAV`. `AudioMix._streams` is a static cache that outlived the scene
tree. `AudioMix._exit_tree` now stops both players and clears the cache. Afterwards a
verbose shutdown, the Simulation suite (which restarts and dies) and the exported build all
report 0 leaks. The remaining "Orphan StringName: BAYER" line is an engine-level message,
not a leaked object.

**UID warnings: documented, not repaired.** `warnings/uid_mismatches.json` lists 146
references in 29 Binbun scenes:
- **64 targets: inconsistent in the pack itself.** The pack's `.uid` files, in Sir's
  original download, disagree with the UIDs its own scenes reference. Binbun shipped them
  that way.
- **1 target wanted under two UIDs:** `shared/guy/animation/idle.anim`.
- **36 references to paid-edition scenes** that don't exist. Only the free demo scenes
  mention them, and those demo scenes are excluded from export.
- **The game itself:** the 8 scenes it loads have 36 mismatched references, and every one
  falls back to a script or shader that exists.

Repairing would mean rewriting vendor files to UIDs their own `.uid` files contradict, so
it is left for Sir to decide. `uid_plan.txt` lists each target with its reason.

## 7. Delivery

`Launch.cmd` starts `..\RECompile-FPS-build\RECompile.exe`. It was rebuilt on 2026-11-14
at 03:00 with the existing "Windows Desktop (encrypted)" preset and 4.7.2 templates, with 0
export errors. A smoke test of that exact file (`--headless --quit-after 240`) gave 0
errors and no leaks. Its SHA-256 is in `summary.json`.

## Still open

- **Traversal at load:** it exceeds the budget when the machine is busy (trial 3).
- **Overload:** the saturation case is still far over budget, dominated by detonation
  effects.
- **First-launch hitch:** the first 4 casts each create a new projectile visual, up to
  25 ms. Pre-warming the pool would remove it; not measured or changed here.
- **Vendor UID warnings:** Sir to decide whether to repair them.
