extends SceneTree
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	var script = load("res://scripts/world/forest_terrain.gd")
	if script == null:
		printerr("FAIL: terrain surface is missing")
		quit(1)
		return
	var a = script.new(17, [[75.0, 130.0, 14.0]], [])
	var b = script.new(17, [[75.0, 130.0, 14.0]], [])
	var c = script.new(18, [[75.0, 130.0, 14.0]], [])
	check(a.heights == b.heights and a.heights != c.heights, "deterministic seeded heights")
	check(a.height_at(Vector2(75, 134)) == 0, "camp remains level")
	var high := 0.0
	var low_normal := 1.0
	for z in range(10, 245, 8):
		for x in range(10, 245, 8):
			var p := Vector2(x + 0.3, z + 0.7)
			high = maxf(high, a.height_at(p))
			low_normal = minf(low_normal, a.normal_at(p).y)
	check(high > 5.0 and low_normal > 0.7, "real hills stay within a walkable slope")
	var mesh: ArrayMesh = a.mesh()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var error := 0.0
	for i in range(0, indices.size(), 291):
		var p: Vector3 = (verts[indices[i]] + verts[indices[i+1]] + verts[indices[i+2]]) / 3.0
		error = maxf(error, absf(p.y-a.height_at(Vector2(p.x,p.z))))
	check(error < 0.0001, "ground sampler agrees with actual triangle interiors")
	print("RESULT ", JSON.stringify({"checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
