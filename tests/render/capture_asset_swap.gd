extends Node
# Live capture for the Dark Forest asset swap [2026-11-24]: the camp, the bamboo
# pathway, the combat field and each approved hostile mid-attack, from the real
# main scene with the real gameplay controllers. GPU renderer required.
#   godot --path . res://tests/render/capture_asset_swap.tscn -- --out=<dir>
# Prints the resolved project path and each actor's model resource, then one RESULT line.

var out_dir := "res://"
var captures: Array = []
var info := {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	if DisplayServer.get_name() == "headless":
		push_error("capture requires a GPU display server")
		get_tree().quit(1)
		return
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	run.call_deferred(main)

static func field(c: Node3D) -> Vector3:
	var ch: Dictionary = c.map1.chunk if not c.map1.chunk.is_empty() else c.map1.next_chunk
	return ch.centre

func frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir + name)
	captures.append(name)

func place(c: Node3D, at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	if c.map1 and not (c.training and c.training.active) and at.distance_to(c.training.ORIGIN) > 400.0:
		at.y = c.map1.height_at(Vector2(at.x, at.z))
	c.player.global_position = at
	c.player.velocity = Vector3.ZERO
	c.player.yaw = deg_to_rad(yaw_deg)
	c.player.pitch = deg_to_rad(pitch_deg)
	c.player.apply_look()
	c.publish(0.0)
	var gf: Node3D = c.find_child("GrassField", true, false)
	if gf: gf.update(999)

func describe(label: String, actor: Node) -> void:
	var paths: Array = []
	for n in actor.model.find_children("*", "MeshInstance3D", true, false):
		paths.append(str(n.mesh.resource_path) if n.mesh else "")
	info[label] = {"model": actor.model.scene_file_path, "meshes": paths,
		"anim": actor.anim.name if actor.anim else "", "clips": actor.anim.get_animation_list() if actor.anim else []}

func run(c: Node3D) -> void:
	c.art.set_grain(0.0)
	await frame()
	await frame()
	# The camp, the pathway and the combat field, at the suite's own viewpoints.
	place(c, c.spawn.at, 0.0, -4.0)
	c._map1_step(0.0, c.session.run.time)
	for i in 6: await frame()
	shot("swap-camp.png")
	var pw0: Dictionary = c.map1.pathways[0]
	place(c, c.map1.path_point(pw0.pts, 12.0), 0.0, 0.0)
	c._map1_step(0.0, c.session.run.time)
	for i in 6: await frame()
	shot("swap-bamboo-pathway.png")
	place(c, field(c) + Vector3(0, 0, 20), 0.0, 2.0)
	c._map1_step(0.0, c.session.run.time)
	for i in 6: await frame()
	shot("swap-combat-field.png")

	var sprites: Array = c.enemies.values().filter(func(e): return e.kind == "sprite")
	var ghouls: Array = c.enemies.values().filter(func(e): return e.kind == "ghoul")
	var morti: Array = c.enemies.values().filter(func(e): return e.kind == "mortus")
	if sprites.is_empty() or ghouls.is_empty() or morti.is_empty():
		push_error("the forest did not spawn all three kinds")
		get_tree().quit(1)
		return
	c.park_enemies([sprites[0].enemy_id, ghouls[0].enemy_id, morti[0].enemy_id])
	var at: Vector3 = field(c) + Vector3(0, 0, 6)
	place(c, at, 0.0, -1.5)
	c._map1_step(0.0, c.session.run.time)
	for e in [sprites[0], ghouls[0], morti[0]]:
		e.inert = true
		e.visible = true
		e.get_node("Shape").disabled = false

	# Hostiles stand on the ground at these spots (the chunk's own height).
	var ground := func(p: Vector3) -> Vector3:
		return Vector3(p.x, c.map1.height_at(Vector2(p.x, p.z)), p.z)

	var s = sprites[0]
	var g = ghouls[0]
	var m = morti[0]

	# Blighted Sprite: the claw scratch (State.STRIKE = 3).
	s.reset_to(ground.call(at + Vector3(-1.1, 0, -3.4)), 180.0)
	s.inert = false
	s._go(3)
	g.visible = false
	m.visible = false
	for i in 6: await frame()
	shot("swap-sprite-strike.png")
	describe("sprite", s)
	s.inert = true
	s._go(0)

	# Forest Ghoul: bow draw (aim) then the single release (shoot + one arrow).
	s.visible = false
	g.visible = true
	m.visible = false
	g.reset_to(ground.call(at + Vector3(1.3, 0, -4.2)), 180.0)
	g.inert = true
	g.aiming = true
	g.shot_at = -100.0
	g._clock = 0.0
	for i in 8: await frame()
	shot("swap-ghoul-draw.png")
	var arrows_before: int = c.arrows.arrows.size() if "arrows" in c.arrows else 0
	g._shoot(c.player, c.session.run.time)
	g._animate()
	for i in 4: await frame()
	shot("swap-ghoul-release.png")
	info["ghoul_release_arrows"] = (c.arrows.arrows.size() if "arrows" in c.arrows else 0) - arrows_before
	describe("ghoul", g)
	g.aiming = false

	# Kostas Mortus: the charge wind-up, then the slam.
	s.visible = false
	g.visible = false
	m.visible = true
	m.reset_to(ground.call(at + Vector3(0.4, 0, -6.0)), 180.0)
	m.inert = false
	m._go(6)
	for i in 12: await frame()
	shot("swap-mortus-charge.png")
	m.charge_dir = (c.player.global_position - m.global_position).normalized()
	m.charge_left = 25.0
	m.dive_hit = false
	m._go(7)
	for i in 3: await frame()
	shot("swap-mortus-slam.png")
	describe("mortus", m)

	var status := "PASS" if captures.size() >= 7 else "FAIL"
	print("RESULT ", JSON.stringify({
		"status": status,
		"project": ProjectSettings.globalize_path("res://project.godot"),
		"seed": 7,
		"captures": captures,
		"hostiles": info,
	}))
	get_tree().quit(0 if status == "PASS" else 1)
