extends Node
# Performance suite: real frames on the GPU at the project resolution.
#   godot --path . res://tests/performance/stress.tscn -- --out=<dir>
# Scripted traversal with actor/effect updates; excludes player simulation and input.
# Generation is recorded separately and excluded from the warmed frame sample.
# Load metrics are sampled after effects update, not merely when the pool is filled.
# 3 s warm-up + 20 s sample; p95 <= P95_BUDGET_MS.

const SUITE := "performance"
const WARM_S := 3.0
const SAMPLE_S := 20.0
const P95_BUDGET_MS := 7.7 # [Sir, 2026-11-13] real-clock frame times (was 6.9 on the smoothed delta)
var checks := 0
var failures: Array[String] = []
var out_dir := "res://"
var fixture := ""
var main: Node3D
var t := 0.0
var frames: Array[float] = []
const Forest = preload("res://scripts/world/dark_forest.gd")
const ROUTE := [0, 1, 2, 5, 4, 6, 3, 1, 0] # clearings, each hop along a path
var PATH: Array = []
var max_lit := 0
var max_shots := 0
var max_burning := 0
var actors_us := 0
var effects_us := 0
var min_shots := 1000000
var min_burning := 1000000
var full_load_frames := 0
var sample_seconds := 0.0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
		elif arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	if DisplayServer.get_name() == "headless":
		failures.append("performance suite requires a GPU display server")
		finish({})
		return
	if fixture == "hang": return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = create_world()
	main.external_driver = true
	main.fixed_map_seed = Forest.densest_seed() # the perf suite runs on a dense map [R11]
	add_child(main)
	for ci in ROUTE: PATH.append(Vector3(Forest.CLEARINGS[ci][0], 0, Forest.CLEARINGS[ci][1]))
	main.spawning = false
	# R6 cap: all 20 Blighted Sprites in play round the camp, all chasing; too
	# tough to die, so the load holds for the whole sample.
	var i := 0
	for id in main.enemies:
		var e: CharacterBody3D = main.enemies[id]
		e.reset_to(Vector3(66.0 + (i % 5) * 4.0, 0, 112.0 + (i / 5) * 3.0), 180.0)
		e.health.max_hp = 1.0e9
		e.health.reset()
		e._go(e.State.CHASE)
		i += 1
	# A Ring of Fire on the player for the whole run.
	var pl: CharacterBody3D = main.player
	main.projectiles.summon_ring(func() -> Vector3: return pl.global_position, 0.0, 1.0e6, 0.0)

# Camera glides along the path (presentation only: no physics in the loop).
# Frame times come from the real clock between frames, not `delta`: Godot's
# delta smoothing snaps delta to common refresh intervals (5.56 / 6.94 / 8.33 ms),
# which made every p95 read exactly 6.94 ms whatever the true cost [2026-11-13].
var _last_us := 0
func _process(delta: float) -> void:
	if main == null: return
	var now_us := Time.get_ticks_usec()
	var real_ms := (now_us - _last_us) / 1000.0 if _last_us > 0 else delta * 1000.0
	_last_us = now_us
	t += real_ms / 1000.0
	var seg_t := fmod(t * 0.5, float(PATH.size() - 1))
	var i := int(seg_t)
	var a: Vector3 = PATH[i]
	var b: Vector3 = PATH[i + 1]
	var pos := a.lerp(b, seg_t - i)
	var dir := (b - a).normalized()
	main.player.global_position = pos
	main.player.yaw = atan2(-dir.x, -dir.z)
	main.player.apply_look()
	main.session.run.time = t # the spells and effects read the session clock
	var u0 := Time.get_ticks_usec()
	main.actors_step(delta, t)
	var u1 := Time.get_ticks_usec()
	_keep_pool_full()
	main.effects_step(delta)
	var u2 := Time.get_ticks_usec()
	if t > WARM_S:
		actors_us += u1 - u0
		effects_us += u2 - u1
	max_shots = maxi(max_shots, main.projectiles.shots.size())
	max_lit = maxi(max_lit, main.projectiles.lit_shots().size())
	max_burning = maxi(max_burning, _burning())
	if t > WARM_S:
		frames.append(real_ms)
		sample_seconds += real_ms / 1000.0
		min_shots = mini(min_shots, main.projectiles.shots.size())
		min_burning = mini(min_burning, _burning())
		if main.projectiles.shots.size() == main.projectiles.POOL and _burning() >= 10:
			full_load_frames += 1
	if t > WARM_S + SAMPLE_S:
		set_process(false)
		report()

# Fireballs from the player's hands at the Sprites (1 damage, Burn on hit)
# until the pool holds 64 in flight.
func _keep_pool_full() -> void:
	var ids: Array = main.enemies.keys()
	var origin: Vector3 = main.player.eye_position()
	var k := 0
	while main.projectiles.shots.size() < main.projectiles.POOL:
		var e: CharacterBody3D = main.enemies[ids[(int(t * 60.0) + k) % ids.size()]]
		var dir: Vector3 = (e.global_position + Vector3(0, 1.0, 0) - origin)
		dir = dir.normalized() if dir.length() > 0.5 else Vector3.FORWARD
		dir = (dir + Vector3(randf_range(-0.3, 0.3), randf_range(-0.05, 0.2), randf_range(-0.3, 0.3))).normalized()
		main.projectiles.launch("basic", origin, dir, {"damage": 1.0, "effect": "Burn", "effect_s": 5.0, "pow": 100.0})
		k += 1

func _burning() -> int:
	var n := 0
	for id in main.enemies:
		if main.effects.has(id, "Burn", t): n += 1
	return n

func report() -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var metrics := {
		"frames": n,
		"workload": "scripted traversal with actor/effect stress (not full gameplay)",
		"generation_and_scatter_ms": main.map_ms,
		"sample_seconds": sample_seconds,
		"min_shots_after_update": min_shots,
		"min_burning": min_burning,
		"full_load_frame_fraction": float(full_load_frames) / maxf(1, n),
		"avg_ms": snappedf(sorted.reduce(func(s, v): return s + v, 0.0) / maxf(1, n), 0.01),
		"p50_ms": snappedf(sorted[int(n * 0.5)], 0.01),
		"p95_ms": snappedf(sorted[int(n * 0.95)], 0.01),
		"p99_ms": snappedf(sorted[mini(n - 1, int(n * 0.99))], 0.01),
		"resolution": str(get_viewport().get_visible_rect().size),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"enemies": main.enemies.size(),
		"max_shots": max_shots,
		"max_lit": max_lit,
		"max_burning": max_burning,
		"rings": main.projectiles.rings.size(),
		"map_seed": main.map_seed,
		"trees": main.map.trees.size(),
		"actors_ms": snappedf(actors_us / 1000.0 / maxf(1, n), 0.001),
		"effects_ms": snappedf(effects_us / 1000.0 / maxf(1, n), 0.001),
	}
	check(n > 300, "sampled enough frames (%d)" % n)
	check(main.enemies.size() == 20 and main.alive_count() == 20, "20 Blighted Sprites active (the R6 cap)")
	check(max_shots == main.projectiles.POOL and main.projectiles.rings.size() == 1 and max_burning >= 10, "the load: %d fireballs in flight (the pool), a Ring of Fire, up to %d Sprites burning" % [max_shots, max_burning])
	check(metrics.p95_ms <= P95_BUDGET_MS, "Dark Forest + 20 Sprites + 64 fireballs + ring + burns: p95 %.2f ms <= %.1f ms" % [metrics.p95_ms, P95_BUDGET_MS])
	var f := FileAccess.open(out_dir + "frametimes.csv", FileAccess.WRITE)
	if f:
		f.store_line("ms")
		for v in frames: f.store_line(str(v))
	finish(metrics)

func finish(metrics: Dictionary) -> void:
	if fixture == "missing-pass":
		get_tree().quit(0)
		return
	if fixture == "fail":
		check(false, "injected fixture failure")
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"suite": SUITE, "status": status, "checks": checks, "failures": failures, "metrics": metrics}))
	get_tree().quit(0 if failures.is_empty() else 1)

func create_world() -> Node3D:
	return load("res://scenes/main.tscn").instantiate()
