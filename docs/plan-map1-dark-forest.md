# Plan: Map 1, the Dark Forest (implementation)

Spec: `docs/spec-map1-dark-forest.md` (approved by Sir, relayed 2026-11-20). It
replaces the 250 m generated forest (`dark_forest.gd` stays as the asset and
prop library: kit trees, props, materials).

## Modules

| File | Role |
|---|---|
| `scripts/core/map1_rules.gd` | Pure, seeded rules (RefCounted, no nodes). Phases: camp, pathway, entering, combat, cooldown. 3 s start, a spawn roll every 3 s (70 %, at most 5 alive), objective (a page on a chunk's first fight while pages are missing, else 20 kills), drop odds, 2 min cooldown, 1-2 exits (30 % for 2), pathway encounters (30 % 1-3, 10 % a horde of 6). Returns events. |
| `scripts/world/map1_world.gd` | The geometry. The camp (old camp spot, so the Training Field portal stays), the town backdrop and its walls, seeded pathway pieces (straight, bend, slope; 30-90 m) lined with bamboo and walls, fog curtains, and the 60 x 60 m combat chunk drawn as 3 x 3 tiles that follow the player (the wrap). Region queries, the height surface, solids for the nav grid, load and unload. |
| `scripts/main.gd` | Forest mode drives the two: the spawner, re-centring enemies to their nearest image (|dx| or |dz| > 30 m: shift 60 m, beyond the fog), page drops, death to the camp, the objectives line. |

## Wrap

The tiles move, never the player. When the player's tile changes, the 3 x 3
tiles move to surround it and the nav grid's origin moves by one period (the
obstacle pattern repeats, so the grid stays valid). Enemies and dropped pages
are shifted to their nearest image each tick; with fog opaque at 30 m the shift
is never seen.

## Ranges (spec §4 "Now")

Sprite detect 35, pounce 10-15, lose track 45. Ghoul detect 35, range 22, keeps
12-22, lose track 45. Mortus detect 25, charge 12-25 / 25 m, lose track 35.
Note: the spec's "Was" pounce (15-20 m) differs from the code (5-10 m, Sir
2026-11-15b); the spec's "Now" is applied.

## Tests

New `tests/simulation/test_map1.gd` (rules over many seeds, the world in the
game scene). The old forest's generation tests retire with it; suites that walk
the old forest (playthrough, render, performance) move to Map 1.
