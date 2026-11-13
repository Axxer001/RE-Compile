extends Node3D
# Binbun grass over the forest floor [Sir, 2026-11-13, Phase 3]. One blade
# MultiMesh per 8 m chunk, built on demand near the camera (nearest first, a few
# per frame) and cached for the run; chunks beyond build_r hide. The blades
# shrink to nothing between fade_start and fade_end in the shader
# (grass_fade.gdshader), so the field grows in instead of popping. Blade spots
# come from the map seed and the chunk, so a chunk always looks the same.
# No grass on the path centrelines or round the campfire. Presentation only:
# no collision, never touches the simulation.
#
# Usage: var g := GrassField.new(); parent.add_child(g); g.setup(map_seed)

const Forest = preload("res://scripts/world/dark_forest.gd")
const MATERIAL := "res://assets/BinbunGrass/src/materials/grass_01/grass_01.tres"
const FADE_SHADER := "res://assets/BinbunGrass/src/shader/grass_fade.gdshader"
const CHUNK := 8.0
const DENSITY := 6.0         # blades per square metre (10 cost ~1 ms p95 under load)
const BLADE := 0.4           # quad size (m), as Binbun's demo
# Grass render distance [Sir, 2026-11-13]: a setting (Settings > Grass distance).
# Blades fade out over the last 30% of it; chunks are built one chunk beyond.
const DEFAULT_DISTANCE := 25.0
const MIN_DISTANCE := 20.0
const MAX_DISTANCE := 120.0
static var view_distance := DEFAULT_DISTANCE # main sets it from the settings
var fade_end := DEFAULT_DISTANCE
var fade_start := DEFAULT_DISTANCE * 0.7
var build_r := DEFAULT_DISTANCE + CHUNK
const PER_FRAME := 4         # chunks built per frame at most
const PATH_CLEAR := 1.2      # no blades this close to a path centreline
const FIRE_CLEAR := 3.2
# Night palette (Binbun's demo palette is a daytime green): dark moss greens.
const NIGHT_GREENS := [Color(0.20, 0.29, 0.12), Color(0.13, 0.21, 0.08), Color(0.08, 0.14, 0.05)]

# A GradientTexture2D in Binbun's palette layout (3 bands) with the night greens.
static func night_palette() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.166667, 0.5, 0.833333])
	g.colors = PackedColorArray(NIGHT_GREENS)
	var t := GradientTexture2D.new()
	t.gradient = g
	return t

var seed := 0
var material: ShaderMaterial
var mesh: QuadMesh
var chunks := {}             # Vector2i -> MultiMeshInstance3D
var focus_fn: Callable       # -> Vector3; defaults to the viewport camera

static func available() -> bool:
	return ResourceLoader.exists(MATERIAL) and ResourceLoader.exists(FADE_SHADER) and not OS.has_environment("RC_NO_GRASS")

func setup(map_seed: int) -> void:
	name = "GrassField"
	seed = map_seed
	material = (load(MATERIAL) as ShaderMaterial).duplicate()
	material.shader = load(FADE_SHADER)
	material.set_shader_parameter("color_gradient", night_palette())
	set_distance(view_distance)
	mesh = QuadMesh.new()
	mesh.size = Vector2(BLADE, BLADE)
	mesh.subdivide_width = 2
	mesh.subdivide_depth = 2
	mesh.center_offset = Vector3(0, BLADE * 0.5, 0)

# Sets how far the grass reaches (m, clamped 20-120); takes effect at once.
func set_distance(m: float) -> void:
	fade_end = clampf(m, MIN_DISTANCE, MAX_DISTANCE)
	fade_start = fade_end * 0.7
	build_r = fade_end + CHUNK
	if material:
		material.set_shader_parameter("fade_start", fade_start)
		material.set_shader_parameter("fade_end", fade_end)

func focus() -> Vector3:
	if focus_fn.is_valid(): return focus_fn.call()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.ZERO

func _process(_delta: float) -> void:
	update(PER_FRAME)

# Builds up to `budget` missing chunks within build_r of the focus (nearest
# first) and shows only chunks in range. Returns the number built.
func update(budget: int) -> int:
	var at := focus()
	var c := Vector2(at.x, at.z)
	var r := int(ceil(build_r / CHUNK))
	var cx := int(floor(c.x / CHUNK))
	var cz := int(floor(c.y / CHUNK))
	var want: Array = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if key.x < 0 or key.y < 0 or key.x * CHUNK >= Forest.SIZE.x or key.y * CHUNK >= Forest.SIZE.y: continue
			var mid := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK
			var d := mid.distance_to(c)
			if d <= build_r + CHUNK * 0.71: want.append([d, key])
	want.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	var built := 0
	for w in want:
		var key: Vector2i = w[1]
		keep[key] = true
		if not chunks.has(key):
			if built >= budget: continue
			chunks[key] = _build(key)
			built += 1
		chunks[key].visible = true
	for key in chunks:
		if not keep.has(key): chunks[key].visible = false
	return built

func blade_count() -> int:
	var n := 0
	for key in chunks:
		if chunks[key].visible: n += (chunks[key] as MultiMeshInstance3D).multimesh.instance_count
	return n

func _build(key: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(seed, key.x, key.y))
	var fire := Vector2(Forest.CAMPFIRE.x, Forest.CAMPFIRE.z)
	var spots := PackedFloat32Array()
	var n := int(CHUNK * CHUNK * DENSITY)
	for i in n:
		var p := Vector2((key.x + rng.randf()) * CHUNK, (key.y + rng.randf()) * CHUNK)
		var s := rng.randf_range(0.8, 1.3)
		if Forest.centreline_dist(p) < PATH_CLEAR or p.distance_to(fire) < FIRE_CLEAR: continue
		spots.append_array([s, 0.0, 0.0, p.x, 0.0, s, 0.0, 0.0, 0.0, 0.0, s, p.y])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size() / 12
	if mm.instance_count > 0: mm.buffer = spots
	var inst := MultiMeshInstance3D.new()
	inst.name = "grass_%d_%d" % [key.x, key.y]
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	return inst
