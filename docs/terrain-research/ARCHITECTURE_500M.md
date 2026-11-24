# 500 m forest architecture

2026-11-15. Approved scope: implement the four terrain/population requests, preserving current movement and combat. This document precedes implementation. Existing shared spell changes remain intact.

## Contracts

- Finite world bounds are (0,0)–(500,500) metres. Keep the existing camp and introductory page/parkour locations; extend connected clearings and paths through the remaining world. Training arena rules remain unchanged.
- A seed-owned terrain surface supplies `height_at(xz)` and mesh triangles from the same sampled heights. Rendering, collision, vegetation roots, navigation and spawn placement use that surface. No caves/stacked floors in this version. Clearings and required corridors are flattened and blended into hills; optional hills remain traversable within movement limits.
- Layout retains existing tree/rock/ledge arrays and page/zone dictionaries. Placement spans the world using stratified cells, bounded jitter, local profiles and minimum spacing. Required content precedes decoration. Seed failure retains the last playable layout. Distribution checks cover spatial sectors, not just total counts.
- Navigation keeps its existing query contract. The arena retains 0.25 m cells; forest cell size is selected explicitly to keep the expanded grid below the old cell count. Conservative obstacle rasterization and height-relative clearance prevent coarse cells from routing through trunks. Ground heights are returned in paths. Terrain slopes and traversable neighboring edges are validated.
- Reuse chunked tree MultiMeshes/impostors. Split far batches spatially; bound grass residency and ground it on the terrain. Collision is grouped spatially and must remain available around player and simulated actors. Rendering distance is not permission to remove gameplay collision.
- Forest capacity is 256 living actors with an initial/maintained target above 200, distributed among validated source slots. Arena remains 20/8. Living population, dormant population, simulated population and rendered models are distinct counters. Dormancy preserves identity/health, never resets rewards, and cannot apply to nearby/aggroed threats or active attacks. The close-crowd benchmark must count only actually simulated actors.
- Keep full combat/effect rules. Reuse the newer burn-presentation budget. Optimize stationary static-ground physics only when transform, ground state and navigation revision are unchanged; wake/movement/reset invalidate it. Do not change attack schedules or movement tuning to pass a benchmark.

## Implementation boundaries

`forest_terrain.gd`: deterministic height samples, interpolation, terrain meshes/collision.
`dark_forest.gd`: world topology, placement, validation and height-grounded scene construction.
`navigation_grid.gd`: explicit cell size and optional terrain-aware navigation, same public methods.
`grass_field.gd`: terrain-grounded blades and bounded deterministic cache.
`main.gd` / `blighted_sprite.gd`: forest population policy, activation/presentation, motion invalidation and spawn checks.
Existing simulation/render/performance runners: updated expectations for changed forest requirements, retained arena regression, new coverage/seam/height/population tests.

## Gates and order

1. Implement/test deterministic ground and connected expanded layout before enabling scene changes.
2. Integrate collision, navigation, vegetation and grass; check mesh/query agreement, slopes, routes, spawn grounding and sector coverage.
3. Enable >200 world population; verify no overlapping source slots, stable IDs, death/respawn and activation. Measure 250 simultaneously simulated enemies separately.
4. Run content/simulation/render plus generation, traversal and dense-combat captures sequentially. Keep 7.7 ms p95 target and existing 200 ms generation/build gate visible; fail rather than lower them. Report load/memory costs and content counts. A functioning large map is not proof of unchanged performance.

## Source-study application

DST supports separating topology from population, counted mandatory content from weighted decoration, and source population from active actors. Its queued wake/spawn and bounded generation retries inform lifecycle tests. Existing RE:Compile systems already provide most of these boundaries. Do not copy commercial Lua or infer native WorldSim/renderer algorithms. C2ME was inventoried, not reconstructed; no Java scheduling implementation is adopted.

## Risks

The shared working tree is active; changes must be surgical and benchmark source hashes pinned. Fine flat-grid assumptions, absolute climb heights, tree collider count and unbounded grass caching are known expansion risks. Distinct area appearance needs rendered inspection. Exact performance capacity is a measured result, not a promise from multiplying constants.

## Implementation decisions after validation

See [IMPLEMENTATION_500M.md](IMPLEMENTATION_500M.md) for measured results. The first version keeps all terrain and static collision resident to avoid collision holes; spatial collision streaming remains unimplemented. Near/far tree rendering is partitioned, and grass residency is bounded. Initial population is 224 with 256 capacity. Initial slots are validated against the built conservative navigation grid and each other, with nearby free-cell fallback. Required mantle heights remain available in seeded clearings; their locations are not fixed to the introductory area. Benchmark counters distinguish active, dormant and reserved actors; rendered-model counts are not inferred from living counts. The 200 ms build and 7.7 ms frame gates remain unmet.
