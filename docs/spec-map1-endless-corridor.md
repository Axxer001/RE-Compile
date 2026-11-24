# Spec: Map 1 endless corridor [Sir, 2026-11-20] — DRAFT for Sir's planning

## Shape
- Fixed width (proposed 70 m), side walls: impassable cliff / dense tree line + invisible collider.
- Length: chunks (proposed 40 m) generated ahead until the map's objectives are met, then the end chunk (exit / boss) spawns and generation stops.
- Live window: 2 chunks behind, current, 2 ahead. Built across frames, at least 2 chunks ahead. Recycled only when >80 m away and inside fog.
- Each chunk seeded by (map seed, chunk index): rebuilt identically if the player walks back.
- Fog hides everything past ~70 m: no visible world edge.
- Floating origin: shift world to near zero every ~1.5 km.

## Chunk types
| Type | Contents |
|---|---|
| Camp | Chunk 0 only. Safe: no spawns |
| Path | Travel and ambient props, light roaming enemies |
| Combat area | Arena chunk with a defined boundary; objectives happen here |
| End | Spawns once the map's objectives are met: exit / boss |
Templates are picked by weighted mix, never the same template twice in a row; combat areas every N chunks (proposed every 3rd).

## Walking back
- Free outside combat.
- In combat: a barrier closes at the combat area's back edge (and front edge) until the area's objective is cleared.

## Objectives
- Map objective: obtain specific pages AND/OR defeat N enemies (per map, Sir to set).
- Pages are not on the ground: they drop from enemies killed inside a combat area, with a drop rate per enemy type (higher for elites).
- A dropped page appears where the enemy died and is picked up on contact.

## Combat area loop
| State | Behaviour |
|---|---|
| Idle (never entered) | Entering starts combat: barriers close, enemies spawn |
| In combat | Spawns until the area's objective is cleared |
| Cleared | Barriers open; respawn cooldown starts (proposed 90 s) |
| Cooldown | Counts down whether or not the player is inside |
| Ready | Does nothing until the player enters; entering starts combat again |

## Open questions for Sir
1. Width, chunk length, combat-area frequency, respawn cooldown (defaults above).
2. Per-area objective: kill X, survive Y s, or kill a specific elite?
3. Page drop rates per enemy type, and does a page drop only once (no duplicates)?
4. Map objective numbers for Map 1 (which pages, how many kills).
5. Does dying keep progress made in the corridor, or restart from camp?
6. What sits on path chunks: enemies, chests, lore, nothing?
7. Is there a cap on corridor length (fail safe), e.g. end chunk forced after K chunks?
