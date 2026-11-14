extends "res://tests/performance/stress.gd"
# Controlled baseline: normal fixed-step session, scripted steering, no saved profile writes.
#   godot --path . res://tests/performance/baseline.tscn -- --scenario=<generation|traversal|combat|overload> --out=<dir>
# Validity (status PASS) means the intended workload happened and the evidence was
# written; it does NOT mean the frame budget was met: that is reported separately
# as metrics.performance = {p95_budget_ms, p95_ms, within_budget}.
# Frame samples are kept in chronological order (frametimes.csv); percentiles use a
# sorted copy. Stage timers (main.costs, pcombat.prof) are reset when the warm-up
# ends, so they cover the same window as the frame sample.
# combat   = 20 live enemies, the player holding LMB (normal Atk Spd schedule), immune,
#            one persistent zero-damage Ring of Fire (from stress.gd).
# overload = combat plus refilling the 64-projectile pool every tick: an artificial
#            saturation test, never a stand-in for normal combat.
var scenario := "traversal"
var elapsed := 0.0
var previous_us := 0
var simulation_us := 0
var ticks := 0
var waypoint := 1
var distance := 0.0
var peak_memory := 0
var generation := {}
var warmed := false
var casts_at_warm := 0
var specials_at_warm := 0
var shots_before := []  # per sampled tick: live projectiles before the session step
var shots_after := []   # ... and after it
var visuals_at_warm := [0, 0]
var sim_ticks_at_warm := 0
const Sprite = preload("res://scripts/actors/blighted_sprite.gd")

# The profiling copy of main.simulate must match the production method (less its
# timing lines), or the stage split would time a different game.
static func simulate_in_sync() -> bool:
	var prod := _body(FileAccess.get_file_as_string("res://scripts/main.gd"), "func simulate(intent: Dictionary, delta: float) -> void:", false)
	var copy := _body(FileAccess.get_file_as_string("res://tests/performance/baseline.gd"), "	func simulate(intent: Dictionary, delta: float) -> void:", true)
	return not prod.is_empty() and prod == copy

static func _body(src: String, header: String, nested: bool) -> Array:
	var i := src.rfind(header) # the last match: the method itself, not this check's own text
	if i < 0: return []
	var out := []
	for line in src.substr(i + header.length()).split("
").slice(1):
		var ln: String = line.trim_prefix("	") if nested else line
		if not ln.begins_with("	"): break
		ln = ln.strip_edges()
		var c := ln.find(" #")
		if c >= 0: ln = ln.substr(0, c).strip_edges()
		if ln.is_empty() or "costs." in ln or "Time.get_ticks_usec" in ln or "profile_ticks" in ln: continue
		out.append(ln)
	return out

func _ready() -> void:
	seed(613)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
	if scenario not in ["generation", "traversal", "combat", "overload"]:
		push_error("Unknown benchmark scenario")
		get_tree().quit(2)
		return
	super._ready()
	if main == null: return
	check(simulate_in_sync(), "the profiling copy of main.simulate matches scripts/main.gd")
	main.player.health.max_hp = 1.0e9
	main.player.health.reset()
	main.player.health.grant_immunity(INF, ["*"])
	if scenario not in ["combat", "overload"]:
		main.park_enemies()
		main.projectiles.reset()
	if scenario == "generation":
		await _generation()
	else:
		main.session.input.key_source = func(key: int) -> bool: return key == KEY_W
		main.session.input.mouse_source = func(button: int) -> bool: return scenario in ["combat", "overload"] and button == MOUSE_BUTTON_LEFT

# Warm rebuild of an already initialised world (assets loaded), stage by stage,
# through the first drawn frame. cold_launch_ms is the process uptime when the
# world first drew (engine start, asset loads, first build): a separate number.
func _generation() -> void:
	var cold_launch_ms := Time.get_ticks_msec()
	await RenderingServer.frame_post_draw
	cold_launch_ms = Time.get_ticks_msec()
	var begin := Time.get_ticks_usec()
	var layout := Forest.generate(60)
	var drawn := Time.get_ticks_usec()
	check(not layout.is_empty(), "generation produced a layout")
	main.map = layout
	main.static_solids = main._fixed_solids + Forest.scatter(main._forest_node, layout)
	var built := Time.get_ticks_usec()
	var all: Array = main.level_solids()
	main.nav.rebuild(all)
	var stood := Time.get_ticks_usec()
	main.nav_climb.rebuild(all.filter(func(b: AABB) -> bool: return b.end.y > Sprite.CLIMB_MAX + 0.01)) # as main._rebuild_navs
	var navigated := Time.get_ticks_usec()
	await get_tree().physics_frame
	var physics := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var first_draw := Time.get_ticks_usec()
	generation = {"scenario": "generation", "kind": "warm rebuild (assets already loaded)", "data_ms": (drawn-begin)/1000.0,
		"scatter_ms": (built-drawn)/1000.0, "nav_standing_ms": (stood-built)/1000.0, "nav_climbing_ms": (navigated-stood)/1000.0,
		"cpu_total_ms": (navigated-begin)/1000.0, "physics_frame_ms": (physics-navigated)/1000.0,
		"through_first_draw_ms": (first_draw-begin)/1000.0, "cold_launch_to_first_world_draw_ms": cold_launch_ms,
		"trees": layout.trees.size(), "settings": _settings()}
	finish(generation)

func _physics_process(delta: float) -> void:
	if main == null or scenario == "generation": return
	var at: Vector3 = main.player.global_position
	var target: Vector3 = PATH[waypoint]
	var dir := target - at
	dir.y = 0.0
	if dir.length() < 2.0: waypoint = (waypoint + 1) % PATH.size()
	main.player.yaw = atan2(-dir.x, -dir.z)
	main.player.apply_look()
	var start := Time.get_ticks_usec()
	if scenario == "overload": _keep_pool_full()
	main.session.input._suppressed.clear() # scripted input must survive window focus changes
	var before: int = main.projectiles.shots.size()
	main.session.step(delta)
	if warmed:
		simulation_us += Time.get_ticks_usec() - start
		ticks += 1
		distance += at.distance_to(main.player.global_position)
		shots_before.append(before)
		shots_after.append(main.projectiles.shots.size())

# The warm-up ends: every counter and stage timer starts from here.
func _start_sample() -> void:
	warmed = true
	casts_at_warm = main.pcombat.basic_casts
	specials_at_warm = main.pcombat.special_casts
	visuals_at_warm = [main.projectiles.visuals_reused, main.projectiles.visuals_created]
	for k in main.costs: main.costs[k] = 0
	main.profile_ticks = 0
	main.pcombat.prof = {}
	sim_ticks_at_warm = 0

func _process(_delta: float) -> void:
	if main == null or scenario == "generation": return
	var now := Time.get_ticks_usec()
	if previous_us == 0:
		previous_us = now
		return
	var ms := (now - previous_us) / 1000.0
	previous_us = now
	elapsed += ms / 1000.0
	t = main.session.run.time
	if elapsed > WARM_S and not warmed: _start_sample()
	if warmed:
		frames.append(ms)
		min_shots = mini(min_shots, main.projectiles.shots.size())
		min_burning = mini(min_burning, _burning())
		peak_memory = maxi(peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	if elapsed >= WARM_S + SAMPLE_S:
		set_process(false)
		set_physics_process(false)
		_report()

func _report() -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var casts: int = main.pcombat.basic_casts - casts_at_warm
	var sample_s := float(ticks) / float(Engine.physics_ticks_per_second)
	var expect_casts: float = sample_s * float(main.session.stats.value("atk_spd", t))
	var combat := scenario in ["combat", "overload"]
	check(n > 300, "enough frames sampled (%d)" % n)
	check(ticks > 100, "the simulation ran (%d ticks)" % ticks)
	check(not main.player.health.dead, "the player is alive at the end")
	check(main.session.input.context == main.session.input.Context.GAMEPLAY, "input stayed in gameplay")
	if scenario == "traversal": check(distance > 10.0 and casts == 0, "traversal: moved %.1f m, no casts" % distance)
	if combat:
		check(main.alive_count() == 20, "20 live enemies (%d)" % main.alive_count())
		check(casts >= int(expect_casts * 0.8), "normal firing happened: %d casts in %.1f s (Atk Spd schedule ~%.0f)" % [casts, sample_s, expect_casts])
	var avg: float = sorted.reduce(func(a, b): return a + b, 0.0) / maxf(1.0, n)
	var p95: float = sorted[int(n * 0.95)] if n > 0 else INF
	var p99: float = sorted[mini(n - 1, int(n * 0.99))] if n > 0 else INF
	var prof: Dictionary = main.pcombat.prof if main.pcombat.prof != null else {}
	var metrics := {"scenario": scenario, "valid_means": "workload happened + evidence written (not the budget)",
		"performance": {"p95_budget_ms": P95_BUDGET_MS, "p95_ms": p95, "within_budget": p95 <= P95_BUDGET_MS},
		"frames": n, "sample_s_wall": elapsed - WARM_S, "avg_ms": avg, "p50_ms": sorted[int(n * 0.5)] if n > 0 else INF, "p95_ms": p95, "p99_ms": p99, "max_ms": sorted[n - 1] if n > 0 else INF,
		"sim_ticks": ticks, "simulation_ms_per_tick": simulation_us / 1000.0 / maxi(1, ticks),
		"stage_us_warmed": main.costs, "stage_ticks": main.profile_ticks,
		"casting_substages_us": prof,
		"workload": {"basic_casts": casts, "special_casts": main.pcombat.special_casts - specials_at_warm, "expected_casts": expect_casts,
			"live_enemies_end": main.alive_count(), "projectiles_before_mean": _mean(shots_before), "projectiles_after_mean": _mean(shots_after),
			"projectiles_after_max": shots_after.max() if not shots_after.is_empty() else 0,
			"visuals_reused": main.projectiles.visuals_reused - visuals_at_warm[0], "visuals_created": main.projectiles.visuals_created - visuals_at_warm[1],
			"distance_m": distance, "player_dead": main.player.health.dead, "min_burning": min_burning},
		"memory": {"peak_static_bytes": peak_memory, "definition": "Performance.MEMORY_STATIC peak over the sample (engine static allocations, not process RSS)"},
		"settings": _settings()}
	var file := FileAccess.open(out_dir + "frametimes.csv", FileAccess.WRITE)
	check(file != null, "frame samples saved to %sframetimes.csv" % out_dir)
	if file:
		file.store_line("index,ms_chronological")
		for i in frames.size(): file.store_line("%d,%.4f" % [i, frames[i]])
		file.close()
	var mf := FileAccess.open(out_dir + "metrics.json", FileAccess.WRITE)
	check(mf != null, "metrics saved")
	if mf:
		mf.store_string(JSON.stringify(metrics, "  "))
		mf.close()
	finish(metrics)

static func _mean(a: Array) -> float:
	return a.reduce(func(x, y): return x + y, 0.0) / maxf(1.0, a.size()) if not a.is_empty() else 0.0

func _settings() -> Dictionary:
	var lofi: CanvasLayer = main.lofi
	return {"engine": Engine.get_version_info().string, "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": OS.get_video_adapter_driver_info(), "api": RenderingServer.get_video_adapter_api_version(),
		"cpu": OS.get_processor_name(), "cpu_threads": OS.get_processor_count(),
		"viewport": str(get_viewport().get_visible_rect().size), "window": str(DisplayServer.window_get_size()),
		"internal_3d": str(lofi.viewport.size) if lofi and lofi.viewport else "", "screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "physics_hz": Engine.physics_ticks_per_second,
		"window_mode": DisplayServer.window_get_mode(), "focused": DisplayServer.window_is_focused(),
		"map_seed": main.map_seed, "grass_distance_m": main.session.settings.grass_distance, "warm_s": WARM_S, "sample_s": SAMPLE_S}

func create_world() -> Node3D:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.set_script(ProfileWorld)
	return world

# Mirrors scripts/main.gd simulate() (2026-11-14) only to split its timing; keep
# the two in step when main.simulate changes (test_perf_harness checks the source).
class ProfileWorld extends "res://scripts/main.gd":
	var costs := {"player": 0, "actors": 0, "effects": 0, "publish": 0, "movement": 0, "casting": 0}
	var profile_ticks := 0
	func simulate(intent: Dictionary, delta: float) -> void:
		var begin := Time.get_ticks_usec()
		if player.health.dead: return
		player.carry_factor = pcombat.combat.movement_factor()
		player.stats = session.stats
		intent = frozen_intent(intent)
		var part := Time.get_ticks_usec()
		player.simulate(intent, delta, session.run.time)
		costs.movement += Time.get_ticks_usec() - part
		hold_for_charge()
		if training: training.check_portals(session.run.time)
		_landing_kick()
		part = Time.get_ticks_usec()
		pcombat.simulate(intent, delta, session.run.time)
		costs.casting += Time.get_ticks_usec() - part
		footsteps(delta)
		try_interact(intent.get("interact", false))
		noise.prune(session.run.time)
		if notice_time > 0.0: notice_time -= delta
		for n in notices: n[1] -= delta
		notices = notices.filter(func(n): return n[1] > 0.0)
		costs.player += Time.get_ticks_usec() - begin
		profile_ticks += 1
	func actors_step(delta: float, now: float) -> void:
		var begin := Time.get_ticks_usec()
		super.actors_step(delta, now)
		costs.actors += Time.get_ticks_usec() - begin
	func effects_step(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super.effects_step(delta)
		costs.effects += Time.get_ticks_usec() - begin
	func publish(delta: float) -> void:
		var begin := Time.get_ticks_usec()
		super.publish(delta)
		costs.publish += Time.get_ticks_usec() - begin
