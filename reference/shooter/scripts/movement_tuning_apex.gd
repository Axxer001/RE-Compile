extends Resource
# Movement numbers in one place: Source rules (docs/movement-reference.md
# §2, §7.1) with the Apex General Tech layer (§7.2, §7.5). Metres, seconds.
# Values marked [study] are community measurements from
# apex-study/movement-reconstruction.md (2026-11-10), converted at
# 1 hu = 0.0254 m. They are measured behaviour, NOT constants extracted from
# Apex. Values marked [design] are our own choices where no number was
# established. Tests read these values, so a change moves the expectations.

# ---- ground (Source) ---------------------------------------------------------
@export var run_speed := 4.4069        # [study] armed walk/strafe 173.5 hu/s
@export var sprint_speed := 6.604      # [study] armed sprint 260 hu/s; forward only (±45° of view)
@export var sprint_toggle := true      # press to toggle (Apex default; superglide expects it) or hold
@export var crouch_speed := 2.032      # [study] crouch walk 80 hu/s; quiet
@export var ads_speed_factor := 0.7     # unarmed / melee default; guns set their own
@export var ground_accel := 50.0       # [study rule, fitted value] m/s², the same for crouch, walk and sprint (wiki: only top speed differs); must beat friction at the holstered sprint (6 x 7.59 = 45.5); 0 to 200 hu/s in 0.17 s vs measured 0.35
@export var ground_friction := 6.0
@export var stop_speed := 2.54         # [Source] sv_stopspeed 100 hu/s (Apex value not measured)
@export var min_floor_normal_y := 0.7  # walkable when normal.y >= 0.7 (about 45.6°)
@export var step_height := 0.5588      # [study] StepHeight 22 hu: step-up and ground snap
@export var max_bumps := 4             # clip planes per move (Source: 4 bumps)
# ---- air (Source) -------------------------------------------------------------
@export var air_accel := 12.0         # [design] Source form; the study's "500" has unknown units
@export var air_cap := 1.524           # [study] air speed 60 hu/s; caps v·wishdir only, gain uses uncapped wishspeed
@export var gravity := 18.4207        # [study fit] jump height 56 hu + jump impulse 285 hu/s -> 725.2 hu/s² (airtime 0.79 s vs measured 0.74)
@export var jump_speed := 7.239        # [study] 285 hu/s -> 1.42 m high
@export var jump_height := 1.4224      # [study] 56 hu
@export var fatigue_height := 0.414    # [study] 16.3 hu: a jump within fatigue_hold_s of landing from a jump
@export var fatigue_hold_s := 0.15     # [study] then recovers linearly...
@export var fatigue_recover_s := 0.75  # [study] ...to full height at 0.75 s after landing
@export var coyote_s := 0.2            # [study]
@export var jump_buffer_s := 0.1
# ---- slide ------------------------------------------------------------------------
@export var slide_min_speed := 5.08    # [study] ground entry above 200 hu/s (walk is below, sprint above)
@export var slide_land_min_speed := 2.286 # [study] landing entry: above 90 hu/s horizontal...
@export var slide_land_min_fall := 5.08   # [study] ...and falling faster than 200 hu/s
@export var slide_boost := 3.81        # [study] 150 hu/s, applied the tick after entry
@export var slide_max_speed := 10.16   # [study] boost cap 400 hu/s (faster speed is kept, not cut)
@export var slide_boost_cooldown_s := 2.0 # [study] from the last slide entry, boosted or not
@export var slide_friction := 1.3      # [study fit] 460 -> 350 hu/s in 0.21 s (slide-jump page); 0 downhill; no fixed slide lifetime [study]
@export var slide_jump_max_speed := 8.89 # [study] a slide jump keeps the slide speed below 350 hu/s...
@export var slide_jump_after_s := 0.24  # [study] ...or from 0.24 s after entry; otherwise a deadslide
@export var holster_mult := 1.15       # [study] no gun in hand: walk, sprint, crouch, slide boost
@export var bhop_window_s := 1.0       # [study] skip_time: a jump this soon after landing...
@export var bhop_penalty := 2.54       # [study] ...above sprint speed loses up to 100 hu/s
@export var sprint_buffer_s := 3.0     # [study] a toggled sprint waits this long for forward
@export var damage_slow_speed := 4.8006 # [study] 189 hu/s, on damage taken on the ground...
@export var damage_slow_cooldown_s := 3.0 # [study] ...at most once per 3 s
@export var melee_lunge := 1.5         # [design] m/s along the aim on a melee swing
@export var punch_boost := 5.0         # [design] m/s back off geometry hit by a melee swing
# ---- Apex layer (§7.2) ------------------------------------------------------------
@export var lurch_full_s := 0.2        # [study] full strength for 0.2 s after a jump...
@export var lurch_window_s := 0.4      # [study] ...then linear decay to 0 at 0.4 s
@export var lurch_strength := 1.0      # [design] redirect fraction at full strength (impulse law not recovered)
@export var lurch_max_loss := 0.1      # [design] speed lost by a full 180° lurch (less for smaller turns)
@export var lurch_max_speed := 29.21   # [study] no lurch above ~1150 hu/s (bounded 1150-1300)
@export var lurch_ref_speed := 6.604   # [design] one lurch fully redirects up to this speed; faster needs a stack
@export var mantle_min_h := 0.5588     # [design] = step_height: no ledge height is neither stepped nor mantled
@export var mantle_max_h := 2.2
@export var mantle_grab_s := 0.45      # [study] mantle grab
@export var mantle_s := 0.3            # [study] mantle pull (mantle-boost page: 0.3 s)
@export var mantle_pull_only_h := 1.067 # [study] up to >= 42 hu: a pull without a grab
@export var mantle_input_deg := 50.0   # [study] the move input must point within 50° of the wall to grab
@export var auto_mantle_h := 2.032     # [study] holding jump mantles obstacles up to 80 hu
@export var insta_mantle_speed := 0.0254 # [study] below 1 hu/s, holding jump mantles step-height obstacles
@export var mantle_boost_speed := 7.6  # [design] crouch in the pull's last 0.15 s (study: no number)
@export var mantle_exit_speed := 3.0
@export var mantle_jump_back := 2.0    # a mantle jump pushes off the wall
@export var gorilla_mult := 1.3        # mantle jump with no move input: higher
@export var superglide_window_s := 0.15 # [study] jump in the last 0.15 s of a mantle pull (also the mantle-boost window)...
@export var superglide_gap_ticks := 1  # [study] ...then crouch exactly 1 input frame later (here: 1 physics tick)
@export var superglide_speed := 13.716 # [study] ~540 hu/s initial combined speed (needs sprint + slide off cooldown)
@export var superglide_up := 4.0       # [design] vertical part of that speed (components not recovered)
@export var wall_climb_speed := 5.715  # [study] peak climb 225 hu/s
@export var wall_climb_accel := 40.0   # [design] m/s² toward the climb speed (a fast fall slips first)
@export var wallrun_speed := 6.553     # [study] sideways climb 258 hu/s
@export var climb_side_speed := 2.921  # [study] sideways part of an upward climb, 115 hu/s
@export var wall_climb_max_h := 2.54   # [study] attach offset: 100 hu above the attach point
@export var wall_climb_stall_speed := 0.254 # [study] slower than 10 hu/s upward...
@export var wall_climb_stall_s := 1.0  # [study] ...is checked after 1 s; faster has no timer
@export var wall_attach_dot := 0.7     # [study] facing the wall within ~45.57°
@export var climb_space_h := 3.7338    # [study] baseline to cutoff, 147 hu
@export var mini_zone_h := 0.4826      # [study] 19 hu
@export var green_zone_h := 1.1938     # [study] 47 hu
@export var detach_drop := 3.2512      # [study] climb space drop on a detach / mini-zone jump, 128 hu
@export var jump_drop := 6.5024        # [study] on a green or neutral jump, 256 hu
@export var mini_bounce_out := 4.775   # [study] 188 hu/s away from the wall
@export var bounce_out := 6.553        # [study] 258 hu/s away (green and neutral)
@export var mini_bounce_up := 2.5      # [design] small hop
@export var green_up_min := 2.0        # [design] top of the green zone; the bottom gets jump_speed
@export var end_boost_h := 0.7112      # [study] 28 hu thrown up at the top of a climb
@export var reattach_dot := 0.9        # [study] a wall >= 25.84° different can be attached higher
@export var wall_release_s := 0.1      # [design] stays attached this long with no input (wall push)
# ---- fall stun ---------------------------------------------------------------------
@export var stun_min_drop := 7.62      # [study] no stun below the free-fall speed from 300 hu...
@export var stun_max_drop := 20.32     # [study] ...full (1 s) from 800 hu
@export var stun_max_s := 1.0          # [study]
@export var wallhop_min_deg := 20.0    # [design] meeting a wall at this angle...
@export var wallhop_max_deg := 50.0    # [design] ...to this clears a fall stun (study: best at 35°)
# ---- abilities (off in the Source base, §7.4; an ability system grants them) ----
@export var air_jumps_max := 0         # double jump
@export var double_jump_speed := 8.0
@export var dash_charges := 0          # dash (request_dash())
@export var dash_speed := 30.0
@export var dash_s := 0.2
@export var dash_recharge_s := 1.2     # per charge, one at a time
@export var dash_iframes_s := 0.1      # melee/bite immunity from the dash start
# ---- view -------------------------------------------------------------------------
@export var fov := 90.0
@export var ads_fov := 65.0
@export var ads_s := 0.25              # unarmed / melee aim-in time; guns set their own
