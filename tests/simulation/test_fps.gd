extends RefCounted
# M0 first-person controller, collision, crouch, interact and pause checks, in the arena.
# Driven through the session with synthetic keys (same path as play).

const DT := 1.0 / 60.0

static func hold(c: Node3D, keys: Dictionary, held: Array, seconds: float) -> void:
	for k in held: keys[k] = true
	for i in int(round(seconds / DT)): c.session.step(DT)
	for k in held: keys.erase(k)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	c.player.global_position = at
	c.player.velocity = Vector3.ZERO
	c.player.yaw = deg_to_rad(yaw_deg)
	c.player.pitch = 0.0
	c.player.apply_look()

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	s.restart()
	var keys := {}
	var saved: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	var p: CharacterBody3D = c.player

	# Spawn settles on the floor.
	for i in 30: s.step(DT)
	check.call(p.is_on_floor() and absf(p.global_position.y) < 0.05, "player rests on the floor (y %.3f)" % p.global_position.y)
	check.call(is_equal_approx(p.height(), 1.8) and absf(p.eye_position().y - 1.68) < 0.02, "standing: 1.8 m capsule, eyes at 1.68 m")

	# Run and crouch speeds (Tech Spec §2.1: run = Mov Spd 10 m/s, crouch 0.4 x run).
	var T = p.tuning
	var RUN: float = p.run_top()
	place(c, Vector3(75, 0, 55), 0.0)
	var a: Vector3 = p.global_position
	keys[KEY_W] = true
	for i in 24: s.step(DT) # 0.4 s
	var run_v: float = p.horizontal_speed()
	keys.erase(KEY_W)
	check.call(is_equal_approx(RUN, 10.0) and run_v > RUN - 0.5 and run_v <= RUN + 0.01 and flat(p.global_position - a).y < 0.0, "W runs north at ~%.0f m/s (%.2f)" % [RUN, run_v])
	for i in 30: s.step(DT)
	check.call(p.horizontal_speed() < 0.05, "releasing W stops within 0.5 s (%.2f m/s left)" % p.horizontal_speed())
	place(c, Vector3(75, 0, 55), 0.0)
	keys[KEY_CTRL] = true
	keys[KEY_W] = true
	for i in 36: s.step(DT)
	var crawl: float = p.horizontal_speed()
	keys.erase(KEY_W)
	check.call(p.crouching and p.state != p.Move.SLIDE and is_equal_approx(p.height(), 0.9) and absf(crawl - RUN * T.crouch_ratio) < 0.2, "Ctrl from a standstill crouches: 0.9 m capsule, ~%.0f m/s (%.2f)" % [RUN * T.crouch_ratio, crawl])
	keys.erase(KEY_CTRL)
	s.step(DT)
	check.call(not p.crouching and is_equal_approx(p.height(), 1.8), "releasing Ctrl stands up in the open")
	for i in 10: s.step(DT)

	# Mouse look: right turns east, pitch clamps at 89 degrees.
	place(c, Vector3(75, 0, 55), 0.0)
	p.queue_look(Vector2(90, 0))
	a = p.global_position
	hold(c, keys, [KEY_W], 0.5)
	var east := flat(p.global_position - a)
	check.call(east.x > 1.2 and absf(east.y) < 0.05, "looking 90 deg right then W walks east (%.2f, %.2f)" % [east.x, east.y])
	p.queue_look(Vector2(0, 1000))
	s.step(DT)
	check.call(is_equal_approx(rad_to_deg(p.pitch), -89.0), "pitch clamps at -89 (%.1f)" % rad_to_deg(p.pitch))
	p.queue_look(Vector2(0, -5000))
	s.step(DT)
	check.call(is_equal_approx(rad_to_deg(p.pitch), 89.0), "pitch clamps at +89")
	for i in 10: s.step(DT)

	# Walls: running into the arena's north wall stops at radius + half wall (0.2 + 0.3).
	place(c, Vector3(110, 0, 3.0), 0.0)
	hold(c, keys, [KEY_W], 1.5)
	check.call(p.global_position.z > 0.49 and p.global_position.z < 0.55, "north wall stops the player (z %.3f)" % p.global_position.z)

	# Jump: rises and lands again.
	place(c, Vector3(75, 0, 55), 0.0)
	for i in 5: s.step(DT)
	keys[KEY_SPACE] = true; s.step(DT); keys.erase(KEY_SPACE)
	var peak := 0.0
	for i in 60:
		s.step(DT)
		peak = maxf(peak, p.global_position.y)
	var apex_h: float = T.jump_speed * T.jump_speed / (2.0 * T.gravity)
	check.call(absf(peak - apex_h) < 0.06 and absf(apex_h - 1.642) < 0.01 and p.is_on_floor(), "jump +8.5 under gravity 22 peaks at %.2f m and lands (%.2f)" % [apex_h, peak])

	# F (interact) with nothing under the crosshair does nothing.
	place(c, Vector3(60, 0, 40), 0.0)
	for i in 3: s.step(DT)
	check.call(c.try_interact(true) == "" and c.try_interact(false) == "", "F with nothing under the crosshair does nothing")

	# Slide gap (1.25 m opening in a 0.4 m wall at z 30): standing is blocked,
	# crouching passes, standing up under it is refused.
	place(c, Vector3(60, 0, 31.9), 0.0)
	hold(c, keys, [KEY_W], 2.0)
	check.call(p.global_position.z > 30.45, "standing player cannot pass the 1.25 m slide gap (z %.2f)" % p.global_position.z)
	place(c, Vector3(60, 0, 31.9), 0.0)
	keys[KEY_CTRL] = true
	hold(c, keys, [KEY_W], 0.5) # crouch walk is 4 m/s
	check.call(p.global_position.z < 30.4 and p.global_position.z > 29.6, "crouching enters the slide gap (z %.2f)" % p.global_position.z)
	keys.erase(KEY_CTRL)
	s.step(DT)
	check.call(p.crouching, "cannot stand up under the gap")
	hold(c, keys, [KEY_W], 0.0)
	keys[KEY_CTRL] = true
	hold(c, keys, [KEY_W], 1.0)
	keys.erase(KEY_CTRL)
	s.step(DT)
	check.call(not p.crouching, "stands up once clear of the gap (z %.2f)" % p.global_position.z)

	# Pause freezes the clock and the body; held keys are flushed on resume.
	place(c, Vector3(75, 0, 55), 0.0)
	for i in 3: s.step(DT)
	var esc := InputEventKey.new(); esc.physical_keycode = KEY_ESCAPE; esc.keycode = KEY_ESCAPE; esc.pressed = true
	s.handle_event(esc)
	var tick0: int = s.run.tick
	a = p.global_position
	hold(c, keys, [KEY_W], 0.5)
	check.call(s.paused() and s.run.tick == tick0 and p.global_position == a, "paused: clock and body frozen")
	check.call(not s.input.look_enabled(), "mouse look disabled while paused")
	keys[KEY_W] = true
	s.handle_event(esc)
	for i in 10: s.step(DT)
	check.call(p.global_position.distance_to(a) < 0.01, "W held across pause stays suppressed")
	keys.erase(KEY_W)

	# Restart returns to spawn with fresh state.
	s.restart()
	check.call(p.global_position.distance_to(c.spawn.at) < 0.01 and p.endurance.value == p.endurance.max_value, "restart: spawn, full endurance")
	s.input.key_source = saved
