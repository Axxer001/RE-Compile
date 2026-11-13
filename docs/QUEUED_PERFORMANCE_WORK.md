# RE:Compile — queued performance and verification work

Prepared: 2026-11-14 (Asia/Manila).
Project: `C:\Users\Axxer\Documents\Codex\2026-11-08\how\outputs\RECompile-FPS`

## Instruction for the next session

Read this checklist and the current source before editing. Work in the order below. Reuse existing code and test runners; optimize only measured bottlenecks. Keep gameplay behavior, collision rules, accessibility and the current performance thresholds intact. Record failures honestly. Do not change thresholds to obtain a PASS. Run benchmarks sequentially, never alongside imports or other verification jobs. Do not overwrite the player's saved profile. Do not reverse engineer Minecraft mods as part of this queue.

## Verified starting point

- Current runtime is the first-person Dark Forest / Grimoire prototype, not the archived campus/shooter game.
- Navigation optimization is already implemented in `scripts/world/navigation_grid.gd`. It hoists repeated calculations out of the cell loop; do not redo it.
- Paired dense-seed navigation measurements showed roughly 74% lower rebuild time. Every cell matched the original implementation on both 600×600 grids; empty rebuild clearing also passed.
- Latest simulation run: 685 checks PASS. Existing imported-asset UID warnings and object leaks at exit remain.
- Focused combat profile: movement 0.269 ms/tick, casting 1.592 ms/tick. Casting accounts for roughly 84% of the broader player update in this diagnostic.
- End-to-end loading and gameplay FPS have not been remeasured after the navigation optimization.
- Normal-rate combat previously produced p95 7.48–14.54 ms; traversal 6.05–8.15 ms. Existing p95 target: 7.7 ms.
- Projectile saturation is an artificial overload scenario, not ordinary player firing. Its effects cost must not be presented as normal gameplay performance.

Evidence:
- [Baseline report](performance-baseline-2026-11-14.md)
- [Navigation optimization and focused profile](priority-profile-2026-11-14.md)
- [Earlier review fixes](review-fixes-2026-11-13.md)
- `evidence/priority-profile/run.log`
- `evidence/priority-profile/navigation.log`
- `evidence/priority-profile/simulation.log`
- `evidence/baseline-summary-20261114.json`

## 1. Preflight and benchmark correctness

- [ ] Check for applicable AGENTS.md instructions and concurrent changes. Confirm the active project and source version; record hashes or Git commit if available. The project previously had no Git repository.
- [ ] Check no benchmark/editor/import process from a previous run is still active. Stop only task-owned processes where needed.
- [ ] Read `tests/performance/baseline.gd`, `stress.gd` and `navigation_compare.gd` before reuse.
- [ ] Verify the profiling subclass's copied `simulate` method still matches `scripts/main.gd`. It currently duplicates that method for timing; synchronize it when the production method changes.
- [ ] Record CPU/GPU, driver, engine version, renderer, internal and physical window resolution, power mode, seed, and relevant settings. Keep the rendered window visible and avoid minimization/occlusion while measuring. Record thermal/background-load limitations.
- [ ] Preserve chronological frame samples. The baseline runner currently sorts its frame array before saving CSV; save the original sequence and sort a copy for percentiles.
- [ ] Add/verify actual workload counters: casts, live enemies, projectiles before/after update, player alive state, simulation ticks and distance traveled. A capture is valid only when the intended workload actually occurred.
- [ ] Keep validity separate from performance acceptance. Baseline PASS currently means workload/capture checks passed, not that p95 met 7.7 ms. Report both explicitly.
- [ ] Align stage timing windows with the warmed frame sample, or label clearly that current stage timers include warm-up.

Acceptance: a runnable benchmark with explicit scenario identity, preserved raw samples, reproducible settings, and no silent success when the player dies, input fails, a script errors, or evidence cannot be written.

## 2. Profile casting before changing it

Relevant files:
- `scripts/combat/player_combat.gd`: `simulate`, `cast_basic`, `crosshair_point`, `hand_origin`
- `scripts/combat/combat_controller.gd`: `advance`
- `scripts/combat/projectile_service.gd`: `launch`, visual allocation/reuse
- `scripts/render/vfx.gd`
- `tests/performance/baseline.gd`

- [ ] Split casting timing into combat advance/resource updates, aim/target queries, hand-origin work, projectile launch, and visual creation/reuse.
- [ ] Record call counts and total/maximum time; distinguish per-tick cost from occasional cast spikes.
- [ ] Run three normal-fire combat trials sequentially with the same dense seed and settings. Use the existing normal input/router/session path, not manual projectile saturation.
- [ ] Identify the dominant measured substage. Do not assume movement collision, raycasts or rendering is the cause.
- [ ] Search every caller before changing shared code.
- [ ] Implement the smallest behavior-preserving fix for that measured cost. Prefer existing pools, cached immutable resources and existing engine facilities. Add no speculative threading framework or new dependency.

Acceptance: a named hot path supported by timings and call counts, plus a narrowly scoped change whose before/after measurements use the same workload. If no reliable gain is demonstrated, remove the attempted optimization and document the finding.

## 3. Regression checks for any casting change

- [ ] Preserve basic/special damage, aim direction, wall blocking, target selection and hand origin.
- [ ] Preserve attack interval, fractional-rate scheduling and the rule that idle input cannot bank casts.
- [ ] Preserve cooldowns, MP costs, slot restrictions, casts interrupted by movement states, pause and input focus behavior.
- [ ] Preserve projectile limits, effect lifetime, pooling reset, death/restart cleanup and damage deduplication.
- [ ] Add one targeted regression for the changed logic, including the relevant edge case.
- [ ] Run Content and Simulation suites. Inspect explicit RESULT status, process exit, error lines and timeout; exit code alone is insufficient.
- [ ] Run rendered verification if visual creation, animation, effects or attachment changed.

Acceptance: targeted regression passes, all required suites pass, no new engine/script errors, and no gameplay rule weakened to reduce cost.

## 4. Validate navigation and end-to-end loading

- [ ] Run `tests/performance/navigation_compare.gd` again after relevant changes.
- [ ] Extend cell-equivalence coverage beyond seed 60: several forest seeds, overlapping boxes, map edges, exact agent-radius boundaries, height-filter boundaries, empty rebuild, and changed obstacles after a previous rebuild.
- [ ] Check standing and climbing grids independently; retain diagonal corner-cutting and reachable page/spawn behavior.
- [ ] Measure three complete rebuilds including generated data, scene/scatter creation, both navigation grids, physics registration and first rendered frame.
- [ ] Label warm rebuild versus cold process launch; do not call first-draw latency pure generation time.
- [ ] Compare end-to-end results with the historical evidence. Do not claim the 74% navigation improvement applies to total loading time or FPS.

Acceptance: cell/path behavior remains equivalent and total loading measurements identify where time is now spent.

## 5. Repeat gameplay performance acceptance

Run three trials per scenario, sequentially, with consistent settings:

| Scenario | Required workload and checks |
|---|---|
| Generation/loading | Same seed, separate warm/cold labels, stage timing plus first drawable frame |
| Traversal | Normal fixed-step movement, actual traveled distance, no enemy workload |
| Dense normal combat | 20 live enemies, normal player firing rate, confirmed casts, player alive; disclose benchmark immunity and persistent ring |
| Optional overload | Explicitly named saturation test; never substitute for normal combat |

- [ ] Use at least the existing 3-second warm-up and 20-second sample; retain all valid trials, including slow ones.
- [ ] Report per-trial average, p95, p99, frame count, simulation cost, load counts and memory metric definition. Use longer samples if too few frames make tail percentiles unstable.
- [ ] Compare against the unchanged 7.7 ms p95 target; report failures rather than averaging them away.
- [ ] Separate CPU stage measurements from GPU timing. Do not infer a GPU bottleneck from frame time alone.
- [ ] Confirm no profile files were changed by the runner.

Acceptance: honest, reproducible before/after evidence. A valid run may still fail the performance target.

## 6. Investigate existing warnings separately

- [ ] Inventory asset UID warnings. Confirm each fallback path resolves to the intended asset before repairing UID references; do not mass-rewrite imported assets blindly.
- [ ] Run the relevant exit path with verbose diagnostics to identify leaked instances. Fix ownership/cleanup only after identifying them.
- [ ] Verify restart and shutdown after any cleanup change, including pooled effects, signal connections and RefCounted cycles.

Acceptance: resolved warnings/leaks have explicit evidence; unresolved ones remain documented. Keep these changes separate from performance changes where possible.

## 7. Closeout and playable delivery

- [ ] Update the current README, verification notes and this checklist with actual results and remaining work.
- [ ] Save logs, raw timings, settings, source hashes and concise before/after tables under a new evidence directory.
- [ ] Log the session in Irminsul, subject to filesystem permissions.
- [ ] Verify which executable `Launch.cmd` selects. It prefers an exported build that may be older than current source.
- [ ] If delivering a new executable, check the existing export preset/templates, rebuild it, and smoke-test that exact exported artifact. Otherwise explicitly state that only source was updated.

## Commands

Run from the project directory. Use `godot_console` or the installed Godot 4.7.2 executable; run each command separately. GPU scenarios require a desktop display, not `--headless`. Create a unique output directory before each benchmark.

```powershell
# Import and parse
 godot_console --headless --path . --editor --quit

# Existing verification wrapper (runs its own import stage)
 powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1 -Suite Content
 powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1 -Suite Simulation

# Navigation equivalence and paired timing
 godot_console --headless --path . -s res://tests/performance/navigation_compare.gd

# Scenario examples: create each output directory first; repeat with unique names
 godot_console --path . res://tests/performance/baseline.tscn -- --scenario=generation --out=evidence/queued-generation-1
 godot_console --path . res://tests/performance/baseline.tscn -- --scenario=traversal --out=evidence/queued-traversal-1
 godot_console --path . res://tests/performance/baseline.tscn -- --scenario=combat --out=evidence/queued-combat-1
```

## Explicitly outside this queue

Minecraft mod reverse engineering; engine migration; new procedural terrain/structure features; lowering quality or performance thresholds; rewriting the movement system without evidence; purchasing or installing games. This document schedules no automation by itself.
