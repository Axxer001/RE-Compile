extends SceneTree

func _initialize() -> void:
	var renderer = load("res://scripts/world/tree_chunks.gd").new()
	root.add_child(renderer)
	renderer.set_process(false)
	var data := {}
	var far := {}
	for x in 50:
		for z in 50:
			var key := Vector2i(x,z)
			data[key] = {"tree": [Transform3D.IDENTITY]}
			var instance := MeshInstance3D.new()
			root.add_child(instance)
			far[key] = [instance]
	var builder := func(parent, _kind, transforms, _name, _shadows, distance_m):
		assert(transforms == [Transform3D.IDENTITY])
		var instance := MeshInstance3D.new()
		instance.visibility_range_end = distance_m
		parent.add_child(instance)
	renderer.setup(data,far,builder,10.0,40.0,Vector2(75,134))
	assert(renderer.loaded.size() > 0 and renderer.loaded.size() < 250)
	assert(far[Vector2i(40,40)][0].visibility_range_begin == 0.0)
	renderer.refresh(Vector2(405,405))
	assert(renderer.loaded.is_empty())
	assert(far[Vector2i(7,13)][0].visibility_range_begin == 0.0)
	assert(far[Vector2i(40,40)][0].visibility_range_begin == 0.0)
	while not renderer.pending.is_empty(): renderer.build_next()
	assert(far[Vector2i(40,40)][0].visibility_range_begin == 32.0)
	renderer.set_distance(60.0)
	assert(far[Vector2i(40,40)][0].visibility_range_begin == 52.0)
	assert(far[Vector2i(7,13)][0].visibility_range_begin == 0.0)
	for group in renderer.loaded.values(): assert(group.get_child(0).visibility_range_end == 60.0)
	for focus in [Vector2(75,134),Vector2(250,250),Vector2(405,405)]:
		renderer.refresh(focus)
		while not renderer.pending.is_empty(): renderer.build_next()
		assert(renderer.loaded.size() < 450)
	print("PASS: tree chunk residency, fallback, teleport, settings, revisit")
	quit()
