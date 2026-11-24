extends "res://tests/render/run_map1_edges.gd"
## Where a pathway meets a closed field [Sir, 2026-11-22 bugs]: captures only, from the
## field and from the pathway, at the entrance and at an exit.
##   godot --path . res://tests/render/map1_joins.tscn -- --out=<dir>

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	joins.call_deferred(main)

func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return rad_to_deg(atan2(-d.x, -d.z))

func around(c: Node3D, mouth: Vector3, inward: Vector3, tag: String) -> void:
	var side := Vector3(-inward.z, 0, inward.x)
	for spot in [[inward * 8.0, "in8"], [inward * 4.0 + side * 9.0, "in4-left"], [inward * 4.0 - side * 9.0, "in4-right"], [inward * 14.0 + side * 16.0, "in14-wide"]]:
		var at: Vector3 = mouth + spot[0]
		await view(c, at, yaw_to(at, mouth), -4.0, "join-%s-%s.png" % [tag, spot[1]])

func joins(c: Node3D) -> void:
	c.spawning = false
	c.park_enemies()
	c.pcombat.rig.visible = false
	var m = c.map1
	var pw0: Dictionary = m.pathways[0]
	# The camp's mouth into Pathway #0, from the camp (left, ahead, right).
	for v in [[Vector3(-9, 0, 9), "camp-left"], [Vector3(0, 0, 12), "camp-ahead"], [Vector3(9, 0, 9), "camp-right"]]:
		var at: Vector3 = m.CAMP_MOUTH + v[0]
		await view(c, at, yaw_to(at, m.CAMP_MOUTH), -3.0, "join-%s.png" % v[1])
	place(c, m.path_point(pw0.pts, m.UNLOAD_M + 1.0), 0.0, 0.0)
	await steps(c, 0.1)
	# The first field's entrance, from inside the field and from the pathway.
	var ch: Dictionary = m.next_chunk
	var e := Vector3(ch.entry.x, 0, ch.entry.y)
	var mouth: Vector3 = ch.centre + e * m.HALF
	place(c, ch.centre + e * (m.HALF - 1.0), 0.0, 0.0)
	await steps(c, 0.1)
	c.rules.phase = "cooldown" # hold the field closed while the captures run
	c.rules.cooldown_left = 999.0
	c.rules.phase_t = 10.0
	await around(c, mouth, -e, "entrance")
	var end_at: Vector3 = m.path_point(pw0.pts, float(pw0.length) - 6.0)
	await view(c, end_at, yaw_to(end_at, ch.centre), -2.0, "join-entrance-from-pathway.png")
	# A fight, then an exit: from the field and from inside the exit pathway.
	c.rules.phase = "entering"
	place(c, ch.centre, 0.0, 0.0)
	await steps(c, 4.0)
	c.rules.objective.met = true
	await steps(c, 5.5)
	var ex: Dictionary = m.pathways.filter(func(q): return q.get("exit", false))[0]
	var d := Vector3(ex.dir.x, 0, ex.dir.y)
	await around(c, ex.pts[0], -d, "exit")
	var in_at: Vector3 = m.path_point(ex.pts, 6.0)
	await view(c, in_at, yaw_to(in_at, ex.pts[0]), -2.0, "join-exit-from-pathway.png")
	print("JOINS done")
	get_tree().quit()
