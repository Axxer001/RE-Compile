# Plan: player rescale + Dark Forest roster [Sir, approved 2026-11-15, defaults accepted]

Goal: implement and test everything; do not stop until all suites PASS. No commit/push without Sir's word.

## 1. Player rescale (stat_container.gd, progression.gd)
- Base: max_hp 100 -> 1000; magic_pow 100 -> 1000; max_mp 100 (unchanged); mov_spd, atk_spd, spell_mastery unchanged.
- Per point and chant gain: max_hp +5 -> +50, magic_pow +5 -> +50 (max_mp unchanged).
- EXP curve: 100 x l^1.4 -> 50 x l^1.3. Kill EXP per enemy: Sprite 25, Ranger 35, Mortus 200. Level points and rank missions unchanged.
- Page % values unchanged (Sir tunes skills later). Saves: allocated points carry over at the new value.

## 2. Player crowd control
- Concuss (-80% Mov/Atk Spd) does NOT block casting.
- Knockback and stun/control DO block casting for their duration.

## Blighted Sprite [Common]
- Melee. HP 500, damage 30, attack speed 1.00 (+20% per hit landed on the player, max +100% / 5 stacks, reset after 5 s without a hit), speed 9 m/s, detection 50 m with line of sight, attack range 5 m. Packs of 4, max 20 alive.
- Pounce: at 15-20 m with line of sight, jump-dash at 20 m/s in a straight line (dodgeable, stops on trees); hit = 60 damage + Concuss 1.5 s (-80% Mov/Atk Spd). Cooldown 10 s.
- Anim: existing set + UAL NinjaJump_Start/Idle/Land for Pounce. VFX: StylizedHitFX on hit.

## Forest Ranger [Common]
- Ranged. HP 250, damage 70, attack speed 1.5, speed 5 m/s, detection 50 m with line of sight, range 30 m. Arrow 15 m/s.
- Keeps 15-30 m; backs off when the player is within 10 m.
- Burst: on first attack, then every 20 s: +100% attack speed and 3 homing arrows (instead of normal shots), 35 damage each. Speed 5 m/s until 20 m from the player, ramping to 20 m/s at 10 m. Gentle homing; trees block arrows; player can't destroy arrows. No status effect (magic glow only).
- Model: Quaternius base body + ranger outfit + bow. Check UAL1/2 for bow clips; if none, IK aim pose. VFX: ElementalMagic projectile tinted green; glowing trail for Burst arrows.

## Kostas Mortus [Elite]
- Melee. HP 3000, damage 80, attack speed 0.5, speed 3 m/s, detection 30 m with line of sight, attack range 5 m. Normal melee between charges. Takes 50% less damage from the front.
- Charge: when the player is 15-30 m away, wind up 1.5 s, then charge at 20 m/s in a straight line toward where it saw the player, up to 30 m or until it hits the player. Hit = 100 damage, 10 m knockback, Concuss 3 s. Hitting a tree or rock stops it and stuns Mortus 1.5 s. Cooldown 15 s.
- Every debuff and effect on Mortus is halved in duration, stat reduction and damage. Immune to pulls, knockback and launches.
- 1 per clearing, guarding a page.
- Model: Sprite body x1.6, darker emissive skin, DarkMagicFX void aura. Anim: slowed Walk; Crouch_Idle wind-up; Sprint charge. VFX: ExplosionFX ground streaks + StylizedHitFX big impact.

## All
- All player effects (Burn, Concuss, Scorched Slow, Phoenix, Gambler) apply to Sprite and Ranger at full value; Mortus per the halving rule.
- Tests: stats/EXP curve; each enemy's attacks, ranges, cooldowns, LOS, ramp/homing, charge path/stop/stun, halving/immunity, casting lockout on knockback. Render captures, performance check.

## Status: implemented 2026-11-15 (uncommitted)

| Item | As built |
|---|---|
| Ranger animation | UAL1/UAL2 have no bow clips (86 clips). Uses `Pistol_Aim_Neutral` / `Pistol_Shoot` with a code-built bow on `hand_l` and code-built arrows (green trail on Burst). |
| Population | Sir: keep 224 hostiles, Sprites in packs of 4, at most 20 awake. Ranger pairs in every 4th zone; one Mortus per page clearing (max 3). |
| De-aggro | Sprite 60 m, Ranger 60 m, Mortus 42 m. |
| Pounce | 0.3 s crouch, straight dash that stops on walls. |
| Mortus knockback | 30 m/s push over ~10 m with a casting lock; Concuss alone does not lock. "Front" is judged from the player's position (90° cone). |
| Flight's pull on Mortus | Still Concusses, does not move it (displace-immune). |
| Arena | Rangers and Mortus parked in reserve; spawn clearance 20 m (forest 54 m). |
| Tests | `tests/simulation/test_roster.gd`; render captures `fp-roster-*.png`, `fp-ranger-arrows.png`. |

## Amendment 2026-11-15b [Sir]

| Enemy | Change |
|---|---|
| Blighted Sprite | Attack range 1.5 m (strike lands within 2 m). Pounce within 10 m (not under 5 m [design]), 2 s crouch, 15 s cooldown. Climbs (unchanged). Gives up past 80 m. |
| Forest Ghoul (was Forest Ranger) | Renamed everywhere (file `forest_ghoul.gd`, kind `ghoul`, ids `ghoul_N`). Normal arrows 10 m/s. No arrow trails (Burst arrows keep a larger glowing green head). Cannot climb. Gives up past 100 m. |
| Kostas Mortus | Attack range 1.5 m (strike lands within 2 m). Cannot climb. Gives up past 50 m. |

Non-climbers path on main's ground grid (`nav`), climbers on `nav_climb`.
