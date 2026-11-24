# Dark Forest + hostile asset swap — LIVE application (2026-11-24)

## Destination tested

`C:\Users\Axxer\Documents\Codex\2026-11-08\how\outputs\RECompile-FPS\project.godot`

Inside the running verification session:

```
ProjectSettings.globalize_path("res://project.godot")
= C:/Users/Axxer/Documents/Codex/2026-11-08/how/outputs/RECompile-FPS/project.godot
```

Git: branch `terrain-first-three`, no commit, no push, no reset, no branch switch, no clean.
The pre-existing dirty work (including untracked `assets/map1_vista/`, `scripts/world/map1_world.gd`,
`scripts/world/map1_fog.gd`, `assets/infected_hostiles/`) is untouched apart from the files listed below.

Environment: Godot `4.7.2.stable.official.ed1daf0bf` · Forward+ · 1920×1080 viewport (720p window
override) · RTX 2050 · map seed 7 for the captures · default graphics preset.

## What was applied

### Environment (approved retro remodel)

284 payload files copied from `Dark Forest Retro Remodel/assets_retro` over their matching paths:
68 `.gltf` + 68 external `.bin` (72 models in total with the 4 `.glb`), their 155 texture tiles,
the tropical/quaternius impostor sheets, `assets/textures/map1/earth.png`, the 7 pack shaders,
`map1_vista/highlands.obj`, `woodline.obj`, `valley_layers.tscn` and the Binbun palette/materials
that the environment manifest names. 161 of them overwrote a live file, 123 were new
files that the retro `.gltf` buffers reference.

**Deliberately excluded: `assets/BinbunGrass/`.** The instruction is to keep the project's original
Binbun grass masks and atlas as the default. Those 14 files (masks, atlas, `grass.gdshader`,
`grass_fade.gdshader`, ground shaders, palette, grass materials) are byte-identical to their
pre-swap state (verified against the backup). The retro grass-sheet look in the review copy came
from replacing that whole grass set; that replacement is **not** part of this swap.

Destination `.import` sidecars were kept for existing files, so their resource UIDs and import
settings survive. New assets got their own import sidecars and Godot generated the local cache
(`.godot` was not copied). Import ran twice: the first pass reported seven
`get_multiple_md5: Condition "f.is_null()"` engine messages while reimporting the changed quaternius
textures; the second pass is clean (0 errors, 0 warnings beyond the pre-existing Binbun `suzanne.mtl`).

Terrain height, collision, spawn rules, progression and the runtime combat floor are unchanged.
The optional `grid_h` height quantization from `integration/map1_world.patch` was **not** applied.

### Code merged into the live tree

| File | Change |
|---|---|
| `scripts/actors/hostile_models.gd` | new — instances one approved GLB under the actor, returns its own `AnimationPlayer` and one nearest-filtered duplicate per surface |
| `scripts/actors/blighted_sprite.gd` | `_build_model` uses the approved GLB; `_skins` + `_set_emission` so a burn glows on every surface; Quaternius body/UAL library removed |
| `scripts/actors/forest_ghoul.gd` | `_build_model` uses the approved GLB; the code-built longbow (`_attach_bow`) deleted — bow, quiver and `Bow`/`Nock` bones come from the model |
| `scripts/actors/kostas_mortus.gd` | `_build_model` uses the approved GLB; old ×1.6 body scale and skin tint gone, model is 2.79 m at scale 1.0 |
| `scripts/world/map1_world.gd` | three presentation hunks: trail material `ALPHA`→`ALPHA_SCISSOR` (0.5) + `NEAREST`; `_earth` filter `NEAREST`; `_culms` radial segments 7→5 |
| `tests/render/run_render.gd` | two look checks updated for the new bodies (nearest-filtered approved skin; the bow is a skeleton bone, not a `Bow` node) |
| `tests/simulation/probe_hostile_models.gd` | new — headless probe of clip bindings, track/bone resolution, death and pooled reset |
| `tests/render/capture_asset_swap.gd/.tscn` | new — live capture scene for the camp, pathway, field and each hostile attacking |
| `docs/asset-licenses.md` | swap provenance rows (SHA-256 of the three GLBs; 284-file environment payload) |

`scripts/world/grass_field.gd` and `scripts/world/dark_forest.gd` needed no change: the live versions
already drive the Binbun field, and the swap keeps that asset set. `_culms()` (the corridor bamboo)
and the runtime combat floor were read through their real callers (`_pathway`, `_field`, `CAMP_BOX`
floor body) before any edit; only the culm segment budget changed.

The merge was conflict-free: every live file was older than the reviewed copy and the diff between
them was exactly the swap hunks above, so the full reviewed file could be written without losing
newer live gameplay code. Backups of each overwritten file (relative path preserved) are in
`C:\Users\Axxer\Documents\Codex\asset-swap-backup-2026-11-24\live\`.

### Hostiles

`assets/hostiles/` now holds the three approved GLBs plus their embedded 64 px tiles and import
sidecars (90 files). Gameplay controllers remain the authority for movement, damage, projectiles and
pooling; only presentation changed.

| Actor | Resource | SHA-256 vs `Finalized Hostiles` |
|---|---|---|
| Blighted Sprite Retro | `res://assets/hostiles/blighted_sprite.glb` | `daf2df24c989f59ca5813821f3ec844cd1cd02f51e0d455b199dc6ea3dcc48ff` ✅ |
| Forest Ghoul Ashveil Retro | `res://assets/hostiles/forest_ghoul.glb` | `657e8ac5d9de87c799bc5cc1c0bf1b76ed0c12eac4f7e240e51f0035b824abe2` ✅ |
| Kostas Mortus Iron Ram Retro | `res://assets/hostiles/kostas_mortus.glb` | `c5bdbca20ae267a2842e7fbe352ab720d209ca3174cd2bf0088eadb3e6fb2bd3` ✅ |

## Verification (from the live destination)

Hashes — all 284 payload files match their pack source SHA-256 (0 mismatches), including the 68
`.bin` geometry buffers; all 3 hostile GLBs match `Finalized Hostiles` (3/3).

| Suite | Result |
|---|---|
| Import (`--headless --path <live> --editor --quit`) | exit 0, 0 errors on the settled pass |
| `tests/simulation/probe_hostile_models.gd` | **PASS** 114 checks — every clip the actors ask for exists, loops/one-shots as imported, every track resolves to a node and bone, death plays, pooled reset restores model/anim/visibility/collision |
| `tests/simulation/run_simulation.gd` | **PASS** 992 checks (includes ground-seam, collider-vs-height, bamboo-gap and hostile combat coverage) |
| `tests/playthrough/run_playthrough.gd` | **PASS** 27 checks, map seed 3380136698 — real loop reaches level 8, takes bullets and bites |
| `tools/validate_content.gd` | **PASS** 216 checks after the ledger rows were added |
| `tests/render/baseline.tscn` (GPU) | 169/170 checks, **1 failure**: `grain off: an unchanged view captures identically (16 changed)` |
| `tests/render/map1_joins.tscn` (GPU) | 13 join captures written, no script errors |

The running actors instantiate their approved visuals: the capture session reported
`model = res://assets/hostiles/{blighted_sprite,forest_ghoul,kostas_mortus}.glb` for all three, with
the imported clip lists (`idle/walk/run/strike/death/pounce_start/air/climb`,
`idle/walk/jog/climb/draw/aim/shoot/death`, `idle/stride/charge/run/rush/strike/impact/death`), and
the Ghoul's single release added exactly **1** arrow (`ghoul_release_arrows: 1`).

Captures (1920×1080 PNG), `evidence/asset-swap-live/captures/`:

* `swap-camp.png` — the camp with its fire, benches and bamboo wall
* `swap-bamboo-pathway.png` — Pathway #0's culms
* `swap-combat-field.png` — the first combat chunk's grass field
* `swap-sprite-strike.png` — Blighted Sprite in its claw strike state
* `swap-ghoul-draw.png`, `swap-ghoul-release.png` — bow draw, then the release with the arrow
* `swap-mortus-charge.png`, `swap-mortus-slam.png` — charge wind-up and the charge dive
* `fp-*.png` (104) from the render suite and `join-*.png` (13) at the pathway/field mouths

Verified in live gameplay: model loading and clips per actor, single arrow per release, attacks
reaching the player (playthrough log), pooled reset, joins of the ground (13 captures; the suites'
seam and collider checks ran in Simulation), the original Binbun grass being drawn.

Verified only on disk: the 284-file / 3-GLB hash equality, the backup contents, and the ledger text.
Not verified: draw-call counts (the harness does not emit them), the grain check above, and human
art judgement of orientation, foot planting, claw clearance, bow silhouette and the new vista/earth
look — those need your eyes on the captures.

## Known residual

* `grain off: an unchanged view captures identically` — 16 pixels drift between two still frames
  with grain disabled (baseline tree: 0). It is a tiny temporal difference in the new foliage/vista,
  not a visible defect; not silenced.
* The campfire lighting check now **passes** with the live Binbun grass (it failed by 0.003 in the
  review copy, where the pack's unlit grass shader replaced the Binbun one).

## Rollback (this swap only)

1. Restore overwritten files, relative paths preserved:
   `xcopy /E /Y "C:\Users\Axxer\Documents\Codex\asset-swap-backup-2026-11-24\live\*" "<live project>\"`
   (161 environment files, plus the actor/world/test scripts and `docs/asset-licenses.md`).
2. Delete the additions listed under `added` in `docs/asset-swap-live-manifest.json`, plus
   `assets/hostiles/`, `scripts/actors/hostile_models.gd(.uid)`,
   `tests/simulation/probe_hostile_models.gd(.uid)`, `tests/render/capture_asset_swap.gd/.tscn`,
   `docs/asset-swap-live-manifest.json` and this report.
3. Reimport: `godot --headless --path "<live project>" --editor --quit`.

No git state was changed, so `git checkout -- <files>` also restores the tracked ones; the untracked
Map 1 work is covered by the backup folder.
