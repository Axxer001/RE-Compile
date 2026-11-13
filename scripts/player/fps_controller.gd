extends CharacterBody3D
# First-person player body. Authoritative state (position, yaw, pitch, crouch)
# changes only inside simulate(), driven by the session tick, so headless tests
# get the same result as play. Mouse motion is queued by _unhandled_input and
# applied on the next tick. Units: metres, seconds, degrees for pitch limits.
#
# Movement follows the Source pipeline (docs/movement-reference.md §2, §7.1)
# retuned to the Grimoire Technical Spec §2.1: run at Mov Spd (from the stat
# container), dash, slide, jump and double jump. The Apex General Tech layer
# (lurch, mantle family, climb space and wall jumps, fall stun, slopes) stays
# on top, each system behind a switch in MovementTuning (decision D1,
# docs/pivot-grimoire-plan.md §8).

const MovementTuning = preload("res://scripts/player/movement_tuning.gd")
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 0.9   # crouch and slide: half the standing hitbox [spec]
const RADIUS := 0.3
const EYE_BELOW_TOP := 0.12  # camera sits this far below the capsule top
const PITCH_LIMIT := 89.0
const MOUSE_SENSITIVITY := 0.12 # degrees per pixel
const INTERACT_RANGE := 2.0
const HANG_BELOW_TOP := 1.4  # feet this far below the ledge top while hanging

# Movement states. One enum in one controller rather than a file per state:
# the states share the velocity and probes, and stay small.
enum Move { GROUND, AIR, DASH, SLIDE, MANTLE, WALLCLIMB }

var tuning := MovementTuning.new()
var state := Move.GROUND
var yaw := 0.0      # radians; 0 looks along -Z
var pitch := 0.0    # radians; + looks up
var crouching := false
var sprinting := false  # loud movement (dash, slide): footstep noise
var aim_t := 0.0        # no aiming in the Grimoire build: always 0 (settings sensitivity reads it)
var stats: RefCounted   # StatContainer: Mov Spd drives the run speed; set by the world (null = run_speed)
var _look_queue := Vector2.ZERO
var look_enabled_fn: Callable # () -> bool; set by the world (InputRouter)
var settings: RefCounted     # Settings (sensitivity, ADS, invert Y); set by the world; null = MOUSE_SENSITIVITY
var carry_factor := 1.0 # speed multiplier from the action clock; set by the world each tick
var air_jumps := 0      # double jump (ability): refilled on landing
var since_floor := 0.0  # coyote time
var since_surface := INF # coyote time from a steep surface (geo jump, edge contact)
var jump_buffer := -1.0 # seconds left on a buffered jump press
var dash_charges := 0
var dash_recharge := 0.0
var dash_request := false # an ability asks for a dash (request_dash())
var state_t := 0.0      # time in the current dash/slide/climb
var dash_dir := Vector3.ZERO
var jump_was := false
var dash_was := false
var crouch_was := false
var last_move := Vector2.ZERO
var tick_n := 0
var slide_entry_at := -INF # session time of the last slide entry (the superglide cooldown)
var slide_from := 0.0   # slide entry speed (linear decay to crouch speed)
var air_slide := false  # left the ground mid-slide with Ctrl held (edge slide)
var surf_slide := false # after a mantle boost any landing with Ctrl held slides (slide surf) [apex]
var air_v := Vector3.ZERO # velocity before the last airborne move (landing checks)
var air_vy := 0.0
var jumped := false     # airborne from a jump (not a fall): landing starts jump fatigue
var fatigued := false
var land_t := 0.0       # time on the ground since the last landing
var step_offset := 0.0  # camera lag after a step-up, eased out (view only)
var lurch_t := INF      # time since the last jump (lurch window)
# Mantle: {phase, t, start, target, top, normal, from_hang, from_climb, sprint, glide_tick, glide_ok}
var mantle := {}
var end_strafe_t := -INF # session time of an end strafe (extra mantle reach)
# Climb space and wall state.
var baseline_y := 0.0   # feet at the last ground contact (dragged down below it)
var wall_t := -INF      # last airborne wall contact (session time)
var wall_n := Vector3.ZERO
var attached := false   # a climb attach this airtime
var attach_y := 0.0
var attach_n := Vector3.ZERO
var climb_y0 := 0.0
var release_t := 0.0    # time on the wall with no input
# Fall stun and slows.
var stun_q := 0.0       # strength 0..1 of the current fall stun
var stun_left := 0.0    # seconds of fall stun left
var edge_q := 1.0       # stun an edge or slope contact would give (it counts as ground contact)
var edge_t := -INF
var slow_at := -INF     # session time of the last damage slow
var damage_pending := false
# Counters (tests).
var jumps := 0
var dashes := 0
var steps_up := 0
var lurches := 0
var mantles := 0
var mantle_jumps := 0
var mantle_hops := 0
var mantle_boosts := 0
var mantle_cancels := 0
var hangs := 0
var insta_mantles := 0
var auto_mantles := 0
var clambers := 0
var superglides := 0
var ledge_glides := 0          # R13 Shift superglides off a ledge (tests)
var shimmied := 0.0            # metres shimmied along ledges (tests)
var bounces := 0        # green-zone wallbounces
var mini_bounces := 0
var wall_pushes := 0
var climbs := 0
var wallruns := 0
var end_boosts := 0
var stuns := 0
var stun_cancels := 0
var wallhops := 0
var geo_jumps := 0
var slide_jumps := 0
var deadslides := 0
var bhop_penalties := 0
var damage_slows := 0
var punch_boosts := 0
var lunges := 0

@onready var shape: CollisionShape3D = $Shape
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var flashlight: SpotLight3D = $Head/Camera/Flashlight
@onready var endurance: Node = $Endurance
@onready var health: Node = $Health

func _ready() -> void:
	_apply_height(STAND_HEIGHT)
	reset_movement()
	health.damaged.connect(func(_pk, applied: float) -> void:
		if applied > 0.0: damage_pending = true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if not look_enabled_fn.is_valid() or look_enabled_fn.call():
			look_from_mouse(event.relative)

# A mouse motion in pixels -> queued look, through the settings (hip/ADS
# sensitivity, invert Y), or MOUSE_SENSITIVITY with none.
func look_from_mouse(relative: Vector2) -> void:
	if settings != null: queue_look(settings.look_degrees(relative, aim_t, tuning.fov, tuning.ads_fov))
	else: queue_look(relative * MOUSE_SENSITIVITY)

# Degrees of yaw (x, right +) and pitch (y, down +) applied next tick.
func queue_look(degrees: Vector2) -> void:
	_look_queue += degrees

func apply_look() -> void:
	yaw -= deg_to_rad(_look_queue.x)
	pitch = clampf(pitch - deg_to_rad(_look_queue.y), deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT))
	_look_queue = Vector2.ZERO
	rotation = Vector3(0.0, yaw, 0.0)
	head.rotation = Vector3(pitch, 0.0, 0.0)

func height() -> float:
	return (shape.shape as CapsuleShape3D).height

func _apply_height(h: float) -> void:
	var cap := shape.shape as CapsuleShape3D
	cap.height = h
	cap.radius = RADIUS
	shape.position.y = h * 0.5
	head.position.y = h - EYE_BELOW_TOP

# True if a standing capsule would fit with its feet at `feet` (default: here).
func can_stand(feet := Vector3.INF) -> bool:
	var at := global_position if feet == Vector3.INF else feet
	var probe := CapsuleShape3D.new()
	probe.radius = RADIUS - 0.02
	probe.height = STAND_HEIGHT - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis(), at + Vector3(0, STAND_HEIGHT * 0.5 + 0.02, 0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func reset_movement() -> void:
	state = Move.GROUND
	air_jumps = tuning.air_jumps_max
	since_floor = 0.0
	since_surface = INF
	jump_buffer = -1.0
	dash_charges = tuning.dash_charges
	dash_recharge = 0.0
	dash_request = false
	state_t = 0.0
	jump_was = false
	dash_was = false
	crouch_was = false
	last_move = Vector2.ZERO
	aim_t = 0.0
	sprinting = false
	slide_entry_at = -INF
	slide_from = 0.0
	air_slide = false
	surf_slide = false
	air_v = Vector3.ZERO
	air_vy = 0.0
	jumped = false
	fatigued = false
	land_t = INF # no recent landing (bunny-hop window)
	step_offset = 0.0
	lurch_t = INF
	mantle = {}
	end_strafe_t = -INF
	baseline_y = global_position.y if is_inside_tree() else 0.0
	wall_t = -INF
	attached = false
	release_t = 0.0
	stun_q = 0.0
	stun_left = 0.0
	edge_q = 1.0
	edge_t = -INF
	slow_at = -INF
	damage_pending = false
	for c in ["jumps", "dashes", "steps_up", "lurches", "mantles", "mantle_jumps", "mantle_hops", "mantle_boosts", "mantle_cancels", "hangs", "insta_mantles", "auto_mantles", "clambers", "superglides", "bounces", "mini_bounces", "wall_pushes", "climbs", "wallruns", "end_boosts", "stuns", "stun_cancels", "wallhops", "geo_jumps", "slide_jumps", "deadslides", "bhop_penalties", "damage_slows", "punch_boosts", "lunges"]:
		set(c, 0)
	floor_max_angle = acos(tuning.min_floor_normal_y)
	floor_snap_length = tuning.step_height # ground snap: trace down step_height after a ground move
	max_slides = tuning.max_bumps
	floor_stop_on_slope = true
	camera.fov = tuning.fov

# An ability (or a test) asks for a dash on the next tick; needs a charge.
func request_dash() -> void:
	dash_request = true

func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()

func _set_horizontal_speed(v: float) -> void:
	var sp := horizontal_speed()
	if sp < 1e-5: return
	velocity.x *= v / sp
	velocity.z *= v / sp

func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	return Vector3(f.x, 0, f.z).normalized()

# Wish direction from the move input, flattened (x strafe, y forward).
func wish_dir(move: Vector2) -> Vector3:
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var w := right * move.x + forward * move.y
	w.y = 0.0
	return w.normalized() if w.length_squared() > 1e-6 else Vector3.ZERO

# The run speed: the Mov Spd stat when the world gives one [spec], else run_speed.
func run_top() -> float:
	return float(stats.value("mov_spd", _last_now)) if stats != null else tuning.run_speed

# Source AirAccelerate: add speed along `wishdir` until the speed along it
# reaches min(wishspeed, cap); the amount per tick uses the uncapped wishspeed
# (that is what makes air strafing gain speed).
func accelerate(wishdir: Vector3, wishspeed: float, accel: float, delta: float, cap := INF) -> void:
	var current := Vector3(velocity.x, 0, velocity.z).dot(wishdir)
	var add := minf(wishspeed, cap) - current
	if add <= 0.0: return
	var amount := minf(accel * wishspeed * delta, add)
	velocity.x += wishdir.x * amount
	velocity.z += wishdir.z * amount

# Ground acceleration [spec]: toward the wish velocity at ground_accel (the
# same rate whatever the top speed). Fall stun scales it down.
func ground_accelerate(wishdir: Vector3, wishspeed: float, delta: float) -> void:
	var current := Vector3(velocity.x, 0, velocity.z).dot(wishdir)
	var add := wishspeed - current
	if add <= 0.0: return
	var rate := tuning.ground_accel * (1.0 - stun_q if stun_left > 0.0 else 1.0)
	var amount := minf(rate * delta, add)
	velocity.x += wishdir.x * amount
	velocity.z += wishdir.z * amount

# Source Friction (ground only): drop = max(speed, stop_speed) * friction * dt.
func friction(amount: float, delta: float) -> void:
	var speed := horizontal_speed()
	if speed < 0.001:
		velocity.x = 0.0; velocity.z = 0.0
		return
	var drop := maxf(speed, tuning.stop_speed) * amount * delta
	var k := maxf(speed - drop, 0.0) / speed
	velocity.x *= k
	velocity.z *= k

func ground_speed(_move := Vector2(0, 1)) -> float:
	return run_top() * (tuning.crouch_ratio if crouching else 1.0) * carry_factor

func _set_crouch(on: bool) -> bool:
	if on == crouching: return true
	if not on and not can_stand(): return false
	crouching = on
	_apply_height(CROUCH_HEIGHT if on else STAND_HEIGHT)
	return true

func _gravity_half(delta: float) -> void:
	velocity.y -= tuning.gravity * delta * 0.5

# ---- fall stun --------------------------------------------------------------------

# Strength 0..1 for an impact speed into the surface [study]: none below the
# free-fall speed from stun_min_drop, full at stun_max_drop; squared [design].
func stun_strength(impact: float) -> float:
	var v0 := sqrt(2.0 * tuning.gravity * tuning.stun_min_drop)
	var v1 := sqrt(2.0 * tuning.gravity * tuning.stun_max_drop)
	var s := clampf((impact - v0) / (v1 - v0), 0.0, 1.0)
	return s * s

# On landing from the air: the impact is the pre-landing velocity along the
# contact normal (an edge gives a tilted normal: edge stun-cancel). Touching a
# wall on the same tick cancels it (corner stun-cancel).
func _land_stun(n: Vector3, now: float) -> void:
	if not tuning.apex_fall_stun: return
	var impact := maxf(-air_v.dot(n), 0.0)
	var q := stun_strength(impact)
	if q <= 0.0: return
	# An edge or slope touched just before counts as the ground contact
	# (edge stun-cancel): the gentler of the two impacts applies.
	if now - edge_t <= 0.3 and edge_q < q:
		if edge_q <= 0.0:
			stun_cancels += 1
			return
		q = edge_q
	if is_on_wall():
		stun_cancels += 1
		return
	stun_q = q
	stun_left = q * tuning.stun_max_s
	velocity.x *= 1.0 - q
	velocity.z *= 1.0 - q
	stuns += 1

# ---- tick -------------------------------------------------------------------------

# One simulation tick. intent: move, jump, dash, crouch (held states).
func simulate(intent: Dictionary, delta: float, now: float) -> void:
	apply_look()
	tick_n += 1
	_last_now = now
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	if move.length() > 1.0: move = move.normalized()
	var wish := wish_dir(move)
	var jump_down: bool = intent.get("jump", false)
	var dash_down: bool = intent.get("dash", false)
	var crouch_down: bool = intent.get("crouch", false)
	var jump_edge := jump_down and not jump_was
	var dash_edge := dash_down and not dash_was
	var crouch_edge := crouch_down and not crouch_was
	jump_was = jump_down; dash_was = dash_down; crouch_was = crouch_down
	var on_floor := is_on_floor()
	var landed := on_floor and (state == Move.AIR or state == Move.WALLCLIMB)
	since_floor = 0.0 if on_floor else since_floor + delta
	since_surface += delta
	stun_left = maxf(stun_left - delta, 0.0)
	if on_floor: baseline_y = global_position.y
	else: baseline_y = minf(baseline_y, global_position.y) # falling below it drags the climb space down
	if landed:
		_land_stun(get_floor_normal(), now)
		state = Move.GROUND
		air_jumps = tuning.air_jumps_max
		attached = false
		fatigued = jumped # jump fatigue follows a jump, not a plain fall
		jumped = false
		land_t = 0.0
	elif on_floor:
		land_t += delta
	if not on_floor and state == Move.GROUND and since_floor > tuning.coyote_s:
		state = Move.AIR
	jump_buffer = tuning.jump_buffer_s if jump_edge else jump_buffer - delta
	if not on_floor: lurch_t += delta
	# Damage slow [study]: damage taken on the ground, once per cooldown.
	if damage_pending:
		damage_pending = false
		if tuning.apex_damage_slow and on_floor and now - slow_at >= tuning.damage_slow_cooldown_s:
			slow_at = now
			if horizontal_speed() > tuning.damage_slow_speed: _set_horizontal_speed(tuning.damage_slow_speed)
			damage_slows += 1
	# Dash [spec]: Shift, one charge, 1.2 s cooldown.
	if dash_charges < tuning.dash_charges:
		dash_recharge += delta
		if dash_recharge + 1e-6 >= tuning.dash_recharge_s:
			dash_recharge = 0.0
			dash_charges += 1
	if (dash_request or dash_edge) and state != Move.DASH and state != Move.MANTLE and dash_charges > 0:
		dash_charges -= 1
		dashes += 1
		dash_dir = wish if wish != Vector3.ZERO else _flat_forward()
		state = Move.DASH
		state_t = 0.0
		health.grant_immunity(now + tuning.dash_iframes_s, ["*"], now) # all damage (S8)
		if crouching: _set_crouch(false)
	dash_request = false
	var moved := false # the state made this tick's move itself
	match state:
		Move.MANTLE:
			moved = _mantle_tick(move, wish, jump_edge, crouch_edge, dash_edge, now, delta)
		Move.DASH:
			# Impulse at dash_speed x (Mov Spd / 10), decaying linearly to run speed [spec].
			if state_t + 1e-6 >= tuning.dash_s:
				var keep_y := velocity.y if not on_floor else 0.0
				velocity = dash_dir * run_top() + Vector3(0, minf(keep_y, 0.0), 0)
				state = Move.GROUND if on_floor else Move.AIR
			else:
				var peak := tuning.dash_speed * run_top() / 10.0
				velocity = dash_dir * lerpf(peak, run_top(), state_t / tuning.dash_s)
				state_t += delta
		Move.SLIDE:
			_slide_tick(move, wish, crouch_down, on_floor, now, delta)
		Move.WALLCLIMB:
			_climb_tick(move, wish, jump_edge, crouch_edge, now, delta)
		Move.GROUND, Move.AIR:
			_ground_air_tick(move, wish, jump_edge, jump_down, crouch_edge, crouch_down, on_floor, landed, now, delta)
	if state != Move.MANTLE and state != Move.DASH and state != Move.SLIDE and state != Move.WALLCLIMB and (state == Move.AIR or not on_floor):
		_gravity_half(delta)
	last_move = move
	sprinting = state == Move.DASH or state == Move.SLIDE
	camera.fov = tuning.fov
	if not moved:
		var pre := Vector3(velocity.x, 0, velocity.z)
		# A step-up makes this tick's move itself (the floor contact from the
		# last move stands until the next one); otherwise move_and_slide.
		if not (on_floor and (state == Move.GROUND or state == Move.SLIDE) and _step_up(delta)):
			if not is_on_floor() or state == Move.AIR:
				air_v = velocity
				air_vy = velocity.y
			_move_scaled(delta)
			if state == Move.AIR or state == Move.WALLCLIMB: _wall_sense(pre, now)
			if state == Move.GROUND and on_floor: _ground_wall_sense(pre)
		# Second half of gravity (airborne after the move).
		if (state == Move.AIR) and not is_on_floor(): _gravity_half(delta)
	step_offset = move_toward(step_offset, 0.0, 2.5 * delta) # eases the camera up after a step
	head.position.y = height() - EYE_BELOW_TOP - step_offset
	endurance.tick(delta, now)

func _ground_air_tick(move: Vector2, wish: Vector3, jump_edge: bool, jump_down: bool, crouch_edge: bool, crouch_down: bool, on_floor: bool, landed: bool, now: float, delta: float) -> void:
	# Edge slide: landing again from a slide that left the ground with Ctrl held
	# resumes it (no new entry, no boost).
	if landed and air_slide and crouch_down and horizontal_speed() > ground_speed():
		air_slide = false
		_set_crouch(true)
		state = Move.SLIDE
		return
	if landed: air_slide = false
	# Slide entry: Ctrl while running [spec], or landing with Ctrl held across
	# the ground and falling fast [apex].
	var ground_entry := crouch_edge and on_floor and horizontal_speed() > tuning.slide_min_ratio * run_top()
	var land_entry := landed and crouch_down and horizontal_speed() > tuning.slide_land_min_speed and (air_vy < -tuning.slide_land_min_fall or surf_slide)
	if landed: surf_slide = false
	if ground_entry or land_entry:
		_enter_slide(now)
		return
	if crouch_down and not crouching: _set_crouch(true)
	elif not crouch_down and crouching: _set_crouch(false)
	if on_floor or since_floor <= tuning.coyote_s:
		# Auto mantle / insta-mantle [study]: holding jump into an obstacle.
		if tuning.apex_mantle and on_floor and jump_down and _try_ground_mantle(wish): return
		# Source order: jump check, then friction (ground only), then
		# accelerate. A jump on the landing tick skips friction.
		if jump_buffer > 0.0 and not crouching:
			_ground_jump()
			state = Move.AIR
			accelerate(wish, ground_speed(move), tuning.air_accel, delta, tuning.air_cap)
		else:
			# [spec] friction with no input or above the top speed; with input,
			# accelerate toward it (turning included).
			var top := ground_speed(move)
			if on_floor and (wish == Vector3.ZERO or horizontal_speed() > top + 0.01): friction(tuning.ground_friction, delta)
			if wish != Vector3.ZERO and horizontal_speed() <= top + 0.01:
				var vh := Vector3(velocity.x, 0, velocity.z).move_toward(wish * top, tuning.ground_accel * (1.0 - stun_q if stun_left > 0.0 else 1.0) * delta)
				velocity.x = vh.x
				velocity.z = vh.z
	else:
		_air_tick(move, wish, jump_edge, now, delta)

func _enter_slide(now: float) -> void:
	_set_crouch(true)
	state = Move.SLIDE
	state_t = 0.0
	air_slide = false
	slide_entry_at = now
	_slide_crouch_was = true # the press that started the slide does not cancel it
	# Entry speed 1.4 x Mov Spd [spec] (faster momentum is kept).
	slide_from = maxf(horizontal_speed(), tuning.slide_entry_mult * run_top())
	var dir := Vector3(velocity.x, 0, velocity.z).normalized()
	if dir == Vector3.ZERO: dir = _flat_forward()
	velocity.x = dir.x * slide_from
	velocity.z = dir.z * slide_from

# Slide [spec]: linear decay from the entry speed to crouch speed over slide_s;
# Ctrl pressed again cancels; a jump is a slide jump (keeps the speed). Downhill
# keeps the speed; leaving the ground with Ctrl held is an edge slide [apex].
func _slide_tick(move: Vector2, wish: Vector3, crouch_down: bool, on_floor: bool, now: float, delta: float) -> void:
	state_t += delta
	var crouch_edge := crouch_down and not _slide_crouch_was
	_slide_crouch_was = crouch_down
	if not on_floor:
		if crouch_down and since_floor > 0.05:
			air_slide = true
			state = Move.AIR
		velocity.y -= tuning.gravity * delta
		return
	if jump_buffer > 0.0:
		_ground_jump()
		state = Move.AIR
		_set_crouch(false)
		return
	if crouch_edge and state_t > delta * 1.5 or state_t + 1e-6 >= tuning.slide_s:
		state = Move.GROUND
		if not crouch_down: _set_crouch(false)
		return
	var downhill := get_floor_normal().dot(Vector3.UP) < 0.996 and Vector3(velocity.x, 0, velocity.z).dot(Vector3(get_floor_normal().x, 0, get_floor_normal().z)) > 0.0
	if not downhill:
		_set_horizontal_speed(lerpf(slide_from, run_top() * tuning.crouch_ratio, state_t / tuning.slide_s))

var _slide_crouch_was := true

# A jump from the ground (or a slide): fatigue, and the bunny-hop penalty
# above run speed within bhop_window_s of landing [apex].
func _ground_jump() -> void:
	if tuning.apex_bhop_penalty and land_t < tuning.bhop_window_s and horizontal_speed() > run_top():
		_set_horizontal_speed(maxf(run_top(), horizontal_speed() - tuning.bhop_penalty))
		bhop_penalties += 1
	_jump(jump_speed_now())

# ---- air ------------------------------------------------------------------------

func _air_tick(move: Vector2, wish: Vector3, jump_edge: bool, now: float, delta: float) -> void:
	# Geo jump [study]: a jump within coyote time of touching a steep surface
	# (a trimp's ramp, an edge) adds the jump on top of the upward speed.
	if tuning.apex_slopes and (jump_edge or jump_buffer > 0.0) and since_surface <= tuning.coyote_s:
		var up := maxf(velocity.y, 0.0)
		_jump(jump_speed_now())
		velocity.y += up
		since_surface = INF
		geo_jumps += 1
		return
	_lurch(move, wish)
	accelerate(wish, ground_speed(move), tuning.air_accel, delta, tuning.air_cap)
	if jump_edge:
		# Optional buffered hop (hop_buffer_enabled, off by default [Sir]): falling
		# just above walkable ground, the press waits for touchdown (a ground jump
		# with no friction tick) and the double jump stays for later. Otherwise
		# the press is the double jump.
		var impact := time_to_ground() if tuning.hop_buffer_enabled else -1.0
		if velocity.y < 0.0 and impact >= 0.0:
			jump_buffer = maxf(jump_buffer, impact + 0.05)
		elif air_jumps > 0:
			air_jumps -= 1
			_jump(tuning.double_jump_speed)
	# Mantle a ledge in reach (the move input within 50° of the wall, or no
	# input while moving at it: a hang), else climb a wall.
	var ledge := find_ledge() if tuning.apex_mantle else {}
	if not ledge.is_empty() and _mantle_input_ok(wish, ledge.normal):
		_start_mantle(ledge, false, now)
		return
	if tuning.apex_climb and wish != Vector3.ZERO:
		var wn := _wall_ahead(0.1)
		if wn != Vector3.ZERO and _flat_forward().dot(-wn) >= tuning.wall_attach_dot and wish.dot(-wn) > 0.05 and can_attach(wn):
			_attach(wn, now)

# Seconds until the feet reach walkable ground when it is within
# hop_buffer_h below, or closer than hop_buffer_s by the fall; -1 otherwise.
func time_to_ground() -> float:
	var vy := -velocity.y
	var reach := maxf(tuning.hop_buffer_h, maxf(vy, 0.0) * tuning.hop_buffer_s + 0.5 * tuning.gravity * tuning.hop_buffer_s * tuning.hop_buffer_s)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, Vector3(0, -reach, 0), hit): return -1.0
	if hit.get_normal().y < tuning.min_floor_normal_y: return -1.0
	var d := maxf(0.0, global_position.y - hit.get_position().y)
	# d = vy t + g t^2 / 2
	var g := tuning.gravity
	return (-vy + sqrt(maxf(vy * vy + 2.0 * g * d, 0.0))) / g

# The move input allows a mantle grab: within mantle_input_deg of the wall, or
# none at all while moving toward the edge (which ends in a hang).
func _mantle_input_ok(wish: Vector3, n: Vector3) -> bool:
	if wish == Vector3.ZERO: return Vector3(velocity.x, 0, velocity.z).dot(-n) > 0.3
	return wish.dot(-n) >= cos(deg_to_rad(tuning.mantle_input_deg))

# Lurch [study]: a newly PRESSED direction key (not a release, not a key
# already held) within lurch_window_s of a jump turns the horizontal velocity
# toward the combined held direction. Full strength for lurch_full_s, then
# linear decay to 0. Each lurch turns at most lurch_ref_speed / speed of the
# way, so faster travel needs a stack of lurches [design law]. Rapid forward
# taps while turning are tap strafing.
static func lurch_envelope(t: float, full: float, window: float) -> float:
	if t < 0.0: return 0.0
	return clampf((window - t) / (window - full), 0.0, 1.0)

static func newly_pressed(move: Vector2, last: Vector2) -> bool:
	return (move.x != 0.0 and signf(move.x) != signf(last.x)) or (move.y != 0.0 and signf(move.y) != signf(last.y))

func _lurch(move: Vector2, wish: Vector3) -> void:
	if not tuning.apex_lurch or lurch_t >= tuning.lurch_window_s or not newly_pressed(move, last_move): return
	var vh := Vector3(velocity.x, 0, velocity.z)
	var speed := vh.length()
	if speed < 0.5 or speed > tuning.lurch_max_speed or wish == Vector3.ZERO: return
	var k: float = tuning.lurch_strength * lurch_envelope(lurch_t, tuning.lurch_full_s, tuning.lurch_window_s)
	k *= minf(1.0, tuning.lurch_ref_speed / speed)
	var d0 := vh / speed
	var ang := d0.signed_angle_to(wish, Vector3.UP)
	var nd := d0.rotated(Vector3.UP, ang * k)
	speed *= 1.0 - tuning.lurch_max_loss * k * absf(ang) / PI
	velocity.x = nd.x * speed
	velocity.z = nd.z * speed
	lurches += 1

# Ground jump speed with jump fatigue [study]: a jump within fatigue_hold_s of
# landing from a jump reaches only fatigue_height, recovering linearly to
# jump_height by fatigue_recover_s.
func jump_speed_now() -> float:
	if not fatigued or not tuning.apex_jump_fatigue: return tuning.jump_speed
	if land_t >= tuning.fatigue_recover_s:
		fatigued = false
		return tuning.jump_speed
	var u := clampf((land_t - tuning.fatigue_hold_s) / (tuning.fatigue_recover_s - tuning.fatigue_hold_s), 0.0, 1.0)
	var full := tuning.jump_speed * tuning.jump_speed / (2.0 * tuning.gravity)
	return sqrt(2.0 * tuning.gravity * lerpf(tuning.fatigue_height, full, u))

func _jump(speed: float) -> void:
	velocity.y = speed # replaces any downward velocity
	jumped = true
	jump_buffer = -1.0
	since_floor = tuning.coyote_s + 1.0
	lurch_t = 0.0
	jumps += 1

# ---- wall sensor, climb space, climb ---------------------------------------------

# After an airborne move: a wall contact resets jump fatigue (wall bump), may
# clear a fall stun (wallhop), and a steep surface refreshes coyote time.
func _wall_sense(pre: Vector3, now: float) -> void:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if tuning.apex_slopes and n.y > 0.05 and n.y < tuning.min_floor_normal_y:
			since_surface = 0.0 # steep slope or an edge
			edge_q = stun_strength(maxf(-air_v.dot(n), 0.0))
			edge_t = now
			# Godot's grounded mover treats steep surfaces as vertical walls (it
			# slides on the flat part of the normal), which removes surf and
			# trimp. Clip the pre-move velocity against the real plane instead
			# (Source ClipVelocity): speed into the slope turns along it.
			var into := air_v.dot(n)
			if into < 0.0: velocity = air_v - n * into
	if is_on_floor() or not is_on_wall(): return
	var wn := get_wall_normal()
	if absf(wn.y) > 0.3: return
	wn = Vector3(wn.x, 0, wn.z).normalized()
	wall_n = wn
	wall_t = now
	jumped = false # wall bump: the next landing carries no jump fatigue
	_wallhop_check(pre, wn)

func _ground_wall_sense(pre: Vector3) -> void:
	if not is_on_wall(): return
	var wn := get_wall_normal()
	if absf(wn.y) > 0.3: return
	_wallhop_check(pre, Vector3(wn.x, 0, wn.z).normalized())

func _wallhop_check(pre: Vector3, wn: Vector3) -> void:
	if not tuning.apex_fall_stun: return
	if stun_left <= 0.0 or pre.length() < 0.5: return
	var into := rad_to_deg(asin(clampf(-pre.normalized().dot(wn), -1.0, 1.0)))
	if into >= tuning.wallhop_min_deg and into <= tuning.wallhop_max_deg:
		stun_left = 0.0
		stun_q = 0.0
		wallhops += 1

# Climb zone of a feet height above the baseline [study].
func climb_zone(rel: float) -> String:
	if rel < 0.0: return "below"
	if rel <= tuning.mini_zone_h: return "mini"
	if rel <= tuning.green_zone_h: return "green"
	if rel < tuning.climb_space_h: return "neutral"
	return "above"

# Climb attach [study]: airborne, inside the climb space, and either the first
# attach this airtime, below the last attach point, or a wall at least 25.84°
# different from the last one.
func can_attach(n: Vector3) -> bool:
	var rel := global_position.y - baseline_y
	if rel < 0.0 or rel >= tuning.climb_space_h: return false
	if not attached: return true
	return global_position.y < attach_y or n.dot(attach_n) <= tuning.reattach_dot

func _attach(wn: Vector3, now: float) -> void:
	wall_n = wn
	wall_t = now
	state = Move.WALLCLIMB
	state_t = 0.0
	release_t = 0.0
	climb_y0 = global_position.y
	attached = true
	attach_y = global_position.y
	attach_n = wn
	jumped = false
	climbs += 1

func _detach(drop: float) -> void:
	state = Move.AIR
	baseline_y -= drop

# On the wall: up at the climb speed (a fast fall slips first), sideways along
# it (wallrun), a mantle when a ledge comes into reach, an end boost at the top
# of the climb space or the attach offset, and a jump off by zone.
func _climb_tick(move: Vector2, wish: Vector3, jump_edge: bool, crouch_edge: bool, now: float, delta: float) -> void:
	state_t += delta
	if jump_edge:
		_climb_jump()
		return
	var ledge := find_ledge() if tuning.apex_mantle else {}
	if not ledge.is_empty() and (wish == Vector3.ZERO or _mantle_input_ok(wish, ledge.normal)):
		_start_mantle(ledge, true, now)
		return
	var wn := _wall_ahead(0.15) # a little past the attach probe: the climb push can leave a one-tick gap
	if crouch_edge or wn == Vector3.ZERO or _flat_forward().dot(-wn) < tuning.wall_attach_dot:
		_detach(tuning.detach_drop)
		return
	wall_n = wn
	var tangent := Vector3.UP.cross(wall_n).normalized()
	var into := wish.dot(-wall_n)
	var side := wish.dot(tangent)
	if wish == Vector3.ZERO:
		release_t += delta
		if release_t > tuning.wall_release_s:
			_detach(tuning.detach_drop)
			return
	else:
		release_t = 0.0
		if into < -0.05 and absf(side) < 0.2: # backwards: let go
			_detach(tuning.detach_drop)
			return
	var upward := into > 0.2
	var target_vy := tuning.wall_climb_speed if upward else 0.0
	var vy := move_toward(velocity.y, maxf(target_vy, velocity.y - tuning.gravity * delta) if upward and velocity.y > target_vy else target_vy, tuning.wall_climb_accel * delta)
	var rise_cap := minf(attach_y + tuning.wall_climb_max_h, baseline_y + tuning.climb_space_h)
	if global_position.y >= rise_cap - 0.001 and vy > 0.0:
		# End boost [study]: thrown end_boost_h further up; a sideways input
		# there is an end strafe (a little more mantle reach) [design].
		velocity = Vector3(0, sqrt(2.0 * tuning.gravity * tuning.end_boost_h), 0) - wall_n * 0.5
		if absf(side) > 0.2: end_strafe_t = now
		end_boosts += 1
		_detach(tuning.detach_drop)
		return
	vy = minf(vy, (rise_cap - global_position.y) / delta + 0.0001)
	if state_t >= tuning.wall_climb_stall_s and vy < tuning.wall_climb_stall_speed:
		_detach(tuning.detach_drop) # non-upward climbing lasts 1 s
		return
	var side_speed := 0.0
	if absf(side) > 0.2:
		side_speed = signf(side) * (tuning.climb_side_speed if upward else tuning.wallrun_speed)
		if not upward and state_t < delta * 1.5: wallruns += 1
	velocity = -wall_n * 1.0 + tangent * side_speed + Vector3(0, vy, 0)

# A jump off the wall [study]: mini zone = mini-bounce, green = wallbounce
# (higher the lower in the zone), neutral = wall push (no height). The climb
# space drops by zone; the wall-tangent speed is kept.
func _climb_jump() -> void:
	var rel := global_position.y - baseline_y
	var zone := climb_zone(rel)
	var tangent := Vector3.UP.cross(wall_n).normalized()
	var along := tangent * velocity.dot(tangent)
	var out := tuning.bounce_out
	var up := 0.0
	var drop := tuning.jump_drop
	match zone:
		"mini", "below":
			out = tuning.mini_bounce_out
			up = tuning.mini_bounce_up
			drop = tuning.detach_drop
			mini_bounces += 1
		"green":
			var u := clampf((rel - tuning.mini_zone_h) / (tuning.green_zone_h - tuning.mini_zone_h), 0.0, 1.0)
			up = lerpf(tuning.jump_speed, tuning.green_up_min, u)
			bounces += 1
		_:
			wall_pushes += 1
	velocity = wall_n * out + along + Vector3(0, up, 0)
	jumped = true
	jump_buffer = -1.0
	lurch_t = 0.0
	jumps += 1
	_detach(drop)

# Normal of a climbable surface within `dist` along the view (flattened): a
# wall or any surface steeper than walkable [study], else ZERO.
func _wall_ahead(dist: float) -> Vector3:
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, _flat_forward() * dist, hit): return Vector3.ZERO
	var n := hit.get_normal()
	if n.y >= tuning.min_floor_normal_y or n.y < -0.3: return Vector3.ZERO
	return Vector3(n.x, 0, n.z).normalized()

# ---- mantle family -----------------------------------------------------------------

# A ledge in reach: a wall right ahead (facing it), a walkable top between
# mantle_min_h and the reach above the feet just past its face, headroom to
# rise, and room to stand. `reach` defaults to mantle_max_h (+ an end strafe).
# Returns {target, top, normal, h} or {}.
func find_ledge(reach := -1.0, min_h := -1.0) -> Dictionary:
	if reach < 0.0:
		reach = tuning.mantle_max_h + (0.05 if end_strafe_recent() else 0.0)
	if min_h < 0.0: min_h = tuning.mantle_min_h
	var fwd := _flat_forward()
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, fwd * 0.35, hit): return {}
	var n := hit.get_normal()
	if absf(n.y) > 0.3: return {}
	n = Vector3(n.x, 0, n.z).normalized()
	if fwd.dot(-n) < 0.5: return {}
	var into := -n
	var contact := hit.get_position()
	var probe := Vector3(contact.x, 0, contact.z) + into * (RADIUS + 0.05)
	var feet := global_position.y
	var q := PhysicsRayQueryParameters3D.create(Vector3(probe.x, feet + reach + 0.05, probe.z), Vector3(probe.x, feet + min_h - 0.05, probe.z), 1, [get_rid()])
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty() or (r.normal as Vector3).y < tuning.min_floor_normal_y: return {}
	var top: float = (r.position as Vector3).y
	var h := top - feet
	if h < min_h or h > reach: return {}
	if test_move(global_transform.translated(n * 0.05), Vector3(0, h + 0.05, 0)): return {} # no headroom to rise (probed just off the wall face)
	var target := Vector3(probe.x, top, probe.z)
	if not can_stand(target + Vector3(0, 0.02, 0)): return {}
	return {"target": target, "top": top, "normal": n, "h": h}

var _last_now := 0.0
func end_strafe_recent() -> bool:
	return _last_now - end_strafe_t < 0.4

# Auto mantle [study]: holding jump on the ground into an obstacle up to
# auto_mantle_h mantles it; below insta_mantle_speed it also takes
# step-height obstacles (insta-mantle).
func _try_ground_mantle(wish: Vector3) -> bool:
	var slow := horizontal_speed() < tuning.insta_mantle_speed
	var ledge := find_ledge(tuning.auto_mantle_h, 0.05 if slow else tuning.step_height + 0.01)
	if ledge.is_empty(): return false
	if wish != Vector3.ZERO and not _mantle_input_ok(wish, ledge.normal): return false
	if wish == Vector3.ZERO and not slow: return false
	if slow and ledge.h <= tuning.step_height + 0.01: insta_mantles += 1
	else: auto_mantles += 1
	_start_mantle(ledge, false, _last_now)
	return true

func _start_mantle(ledge: Dictionary, from_climb: bool, now: float) -> void:
	var h: float = ledge.top - global_position.y
	var phase := "pull" if h <= tuning.mantle_pull_only_h else "grab"
	mantle = {"phase": phase, "t": 0.0, "start": global_position, "target": ledge.target, "top": ledge.top, "normal": ledge.normal,
		"from_hang": false, "from_climb": from_climb, "sprint": horizontal_speed() >= 0.8 * run_top(), "glide_tick": -1, "glide_ok": false, "pull_start": global_position}
	state = Move.MANTLE
	velocity = Vector3.ZERO
	if crouching: _set_crouch(false)
	mantles += 1
	_last_now = now

func _mantle_cancel() -> void:
	velocity = Vector3(mantle.normal) * 1.5
	mantle = {}
	state = Move.AIR
	mantle_cancels += 1

# Grab (up to the hang point) -> hang (until input) -> pull (up and over) [R13].
# Any phase: Shift superglides off the ledge toward the held direction
# (forward if none), no timing window; a jump is a mantle hop (grab/hang) or
# a mantle jump (pull). Grab/hang: W (forward) climbs (the pull); A/D shimmy
# along the ledge; S does nothing; move keys never drop the player off.
# Pull: in its last superglide_window_s a crouch is a mantle boost (and, with
# apex_timed_superglide on, a jump then a crouch one tick later is the old
# superglide). Returns true while the mantle moves the body itself.
func _mantle_tick(move: Vector2, wish: Vector3, jump_edge: bool, crouch_edge: bool, glide_edge: bool, now: float, delta: float) -> bool:
	_last_now = now
	var m := mantle
	var n: Vector3 = m.normal
	var forward := move.y > 0.0
	var top: float = m.top
	if glide_edge:
		_ledge_glide(wish)
		return false
	var hang_pos := Vector3(Vector3(m.start).x, top - HANG_BELOW_TOP, Vector3(m.start).z)
	match String(m.phase):
		"grab", "hang":
			if jump_edge:
				_mantle_jump(move, true)
				return false
			if m.phase == "grab":
				m.t = minf(float(m.t) + delta, tuning.mantle_grab_s)
				global_position = Vector3(m.start).lerp(hang_pos, smoothstep(0.0, 1.0, m.t / tuning.mantle_grab_s))
				if m.t >= tuning.mantle_grab_s - 1e-6:
					if forward: _begin_pull(m)
					else:
						m.phase = "hang"
						m.from_hang = true
						hangs += 1
			else:
				if forward: _begin_pull(m)
				elif move.x != 0.0: _shimmy(m, move, delta)
				global_position = Vector3(Vector3(m.start).x, top - HANG_BELOW_TOP, Vector3(m.start).z)
			velocity = Vector3.ZERO
			return true
	# Pull.
	var dur := tuning.mantle_s
	var remaining: float = dur - float(m.t)
	var in_window := remaining > 0.0 and remaining <= tuning.superglide_window_s + 1e-6
	if int(m.glide_tick) >= 0 and tuning.apex_timed_superglide:
		var gap := tick_n - int(m.glide_tick)
		if crouch_edge and gap == tuning.superglide_gap_ticks and bool(m.glide_ok):
			_superglide(now)
			return false
		if gap >= tuning.superglide_gap_ticks:
			_mantle_jump(move, false)
			return false
	elif jump_edge:
		if in_window and not crouch_edge and tuning.apex_timed_superglide:
			m.glide_tick = tick_n
			m.glide_ok = bool(m.sprint) and now - slide_entry_at >= tuning.superglide_cooldown_s
		elif in_window and crouch_edge and not bool(m.from_hang):
			_mantle_boost(now) # jump and crouch on one tick: the crouch wins
			return false
		else:
			_mantle_jump(move, false)
			return false
	elif crouch_edge and in_window and not bool(m.from_hang):
		_mantle_boost(now)
		return false
	m.t = minf(float(m.t) + delta, dur)
	var u: float = m.t / dur
	var start: Vector3 = m.pull_start
	var target: Vector3 = m.target
	var rise := 0.6
	var pos := start
	if u < rise:
		pos.y = lerpf(start.y, top + 0.02, smoothstep(0.0, 1.0, u / rise))
	else:
		pos = Vector3(start.x, top + 0.02, start.z).lerp(Vector3(target.x, top + 0.02, target.z), (u - rise) / (1.0 - rise))
	global_position = pos
	velocity = Vector3.ZERO
	if m.t >= dur - 1e-6 and int(m.glide_tick) < 0:
		# Clamber [study rule]: another ledge in reach right at the top chains a pull.
		if forward:
			var next := find_ledge()
			if not next.is_empty() and float(next.top) > top + 0.1:
				_start_mantle(next, false, now)
				mantle.phase = "pull"
				mantle.pull_start = global_position
				clambers += 1
				return true
		# Done: standing on top with a little forward speed; the normal move
		# this tick settles onto the floor.
		state = Move.GROUND
		velocity = -n * tuning.mantle_exit_speed + Vector3(0, -1.0, 0)
		since_floor = 0.0
		mantle = {}
		return false
	return true

# Shimmy [R13]: A/D slide the hang along the ledge (left/right as the camera
# sees it) at shimmy_speed, as long as the wall and its top continue there
# and nothing blocks the way; it stops at the ledge's end or a wall.
func _shimmy(m: Dictionary, move: Vector2, delta: float) -> void:
	var n: Vector3 = m.normal
	var along := n.cross(Vector3.UP).normalized()
	var cam_right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := along * signf(move.x) * (1.0 if cam_right.dot(along) >= 0.0 else -1.0)
	var step := dir * tuning.shimmy_speed * delta
	var top: float = m.top
	var at := Vector3(Vector3(m.start).x, top - HANG_BELOW_TOP, Vector3(m.start).z) + step
	var space := get_world_3d().direct_space_state
	var chest := at + Vector3(0, HANG_BELOW_TOP - 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(chest, chest - n * (RADIUS + 0.6), 1, [get_rid()])
	if space.intersect_ray(q).is_empty(): return # the wall ends here
	var over := Vector3(at.x, top + 0.5, at.z) - n * (RADIUS + 0.3)
	var q2 := PhysicsRayQueryParameters3D.create(over, over - Vector3(0, 0.9, 0), 1, [get_rid()])
	var lip := space.intersect_ray(q2)
	if lip.is_empty() or absf(float(lip.position.y) - top) > 0.15: return # the ledge ends (or steps)
	if test_move(Transform3D(global_transform.basis, Vector3(Vector3(m.start).x, top - HANG_BELOW_TOP, Vector3(m.start).z)), step): return # a wall in the way
	m.start = Vector3(m.start) + step
	m.target = Vector3(m.target) + step
	shimmied += step.length()

# Superglide off a ledge [R13]: Shift, any time on the mantle, no timing
# window. The held move keys pick the direction (camera-relative, normalised,
# like Quick Step; forward if none): ledge_glide_speed that way plus
# ledge_glide_up of lift, then normal air physics. Over the ledge it starts
# from the lip. No dash charge, no cooldown, no i-frames.
func _ledge_glide(wish: Vector3) -> void:
	var n: Vector3 = mantle.normal
	var dir := wish.normalized() if wish != Vector3.ZERO else _flat_forward()
	if dir.dot(-n) > 0.1: global_position.y = float(mantle.top) + 0.05 # over the lip
	velocity = dir * tuning.ledge_glide_speed + Vector3.UP * tuning.ledge_glide_up
	state = Move.AIR
	mantle = {}
	superglides += 1
	ledge_glides += 1

func _begin_pull(m: Dictionary) -> void:
	m.phase = "pull"
	m.t = 0.0
	m.pull_start = global_position

# Mantle hop (from a grab or hang) and mantle jump (from a pull): push off the
# wall and jump; with no move input, higher (gorilla jump).
func _mantle_jump(move: Vector2, hop: bool) -> void:
	var n: Vector3 = mantle.normal
	var up := tuning.jump_speed * (tuning.gorilla_mult if move == Vector2.ZERO else 1.0)
	velocity = n * tuning.mantle_jump_back
	_jump(up)
	state = Move.AIR
	mantle = {}
	mantle_jumps += 1
	if hop: mantle_hops += 1

# Mantle boost [apex]: an instant push over the ledge, no cooldown.
func _mantle_boost(now: float) -> void:
	var into := -Vector3(mantle.normal)
	global_position.y = float(mantle.top) + 0.05
	velocity = into * tuning.mantle_boost_speed
	surf_slide = true
	state = Move.AIR
	mantle = {}
	mantle_boosts += 1

# Launch: superglide_speed total (study: ~540 hu/s combined), superglide_up
# of it vertical [design], the rest over the ledge. Counts as a slide entry
# for the shared boost cooldown.
func _superglide(now: float) -> void:
	var into := -Vector3(mantle.normal)
	global_position.y = float(mantle.top) + 0.05
	velocity = into * sqrt(maxf(tuning.superglide_speed * tuning.superglide_speed - tuning.superglide_up * tuning.superglide_up, 0.0))
	_jump(tuning.superglide_up)
	slide_entry_at = now
	_set_crouch(true)
	state = Move.AIR
	mantle = {}
	superglides += 1

# Where the hands go while mantling or climbing (presentation; the arms rig
# plants on it): {point, normal} in world space, or {} when the hands are free.
# Mantle: the ledge's top edge in front of the player, facing up. Climb: the
# wall in front of the eyes, facing out.
func hand_contact() -> Dictionary:
	if state == Move.MANTLE and not mantle.is_empty():
		var n: Vector3 = mantle.normal
		var edge: Vector3 = Vector3(mantle.target) + n * (RADIUS + 0.05)
		return {"point": Vector3(edge.x, float(mantle.top), edge.z), "normal": Vector3.UP}
	if state == Move.WALLCLIMB and wall_n != Vector3.ZERO:
		var at := global_position + Vector3(0, height() - 0.35, 0) - wall_n * RADIUS
		return {"point": at, "normal": wall_n}
	return {}

# ---- step-up ---------------------------------------------------------------------

# Step-up (move_and_slide has none): if this tick's horizontal move hits a
# wall-like face, but the same move from step_height higher is clear and
# there is walkable floor below it within step_height, make the move up,
# across and down onto the step ourselves. Returns true when it did.
# Higher obstacles (ledges, the 0.6 m jump blocks) still block.
func _step_up(delta: float) -> bool:
	var h := Vector3(velocity.x, 0, velocity.z) * delta
	if h.length() < 0.0005: return false
	var lift := Vector3(0, 0.04, 0) # clear of the floor so the probe meets only the step face
	var base := global_transform.translated(lift)
	var hit := KinematicCollision3D.new()
	if not test_move(base, h, hit): return false
	if hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle: return false # a walkable slope: move_and_slide handles it
	var up := Vector3(0, tuning.step_height, 0)
	if test_move(base, up): return false # no headroom
	var raised := base.translated(up)
	var far := raised.translated(h.normalized() * maxf(h.length(), RADIUS + 0.05))
	if test_move(raised, far.origin - raised.origin): return false # still blocked higher up: a wall, not a step
	var probe := KinematicCollision3D.new()
	if not test_move(far, -(up + lift * 2.0), probe): return false # no floor within reach
	if probe.get_normal().angle_to(Vector3.UP) > floor_max_angle: return false
	var landing := raised.origin + h
	landing.y = far.origin.y + probe.get_travel().y
	var rise := landing.y - global_position.y
	if rise <= 0.01: return false
	global_position = landing
	step_offset = minf(step_offset + rise, tuning.step_height)
	steps_up += 1
	return true

# move_and_slide integrates over the physics delta; scale the velocity so the
# body covers `delta` worth of motion (bullet time hands in a scaled delta).
func _move_scaled(delta: float) -> void:
	var phys := get_physics_process_delta_time()
	var k := delta / phys if phys > 0.0 else 1.0
	if is_equal_approx(k, 1.0):
		move_and_slide()
		return
	velocity *= k
	move_and_slide()
	velocity /= k

# What the crosshair points at within reach: {collider, position} or {}.
# Mask: world (1) + interactable (4), so walls hide items behind them.
func look_target(mask := 0b101) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * INTERACT_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	q.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(q)

func eye_position() -> Vector3:
	return camera.global_position
