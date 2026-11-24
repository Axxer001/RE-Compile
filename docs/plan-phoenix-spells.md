# Plan: Phoenix set [Sir, approved 2026-11-14, defaults accepted]

**Status: implemented 2026-11-14.** Code: `spell_service.gd` (Flight, Call), `player_combat.gd` (Rise), `health_component.gd` (`death_guard`). Tests: `tests/simulation/test_phoenix.gd`, render captures `fp-phoenix-ring.png` / `fp-phoenix-call-rings.png`, rain benchmark `tests/performance/phoenix_rain.tscn`.

Goal: implement and test everything below; do not stop until all suites PASS.

## Flight of the Phoenix [Spell, Rank E, C++ lesson: Operators]
- 80 MP; 1 min cooldown x Spell Mastery; Burn 5 s. Cannot be cast while airborne.
- Climb 5 s to 30 m; choose window 5 s at peak; crash takes 3 s.
- On cast: enemies within 20 m pulled instantly to the cast spot, no damage; Concuss 3 s (-80% move, -80% attack speed).
- A spot can be chosen with LMB at any point in the climb (early cancel) or in the window. No choice by window end -> auto-crash to the cast spot.
- Landing ring: 50 m radius ground decal shown from cast. Locks only on ground inside the ring; sky/outside/walls rejected with a marker.
- Damage: 100% Pow until 2 s of climb, then linear to 500% at 5 s (30 m); value taken when spot is chosen / auto-crash.
- Impact: AoE 20 m radius damage + Burn, knockback to 20 m. ExplosionFX nuke scaled. Trail + pull: DarkMagicFX.
- Player frozen (look allowed), invulnerable, no damage cancel, no fall damage. All other abilities and passives (Sage Arts, Rise heal) gated for the whole cast incl. crash.

## Call of the Phoenix [Spell, Rank E, C++ lesson: Strings]
- 50 MP; 30 s cooldown x Mastery; Burn 5 s.
- Casting state 5 s, frozen like Explosion (hover if airborne); damage does not cancel.
- LMB locks up to 3 areas, 15 m across (7.5 m radius), ground only, max 30 m; invalid aim -> notice. Overlap allowed.
- 3 locked -> cast ends early, rain starts. Timeout with fewer -> rain only on locked. MP + cooldown spent even with 0 locks.
- Each area: 30 basic Scorch-and-Burn fireballs (same size/damage/AoE/Burn/VFX) falling from above over 5 s, spread out (~18 in flight total, never exhaust the 64 pool). Trees/canopy stop them.
- Locked areas highlighted with rings from lock until their rain ends. Player free once casting ends.

## Rise of the Phoenix [Passive, Rank E, C++ lesson: Math]
- Killing a burning enemy: +2% max HP and +2% max MP per kill.
- Resurrection arms after 20 kills this run; counter resets to 0 after use. Effects tab shows "Rise 12/20" then "Armed".
- On death while armed: no run reset, revive in place at full HP (MP unchanged), 2 s invulnerable, blast 200% Pow + Burn, knockback to 20 m; blast kills count toward the next 20.
- Occupies the single passive slot (replaces Sage Arts when equipped).

## Common
- Pages 9-11, 24 g++-checked C++ programs, chant tiers 8-10, Grimoire stats, unlocked from start for testing.
- Procedural sounds: climb whoosh, dive + boom, fire rain, rebirth.
- Tests: Flight curve/timers/invalid locks/auto-crash/knockback/gating; Call locks/early finish/spend/fireball count; Rise heal/arming/revive. Render captures of rings; performance check of the rain.

## Rain performance (measured 2026-11-14, `phoenix_rain.tscn`, 20 Sprites, densest forest seed)
| Run | p50 ms | p95 ms |
|---|---|---|
| No rain, no Burn | 3.4 | 5.3 |
| Every Sprite burning, no rain | 4.6 | 8.4-9.6 |
| Rain on 3 areas non-stop | 4.8 | 8.7-8.8 (quiet machine) |
Nearly all the cost is the burning crowd (per-Sprite Burn embers), not the rain. Trims to the rain's own visuals (no lights, cheap bursts, plain cores) gained nothing measurable and were reverted, so the rain keeps the basic fireball's full VFX. A 20-Sprite burning crowd is over the 7.7 ms p95 budget with or without Phoenix.
