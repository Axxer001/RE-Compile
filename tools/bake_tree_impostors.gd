extends SceneTree
# Bakes far-LOD impostor textures for the forest's tree kinds: each kit tree is
# rendered side-on (orthographic, transparent background, flat even lighting)
# into a PNG that dark_forest.gd draws on crossed quads beyond NEAR_END.
#   godot --path . -s res://tools/bake_tree_impostors.gd      (needs a GPU: not headless)
# Output: assets/quaternius/nature/impostors/<Kind>.png (CC0, derived from the kit).

const KIT := "res://assets/quaternius/nature/"
const OUT := "res://assets/quaternius/nature/impostors/"
const KINDS := ["Pine_5", "DeadTree_1"]
const W := 256
const H := 512

func _initialize() -> void:
	_bake.call_deferred()

func _bake() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var done := []
	for kind in KINDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(W, H)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_CLEAR_COLOR
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color.WHITE
		env.environment.ambient_light_energy = 0.9
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 20, 0)
		sun.light_energy = 0.6
		vp.add_child(sun)
		var tree: Node3D = (load(KIT + kind + ".gltf") as PackedScene).instantiate()
		vp.add_child(tree)
		var aabb := AABB()
		var first := true
		for m in tree.find_children("*", "MeshInstance3D", true, false):
			var a: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Fit the taller of height or width*2 (the texture is 1:2), base at the bottom edge.
		cam.size = maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z) * 2.0) * 1.02
		var cx := aabb.get_center()
		cam.position = Vector3(cx.x, aabb.position.y + cam.size * 0.5, cx.z + 50.0)
		vp.add_child(cam)
		cam.look_at(Vector3(cx.x, cam.position.y, cx.z))
		for i in 4: await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.save_png(OUT + kind + ".png")
		# Height of the visible tree in texture units, so the quad can be sized to match.
		done.append({"kind": kind, "tree_h": aabb.size.y, "view_h": cam.size, "view_w": cam.size * float(W) / float(H)})
		vp.queue_free()
	var f := FileAccess.open(OUT + "impostors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(done, "\t"))
	f.close()
	print("RESULT ", JSON.stringify({"suite": "bake_tree_impostors", "status": "PASS", "kinds": done.size()}))
	quit()
