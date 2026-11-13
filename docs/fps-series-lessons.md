# Lessons from StayAtHomeDev "Godot FPS Series" (26 videos), for RE:Compile FPS

Source: caption transcripts (no frames) of episodes #1–#24, read 2026-11-09. Patterns only; no code copied.
Compared against the FPS project as it stood on 2026-11-09 (`fps_controller.gd`, `weapon_view.gd`,
`weapon_definition.gd`, `health_component.gd`, the actors).

## Already covered by the project

| Lesson (episode) | Where it already lives |
|---|---|
| Weapon as an exported `Resource`: damage, ammo, pellets, spread, fire mode (#6, #8, #9) | `weapon_definition.gd` |
| Definition separate from per-copy state (#10) | `weapon_definition.gd` + `weapon_instance.gd` |
| States decide *when*, controller *does* (#7) | `combat_controller.gd` actions (windup → active → recovery) |
| Health component with damage/heal/died signals, clamped (#13) | `health_component.gd` + `damage_packet.gd` |
| Base pickup with can/apply (#11) | `pickup3d.gd` |

## Gaps worth taking (highest value first)

| # | Pattern (episode) | Gap in the FPS project | Suggested change | Fits |
|---|---|---|---|---|
| 1 | **Spring utility** (stiffness/damping; settles with overshoot; recoil example 80/10) (#18, #22) | `weapon_view.pose()` lerps fixed curves and snaps back to `rest` (`if t > total - 0.05: xf = rest`) | One `Spring` helper (position + rotation). Actions *kick* it; the viewmodel settles naturally, with no snap | M5a feel |
| 2 | **Viewmodel bob** scaled by ground speed (#21) | No bob | Sine bob × (speed / SPRINT), zero when airborne; stronger while sprinting, damped while crouched | M1 feel |
| 3 | **Look sway** from mouse delta (#19) | None | Feed `_look_queue` into the spring target, clamped | M1 |
| 4 | **Strafe tilt** (#20) and **camera run tilt** (#2): pitch 0.1, roll 0.25, caps 1° / 2.5°, scaled by velocity·right | None | Camera roll from lateral velocity; slight weapon roll | M1 |
| 5 | **Position lag** on jump/fall/crouch/stairs from camera-Y velocity, with dead zone and cap (#23) | None | Spring target = −(cam_y velocity), clamped | M1 |
| 6 | **Idle breathing**: slow sine + spring (#18) | Static `rest` | Small sine on `rest`; scale up when endurance is low (ties into `endurance_component`) | M2 dread |
| 7 | **Fall kick**: 0.3 s, triggers above ~5 m/s, uses previous-frame Y velocity (#2) | None | Camera pitch/drop on hard landings; pair with a noise event (`noise_service`) | M2 |
| 8 | **Damage kick toward the hit direction** (#2) | None | Camera kick from `DamagePacket` source; also feeds horror readability | M2 |
| 9 | **Stair stepping** by probing step height (#3) | Capsule-only controller | Only if two-floor stairs (M3) snag; prefer ramps in the collision first | M3 |
| 10 | **Animation blend + random phase**: 0.2 s crossfade; random idle start so a group isn't in sync (#15B, #15C) | Actors call `anim.play(want)` with no blend; all start at frame 0 | `anim.play(want, 0.2)` (or `default_blend_time = 0.2`); `anim.seek(randf() * len)` once on spawn | M2 actors |
| 11 | **Enemy melee loop**: stop, face, attack, re-check range at the end (#15C) | Check `shambler.gd`/`tracer.gd` against it | Attack→locomotion only after the clip ends | M2 |
| 12 | **Trigger volumes + Triggerable component**: target names, once/exit/delay, `map_entities` group (#16) | Pressure/threat is global | Room-scoped scripted beats (lights fail, door locks, spawn) from data | M3 building |
| 13 | **Muzzle flash**: a brief light + sprite (#24) | Recoil kick only | Short OmniLight pulse. In lo-fi dark it doubles as a threat cue (it lights up the room) | M5a |

Design guard rails from the series: clamp every feel effect, put each behind a setting (motion sickness),
scale by speed, and never let feel code change hit timing (commit stays at `windup_s`).

## Skip

- TrenchBroom pipeline (#4, #5, #12): rooms are hand-built in Godot.
- Basic FPS controller (#1): already done better (crouch probe, carry factor).
