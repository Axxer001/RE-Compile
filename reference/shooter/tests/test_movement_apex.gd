extends RefCounted
# R1b movement (docs/movement-reference.md §7): the Source core (§7.1),
# Apex base speeds and sprint (§7.5), slide, jumps, the Apex layer (§7.2:
# lurch, tap strafe, mantle, mantle jump, gorilla jump, superglide, wall
# bounce, wall climb) and the abilities that are off in the base (§7.4:
# dash, double jump). Driven through the session with synthetic keys, like
# play. Numbers come from the tuning resource, so a retune moves the
# expectations with it.
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
	c.enemies["shambler_1"].reset_to(Vector3(112, 0, 74), 90.0, c.noise.last_id()) # out of the way, far corner
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var p: CharacterBody3D = c.player
	var T: Resource = p.tuning
	var H: float = p.speed_mult() # unarmed in these tests: the holster x1.15 applies [study]
	var WALK: float = T.run_speed * H
	var SPRINT: float = T.sprint_speed * H
	var CROUCH: float = T.crouch_speed * H
	# Study values (apex-study, 1 hu = 0.0254 m), written out literally so a retune cannot pass silently.
	check.call(T.run_speed == 4.4069 and T.sprint_speed == 6.604 and T.crouch_speed == 2.032 and T.sprint_toggle and T.gravity == 18.4207 and T.jump_speed == 7.239 and T.air_cap == 1.524 and T.coyote_s == 0.2, "tuning: apex-study numbers (walk 173.5, sprint 260, crouch 80 hu/s; jump 285 hu/s; air 60 hu/s; coyote 0.2 s)")
	check.call(T.slide_min_speed == 5.08 and T.slide_land_min_speed == 2.286 and T.slide_land_min_fall == 5.08 and T.slide_boost == 3.81 and T.slide_max_speed == 10.16 and T.lurch_full_s == 0.2 and T.lurch_window_s == 0.4 and T.wall_climb_max_h == 2.54 and T.superglide_speed == 13.716, "tuning: study slide (200/90+200, boost 150 cap 400 hu/s), lurch 0.2/0.4 s, climb 100 hu, superglide 540 hu/s")
	check.call(T.dash_charges == 0 and T.air_jumps_max == 0 and p.dash_charges == 0 and p.air_jumps == 0, "dash and double jump are off in the base (abilities, §7.4)")
	check.call(T.min_floor_normal_y == 0.7 and is_equal_approx(cos(p.floor_max_angle), 0.7) and is_equal_approx(p.floor_snap_length, T.step_height) and p.max_slides == T.max_bumps, "walkable at normal.y >= %.1f, ground snap %.2f m, %d clip bumps" % [T.min_floor_normal_y, T.step_height, T.max_bumps])

	# ---- §7.1 Source core ------------------------------------------------------------
	# Friction: releasing everything at 10 m/s stops within about 0.4 s.
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(0, 0, -10.0)
	var stop_ticks := 0
	while p.horizontal_speed() > 0.01 and stop_ticks < 60:
		s.step(DT)
		stop_ticks += 1
	check.call(stop_ticks * DT <= 0.42, "friction: 10 m/s to a stop in %.2f s (about 0.4)" % (stop_ticks * DT))
	# Ground accel: 95% of walk speed in about 0.3 s.
	keys[KEY_W] = true
	var acc_ticks := 0
	while p.horizontal_speed() < 0.95 * WALK and acc_ticks < 60:
		s.step(DT)
		acc_ticks += 1
	steps(c, 20)
	keys.erase(KEY_W)
	check.call(acc_ticks * DT <= 0.3 and absf(p.horizontal_speed() - WALK) < 0.01, "ground accel: 95%% of walk in %.2f s, then exactly %.0f m/s (%.2f)" % [acc_ticks * DT, WALK, p.horizontal_speed()])
	steps(c, 30)
	# Air strafe: D + turning right 120° in the air ends faster than it started;
	# the same turn with no strafe key keeps the speed (nothing to accelerate).
	for strafe in [true, false]:
		await air_at(c, tree, Vector3(60, 7.0, 60), 0.0, Vector3(0, 0, -WALK))
		if strafe: keys[KEY_D] = true
		for i in 40:
			p.queue_look(Vector2(3.0, 0)) # 3 degrees right per tick
			s.step(DT)
		keys.erase(KEY_D)
		var after: float = p.horizontal_speed()
		if strafe:
			# Python model of the same maths at holstered walk: 7.94 with the 1.524 cap, 4.80 with none, 15.02 uncapped.
			check.call(after > WALK + 1.5 and after < WALK + 5.0 and p.state == p.Move.AIR, "air strafe (D + turning right): %.2f m/s from %.1f (model 7.31)" % [after, WALK])
		else:
			check.call(absf(after - WALK) < 0.01, "turning with no strafe key: speed unchanged (%.2f)" % after)
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
	var hop_expect: float = maxf(SPRINT, 14.0 - T.bhop_penalty * H)
	check.call(p.jumps == hop0 + 1 and absf(hop_speed - hop_expect) < 0.02 and p.bhop_penalties == 1, "bunny hop above sprint speed: the landing-tick jump loses up to 100 hu/s (14 -> %.2f, expected %.2f) [study]" % [hop_speed, hop_expect])
	land(c)
	# Below sprint speed a landing-tick jump keeps 100% (no friction on the jump tick).
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
	check.call(p.jumps == hop0 + 1 and hop_speed > 6.0 * 0.999 and p.bhop_penalties == 0, "bunny hop below sprint speed keeps 100%% of 6 m/s (%.3f)" % hop_speed)
	land(c)
	# Five chained hops: hold speed without strafing, gain with circle strafing.
	for strafe in [false, true]:
		# Unstrafed hops go 35 m north: start by the south wall, clear of the slide-gap wall at z 30.
		await air_at(c, tree, Vector3(60, 1.2, 60 if strafe else 74), 0.0, Vector3(0, 0, -10.0))
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
		if strafe: check.call(hops == 5 and v5 >= SPRINT - 0.05, "5 strafed hops stay at or above sprint speed (%.2f, sprint %.2f)" % [v5, SPRINT])
		else: check.call(hops == 5 and absf(v5 - SPRINT) < 0.05, "5 hops from 10 m/s bleed down to sprint speed (%.2f vs %.2f) [study]" % [v5, SPRINT])
		land(c)
	# Clip: sliding along a wall keeps the tangential speed.
	await air_at(c, tree, Vector3(100, 2.0, 1.0), 0.0, Vector3(8.0, 0, -8.0))
	steps(c, 10)
	check.call(p.velocity.x > 7.9 and absf(p.velocity.z) < 0.5 and p.global_position.z < 0.6, "clip: along the north wall at 45 deg keeps the 8 m/s tangent (%.2f, %.2f)" % [p.velocity.x, p.velocity.z])
	land(c)

	# ---- §7.5 walk and sprint ----------------------------------------------------------
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true
	steps(c, 40)
	var walk_v: float = p.horizontal_speed()
	tap(c, keys, KEY_SHIFT) # toggle on
	steps(c, 40)
	var sprint_v: float = p.horizontal_speed()
	check.call(absf(walk_v - WALK) < 0.05 and absf(sprint_v - SPRINT) < 0.05 and p.sprint_on and p.sprinting, "walk %.1f m/s, Shift toggles sprint to %.1f" % [walk_v, sprint_v])
	keys.erase(KEY_W)
	keys[KEY_D] = true
	steps(c, 40)
	var side_v: float = p.horizontal_speed()
	keys.erase(KEY_D)
	check.call(side_v <= WALK + 0.05, "sideways input never exceeds walk speed (%.2f)" % side_v)
	keys[KEY_W] = true; keys[KEY_D] = true # sprint is still on (toggle)
	steps(c, 40)
	check.call(absf(p.horizontal_speed() - SPRINT) < 0.05, "forward + strafe (45 deg) still sprints (%.2f)" % p.horizontal_speed())
	keys.erase(KEY_D)
	keys[MOUSE_BUTTON_RIGHT] = true
	s.step(DT)
	keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(not p.sprint_on, "ADS cancels the sprint")
	tap(c, keys, KEY_SHIFT)
	keys[KEY_CTRL] = true; s.step(DT); keys.erase(KEY_CTRL)
	check.call(not p.sprint_on, "crouch cancels the sprint")
	tap(c, keys, KEY_SHIFT)
	keys[MOUSE_BUTTON_LEFT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_LEFT)
	check.call(not p.sprint_on, "firing cancels the sprint")
	keys.erase(KEY_W)
	steps(c, 40)
	# Hold mode.
	T.sprint_toggle = false
	place(c, Vector3(60, 0, 60), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true; keys[KEY_SHIFT] = true
	steps(c, 40)
	var held_v: float = p.horizontal_speed()
	keys.erase(KEY_SHIFT)
	steps(c, 40)
	check.call(absf(held_v - SPRINT) < 0.05 and absf(p.horizontal_speed() - WALK) < 0.05, "hold mode: Shift held sprints (%.2f), released walks (%.2f)" % [held_v, p.horizontal_speed()])
	keys.erase(KEY_W)
	T.sprint_toggle = true
	steps(c, 40)

	# ---- slide -------------------------------------------------------------------------
	# Walk speed is below slide_min_speed: Ctrl crouches. From a sprint it slides.
	place(c, Vector3(60, 0, 62), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true
	steps(c, 30)
	keys[KEY_CTRL] = true
	s.step(DT)
	check.call(p.crouching and p.state != p.Move.SLIDE, "Ctrl at walk speed (%.1f < %.0f) crouches" % [p.horizontal_speed(), T.slide_min_speed])
	keys.erase(KEY_CTRL)
	steps(c, 5)
	tap(c, keys, KEY_SHIFT)
	steps(c, 30)
	var before: float = p.horizontal_speed()
	keys[KEY_CTRL] = true
	s.step(DT)
	var at_entry: float = p.horizontal_speed()
	s.step(DT) # the boost lands the tick after entry
	check.call(p.state == p.Move.SLIDE and p.crouching and is_equal_approx(p.height(), 1.1) and at_entry < before + 0.2 and p.horizontal_speed() > minf(before + T.slide_boost, T.slide_max_speed) - 0.4, "Ctrl from a sprint: slide, crouched; boost the tick after entry %.1f -> %.1f -> %.1f" % [before, at_entry, p.horizontal_speed()])
	steps(c, 6)
	keys.erase(KEY_CTRL)
	s.step(DT)
	check.call(p.state != p.Move.SLIDE and not p.crouching, "releasing Ctrl ends the slide and stands up")
	keys.erase(KEY_W)
	steps(c, 40)
	# Slide jump [study]: from a boosted slide after 0.24 s (or below 350 hu/s)
	# it keeps the slide's speed; earlier and faster it is a deadslide.
	for early in [false, true]:
		place(c, Vector3(60, 0, 62), 0.0)
		await tree.physics_frame
		keys[KEY_W] = true
		tap(c, keys, KEY_SHIFT)
		steps(c, 30)
		keys[KEY_CTRL] = true
		steps(c, 3 if early else 16)
		var slide_v: float = p.horizontal_speed()
		keys.erase(KEY_W)
		tap(c, keys, KEY_SPACE)
		keys.erase(KEY_CTRL)
		steps(c, 2)
		if early:
			check.call(p.state == p.Move.AIR and p.deadslides == 1 and p.slide_jumps == 0 and p.horizontal_speed() <= SPRINT + 0.05, "deadslide: jumping 0.05 s into the slide at %.1f m/s (> 8.89) keeps only sprint speed (%.2f)" % [slide_v, p.horizontal_speed()])
		else:
			check.call(p.state == p.Move.AIR and p.velocity.y > 0.0 and p.slide_jumps == 1 and p.horizontal_speed() >= slide_v - 0.05, "slide jump after 0.27 s: airborne at the slide speed (%.2f vs %.2f)" % [p.horizontal_speed(), slide_v])
		land(c)
	# No fixed slide lifetime: Ctrl held, it ends only once speed drops below crouch speed.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true
	tap(c, keys, KEY_SHIFT)
	steps(c, 30)
	keys.erase(KEY_W)
	keys[KEY_CTRL] = true
	s.step(DT)
	var slide_ticks := 0
	while p.state == p.Move.SLIDE and slide_ticks < 600:
		s.step(DT)
		slide_ticks += 1
	check.call(slide_ticks * DT > 0.8 and p.horizontal_speed() < CROUCH + 0.1 and p.crouching, "no slide lifetime: lasted %.2f s, ended at %.2f m/s (below crouch %.2f); Ctrl held -> crouch" % [slide_ticks * DT, p.horizontal_speed(), CROUCH])
	keys.erase(KEY_CTRL)
	steps(c, 30)
	# Landing at speed with Ctrl held slides (boosted); a second slide inside the cooldown gets none.
	# A small drop (falls slower than 200 hu/s) with Ctrl held is a crouch, not a slide.
	await air_at(c, tree, Vector3(60, 0.3, 62), 0.0, Vector3(0, 0, -4.0))
	keys[KEY_CTRL] = true
	for i in 30: s.step(DT)
	check.call(p.crouching and p.state != p.Move.SLIDE, "landing slowly (fall < %.2f m/s) with Ctrl held: crouch, no slide" % T.slide_land_min_fall)
	keys.erase(KEY_CTRL)
	steps(c, 10)
	# A real drop at 4 m/s across (below the ground entry, above the landing entry) slides.
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
	s.step(DT)
	check.call(slid_on_landing and p.horizontal_speed() > 4.0 + T.slide_boost - 0.5, "landing entry: falling fast at 4 m/s across with Ctrl held -> boosted slide (%.2f m/s)" % p.horizontal_speed())
	keys.erase(KEY_CTRL)
	steps(c, 3)
	keys[KEY_W] = true
	tap(c, keys, KEY_SHIFT)
	steps(c, 20)
	var v_before: float = p.horizontal_speed()
	keys[KEY_CTRL] = true
	steps(c, 2) # entry, then the tick a boost would land
	check.call(p.state == p.Move.SLIDE and p.horizontal_speed() <= v_before + 0.05, "a slide within %.0f s of the last boost gets none (%.2f -> %.2f)" % [T.slide_boost_cooldown_s, v_before, p.horizontal_speed()])
	keys.erase(KEY_CTRL); keys.erase(KEY_W)
	steps(c, 40)
	# Every entry restarts the cooldown, boosted or not [study]: slides at 0 s
	# (boost), 1 s (none) and 2.5 s (none: only 1.5 s after the last entry).
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true
	tap(c, keys, KEY_SHIFT)
	steps(c, 30)
	var gains := []
	var t_start: float = s.run.time
	for at in [0.0, 1.0, 2.5]:
		while s.run.time - t_start < at:
			s.step(DT)
			if p.state != p.Move.SLIDE and not p.sprint_on and p.is_on_floor() and not keys.has(KEY_CTRL): tap(c, keys, KEY_SHIFT)
		var vb: float = p.horizontal_speed()
		keys[KEY_CTRL] = true
		steps(c, 2)
		gains.append(p.horizontal_speed() - vb)
		keys.erase(KEY_CTRL)
		s.step(DT)
	keys.erase(KEY_W)
	check.call(gains[0] > 2.0 and gains[1] < 0.1 and gains[2] < 0.1, "the cooldown restarts on every slide entry: boosts %.2f / %.2f / %.2f" % gains)
	steps(c, 40)

	# ---- jumps -------------------------------------------------------------------------
	place(c, Vector3(60, 0, 55), 0.0)
	await tree.physics_frame
	steps(c, 3)
	var j0: int = p.jumps
	tap(c, keys, KEY_SPACE)
	steps(c, 12)
	var vy_before: float = p.velocity.y
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 1 and p.velocity.y < vy_before, "no double jump in the base: a second press in the air does nothing")
	land(c)
	# Double jump as an ability.
	T.air_jumps_max = 1
	place(c, Vector3(60, 0, 55), 0.0)
	await tree.physics_frame
	steps(c, 3)
	j0 = p.jumps
	tap(c, keys, KEY_SPACE)
	steps(c, 12)
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 2 and absf(p.velocity.y - T.double_jump_speed) < 0.5, "double jump ability (air_jumps_max 1): up at %.1f m/s" % T.double_jump_speed)
	tap(c, keys, KEY_SPACE)
	check.call(p.jumps == j0 + 2 and p.air_jumps == 0, "only one extra jump in the air")
	land(c)
	check.call(p.air_jumps == 1, "landing restores the double jump")
	T.air_jumps_max = 0
	# Coyote time: a jump just after leaving the floor is a ground jump.
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
	check.call(absf(peaks_f[0] - T.fatigue_height) < 0.06, "jump fatigue: jumping on landing from a jump peaks at %.2f m (study 16.3 hu = %.2f)" % [peaks_f[0], T.fatigue_height])
	check.call(absf(peaks_f[50] - T.jump_height) < 0.06, "fatigue recovers: after %.2f s the jump peaks at %.2f m (study 56 hu = %.2f)" % [50 * DT + DT, peaks_f[50], T.jump_height])
	# A plain fall (no jump first) carries no fatigue.
	await air_at(c, tree, Vector3(60, 1.0, 55), 0.0, Vector3.ZERO)
	land(c)
	tap(c, keys, KEY_SPACE)
	var pk2 := 0.0
	for i in 120:
		s.step(DT)
		pk2 = maxf(pk2, p.global_position.y)
		if p.is_on_floor() and i > 3: break
	check.call(absf(pk2 - T.jump_height) < 0.06, "falling without a jump leaves no fatigue (peak %.2f)" % pk2)
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

	# ---- abilities: dash (off in the base) ------------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	p.request_dash()
	s.step(DT)
	check.call(p.dashes == 0 and p.state != p.Move.DASH, "no dash in the base (0 charges)")
	T.dash_charges = 2
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	var a: Vector3 = p.global_position
	p.request_dash()
	s.step(DT)
	steps(c, int(round(T.dash_s / DT)) - 1)
	var dashed: float = Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length()
	var expect: float = T.dash_speed * T.dash_s
	check.call(absf(dashed - expect) < 0.3 and p.global_position.z < a.z, "dash ability: %.2f m forward in %.2f s (%.2f)" % [expect, T.dash_s, dashed])
	s.step(DT)
	check.call(p.state != p.Move.DASH and p.horizontal_speed() <= WALK + 0.01, "after the dash: momentum capped at walk speed (%.2f)" % p.horizontal_speed())
	var win: float = p.health._immune_until - p.health._immune_from
	check.call(absf(win - T.dash_iframes_s) < 0.001 and "bite" in p.health._immune_kinds and not "fire" in p.health._immune_kinds, "dash grants %.1f s of bite/melee immunity, not fire" % T.dash_iframes_s)
	steps(c, 10)
	p.request_dash(); s.step(DT)
	steps(c, 14)
	check.call(p.dashes == 2 and p.dash_charges == 0, "two dashes use both charges")
	p.request_dash(); s.step(DT)
	check.call(p.dashes == 2 and p.state != p.Move.DASH, "a third dash is refused with no charges")
	steps(c, int(T.dash_recharge_s / DT) - 22)
	check.call(p.dash_charges == 1, "one charge back after %.1f s" % T.dash_recharge_s)
	steps(c, int(T.dash_recharge_s / DT) + 2)
	check.call(p.dash_charges == 2, "both charges back after %.1f s" % (2.0 * T.dash_recharge_s))
	T.dash_charges = 0
	steps(c, 30)

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
	p.velocity = Vector3(0, 0, -14.0)
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
	check.call(one < 60.0 and three > one + 15.0 and p.lurches >= 3, "lurch stack at 14 m/s: one press turns %.0f deg, three turn %.0f deg" % [one, three])
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
	# No lurch above the study's ~1150 hu/s cutoff (29 m/s).
	place(c, Vector3(20, 0, 74), -90.0)
	await tree.physics_frame
	steps(c, 2)
	p.velocity = Vector3(32.0, 0, 0)
	p.land_t = 5.0
	tap(c, keys, KEY_SPACE)
	steps(c, 2)
	var lc0: int = p.lurches
	keys[KEY_D] = true; s.step(DT); keys.erase(KEY_D)
	check.call(p.lurches == lc0, "no lurch above %.0f m/s (tap D at 32 m/s)" % T.lurch_max_speed)
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
	check.call(hd > 70.0 and hd < 135.0, "S + D lurch: toward the combined back-right direction (%.0f deg; a pure D press turns about 60 at 10 m/s) [study]" % hd)
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
	# Superglide: sprinting into a mantle, jump then crouch 1 tick apart in its last 150 ms.
	var glide := {}
	# [name, ticks into the mantle, gap (0 = same tick), sprint, slide on cooldown]
	# Ticks are counted into the PULL (the window is its last 0.15 s).
	for gap_case in [["in window, 1 tick", 12, 1, true, false], ["same tick", 12, 0, true, false], ["in window, 2 ticks", 12, 2, true, false], ["too early, 1 tick", 3, 1, true, false], ["walking", 12, 1, false, false], ["slide on cooldown", 12, 1, true, true]]:
		place(c, ledge_at, 0.0)
		await tree.physics_frame
		steps(c, 2)
		keys[KEY_W] = true
		if gap_case[3]: tap(c, keys, KEY_SHIFT) # sprint on (toggle)
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
	check.call(glide["in window, 1 tick"][0] == 1 and absf(glide["in window, 1 tick"][1] - glide_h) < 0.3, "superglide: sprint, jump + crouch 1 tick apart late in the mantle -> %.1f m/s across (%.1f of %.1f total)" % [glide["in window, 1 tick"][1], glide_h, T.superglide_speed])
	for k in ["same tick", "in window, 2 ticks", "too early, 1 tick", "walking", "slide on cooldown"]:
		check.call(glide[k][0] == 0 and glide[k][1] < glide_h - 2.0, "superglide refused (%s): %.1f m/s" % [k, glide[k][1]])

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
	for i in 150:
		s.step(DT)
		if was_climbing and p.state != p.Move.WALLCLIMB and climb_rise < 0.0: climb_rise = p.global_position.y - p.climb_y0
		was_climbing = p.state == p.Move.WALLCLIMB
		if p.is_on_floor() and p.state == p.Move.GROUND and i > 5: break
	keys.erase(KEY_W)
	check.call(p.climbs == 1 and p.end_boosts == 1 and climb_rise > 2.2 and climb_rise <= 2.54 + 0.1, "the 8 m wall: one climb, rising %.2f m to the attach offset (100 hu = 2.54), then an end boost" % climb_rise)
	steps(c, 5)

	# ---- ADS ---------------------------------------------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	check.call(absf(p.camera.fov - T.fov) < 0.5, "hip FOV %.0f" % T.fov)
	keys[MOUSE_BUTTON_RIGHT] = true
	keys[KEY_W] = true
	steps(c, 30)
	check.call(p.aiming and absf(p.camera.fov - T.ads_fov) < 1.0 and p.horizontal_speed() <= WALK * T.ads_speed_factor + 0.05, "RMB aims: FOV -> %.0f, speed x%.1f (%.2f m/s)" % [T.ads_fov, T.ads_speed_factor, p.horizontal_speed()])
	keys.erase(MOUSE_BUTTON_RIGHT); keys.erase(KEY_W)
	steps(c, 30)
	check.call(absf(p.camera.fov - T.fov) < 1.0, "releasing RMB returns the FOV")

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
