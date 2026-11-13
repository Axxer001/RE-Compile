extends RefCounted
# Simple clothes for the Quaternius base bodies, made from the body itself.
# A garment is the subset of body triangles whose vertices are mostly moved by
# the garment's bones (e.g. a shirt = spine + clavicles + upper arms), pushed
# out along the normals so it sits over the skin. It keeps the body's bone
# weights and Skin, so it bends exactly with every animation, with no rigging.
# Surfaces are cached per (body mesh, garment), so each shape is built once.
# Colours are original: a WMSU-style white polo / blouse, dark trousers, black
# shoes, with grime and dried blood from a procedural noise texture.

const GARMENTS := {
	# bones: skin bind names; offset: metres outward; min_y/max_y: bind-pose limits
	# "also": a second rule (bones + y range) that adds vertices, e.g. the upper
	# hips so an untucked shirt meets the trousers.
	"polo": {"bones": ["spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"], "offset": 0.026, "max_y": 1.52, "weight": 0.3,
		"also": {"bones": ["pelvis"], "min_y": 0.9}},
	"trousers": {"bones": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"], "offset": 0.016, "min_y": 0.1, "weight": 0.3},
	"shoes": {"bones": ["foot_l", "foot_r", "ball_l", "ball_r"], "offset": 0.012, "weight": 0.4},
}
const SELECT_WEIGHT := 0.5 # default: vertex belongs when the garment bones carry >= this weight

static var _cache := {} # "mesh_rid:garment" -> ArrayMesh

# The body skin mesh of an instantiated base-character scene (largest mesh).
static func body_mesh(model: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if best == null or mi.mesh.surface_get_array_len(0) > best.mesh.surface_get_array_len(0): best = mi
	return best

static func _binds(body: MeshInstance3D, names: Array) -> Dictionary:
	var out := {}
	for i in body.skin.get_bind_count():
		if String(body.skin.get_bind_name(i)) in names: out[i] = true
	return out

# Builds (or reuses) one garment mesh for the given body MeshInstance3D.
static func garment_mesh(body: MeshInstance3D, garment: String) -> ArrayMesh:
	var key := "%s:%s" % [body.mesh.get_rid().get_id(), garment]
	if _cache.has(key): return _cache[key]
	var spec: Dictionary = GARMENTS[garment]
	var wanted := _binds(body, spec.bones)
	var also: Dictionary = spec.get("also", {})
	var also_wanted := _binds(body, also.get("bones", []))
	var threshold: float = spec.get("weight", SELECT_WEIGHT)
	var arr: Array = body.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var index: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := bones.size() / verts.size()
	var keep := PackedByteArray()
	keep.resize(verts.size())
	for v in verts.size():
		var w := 0.0
		var wa := 0.0
		for k in per:
			var bi := bones[v * per + k]
			if wanted.has(bi): w += weights[v * per + k]
			if also_wanted.has(bi): wa += weights[v * per + k]
		var y := verts[v].y
		var ok := w >= threshold and y >= float(spec.get("min_y", -INF)) and y <= float(spec.get("max_y", INF))
		if not ok and not also.is_empty():
			ok = wa >= threshold and y >= float(also.get("min_y", -INF)) and y <= float(also.get("max_y", INF))
		keep[v] = 1 if ok else 0
	# Re-index the kept triangles into a compact vertex set.
	var remap := {}
	var o_v := PackedVector3Array(); var o_n := PackedVector3Array(); var o_uv := PackedVector2Array()
	var o_b := PackedInt32Array(); var o_w := PackedFloat32Array(); var o_i := PackedInt32Array()
	var off: float = spec.offset
	for t in range(0, index.size(), 3):
		var a := index[t]; var b := index[t + 1]; var c := index[t + 2]
		if keep[a] == 0 or keep[b] == 0 or keep[c] == 0: continue
		for v in [a, b, c]:
			if not remap.has(v):
				remap[v] = o_v.size()
				o_v.append(verts[v] + normals[v] * off)
				o_n.append(normals[v])
				o_uv.append(uvs[v])
				for k in per:
					o_b.append(bones[v * per + k])
					o_w.append(weights[v * per + k])
			o_i.append(remap[v])
	var out := ArrayMesh.new()
	if o_i.is_empty():
		_cache[key] = out
		return out
	var s := []
	s.resize(Mesh.ARRAY_MAX)
	s[Mesh.ARRAY_VERTEX] = o_v; s[Mesh.ARRAY_NORMAL] = o_n; s[Mesh.ARRAY_TEX_UV] = o_uv
	s[Mesh.ARRAY_BONES] = o_b; s[Mesh.ARRAY_WEIGHTS] = o_w; s[Mesh.ARRAY_INDEX] = o_i
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s, [], {}, flags)
	_cache[key] = out
	return out

# Fabric with grime (and optionally dried blood) from noise, triplanar so the
# body's UV seams never show.
static func fabric(base: Color, grime: Color, blood := 0.0, seed := 0) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	# Mostly clean cloth, darker grime toward low noise, rare dried-blood patches
	# only at the very bottom of the range (sparse, irregular, not a pattern).
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.05, 0.04).lerp(grime, 1.0 - blood) if blood > 0.0 else grime)
	ramp.set_offset(0, 0.0)
	ramp.set_color(1, base)
	ramp.add_point(0.2, grime.lerp(base, 0.35))
	ramp.add_point(0.45, base.lerp(grime, 0.12))
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(2.2, 2.2, 2.2)
	mat.roughness = 0.95
	return mat

# Dresses an instantiated base-character scene: adds one skinned MeshInstance3D
# per garment next to the body (same skeleton and Skin). Returns the nodes.
static func dress(model: Node, outfit: Dictionary) -> Array[MeshInstance3D]:
	var body := body_mesh(model)
	var made: Array[MeshInstance3D] = []
	for garment in outfit:
		var mi := MeshInstance3D.new()
		mi.name = "Outfit_" + garment
		mi.mesh = garment_mesh(body, garment)
		mi.skin = body.skin
		body.get_parent().add_child(mi)
		mi.transform = body.transform
		mi.skeleton = mi.get_path_to(body.get_node(body.skeleton))
		mi.material_override = outfit[garment]
		made.append(mi)
	return made
