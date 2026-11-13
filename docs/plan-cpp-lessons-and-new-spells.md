# Plan: C++ lessons + three new spells [Sir, approved 2026-11-14]

**Status (2026-11-14): both phases done.** Phase 1: 40 programs (pages 1-5), chant tiers 1-4. Phase 2: pages 6-8 with 24 more programs (64 in all, each `g++ -std=c++17 -fsyntax-only -Wall -Werror`), chant tiers 5-7, `scripts/combat/spell_service.gd` (Dragon's Breath, Firefly, Explosion), Beam VFX imported (CC0 per its itch page, ledgered), HUD cast bar, Grimoire stats. Tests: `tests/simulation/test_spells.gd` (18 checks) and render captures. Dragon's Breath is now 2% x 20 ticks over 10 s with a DarkMagicFX fire cone; Beam VFX removed. Settings > "Infinite Mana + No Cooldown (testing)", off by default. Perf: not measured on a quiet machine (Valorant was running).

Queued to run after the current performance/verification task. Phase 1 first (touches no casting files), then Phase 2.

## Phase 1 — Python -> C++ teaching (all existing content replaced, none kept)

One W3Schools C++ course lesson per page, in course order (https://www.w3schools.com/cpp/). Only as many lessons as pages; later lessons arrive with later pages. All lesson text and code is original (never copied from W3Schools). Each page's code is its own ability, written using only what the course has taught up to that page.

| # | Page | C++ lesson | Code shows |
|---|---|---|---|
| 1 | Scorch and Burn | C++ Intro | first program: `#include <iostream>`, `int main()`, `return 0;` |
| 2 | Cultivate | Get Started | program layout, where execution starts |
| 3 | Ring of Fire | Syntax | statements and `;`, `{ }` blocks, `using namespace std;` |
| 4 | Quick Step | Output | `cout <<`, `endl`, `\n` |
| 5 | Sage Arts | Comments | `//`, `/* */` |
| 6 | Dragon's Breath | Variables | `int`/`double`/`string`, constants, identifiers |
| 7 | Firefly | User Input | `cin >>` |
| 8 | Explosion | Data Types | `int`, `float`, `double`, `bool`, `char`, `string`, `auto` |

Work:
1. `tools/make_code_assembly_bank.py` -> C++ generator, 8 variants per page (64), each checked with `g++ -fsyntax-only`; regenerate `data/puzzles/code_assembly.json`.
2. `scripts/core/page_library.gd` TEACH: C++ lesson, tip, concept tags per page.
3. `scripts/core/chant_engine.gd`: one tier per page lesson, C++ syntax blanks (`#include`/`main`/`return`; `;`/`{}`/`namespace`; `cout`/`<<`/`endl`; comment markers; type names and `=`; `cin`/`>>`; data-type keywords). Unlocked-pages guardrail unchanged. Saved chant levels carry over.
4. `scripts/ui/grimoire_panel.gd`: C++ formatting (braces, `//`).
5. `tools/validate_content.gd` and tests for bank and chants.
6. Docs (`pivot-grimoire-plan.md`, `architecture-rehaul.md`): Python -> C++, page/lesson mapping.

## Phase 2 — new spells (all Spell, Rank E, unlocked from start for testing)

### Dragon's Breath
*Breathe a continuous torrent of flame for 10 seconds, scorching every enemy caught in the blaze. While breathing, you cannot use other attacks, skills or spells.*
- 2% Magic Pow per tick, every 0.5 s for 10 s (20 ticks, 40% in all); Burn 5 s. [Sir, 2026-11-14; was 80% for 5 s]
- Cone from the mouth, 20 m long widening to 5 m, aimed with the camera; trees and walls block it.
- Move and look freely; other attacks/skills/spells locked.
- 50 MP; 20 s cooldown x Spell Mastery. VFX: a fire cone built from DarkMagicFX's fire-ball flame particles (its void_particles shader and flame quad), emitted along the 20 m x 5 m cone [Sir, 2026-11-14; the Beam VFX was dropped and removed].

### Firefly
*Lock on to up to 5 enemies in sight and launch 30 tiny missiles into the sky, which split and rain down on the locked targets.*
- 30% Magic Pow per missile; Burn 5 s.
- Lock: within 30 m, in view and line of sight; >5 in sight -> 5 random (own RNG).
- Missiles per target = floor(30 / targets): 5->6, 4->7, 3->10, 2->15, 1->30.
- Rise, then home; a dead target's missiles retarget to another locked enemy.
- No targets: cast fails, nothing spent. 70 MP; 15 s x Spell Mastery.
- VFX: DarkMagicFX (missiles), StylizedHitFX (impacts).

### Explosion
*Aim at a distant area and channel for 20 seconds. Once fully charged, the locked area erupts in a cataclysmic explosion. While charging you cannot move, look around or use abilities, and taking damage breaks the spell.*
- 1000% Magic Pow once at charge completion, no projectile; Burn 5 s.
- Lock at crosshair point up to 80 m; nothing hit -> point at 80 m dropped to ground.
- Blast: 50 m circle (25 m radius); never hurts the caster.
- Charge 20 s: no move/look/actions; cast in air -> hold airborne until end or break.
- Any damage cancels: MP lost, full cooldown starts. No self-cancel.
- Needs full MP, spends 100% max MP. 5 min x Spell Mastery.
- VFX: ExplosionFX nuke scaled to 50 m.

Each spell: pack imported with the 12 FPS pixel patch + licence ledger, cast pose, HUD cooldown/charge bar, simulation tests (damage, ticks, split, cancel, airborne hold, MP, cooldown), perf budget check.
