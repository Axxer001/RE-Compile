extends RefCounted
# M6b polish: synthesised sound (rendered, audible, triggered by the right
# events), view-only camera kicks (aim untouched, decaying), enemy animation
# phase, story notes.

const DT := 1.0 / 60.0
const Sfx = preload("res://scripts/audio/sfx.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k; e.keycode = k; e.pressed = true
	return e

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var sfx: Node3D = c.sfx

	# ---- sound: every recipe rendered, audible, not clipped ------------------------
	for r in Sfx.RECIPES:
		var pk: float = sfx.peak(r)
		check.call(sfx.streams[r].data.size() == int(Sfx.RECIPES[r][0] * Sfx.RATE) * 2 and pk > 0.05 and pk <= 1.0, "sound '%s' rendered and audible (peak %.2f)" % [r, pk])
	# Events play their sounds.
	var before: int = sfx.count("footstep")
	c.player.global_position = Vector3(75, 0, 55)
	c.player.yaw = 0.0; c.player.pitch = 0.0; c.player.apply_look()
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.0); keys.erase(KEY_W)
	check.call(sfx.count("footstep") > before, "walking plays footsteps")
	before = sfx.count("footstep")
	keys[KEY_CTRL] = true; keys[KEY_W] = true; steps(c, 1.0); keys.erase(KEY_W); keys.erase(KEY_CTRL)
	check.call(sfx.count("footstep") == before, "crouch-walking is silent")
	var alarms0: int = sfx.count("alarm")
	c.noise.emit_noise(Vector3(9.5, 0, 3), 10.0, "alarm", "terminal", s.run.time)
	check.call(sfx.count("alarm") == alarms0 + 1 and sfx.played.back().pos == Vector3(9.5, 0, 3), "an alarm sounds at the terminal's position")
	steps(c, 1.0)

	# ---- camera kick: view only, decays; aim never moves ---------------------------
	var lofi: CanvasLayer = c.lofi
	lofi.kick = Vector2.ZERO
	var aim_before: Basis = c.player.camera.global_transform.basis
	c.player.health.apply(DamagePacket.new(980002, "sprite_1", "infected", 15.0, "bite"), s.run.time)
	check.call(lofi.kick.x > 0.02 and sfx.count("bite") >= 1, "a bite kicks the view and plays a sound")
	lofi.sync()
	check.call(c.player.camera.global_transform.basis.is_equal_approx(aim_before) and not lofi.camera.global_transform.basis.is_equal_approx(aim_before), "the kick moves only the drawn view, never the aim")
	for i in 30: lofi._process(DT)
	check.call(lofi.kick == Vector2.ZERO or lofi.kick.length() < 0.002, "the kick fades within 0.5 s")
	for i in 5: c.player.health.apply(DamagePacket.new(980010 + i, "sprite_1", "infected", 15.0, "bite"), s.run.time + i)
	check.call(lofi.kick.length() <= lofi.KICK_MAX + 1e-6, "kicks never exceed %.2f rad" % lofi.KICK_MAX)
	lofi.kick = Vector2.ZERO
	c.player.global_position = Vector3(75, 1.4, 55) # a 1.4 m drop
	c.player.velocity = Vector3.ZERO
	c.was_on_floor = false
	await tree.physics_frame
	var landed_kick := 0.0
	for i in 60:
		s.step(DT)
		landed_kick = minf(landed_kick, lofi.kick.x)
	check.call(landed_kick < -0.005, "a hard landing dips the view (%.3f rad)" % landed_kick)

	# ---- enemy animation: idle loops start at a random point ------------------------
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	var phases := {}
	for i in 4:
		sh.reset_to(Vector3(60, 0, 62), 0.0, c.noise.last_id())
		phases[snappedf(sh.anim.current_animation_position, 0.001)] = true
	check.call(phases.size() >= 3, "four resets give different idle phases (%d distinct)" % phases.size())

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
