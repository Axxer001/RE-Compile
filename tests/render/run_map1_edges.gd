extends "res://tests/render/run_render.gd"
## Map 1's visibility-driven areas [docs/plan-map1-visibility.md]: captures only (no
## verdicts) of each state: the camp, a pathway, the closed first field, the fight's
## blackout, the fight, the closed field with its exits, and an exit pathway.
##   godot --path . res://tests/render/map1_edges.tscn -- --out=<dir>

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	edges.call_deferred(main)

func view(c: Node3D, at: Vector3, yaw: float, pitch: float, name: String) -> void:
	place(c, at, yaw, pitch)
	c._map1_step(0.0, c.session.run.time)
	for i in 4: await frame()
	print("EDGES %s: %s, visibility %.1f m" % [name, c.rules.phase, c.map1.vis_now])
	shot(name)

## Game time passes for the map and the rules (the player stays put).
func steps(c: Node3D, seconds: float) -> void:
	for i in int(seconds * 60.0):
		c._map1_step(1.0 / 60.0, c.session.run.time)
		c.session.run.time += 1.0 / 60.0
	await frame()

func edges(c: Node3D) -> void:
	c.spawning = false
	c.park_enemies()
	c.pcombat.rig.visible = false
	var m = c.map1
	await view(c, c.spawn.at, 0.0, 0.0, "vis-1-camp.png")
	var pw0: Dictionary = m.pathways[0]
	await view(c, m.path_point(pw0.pts, 10.0), 0.0, 0.0, "vis-2-pathway.png")
	place(c, m.path_point(pw0.pts, m.UNLOAD_M + 1.0), 0.0, 0.0)
	await steps(c, 0.1)
	var ch: Dictionary = m.next_chunk
	var e: Vector3 = Vector3(ch.entry.x, 0, ch.entry.y)
	await view(c, ch.centre + e * (m.HALF - 1.5), 180.0 if ch.entry.y < 0 else 0.0, 0.0, "vis-3-field-entering.png")
	await view(c, ch.centre + e * (m.HALF - 3.5), 180.0 if ch.entry.y < 0 else 0.0, -2.0, "vis-4-field-closed.png")
	await view(c, ch.centre, 90.0, -2.0, "vis-5-field-closed-side.png")
	place(c, ch.centre + e * (m.HALF - 4.0), 0.0, 0.0)
	await steps(c, 2.0)
	shot("vis-6-blackout-fading.png")
	print("EDGES blackout: %s, visibility %.1f m" % [c.rules.phase, m.vis_now])
	await steps(c, 1.3)
	shot("vis-7-blackout-swapped.png")
	print("EDGES swapped: %s, visibility %.1f m" % [c.rules.phase, m.vis_now])
	await steps(c, 2.0)
	await view(c, m.chunk.centre, 0.0, -2.0, "vis-8-combat.png")
	# End the fight: the objective met, the field clear.
	c.rules.objective.met = true
	await steps(c, 3.4)
	shot("vis-9-ending-swapped.png")
	await steps(c, 2.0)
	var tc: Vector3 = m.chunk.centre + Vector3(m.chunk.tile.x * m.CHUNK, 0, m.chunk.tile.y * m.CHUNK)
	var exits: Array = m.pathways.filter(func(q): return q.get("exit", false))
	print("EDGES exits: %s" % str(exits.map(func(q): return q.dir)))
	var d0: Vector2i = exits[0].dir
	var face := rad_to_deg(atan2(-float(d0.x), -float(d0.y)))
	await view(c, tc, face, -2.0, "vis-10-closed-exit-ahead.png")
	await view(c, tc + Vector3(d0.x, 0, d0.y) * 20.0, face, -2.0, "vis-11-closed-exit-near.png")
	await view(c, m.path_point(exits[0].pts, 1.5), face, 0.0, "vis-12-exit-entering.png")
	await view(c, m.path_point(exits[0].pts, 12.0), face + 180.0, 0.0, "vis-13-exit-looking-back.png")
	print("EDGES done")
	get_tree().quit()
