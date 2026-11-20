# 250 m forest revision — 2026-11-16

This implements the user's smaller, less crowded, path-free forest direction and supersedes the earlier 500 m target. Historical performance captures remain historical; they do not measure this revision.

## Settings and behavior

| Setting | Current behavior |
| --- | --- |
| World bounds | 250 × 250 m; one quarter of the previous area |
| Hostile population target | 64 total, including Ghouls and Mortus; safe-placement exclusions can produce fewer |
| Replenishment | At most one successful respawn every 8 seconds, subject to existing safety checks; movement arena retains 4 seconds |
| Sprite activity | 12 idle Sprites selected for activity; fighting enemies are not forcibly put to sleep |
| Spawn zones | 24 distributed zones, with smaller Sprite packs, Ghoul pairs and page guards |
| Tree grid spacing | Seeded 6–7.5 m, formerly 4–5.2 m; jitter and regional thinning retained |
| Rocks | Distributed across the resized 5 × 5 grid of 50 m sectors |
| Pathways | Empty path network: no painted strips, vegetation corridors or terrain flattening along paths |
| Hills | Broad seeded hills replace the former flat core and flattened clearings |
| Camp exception | A 20 m radius remains level for fixed props and the training portal, blending into hills by 50 m |
| Surface | 65 × 65 vertices with exact 250 m bounds; rendering, collision and navigation share heights |

Pages, spawn zones and initial enemy positions now sample the terrain height. Performance fixtures also ground their positions on the resized surface. The render fixture retains its historical `terrain_500` filename for compatibility, but its cameras now lie within 250 m bounds.

## Validation

Evidence is in `evidence/forest-250/`:

- `simulation-final.log`: **913 checks passed**. Earlier failures from arena respawn timing and old flat-ground/full-pack assertions were corrected before this run.
- `content.log`: **200 checks passed**, including placement/spacing validation over **1,000 seeds**.
- `test_forest_expansion.log`: **403 checks passed** across **100 seeds**. Observed **754–1,182 trees**; trees and rocks present in every 50 m sector; decoration centres in bounds; pages and zones grounded; both triangles of every terrain cell below the 45-degree walkability limit; former flat-core locations elevated.
- `navigation.log`: **50 checks passed**. Includes real navigation from camp to all pages and all zones across **20 seeds**, initial spawn clearance, no initial actor overlaps, sleeping/waking residents, hill collision agreement and player grounding.
- `test_terrain_surface.log`: **4 checks passed** for deterministic heights and surface behavior.
- `run_terrain_ready.log`: **17 checks passed** for terrain-aware gameplay helpers.
- `render.log`: **8 GPU render checks passed**. Camp, hill and south screenshots were visually inspected.
- `git diff --check`: passed.

The data placement validator alone does not prove connectivity now that the protected path network is gone; the navigation test provides the separate sampled evidence. This is not an exhaustive connectivity proof over all possible seeds.

## Limits and next check

No new FPS benchmark, exported-build test or long gameplay soak was run for this revision. Cold initial construction in the standalone runtime captures still exceeded 200 ms (about 367–611 ms); the regression suite's warmed generation/build check passed. Smaller geometry and fewer residents reduce workload, but no frame-rate improvement is claimed without a new timed capture.

Existing imported VFX UID fallback warnings and exit object-leak warnings remain in some logs. Next performance measurement should use the new map and roster, and verify that the traversal route actually moves around trees now that protected pathways are removed.
