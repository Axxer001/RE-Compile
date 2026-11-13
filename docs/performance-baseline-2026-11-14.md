# RE:Compile baseline — 2026-11-14

Three sequential runs per scenario, no overlapping verification jobs. Godot 4.7.2, Forward+, RTX 2050 selected in runtime logs, viewport 1920×1080, seed 60. Vsync disabled, FPS uncapped. Traversal/generation ran November 13; combat ran November 14. Driver power state, thermals, physical window visibility, background OS load and GPU utilization were not controlled or recorded. These are local diagnostic baselines, not a hardware comparison.

The runner uses the normal fixed-step session and synthetic physical-key input. Traversal parks enemies. Combat keeps 20 enemies alive, grants the player immunity, steers along the same route, holds normal attack input, and includes one persistent zero-damage Ring of Fire. Player immunity removes damage reactions; enemy crowding can restrict travel. This is controlled gameplay, not a human playthrough. Generation measures rebuilding an already initialized world (warm assets), not cold launch or streamed terrain.

| Scenario | Average frame ms (three runs) | p95 ms (three runs) |
|---|---|---|
| Traversal | 4.64, 4.36, 3.96 | 7.82, 8.15, 6.05 |
| Normal-rate dense combat | 6.09, 4.31, 4.79 | 14.54, 7.48, 8.66 |
| Synthetic projectile saturation | 463.60, 563.46, 428.45 | 945.67, 1027.23, 782.54 |

## Generation breakdown

| Stage | Three runs, ms |
|---|---|
| data_ms | 16.77, 21.06, 15.84 |
| scatter_ms | 60.67, 80.58, 54.62 |
| navigation_ms | 141.62, 308.48, 132.99 |
| cpu_total_ms | 219.07, 410.12, 203.45 |
| through_first_draw_ms | 2743.71, 3674.76, 2287.43 |

Navigation accounts for roughly 65–75% of measured CPU rebuild cost. First-draw latency additionally includes renderer/physics scheduling and startup warm-up; it is not pure terrain generation. Both navigation grids cover 150×150 m at 0.25 m cells (360,000 cells each).

## Stage profiling

Combat stage timers include warm-up; frame percentiles exclude the first three seconds and cover approximately 20 seconds. Timers are CPU wall durations, not GPU timings. Normal-fire combat's largest measured simulation stage is `main.simulate` (player movement, casting, footsteps and interactions), not enemy AI.

- normal_combat: mean milliseconds per tick across each run: player 2.350, 1.844, 2.090; actors 0.903, 0.680, 0.750; effects 0.984, 0.704, 0.794; publish 0.506, 0.376, 0.416.
- overload: mean milliseconds per tick across each run: player 1.942, 2.024, 1.855; actors 0.821, 0.769, 0.626; effects 40.973, 39.071, 31.334; publish 1.022, 0.854, 0.686.

Saturation refills the 64-projectile pool every physics tick, potentially much faster than normal casting. It produced only 37–47 frames per sample; p95/p99 are coarse at that count. Effects dominate this artificial overload. Do not describe these numbers as ordinary combat FPS. The corresponding logs label this older fixture `combat`; the current runner names it `overload`.

## Conclusions and next work

- Normal combat exceeds the existing 7.7 ms p95 budget in two of three trials; traversal in two of three. Suite PASS means valid capture and workload checks, not meeting that performance target.
- Profile the player/controller path during crowded combat next; its stage includes more than collision, so collision is a hypothesis, not an established root cause.
- For map loading, profile the two navigation rebuilds independently before changing grid resolution or introducing threads.
- For overload robustness, investigate projectile detonation/VFX workload and sustainable spawn budgets. Do not remove required gameplay behavior just to pass an artificial saturation test.
- No Minecraft reverse engineering is justified by these results yet.

Excluded runs: stationary traversal caused by incorrect input injection, combat after player death, a profiler parse failure, and a live-combat run rejected only for a low frame count. All preserved as diagnostic evidence, not mixed into the table. No production optimization or exported-build update was performed.
