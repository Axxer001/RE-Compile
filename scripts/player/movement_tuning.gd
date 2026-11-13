extends Resource
# Movement numbers in one place (Grimoire MVP, 2026-11-11).
#   [spec]   Technical Spec §2.1 (Downloads/RE_Compile_Technical_Spec.md)
#   [apex]   the Apex General Tech layer kept by decision D1
#            (docs/pivot-grimoire-plan.md §8): community measurements from
#            apex-study, 1 hu = 0.0254 m, rescaled to the spec's pace:
#            horizontal speeds x1.514 (Apex sprint 6.604 -> run 10), vertical
#            speeds x1.174 (Apex jump 7.239 -> 8.5); heights unchanged.
#   [design] our own choice where neither gives a number.
# The run speed comes from the Mov Spd stat (StatContainer) when the world
# provides one; run_speed is the fallback. Tests read these values.

# ---- ground [spec] -------------------------------------------------------------
@export var run_speed := 10.0          # [spec] Mov Spd base (the stat overrides it)
@export var crouch_ratio := 0.4        # [design] crouch walk = 0.4 x run
@export var ground_accel := 45.0       # [spec] m/s² toward run speed (with input)
@export var ground_friction := 12.0    # [spec] Source friction with no input or above run speed
@export var stop_speed := 2.54         # [Source] 100 hu/s
@export var min_floor_normal_y := 0.7  # walkable when normal.y >= 0.7 (about 45.6°)
@export var step_height := 0.5588      # [apex] 22 hu: step-up and ground snap
@export var max_bumps := 4             # clip planes per move (Source: 4 bumps)
# ---- air -------------------------------------------------------------------------
@export var air_accel := 12.0          # [design] Source air acceleration (x wishspeed)
@export var air_cap := 2.307           # [apex] 60 hu/s x1.514; caps v·wishdir only
@export var gravity := 22.0            # [spec]
@export var jump_speed := 8.5          # [spec] about 1.64 m high
@export var double_jump_speed := 7.0   # [spec] keeps the horizontal vector
@export var air_jumps_max := 1         # [spec] one double jump; landing resets it
@export var coyote_s := 0.2            # [apex]
@export var jump_buffer_s := 0.1       # [design]
@export var hop_buffer_enabled := false # [Sir, final: "No, keep double jump"] off: every air press spends the double jump
@export var hop_buffer_h := 0.3        # when on: a falling press this close above ground buffers a hop (keeps the double jump)
@export var hop_buffer_s := 0.1        # ...or this close in time to impact
# ---- dash [spec] -------------------------------------------------------------------
@export var dash_charges := 1          # [spec] one dash, 1.2 s cooldown
@export var dash_recharge_s := 1.2     # [spec]
@export var dash_speed := 20.0         # [spec] impulse at base Mov Spd (scales with Mov Spd / 10)
@export var dash_s := 0.25             # [spec] decays linearly to run speed over this
@export var dash_iframes_s := 0.15     # [spec] invulnerable to all damage (S8)
# ---- slide [spec] ------------------------------------------------------------------
@export var slide_entry_mult := 1.4    # [spec] entry speed = 1.4 x Mov Spd
@export var slide_s := 1.2             # [spec] linear decay to crouch speed over this; Ctrl again cancels
@export var slide_min_ratio := 0.7     # [design] "while running": above 0.7 x run speed
@export var slide_land_min_speed := 3.46 # [apex] landing entry: 90 hu/s x1.514 across...
@export var slide_land_min_fall := 5.96  # [apex] ...and falling faster than 200 hu/s x1.174
# ---- Apex layer switches (D1: kept, each can be turned off) -------------------------
@export var apex_lurch := true         # lurch, lurch stacks, tap strafe
@export var apex_mantle := true        # mantle grab/hang/pull, hop, boost, superglide, auto/insta mantle, clamber
@export var apex_climb := true         # climb space, wallrun, mini-bounce, wallbounce, wall push, end boost
@export var apex_fall_stun := true     # fall stun and its cancels, wallhop
@export var apex_jump_fatigue := true  # lower repeat jumps
@export var apex_bhop_penalty := true  # hops above run speed lose speed
@export var apex_slopes := true        # surf, trimp, geo jump (steep-surface clip)
@export var apex_damage_slow := true   # damage on the ground slows
# ---- Apex values (rescaled) -----------------------------------------------------------
@export var fatigue_height := 0.478    # [apex] 16.3/56 of the jump height
@export var fatigue_hold_s := 0.15     # [apex]
@export var fatigue_recover_s := 0.75  # [apex]
@export var bhop_window_s := 1.0       # [apex] skip_time
@export var bhop_penalty := 3.85       # [apex] 100 hu/s x1.514, above run speed
@export var damage_slow_speed := 7.27  # [apex] 189 hu/s x1.514
@export var damage_slow_cooldown_s := 3.0 # [apex]
@export var lurch_full_s := 0.2        # [apex] full strength for 0.2 s after a jump...
@export var lurch_window_s := 0.4      # [apex] ...then linear decay to 0 at 0.4 s
@export var lurch_strength := 1.0      # [design]
@export var lurch_max_loss := 0.1      # [design]
@export var lurch_max_speed := 44.2    # [apex] 1150 hu/s x1.514
@export var lurch_ref_speed := 10.0    # [design] one lurch fully redirects up to run speed
@export var mantle_min_h := 0.5588     # [design] = step_height
@export var mantle_max_h := 2.2        # [apex]
@export var mantle_grab_s := 0.45      # [apex]
@export var mantle_s := 0.3            # [apex] pull
@export var mantle_pull_only_h := 1.067 # [apex]
@export var mantle_input_deg := 50.0   # [apex]
@export var auto_mantle_h := 2.032     # [apex]
@export var insta_mantle_speed := 0.0254 # [apex]
@export var mantle_boost_speed := 11.5 # [design] 7.6 x1.514
@export var mantle_exit_speed := 4.5   # [design] 3 x1.514
@export var mantle_jump_back := 3.0    # [design] 2 x1.514
@export var gorilla_mult := 1.3        # [design]
@export var superglide_window_s := 0.15 # [apex]
@export var superglide_gap_ticks := 1  # [apex]
@export var superglide_speed := 20.77  # [apex] 540 hu/s x1.514
@export var superglide_up := 4.7       # [design] 4 x1.174
@export var superglide_cooldown_s := 2.0 # [apex] shared with slide entries
# R13 (Sir): on a ledge, Shift superglides toward the held direction (forward
# if none), no timing window; the old timed superglide (jump then crouch in the
# pull's last 150 ms) is off. A hang lasts until input: W climbs, A/D shimmy.
@export var apex_timed_superglide := false # [R13] the jump-then-crouch frame trick
@export var ledge_glide_speed := 15.0   # [proposed R13] 1.5 x run, in the chosen direction
@export var ledge_glide_up := 2.0       # [proposed R13] m/s of lift
@export var shimmy_speed := 2.0         # [proposed R13] m/s along the ledge
@export var wall_climb_speed := 6.71   # [apex] 225 hu/s x1.174
@export var wall_climb_accel := 40.0   # [design]
@export var wallrun_speed := 9.92      # [apex] 258 hu/s x1.514
@export var climb_side_speed := 4.42   # [apex] 115 hu/s x1.514
@export var wall_climb_max_h := 2.54   # [apex] attach offset 100 hu
@export var wall_climb_stall_speed := 0.254 # [apex]
@export var wall_climb_stall_s := 1.0  # [apex]
@export var wall_attach_dot := 0.7     # [apex]
@export var climb_space_h := 3.7338    # [apex] 147 hu
@export var mini_zone_h := 0.4826      # [apex] 19 hu
@export var green_zone_h := 1.1938     # [apex] 47 hu
@export var detach_drop := 3.2512      # [apex] 128 hu
@export var jump_drop := 6.5024        # [apex] 256 hu
@export var mini_bounce_out := 7.23    # [apex] 188 hu/s x1.514
@export var bounce_out := 9.92         # [apex] 258 hu/s x1.514
@export var mini_bounce_up := 2.94     # [design] 2.5 x1.174
@export var green_up_min := 2.35       # [design] 2 x1.174
@export var end_boost_h := 0.7112      # [apex] 28 hu
@export var reattach_dot := 0.9        # [apex]
@export var wall_release_s := 0.1      # [design]
@export var stun_min_drop := 7.62      # [apex] 300 hu
@export var stun_max_drop := 20.32     # [apex] 800 hu
@export var stun_max_s := 1.0          # [apex]
@export var wallhop_min_deg := 20.0    # [design]
@export var wallhop_max_deg := 50.0    # [design]
# ---- view ------------------------------------------------------------------------
@export var fov := 90.0
@export var ads_fov := 65.0            # used only by the settings' zoom-scaled sensitivity
