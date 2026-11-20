extends SceneTree
var failures := []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL: ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.external_driver = true
	world.world_kind = "arena"
	root.add_child(world)
	await physics_frame
	await physics_frame
	await preload("res://tests/simulation/test_terrain_ready.gd").run(check, world)
	world.queue_free()
	await physics_frame
	print("RESULT ", JSON.stringify({"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
