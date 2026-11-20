# Project Stage Analysis

**Date**: 2026-11-15
**Stage**: Production (observed); Concept (configured)
**Stage Confidence**: CONCERNS — ambiguous signals: the code fits Production, but the project has no game brief where the kit expects one (Concept's indicator)
**Analysis Scope**: Full project (rigor `minimal`, workflow `minimal`, automation `guided`)

## Completeness Overview
- Design: no kit-format design docs (`design/game-brief.md` absent; 0 GDDs, which is normal at `minimal`). The current design lives outside the kit's layout: `docs/pivot-grimoire-plan.md` (the Grimoire pivot, page and C++ lesson table), `docs/plan-phoenix-spells.md`, `docs/plan-gambler-set.md`, `docs/settings-menu-plan.md`, `docs/architecture-rehaul.md`. `docs/design-brief.md` is the superseded salvage-horror pitch (2026-11-09) and does not describe the game today.
- Code: 58 GDScript files, about 14,600 lines, in `scripts/` (`engine.code_root`), across 8 systems: `ui/` (10 files, 3,054 lines), `combat/` (10, 2,760), `world/` (9, 2,237), `core/` (16, 1,700), `player/` (3, 1,305), `render/` (3, 1,076), `actors/` (4, 881), `audio/` (2, 508), plus `main.gd`. Playable: forest world, Training Field, 15 Grimoire pages (attacks, skills, spells, passives), Code Assembly and Spell Chant, HUD, settings, export build.
- Architecture: 0 ADRs in `docs/architecture/` (not a gap at `minimal`). Decisions are recorded in the plan documents and in the Irminsul project log.
- Production: no epics or stories (not a gap at `minimal`). Work is tracked in `tasks/todo.md` and the `docs/plan-*.md` files.
- Tests: 47 runners in `tests/` (simulation 40, performance 4, render 2, playthrough 1), run through `verify.ps1`: Content 200, Simulation 879, Render 120, Mobile 120 and Playthrough 24 checks, all passing at the last full run (2026-11-14). The suites are custom runners, not gdUnit4, so the kit's `/test-setup` artifact (`.github/workflows/tests.yml`) is absent.

## Stage Classification Rationale
**Configured stage**: Concept (`project.stage` in `project.yaml`, set by `/start` on 2026-11-15)
**Observed stage**: Production. Its indicators: the engine is configured (Godot 4.7) and the code root holds 58 source files with active development (multiple feature sets added 2026-11-13 to 2026-11-14).
At `workflow: minimal` nothing runs `/gate-check`, so the configured stage stays where `/start` set it; that lag is expected, not a disagreement. Confidence is CONCERNS only because the one artifact `minimal` expects, a game brief, is missing, which is Concept's indicator.

## Gaps Identified
1. **No current game brief** (`design/game-brief.md`). The code root already holds the game (58 files), so the brief should be written from what is built, not brainstormed. Question: should the brief take its pitch and pillars from the Grimoire pivot plan (`docs/pivot-grimoire-plan.md`) as well as the code, and should `docs/design-brief.md` stay as history?
2. **Existing documents are outside the kit's layout.** Question: keep the plans in `docs/` as they are (the kit reads them on demand), or let `/adopt` propose moving the design parts into `design/`?

## Recommended Next Steps
1. `/adopt`: checks which existing files the kit's skills can read and lists any format gaps (it never rewrites existing artifacts).
2. `/reverse-document design scripts`: writes `design/game-brief.md` from the built game, with its build order as the plan at `minimal`.
3. Keep building through `/dev-story` against that brief; `verify.ps1` stays the test gate (`commands.test` in `project.yaml`).

## Role-Specific Recommendations
None requested (general analysis).
