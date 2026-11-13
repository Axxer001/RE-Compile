extends RefCounted
# The movement arena: its size and walls, and that each movement prop does
# what it is there for (driven through the session with synthetic keys):
# slide through the 1.25 m gap, each ledge topped by a running jump (landing
# or mantle), ramps up to 45° walkable and 55° a wall, ground snap downhill, the stairs walkable (step-up) while ledges and the
# jump blocks are not, the jump course, the arena wall holds a full run.

const DT := 1.0 / 60.0
const Greybox = preload("res://scripts/world/greybox.gd")

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement()

static func tap(c: Node3D, keys: Dictionary, k: int) -> void:
	keys[k] = true; c.session.step(DT); keys.erase(k)

# Run north from `start` (W held), jump once z <= jump_z; release W on
# landing above the floor. Returns the highest floor the player stood on.
static func run_and_jump(c: Node3D, tree: SceneTree, keys: Dictionary, start: Vector3, jump_z: float) -> float:
	var p: CharacterBody3D = c.player
	place(c, start, 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	var guard := 0
	while p.global_position.z > jump_z and guard < 120:
		c.session.step(DT)
		guard += 1
	tap(c, keys, KEY_SPACE)
	var best := 0.0
	for i in 120:
		c.session.step(DT)
		if i > 3 and p.is_on_floor():
			best = maxf(best, p.global_position.y)
			if p.global_position.y > 0.5: break
	keys.erase(KEY_W)
	steps(c, 3)
	return best

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
	var p: CharacterBody3D = c.player

	# ---- the box -----------------------------------------------------------------
	check.call(Greybox.BOUNDS[1] - Greybox.BOUNDS[0] == Vector2(120, 80) and c.nav.size == Vector2i(480, 320), "arena is 120 x 80 m; the nav grid covers it at 0.25 m")
	var tall := 0
	for b in c.static_solids:
		if is_equal_approx(b.end.y, 8.0) and (b.size.x >= 119.0 or b.size.z >= 79.0): tall += 1
	check.call(tall == 4, "four 8 m perimeter walls (%d)" % tall)
	check.call(c.spawn.at == Vector3(60, 0, 40) and p.global_position.distance_to(Vector3(60, 0, 40)) < 0.05, "the player spawns in the middle")
	# Running into the east wall: stopped at radius + half wall.
	place(c, Vector3(114.0, 0, 40), -90.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 60)
	keys.erase(KEY_W)
	check.call(p.global_position.x > 119.3 and p.global_position.x < 119.55, "a full run into the arena wall stops at it (x %.2f)" % p.global_position.x)

	# ---- slide gap ------------------------------------------------------------------
	place(c, Vector3(60, 0, 38), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	steps(c, 24)
	keys.erase(KEY_W)
	keys[KEY_CTRL] = true
	var slid_through := false
	for i in 90:
		s.step(DT)
		if p.global_position.z < 29.5:
			slid_through = p.state == p.Move.SLIDE
			break
	keys.erase(KEY_CTRL)
	steps(c, 90) # the slide runs its 1.2 s, then stands up in the open
	check.call(slid_through and not p.crouching, "a slide carries through the 1.25 m gap, then stands (z %.2f)" % p.global_position.z)

	# ---- ledges (z 37-43): a running jump with W held tops each, by landing or mantling ----
	for l in Greybox.LEDGES:
		var m0: int = p.mantles
		var hl: float = await run_and_jump(c, tree, keys, Vector3(l[0], 0, 50), 45.5)
		check.call(absf(hl - float(l[1])) < 0.05, "running jump onto the %.0f m ledge (stood at %.2f m, %d mantle)" % [l[1], hl, p.mantles - m0])
	place(c, Vector3(75, 0, 55), 0.0)
	await tree.physics_frame
	steps(c, 3)

	# ---- ramps: walk up, stop on the platform; steeper than walkable is a wall ----
	for r in Greybox.RAMPS:
		if float(r[1]) > 45.6: # the spec's walkable limit, normal.y >= 0.7
			place(c, Vector3(r[0], 0, Greybox.RAMP_START_Z + 3.0), 0.0)
			await tree.physics_frame
			steps(c, 2)
			keys[KEY_W] = true
			steps(c, 90)
			keys.erase(KEY_W)
			check.call(p.global_position.y < 0.5 and p.global_position.z > Greybox.RAMP_START_Z - 0.6, "the %.0f deg ramp is too steep: a wall (y %.2f)" % [r[1], p.global_position.y])
			continue
		var top_z: float = Greybox.RAMP_START_Z - Greybox.ramp_run(r) - 1.0
		place(c, Vector3(r[0], 0, Greybox.RAMP_START_Z + 3.0), 0.0)
		await tree.physics_frame
		steps(c, 2)
		keys[KEY_W] = true
		var guard := 0
		while p.global_position.z > top_z and guard < 180:
			s.step(DT)
			guard += 1
		keys.erase(KEY_W)
		steps(c, 30)
		check.call(p.is_on_floor() and absf(p.global_position.y - float(r[2])) < 0.05, "the %.0f deg ramp is walkable up to its %.0f m platform (y %.2f)" % [r[1], r[2], p.global_position.y])
	# Ground snap: running down the 30 deg ramp never leaves the floor.
	var r30: Array = Greybox.RAMPS[0]
	place(c, Vector3(r30[0], r30[2], Greybox.RAMP_START_Z - Greybox.ramp_run(r30) - 1.0), 180.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	var airborne := 0
	for i in 90:
		s.step(DT)
		if not p.is_on_floor(): airborne += 1
		if p.global_position.z > Greybox.RAMP_START_Z + 1.0: break
	keys.erase(KEY_W)
	check.call(airborne == 0 and p.global_position.z > Greybox.RAMP_START_Z, "ground snap: running down the 30 deg ramp stays on the floor (%d airborne ticks)" % airborne)
	steps(c, 20)

	# ---- stairs: walked up by step-up; higher faces still block ----------------
	var st: Dictionary = Greybox.STAIRS
	place(c, Vector3(st.x, 0, st.start_z + 2.0), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	var climbed := 0.0
	for i in 100: # 4.7 m of approach and stairs at walk speed
		s.step(DT)
		if p.is_on_floor(): climbed = maxf(climbed, p.global_position.y)
	keys.erase(KEY_W)
	var top_step: float = st.rise * st.steps
	check.call(absf(climbed - top_step) < 0.05 and p.steps_up >= st.steps, "walking up the 0.3 m stairs reaches the top step (%.2f m, %d step-ups)" % [climbed, p.steps_up])
	steps(c, 40)
	for probe in [[Vector3(86, 0, 46), "the 1 m ledge"], [Vector3(92.5, 0, Greybox.JUMP_COURSE_Z + 3.0), "the 0.6 m jump block"]]:
		place(c, probe[0], 0.0)
		await tree.physics_frame
		steps(c, 2)
		keys[KEY_W] = true
		steps(c, 60)
		keys.erase(KEY_W)
		check.call(p.global_position.y < 0.05 and p.steps_up == 0, "walking into %s does not step up (y %.2f)" % [probe[1], p.global_position.y])
	# The jump course: one jump per block, 0.6 m apart in height.
	place(c, Vector3(82.0, 0, Greybox.JUMP_COURSE_Z), -90.0) # run-up
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	var course_top := 0.0
	for i in 400: # about 6.7 s budget at run speed
		# Jump 1.4-3 m before the next block's face (front of the capsule clears it rising).
		var next_face := INF
		for jc in Greybox.JUMP_COURSE:
			var face: float = jc[0] - Greybox.JUMP_W * 0.5
			if face > p.global_position.x + 0.3: next_face = minf(next_face, face)
		var d := next_face - p.global_position.x
		if p.is_on_floor() and d > 1.4 and d < 2.2: tap(c, keys, KEY_SPACE)
		else: s.step(DT)
		if p.is_on_floor(): course_top = maxf(course_top, p.global_position.y)
		if course_top > 2.35 or p.global_position.x > 116.0: break
	keys.erase(KEY_W)
	steps(c, 30)
	check.call(absf(course_top - 2.4) < 0.05, "the jump course can be hopped to its 2.4 m top (%.2f)" % course_top)

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
