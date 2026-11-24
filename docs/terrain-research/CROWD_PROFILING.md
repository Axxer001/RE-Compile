# Active-crowd performance investigation

Design constraint: RE:Compile is an aimed fantasy roguelite. Preserve responsive aiming, combat timing, readable enemy attacks and spell/status feedback when reducing CPU work.

## Scope and method

Reuse `baseline.gd`'s fixed scene, seed, workload and active-population validation. `crowd_profile.gd` adds diagnostic variants and engine render measurements without changing gameplay scripts. `profile_crowd.py` runs sequential captures, removes inherited RC diagnostic flags, pins source hashes and rejects engine errors or invalid workloads. The default tree renderer stays eager.

Measure 20 and 250 genuinely active enemies, then remove one presentation cost at a time at 250. Diagnostic variants are not acceptable gameplay settings or proof of optimization: invisible enemies and frozen animations would break the intended experience.

Variants: no shadows; no fog (regular and volumetric); far tree impostors only; hidden enemy models (actors remain visible/active); stopped enemy animation playback; zero full burn FX slots (glow/status effects remain); particle drawing suppressed (particle simulation remains).

Render CPU sums root and low-resolution world viewport render CPU plus frame setup. GPU sums both viewport GPU measurements. Physics monitor values include engine and script work; existing stage timers measure session work. These overlapping measures must not be summed as a frame breakdown. The physics monitor is engine-aggregated, not a per-actor collision timer.

Source: [Godot RenderingServer timing documentation](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu). The GPU clock can change under varying utilization, so repeat large comparisons before selecting a production fix.

## Reproduction

From the project directory, run `python tools/profile_crowd.py --out evidence/crowd-profile/new-baselines` for 20/250 baselines. Use `--counts 250 --variants no_animation no_enemy_models no_shadows no_fog no_tree_detail no_burn_fx no_particle_draw` with a new output directory for isolation runs. Requires the actual GPU display. Each run includes a benchmark-only density scan before warmup; process uptime is not game cold-load time.

Raw logs, source hashes, chronological frame samples, population history, CPU stages and render timing summaries stay in the selected output directory. A PASS means the workload happened and timing evidence exists, not that the 7.7 ms frame budget passed.

## Baseline findings (2026-11-15)

RTX 2050, Ryzen 5 6600H, Godot 4.7.2, internal 640×360, high preset, seed 1. Baseline captures are in `evidence/crowd-profile/baselines`.

| Metric | 20 active | 250 active |
|---|---:|---:|
| Frame p95, ms | 14.791 | 216.583 |
| GPU p95, ms | 3.848 | 7.457 |
| Render CPU p95, ms | 2.902 | 11.366 |
| Session simulation mean ms/tick | 3.868 | 14.752 |
| Simulation ticks / rendered frame | 0.59 | 7.96 |
| Actors mean ms/tick | 0.592 | 4.090 |
| Combat effects mean ms/tick | 0.931 | 4.188 |
| Publishing mean ms/tick | 1.756 | 4.700 |
| Player mean ms/tick | 0.485 | 1.687 |

Player timing includes movement and casting; do not sum those nested timers again. The 250 case retained exactly 250 active, aggroed enemies with none dormant throughout the sample. It is a dense combat stress case: the player becomes blocked by the crowd, and movement distance was zero. It is not representative of dispersed residents across the entire map.

GPU work alone cannot explain the 250-enemy frame delay. Nearly eight simulation ticks per rendered frame indicates persistent catch-up work. Actor, effects and presentation costs repeat during those ticks. This identifies a CPU/simulation problem, but does not yet isolate native physics cost from script cost.

The profiler switch `--script-profile` emits Godot's built-in function timings to the run log. Use a separate output directory: those frame times include profiler overhead and must not be compared as an optimization result.

## Visual and animation isolation

All seven captures in `evidence/crowd-profile/isolation` passed 14 workload/evidence checks with zero engine/script errors and exactly 250 active enemies. One capture per variant: modest differences can be noise and do not establish a ranking.

| Removed work | Frame p95, ms | GPU p95, ms |
|---|---:|---:|
| Nothing (baseline) | 216.583 | 7.457 |
| Enemy animation playback | 220.171 | 6.510 |
| Enemy model drawing | 206.280 | 5.117 |
| Shadows | 231.669 | 5.074 |
| Regular and volumetric fog | 224.449 | 7.284 |
| Detailed trees (impostors retained) | 211.580 | 6.383 |
| Full burning-enemy FX (glow retained) | 203.423 | 6.681 |
| Particle drawing (simulation retained) | 235.297 | 5.746 |

None removed the large crowd slowdown. Keep production graphics unchanged. These are elimination diagnostics, not acceptable fixes: hiding enemies or freezing animations would violate gameplay/presentation requirements.

## Function profile and first targeted change

`functions-debug/250-baseline/run.log` contains a validated native Godot script profile (`--debug --profiling`), with `hot-functions.json` summarizing its last 20 emitted frame snapshots. These are sampled, instrumented frames, not unbiased wall-time benchmarks. Inclusive times overlap; profiler wrappers and dynamic calls can double-count nested work, so do not sum them.

The snapshots averaged eight simulation ticks each. `_show_burning` accounted for about 28 ms inclusive per snapshot, `_tick_rings` about 23 ms, and `combat_targets` about 17 ms. One snapshot had 18,568 burn-sort comparator calls. The comparator previously read two world positions and calculated two squared distances every comparison.

The first change caches each burning enemy's squared distance once per call, then sorts the same actor array using those values. It retains the existing comparison, cap, flicker, dead/hidden/expired handling and camera focus. It does not change aiming, damage, AI, physics rate, model quality or the number of detailed flames.

The initial focused comparison ran six alternating old/new pairs, 300 calls per algorithm per pair with 250 burning actors. Before editing, the new/old time ratio was 0.942 and failed the 0.85 acceptance threshold. After the three-line change, all 12 initial behavior checks passed and the ratio was 0.744 (25.6% less CPU time for this isolated function). Camera and equal-distance cases were then added for final verification.

`functions/` is an earlier attempt launched without the local debugger. It emitted workload timings but no function profile; do not use it as function-level evidence. The runner now requires an accumulated profile marker when profiling is requested.

Other shared project changes landed between the original diagnostic captures and this resumed optimization. The burn-sort GPU comparison therefore uses a benchmark-only `legacy_burn_sort` variant on the same current source, rather than treating the earlier 216 ms result as a controlled before/after baseline.

## Final burn-sort validation

The final focused test passed 14 behavior checks, including camera focus, equal-distance ties, zero/one/six/all flame slots, movement, hidden/dead actors and expiry. Six alternating timing pairs produced 2,786,975 microseconds for the legacy algorithm and 2,090,009 for the optimized algorithm across 1,800 calls each: **25.0% less isolated CPU time**. Evidence: `evidence/crowd-profile/burn-selection-final.log`. This uses lightweight actor fixtures to isolate selection work, not a complete game frame.

| Same-source 250-active GPU capture | Legacy frame p95, ms | Optimized frame p95, ms |
|---|---:|---:|
| Legacy first (`burn-pair`) | 230.705 | 188.887 |
| Optimized first (`burn-pair-reverse`) | 153.478 | 163.147 |

All four captures passed 14 checks with zero engine/script errors. Both algorithms retain 250 active enemies. Results vary substantially and reverse order reverses the frame-time winner. **No reliable overall FPS improvement is established.** Keep the three-line change for its repeated, behavior-preserving reduction in the measured selection function; do not present it as fixing crowd performance. The 7.7 ms frame-time target remains unmet.

The next CPU targets are repeated presentation publishing during physics catch-up and repeated construction/scanning of combat target lists. Profile and verify each separately; preserve fixed-step combat timing, aiming response and effect feedback. Do not reduce simulation rate or silently deactivate nearby combatants as a substitute for optimization.

No export, prolonged soak or full simulation-suite rerun was performed for this three-line change. Functional scope was covered by the focused selection test and real 250-active combat captures. Shared unrelated changes were preserved.
