extends RefCounted
# Sir's R13 (handoff §10), on the arena's 2 m ledge (x 90-94, z 37-43, south
# face at z 43): a ledge hang lasts until input; W climbs, A/D shimmy and stop
# at the ledge's end (the hands follow), S does nothing; jump is the mantle
# hop; Shift superglides at 15 m/s (+2 up) toward the held direction, forward
# with none, with no dash charge spent, no cooldown and no i-frames.

const DT := 1.0 / 60.0
const TOP := 2.0
const LEDGE_X := [90.0, 94.0]

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# Jump the player up the south face: it grabs and (with no keys) hangs.
static func hang(c: Node3D, tree: SceneTree, keys: Dictionary, x := 92.0, ticks := 45) -> bool:
	var p: CharacterBody3D = c.player
	keys.clear()
	p.global_position = Vector3(x, 0.6, 43.45)
	p.yaw = 0.0 # facing north, the wall
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement()
	await tree.physics_frame
	c.session.step(DT)
	p.global_position = Vector3(x, 0.6, 43.45)
	p.velocity = Vector3(0, 0.01, 0)
	p.move_and_slide()
	p.global_position = Vector3(x, 0.6, 43.45)
	p.velocity = Vector3(0, 6.0, -0.6)
	p.state = p.Move.AIR
	p.since_floor = 1.0
	p.lurch_t = INF
	p.land_t = 5.0
	steps(c, ticks)
	return p.state == p.Move.MANTLE and String(p.mantle.get("phase", "")) == "hang"

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var p: CharacterBody3D = c.player
	var T: Resource = p.tuning
	var keys := {}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)

	check.call(T.ledge_glide_speed == 15.0 and T.ledge_glide_up == 2.0 and T.shimmy_speed == 2.0 and not T.apex_timed_superglide, "R13 tuning: glide 15 m/s + 2 up, shimmy 2 m/s, timed superglide off")
	# Hang until input.
	var hung: bool = await hang(c, tree, keys)
	var at0: Vector3 = p.global_position
	steps(c, 300)
	check.call(hung and p.state == p.Move.MANTLE and String(p.mantle.phase) == "hang" and p.global_position.distance_to(at0) < 0.01, "no input: still hanging after 5 s [R13]")
	keys[KEY_S] = true
	steps(c, 60)
	keys.erase(KEY_S)
	check.call(p.state == p.Move.MANTLE and p.global_position.distance_to(at0) < 0.01 and p.mantle_cancels == 0, "S does nothing: same spot, still hanging")
	keys[KEY_W] = true
	steps(c, 40)
	keys.erase(KEY_W)
	check.call(p.state != p.Move.MANTLE and absf(p.global_position.y - TOP) < 0.05 and p.global_position.z < 43.0, "W climbs onto the ledge (y %.2f)" % p.global_position.y)

	# Shimmy: D right (east, facing north) to the ledge's end, the hands with it; A back left.
	await hang(c, tree, keys)
	var x0: float = p.global_position.x
	keys[KEY_D] = true
	steps(c, 30)
	var x_half: float = p.global_position.x
	var hand: Dictionary = p.hand_contact()
	steps(c, 120)
	var x_end: float = p.global_position.x
	steps(c, 60)
	keys.erase(KEY_D)
	check.call(absf(x_half - x0 - 1.0) < 0.1 and absf(float(hand.point.x) - x_half) < 0.05, "D shimmies right at 2 m/s (%.2f m in 0.5 s); the ledge hands follow" % (x_half - x0))
	check.call(x_end > LEDGE_X[1] - 0.6 and x_end <= LEDGE_X[1] + 0.35 and absf(p.global_position.x - x_end) < 0.01 and p.state == p.Move.MANTLE, "it stops at the ledge's end (x %.2f) and keeps hanging" % x_end)
	keys[KEY_A] = true
	steps(c, 30)
	keys.erase(KEY_A)
	check.call(p.global_position.x < x_end - 0.9 and p.state == p.Move.MANTLE, "A shimmies back left")

	# Jump from the hang: the mantle hop, unchanged.
	await hang(c, tree, keys)
	var hops0: int = p.mantle_hops
	keys[KEY_SPACE] = true; s.step(DT); keys.erase(KEY_SPACE)
	check.call(p.mantle_hops == hops0 + 1 and p.state == p.Move.AIR and p.velocity.z > 0.5, "jump in the hang: the mantle hop")
	steps(c, 90)

	# Shift: superglides at 15 m/s toward the held direction, forward with none.
	for case in [["none", [], Vector2(0, -1)], ["D", [KEY_D], Vector2(1, 0)], ["A+W", [KEY_A, KEY_W], Vector2(-1, -1).normalized()], ["S", [KEY_S], Vector2(0, 1)]]:
		await hang(c, tree, keys)
		var charges: int = p.dash_charges
		var g0: int = p.ledge_glides
		var dash0: int = p.dashes
		for k in case[1]: keys[k] = true
		keys[KEY_SHIFT] = true
		s.step(DT)
		keys.clear()
		var v: Vector3 = p.velocity
		var dir := flat(v).normalized()
		var spd := flat(v).length()
		check.call(p.ledge_glides == g0 + 1 and p.state == p.Move.AIR and absf(spd - 15.0) < 0.8 and dir.dot(case[2]) > 0.97 and v.y > 1.0, "Shift%s: a superglide at %.1f m/s toward %s (lift %.1f) [R13]" % ["" if case[0] == "none" else " + " + case[0], spd, case[2], v.y])
		check.call(p.dash_charges == charges and p.dashes == dash0 and not p.health.immune_to("bite", s.run.time), "Shift%s on the ledge: no dash, no charge spent, no i-frames" % ("" if case[0] == "none" else " + " + case[0]))
		for i in 120:
			s.step(DT)
			if p.is_on_floor(): break
		steps(c, 5)
	# During the grab itself (before the hang), Shift glides too: no timing window.
	await hang(c, tree, keys, 92.0, 20)
	var grabbing: bool = p.state == p.Move.MANTLE and String(p.mantle.get("phase", "")) == "grab"
	keys[KEY_SHIFT] = true
	s.step(DT)
	keys.clear()
	check.call(grabbing and p.state == p.Move.AIR and absf(flat(p.velocity).length() - 15.0) < 0.8, "Shift mid-grab glides too: no timing window")
	s.input.key_source = saved_k
	s.restart()
	await tree.physics_frame
