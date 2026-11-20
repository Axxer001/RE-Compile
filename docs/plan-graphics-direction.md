# Plan: graphics direction [Sir, approved 2026-11-20]

Goal: implement and test everything; do not stop until all suites PASS. No commit/push without Sir's word.
Source: C:\Users\Axxer\Desktop\GAME ASSETS\Mage Arena Style (Graphics.md, ForestLight.gd/.tscn, 4 plant GLBs). Plant geometry and textures made by Sir's tool (Astra): cleared, ledger as Sir's own.

## Direction: option A — Mage Arena-style materials under Silent Hill 2-style lighting
### Materials (apply to everything: trees, rocks, ground, props, enemies, effects where sensible)
- Low-poly faceted look: per-face (flat) normals; opaque; double-sided where the pack is; roughness 1.0; vertex brightness kept; StandardMaterial3D, no custom material shaders.
- Small painted albedo maps with NEAREST filtering + mipmaps (bamboo stem: linear + mipmaps, as in the pack).
- Muted earthy palette: bark tint ~(0.55, 0.49, 0.45), leaves ~(0.46, 0.43, 0.39), soil ~(0.44, 0.43, 0.37). Re-tint kit rocks, ground and enemy skins/outfits to this palette.
- Effects (Binbun): tint toward the muted palette; keep magic (fire, wand glow) as the saturated accent.

### Plants
- Replace the pines and dead trees with Banana, Mango, Narra, Bamboo Clump (local Philippine forest). Re-measure trunk radii/colliders; rebuild far-tree impostors for the new kinds; keep chunked MultiMesh + visibility ranges.

### Lighting (Silent Hill 2 inspiration, night)
- Fog: dense, dark grey-green (~#1a1f1c), fully opaque ~30 m; background/sky matched exactly to the fog colour; volumetric drift kept (cheap settings).
- Camera far clip ~40 m. No visible sky or stars.
- Moon/key light: weak cool directional; ForestLight's cool ambient fill as the base, scaled to night.
- Wand light: warm cone ~15 m + soft ~4 m glow from the wand tip.
- Enemies: glowing eyes or a dim rim so silhouettes read in fog.
- Tonemapping: linear (per the pack), exposure tuned for night.

### Post
- REMOVE the pixelated low-res render (lofi_view 640x360) and the 16-bit colour dither: render at native resolution.
- Keep only: film grain (raised slightly), desaturation ~30%, vignette.

## Tests
- Render captures: forest (near/mid/far), camp, enemies in fog, wand light, effects. Check fog/background colour match (no band), no visible void.
- Simulation/Content/Mobile/Playthrough green; update tests that assert lofi_view, colour16, pines or old tints.
- Performance run (expect a gain from the 40 m far clip and fewer, lower-poly trees).

## Status: implemented 2026-11-20 (uncommitted)

| Item | As built |
|---|---|
| Plants | `assets/tropical/` (Narra 0.3, Mango 0.3, Banana 0.25, Bamboo 0.15 of trees); each keeps its own height x0.85-1.15; trunk radii measured (Narra 0.46, Mango 0.27, Banana 0.18, Bamboo clump 0.9 m); pack materials kept (opaque, double-sided, nearest / bamboo stem linear), roughness 1. Impostors rebaked to `assets/tropical/impostors/`. Provenance checked: per-plant names only; Mage Arena gave measurements only. |
| Materials | `scripts/render/look.gd`: matte (roughness 1, nearest-mip maps), per-face normals for kit rocks, enemy skins/cloth pulled ~35-45% to the earthy palette (in place, once per shared material). Effects untinted (the post desaturates them; fire stays the accent). |
| Lighting | `art_direction.gd`: depth fog #1a1f1c from 3 m, opaque at 30 m; background = fog colour; no sky (Binbun night sky removed); far clip 40 m (forest); weak cool moon (0.22); pack ambient (0.64,0.66,0.70) x0.3; linear tonemap, exposure 1.15; cheap volumetric drift. Training Field: day-blue background, fog out to 400 m, far 500 m while there. |
| Wand light | `ember_wand.gd`: warm SpotLight 15 m / 26 deg (shadowed) along the view + 4 m tip glow. |
| Eyes | `blighted_sprite.gd._add_eyes()`: two unshaded emissive spheres on the head bone (Sprite yellow-green, Ghoul pale, Mortus red). |
| Post | Pixel view and 16-bit dither removed (world view SubViewport at 1x, kept for the camera kicks); post = grain (raised), 30% desaturation, vignette. Settings `pixel_scale` and `colour16` removed. |
| Tests | Render: no-sky/no-void, fog wall at 35 m invisible vs 12 m visible, native res, tropical kinds, forest near/mid/far, enemy eyes in fog, wand light. Sim/graphics/forest tests updated. |
| Performance | Not passing: p95 ~20-23 ms on today's (changed, 250 m) forest under load; new trees vs old pines measured the same (19.9 vs 20.2 ms). |
