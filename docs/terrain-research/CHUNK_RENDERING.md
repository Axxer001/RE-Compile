# Camera-local detailed tree chunks

Adapt the section residency and incremental build ideas used by Minecraft renderers using existing Godot MultiMeshes. No Minecraft code or assets are copied.

Scope: `dark_forest.gd` constructs tree transforms and far impostors; `tree_chunks.gd` owns detailed chunk residency; `set_tree_distance` updates both cached geometry and fallback visibility. World layout, collision, navigation, grass and enemies retain their existing behavior. No save or content migration.

Detailed chunks load within detail distance plus a guard band, are built incrementally, and remain cached through a larger eviction radius. Far impostors cover unloaded chunks, including camera teleports. Missing impostor assets retain the eager renderer. **Experimental opt-in: `RC_STREAM_TREES=1`.** The existing eager renderer remains the default because the paired GPU results below did not establish a repeatable gain. `RC_EAGER_TREES=1` forces eager construction even when the stream flag is present.

Checks: initial residency, bounded cache, teleport fallback, revisit, live distance changes, existing forest runtime and visual checks. Compare eager and streamed construction and populated traversal on the same source and hardware. This does not establish the separate 250-active-enemy performance target.

Ground remains a single 31,250-triangle mesh and collision remains resident. Splitting these is deferred until measurements justify the extra draw calls and physics lifecycle complexity.

## Implementation details and limits

- Existing 10 m cells and deterministic tree transforms are reused. Only detailed tree geometry has a residency lifecycle; all far impostors remain resident.
- Default detail distance is 40 m; load radius is 76 m and retention radius is 96 m. Refresh runs after 2 m of camera movement. Initial camp detail is built synchronously.
- Nearest missing cells build first. The 1.5 ms construction budget is checked between cells: one cell can exceed it. Eviction and queue selection are outside that budget. Teleports can therefore still hitch; this is not a hard frame-time guarantee.
- An unloaded cell's impostors have no minimum visibility distance. The usual detail/impostor cross-fade is restored only after its detailed geometry exists. Live settings update both representations.
- Missing impostors select eager construction. `RC_EAGER_TREES=1` also selects eager construction for measurement; it is not a player-facing setting.
- No background Godot scene-tree mutations or new dependencies are introduced. Ground heights, spawn placement, physical tree bodies, navigation and enemy simulation are unchanged by this slice.

## Design references

[Sodium section manager](https://github.com/CaffeineMC/sodium/blob/dev/common/src/main/java/net/caffeinemc/mods/sodium/client/render/chunk/RenderSectionManager.java) is a reference for queued section construction. It is a Minecraft mod, not evidence that every Java vanilla implementation is identical.

[Godot MultiMesh documentation](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) explains why small spatial batches matter: individual instances within one MultiMesh are not independently culled. [Godot visibility ranges](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html) supply the existing detail/impostor handoff.

## Verification

- `test_tree_chunks.gd`: residency, unloaded fallback, teleport eviction, distance settings, bounded revisits passed.
- `test_forest_runtime.gd`: all 9 checks passed, including 224 residents, spawn clearance, navigation and hill collision.
- `terrain_500.tscn`: all 17 checks passed with no engine/script errors in `evidence/tree-chunks-render-isolated.log`. Covers actual camera tracking, queue completion and bounded residency at camp, hill and south; settled hill capture inspected visually.
- After the final opt-in gate change, all 17 visual checks passed again with zero engine/script errors (`evidence/tree-chunks-render-optin.log`); the focused tree-cache check also passed again.
- Two intervening GPU attempts failed under memory pressure during startup, before the camera assertions. Logs are retained; those attempts are not successful validation or timing samples. A later isolated run passed without changing production code.
- No full simulation-suite rerun, exported build, prolonged soak or 250-active-combat rebenchmark in this slice.

## Paired GPU results (2026-11-15)

RTX 2050, Ryzen 5 6600H, Godot 4.7.2, high preset at internal 640×360. Both runs used seed 1, 10,299 trees and unchanged production source within each capture set. Traversal had 224 residents, roughly 17–41 active, across about 187 m; this is not a 224-active-combat workload.

| Metric | Pair 1 eager | Pair 1 streamed | Pair 2 eager | Pair 2 streamed |
|---|---:|---:|---:|---:|
| Traversal p95, ms | 27.086 | 17.254 | 27.320 | 30.958 |
| Warm rebuild CPU, ms | 1189.710 | 1397.378 | 1427.846 | 1339.193 |
| Scatter stage, ms | 466.907 | 556.774 | 600.305 | 541.790 |
| Rebuild through first draw, ms | 1398.224 | 1599.846 | 1713.776 | 1527.318 |

Pair 1 ran eager first; pair 2 ran streamed first. All eight captures passed workload validity checks with no engine/script errors. Sources and logs are retained under `evidence/tree-chunks` and `evidence/tree-chunks-reverse`. The final default/opt-in gate was changed after these captures; the two rendering algorithms were not changed.

**Decision: do not enable streaming by default.** Timing results are inconsistent, and neither mode meets the 7.7 ms traversal or 200 ms build target. Do not claim a measured speedup from the best sample. The implementation provides bounded detailed geometry and a tested fallback, but it is not full world streaming.

Next useful work: capture renderer/CPU stage timings under stable system memory conditions; distinguish visibility traversal, GPU tree/fog cost, physics and enemy updates before choosing the next optimization. Profile cell selection, eviction and whole-cell uploads before promoting this experiment. Ground/collision streaming and large active crowds remain separate work.
