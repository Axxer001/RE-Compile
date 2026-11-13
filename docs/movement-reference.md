# Movement reference: Source/Quake model + Ultrakill, Beyond Citadel, Apex notes

Compiled 2026-11-09 for R1 (movement). Algorithms are paraphrased as maths; **no third-party code is copied**.
Unit conversion: 1 Source/Quake unit ≈ 1 inch = 0.0254 m (the player-scale convention).

## 1. Licences: what we can and can't use

| Source | Licence | Use in RE:Compile |
|---|---|---|
| Valve Source SDK 2013 `game/shared/gamemovement.cpp` | Source 1 SDK licence (Source-engine products only) | **Read for the algorithm; never copy code.** Re-implement from the maths below |
| ioquake3 `code/game/bg_pmove.c` | GPL v2+ | **Read only.** Copying it would force RE:Compile to be GPL |
| [modcommunity/dot-fps-controller](https://github.com/modcommunity/dot-fps-controller) | **MIT**, Godot **4.7+** | **Can be used directly** with attribution in `asset-licenses.md`. It has air strafing/bhop (30-unit air cap), surf, stairs, ground snap, crouch-jump, coyote time, jump buffer, slide, launch, wall run, wall jump and wall slide (the extras are off by default) |
| [BirDt/bhop3d](https://github.com/BirDt/bhop3d) | AGPL v3 | Don't use |
| pbentes/Source-Engine-Movement, SUCC, ebucario | Licence unclear / work in progress | Don't use until licences are confirmed |

**Recommendation for R1:** either take `dot-fps-controller` (MIT, same Godot version) as the base and adapt it to our state machine, `TimeService` and dash/double-jump spec, or write our own controller using the maths below. Adopting it removes most of R1's risk; the cost is learning its structure (`DotFpsMotor`, `DotFpsTunables`, `DotFpsState`). Decide after a 1-hour spike in which we drop it into the greybox.

## 2. The Source movement pipeline (one tick)

Order matters. In Source, **jump is checked before friction**, which is what makes bunny-hopping possible: land and jump in the same tick and friction never applies.

```
1. StartGravity (half the gravity step)
2. CheckJump        -> if grounded and jump newly pressed: leave ground, vz = jump_speed
3. if grounded: vz = 0; Friction()
4. grounded ? WalkMove() : AirMove()
5. CategorizePosition (on ground if the surface under you has normal.y >= 0.7, about 45°)
6. FinishGravity (the other half step)
7. if grounded: vz = 0
```

### Friction (ground only)
```
speed = |v_horizontal|;  if speed < 0.1: return
control = max(speed, stop_speed)            # below stop_speed, braking is constant: the crisp stop
drop = control * friction * surface_friction * dt
v *= max(speed - drop, 0) / speed
```

### Accelerate (ground)
```
current = v · wishdir                       # only speed ALONG the wish direction counts
add = wishspeed - current;  if add <= 0: return
v += wishdir * min(accel * wishspeed * dt * surface_friction, add)
```
This reaches full speed in about 1/accel seconds (accel 10 ≈ 0.1 s). That snappy start is half of the "crisp" feel.

### AirAccelerate (the air-strafe trick)
```
capped = min(wishspeed, air_cap)            # air_cap = 30 units ≈ 0.76 m/s
current = v · wishdir
add = capped - current;  if add <= 0: return
v += wishdir * min(air_accel * wishspeed * dt, add)   # note: the uncapped wishspeed scales the gain
```
Because the cap applies only to speed *along* the wish direction, strafing sideways while turning keeps `current` near 0, so you keep gaining speed. That's air strafing; chaining it with landing jumps is bunny-hopping. Air strafing is off with `air_cap = 0`; Quake III has no cap but `air_accel = 1`.

### Slide/step/snap helpers
- **TryPlayerMove:** up to 4 bumps per tick; clip velocity against up to 5 planes. In a crease between two planes, move along their cross product. If velocity ends up opposing the original, stop.
- **ClipVelocity:** `out = in - n * (in·n) * overbounce` (overbounce 1 = a plain slide). Then remove any leftover component pushing into the plane.
- **StepMove (stairs):** try the move flat; also try *raised by step height → move → lowered*. Keep whichever goes further horizontally, as long as you land on a surface with normal.y ≥ 0.7.
- **StayOnGround:** after a ground move, trace down by step height and snap if you hit walkable ground, so you don't fly off ramps or bounce down stairs.
  - In Godot, `CharacterBody3D.floor_snap_length` plus a step-up shape cast covers both.

## 3. Reference constants

| Constant | Quake III | CS:Source | CS:GO | In metres (CS:S) |
|---|---|---|---|---|
| max run speed | 320 u/s | 250 (knife) | 250 | 6.35 m/s |
| accelerate | 10 | 10 (commonly cited 5 in some modes) | 5.5 | (1/s) |
| air accelerate | 1 | 10 (100+ on bhop servers) | 12 | |
| air wish cap | none | 30 u/s | 30 u/s | 0.76 m/s |
| friction | 6 | 4 | 5.2 | |
| stop speed | 100 | 100 | 80 | 2.54 m/s |
| gravity | 800 u/s² | 800 | 800 | 20.3 m/s² |
| jump speed | 270 u/s | ~268 (√(2·800·45)) | ~268 | 6.8 m/s, about 1.14 m high |
| step height | 18 u | 18 u | 18 u | 0.46 m |
| walkable slope | normal.z ≥ 0.7 | 0.7 | 0.7 | ≈ 45.6° |

Sources: the friction values are on the Valve Developer Wiki (`sv_friction`: CS:S 4, CS:GO 5.2); Quake III values come from `bg_pmove.c`. The CS:S/CS:GO accelerate, air-accelerate, stop-speed and gravity figures are commonly cited server defaults; check them in-game with `cvarlist` if exact values matter.

## 4. Fast-shooter layers on top

### Ultrakill (community wiki and speedrun forums; no developer source. Unity units ≈ m)
| Move | Figure |
|---|---|
| Walk top speed | ~16.5 m/s |
| Slide top speed | ~24 m/s (slide speed carries into jumps) |
| Dash | ~49.5 m/s burst, **i-frames** (invincibility), costs 1 of 3 stamina bars; ~1 bar per 1.5 s regen |
| Dash-jump | costs 2 stamina; ~49 m/s |
| Slam (ground pound) | ~100 m/s straight down |
| Wall jump | up to 3 per airtime, reset on landing; a slide wall jump keeps the slide's speed with less height |

The figures conflict between sources, so treat them as feel targets, not specs.

### Beyond Citadel (reviews only; no technical documentation found)
- Double jump, **double dash** (2 charges), corner leaning.
- Momentum is deliberately *less* exaggerated than in its predecessor *The Citadel*: predictable and responsive rather than slippery.
- The final episode adds platforming-focused movement.

### Titanfall / Apex
- A small **boost at the start of a slide**; slide friction depends on the slope (keeps momentum downhill, slows uphill).
- **Double jump cancels existing downward velocity** before applying its lift, so it feels like an air jet rather than a weak push.
- Limited air steering against your current velocity.
- Wall-run feedback: **tilt the camera away from the wall** (Titanfall interview).
- Apex dropped wall running for battle-royale pacing. We're an arena shooter, so it's fine for us.

## 5. Proposed RE:Compile tuning (first pass, metres)

| Parameter | Value | Reasoning |
|---|---|---|
| Run speed | 10 m/s | Between CS (6.4) and Ultrakill (16.5): fast but readable in corridors |
| Ground accel / friction / stop speed | 10 / 6 / 3 m/s | Quake-crisp start and stop |
| Air accel / air cap | 12 / 0.76 m/s | Source-style air strafing on; bhop possible but not dominant |
| Gravity / jump | 20 m/s² / 7 m/s (≈1.2 m high) | Source-like snappy arc |
| Double jump | 6.5 m/s, cancels downward velocity first | Apex/Titanfall feel |
| Dash (Shift) | 25 m/s for 0.15 s, 2 charges, 1.2 s each to recharge, 0.1 s of i-frames | Beyond Citadel double dash + Ultrakill i-frames, scaled to our speed |
| Slide (Ctrl) | +2 m/s entry boost, friction 1 (0 downhill), max 18 m/s, cancel on Ctrl or jump; slide-jump keeps speed | Apex slide + Ultrakill slide-jump |
| Coyote time / jump buffer | 0.1 s / 0.1 s | Standard for forgiveness |
| Step height / walkable slope | 0.4 m / 46° | Source equivalents |
| Later: wall run, wall jump ×3, slam | — | Plug in as extra states (see architecture-rehaul §4.1 and the future-movement notes) |

All of these go in a `MovementTuning` resource, and all movement uses `TimeService.player_dt`.

## 6. Sources
- Valve Developer Wiki, [sv_friction](https://developer.valvesoftware.com/wiki/Sv_friction)
- Valve Source SDK 2013, `src/game/shared/gamemovement.cpp` (GitHub: ValveSoftware/source-sdk-2013), read only
- ioquake3, `code/game/bg_pmove.c` (GitHub: ioquake/ioq3), GPL, read only
- [neon.moe, "FPS movement"](https://blog.neon.moe/2020/04/03/fps-movement): Quake friction/accel, bob 0.6 s, roll from strafe
- [The mathematics of B-hopping](https://graffeggyfrifiadurydd.blogspot.com/2019/07/the-mathematics-of-b-hopping-you-dont.html): jump before friction
- [q3df wiki: groundboosting in the code](https://q3df.org/wiki?p=8)
- [modcommunity/dot-fps-controller](https://github.com/modcommunity/dot-fps-controller) (MIT, Godot 4.7+)
- [ULTRAKILL Wiki: Stamina](https://ultrakill.wiki.gg/wiki/Stamina); [speedrun.com movement strats](https://www.speedrun.com/ja-JP/posts/adk0s); [gamepretty guide](https://gamepretty.com/?p=10622)
- [PC Gamer: Beyond Citadel](https://www.pcgamer.com/games/fps/beyond-citadel-is-a-great-retro-fps-that-i-want-to-recommend-to-everybody-and-nobody/); [PCGamesN: Beyond Citadel](https://www.pcgamesn.com/beyond-citadel/steam-retro-anime-fps-game)
- [Game Developer: getting Titanfall's controls right](https://www.gamedeveloper.com/design/designer-interview-getting-i-titanfall-i-s-controls-just-right); [theanilsson: movement](https://theanilsson.github.io/movement.html)

## 7. R1b spec: Source rules + Apex General Tech (2026-11-09)

The user's direction: **follow Source movement rules first**, then add Apex General Tech on top.
Everything is rebuilt from documented behaviour (the Source pipeline in §2, the Apex Movement Wiki), not copied code.
Tunables live in `movement_tuning.gd`; each tech gets a scripted-input test in `tests/simulation/`.

### 7.1 Source core (audit the existing controller against these)

| Rule | Requirement | Test |
|---|---|---|
| Tick order | gravity half → **jump check → friction (ground only)** → accelerate → move → categorise → gravity half | A jump on the landing tick keeps 100% of horizontal speed |
| Friction | `drop = max(speed, stop_speed) * friction * dt`; none while airborne | Releasing keys at 10 m/s stops within about 0.4 s |
| Ground accel | add only up to `wishspeed` along `wishdir` | Reaches 95% of run speed in about 0.3 s |
| Air accel + cap | the cap (0.76 m/s) applies to `v · wishdir` only; the gain uses uncapped wishspeed | **Air strafe:** strafe + turn 90° in the air ends faster than it started |
| Bunny hop | chained landing jumps lose no speed to friction | 5 timed hops with strafing gain speed; without strafing they hold speed |
| Clip / slide | at most 4 bumps and 5 planes per tick; in a crease, move along the edge | Sliding along a wall keeps the tangential speed |
| Step-up | try flat and raised-then-lowered, keep the farther; land only on normal.y ≥ 0.7 | Walk up the arena's 0.3 m stairs with no jump |
| Ground snap | after a ground move, trace down `step_height`; snap if walkable | Running down a 30° ramp never goes airborne |
| Walkable slope | normal.y ≥ 0.7 (about 46°) | The 45° ramp is walkable; steeper surfaces count as walls |
| Surf (optional) | on surfaces steeper than walkable while airborne: clip, no friction | Later; free once clip is correct |

### 7.2 Apex layer (one state or rule each)

| Tech | Rule (first-pass numbers) | Test (scripted inputs) |
|---|---|---|
| **Lurch** | For 0.2 s after a jump (or a slide jump), a new move input blends velocity toward it: `v_h = slerp_dir(v_h, wish, lurch_strength * (1 - t/0.2))`, losing at most 10% speed per lurch; stacking forward lurches turns more sharply; no lurch after the window | Jump at 12 m/s, then tap strafe right at 0.05 s: the heading turns ≥ 60° with ≥ 85% of speed kept. The same tap at 0.3 s barely turns |
| **Tap strafe** | Lurch driven by rapid repeated forward taps (Apex uses scroll-wheel-bound forward); each new forward press restarts lurch blending; back + side cancels the forward lurches, leaving a pure sideways shift | 5 forward taps in 0.1 s while turning the view 90°: velocity follows the view |
| **Slide boost** (exists) | Keep the one-boost-per-2 s rule; the slide jump keeps slide speed | Already tested; add "slide jump speed ≥ slide speed" |
| **Mantle** | Ledge detector: a forward shape cast hits a wall, a downward cast from above finds a walkable top within 0.5–2.2 m of the feet, and there's room to stand. Jump/forward into it → MANTLE state: pull up and over in about 0.45 s, then exit grounded with a small forward speed | Jump at the arena's 2 m ledge: you end standing on top within 0.6 s |
| **Mantle jump** | A jump during a mantle cancels it into a jump from the mantle point; coyote grace 0.1 s after leaving the mantle | Jump at 0.2 s into a mantle: airborne with an upward velocity, never on the ledge |
| **Gorilla jump** | A mantle jump with no forward input throws you higher (×1.3 jump) | Peak height > the plain mantle jump |
| **Superglide** | During the **last 150 ms** of a mantle: jump, then crouch within **1 physics tick** (16.7 ms at 60 Hz; buffer the pair) → instant slide-speed burst (about 1.5× run speed) while airborne, so no ground friction applies. Input order and the gap are checked from the buffered events, not frame polling | Jump + crouch one tick apart at 0.35/0.45 s into the mantle: speed ≥ 14 m/s. The same pair 3 ticks apart, or outside the window: no burst |
| **Wall bounce** | The shared wall sensor detects contact while airborne with horizontal speed ≥ 6 m/s; a jump within 0.1 s of contact reflects velocity off the wall normal (`v - 2(v·n)n`, keeping 90%) plus `jump_speed` upward; costs no double jump | Slide jump into a wall and jump on contact: you leave the wall with ≥ 80% speed, heading away from it |
| **Wall climb** | Running into a wall while airborne and holding forward climbs up to 1.5 m at 4 m/s for at most 0.4 s, once per airtime; then mantle if a ledge is reached | Into the 3 m ledge: climb, then mantle onto it |
| **Coyote time** (exists) | 0.1 s after leaving ground or a mantle | Already tested |

**Frame-perfect windows:** superglide uses a 1-tick gap as in Apex.
- Decide in playtests whether to keep it at 1 tick.
- Widening it to 2 ticks would accommodate players on low frame rates.
- Inputs are timestamped in `_unhandled_input` so the test doesn't depend on frame rate.

### 7.3 Order of work
1. Audit §7.1 and fix anything that fails. Tick order and air strafe come first; `addons/dot_player_controller` has a tested reference implementation (MIT) to compare against.
2. Lurch and tap strafe.
3. Mantle, then mantle jump, gorilla jump and superglide.
4. Wall sensor, then wall bounce and wall climb.
5. Tune with the user, against Apex clips measured with the watch skill.

### 7.4 Decision (2026-11-09): pure Source base
The user removed **dash and double jump** from the base movement so it feels like plain Source. Both return later as **player abilities or skills**.
- Keep the code behind tunables or flags (`dash_charges = 0`, `air_jumps = 0`) for an ability system to grant later.
- Shift is unbound for now.
- Vertical reach now comes from jump, mantle and wall climb only.

### 7.5 Decision (2026-11-09): Shift = sprint (Apex base)
Apex-style ground movement on Source rules:

| Setting | Value |
|---|---|
| Walk (default) | 7 m/s |
| Sprint (Shift) | 10 m/s, **forward only** (within ±45° of view); strafing or backpedalling caps you at walk |
| Sprint control | Toggle (default) or hold, as a setting. Superglide expects toggle, per the Apex wiki |
| Sprint ends on | crouch, ADS, reload, fire |
| Slide entry | Above about 8 m/s, so a slide from a sprint gets the full boost |

Sprint state carries through jumps. Air strafing is unchanged.
