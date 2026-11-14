# Pivot plan: RE:Compile → fantasy FPS "bullet heaven" (Grimoire MVP)

Status: draft 1, 2026-11-11. Source documents: `Downloads/RE_Compile_GDD.md` and `Downloads/RE_Compile_Technical_Spec.md`.
This supersedes `architecture-rehaul.md` (bullet-time shooter) for new work. The shooter build stays runnable until each
system is replaced; nothing is deleted, and retired code moves to `reference/`.

## 1. What the new game is

- **Genre and loop:** first-person fantasy "bullet heaven" (inspired by Mage Arena and HoloCure). Explore the Dark Forest, pick up scattered grimoire **pages**, unlock each one with a **code-ordering puzzle**, equip abilities, kill Blighted Sprites, level up, and rank up from E to D.
- **Combat:** fireball attacks plus 2 skills, 3 spells and 1 passive, driven by 6 stats (HP, MP, Magic Pow, Mov Spd, Atk Spd, Spell Mastery).
- **Learning layer:** each unlocked page teaches C++ (one beginner lesson per page; Python retired 2026-11-14). **Spell Chanting** (fill-in-the-blank code) force-levels a stat, and difficulty is capped by the pages you've unlocked.

### Teaching language: C++ [Sir, 2026-11-14]

All teaching content is C++ (Python retired). Each page teaches one beginner C++ lesson, in course order. Its code uses only what that lesson and the earlier ones teach, and all text is original.

| # | Page | C++ lesson | Code shows | Chant tier |
|---|---|---|---|---|
| 1 | Scorch and Burn | Intro | `#include <iostream>`, `int main()`, `return 0;` | 1: program structure |
| 2 | Cultivate | Get Started | program layout; execution starts in `main` | 1 (once unlocked) |
| 3 | Ring of Fire | Syntax | `;`, `{ }` blocks, `using namespace std;` / `std::` | 2: syntax |
| 4 | Quick Step | Output | `cout <<`, chaining, `endl`, `\n` | 3: output |
| 5 | Sage Arts | Comments | `//`, `/* */` | 4: comments |
| 6 | Dragon's Breath | Variables | `int`/`double`/`string`, `const`, `=` | 5: variables |
| 7 | Firefly | User Input | `cin >>` into a declared variable | 6: user input |
| 8 | Explosion | Data Types | `int`, `float`, `double`, `bool`, `char`, `string`, `auto` | 7: data types |

The puzzle bank is `data/puzzles/code_assembly.json`, made by `tools/make_code_assembly_bank.py`, which compiles every variant with `g++ -std=c++17 -fsyntax-only -Wall -Werror`. Saved chant levels carry over unchanged.


## 2. Reuse map

About 55–60% of the current code carries over.

### 2.1 Keep almost as is

| Current system | Files | New role |
|---|---|---|
| Damage pipeline | `damage_packet.gd`, `health_component.gd` | All ability damage. Its "each action hits once" dedup fits AOE blasts (one blast = one action id). Orbitals need a per-orb re-hit interval (§4.4) |
| Action clock | `combat_controller.gd` | Cast timing: windup/active/recovery for basic and special attacks and skill casts; Atk Spd sets the basic attack's interval |
| Fire zones and AOE | `hazards.gd` (frag radius + falloff, molotov fire ticks per body) | Fireball explosion AOE; its rate-limited fire ticks become the starting point for the Burn effect |
| Enemy AI | `shambler.gd` (nav grid, senses, idle/chase/windup/attack/dead, Quaternius body and clips) | **Blighted Sprite**: retune to 120 HP, 5.5 m/s, aggro 16 m / de-aggro 24 m, 0.35 s windup, 12 damage every 1.2 s, and add a Disengage (return to origin) state |
| Navigation | `navigation_grid.gd` | Forest pathing |
| Missions | `objectives.gd` | Mission tracker ("Defeat 20 enemies") |
| Session and time | `game_session.gd`, `time_service.gd` | Run state; TimeService stays available for slows and freezes |
| Settings and pause | `settings.gd`, `pause_menu.gd`, `settings_panel.gd`, `input_router.gd` (rebinds, wheel pulses) | Unchanged; only the action list changes (§3) |
| Pickups | `pickup3d.gd`, `interactable3d.gd` | Page pickups on F |
| Puzzle UI groundwork | `terminal3d.gd`, `terminal_panel.gd`, `hack_puzzles.gd` (Python snippets, multi-choice) | Base for the **Code Assembly** and **Spell Chant** UIs (§4.6) |
| Arms rig | `arms_rig.gd` + WRAD ARMS | Casting hands: open palm / fist presets, IK targets for spell poses |
| Look and feel | `art_direction.gd` (night grade, fog, practical lights), `spring.gd`, `weapon_view.gd` springs | The Dark Forest mood fits the L4D2-style grade directly; springs drive hand sway and recoil |
| Tooling | `verify.ps1`, all suites, mutation habit, encrypted export, content validator, licence ledger | Unchanged gate |
| Arena builder | `greybox.gd` | Rebuild as a Dark Forest grey box (trees as pillars, clearings, page spots) |

### 2.2 Keep but rework

| File | Change |
|---|---|
| `fps_controller.gd` + `movement_tuning.gd` | Retune to Tech Spec §2.1. Turn **dash and double jump back on** (they're behind the `dash_charges` / `air_jumps_max` flags). Shift becomes dash, not sprint. Run speed is read from the **Mov Spd** stat. Keep the Source core (tick order, friction, air accel, step-up, snap). See decision D1 for the Apex tech layer |
| `weapon_definition.gd` → `ability_page.gd` | The same Resource pattern, re-fielded: type, MP cost, cooldown, rank requirement, damage % of Magic Pow, effect, code lines, lesson, hints |
| `inventory.gd` | Becomes the **page collection** plus the **loadout** (1 attack, 2 skills, 3 spells, 1 passive). Keep its no-duplicate / no-silent-loss guarantees |
| `inventory_panel.gd` | Becomes the **Grimoire** UI (Grimoire tab + Player ID tab) on Tab |
| `player_combat.gd` | Becomes the **spellcaster**: slot input → ability execute, MP spend, cooldown check, rank gate |
| `hack_puzzles.gd` | Becomes `PageDatabase` puzzle content (5 line-ordering puzzles) plus `ChantEngine` templates |
| HUD (inside `main.gd`) | The GDD layout: top-left Level/Rank/HP/MP, bottom-centre action bar with cooldown overlays, top-right mission. Enemy HP bars |
| `death_panel.gd` | Death and respawn |

### 2.3 Retire to `reference/`

- **Guns:** weapon data and `.tres` files, ammo, reload, ADS, spread and recoil patterns, the Quaternius gun models and viewmodels. Ranged ray code is partly reused for fireball aim.
- **Shooter and survival leftovers:** bag tiers, loot items (laptop, CRT, analyser), the bat and katana, throwables as items (frag and molotov logic lives on inside hazards), `endurance_component` (unless reused for dash), `lofi_view` (only its camera-kick part might stay), and the campus texts in `hack_puzzles`.
- **Bullet-time ability** (Q is now Skill 2). The settings menu's sprint toggle goes too, since there's no sprint.

## 3. New input map

| Key | Action | Was |
|---|---|---|
| WASD / Space / Ctrl | run / jump + double jump / crouch + slide | same |
| Shift | **dash** | sprint |
| LMB / RMB | **basic / special attack** | fire / aim |
| E | **Skill 1** | interact |
| Q | **Skill 2** | bullet time |
| 1 / 2 / 3 | **Spell 1–3** | weapon slots |
| F | **interact** (pages, doors, NPCs) | flashlight |
| Tab / Esc | Grimoire + Player ID / pause | inventory / pause |

Removed: reload (R), drop (G), throw, cycle throwable, flashlight, slot 4. The rebinding menu keeps working; only `Settings.ACTIONS` and the labels change.

## 4. New systems

| # | System | Notes |
|---|---|---|
| 4.1 | `StatContainer` | Base stats plus points. Per point: HP +15, MP +10, Pow +5, Spd +0.25 (cap 22), AtkSpd +0.20 (cap 12), Mastery +1.5% (soft 45% at ×0.5 gains, hard 65%). Buffs from `StatusModifier` (multipliers and flats) are applied on top |
| 4.2 | `Progression` | EXP to the next level = floor(100·L^1.4). Points per level = 1 + floor(L/10). Rank up gives 5×rank index points; page unlock gives 3. Each source's EXP is set per the Tech Spec §1.3 |
| 4.3 | `EffectSystem` | Effects keyed by id per target. Re-applying the same effect refreshes its duration with unchanged potency; different effects coexist; each has its own timer. **Burn**: 2% Pow per second, 5 s (basic) or 10 s (special). Ticks go through DamagePacket, with action id = effect instance |
| 4.4 | `ProjectileService` | Pooled fireballs that sweep-test each tick, then explode (3.5 m AOE) on contact with an enemy or the world. Special: aims at the crosshair's ground point, large AOE, 15 s cooldown. **Orbitals** (Ring of Fire): 4 orbs at 3 m, lasting 10 s; each orb can re-hit the same enemy every 0.5 s (design value; the GDD says multiple hits per rotation are allowed) |
| 4.5 | `Abilities` | Scorch and Burn, Cultivate (10 s buff, 20 s cooldown), Ring of Fire (30 MP, 15 s cooldown, rank D), Quick Step (5 m teleport along the move direction, forward if none held, 10 s cooldown, with a shape-cast so you can't teleport into walls), Sage Arts (passive, rank D) |
| 4.6 | `GrimoireSystem` | **PageDatabase** (5 `ability_page.tres` files). **CodeOrderValidator**: drag lines into order, compare against the correct sequence, retry with no penalty. **ChantEngine**: pick a template from the unlocked pages' lessons, mask tokens by tier, compare the answer after normalising whitespace and quotes. Guardrail: never use a locked page's concept |
| 4.7 | `CombatDirector` | **AggroTracker**: in combat while any enemy is aggroed; after the last one drops, a 10 s cooldown, then out of combat, which drives Sage Arts. **MissionManager**: 20 kills promotes E → D (+300 EXP and +5 points) |
| 4.8 | EXP orbs | Enemies drop a 25 EXP orb on death, collected by walking over it with a short magnet. "Bullet heaven" feel |
| 4.9 | Casting visuals | Hands cast instead of holding guns: a palm-forward basic attack, a two-handed special charge, a self-buff glow for Cultivate, a flash at the teleport, the orbit ring. Uses the arms rig's presets and springs |

## 5. Spec issues to resolve

| # | Issue | Proposal |
|---|---|---|
| S1 | **Q/E mismatch:** Controls say E = Skill 1, Q = Skill 2; the HUD shows [Q] Sk1 [E] Sk2 | Keep the controls table (E = Skill 1) and fix the HUD order to E, Q |
| S2 | The Tech Spec's **cumulative EXP column is wrong**: L5 says 2,752 (actual 2,475), L10 says 12,050 (actual 11,742), L20 says 56,120 (actual 58,579). Per-level values are correct | Use the formula; fix the table |
| S3 | "Hyperbolic decay" cooldown, but the formula is linear `base × (1 − min(M, 0.65))`, and the 45% soft cap appears only in the stat table | Soft cap on stat gain (each point past 45% gives +0.75%); cooldown formula linear as written |
| S4 | Sage Arts rates: GDD says TBD (≈2%/s); the Tech Spec's code restores 3% HP / 5% MP per call with no interval | Treat it as **per second**: 3% HP/s, 5% MP/s |
| S5 | Sprite speed 5.5 m/s is called "slightly slower than player walking", but the player runs at 10 | Keep 5.5 (fine for a bullet heaven, since the player kites); fix the wording |
| S6 | Ring of Fire hit rule says "multiple fireballs per rotation" but gives no re-hit interval | 0.5 s per orb per enemy |
| S7 | Special attack "at a targeted area": cast range is unspecified | A ray from the crosshair up to 40 m; on a miss, detonate at max range |
| S8 | Dash i-frames (0.15 s) protect against what? | All damage, using the existing dash i-frame hook |
| S9 | Re-spec (open question 6) | Out of MVP |
| S10 | Stat **reward from a Spell Chant** is +1 stat **and** +1 level, but a level-up also grants a stat point | Chant level-ups grant no extra stat point (otherwise the chant loop gives 2 per success). Confirm |

## 6. Decisions for Sir

- **D1: Movement tech.** The GDD asks for run, dash, crouch, slide, jump and double jump with "polished physics". The current controller also has the full Apex layer (lurch, mantle, superglide, wall bounce, climb, surf).
  - **(a)** Keep all of it, retuned (more mobility, fits a bullet heaven).
  - **(b)** Keep only the Source core plus the GDD moves, and park the Apex tech behind flags.
  - Recommendation: **(a)**, keeping the tech gated behind flags so it can be tuned off.
- **D2: Hands.** Keep the WRAD arms for casting (recommended), or switch to a floating-grimoire / staff viewmodel.
- **D3: Art.** Keep the L4D2-style night grade for the Dark Forest (recommended, almost free) or go brighter for a fantasy tone.
- **D4: Guns.** Retire them to `reference/` (recommended), or keep one as a debug weapon.
- **D5: Scope order.** The milestones below, or Grimoire-first if the teaching loop matters most for a demo.

## 7. Milestones (each ends with all suites green)

| # | Milestone | Content | Reuse share |
|---|---|---|---|
| P0 | Pivot | New input map; retire guns/loot to `reference/`; `ability_page.gd`; StatContainer + Progression + EffectSystem (headless, tested) | High |
| P1 | Movement | Retune to Tech Spec §2.1; dash and double jump on; Mov Spd drives run speed | Very high |
| P2 | Combat core | Fireball projectiles, AOE, Burn, Special with cooldown; casting hands; MP and cooldowns; Atk Spd interval | Medium |
| P3 | Enemy and director | Blighted Sprite (from the shambler); aggro tracker; EXP orbs; Mission 20 kills → Rank D | High |
| P4 | Abilities | Cultivate (pre-equipped), Quick Step, Ring of Fire, Sage Arts; rank gating | Medium |
| P5 | Grimoire | Page pickups; Code Assembly puzzle; page view (code, lesson, hints); loadout equip; Player ID tab; stat allocation | Medium (puzzle UI reused) |
| P6 | Spell Chanting | Templates and tiers from §3.3; masking; answer check; difficulty per stat; guardrail; rewards | Medium |
| P7 | HUD and forest | GDD HUD; Dark Forest grey box with 4 page spots and sprite spawns; tuning pass | High |

**Rough effort:** P0–P7 at the pace of these agent sessions is about 4–6 working days. P5–P6 (puzzle UX) is the long pole.

**Ownership:** the main session owns `main.gd`, `fps_controller.gd`, `player_combat.gd`, `weapon_view.gd` and the tests. New systems (StatContainer, Progression, Effects, ChantEngine, PageDatabase) can be built as new files in parallel.

## 8. Decisions (2026-11-11, Sir: "Yes, recommended")
- D1: keep the full Apex movement tech, gated behind flags; the GDD moves (dash, double jump) come on.
- D2: WRAD arms for casting.
- D3: keep the L4D2-style night grade for the Dark Forest.
- D4: guns retired to `reference/`.
- D5: build in order P0 → P7.
- Spec issues S1–S10 resolved as proposed in §5.

**Work split:**
- **Main session:** P0 input map and gun retirement, then P1 movement, plus its own files (main, controller, player_combat, weapon_view, tests registration).
- **This session:** new headless systems as new files: `ability_page.gd`, `stat_container.gd`, `progression.gd`, `effect_system.gd` and their tests. Then PageDatabase, CodeOrderValidator and ChantEngine (P5/P6 data).


### Training Field [Sir, 2026-11-14]

A separate 200 x 200 m daytime practice field (`scripts/world/training_field.gd`), built at world x 1000 so it never overlaps the forest. A Binbun portal (CC0) east of the camp fire leads there and a second portal leads back. Portals check only the player, so enemies never pass, and both are sealed (red) while the player is in combat. Entering turns the world to day (sun, blue sky, light fog) and hides the forest; leaving, or a restart or death, restores the night.

| Area (local metres) | Contents |
|---|---|
| North-west | The movement sandbox's drills: slide gap, 1/2/3 m ledges, ramps, stairs, jump course, run walls, drop tower, surf wedge, clamber |
| North-east | Rock formations: boulder field (1-2.5 m), rock stairs 1-5 m, a 7 m climbing tower with a 3.5 m ledge, an arch to slide under, scattered cover |
| South-west | 18 training dummies: still, on 2-3 m platforms, and strafing. They take no damage and never die, but show every hit as a damage number and a running total (clears 3 s after the last hit). |
| South-east | Target range: 15 boards at 10, 20, 30, 50 and 80 m from a firing line; a hit flashes the board |

Training hits never count toward the profile's records and give no EXP.
