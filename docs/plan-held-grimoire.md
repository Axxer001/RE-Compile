# Plan: held grimoire casting rehaul [Sir, approved 2026-11-20]

Goal: implement and test everything; do not stop until all suites PASS. No commit/push without Sir's word.

## Assets (C:\Users\Axxer\Desktop\GAME ASSETS)
- Use: `Held Grimoire/Godot` (HeldRig.tscn, PageInk.gd, Rose Compass Grimoire, Ember Wand, EB Garamond + Archivo fonts, OFL), `Ember Wand` (WandView.tscn and its movement clips), `Rose Compass Grimoire`.
- DO NOT use anything from `Dragon Grimoire` (its `Mage Arena - Book Source.zip` holds files extracted from Mage Arena: copyrighted). Verify that the Rose Compass rig references none of those files.
- Fix the res:// paths per `Held Mode.md` when moving into the project; ledger the assets and fonts in docs/asset-licenses.md (origin: Sir's GAME ASSETS).

## Input
- Unbind Q and E (skill_1 / skill_2 actions removed); reserved for later.
- 1-4: select spell page 1-4 in the held grimoire. 5: turn to the status page.
- LMB: cast the active page. RMB: its second mode (attack pages' special) if it has one; otherwise nothing.
- Tab still opens the full Grimoire panel (the asset's stow/equip hook is unbound).

## Loadout
- 4 spell slots + 1 passive. No separate attack or skill slots.
- Any non-passive page fits a spell slot. Attack pages (Scorch and Burn, Heads or Tails): basic attack on LMB (held LMB repeats at the Atk Spd rate), special on RMB.
- Skill pages (Cultivate, Quick Step) become spells and go into spell slots (keep their numbers; no MP cost unless they had one).
- Save migration: old attack page -> slot 1, then skills and spells fill slots 2-4 in their old order; extras beyond 4 are unequipped but stay unlocked; passive kept.

## Page turning
- A page-to-page turn always takes 0.5 s total, whatever the distance. Each page between is flipped individually (page 1 -> 4 plays 3 flips, each 0.5/3 s). Use the asset's page-turn animation at the matching speed.
- The active spell changes once the turn finishes. Casting during a turn is ignored.
- Page 5: the status page. Shows the equipped passive and every active effect, buff and debuff on the player with time left, in the same page design, ink and fonts as the spell pages. Not castable (LMB/RMB do nothing there).

## Hands and HUD
- Held grimoire in the right hand, wand in the left by default; Settings toggle mirrors the whole rig. Spells leave from the wand tip.
- Replace the code-built wand (wand_view.gd) with the Ember Wand and its movement clips (wire the controller's states to the clip names in `Movement Guide.md`).
- Remove the loadout or inventory bar at the bottom of the HUD. The book's live page ink shows the active page, cooldowns and ready state (no separate HUD cooldown display).

## Tests
- Input map (Q/E unbound; 1-5); loadout of 4 + passive and save migration; attack page LMB/RMB; skills cast as spells; 0.5 s turn with the correct number of flips for every distance; cast blocked mid-turn; status page lists passive and effects; hand swap; HUD bar gone. Render captures of both hand layouts and the status page.

## Status: implemented 2026-11-20 (uncommitted)

| Item | As built |
|---|---|
| Book asset | `assets/held_grimoire/rose_compass_grimoire.glb`. **Its rig and meshes match the Mage Arena book** (43 shared bones, `magebookbase`/`magebookp1-4`, PageFlip1-4); Sir was told and chose to use it as-is. Ledgered as NOT CLEARED: replace before shipping. |
| Wand | `assets/held_grimoire/ember_wand.glb` + `scripts/player/ember_wand.gd` (pack's WandView, controller states -> clips); `wand_view.gd` removed. |
| Rig / ink | `scripts/player/held_rig.gd`, `scripts/ui/page_ink.gd` (pack ports; game clock, MP and cooldowns from player_combat). Right-hand book = the left pose mirrored, then spun half a turn so the ink reads upright. |
| Input | `page_1`..`page_5` on 1-5; `skill_1`/`skill_2` (E/Q) removed; key layout 4 (older saved bindings dropped). |
| Loadout | `spell_1`..`spell_4` + `passive`; start: Scorch and Burn (1), Cultivate (2). `migrate_loadout()` for old dictionaries (loadouts are not saved: lost on death). |
| Turns | `TURN_S` 0.5 s, one flip per page crossed (rig.flips_drawn); open page changes at the end; no casting mid-turn or on page 5. |
| Settings | "Grimoire in the left hand" toggle (`book_hand`, saved under [display]). |
| HUD | Loadout bar removed; page ink shows state/cooldowns. |
| Tests | `tests/simulation/test_held_grimoire.gd`; render `fp-held-right/left/status/cast.png` (copies in `production/qa/evidence/2026-11-20-*`). |

## Animation coverage [Sir, 2026-11-20: use every pack animation]

| Clip | Trigger | Used |
|---|---|---|
| Wand Idle / Walk / Run / Backpedal / StrafeLeft / StrafeRight | ground state by speed and held move | yes |
| Wand CrouchHold / CrouchWalk | crouching, still / moving (also a dead slide) | yes |
| Wand StepUp | `steps_up` rises | yes |
| Wand Jump / Fall / Land | AIR rising (and `geo_jumps`) / AIR falling / touchdown | yes |
| Wand DoubleJump | `air_jumps` spent in the air | yes |
| Wand AirStrafe | `lurches` rises | yes |
| Wand Dash | DASH state | yes |
| Wand SlideEnter / Slide / SlideExit / SlideJump | entering SLIDE / SLIDE / standing up out of it / `slide_jumps` | yes |
| Wand SlopeSurf | SLIDE on a floor steeper than 0.35 rad | yes (wired; not unit-tested: needs a real slope) |
| Wand WallClimb / WallRunLeft / WallRunRight | WALLCLIMB; sideways > 1.5 m/s left / right | yes |
| Wand WallBounce / WallPush | `bounces`, `mini_bounces`, `wallhops` / `wall_pushes` | yes |
| Wand LedgeCatch / LedgeHang / ShimmyLeft / ShimmyRight / MantlePull | mantle phase grab / hang / hang moving / pull | yes |
| Wand MantleHop / MantleBoost / Superglide / LedgeDrop | `mantle_hops` / `mantle_boosts`, `end_boosts` / `superglides` / `mantle_cancels` | yes |
| Wand Lunge | `lunges`, `punch_boosts` | yes |
| Wand Cast / Attack | an accepted spell, skill or special / an attack page's basic | yes |
| Wand Channel | Dragon's Breath or Explosion running | yes |
| Wand Damage / Stagger | a hit < 100 / a hit >= 100 or a fall stun (`stuns`) | yes |
| Wand Equip / Stow | spawn and a new run / death | yes |
| Book Equip | the equip lift (forwards), the stow on death (backwards) | yes |
| Book Idle | rest pose once equipped and no turn running | yes |
| Book PageFlip1-4 | each flip of a turn: crossing pages j/j+1 plays PageFlip(j+1), backwards when turning back; page 5 shares folio 4 | yes |
| Rig page-turn leaf, cast snap, hit reaction, softened movement mirror | every flip / every cast / every hit / every frame (book follows the wand's Motion) | yes |

Unused: none.
