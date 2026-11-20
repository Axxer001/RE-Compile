extends "res://tests/performance/baseline.gd"

const VARIANTS := ["baseline", "legacy_burn_sort", "no_shadows", "no_fog", "no_tree_detail", "no_enemy_models", "no_animation", "no_burn_fx", "no_particle_draw", "no_far_trees", "no_tree_collision", "no_residents", "no_grass"]
var variant := "baseline"
var render_samples: Array = []
var measured_viewports: Array[RID] = []

func create_world() -> Node3D:
	var world := super.create_world()
	if variant == "legacy_burn_sort":
		world.set_script(LegacyBurnWorld)
		world.nav_climb = ProfileNav.new()
	return world

# Previous production sort, isolated here for same-source GPU comparisons.
class LegacyBurnWorld extends ProfileWorld:
	func _show_burning(now: float) -> void:
		var lit: Array = []
		for id in enemies:
			var e: CharacterBody3D = enemies[id]
			if e.visible and not e.health.dead and effects.has(id,"Burn",now): lit.append(e)
			else: e.set_burning(false)
		var cam := get_viewport().get_camera_3d()
		var eye: Vector3 = cam.global_position if cam else player.global_position
		if lit.size() > vfx.embers_full:
			lit.sort_custom(func(a,b): return eye.distance_squared_to(a.global_position) < eye.distance_squared_to(b.global_position))
		for i in lit.size():
			lit[i].set_burning(true,i<vfx.embers_full)
			lit[i].burn_flicker(now)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
	if variant not in VARIANTS:
		push_error("Unknown crowd profiling variant")
		get_tree().quit(2)
		return
	super._ready()
	if main == null: return
	for viewport in [get_viewport(), main.lofi.viewport]:
		var rid: RID = viewport.get_viewport_rid()
		measured_viewports.append(rid)
		RenderingServer.viewport_set_measure_render_time(rid, true)
	if variant == "no_shadows":
		for light in main.find_children("*", "Light3D", true, false): light.shadow_enabled = false
	if variant == "no_fog":
		for world in main.find_children("*", "WorldEnvironment", true, false):
			world.environment.fog_enabled = false
			world.environment.volumetric_fog_enabled = false
	if variant == "no_tree_detail":
		main.find_child("KitTrees",true,false).visible = false
		for geometry in main.find_child("FarTrees",true,false).get_children(): geometry.visibility_range_begin = 0.0
	if variant == "no_far_trees": main.find_child("FarTrees",true,false).hide()
	if variant == "no_tree_collision": main.find_child("TreeColliders",true,false).free()
	if variant == "no_grass": main.find_child("GrassField",true,false).hide()
	if variant == "no_residents":
		for enemy in main.enemies.values(): main._to_reserve(enemy)
		check(scenario == "traversal" and not residents and main.alive_count() == 0,"resident-free traversal control")
	if variant == "no_enemy_models":
		for enemy in main.enemies.values(): enemy.model.visible = false
	if variant == "no_animation":
		for enemy in main.enemies.values(): enemy.anim.active = false
	if variant == "no_burn_fx": main.vfx.embers_full = 0
	if variant == "no_particle_draw":
		for particle in main.find_children("*", "GPUParticles3D", true, false): particle.layers = 0
		get_tree().node_added.connect(func(node):
			if node is GPUParticles3D: node.layers = 0)

func _process(delta: float) -> void:
	if warmed and is_processing():
		var cpu := RenderingServer.get_frame_setup_time_cpu()
		var gpu := 0.0
		for rid in measured_viewports:
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		render_samples.append([cpu, gpu, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	super._process(delta)

func _report() -> void:
	if variant == "no_residents":
		check(main.enemies.values().all(func(e): return e.reserve and e.dormant and not e.anim.active),"resident-free control keeps all actors and animations asleep")
	check(not render_samples.is_empty(), "render samples collected")
	var report := {"variant":variant, "samples":render_samples.size(),
		"notes":"Render CPU sums both viewports plus frame setup; GPU sums both viewports. Physics monitor includes engine work and scripts; timings overlap and must not be added. Particle draw suppression leaves particle simulation active."}
	var names := ["render_cpu_ms", "gpu_ms", "physics_frame_ms", "draw_calls", "primitives"]
	for i in names.size():
		var values: Array = render_samples.map(func(row): return row[i])
		values.sort()
		report[names[i]] = {"mean":_mean(values), "p95":values[int(values.size()*0.95)] if not values.is_empty() else 0.0}
	check(float(report.gpu_ms.mean) > 0.0,"GPU timing is available")
	var f := FileAccess.open(out_dir+"render-profile.json",FileAccess.WRITE)
	check(f != null,"render profile saved")
	if f: f.store_string(JSON.stringify(report,"  ")); f.close()
	super._report()
