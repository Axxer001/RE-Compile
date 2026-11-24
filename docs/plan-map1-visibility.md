# Plan: Map 1 visibility-driven areas [Sir, approved 2026-11-22]

Every load and unload happens where the player cannot see it: behind the fog, or
during a short 5 m blackout. Replaces the timed entrance curtain, the seal curtains,
pathway encounters and the cooldown's fog-gap exit mouths.

## Visibility (the fog's opaque distance)

| Place | Visibility |
|---|---|
| Camp | 30 m (the town and valley sit in the fog for now [Sir]) |
| Pathway | 20 m (Sir proposed 30; 20 lets the area behind unload 22 m in) |
| Combat chunk, peaceful | 60 m |
| Combat | 30 m (cap) |
| Blackout | 5 m |

| Moment | Change |
|---|---|
| Camp -> Pathway #0 | 30 -> 20 m over the first 3 m |
| Into an exit pathway | 60 -> 20 m over the first 3 m |
| Into a combat chunk | 20 -> 60 m over the first 3 m |
| Combat starts (at 60 m, not on cooldown) | 3 s fade 60 -> 5 m; 0.5 s hold: border and entrance pathway removed, the field wraps; 1.5 s out to 30 m |
| Combat ends (objectives met, field clear) | 3 s fade 30 -> 5 m; 0.5 s hold: player moved to the chunk's centre, dropped pages into the square, bamboo border and 1-2 exit pathways built; 1.5 s out to 60 m; cooldown 2:00 |
| Cooldown ends in the chunk | the combat-start sequence again (border and exits go in its blackout) |

## The field and the exits

- A combat chunk that is not in combat is a 60 x 60 m field closed in bamboo (walled),
  with gaps only where pathways attach. During combat it has no border and wraps.
- Exits: each on a random edge (a single exit too [Sir]); its pathway heads straight
  out from that edge. Two on the same edge sit 36 m apart and bend only away from each
  other; on different edges they diverge. Never over the field.
- Leaving: the old field and the unchosen pathway unload once the player is 22 m into
  the chosen pathway; a bamboo thicket closes the way back there, out of sight. The
  camp unloads the same way, 22 m into Pathway #0.
- No pathway encounters [Sir].

## Grass

A peaceful chunk draws grass to 40 m (High), 32 m (Medium), 25 m (Low); combat stays at
the preset's distance (25 m). Measured against the frame budget (peaceful chunks have
no enemies or fireballs).

## Order

1. The visibility controller and the two blackouts.
2. The closed field and exits on any edge.
3. Unloading behind the player with thickets; encounters removed.
4. Tests (simulation, playthrough) and screenshots.
5. Peaceful-field grass and a performance check.

## Status: implemented 2026-11-22 (uncommitted)

- Rules (`map1_rules.gd`): phases entering -> starting -> combat -> ending -> cooldown; a
  fight starts once the player is 3 m in; the blackouts run 3 s down, 0.5 s hold (the
  swap at its middle), 1.5 s up; `timed_visibility()`; pathway encounters removed.
- World (`map1_world.gd`): `visibility_at()`, `settled()`; a closed field shows only its
  own tile inside a walled bamboo border (`_build_border`); `start_combat()` /
  `end_combat()`; exits on random edges (`pathway_points` takes a direction and a lean);
  the camp, the old field and the unchosen exit unload 22 m in behind a thicket and wall.
  Tonight's fog-gap mouths, the entrance and seal curtains and `sealing()` are gone.
- Fog: visibility drives the depth fog; a closed field gets thin banks and a far-gathered
  curve (PEACE_BEGIN 8 m, PEACE_CURVE 2.2) so its 60 m reads open.
- Grass: 40 / 32 / 25 m (High / Medium / Low) in a closed field: p95 4.5 -> 5.1 ms at
  1920 x 1080 (tests/performance/peace_grass.gd). Fights unchanged (9.5 ms, over 7.7).
- Suites: Simulation 987, Render 170, Mobile 170, Playthrough 27 pass; Content fails only
  on assets/map1_vista's missing ledger row (another agent's assets).
- Captures: production/qa/evidence/2026-11-22-vis-*.png (tests/render/map1_edges.tscn).
