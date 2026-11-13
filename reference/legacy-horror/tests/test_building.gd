extends RefCounted
# M3 building checks: four rooms and their doors, the office reached only by
# crouching under the duct, enemy routes, furniture collision and nav
# blocking, and every loot item placed on open floor or on top of furniture.

const DT := 1.0 / 60.0
const Greybox = preload("res://scripts/world/greybox.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put_player(c: Node3D, at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)
	p.apply_look()

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	var keys := {}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	var sh: CharacterBody3D = c.enemies["shambler_1"]
	sh.reset_to(Vector3(18.0, 0, 3.0), 90.0, c.noise.last_id()) # parked in the lab, facing the wall

	# Layout: four rooms, three doors, lights in every room.
	check.call(Greybox.ROOMS.size() == 4 and c.doors.size() == 3, "four rooms and three doors")
	for id in Greybox.ROOMS:
		var r: Dictionary = Greybox.ROOMS[id]
		var lit: bool = c.lamps.any(func(l): return Greybox.room_at(l.position) == id)
		check.call(lit, "%s has a ceiling light" % id)
	check.call(Greybox.room_at(Vector3(4, 0, 7)) == "classroom_104" and Greybox.room_at(Vector3(15, 0, 3)) == "computer_lab" and Greybox.room_at(Vector3(14, 0, 8)) == "faculty_office", "room lookup by position")

	# Computer lab: closed door blocks, open door lets the player in.
	var lab_door: Node3D = c.doors["door_lab"]
	put_player(c, Vector3(10.0, 0, 3.0), -90.0) # corridor, facing east
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.0); keys.erase(KEY_W)
	check.call(c.player.global_position.x < 10.8, "closed lab door blocks (x %.2f)" % c.player.global_position.x)
	put_player(c, Vector3(10.0, 0, 3.0), -90.0)
	await tree.physics_frame
	keys[KEY_E] = true; s.step(DT); keys.erase(KEY_E); s.step(DT)
	check.call(lab_door.is_open, "E opens the lab door")
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.0); keys.erase(KEY_W)
	check.call(Greybox.room_at(c.player.global_position) == "computer_lab", "walked into the computer lab (%s)" % c.player.global_position)

	# Lab furniture is solid: walking north into a workstation stops at its edge.
	put_player(c, Vector3(15.0, 0, 2.6), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.5); keys.erase(KEY_W)
	check.call(c.player.global_position.z > 1.15, "lab desk blocks the player (z %.2f)" % c.player.global_position.z)

	# Faculty office: only by crouching under the duct, then through its door.
	put_player(c, Vector3(9.5, 0, 6.3), 180.0) # corridor north of the duct, facing south
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.2); keys.erase(KEY_W)
	check.call(c.player.global_position.z < 7.0, "standing: the duct blocks the way south (z %.2f)" % c.player.global_position.z)
	keys[KEY_CTRL] = true
	keys[KEY_W] = true; steps(c, 1.6); keys.erase(KEY_W)
	keys.erase(KEY_CTRL)
	steps(c, 0.2)
	check.call(c.player.global_position.z > 7.9 and not c.player.crouching, "crouched under the duct and stood up (z %.2f)" % c.player.global_position.z)
	put_player(c, Vector3(10.0, 0, 9.0), -90.0) # in front of the office door
	await tree.physics_frame
	keys[KEY_E] = true; s.step(DT); keys.erase(KEY_E); s.step(DT)
	await tree.physics_frame
	keys[KEY_W] = true; steps(c, 1.0); keys.erase(KEY_W)
	check.call(c.doors["door_office"].is_open and Greybox.room_at(c.player.global_position) == "faculty_office", "office door opened and entered (%s)" % c.player.global_position)

	# Enemy routes with every door open: the lab yes, the office no (the duct).
	for id in c.doors: c.doors[id].set_open(true)
	c.nav_dirty = true
	s.step(DT)
	check.call(c.nav.find_path(Vector3(9.5, 0, 5), Vector3(15, 0, 3)).ok, "standing walkers can reach the lab")
	check.call(not c.nav.find_path(Vector3(9.5, 0, 5), Vector3(14, 0, 8)).ok, "standing walkers cannot reach the office (duct)")
	check.call(c.nav.find_path(Vector3(4, 0, 7), Vector3(15, 0, 3)).ok, "classroom to lab route through two doors")

	# Furniture is in the navigation solids.
	var furn_blocked := 0
	var solid_count := 0
	for f in Greybox.FURNITURE:
		if not f[4]: continue
		solid_count += 1
		if c.nav.blocked(c.nav.cell_of(Vector3(f[1].x, 0, f[1].y))): furn_blocked += 1
	check.call(solid_count > 20 and furn_blocked == solid_count, "every solid furniture piece blocks enemy navigation (%d/%d)" % [furn_blocked, solid_count])

	# Loot sits on open floor, or on top of a solid (desk) at its surface height.
	for id in c.pickups:
		var p: Node3D = c.pickups[id]
		var at: Vector3 = p.global_position
		var inside := false
		var supported := at.y < 0.01
		for box in Greybox.solids:
			if box.size.y < 0.3 and box.position.y < 0.0: continue # the floor slab
			var over := at.x > box.position.x and at.x < box.end.x and at.z > box.position.z and at.z < box.end.z
			if not over: continue
			if absf(box.end.y - at.y) <= 0.05: supported = true
			elif at.y < box.end.y and at.y + 0.1 > box.position.y: inside = true
		check.call(supported and not inside, "%s rests on floor or furniture, not inside it (%s)" % [p.label(), at])

	s.input.key_source = saved_k
	s.restart()
	await tree.physics_frame
