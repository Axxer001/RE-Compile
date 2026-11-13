extends RefCounted
# Grimoire movement (Tech Spec §2.1, docs/pivot-grimoire-plan.md §8 P1): run
# speed from the Mov Spd stat, accel 45 / friction 12, dash (20 m/s decaying
# to run over 0.25 s, 0.15 s i-frames against every damage kind, 1.2 s
# cooldown), slide (1.4 x Mov Spd decaying over 1.2 s, Ctrl again cancels,
# 0.9 m hitbox), jump +8.5 under gravity 22 and the double jump +7.0. Then
# the Apex layer kept by D1 (Source air strafe and bunny hop, lurch, tap
# strafe, mantle family, superglide, wall climb), each system behind its own
# switch, checked off too. Driven through the session with synthetic keys,
# like play. The shooter-era version is reference/shooter/tests/test_movement_apex.gd.
#
# Teleport rule: after moving the body by hand, is_on_floor() keeps its old
# value until the next move, and a stale "on floor" also opens coyote time
# (ground acceleration in the air). air_at() steps once before setting an
# airborne state.

const DT := 1.0 / 60.0

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement() # fresh state, charges and cooldowns

# Airborne at `at` with velocity `v`, the stale floor contact cleared.
static func air_at(c: Node3D, tree: SceneTree, at: Vector3, yaw_deg: float, v: Vector3) -> void:
	var p: CharacterBody3D = c.player
	place(c, at, yaw_deg)
	await tree.physics_frame
	c.session.step(DT)
	p.global_position = at
	p.velocity = v
	p.state = p.Move.AIR
	p.since_floor = 1.0
	p.lurch_t = INF

static func tap(c: Node3D, keys: Dictionary, k: int) -> void:
	keys[k] = true; c.session.step(DT); keys.erase(k)

static func land(c: Node3D) -> void:
	for i in 180:
		c.session.step(DT)
		if c.player.is_on_floor() and c.player.state == c.player.Move.GROUND: break
	steps(c, 3)

static func heading(v: Vector3) -> float: # degrees, 0 = north (-Z), + = toward east
	return rad_to_deg(atan2(v.x, -v.z))

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies() # enemy rules are tested in test_threat
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var p: CharacterBody3D = c.player
	var T: Resource = p.tuning
	var RUN: float = p.run_top()
	var CROUCH: float = RUN * T.crouch_ratio
	var JH: float = T.jump_speed * T.jump_speed / (2.0 * T.gravity) # full jump height
	# Spec values (Tech Spec §2.1), written out literally so a retune cannot pass silently.
	check.call(T.run_speed == 10.0 and T.ground_accel == 45.0 and T.ground_friction == 12.0 and T.gravity == 22.0 and T.jump_speed == 8.5 and T.double_jump_speed == 7.0 and T.air_jumps_max == 1, "tuning [spec]: run 10, accel 45, friction 12, gravity 22, jump 8.5, double jump 7.0")
	check.call(T.dash_charges == 1 and T.dash_speed == 20.0 and T.dash_s == 0.25 and T.dash_iframes_s == 0.15 and T.dash_recharge_s == 1.2 and T.slide_entry_mult == 1.4 and T.slide_s == 1.2 and p.CROUCH_HEIGHT == 0.9, "tuning [spec]: dash 20 m/s over 0.25 s, 0.15 s i-frames, 1.2 s cooldown; slide 1.4x over 1.2 s, 0.9 m hitbox")
	check.call(T.apex_lurch and T.apex_mantle and T.apex_climb and T.apex_fall_stun and T.apex_jump_fatigue and T.apex_bhop_penalty and T.apex_slopes and T.apex_damage_slow, "the Apex layer is on by default (D1), one switch per system")
	check.call(p.dash_charges == 1 and p.air_jumps == 1, "dash and double jump are on: one charge, one air jump")
	check.call(T.min_floor_normal_y == 0.7 and is_equal_approx(cos(p.floor_max_angle), 0.7) and is_equal_approx(p.floor_snap_length, T.step_height) and p.max_slides == T.max_bumps, "walkable at normal.y >= %.1f, ground snap %.2f m, %d clip bumps" % [T.min_floor_normal_y, T.step_height, T.max_bumps])

	# ---- run speed = Mov Spd [spec] -----------------------------------------------------
	check.call(p.stats == s.stats and is_equal_approx(RUN, s.stats.value("mov_spd", s.run.time)) and is_equal_approx(RUN, 10.0), "run speed reads the Mov Spd stat (%.1f m/s)" % RUN)
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	s.stats.add_modifier("test_haste", "mov_spd", 1.0, 5.0, s.run.time + 3.0)
	keys[KEY_W] = true
	steps(c, 40)
	var hasted: float = p.horizontal_speed()
	keys.erase(KEY_W)
	s.stats.modifiers.clear()
	steps(c, 30)
	check.call(absf(hasted - 15.0) < 0.05 and is_equal_approx(p.run_top(), 10.0), "Mov Spd +5 (a modifier) runs at %.2f m/s; it expires back to 10" % hasted)

	# ---- ground: accel 45, friction 12 [spec] -------------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 6)
	var v6: float = p.horizontal_speed()
	var acc_ticks := 6
	while p.horizontal_speed() < RUN - 0.001 and acc_ticks < 60:
		s.step(DT)
		acc_ticks += 1
	steps(c, 20)
	check.call(absf(v6 - 45.0 * 6.0 * DT) < 0.05 and acc_ticks * DT <= 0.25 and absf(p.horizontal_speed() - RUN) < 0.01, "accel 45 m/s²: %.2f m/s after 0.1 s, run speed in %.2f s, then exactly %.0f" % [v6, acc_ticks * DT, RUN])
	# D alone and W + D run at the same speed (no forward-only sprint).
	keys.erase(KEY_W); keys[KEY_D] = true
	steps(c, 40)
	var side_v: float = p.horizontal_speed()
	keys[KEY_W] = true
	steps(c, 40)
	var diag_v: float = p.horizontal_speed()
	keys.erase(KEY_W); keys.erase(KEY_D)
	check.call(absf(side_v - RUN) < 0.05 and absf(diag_v - RUN) < 0.05, "sideways %.2f and diagonal %.2f: the same run speed" % [side_v, diag_v])
	# Friction: releasing everything at run speed stops within 0.25 s.
	var stop_ticks := 0
	while p.horizontal_speed() > 0.01 and stop_ticks < 60:
		s.step(DT)
		stop_ticks += 1
	check.call(stop_ticks * DT <= 0.25, "friction 12: %.0f m/s to a stop in %.2f s" % [RUN, stop_ticks * DT])
	# Above run speed with W held: friction pulls it back to run speed, not below for long.
	p.velocity = Vector3(0, 0, -16.0)
	keys[KEY_W] = true
	steps(c, 6)
	var over6: float = p.horizontal_speed()
	steps(c, 30)
	keys.erase(KEY_W)
	check.call(over6 <= RUN + 0.01 and absf(p.horizontal_speed() - RUN) < 0.01, "overspeed with input: 16 m/s back to run in 0.1 s (%.2f), then holds %.0f" % [over6, RUN])
	steps(c, 30)

	# ---- Source air layer: air strafe, bunny hop, clip ---------------------------------
	# A press in the air spends the double jump, so these hop and buffer checks run
	# with it off (air_jumps_max 0), as after the double jump is used.
	T.air_jumps_max = 0
	# Air strafe: D + turning right 120° in the air ends faster than it started;
	# the same turn with no strafe key keeps the speed (nothing to accelerate).
	for strafe in [true, false]:
		await air_at(c, tree, Vector3(60, 7.0, 60), 0.0, Vector3(0, 0, -RUN))
		if strafe: keys[KEY_D] = true
		for i in 40:
			p.queue_look(Vector2(3.0, 0)) # 3 degrees right per tick
			s.step(DT)
		keys.erase(KEY_D)
		var after: float = p.horizontal_speed()
		if strafe:
			check.call(after > RUN + 1.0 and after < RUN + 8.0 and p.state == p.Move.AIR, "air strafe (D + turning right): %.2f m/s from %.1f" % [after, RUN])
		else:
			check.call(absf(after - RUN) < 0.01, "turning with no strafe key: speed unchanged (%.2f)" % after)
		land(c)
	# Bunny hop: a buffered jump on the landing tick keeps 100% of the speed.
	await air_at(c, tree, Vector3(60, 1.0, 60), 0.0, Vector3(0, 0, -14.0))
	var guard := 0
	while p.global_position.y > 0.25 and guard < 60:
		s.step(DT)
		guard += 1
	var hop0: int = p.jumps
	tap(c, keys, KEY_SPACE) # just before touchdown: buffered
	var hop_speed := 0.0
	for i in 12:
		s.step(DT)
		if p.jumps > hop0:
			hop_speed = p.horizontal_speed()
			break
	var hop_expect: float = maxf(RUN, 14.0 - T.bhop_penalty)
	check.call(p.jumps == hop0 + 1 and absf(hop_speed - hop_expect) < 0.02 and p.bhop_penalties == 1, "bunny hop above run speed: the landing-tick jump loses up to %.2f m/s (14 -> %.2f, expected %.2f) [apex]" % [T.bhop_penalty, hop_speed, hop_expect])
	land(c)
	# Below run speed a landing-tick jump keeps 100% (no friction on the jump tick).
	await air_at(c, tree, Vector3(60, 1.0, 60), 0.0, Vector3(0, 0, -6.0))
	guard = 0
	while p.global_position.y > 0.25 and guard < 60:
		s.step(DT)
		guard += 1
	hop0 = p.jumps
	tap(c, keys, KEY_SPACE)
	hop_speed = 0.0
	for i in 12:
		s.step(DT)
		if p.jumps > hop0:
			hop_speed = p.horizontal_speed()
			break
	check.call(p.jumps == hop0 + 1 and hop_speed > 6.0 * 0.999 and p.bhop_penalties == 0, "bunny hop below run speed keeps 100%% of 6 m/s (%.3f)" % hop_speed)
	land(c)
	# Five chained hops: hold speed without strafing, gain with circle strafing.
	for strafe in [false, true]:
		# Unstrafed hops go 35 m north: start by the south wall, clear of the slide-gap wall at z 30.
		await air_at(c, tree, Vector3(60, 1.2, 60 if strafe else 74), 0.0, Vector3(0, 0, -14.0))
		if strafe: keys[KEY_D] = true
		var hops := 0
		var j0: int = p.jumps
		for i in 400:
			if strafe: p.queue_look(Vector2(3.0, 0))
			if p.velocity.y < 0.0 and p.global_position.y < 0.25 and p.state == p.Move.AIR: tap(c, keys, KEY_SPACE)
			else: s.step(DT)
			hops = p.jumps - j0
			if hops >= 5: break
		keys.erase(KEY_D)
		var v5: float = p.horizontal_speed()
		if strafe: check.call(hops == 5 and v5 >= RUN - 0.05, "5 strafed hops stay at or above run speed (%.2f, run %.2f)" % [v5, RUN])
		else: check.call(hops == 5 and absf(v5 - RUN) < 0.05, "5 hops from 14 m/s bleed down to run speed (%.2f vs %.2f) [apex]" % [v5, RUN])
		land(c)
	# Clip: sliding along a wall keeps the tangential speed.
	await air_at(c, tree, Vector3(100, 2.0, 1.0), 0.0, Vector3(8.0, 0, -8.0))
	steps(c, 10)
	check.call(p.velocity.x > 7.9 and absf(p.velocity.z) < 0.5 and p.global_position.z < 0.6, "clip: along the north wall at 45 deg keeps the 8 m/s tangent (%.2f, %.2f)" % [p.velocity.x, p.velocity.z])
	land(c)

	T.air_jumps_max = 1

	# ---- dash [spec]: Shift, 20 m/s decaying to run over 0.25 s, i-frames, 1.2 s cooldown ----
	place(c, Vector3(60, 0, 62), 0.0)
	await tree.physics_frame
	steps(c, 2)
	var a: Vector3 = p.global_position
	var t_dash: float = s.run.time
	tap(c, keys, KEY_SHIFT)
	var v_first: float = p.horizontal_speed()
	var worst_decay := 0.0 # the dash speed against the linear 20 -> 10 line, worst tick
	for i in int(round(T.dash_s / DT)) - 1:
		s.step(DT)
		if p.state == p.Move.DASH:
			var line: float = lerpf(T.dash_speed, RUN, p.state_t / T.dash_s)
			worst_decay = maxf(worst_decay, absf(p.horizontal_speed() - line - (T.dash_speed - RUN) * DT / T.dash_s))
	s.step(DT)
	var dashed: float = Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
	var expect := 0.0
	for k in int(round(T.dash_s / DT)): expect += lerpf(T.dash_speed, RUN, k * DT / T.dash_s) * DT
	check.call(p.dashes == 1 and absf(v_first - T.dash_speed) < 0.01 and absf(dashed - expect) < 0.3 and p.global_position.z < a.z, "dash: %.0f m/s at once, %.2f m in %.2f s with no input (expected %.2f)" % [v_first, dashed, T.dash_s, expect])
	check.call(worst_decay < 0.05, "dash speed decays linearly to run speed (worst tick off the line by %.3f m/s)" % worst_decay)
	check.call(p.state != p.Move.DASH and absf(p.horizontal_speed() - RUN) < 0.3, "after the dash: run speed (%.2f)" % p.horizontal_speed())
	check.call(p.health.immune_to("bite", t_dash + 0.1) and p.health.immune_to("fire", t_dash + 0.1) and p.health.immune_to("spell", t_dash + 0.1) and not p.health.immune_to("bite", t_dash + T.dash_iframes_s + 0.04), "dash i-frames: %.2f s against every damage kind (S8), then none" % T.dash_iframes_s)
	steps(c, 3)
	tap(c, keys, KEY_SHIFT)
	check.call(p.dashes == 1 and p.state != p.Move.DASH, "a second Shift inside the 1.2 s cooldown is refused")
	var cd_ticks := 0
	while p.dash_charges == 0 and cd_ticks < 200:
		s.step(DT)
		cd_ticks += 1
	var since: float = s.run.time - t_dash
	check.call(absf(since - T.dash_recharge_s) < 2.5 * DT, "the dash charge is back %.2f s after the dash (1.2)" % since)
	# Dash direction follows the move input: A held dashes west.
	place(c, Vector3(60, 0, 62), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_A] = true
	tap(c, keys, KEY_SHIFT)
	var dash_h := heading(p.velocity)
	keys.erase(KEY_A)
	check.call(p.state == p.Move.DASH and absf(dash_h + 90.0) < 1.0, "A + Shift dashes west (heading %.0f deg)" % dash_h)
	steps(c, 40)
	# The impulse scales with Mov Spd: at 15 the dash starts at 30 m/s.
	place(c, Vector3(60, 0, 62), 0.0)
	await tree.physics_frame
	steps(c, 2)
	s.stats.add_modifier("test_haste", "mov_spd", 1.0, 5.0, s.run.time + 3.0)
	tap(c, keys, KEY_SHIFT)
	var v_haste: float = p.horizontal_speed()
	s.stats.modifiers.clear()
	check.call(absf(v_haste - 30.0) < 0.05, "dash impulse x Mov Spd / 10: %.1f m/s at Mov Spd 15" % v_haste)
	steps(c, 40)

	# ---- slide [spec]: Ctrl while running, 1.4 x Mov Spd decaying over 1.2 s -----------
	# From a standstill (below 0.7 x run) Ctrl crouches; at run speed it slides.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_CTRL] = true
	s.step(DT)
	check.call(p.crouching and p.state != p.Move.SLIDE and is_equal_approx(p.height(), 0.9), "Ctrl at a standstill crouches (0.9 m), no slide")
	keys.erase(KEY_CTRL)
	steps(c, 5)
	keys[KEY_W] = true
	steps(c, 30)
	keys.erase(KEY_W)
	keys[KEY_CTRL] = true
	s.step(DT)
	var entry: float = p.horizontal_speed()
	check.call(p.state == p.Move.SLIDE and p.crouching and is_equal_approx(p.height(), 0.9) and absf(entry - T.slide_entry_mult * RUN) < 0.3, "Ctrl at run speed: slide at %.2f m/s (1.4 x %.0f), 0.9 m hitbox" % [entry, RUN])
	var slide_ticks := 1
	var worst_slide := 0.0
	while p.state == p.Move.SLIDE and slide_ticks < 200:
		s.step(DT)
		slide_ticks += 1
		if p.state == p.Move.SLIDE:
			worst_slide = maxf(worst_slide, absf(p.horizontal_speed() - lerpf(T.slide_entry_mult * RUN, CROUCH, p.state_t / T.slide_s)))
	check.call(absf(slide_ticks * DT - T.slide_s) < 2.5 * DT and worst_slide < 0.3 and p.crouching and p.horizontal_speed() < CROUCH + 0.3, "the slide decays linearly (worst tick %.2f m/s off) and ends after %.2f s at crouch speed, Ctrl held -> crouch" % [worst_slide, slide_ticks * DT])
	keys.erase(KEY_CTRL)
	steps(c, 30)
	# Ctrl again cancels: tap Ctrl to slide, it keeps sliding; tap again stands up.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 30)
	keys.erase(KEY_W)
	tap(c, keys, KEY_CTRL)
	steps(c, 15)
	var still: bool = p.state == p.Move.SLIDE
	tap(c, keys, KEY_CTRL)
	s.step(DT)
	check.call(still and p.state != p.Move.SLIDE and not p.crouching, "Ctrl tapped: the slide carries on (%s); Ctrl again cancels and stands up" % still)
	steps(c, 30)
	# Slide jump: Space during the slide leaves at the slide's speed.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 30)
	keys.erase(KEY_W)
	keys[KEY_CTRL] = true
	steps(c, 10)
	var slide_v: float = p.horizontal_speed()
	tap(c, keys, KEY_SPACE)
	keys.erase(KEY_CTRL)
	steps(c, 2)
	check.call(p.state == p.Move.AIR and p.velocity.y > 0.0 and p.horizontal_speed() >= slide_v - 0.3 and not p.crouching, "slide jump: airborne, standing, at the slide speed (%.2f vs %.2f)" % [p.horizontal_speed(), slide_v])
	land(c)
	steps(c, 30)
	# A small drop (falls slower than the landing entry) with Ctrl held is a crouch.
	await air_at(c, tree, Vector3(60, 0.3, 62), 0.0, Vector3(0, 0, -4.0))
	keys[KEY_CTRL] = true
	for i in 30: s.step(DT)
	check.call(p.crouching and p.state != p.Move.SLIDE, "landing slowly (fall < %.2f m/s) with Ctrl held: crouch, no slide" % T.slide_land_min_fall)
	keys.erase(KEY_CTRL)
	steps(c, 10)
	# A real drop at 4 m/s across with Ctrl held slides on landing [apex].
	await air_at(c, tree, Vector3(60, 1.5, 62), 0.0, Vector3(0, 0, -4.0))
	keys[KEY_CTRL] = true
	s.step(DT)
	check.call(p.crouching and p.state == p.Move.AIR, "Ctrl in the air crouches")
	var slid_on_landing := false
	for i in 40:
		s.step(DT)
		if p.state == p.Move.SLIDE:
			slid_on_landing = true
			break
	check.call(slid_on_landing and absf(p.horizontal_speed() - T.slide_entry_mult * RUN) < 0.3, "landing entry: falling fast at 4 m/s across with Ctrl held -> slide at %.2f m/s" % p.horizontal_speed())
	keys.erase(KEY_CTRL)
	steps(c, 90)

	# ---- jumps [spec]: +8.5 under gravity 22; double jump +7.0 keeping the horizontal vector ----
	place(c, Vector3(60, 0, 55), 0.0)
	await tree.physics_frame
	steps(c, 3)
	var j0: int = p.jumps
	tap(c, keys, KEY_SPACE)
	var peak1 := 0.0
	for i in 90:
		s.step(DT)
		peak1 = maxf(peak1, p.global_position.y)
		if p.is_on_floor() and i > 3: break
	check.call(p.jumps == j0 + 1 and absf(peak1 - JH) < 0.06 and absf(JH - 1.642) < 0.01, "jump: +%.1f m/s under %.0f peaks at %.2f m (%.2f)" % [T.jump_speed, T.gravity, JH, peak1])
	steps(c, 60)
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 30)
	keys.erase(KEY_W)
	j0 = p.jumps
	tap(c, keys, KEY_SPACE)
	steps(c, 12)
	var vh_before := Vector2(p.velocity.x, p.velocity.z)
	tap(c, keys, KEY_SPACE)
	var vh_after := Vector2(p.velocity.x, p.velocity.z)
	check.call(p.jumps == j0 + 2 and absf(p.velocity.y - T.double_jump_speed) < 0.4 and vh_after.distance_to(vh_before) < 0.3 and vh_after.length() > RUN - 1.0, "double jump: up at %.1f m/s, horizontal %.2f m/s kept (%.2f before)" % [p.velocity.y, vh_after.length(), vh_before.length()])
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 2 and p.air_jumps == 0, "only one double jump per airtime")
	land(c)
	check.call(p.air_jumps == 1, "landing restores the double jump")
	steps(c, 60)
	# Default [Sir: "No, keep double jump"]: a press just above the floor while
	# falling is the double jump, not a buffered hop.
	check.call(not T.hop_buffer_enabled, "no landing-hop buffer by default (keep the double jump)")
	await air_at(c, tree, Vector3(60, 1.2, 74), 0.0, Vector3(0, 0, -9.0))
	var gd := 0
	while p.global_position.y > 0.25 and gd < 60:
		s.step(DT)
		gd += 1
	var jd: int = p.jumps
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == jd + 1 and p.air_jumps == 0 and p.velocity.y > 6.0, "default: a press 0.25 m above the floor spends the double jump")
	land(c)
	# The optional buffered hop (hop_buffer_enabled): a press while falling within
	# 0.3 m of the floor waits for touchdown: a ground jump that keeps the speed,
	# the double jump still in hand.
	T.hop_buffer_enabled = true
	await air_at(c, tree, Vector3(60, 1.2, 74), 0.0, Vector3(0, 0, -9.0))
	var gb := 0
	while p.global_position.y > 0.25 and gb < 60:
		s.step(DT)
		gb += 1
	var jb: int = p.jumps
	var vfall: float = p.horizontal_speed()
	tap(c, keys, KEY_SPACE)
	var held_off: bool = p.jumps == jb and p.air_jumps == 1
	var hop_v := 0.0
	for i in 12:
		s.step(DT)
		if p.jumps > jb:
			hop_v = p.horizontal_speed()
			break
	check.call(held_off and p.jumps == jb + 1 and absf(hop_v - vfall) < 0.02 and p.air_jumps == 1 and p.velocity.y > T.jump_speed - 1.0, "buffer on: a press 0.25 m above the floor jumps on touchdown at %.2f m/s (from %.2f), double jump kept" % [hop_v, vfall])
	steps(c, 8)
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == jb + 2 and p.air_jumps == 0, "after a buffered hop the double jump still fires")
	land(c)
	# A slow fall from 0.28 m takes longer than the 0.1 s press buffer: the
	# buffer lasts until touchdown.
	await air_at(c, tree, Vector3(60, 0.28, 74), 0.0, Vector3(0, -0.2, -6.0))
	p.velocity = Vector3(0, 0.01, 0) # clear the stale floor contact this low (teleport rule)
	p.move_and_slide()
	p.global_position = Vector3(60, 0.28, 74)
	p.velocity = Vector3(0, -0.2, -6.0)
	var js: int = p.jumps
	var t_press: float = s.run.time
	tap(c, keys, KEY_SPACE)
	var t_hop := -1.0
	for i in 30:
		s.step(DT)
		if p.jumps > js:
			t_hop = s.run.time
			break
	check.call(p.jumps == js + 1 and p.air_jumps == 1 and t_hop - t_press > T.jump_buffer_s, "slow fall: the buffered hop still fires %.2f s after the press (past the 0.1 s buffer)" % (t_hop - t_press))
	land(c)
	# Rising just off the floor, a press is the double jump (only a fall buffers).
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	steps(c, 3)
	var jr: int = p.jumps
	tap(c, keys, KEY_SPACE)
	s.step(DT) # release (a press needs an up tick before it)
	var rising_y: float = p.global_position.y
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == jr + 2 and p.air_jumps == 0 and rising_y < 0.3, "rising %.2f m off the floor, a second press is the double jump (jumps +%d, air jumps %d, vy %.2f)" % [rising_y, p.jumps - jr, p.air_jumps, p.velocity.y])
	land(c)
	# High above the floor, a falling press is the double jump.
	await air_at(c, tree, Vector3(60, 3.0, 74), 0.0, Vector3(0, -2.0, 0))
	var jh: int = p.jumps
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == jh + 1 and p.air_jumps == 0 and p.velocity.y > 6.0, "falling 3 m up: the press is the double jump")
	land(c)
	# Fast fall: 0.1 s to impact counts even above 0.3 m.
	await air_at(c, tree, Vector3(60, 1.6, 74), 0.0, Vector3(0, -12.0, 0))
	var gf := 0
	while p.global_position.y > 1.0 and gf < 30:
		s.step(DT)
		gf += 1
	var jf: int = p.jumps
	var high: float = p.global_position.y
	tap(c, keys, KEY_SPACE)
	var waited: bool = p.jumps == jf and p.air_jumps == 1
	for i in 12:
		s.step(DT)
		if p.jumps > jf: break
	check.call(high > 0.4 and waited and p.jumps == jf + 1 and p.air_jumps == 1, "falling at %.0f m/s, a press %.2f m up (under 0.1 s to impact) buffers the hop" % [-p.air_vy if p.air_vy < 0.0 else 12.0, high])
	land(c)
	T.hop_buffer_enabled = false
	steps(c, 30)
	# Coyote time: a jump just after leaving the floor is a ground jump (double jump off again).
	T.air_jumps_max = 0
	p.reset_movement()
	p.global_position = Vector3(60, 1.0, 55)
	p.velocity = Vector3.ZERO
	p.since_floor = 0.0
	p.state = p.Move.GROUND
	await tree.physics_frame
	steps(c, 3) # 0.05 s off the floor
	j0 = p.jumps
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 1 and p.velocity.y > T.jump_speed - 0.5, "coyote time: jumping 0.05 s after the edge is a full ground jump")
	land(c)
	p.reset_movement()
	p.global_position = Vector3(60, 2.0, 55)
	p.velocity = Vector3.ZERO
	p.since_floor = 0.0
	p.state = p.Move.GROUND
	await tree.physics_frame
	steps(c, 10) # 0.17 s: inside the study's 0.2 s, past the old 0.1 s
	j0 = p.jumps
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 1, "coyote time is 0.2 s: a jump 0.17 s after the edge still counts")
	land(c)
	# Jump fatigue: a jump straight after landing from a jump is low; after 0.75 s it is full.
	var peaks_f := {}
	for wait in [0, 50]:
		place(c, Vector3(60, 0, 55), 0.0)
		await tree.physics_frame
		steps(c, 3)
		tap(c, keys, KEY_SPACE)
		for i in 120:
			s.step(DT)
			if p.is_on_floor() and p.state == p.Move.GROUND: break
		steps(c, wait)
		tap(c, keys, KEY_SPACE)
		var pk := 0.0
		for i in 120:
			s.step(DT)
			pk = maxf(pk, p.global_position.y)
			if p.is_on_floor() and i > 3: break
		peaks_f[wait] = pk
		steps(c, 3)
	check.call(absf(peaks_f[0] - T.fatigue_height) < 0.06, "jump fatigue: jumping on landing from a jump peaks at %.2f m (fatigue height %.2f)" % [peaks_f[0], T.fatigue_height])
	check.call(absf(peaks_f[50] - JH) < 0.06, "fatigue recovers: after %.2f s the jump peaks at %.2f m (full %.2f)" % [50 * DT + DT, peaks_f[50], JH])
	# A plain fall (no jump first) carries no fatigue.
	await air_at(c, tree, Vector3(60, 1.0, 55), 0.0, Vector3.ZERO)
	land(c)
	tap(c, keys, KEY_SPACE)
	var pk2 := 0.0
	for i in 120:
		s.step(DT)
		pk2 = maxf(pk2, p.global_position.y)
		if p.is_on_floor() and i > 3: break
	check.call(absf(pk2 - JH) < 0.06, "falling without a jump leaves no fatigue (peak %.2f)" % pk2)
	steps(c, 3)
	# Jump buffer: pressing just before landing jumps on touchdown.
	await air_at(c, tree, Vector3(60, 1.0, 55), 0.0, Vector3(0, -3.0, 0))
	guard = 0
	while p.global_position.y > 0.3 and guard < 60:
		s.step(DT)
		guard += 1
	j0 = p.jumps
	tap(c, keys, KEY_SPACE)
	var in_air_after_press: bool = p.jumps == j0 and not p.is_on_floor()
	var jumped_on_land := false
	for i in 12:
		s.step(DT)
		if p.jumps > j0:
			jumped_on_land = true
			break
	check.call(in_air_after_press and jumped_on_land, "jump buffer: a press in the air jumps on touchdown")
	land(c)

	T.air_jumps_max = 1

	# ---- §7.2 lurch and tap strafe ---------------------------------------------------
	var turns := {}
	var lurch_counts := {}
	for tap_t in [3, 18, 27]: # 0.05 s (full), 0.3 s (half), 0.45 s (over) after the jump
		place(c, Vector3(60, 0, 60), 0.0)
		await tree.physics_frame
		steps(c, 2)
		p.velocity = Vector3(0, 0, -12.0)
		p.land_t = 5.0 # long after landing: no bunny-hop penalty on this jump
		tap(c, keys, KEY_SPACE)
		steps(c, tap_t - 1)
		var h0 := heading(p.velocity)
		var l0: int = p.lurches
		keys[KEY_D] = true; steps(c, 3); keys.erase(KEY_D)
		lurch_counts[tap_t] = p.lurches - l0
		var turned: float = heading(p.velocity) - h0
		turns[tap_t] = turned
		if tap_t == 3:
			check.call(turned >= 45.0 and p.horizontal_speed() >= 0.85 * 12.0, "lurch: tap D 0.05 s after a 12 m/s jump turns %.0f deg (one lurch at 12 m/s turns about %.0f%% of the way), keeps %.0f%%" % [turned, 100.0 * T.lurch_ref_speed / 12.0, 100.0 * p.horizontal_speed() / 12.0])
		land(c)
	check.call(turns[18] > 0.3 * turns[3] and turns[18] < 0.75 * turns[3], "lurch decays after 0.2 s: at 0.3 s it turns %.0f deg, about half of %.0f" % [turns[18], turns[3]])
	check.call(lurch_counts[27] == 0, "no lurch after 0.4 s: tap D at 0.45 s is only air strafe (%.1f deg, 0 lurches)" % turns[27])
	# Lurch stack [study rule]: at speed, repeated presses keep turning further.
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -20.0)
	p.land_t = 5.0
	tap(c, keys, KEY_SPACE)
	steps(c, 2)
	var hs0 := heading(p.velocity)
	tap(c, keys, KEY_D)
	var one: float = heading(p.velocity) - hs0
	s.step(DT)
	tap(c, keys, KEY_D)
	s.step(DT)
	tap(c, keys, KEY_D)
	var three: float = heading(p.velocity) - hs0
	check.call(one < 60.0 and three > one + 15.0 and p.lurches >= 3, "lurch stack at 20 m/s: one press turns %.0f deg, three turn %.0f deg" % [one, three])
	land(c)
	# Combined direction [study]: holding W and pressing D lurches to 45 deg; A held + D pressed is a null lurch.
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -6.0)
	p.land_t = 5.0
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	tap(c, keys, KEY_D)
	keys.erase(KEY_W)
	var hw := heading(p.velocity)
	check.call(hw > 35.0 and hw < 55.0, "W held + D pressed: a 45 deg lurch (%.0f deg)" % hw)
	land(c)
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -6.0)
	p.land_t = 5.0
	keys[KEY_A] = true
	tap(c, keys, KEY_SPACE)
	var hn0 := heading(p.velocity)
	tap(c, keys, KEY_D)
	keys.erase(KEY_A)
	check.call(absf(heading(p.velocity) - hn0) < 3.0, "A held + D pressed: a null lurch (turned %.1f deg)" % (heading(p.velocity) - hn0))
	land(c)
	# No lurch above the ~1150 hu/s cutoff (x1.514: 44.2 m/s).
	place(c, Vector3(20, 0, 74), -90.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(48.0, 0, 0)
	p.land_t = 5.0
	tap(c, keys, KEY_SPACE)
	steps(c, 2)
	var lc0: int = p.lurches
	keys[KEY_D] = true; s.step(DT); keys.erase(KEY_D)
	check.call(p.lurches == lc0, "no lurch above %.0f m/s (tap D at 48 m/s)" % T.lurch_max_speed)
	land(c)
	# Releasing a key is not a lurch: jump holding W + D, release D at 0.05 s.
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -12.0)
	keys[KEY_W] = true; keys[KEY_D] = true
	tap(c, keys, KEY_SPACE)
	steps(c, 2)
	var lr0: int = p.lurches
	var hr0 := heading(p.velocity)
	keys.erase(KEY_D)
	steps(c, 3)
	keys.erase(KEY_W)
	check.call(p.lurches == lr0 and absf(heading(p.velocity) - hr0) < 5.0, "releasing D is not a lurch (%d lurches, turned %.1f deg)" % [p.lurches - lr0, heading(p.velocity) - hr0])
	land(c)
	# Tap strafe: 5 forward taps while turning the view 90 deg right: velocity follows the view.
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -10.0)
	tap(c, keys, KEY_SPACE)
	for i in 10:
		p.queue_look(Vector2(9.0, 0))
		if i % 2 == 0: keys[KEY_W] = true
		else: keys.erase(KEY_W)
		s.step(DT)
	keys.erase(KEY_W)
	var view_h := heading(-p.global_transform.basis.z)
	var off: float = absf(wrapf(heading(p.velocity) - view_h, -180.0, 180.0))
	check.call(p.lurches >= 5 and off < 25.0, "tap strafe: 5 W taps while turning 90 deg: velocity %.0f deg off the view (%d lurches)" % [off, p.lurches])
	land(c)
	# Back + side cancels the forward part: a pure sideways shift.
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -10.0)
	tap(c, keys, KEY_SPACE)
	keys[KEY_S] = true; keys[KEY_D] = true; s.step(DT); keys.erase(KEY_S); keys.erase(KEY_D)
	var hd := heading(p.velocity)
	check.call(hd > 70.0 and hd <= 136.0, "S + D lurch: toward the combined back-right direction (%.0f deg) [apex]" % hd)
	land(c)

	# ---- §7.2 mantle family (the 2 m ledge: face at z 43, top 2 m) ---------------------
	var ledge_at := Vector3(92, 0, 43.65)
	# Mantle: jump at the ledge, standing on top within 0.6 s.
	place(c, ledge_at, 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	var mt := 0
	for i in 60:
		s.step(DT)
		mt += 1
		if p.mantles > 0 and p.state == p.Move.GROUND and p.is_on_floor(): break
	keys.erase(KEY_W)
	check.call(p.mantles == 1 and absf(p.global_position.y - 2.0) < 0.05 and p.global_position.z < 43.0 and (mt + 1) * DT <= T.mantle_grab_s + T.mantle_s + 0.35, "mantle: jump at the 2 m ledge, grab + pull, standing on top in %.2f s (y %.2f)" % [(mt + 1) * DT, p.global_position.y])
	steps(c, 10)
	# Mantle jump at 0.2 s (W held) and gorilla jump (no input): airborne, higher with no input.
	var peaks := {}
	for gorilla in [false, true]:
		place(c, ledge_at, 0.0)
		await tree.physics_frame
		steps(c, 2)
		keys[KEY_W] = true
		tap(c, keys, KEY_SPACE)
		var w := 0
		while p.state != p.Move.MANTLE and w < 30:
			s.step(DT)
			w += 1
		steps(c, 12) # 0.2 s into the mantle
		if gorilla: keys.erase(KEY_W)
		tap(c, keys, KEY_SPACE)
		keys.erase(KEY_W)
		var up_ok: bool = p.state == p.Move.AIR and p.velocity.y > 0.0 and p.mantle_jumps == 1
		var peak := 0.0
		var stood := false
		for i in 120:
			s.step(DT)
			peak = maxf(peak, p.global_position.y)
			if p.is_on_floor() and p.global_position.y > 1.9: stood = true
			if p.is_on_floor() and p.state == p.Move.GROUND and i > 5: break
		peaks[gorilla] = peak
		check.call(up_ok and not stood, "%s at 0.2 s: airborne going up, never on the ledge (peak %.2f)" % ["gorilla jump (no input)" if gorilla else "mantle jump", peak])
		steps(c, 5)
	check.call(peaks[true] > peaks[false] + 0.2, "gorilla jump peaks higher than the mantle jump (%.2f vs %.2f)" % [peaks[true], peaks[false]])
	# Superglide: running into a mantle, jump then crouch 1 tick apart in its last 150 ms.
	var glide := {}
	# [name, ticks into the mantle, gap (0 = same tick), at full run, slide on cooldown]
	# Ticks are counted into the PULL (the window is its last 0.15 s).
	# The timed superglide is off by default [R13] (Shift on a ledge replaces it); its
	# rules still hold behind the flag.
	check.call(not T.apex_timed_superglide, "the timed (jump then crouch) superglide is off by default [R13]")
	T.apex_timed_superglide = true
	for gap_case in [["in window, 1 tick", 12, 1, true, false], ["same tick", 12, 0, true, false], ["in window, 2 ticks", 12, 2, true, false], ["too early, 1 tick", 3, 1, true, false], ["slow approach", 12, 1, false, false], ["slide on cooldown", 12, 1, true, true]]:
		place(c, ledge_at, 0.0)
		await tree.physics_frame
		steps(c, 2)
		keys[KEY_W] = true
		if gap_case[3]: p.velocity = Vector3(0, 0, -p.run_top()) # at full run (the mantle notes >= 0.8 x run)
		tap(c, keys, KEY_SPACE)
		var w2 := 0
		while (p.state != p.Move.MANTLE or String(p.mantle.get("phase", "")) != "pull") and w2 < 90:
			s.step(DT)
			w2 += 1
		if gap_case[4]: p.slide_entry_at = s.run.time # as if a slide just started
		steps(c, int(gap_case[1]) - 1)
		if int(gap_case[2]) == 0:
			keys[KEY_SPACE] = true; keys[KEY_CTRL] = true; s.step(DT); keys.erase(KEY_SPACE); keys.erase(KEY_CTRL)
		else:
			tap(c, keys, KEY_SPACE)
			steps(c, int(gap_case[2]) - 1)
			tap(c, keys, KEY_CTRL)
		var burst: float = p.horizontal_speed()
		glide[gap_case[0]] = [p.superglides, burst]
		keys.erase(KEY_W)
		land(c)
		steps(c, 5)
	var glide_h := sqrt(T.superglide_speed * T.superglide_speed - T.superglide_up * T.superglide_up)
	check.call(glide["in window, 1 tick"][0] == 1 and absf(glide["in window, 1 tick"][1] - glide_h) < 0.3, "superglide: full run, jump + crouch 1 tick apart late in the mantle -> %.1f m/s across (%.1f of %.1f total)" % [glide["in window, 1 tick"][1], glide_h, T.superglide_speed])
	for k in ["same tick", "in window, 2 ticks", "too early, 1 tick", "slow approach", "slide on cooldown"]:
		check.call(glide[k][0] == 0 and glide[k][1] < glide_h - 2.0, "superglide refused (%s): %.1f m/s" % [k, glide[k][1]])
	T.apex_timed_superglide = false

	# ---- §7.2 wall climb (climb-zone jumps: test_r1e.gd) ---------------------------
	# Climb: jump into the 3 m ledge from its foot (out of mantle reach), climb, then mantle on top.
	place(c, Vector3(98, 0, 43.4), 0.0) # 0.1 m from the face
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	for i in 90:
		s.step(DT)
		if p.mantles > 0 and p.state == p.Move.GROUND and p.is_on_floor(): break
	keys.erase(KEY_W)
	check.call(p.climbs == 1 and p.mantles == 1 and absf(p.global_position.y - 3.0) < 0.05, "wall climb: into the 3 m ledge, climb (%d), mantle (%d), on top (y %.2f)" % [p.climbs, p.mantles, p.global_position.y])
	steps(c, 5)
	# Once per airtime, and at most 1.5 m: into the 8 m arena wall.
	place(c, Vector3(110, 0, 0.55), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	var climb_rise := -1.0 # (one attach: the same wall again needs a 3.25 m drop below the first)
	var was_climbing := false
	var climbs_up := 0 # attaches while still up the wall (a reattach below the first attach, at the floor, is allowed)
	for i in 150:
		s.step(DT)
		if was_climbing and p.state != p.Move.WALLCLIMB and climb_rise < 0.0: climb_rise = p.global_position.y - p.climb_y0
		was_climbing = p.state == p.Move.WALLCLIMB
		if p.global_position.y > 1.0: climbs_up = p.climbs
		if p.is_on_floor() and p.state == p.Move.GROUND and i > 5: break
	keys.erase(KEY_W)
	check.call(climbs_up == 1 and p.end_boosts == 1 and climb_rise > 2.2 and climb_rise <= 2.54 + 0.15, "the 8 m wall: one climb, rising %.2f m to the attach offset (100 hu = 2.54), then an end boost (climbs up the wall %d, end boosts %d)" % [climb_rise, climbs_up, p.end_boosts])
	steps(c, 5)

	# ---- Apex switches: each system turns off on its own (D1) ------------------------
	# Lurch off: a D tap right after a 12 m/s jump is only air strafe.
	T.apex_lurch = false
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -12.0)
	tap(c, keys, KEY_SPACE)
	steps(c, 2)
	var hl0 := heading(p.velocity)
	keys[KEY_D] = true; steps(c, 3); keys.erase(KEY_D)
	var turned_off: float = heading(p.velocity) - hl0
	T.apex_lurch = true
	check.call(p.lurches == 0 and turned_off < 15.0, "apex_lurch off: no lurch, the D tap turns only %.1f deg" % turned_off)
	land(c)
	# Bunny-hop penalty off: a landing-tick hop at 14 m/s keeps it all (double jump off,
	# so the press is a buffered landing hop, not an air jump).
	T.apex_bhop_penalty = false
	T.air_jumps_max = 0
	await air_at(c, tree, Vector3(60, 1.0, 60), 0.0, Vector3(0, 0, -14.0))
	var g2 := 0
	while p.global_position.y > 0.25 and g2 < 60:
		s.step(DT)
		g2 += 1
	var h0: int = p.jumps
	tap(c, keys, KEY_SPACE)
	var hs := 0.0
	for i in 12:
		s.step(DT)
		if p.jumps > h0:
			hs = p.horizontal_speed()
			break
	T.apex_bhop_penalty = true
	T.air_jumps_max = 1
	check.call(p.jumps == h0 + 1 and p.air_jumps == 0 and p.land_t < 0.2 and hs > 14.0 * 0.999 and p.bhop_penalties == 0, "apex_bhop_penalty off: the hop keeps 14 m/s (%.2f)" % hs)
	land(c)
	# Jump fatigue off: jumping on landing from a jump is full height.
	T.apex_jump_fatigue = false
	place(c, Vector3(60, 0, 55), 0.0)
	await tree.physics_frame
	steps(c, 3)
	tap(c, keys, KEY_SPACE)
	for i in 120:
		s.step(DT)
		if p.is_on_floor() and p.state == p.Move.GROUND: break
	tap(c, keys, KEY_SPACE)
	var pk3 := 0.0
	for i in 120:
		s.step(DT)
		pk3 = maxf(pk3, p.global_position.y)
		if p.is_on_floor() and i > 3: break
	T.apex_jump_fatigue = true
	check.call(absf(pk3 - JH) < 0.06, "apex_jump_fatigue off: the landing jump peaks at the full %.2f m (%.2f)" % [JH, pk3])
	steps(c, 3)
	# Mantle off: jumping at the 2 m ledge does not mantle.
	T.apex_mantle = false
	place(c, Vector3(92, 0, 43.65), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	steps(c, 60)
	keys.erase(KEY_W)
	T.apex_mantle = true
	check.call(p.mantles == 0 and p.hangs == 0, "apex_mantle off: no mantle or hang at the 2 m ledge (%d, %d)" % [p.mantles, p.hangs])
	steps(c, 5)
	# Climb off: jumping into the 8 m wall does not climb.
	T.apex_climb = false
	place(c, Vector3(110, 0, 0.55), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	steps(c, 70)
	keys.erase(KEY_W)
	T.apex_climb = true
	check.call(p.climbs == 0 and p.state != p.Move.WALLCLIMB, "apex_climb off: no wall climb")
	steps(c, 5)

	# ---- view: no aiming in the Grimoire build ---------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	keys[MOUSE_BUTTON_RIGHT] = true
	keys[KEY_W] = true
	steps(c, 30)
	check.call(absf(p.camera.fov - T.fov) < 0.5 and p.aim_t == 0.0 and absf(p.horizontal_speed() - RUN) < 0.05, "RMB (special attack) neither zooms nor slows: FOV %.0f, %.2f m/s" % [p.camera.fov, p.horizontal_speed()])
	keys.erase(MOUSE_BUTTON_RIGHT); keys.erase(KEY_W)
	steps(c, 30)

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
