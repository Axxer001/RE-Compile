# Plan: Map 1 layout and fog pass [Sir, 2026-11-20]

Source: C:\Users\Axxer\Desktop\GAME ASSETS\Dark Forest Layouts (Implementation Guide.md, layout.gd, Bamboo/Grass/Mist shaders, Earth.png, captures). Build in this order: **pathway, then camp, then combat field, then fog**. Test each before the next. The Map 1 rules and tests must stay green throughout.

## 1. Pathway
- As in the guide. Keep the routes, lengths, walls, colliders, encounter rolls and seals.
- Several irregular rows of bamboo along both sides, set into the slope: lit inner stems, a black outer silhouette. One shared stem mesh with Bamboo.gdshader, instanced per pathway. BinbunGrass along the edges.
- Walk both directions and the sharpest seeded bend: no sky showing through, no bright fog curtains, no stems inside the lane.

## 2. Camp
- As in the guide. Keep the respawn point, portal, safe area, entrance and valley walls.
- Composed in depth: campfire, grassy banks, a trail down to the town (anchor about 106 m away), a keep above the roofline and a final ridge. Lit, emissive windows. No trees at the camp or in the town.
- Town: Kenney Fantasy Town Kit (CC0) **if Sir approves the download**. Until then, the simple-shape town from the guide's capture.

## 3. Combat field [Sir]
- **Grass only, plus a few rocks.** The banana trees go. The rocks are natural: half-buried, moss and soil tinted to the palette, sized to the hills. They're the only cover, so Mortus can still stun himself on them and they still block Ghoul arrows.
- **BinbunGrass covers the entire surface densely**, with no bare polygons visible from eye height, at any heading or crest.
- Hills: layout.gd's two periodic waves, **scaled so the maximum slope stays under 25°** (about 55% of 3.8 m and 2.1 m), with a seed-dependent phase. Identical across the seams and the 3 × 3 wrap. One mesh per chunk, reused by all 9 tiles.
- Collision and height_at come from the same triangles. Navigation, enemy and page placement go through height_at. Entrance and exit heights blend smoothly into the pathway ends.
- **Spawn-wrap fix:** on a 60 m wrapping field, nothing is more than 30 m away along an axis. Spawn only at diagonal positions that are still 32 m or more away after wrapping (otherwise retry), and fade enemies in from the mist.
- Test diagonal crossings, dashes, projectiles skimming over crests, drops on slopes, and Pounce and Charge on slopes.

## 4. Fog: as close to Silent Hill 2 as possible [Sir]
- **Thick, close, and always moving.** Keep the 30 m opaque cutoff, with the background matching the fog colour exactly.
- **Rolling volumetric fog:** the density comes from scrolling 3D noise, so banks visibly thicken and thin as they drift past. Wind direction changes slowly.
- **Drifting fog sheets:** soft sheets fading at every edge, spread around the player at several angles. They're spawned upwind, drift with the wind and are recycled downwind, so they read as wisps from every heading, never as flat walls.
- **Breathing visibility:** the visible distance slowly varies (about 24–32 m over 20–40 s), so silhouettes appear and vanish. It never goes below the spawn fade-in distance.
- **Close haze:** a faint near layer within 2–6 m, so even close objects soften (as in Silent Hill 2's streets).
- **Mist.gdshader** in the hollows: low, slow-moving mist.
- **Wand light shafts:** the wand cone lights the fog (volumetric light), as Silent Hill's flashlight does.
- **Per zone:** thinner at the camp, so the town is visible; thickest in combat; closing in when the fog seals a path.
- Keep enemy eyes and attack wind-ups readable through the fog.

## 5. Performance and acceptance
- Measure the grass instance count, transparent overdraw (fog sheets and mist) and spikes when chunks swap. Trim far grass and fog sheet coverage first.
- p95 against 7.7 ms on Map 1's real worst case, before and after, under the same load.
- Eye-height captures at the same seed: the camp facing both ways, a pathway bend, a field crest and a hollow, and fog moving while standing still.
- Every suite passes. No commit or push without Sir's word.

## Results (2026-11-20, implemented; not committed)

- Pathway: ranked culms (~20 per m per side, 3.75-10.5 m out, outer ranks darkened through INSTANCE_CUSTOM), raised banks, grass verges; the floor blends into the field over its last/first 10 m (seam 0.013 m).
- Camp: bamboo only on the forest side; grassy shoulders and valley (one mesh), a trail of Earth.png down to a Kenney Fantasy Town Kit town on the far slope (~106 m), a keep above the roofline, a ridge. No trees.
- Field: grass only (~18,000 cards per tile, shared by the 9 tiles) and 6-9 half-buried rocks. Hills at HILL_K 0.52: steepest triangle 24.1 deg over 40 seeds. The mesh, the collider (a triangle mesh: under Jolt it beat a HeightMapShape3D, 1.5 vs 2.2 ms of actors) and height_at share the 2 m triangles; height_at reads a cached grid. Diagonal spawns only, fading in over 1.6 s. Enemies that lose their ground go back to the pool.
- Fog: map1_fog.gd (rolling FogVolume banks on drifting 3D noise, 12 drifting sheets, visibility breathing 24-32 m, haze from the eye, hollow mist, wand light in the fog, per-zone density, closing in while a pathway seals). The mobile renderer has no volumetric fog, so its sheets are denser.
- Also fixed: fire zones assumed a flat floor at y 0 (hazards.ground_fn); wrap moves shift the nav grids instead of rebuilding them (8.7 ms spike).
- Performance (the Map 1 worst case, 11 enemies, 64 fireballs, Ring, burns; same load): before the pass p95 7.4-8.4 ms; after 9.1-9.4 ms (a flat field with everything else: 8.1). Over the 7.7 ms budget. The hills' cost is mostly the enemies' slides on slopes. Trimming the far grass and the sheets saved almost nothing; turning off the grass, the banks or the sheets saves 0.1-0.3 ms each.
