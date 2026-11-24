# Spec: Map 1 — the Dark Forest [Sir, 2026-11-20] — DRAFT for Sir's approval

Supersedes docs/spec-map1-endless-corridor.md. No end state yet (Sir will add one later).

## 1. Camp (start)
- The player starts at a camp just before the forest entrance. Safe: nothing spawns.
- Behind the camp: a path downhill towards a small town in view. It's a visual backdrop only (a distant low-detail town); invisible walls block it.
- Fog at the camp is light enough to see the town and the valley. Forward: the forest entrance behind thick bamboo and fog, with nothing visible past it.
- Pathway #0 starts at the camp and always leads to the first combat chunk.
- Entering the forest: the camp fades into thick fog behind the player. Past a set distance (proposed 25 m into Pathway #0), an invisible wall closes the way back and the camp unloads.
- Death: respawn at the camp. Found pages stay; the corridor is rebuilt from the start.

## 2. Pathway chunks
- Connect one combat chunk to the next. Each has exactly one entrance and one exit.
- Built from seeded pieces: straight, bend, slope up or down. Length varies (proposed 30–90 m).
- Both sides are lined with thick bamboo and fog, with invisible walls behind them.
- Walking in: the area behind fogs over slowly, then is walled off and unloaded.
- Encounters, rolled once per pathway: 30% chance of 1–3 enemies of any kind; 10% chance of a horde of 6 enemies of any kind; otherwise none. Same mix as combat spawns (§4).
- After combat, 1 pathway always opens at the end of the combat chunk; 30% chance of a second. A second pathway does nothing different yet; Sir will plan it later.

## 3. Combat chunks
- An open field of about 60 × 60 m with Banana trees and rock formations only. Dark, with fog opaque at about 30 m.
- **Wrap-around field:** the field tiles onto itself. Walking off one edge brings you back in on the opposite side, with copies drawn around the player so there's no visible seam. Enemies measure distance and pathfind across the wrap, so they always reach the player. Only this one chunk is loaded.
- Entering from a pathway: once the player has stood in the combat chunk for **3 s**, combat mode starts. The pathway behind fogs over, is walled off and unloads.

### States
| State | Rules |
|---|---|
| **Combat** | Every pathway is sealed by fog and unloaded. An enemy roll every 3 s (§4). Ends when the objective is met (spawning stops at that moment) **and** every remaining enemy is dead |
| **Cooldown** | 2 min. Only this chunk is active. 1–2 pathway entrances open at its far end, free of fog. When the 2 min are up, they fog over and unload, and combat starts again **only if the player is in the combat chunk** (for at least 3 s) |
| **In a pathway** | Once the player steps into a pathway, combat never triggers while they're outside the combat chunk, even if the cooldown has run out. The pathway leads to a new combat chunk |

### Objectives
| When | Objective |
|---|---|
| First combat in a new chunk, with pages still missing | Combat doesn't end until a **page drops** (and the field is cleared). Pages drop **only** here |
| First combat, all pages already found | Defeat 20 enemies |
| Every later combat in the same chunk | Defeat 20 enemies |

- **Page pool:** every page that's currently available and not yet found.
- **Page drop chance per kill:** Blighted Sprite 20%, Forest Ghoul 20%, Kostas Mortus 50%. A page drops where the enemy dies and is picked up by touching it.

## 4. Enemies
- Spawn mix: Blighted Sprite 40%, Forest Ghoul 40%, Kostas Mortus 20%.
- Combat: every 3 s, roll whether an enemy spawns, then which kind (proposed: 70% chance an enemy spawns). **At most 5 alive.** No roll while 5 are alive or once the objective is met.
- Spawn ring: 32–40 m from the player, just past the fog line, never in view.
- "Forest Ghoul" is the Forest Ranger renamed (ranged). "Kostas Mortus" is the spelling.
- **Ranges scaled to the fog** (proposed):

| Enemy | Was | Now |
|---|---|---|
| Sprite detection | 50 m | 35 m |
| Sprite Pounce | 15–20 m | 10–15 m |
| Ghoul detection / attack range | 50 / 30 m | 35 / 22 m |
| Ghoul keeps its distance at | 15–30 m | 12–22 m |
| Mortus detection | 30 m | 25 m |
| Mortus Charge trigger / length | 15–30 m / 30 m | 12–25 m / 25 m |
| Lose track of the player | 60 / 42 m | 45 / 35 m |

## 5. HUD (temporary, lightweight)
- One objectives line with a small state tag, for example:
  - "Find a page" / "Defeat 20 · 12/20" / "Clear the field · 3 left"
  - "Cooldown 1:42 · choose a path" / "Pathway"

## 6. Tests
- Camp: the backdrop is walled off and the camp unloads after the point of no return.
- Pathways: the fog closes behind and they unload; the encounter odds hold over many seeds; no combat while in a pathway.
- Combat: starts after 3 s; the wrap works and enemies reach the player across the edge; spawning stops at the objective; combat ends only when the field is clear; the page objective and the fallback to 20 kills; only first fights drop pages; the drop rates hold over many seeds.
- Cooldown: 2 min, 1–2 exits (30% for 2), the exits close, and combat restarts only when the player is in the chunk.
- Death: respawn at the camp with found pages kept.
- Performance: one combat chunk loaded; p95 against the 7.7 ms budget.
