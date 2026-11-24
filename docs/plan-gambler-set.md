# Plan: Gambler set [Sir, approved 2026-11-14, defaults accepted]

**Status: implemented 2026-11-14.** Code: `scripts/combat/gambler_service.gd` (the die, buffs, Addiction, coins, bounces, the purse), hooks in `player_combat.gd` (Let it Ride slot, Heads/Tails casts, Addiction gating), `main.gd` (tick, kills, Heavy Pockets slow, statuses, looks), `stat_container.gd` (`post` multiplier applied last, `remove_sources`), `vfx.gd` (coins, hits, arcs, Tails burst, loot loops), `ui/dice_view.gd` (the HUD die), `hud.gd` (coin counter, gold flash, Addiction tint). Assets: Coin, Coin_Pile, Coin_Pile_2 (Quaternius CC0), Binbun Loot VFX (CC0 per itch page; 12 FPS patched). Tests: `tests/simulation/test_gambler.gd` (40 checks), render `fp-gambler-*.png` (4 checks), perf `phoenix_rain.tscn --gamble=1`.
Sir's Addiction addition (2026-11-14): entry calls `strip_buffs`; while it lasts `StatContainer.buff_block` refuses any modifier that raises a stat (Addiction's own exempt), `can_rise` is false (chants gain nothing), `EffectSystem.buff_blocked["player"]` refuses buff effects, and Cultivate sets nothing; debuffs still land. Tested (5 checks).
Implementation choices inside the spec: a roll's result applies at once (the die then tumbles 0.7 s and lands on it); a low roll that starts Addiction strips buffs first; bounces land instantly along a short gold arc; Heads coins that hit a tree or rock just ring off; Pocket Change / Heavy Pockets looks show on the 6 nearest marked enemies (the coin pile on every one).

Goal: implement and test everything below; do not stop until all suites PASS. All three Rank D, unlocked from start for testing.

## Let it Ride [Spell, Rank D, C++ lesson 14: Switch]
- 0 MP; 5 s cooldown. Roll d6 from its own seeded RNG; animated 3D die (code-built cube with pips) in a HUD SubViewport, player-only.
- 1-3: remove every buff on the player (all sources, Cultivate included); Let it Ride's next cooldown -2 s (5 -> 3). Two low rolls in a row -> "Gambling Addiction"; a 4-6 roll resets the streak.
- 4-5: "Gambler's High" 20 s: +100% Magic Pow, +30% Atk Spd, +30% Mov Spd, +20% Spell Mastery.
- 6: "I JUST HIT THE JACKPOT!" 10 s: +500% Magic Pow, +100% Atk Spd, +100% Mov Spd, +100% Spell Mastery.
- Same buff again refreshes its duration; High and Jackpot stack with each other.
- Gambling Addiction [added by Sir]: on entry every existing buff is removed, and while it lasts the player cannot receive buffs from any source (Cultivate, chants or other effects). Also: all other skills, spells, attacks and passives disabled; Magic Pow x0.1 (applied last), Mov Spd +50%; Let it Ride cooldown 0; its rolls grant no stats. Ends after 2 rolls above 3 in total (not necessarily in a row); low rolls during Addiction do nothing extra.

## Heads or Tails [Attack, Rank D, C++ lesson 12: Booleans] (replaces Scorch and Burn in the attack slot)
- Heads (basic, Atk Spd rate): single-target coin, 30 m range, 15 m/s, 80% Magic Pow (flag in balance tests).
- Tails (special): giant coin, explodes 20 m radius, 120% Magic Pow, applies "Pocket Change" 10 s; 20 s cooldown x Spell Mastery. Re-hit refreshes Pocket Change.
- Pocket Change: a Heads coin hitting an affected enemy bounces to another affected enemy within 10 m, up to 3 bounces, never the same enemy twice, +10% additive per bounce (110/120/130%).

## Where are my Coins? [Passive, Rank D, C++ lesson 13: If...Else] (single passive slot)
- +1 coin per kill, max 10; HUD counter beside the effects tab.
- At 10 coins, gaining or having any active buff (any source) consumes all 10 -> every enemy within 30 m gets "Heavy Pockets": -80% Mov Spd decaying linearly to 0 over 10 s.
- No coins gained while any enemy has Heavy Pockets. Disabled during Gambling Addiction (as are all passives).

## Assets
- Import only Coin, Coin_Pile, Coin_Pile_2 from Downloads\RECOMPILE EFFECTS AND ASSETS\Fantasy Props MegaKit[Standard] (Quaternius CC0).
- Import GodotLootVFX (check/ledger licence; pixel 12 FPS patch).
- Heads: coin mesh spinning + ElementalMagicFX trail tinted gold; StylizedHitFX vfx_hit_01 on hit. Bounce: hit FX + short gold arc.
- Tails: giant coin; ExplosionFX ground explosion tinted gold + StylizedHitFX vfx_big_impact_01.
- Pocket Change: loot_vfx_common over enemy. Heavy Pockets: ground loot ring + small Coin_Pile at feet.
- Gambler's High: StatusFX aura tinted green. Jackpot: loot_vfx_legendary + gold screen flash. Addiction: DarkMagicFX void aura + purple desaturated tint.
- Procedural sounds: dice rattle, coin clink, ka-ching, jackpot fanfare, Addiction thud.

## Work
- Pages 12-14, 24 g++-checked C++ programs, chant tiers 11-13, Grimoire stats.
- Tests: seeded roll outcomes, streak/Addiction entry and exit, stacking/refresh, gating; Heads damage, bounce chain, Pocket Change refresh; coin cap, consume, decay, coin block. Render captures of die and effects; performance check.

## Measured 2026-11-14 (`phoenix_rain.tscn --gamble=1`: 20 Sprites all with Pocket Change and Heavy Pockets, Heads 5/s with bounces, Tails every 2 s)
| Run | p50 ms | p95 ms |
|---|---|---|
| No Gambler load | 3.84 | 6.01 |
| Gambler worst case | 4.46 | 7.59 |
A second pair ran on a busier machine (5.3 / 4.9 p50), so the numbers are indicative: about +0.6 ms p50, inside the 7.7 ms p95 budget on the quiet pair.

## Additions [Sir, 2026-11-14, after the first build]
- Fix: Heads dealt no damage. Its packets used damage kind "coin", which `DamagePacket.KINDS` did not list, so every hit was invalid; "coin" is now a valid kind, and the tests check real HP loss.
- All In [Spell, Rank D, C++ lesson 15: While Loop]: 0 MP, 1 min cooldown. 99% of current HP for 10 s of Invincibility; when it ends, any buff active -> every lost HP back and +200% Magic Pow 10 s, otherwise -70% Mov Spd and Atk Spd 5 s. Its win counts as a buff (Addiction strips and blocks it; it spills the coins). The Invincibility itself is not counted as a buff for the bet. 8 g++-checked programs, chant tier 14 (while / do).
- Auras: every Gambler buff has its own look, low round the body: High green motes; Jackpot a gold loot ring; All In's Invincibility a silver ring; All In won a wider crimson ring. The ground rings drop their light pillar and centre glow. Render check: with all four on, fewer than 5% of the forward view's samples change.
- Let it Ride [Sir, 2026-11-14]: the die finishes rolling before anything happens. The face is decided at the cast and its effects land 0.95 s later, when the HUD die settles (`GamblerService.LAND_S`, `pending`, `land()`). The cooldown starts at the cast, and a second cast while the die tumbles is refused ("rolling").
- Gambler's High's aura is now a small green ground ring, because Sage Arts already wears the green StatusFX motes.
