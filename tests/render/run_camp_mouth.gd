extends "res://tests/render/run_map1_edges.gd"
## Sir's picture 2 spot [2026-11-22]: just inside Pathway #0 at the camp, looking at the
## bamboo either side. Captures only.
##   godot --path . res://tests/render/camp_mouth.tscn -- --out=<dir>

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	mouth.call_deferred(main)

func mouth(c: Node3D) -> void:
	c.spawning = false
	c.park_enemies()
	var m = c.map1
	var pw0: Dictionary = m.pathways[0]
	for a in [0.5, 2.0, 4.0]:
		var at: Vector3 = m.path_point(pw0.pts, a)
		for yaw in [-60.0, -20.0, 20.0, 60.0, 180.0]:
			for pitch in [-25.0, 0.0]:
				await view(c, at, yaw, pitch, "mouth-a%.1f-y%d-p%d.png" % [a, int(yaw), int(pitch)])
	get_tree().quit()
