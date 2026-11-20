extends RefCounted
# The material look [Sir, 2026-11-20; docs/plan-graphics-direction.md]: Mage
# Arena-style faceted low poly with small nearest-filtered painted maps and a
# muted earthy palette, under the Silent Hill 2-style night (art_direction.gd).
# StandardMaterial3D only, no custom material shaders. Presentation only.
#   matte(mat)        roughness 1, no metal, nearest-filtered maps (a linear map
#                     with mipmaps, like the bamboo stem's, is left as authored)
#   faceted(mesh)     the same mesh with per-face (flat) normals; cached
#   mute(node, s)     every material under `node` matte, its colour pulled `s`
#                     of the way to the palette (the skins and cloth of enemies)
#   palette_tint(c)   a colour pulled to the palette's earthy range

const BARK := Color(0.55, 0.49, 0.45)    # the reference oak bark tint
const LEAF := Color(0.46, 0.43, 0.39)    # the reference leaf tint
const SOIL := Color(0.44, 0.43, 0.37)
const STONE := Color(0.47, 0.46, 0.42)   # rocks: between soil and bark

static var _faceted := {}                # source mesh -> flat-normal copy

static func matte(m: BaseMaterial3D) -> void:
	if m == null: return
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.25
	if m.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_LINEAR, BaseMaterial3D.TEXTURE_FILTER_NEAREST]:
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

# Per-face normals: unshare every vertex, then let SurfaceTool derive one normal
# per triangle. Skinned and blend-shape meshes are returned unchanged.
static func faceted(mesh: Mesh) -> Mesh:
	if mesh == null: return mesh
	if _faceted.has(mesh): return _faceted[mesh]
	if not mesh is ArrayMesh or (mesh as ArrayMesh).get_blend_shape_count() > 0:
		_faceted[mesh] = mesh
		return mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_BONES] != null:
			_faceted[mesh] = mesh # skinned: keep (its smooth normals ride the skeleton)
			return mesh
		var st := SurfaceTool.new()
		st.create_from(mesh, s)
		st.deindex()
		st.generate_normals()
		st.commit(out)
		var sm: Material = mesh.surface_get_material(s)
		if sm != null: out.surface_set_material(out.get_surface_count() - 1, sm)
	out.resource_name = mesh.resource_name
	_faceted[mesh] = out
	return out

static func palette_tint(c: Color, strength := 0.45) -> Color:
	var l := c.get_luminance()
	var earth := Color(SOIL.r, SOIL.g, SOIL.b) * (l / maxf(SOIL.get_luminance(), 0.01))
	var t := c.lerp(earth, strength)
	t.a = c.a
	return t

# Every mesh material under `node`: matte, colour pulled toward the palette.
static func mute(node: Node, strength := 0.45) -> void:
	if node == null: return
	for g in node.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null or m.has_meta("rc_muted"): continue
			# In place, once: these materials are shared or cached per garment, so
			# every enemy wearing them is muted alike (and no override per instance).
			matte(m)
			if not m.emission_enabled: m.albedo_color = palette_tint(m.albedo_color, strength) # glows (eyes, crystals) keep their colour
			m.set_meta("rc_muted", true)
