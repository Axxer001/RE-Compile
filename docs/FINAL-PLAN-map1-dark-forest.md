# RE:Compile: Map 1, the Dark Forest. Final plan and how it works

**Status:** built and tested (2026-11-20), not yet committed. It combines Sir's approved spec (`spec-map1-dark-forest.md`) and the as-built notes (`plan-map1-dark-forest.md`). There's no end state yet; Sir will add one later.

---

## 1. Overview

```
 TOWN (backdrop, unreachable)
   ▲ downhill path, walled off
 ┌─────────┐
 │  CAMP   │  safe, light fog, start / respawn
 └────┬────┘
      │  Pathway #0 (fixed). Point of no return 25 m in
      ▼
 ┌──────────────────────┐   enter, then 3 s   ┌──────────┐
 │ COMBAT CHUNK (60×60) │ ──────────────────► │  COMBAT  │ fog seals everything
 │ wrap-around field    │ ◄────────────────── │   MODE   │ spawn roll every 3 s
 └──────────┬───────────┘ objective + cleared └──────────┘
            │
            ▼
      COOLDOWN (2 min): 1 exit guaranteed, 30% chance of 2, free of fog
            │                              │
     player steps into a pathway    timer runs out with the player in the chunk
            ▼                              ▼
    PATHWAY (30–90 m) ──► NEW COMBAT CHUNK    the exits fog over → COMBAT again (20 kills)
```

It's a chain of **combat chunks** joined by **pathways**. Only the area the player is in exists; everything behind them is sealed by fog and unloaded. That keeps performance flat however far the player goes.

---

## 2. The camp (start)

| Element | How it works |
|---|---|
| Start point | The player begins at a camp just before the forest entrance. Nothing spawns there |
| Town backdrop | Behind the camp, a path runs downhill to a small town about 106 m away. It's a visual backdrop only, blocked by invisible walls. It sets the scene for where the adventure began |
| Visibility | Fog at the camp is pushed out to 260 m so the valley and town can be seen |
| Forward | The forest entrance, hidden behind thick bamboo and fog. Nothing past it is visible |
| Training Field | The existing portal at the camp stays |
| Leaving | Pathway #0 starts at the camp and always leads to the first combat chunk. As the player walks in, the camp fades behind them into thick fog |
| Point of no return | 25 m into Pathway #0, an invisible wall closes the way back and the camp unloads |
| Death | The player respawns at the camp. **Found pages are kept**, and the corridor is rebuilt from the start |

---

## 3. Pathway chunks

| Rule | Detail |
|---|---|
| Purpose | Joins one combat chunk to the next |
| Shape | Seeded pieces: **straight, bend, slope up or down**. Always exactly **one entrance and one exit** |
| Length | 30–90 m, varying from one pathway to the next |
| Walls | Both sides are lined with thick bamboo and fog, with invisible walls behind them so the player can't leave the path |
| Fog behind | Once the player walks in, the area they came from slowly fogs over, then is walled off and unloaded |
| Encounters | Rolled once per pathway: **30% chance of 1–3 enemies**, **10% chance of a horde of 6**, otherwise none. Same enemy mix as combat (§5) |
| No combat in pathways | While the player is in a pathway, combat mode never triggers, even if the last chunk's cooldown has finished |
| After combat | **1 pathway always** opens at the end of the chunk, with a **30% chance of a second**. The second does nothing different yet; Sir will design a choice for it later |
| Removal | Pathways fog over and unload when the player starts combat in the next chunk, or when a cooldown ends with the player still in the chunk |

---

## 4. Combat chunks

### The field
| Element | Detail |
|---|---|
| Size | 60 × 60 m open field |
| Contents | **Banana trees and rock formations** only, leaving room to fight |
| Visibility | Night darkness, with fog fully opaque at about 30 m |
| Endless feel | A **wrap-around field** (see below) |

### How the wrap works
- The field is drawn as **3 × 3 copies of the same chunk** around the player. When the player crosses into a new copy, the tiles move to surround them again. **The player never moves**; the world shifts.
- The navigation grid moves with it. The obstacle layout repeats exactly, so enemy pathfinding stays valid.
- Every tick, enemies and dropped pages are moved to their **nearest copy**: anything more than 30 m away on either axis shifts by 60 m. That always happens beyond the fog, so the player never sees it.
- The result is a field that feels endless, where enemies always reach the player and only one chunk's worth of geometry exists.

### States
| State | Behaviour |
|---|---|
| **Entering** | The player must be in the combat chunk for **3 s**. Then combat starts and the pathway behind fogs over, is walled off and unloads |
| **Combat** | Every pathway is sealed by fog and unloaded. Enemies spawn (§5). **Spawning stops the moment the objective is met.** Combat ends once the objective is met **and** every remaining enemy is dead |
| **Cooldown** | Lasts **2 minutes**. Only this chunk is active. **1–2 pathway entrances** open at the far end of the chunk, free of fog. When the 2 minutes are up, they fog over and unload, and combat restarts, but only if the player is in the chunk (for 3 s) |
| **In a pathway** | Entering a pathway commits the player to it. Nothing triggers until they reach the next chunk |

### Objectives
| Situation | Objective |
|---|---|
| **First fight in a new chunk, pages still missing** | Combat doesn't end until **a page drops** (and the field is cleared). Pages drop **only** in this situation |
| First fight, every page already found | **Defeat 20 enemies** |
| Every later fight in the same chunk (after its cooldown) | **Defeat 20 enemies** |

- **Page pool:** every page currently available that hasn't been found yet.
- **Page drops:** a page appears where the enemy dies and is collected by touching it.

---

## 5. Enemies

### Spawning
| Rule | Value |
|---|---|
| Spawn roll | Every **3 s** during combat. 70% chance an enemy spawns, then a second roll picks which one |
| Cap | **At most 5 alive.** No roll while 5 are alive, or once the objective is met |
| Where | A ring **32–40 m** from the player, just past the fog line, so spawns are never seen (as in Silent Hill 2) |

### The roster
| Enemy | Type | Spawn | Page drop | Role |
|---|---|---|---|---|
| **Blighted Sprite** | Common, melee | 40% | 20% | Fast, comes in numbers, Pounce |
| **Forest Ghoul** | Common, ranged (the Forest Ranger renamed) | 40% | 20% | Keeps its distance, homing Burst arrows |
| **Kostas Mortus** | Elite, melee | 20% | 50% | A tank: Charge, front armour, halved debuffs |

### Stats, with ranges scaled to the 30 m fog
| | Blighted Sprite | Forest Ghoul | Kostas Mortus |
|---|---|---|---|
| HP | 500 | 250 | 3000 |
| Damage | 30 | 70 per arrow | 80 |
| Attack speed | 1.00 (+20% per hit landed, up to +100%, resets after 5 s) | 1.5 | 0.5 |
| Speed | 9 m/s | 5 m/s | 3 m/s |
| Detection | 35 m, on sight | 35 m, on sight | 25 m, on sight |
| Attack range | 5 m | 22 m (keeps 12–22 m away) | 5 m |
| Loses track at | 45 m | 45 m | 35 m |
| Signature skill | **Pounce:** at 10–15 m, a short crouch, then a leap-dash at 20 m/s for 60 damage and Concuss 1.5 s. 10 s cooldown | **Burst:** on its first attack, then every 20 s: +100% attack speed and 3 homing arrows (35 each) that speed up from 5 to 20 m/s as they close in | **Charge:** at 12–25 m, a 1.5 s wind-up, then a 20 m/s straight charge for up to 25 m. 100 damage, 10 m knockback (blocks casting) and Concuss 3 s. Hitting a tree stuns it for 1.5 s. 15 s cooldown |
| Special | Can be dodged; stops on trees | Trees block its arrows | Takes 50% less damage from the front. Every debuff on it is halved. Immune to pulls and knockbacks |
| Eyes in the fog | Yellow-green | Pale | Red |

---

## 6. HUD (temporary, lightweight)

A single objectives line, for example:

| Moment | Line |
|---|---|
| First fight | "Find a page" |
| Kill objective | "Defeat 20 · 12/20" |
| Objective met | "Clear the field · 3 left" |
| Cooldown | "Cooldown 1:42 · choose a path" |
| Pathway | "Pathway" |

---

## 7. Look and atmosphere

| Element | Setting |
|---|---|
| Direction | Mage Arena-style materials under Silent Hill 2-style lighting |
| Fog | Dark grey-green `#1a1f1c`, opaque at about 30 m (260 m at the camp). The background matches the fog exactly, so no void is ever visible |
| Light | A faint cool moon and a warm wand light (a 15 m cone plus a 4 m glow) |
| Plants | Banana trees and rocks in the fields; bamboo along the pathways; Narra, Mango and Bamboo elsewhere |

---

## 8. Code and tests

| File | Role |
|---|---|
| `scripts/core/map1_rules.gd` | Pure seeded rules: the phases (camp, pathway, entering, combat, cooldown), timers, spawn rolls, objectives, drop odds, exits and encounters |
| `scripts/world/map1_world.gd` | The geometry: the camp, the town and its walls, the pathway pieces with bamboo and walls, the fog curtains, the 3 × 3 wrapping combat tiles, loading and unloading |
| `scripts/main.gd` | Runs the spawner, moves enemies and pages to their nearest copy, page drops, death back to the camp, and the HUD line |
| `tests/simulation/test_map1.gd` | 41 checks: the rules over many seeds, the wrap, the timers, objectives, odds and unloading. They caught 3 deliberately inserted bugs |

**Test results (2026-11-20):**
- Simulation 958, Content 214, Render 165, Mobile 165 and Playthrough 27: **all pass**. The Playthrough bot plays camp, pathway, page, cooldown, 20 kills, exit, a second chunk, then death back to the camp with pages kept.
- **Performance:**
  - Worst case is 11 enemies, 64 fireballs, Ring of Fire and burns.
  - p95 was **7.35 and 7.38 ms** on a quiet machine, a pass against the 7.7 ms budget, but 7.9–11 ms with other programs running.
  - The map itself costs about 3 ms; the rest is enemies and effects.

---

## 9. Open items (Sir to plan)

1. **End state** for Map 1: a boss, an exit to Map 2, or something else.
2. **What the second pathway does:** a risk or reward choice between the two.
3. **New enemy models:** the Infected Hostiles pack is staged but not used, and its animations aren't cleared.
4. **Skill rework** against this roster.
5. **Sounds:** your prioritised list (ambience, fog swell, footsteps and combat music first).
6. The benchmark tool `tests/performance/baseline.gd` still walks the old forest.
