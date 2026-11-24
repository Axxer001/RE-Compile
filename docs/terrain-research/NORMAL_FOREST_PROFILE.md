# Normal forest performance investigation

RE:Compile is an aimed fantasy roguelite. Optimize its intended traversal and encounters before using a 250-active crowd stress case to choose production work.

## Controlled workload

Use `crowd_profile.tscn --scenario=traversal --residents`: the production forest roster and activation logic, a fixed seed selected by the existing dense-map scan, the same scripted route through expanded clearings, high graphics settings and real GPU timing. No forced mass aggro or 250-enemy combat override. Player invulnerability prevents the benchmark ending early; spawning is disabled after the roster reset to hold the initial population constant. The initial roster and sampled active/dormant counts are recorded.

`profile_crowd.py --scenario traversal` runs one traversal per variant. The `count: 0` directory/runner label means no forced crowd count; use `metrics.workload.initial_roster` and `requested_enemies` for the actual resident population. The `no_residents` control deliberately parks all enemies.

Initial roster size is measured, not forced to the old 224 constant: quiet-start placement, unsafe candidates and page guardians can affect actual population. Every sampled tick must preserve that initial population. Tests also require movement, no casts, a living player and gameplay input context. GPU data, frame samples and source hashes must be present, and engine/script errors invalidate the run.

## Isolation switches

- `baseline`: full production forest and initial residents.
- `no_tree_detail`: detailed trees hidden, far impostors allowed close to camera.
- `no_far_trees`: far impostors hidden; detailed trees remain.
- `no_tree_collision`: tree physics bodies removed; tree visuals and navigation obstacles remain.
- `no_residents`: the same forest without live residents.
- `no_grass`: grass hidden; its chunk update logic remains.

All switches are benchmark-only. Missing trees, absent residents and non-solid trunks are not acceptable game optimizations. Scripted inputs are identical, but combat and knockback can alter the exact camera trajectory; compare movement and population alongside timing. CPU/GPU measurements overlap and should not be added into a synthetic total.

## Harness correction

The first capture in `evidence/forest-profile/isolation` was rejected: `reset_run()` restored normal health and enabled spawning after the harness had configured protection. The player died and the roster grew from 223 to 224. Its 14.599 ms p95 is not a valid full-route baseline. Corrected captures live in `isolation-fixed`: protection and disabled spawning are applied after reset. Production health and spawning were not changed.

The initial `no_residents` control also proved unsuitable for attribution despite passing the general workload checks: `park_enemies()` hides bodies but calls `set_dormant(false)`, leaving hidden animation players active. Its roughly 24.7 ms p95 does not measure the cost of removing all resident work. Exclude those controls in `isolation-fixed` and `reverse`; use the fully reserved control after its dedicated animation/reserve assertions are added. Other variants do not use `park_enemies()` after the roster reset and are unaffected.

## Reproduction

`python tools/profile_crowd.py --out evidence/forest-profile/new-run --scenario traversal --variants baseline no_tree_detail no_far_trees no_tree_collision no_residents no_grass`

Use a fresh output directory. Runs are sequential and pin project source hashes. The dense-seed scan precedes warmup and is not game cold-load time. Require repeated comparisons before claiming an optimization.

## Verified traversal results (2026-11-16)

Ryzen 5 6600H / RTX 2050, Godot 4.7.2, high settings, internal 640×360, seed 1. The production roster contained 188 Sprites, 32 Rangers and 3 Mortus (223 total); the baseline had 16–22 active and 201–207 dormant residents. It covered 197.7 m, with no casts and no deaths. The player is invulnerable for measurement; these are traversal/AI-encounter captures, not an aimed mixed-roster firefight.

| First isolation sweep | Frame p95 ms | Render CPU p95 ms | GPU p95 ms | Session mean ms/tick |
|---|---:|---:|---:|---:|
| Full forest | 16.957 | 4.746 | 2.417 | 5.95 |
| No detailed trees | 16.724 | 4.680 | 1.527 | 5.94 |
| No distant tree images | 14.690 | 2.267 | 2.220 | 6.11 |
| No tree collision bodies | 16.963 | 4.940 | 2.416 | 5.83 |
| Grass hidden | 16.302 | 4.430 | 2.154 | 5.97 |

The reverse-order distant-tree comparison used identical source hashes: no distant tree images measured 14.327 ms frame p95 / 2.291 ms render CPU p95; full forest measured 18.047 / 5.051 ms. Draw-call p95 fell from 2,859–2,864 to 830–839 across the two comparisons. CPU render work changed much more than GPU time. This supports a repeatable cost from submitting the existing fine-grained distant-tree batches; it does not prove that any particular rebatching implementation will achieve the same saving.

The tree-detail and collision controls did not materially improve total frame time. The grass result is small and not replicated; it does not justify removing grass. The population control is reported separately because the first version left hidden animations running.

Recommended next rendering prototype: consolidate distant-tree submission into larger batches while retaining the existing near-detail handoff and all tree positions. Validate camera motion, hill views, detail-distance settings and the opt-in streaming fallback. Do not simply hide distant trees or enlarge existing cells without checking their distance-based fades: changing batch bounds can make trees disappear at the handoff.

No production renderer, tree collision, population, graphics setting or game balance was changed during this profiling pass. The 7.7 ms frame-time target remains unmet even with all distant tree images hidden.

## Corrected population control

`reserved-control` uses the existing `_to_reserve` helper for every actor and asserts at the end that all are reserved, dormant and have inactive animation players. The control passed: 10.684 ms frame p95 and 2.819 ms mean session tick time, compared with 17.980 ms / 6.410 ms for its full-roster baseline. This is a separate comparison from the distant-tree controls; do not add their savings together.

The control removes actor updates, models, animations and actor collision together, so it establishes a resident-related cost rather than a precise AI-only cost. Preserve the intended roster in production. Repeated status/presentation work and actor/effects loops remain CPU targets alongside distant-tree submission.

## 20-enemy spell-combat check

The existing controlled combat workload at 20 active enemies measured 14.986 ms frame p95 with the full forest and 13.606 ms with distant tree images hidden (`combat-20`). GPU p95 was 4.380 versus 4.239 ms. Both captures passed workload checks, maintained 20 active enemies and normal firing, and had no engine/script errors. This single pair supports the direction of the traversal result but does not establish a precise combat saving. It uses the benchmark's first 20 Sprites, not a representative mixture of Rangers, Mortus and Sprites.

## Outcome and next implementation

The profiling task is complete: distant-tree submission is a repeatable rendering cost, and resident-related work is a separate CPU cost. Prioritize a distant-tree batching prototype that preserves scenery and the detail handoff; follow with targeted resident/effects/presentation CPU profiling. Shrinking the map, removing tree collision or stripping close-up tree detail is not supported by these measurements.

Only test harnesses and this report changed. Retained captures passed their workload/evidence checks; the rejected initial traversal and two semantically flawed population controls remain clearly identified above. No production optimization was enabled by these removal experiments. No exported build, long soak, mixed-roster player-cast combat suite or new visual-fidelity test was run; visual validation is required for any subsequent batching change.
