extends SceneTree
# Headless simulation suite. Never awaits rendering.
#   godot --headless --path . -s res://tests/simulation/run_simulation.gd
# Emits exactly one `RESULT {json}` line; status PASS only after every check ran.
# --fixture=fail|missing-pass|hang deliberately breaks the suite (harness self-test).

const SUITE := "simulation"
var checks := 0
var failures: Array[String] = []
var fixture := ""

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.world_kind = "arena" # the rule tests run in the movement arena; the forest has its own checks
	root.add_child(main)
	run.call_deferred(main)

func run(c: Node3D) -> void:
	if fixture == "hang":
		return # never quits; wrapper must report a timeout
	await physics_frame # bodies join the physics space before queries
	await physics_frame
	await preload("res://tests/simulation/test_fps.gd").run(check, c)
	await preload("res://tests/simulation/test_movement.gd").run(check, c)
	await preload("res://tests/simulation/test_arena.gd").run(check, c)
	await preload("res://tests/simulation/test_r1e.gd").run(check, c)
	preload("res://tests/simulation/test_health.gd").run(check, c)
	preload("res://tests/simulation/test_grimoire_core.gd").run(check, c)
	await preload("res://tests/simulation/test_spellcasting.gd").run(check, c)
	await preload("res://tests/simulation/test_abilities.gd").run(check, c)
	await preload("res://tests/simulation/test_grimoire.gd").run(check, c)
	await preload("res://tests/simulation/test_audio.gd").run(check, c)
	await preload("res://tests/simulation/test_chant.gd").run(check, c)
	await preload("res://tests/simulation/test_threat.gd").run(check, c)
	await preload("res://tests/simulation/test_polish.gd").run(check, c)
	preload("res://tests/simulation/test_settings.gd").run(check, c)
	await preload("res://tests/simulation/test_pause_menu.gd").run(check, c)
	await preload("res://tests/simulation/test_arms_rig.gd").run(check, c)
	await preload("res://tests/simulation/test_hud.gd").run(check, c)
	await preload("res://tests/simulation/test_r12.gd").run(check, c)
	await preload("res://tests/simulation/test_r13.gd").run(check, c)
	await preload("res://tests/simulation/test_r14.gd").run(check, c)
	await preload("res://tests/simulation/test_r15.gd").run(check, c)
	await preload("res://tests/simulation/test_book_card.gd").run(check, c)
	await preload("res://tests/simulation/test_vfx.gd").run(check, c)
	await preload("res://tests/simulation/test_player_body.gd").run(check, c)
	preload("res://tests/simulation/test_target_along.gd").run(check, c)
	await preload("res://tests/simulation/test_spells.gd").run(check, c)
	# The Dark Forest: the game world, built as the game builds it.
	c.queue_free()
	await physics_frame
	var forest: Node3D = load("res://scenes/main.tscn").instantiate()
	forest.external_driver = true
	root.add_child(forest)
	await physics_frame
	await physics_frame
	await preload("res://tests/simulation/test_forest.gd").run(check, forest)
	await preload("res://tests/simulation/test_training.gd").run(check, forest)
	await preload("res://tests/simulation/test_graphics.gd").run(check, forest)
	if fixture == "fail":
		check(false, "injected fixture failure")
	if fixture == "missing-pass":
		quit(0)
		return
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"suite": SUITE, "status": status, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
