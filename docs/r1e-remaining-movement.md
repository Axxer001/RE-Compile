# R1e: the remaining Apex General Tech (2026-11-10)

Sir's scope: everything in the Apex Movement Wiki's General Tech section that is not
yet in RE:Compile, excluding ziplines, superglide variants, item interactions and
skydive. Rules come from the wiki pages saved under
`apex-study/evidence/movement-pages` (community measurements, not extracted Apex code),
converted at 1 hu = 0.0254 m. `[study]` values are measured there; `[design]` values are ours
where the wiki gives no number.

## Skipped, with reasons

| Move | Reason |
|---|---|
| Wall bug, infinite climb | Apex collision bugs, not designed moves |
| Analog climb, climb lock | Depend on analog-stick angles and an unmeasured climb force curve |
| Slidehop heal | Waits for healing items |

## Changes to existing rules found on the pages

| Rule | Was | Now |
|---|---|---|
| Step height | 0.35 m | 0.5588 m (22 hu) [study] |
| Ground acceleration | Source (x wishspeed) | constant 40 m/s² for crouch, walk and sprint alike [study rule; value fitted] |
| Bunny hop | keeps 100% | above sprint speed, a jump within 1 s of landing loses up to 2.54 m/s (100 hu/s) [study] |
| Slide jump | always keeps slide speed | only from a boosted slide, and only below 8.89 m/s (350 hu/s) or at least 0.24 s after entry [study]; otherwise a deadslide: speed falls back to sprint speed [design interpretation] |
| Lurch direction | back + side gave a pure sideways shift | the combined held direction, as the wiki states [study] |
| Lurch stack | one press could fully redirect | each lurch turns at most `lurch_ref_speed / speed` of the way, so faster travel needs stacked lurches [design law, study rule] |
| Wall bounce | reflected velocity | a jump off a climb, set by the climb zone [study] |
| Mantle | one 0.45 s move | grab (0.45 s) then pull (0.3 s); low ledges (<= 1.07 m) pull only [study] |

## New systems

| System | Rules |
|---|---|
| Fall stun | Impact speed along the landing contact normal; none below the free-fall speed from 7.62 m (300 hu), full (1 s) at 20.32 m (800 hu); strength squared [design: the wiki suspects quadratic]. Slows velocity and ground acceleration. Cancelled by edge contact (tilted contact normal), mantling, climbing (slows the fall) and touching a wall and the ground on the same tick (corner) [study] |
| Holster | No gun in hand: walk, sprint, crouch and slide boost x1.15 [study] |
| Damage slow | Damage taken on the ground drops speed to 4.80 m/s (189 hu/s); 3 s cooldown [study] |
| Melee movement | A melee swing lunges 1.5 m/s along the aim; into geometry it pushes you back 5 m/s (punch boost) [design values] |
| Sprint buffer | A toggled sprint waits up to 3 s for a forward input [study] |
| Edge slide | Leaving the ground mid-slide with Ctrl held keeps the slide: no friction in the air, landing resumes the slide without a new entry [study rule] |
| Mantle phases | Grab needs the move input within 50° of the wall (none = hang); grab cancels: crouch, back, side turned away; pull cancels: back, side. Jump in grab/hang = mantle hop. Crouch in the pull's last 0.15 s = mantle boost (7.6 m/s [design], no cooldown, not from a hang; starts the slide cooldown; the next landing slide does not count as an entry). Holding jump into an obstacle up to 2.03 m mantles it (auto mantle); below 0.0254 m/s it also mantles step-height obstacles (insta-mantle). A ledge within reach at the end of a pull chains another pull (clamber) [study rules] |
| Climb space | Baseline = feet at the last ground contact, dragged down when you fall below it; zones mini 0-0.48 m, green to 1.19 m, neutral to the 3.73 m cutoff; each climb may rise 2.54 m above its attach point; climb at 5.715 m/s up, 6.553 m/s sideways (wallrun), 2.921 m/s sideways while climbing up; climbing slower than 0.254 m/s up ends after 1 s; attach facing within 45.57° on surfaces steeper than walkable; reattach to the same wall only below the last attach point (any wall >= 25.84° different at once); a detach drops the climb space 3.25 m, a jump from green/neutral 6.5 m; topping out gives a 0.71 m end boost (end strafe: a sideways input there adds 0.05 m of mantle reach [design]) [study] |
| Climb jumps | Mini zone: 4.78 m/s away and a small hop (mini-bounce); green: 6.55 m/s away, higher the lower you are in the zone (wallbounce); neutral: 6.55 m/s away, no height (wall push) [study speeds, design heights] |
| Wall contact | Touching a wall in the air resets jump fatigue; meeting a wall at 20-50° clears an active fall stun (wallhop) [study rule, design angles] |
| Slopes | Surfaces steeper than walkable are never floor: air strafing into them surfs, hitting them airborne at speed trimps, and touching one refreshes coyote time so a jump right after is added on top of the upward speed (geo jump) [study rules] |

## Arena additions

A 20.9 m drop tower with a 41° access ramp (west side), a long 60° surf wedge along the
south wall, and a two-tier clamber block east of the ledges.
