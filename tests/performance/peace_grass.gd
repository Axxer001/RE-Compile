extends Node
## A closed (peaceful) Map 1 field's frame time with the grass drawn to 25 m and to
## 40 m [docs/plan-map1-visibility.md]: measurements only, no verdicts.
##   godot --path . res://tests/performance/peace_grass.tscn

var c: Node3D

func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = true
	c.fixed_map_seed = 7
	add_child(c)
	run.call_deferred()

func sample(seconds: float) -> Dictionary:
	var times: Array = []
	var last := Time.get_ticks_usec()
	var t0 := last
	while Time.get_ticks_usec() - t0 < int(seconds * 1.0e6):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	return {"p50": times[int(times.size() * 0.5)], "p95": times[int(times.size() * 0.95)], "n": times.size()}

func run() -> void:
	c.park_enemies()
	var m = c.map1
	var ch: Dictionary = m.next_chunk
	c.player.global_position = ch.centre + Vector3(0, m.height_at(Vector2(ch.centre.x, ch.centre.z)) - ch.centre.y + 0.05, 0)
	c._map1_step(0.0, c.session.run.time)
	c.rules.phase = "cooldown"
	c.rules.cooldown_left = 999.0
	for i in 30: await RenderingServer.frame_post_draw
	var out := {}
	for reach in [25.0, 40.0, 25.0, 40.0]:
		m.set_grass_reach(reach)
		for yaw in [0.0, 90.0]:
			c.player.yaw = deg_to_rad(yaw)
			c.player.apply_look()
			for i in 20: await RenderingServer.frame_post_draw
			var r: Dictionary = await sample(4.0)
			var key := "%d m, yaw %d" % [int(reach), int(yaw)]
			out[key] = out.get(key, []) + [r]
	print("PEACE window %s, closed field, rules %s" % [get_viewport().get_visible_rect().size, c.rules.phase])
	for k in out: print("PEACE %s: p50 %s ms, p95 %s ms" % [k, str(out[k].map(func(r): return snappedf(r.p50, 0.01))), str(out[k].map(func(r): return snappedf(r.p95, 0.01)))])
	get_tree().quit()
