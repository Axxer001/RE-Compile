# Priority profiling and navigation optimization — 2026-11-14

## Measured player path

One normal-rate, 20-enemy combat diagnostic: 1,389 fixed ticks, movement 373,618 us (0.269 ms/tick), casting 2,210,558 us (1.592 ms/tick), total player path 2,631,158 us (1.894 ms/tick). Casting is 84% of this stage. Movement/collision was not the dominant cost, so no movement rules changed. Combat p95 9.591 ms is a diagnostic measurement, not evidence that navigation optimization changes gameplay frame times. Profile subclass mirrors main.simulate only to divide timing; keep it synchronized if that method changes.

## Navigation change

Hoisted the X-axis coordinate and box-distance calculation out of the inner cell loop. Removed repeated centre Vector3/Vector2 construction, helper calls and redundant per-cell height tests. Kept the original square-root comparison, strict radius boundary, grid size, cell size, height filtering, clearing and revision semantics.

Dense forest seed 60, 950 trees; paired old/new implementations in the same headless process, one warm-up plus three timed rebuilds each:

| Grid | Old ms | New ms | Median reduction |
|---|---|---|---|
| Standing | 112.729, 91.040, 97.396 | 32.811, 22.758, 25.857 | 73.5% |
| Climbing | 97.091, 106.811, 111.243 | 27.537, 27.314, 27.660 | 74.2% |

Compared every cell on both 600×600 grids: zero differences (720,000 comparisons). An empty rebuild also cleared every blocked cell. Full simulation suite: 685 checks PASS, no ERROR/SCRIPT ERROR/FAIL lines. Existing asset UID and exit leak warnings remain.

Evidence: evidence/priority-profile/run.log, navigation.log, simulation.log. Reproduce the paired comparison with `godot --headless --path . -s res://tests/performance/navigation_compare.gd`. The reference implementation is retained in this test only.

Next target: profile the casting path (aim queries, launch/visual creation and combat advance) separately. No claim that its cost is all collision or rendering. No Minecraft reverse engineering, gameplay changes, exported executable rebuild, or end-to-end loading/FPS improvement claimed. Timing comparison covers one dense seed; simulation regressions cover additional forest seeds.
