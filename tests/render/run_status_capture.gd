extends "res://tests/render/run_render.gd"
## The held book's status page (page 5) with several effects on, at the default
## gameplay window (1280 x 720) and FOV (90): captures only, no verdicts.
##   godot --path . res://tests/render/status_capture.tscn -- --out=<dir>

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	status.call_deferred(main)

func status(c: Node3D) -> void:
	c.park_enemies()
	var s = c.session
	var pc = c.pcombat
	place(c, c.spawn.at, 0.0, 0.0)
	pc.ready_at.erase("spell_2")
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time) # Cultivate (buff)
	c.concuss(s.run.time + 6.0, 0.2) # Concuss (debuff)
	c.effects.apply("player", "Burn", 8.0, s.run.time, "test", 150.0) # Burn (debuff)
	for e in ["Slow", "Scorched", "Haste"]:
		if c.effects.has_method("known") and not c.effects.known(e): continue
	pc.turn_to_page(pc.STATUS_PAGE, s.run.time)
	s.run.time += pc.TURN_S * pc.flips() + 0.01
	pc.simulate({}, 0.0, s.run.time)
	c.publish(0.0)
	for i in 6: await frame()
	var rows: Array = pc.rig.status_info().effects
	print("STATUS window=%s fov=%.0f rows=%s" % [get_viewport().get_visible_rect().size, c.player.camera.fov, str(rows.map(func(r): return "%s (%s) %.1fs" % [r.name, r.kind, r.s]))])
	shot("status-page-effects.png")
	c.effects.apply("player", "Scorched Slow", 5.0, s.run.time, "test", 0.0) # a fourth effect: the page shows two and "+2 more"
	c.publish(0.0)
	for i in 4: await frame()
	print("STATUS with a fourth: %d rows" % pc.rig.status_info().effects.size())
	shot("status-page-more.png")
	get_tree().quit()
