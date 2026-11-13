# RE:Compile — current prototype

The active runtime is a first-person Dark Forest survival/action prototype in Godot 4.7.2, using GDScript and Forward+. Open `project.godot` and run `scenes/main.tscn` to play the current source. `Launch.cmd` prefers a separately exported build if present; that build may predate source changes.

## Current game loop

Explore a 150 × 150 m forest, find Grimoire pages, unlock and equip abilities, fight Blighted Sprites, and develop stats through chants and progression. Death resets the run while unlocked pages, rank, chant tiers, and lifetime records persist. New game resets that profile.

Clearings, connecting paths, and camp are authored. Each run randomizes trees, rocks, ledges, page locations, and enemy spawn zones from a seed. This is a finite generated map, not a streamed infinite world or procedural building generator. Terminal hacking and research extraction belong to earlier versions in `reference/`.

## Implementation and verification

Generation separates data from scene construction and checks placement rules. Trees use chunked MultiMeshes and distance-based representations; enemies use a bounded pool. Profile saves use a temporary file and retain the previous readable profile as `.bak`; failed saves report a warning and an in-game notice. Loading tries the backup if the primary is missing or unreadable. Backup recovery can restore an older save.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\verify.ps1 -Suite Simulation` for headless regression checks. Other suites are Content, Render, Mobile, Playthrough, Performance, and All. Evidence is written under `evidence/`. Existing evidence is historical, not proof of the current source.

The Performance suite measures scripted traversal plus actor/effect updates. It reports real-clock frame percentiles, generation/scatter time separately, and sustained-load metrics. It does not measure full player/input simulation or fresh-terrain streaming. Peak load counts alone do not establish sustained worst-case load. Separate full-gameplay measurements are still required before making performance claims.

Full-gameplay benchmarks: `godot_console --path . res://tests/performance/baseline.tscn -- --scenario=<generation|traversal|combat|overload> --out=<new dir>` (GPU display required; run one at a time). PASS means a valid capture; the 7.7 ms p95 verdict is `metrics.performance.within_budget`. Latest results and the casting fix: [docs/queued-performance-2026-11-14.md](docs/queued-performance-2026-11-14.md).

## Scope and assets

The current source and regression tests describe implemented behavior; older architecture plans and the former campus/shooter README do not establish current features. The movement arena remains a test fixture. Asset provenance is recorded in `docs/asset-licenses.md`; archived systems live under `reference/`.
