extends Node3D
## Map 1, the Dark Forest [Sir, 2026-11-20; docs/spec-map1-dark-forest.md;
## docs/plan-map1-dark-forest.md]: the geometry. The camp (with the town in the
## valley behind it, walled off), seeded pathways (straight, bend, slope pieces,
## lined with bamboo and walls) and the 60 x 60 m wrap-around combat chunk,
## drawn as 3 x 3 identical tiles that follow the player. The rules live in
## map1_rules.gd; main.gd drives both. World axes: +X east, -Z north (the map
## runs north from the camp), +Y up; metres.

const DarkForest = preload("res://scripts/world/dark_forest.gd") # kit trees, props, materials
const ArtDirection = preload("res://scripts/render/art_direction.gd")
const Map1Fog = preload("res://scripts/world/map1_fog.gd")
const Map1Rules = preload("res://scripts/core/map1_rules.gd")
const MIST_SHADER := "res://assets/shaders/map1/mist.gdshader"
const HOLLOWS := 8               # mist patches gather in this many of a field's lowest spots

# ---- layout (spec §1-§3) ------------------------------------------------------------
const CHUNK := 60.0
const HALF := 30.0
const PATH_HALF := 3.0           # walkable half width of a pathway
const WALL_OFF := 3.4            # invisible walls this far from the centreline
const BAMBOO_OFF := 4.6          # region test: a point this close to the centreline is in the pathway
const BAMBOO_STEP := 2.3
# The layout pass [Sir, 2026-11-20; docs/plan-map1-layout-pass.md §1]: irregular
# ranks of culms set into raised banks, lit inside, black behind; grass verges.
const CULM_IN := 3.75            # the nearest stems (outside the 3.4 m walls)
const CULM_OUT := 10.5
const CULMS_PER_M := 20.0        # per side
const BANK_H := 2.2              # the banks rise this much over 2.5-8 m from the centreline
const BANK_R := Vector2(2.5, 8.0)
const STRIP_X := [-16.0, -13.0, -9.0, -6.5, -4.6, -3.4, -2.0, 0.0, 2.0, 3.4, 4.6, 6.5, 9.0, 13.0, 16.0] # floor cross-section
const FLOOR_HALF := 13.0         # the floor proper (lane and banks); past it the ground slopes away into the earth
const TURN_SPREAD_M := 8.0       # a floor cross-section faces the centreline this far either side
const FALL_OFF := 3.6            # ... this far down over the last 3 m: no edge ever hangs in the air
const VERGE_DENSITY := 3.2       # grass cards per m² along the verges
const LANE_TUFTS := 0.035        # a few tufts on the walking line
const BAMBOO_SHADER := "res://assets/shaders/map1/bamboo.gdshader"
const WALL_H := 8.0
const CAMPFIRE := Vector3(75, 0, 129)
const SPAWN := {"at": Vector3(75, 0, 134), "yaw": 0.0}  # the camp, facing north (the forest)
const CAMP_BOX := [Vector2(61, 115), Vector2(92, 146)]   # walled camp floor (x/z min, max)
const CAMP_MOUTH := Vector3(75, 0, 115)                 # Pathway #0 starts here
const CAMP_FOG_END := 260.0      # the camp: the town and the valley in view
const CAMP_FOG_BLEND_M := 12.0
const HEDGE_HALF := 10.0         # an exit's bamboo line during the cooldown: this far either side of the mouth
const EDGE_DEPTH := 8.0          # a closed field's treeline (and the ground under it) reaches this far beyond its edge
const UNLOAD_M := 22.0           # into a pathway this far (past the 20 m visibility): the area behind unloads [plan-map1-visibility]
const SAME_EDGE_OFFSET := 18.0   # two exits on one edge sit this far either side of its middle, bending apart
const EDGES := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)] # N E S W: a field's edges, outward
const ENTRANCE_CLEAR := 9.0
const EXIT_CLEAR := 5.5
const CENTRE_CLEAR := 7.0        # an open middle to fight in
# The combat field [layout pass §3, Sir]: grass only, a few natural rocks, hills.
const ROCKS := Vector2i(6, 9)    # half-buried rocks per chunk: the only cover
const HILL_K := 0.52             # the two waves' scale: steepest face ~24 degrees on the 2 m triangles (under 25)
const FIELD_STEP := 2.0          # the surface grid (mesh, collider and height_at share its triangles)
const GRASS_CELL := 10.0         # grass drawn per cell (shared by the 9 tiles)
const FIELD_GRASS := 5.0         # cards per m²: no bare ground from eye height
const BLEND_M := 10.0            # a pathway's floor blends into the field over its last (or first) metres
const ROCK_GROUPS := 7
const TOWN_AT := Vector3(75, -7, 240)  # the town's anchor, ~106 m from the spawn [layout pass §2]
const KENNEY := "res://assets/kenney_fantasy_town/"  # Kenney Fantasy Town Kit 2.0 (CC0), the pieces used
const TOWN_CELL := 4.4           # a kit cell (1 m) drawn this big
const TOWN_TINT := Color(0.82, 0.78, 0.9) # the night palette over the kit's colour map

var rng := RandomNumberGenerator.new()
var seed_value := 0
var ground_mat: Material
var camp: Node3D
var town: Node3D
var camp_loaded := false
var pathways: Array = []         # {node, pts, length, index, sealed, seal_t, curtain, from}
var chunk := {}                  # the combat chunk: {centre, base_y, layout, tiles, tile, wrap, entry, border, edge_solids, index}
var next_chunk := {}             # built when a pathway is committed, entered at its end
var old_chunk := {}              # being left: unloads when the pathway behind seals
var curtain_mat: ShaderMaterial
var vis_now := 30.0             # the player's visibility this frame (main sets it): the camp's sky and lights follow
var grass_reach := 25.0         # how far the field's grass draws now (set_grass_reach)
const PEACE_GRASS := {"low": 25.0, "medium": 32.0, "high": 40.0} # a closed field's grass reach per preset [plan-map1-visibility]
var chunks_built := 0
var log_lines: Array = []
var fog: Node3D                  # Map1Fog: banks, sheets, breathing visibility

# ---- build ---------------------------------------------------------------------------

## The fixed part, once: the moon and the camp fire light (kept as lamps). Returns
## {node, spawn, solids, bounds, lamps} like the other levels.
func build(parent: Node3D) -> Dictionary:
	name = "DarkForest"
	parent.add_child(self)
	curtain_mat = ShaderMaterial.new()
	curtain_mat.shader = preload("res://assets/shaders/map1/seal_mist.gdshader")
	curtain_mat.set_shader_parameter("noise_tex", preload("res://assets/BinbunSky/textures/clouds/clouds_01.tres"))
	ground_mat = _ground_material()
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = ArtDirection.FOG_END # nothing past the opaque fog is seen: no shadows drawn there [perf]
	add_child(moon)
	var fire := OmniLight3D.new()
	fire.name = "CampFire"
	fire.position = CAMPFIRE + Vector3(0, 1.2, 0)
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 3.5
	fire.omni_range = 16.0
	fire.shadow_enabled = false
	fire.set_meta("base_energy", 3.5)
	fire.set_meta("flicker", "fire")
	add_child(fire)
	fog = Map1Fog.new()
	add_child(fog)
	fog.setup(1)
	var lamps: Array[OmniLight3D] = [fire]
	return {"node": self, "spawn": SPAWN, "solids": [], "bounds": nav_bounds(), "lamps": lamps}

static func _ground_material() -> Material:
	const GM := "res://assets/BinbunGrass/src/materials/grass_01/grass_ground_01.tres"
	const GS := "res://assets/BinbunGrass/src/shader/ground_lit.gdshader"
	if ResourceLoader.exists(GM) and ResourceLoader.exists(GS):
		var gm: ShaderMaterial = (load(GM) as ShaderMaterial).duplicate()
		gm.shader = load(GS)
		gm.set_shader_parameter("color_gradient", load("res://scripts/world/grass_field.gd").night_palette())
		return gm
	return DarkForest.material("ground")

## A new run (or the first): the camp, Pathway #0 and the first combat chunk,
## everything else gone. Same seed, same corridor.
func reset(seed_in: int) -> void:
	seed_value = seed_in
	rng.seed = seed_in ^ 0x6d61
	for n in [camp, town]:
		if n != null and is_instance_valid(n): n.free()
	for pw in pathways: if is_instance_valid(pw.node): pw.node.free()
	for c in [chunk, next_chunk, old_chunk]: _free_chunk(c)
	pathways = []
	chunk = {}
	next_chunk = {}
	old_chunk = {}
	chunks_built = 0
	log_lines = []
	var fire: Node3D = get_node_or_null("CampFire")
	if fire: fire.visible = true
	var lay := chunk_layout(seed_value * 31 + chunks_built + 1)
	var pw := _build_pathway(CAMP_MOUTH, pathway_length_draw(), 0, "camp", {"flat": CAMP_MOUTH.y}, lay) # its banks settle onto the camp's ground

	_build_camp(pw.pts)
	_build_town()
	camp_loaded = true
	next_chunk = _build_chunk(pw.pts[pw.pts.size() - 1], lay)

func pathway_length_draw() -> float:
	return rng.randf_range(30.0, 90.0)

# ---- the camp and the town -----------------------------------------------------------

var camp_solids: Array = []

func _build_camp(path_points: Array) -> void:
	camp_solids = []
	camp = Node3D.new()
	camp.name = "Camp"
	add_child(camp)
	var size := CAMP_BOX[1] - CAMP_BOX[0]
	var floor_body := DarkForest._box(camp, Vector3(CAMP_BOX[0].x + size.x * 0.5, -0.1, CAMP_BOX[0].y + size.y * 0.5), Vector3(size.x, 0.2, size.y), null, "floor", [], false)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size # the valley mesh (shoulders) carries on round it
	fm.mesh = pm
	fm.position = Vector3(0, 0.1, 0)
	fm.material_override = ground_mat
	floor_body.add_child(fm)
	for i in 3: # benches round the fire (log colliders)
		var a := TAU * float(i) / 3.0 + 0.4
		var at := CAMPFIRE + Vector3(cos(a) * 2.6, 0.0, sin(a) * 2.6)
		var has_bench := DarkForest.prop_available("Bench")
		DarkForest._box(camp, at + Vector3(0, 0.2, 0), Vector3(1.8, 0.4, 0.45), DarkForest.material("log"), "log_%d" % i, camp_solids, not has_bench, rad_to_deg(-a) + 90.0)
		if has_bench:
			var b := DarkForest.prop("Bench", 1.8)
			b.name = "bench_%d" % i
			b.position = at
			b.rotation.y = -a + PI * 0.5
			camp.add_child(b)
	DarkForest._dress_camp(camp, camp_solids)
	# Walls: round the camp floor, open only at the forest mouth (north) [spec §1].
	var lo: Vector2 = CAMP_BOX[0]
	var hi: Vector2 = CAMP_BOX[1]
	var mouth_l := CAMP_MOUTH.x - PATH_HALF
	var mouth_r := CAMP_MOUTH.x + PATH_HALF
	for w in [[Vector3(lo.x - 0.3, WALL_H * 0.5, (lo.y + hi.y) * 0.5), Vector3(0.6, WALL_H, size.y + 1.0), "camp_wall_w"],
			[Vector3(hi.x + 0.3, WALL_H * 0.5, (lo.y + hi.y) * 0.5), Vector3(0.6, WALL_H, size.y + 1.0), "camp_wall_e"],
			[Vector3((lo.x + hi.x) * 0.5, WALL_H * 0.5, hi.y + 0.3), Vector3(size.x + 1.0, WALL_H, 0.6), "camp_wall_town"], # the town: in view, out of reach
			[Vector3((lo.x + mouth_l) * 0.5, WALL_H * 0.5, lo.y - 0.3), Vector3(mouth_l - lo.x, WALL_H, 0.6), "camp_wall_nw"],
			[Vector3((mouth_r + hi.x) * 0.5, WALL_H * 0.5, lo.y - 0.3), Vector3(hi.x - mouth_r, WALL_H, 0.6), "camp_wall_ne"]]:
		DarkForest._box(camp, w[0], w[1], null, w[2], camp_solids, false)
	# The forest edge [layout pass §2]: ranks of bamboo behind the north wall (the
	# entrance, its own sightline); grassy shoulders on the other sides; no trees.
	var stems := []
	for k in 1250:
		var x := rng.randf_range(lo.x - 16.0, hi.x + 16.0)
		if absf(x - CAMP_MOUTH.x) < PATH_HALF + 0.6: continue
		var row: int = k % 3
		var back: float = [1.2, 5.8, 12.0][row] + rng.randf_range(-0.75, 0.75) + sin(x * 0.28 + row) * 0.65
		var z := lo.y - back + (maxf(lo.x - x, x - hi.x) * 0.8 if (x < lo.x or x > hi.x) else 0.0) # round the corners onto the shoulders
		if float(path_project(path_points, Vector3(x, 0, z)).gap) < CULM_IN: continue
		stems.append([Vector3(x, valley_y(x, z), z), clampf(back / 12.0, 0.0, 1.0)])
	_culms(camp, stems, "CampBamboo")
	var tufts := []
	for k in int(size.x * size.y * 2.2):
		var q := Vector3(rng.randf_range(lo.x, hi.x), 0.0, rng.randf_range(lo.y, hi.y))
		if Vector2(q.x - CAMPFIRE.x, q.z - CAMPFIRE.z).length() < 4.2: continue # the fire and its seats
		if absf(q.x - CAMPFIRE.x) < 1.6 and q.z > CAMPFIRE.z: continue # the trail down to the town
		tufts.append(q)
	_grass(camp, tufts, "CampGrass")

## The valley behind the camp [layout pass §2]: open grassy banks either side of a
## trail winding down toward the town (y falls 9 m per 100 m), then a ridge.
## Height at world (x, z); the camp floor (inside CAMP_BOX) stays flat.
static func valley_y(x: float, z: float) -> float:
	var u := z - CAMP_BOX[1].y
	var out: float = maxf(CAMP_BOX[0].x - x, x - CAMP_BOX[1].x)
	var bank_shape: float = 4.0 + 3.8 * sin(z * 0.14) + (3.2 if x > CAMP_MOUTH.x else -2.4)
	var shoulder: float = smoothstep(0.0, 14.0, out) * bank_shape
	if u <= 0.0:
		return shoulder
	var dx := x - valley_trail(z)
	var open := 1.0 - smoothstep(50.0, 78.0, u) # the banks part where the valley opens onto the town
	var far_slope := smoothstep(70.0, 135.0, u) * 18.0 # the town climbs the far side, facing the camp
	return shoulder * (1.0 - smoothstep(0.0, 18.0, u)) + 1.45 * far_slope - 0.09 * u + smoothstep(3.0, 16.0, absf(dx)) * (3.8 + 2.8 * sin(u * 0.13 + dx * 0.12)) * smoothstep(0.0, 14.0, u) * open + 1.1 * sin(u * 0.18) * smoothstep(4.0, 24.0, u) * open

static func valley_trail(z: float) -> float:
	return CAMPFIRE.x + 6.0 * sin((z - CAMP_BOX[1].y) * 0.065)

func _build_town() -> void:
	town = Node3D.new()
	town.name = "Town"
	add_child(town)
	# The ground: one mesh from the camp's sides down the valley (2 m grid).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := 15.0
	var x1 := 135.0
	var z0: float = CAMP_BOX[0].y - 14.0
	var z1 := TOWN_AT.z + 70.0
	var step := 2.0
	var x := x0
	while x < x1:
		var z := z0
		while z < z1:
			for q in [Vector2(0, 0), Vector2(step, 0), Vector2(0, step), Vector2(step, 0), Vector2(step, step), Vector2(0, step)]:
				var px: float = x + q.x
				var pz: float = z + q.y
				var py := valley_y(px, pz)
				if px > CAMP_BOX[0].x and px < CAMP_BOX[1].x and pz > CAMP_BOX[0].y and pz < CAMP_BOX[1].y: py = -0.05 # under the camp floor
				st.set_uv(Vector2(px, pz) * 0.31)
				st.add_vertex(Vector3(px, py, pz))
			z += step
		x += step
	st.generate_normals()
	var slope := MeshInstance3D.new()
	slope.name = "Valley"
	slope.mesh = st.commit()
	slope.material_override = ground_mat
	slope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(slope)
	# The trail: a strip conforming to the ground, ~2.6 m wide, down toward the roofs.
	var earth: StandardMaterial3D = earth_material().duplicate()
	earth.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR # [Dark Forest swap 2026-11-24]
	earth.alpha_scissor_threshold = 0.5
	earth.vertex_color_use_as_albedo = true
	earth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var ps := SurfaceTool.new()
	ps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zt: float = CAMP_BOX[1].y - 8.0
	while zt < TOWN_AT.z - 24.0:
		var za := zt
		var zb := zt + 2.0
		var w := lerpf(1.6, 1.0, clampf((za - CAMP_BOX[1].y) / 90.0, 0.0, 1.0))
		var quad := []
		for v in [[za, -w], [za, w], [zb, w], [zb, -w]]:
			var tx: float = valley_trail(v[0]) + float(v[1]) if v[0] > CAMP_BOX[1].y else CAMPFIRE.x + float(v[1])
			var ty: float = (valley_y(tx, v[0]) if v[0] > CAMP_BOX[1].y else 0.0) + 0.04
			quad.append(Vector3(tx, ty, v[0]))
		for i in [0, 1, 2, 0, 2, 3]:
			var fade: float = smoothstep(CAMP_BOX[1].y - 8.0, CAMP_BOX[1].y + 3.0, quad[i].z)
			ps.set_color(Color(1, 1, 1, 0.82 * fade))
			ps.set_normal(Vector3.UP)
			ps.set_uv(Vector2(quad[i].x, quad[i].z) * 0.31)
			ps.add_vertex(quad[i])
		zt = zb
	var path := MeshInstance3D.new()
	path.name = "TownPath"
	path.mesh = ps.commit()
	path.material_override = earth
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(path)
	# Grass on the banks near the camp (it fades out with distance anyway).
	var tufts := []
	for k in 9000:
		var q := Vector3(rng.randf_range(CAMP_BOX[0].x - 14.0, CAMP_BOX[1].x + 14.0), 0, rng.randf_range(CAMP_BOX[1].y, CAMP_BOX[1].y + 40.0))
		if absf(q.x - valley_trail(q.z)) < 2.0 and rng.randf() > 0.035: continue
		q.y = valley_y(q.x, q.z)
		tufts.append(q)
	for k in 2500: # and the shoulders beside the camp
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var qx: float = (CAMP_BOX[0].x - rng.randf_range(0.5, 14.0)) if side < 0.0 else (CAMP_BOX[1].x + rng.randf_range(0.5, 14.0))
		var q2 := Vector3(qx, 0, rng.randf_range(CAMP_BOX[0].y, CAMP_BOX[1].y))
		q2.y = valley_y(q2.x, q2.z)
		tufts.append(q2)
	_grass(town, tufts, "ValleyGrass")
	# The town: Kenney Fantasy Town Kit houses, tinted to the night, lit windows.
	var trng := RandomNumberGenerator.new()
	trng.seed = 0x70776e # the same town every run
	var placed := []
	var tries := 0
	while placed.size() < 22 and tries < 400:
		tries += 1
		var at := TOWN_AT + Vector3(trng.randf_range(-40, 40), 0, trng.randf_range(-10, 30))
		if absf(at.x - valley_trail(at.z)) < 4.0: continue
		var ok := true
		for o in placed: if Vector2(o.x - at.x, o.z - at.z).length() < 14.0: ok = false
		if not ok: continue
		placed.append(at)
		var w := trng.randi_range(2, 3)
		var d := trng.randi_range(2, 3)
		var floors := trng.randi_range(1, 2)
		at.y = valley_y(at.x, at.z) - 0.4
		_house(town, at, trng.randf_range(-0.35, 0.35), w, d, floors, trng)
	# The keep above the roofline, and a final ridge.
	var keep_at := Vector3(TOWN_AT.x + 4.0, 0, TOWN_AT.z + 34.0)
	keep_at.y = valley_y(keep_at.x, keep_at.z)
	_keep(town, keep_at)
	var ridge_m := StandardMaterial3D.new()
	ridge_m.albedo_color = Color(0.13, 0.16, 0.2)
	ridge_m.roughness = 1.0
	for k in 12:
		var hill := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 16
		sm.rings = 8
		hill.mesh = sm
		hill.material_override = ridge_m
		var hx := TOWN_AT.x - 76.0 + k * 13.0
		hill.position = Vector3(hx, TOWN_AT.y + 9.0, TOWN_AT.z + 62.0 + 8.0 * cos(hx))
		hill.scale = Vector3(65, 32 + 23 * absf(sin(hx * 0.08)), 45)
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		town.add_child(hill)
	var vista: Node3D = preload("res://assets/map1_vista/valley_layers.tscn").instantiate()
	vista.position = CAMPFIRE
	town.add_child(vista)
	var skyline := MeshInstance3D.new()
	skyline.name = "ValleySky"
	var dome := SphereMesh.new()
	dome.radius = 224.0
	dome.height = 448.0
	skyline.mesh = dome
	var sky_material := ShaderMaterial.new()
	sky_material.shader = preload("res://assets/shaders/map1/valley_sky.gdshader")
	sky_material.set_shader_parameter("cloud_tex_01", preload("res://assets/BinbunSky/textures/clouds/clouds_01.tres"))
	sky_material.set_shader_parameter("cloud_tex_02", preload("res://assets/BinbunSky/textures/clouds/clouds_02.tres"))
	skyline.material_override = sky_material
	skyline.position = CAMPFIRE
	skyline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(skyline)
	var glow := OmniLight3D.new()
	glow.name = "TownGlow"
	glow.position = TOWN_AT + Vector3(0, 8, 6)
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = 4.0
	glow.omni_range = 70.0
	town.add_child(glow)

## A kit piece (cached scene), tinted to the night; windows get an emissive pane.
static var _kit_scenes := {}
static var _kit_tinted := {}
static var _window_mat: StandardMaterial3D
func _piece(parent: Node3D, name: String, xf: Transform3D) -> Node3D:
	if not _kit_scenes.has(name):
		_kit_scenes[name] = load(KENNEY + name + ".glb") if ResourceLoader.exists(KENNEY + name + ".glb") else null
	var ps: PackedScene = _kit_scenes[name]
	if ps == null: return null
	var n: Node3D = ps.instantiate()
	n.transform = xf
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in g.mesh.get_surface_count():
			var src := g.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null: continue
			if not _kit_tinted.has(src):
				var t: BaseMaterial3D = src.duplicate()
				t.albedo_color = src.albedo_color * TOWN_TINT
				t.roughness = 1.0
				t.metallic = 0.0
				_kit_tinted[src] = t
			g.set_surface_override_material(si, _kit_tinted[src])
	parent.add_child(n)
	if name.contains("window"):
		if _window_mat == null:
			_window_mat = StandardMaterial3D.new()
			_window_mat.albedo_color = Color(1.0, 0.74, 0.42)
			_window_mat.emission_enabled = true
			_window_mat.emission = Color(1.0, 0.62, 0.28)
			_window_mat.emission_energy_multiplier = 3.2
		var pane := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.34, 0.34)
		pane.mesh = qm
		pane.material_override = _window_mat
		pane.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.53, 0.55, 0.0)) # on the panel's outer (+x) face
		n.add_child(pane)
	return n

## A house of w x d kit cells and 1-2 floors: wall panels on every outer face
## (doors and lit windows among them), gable roofs on top.
func _house(parent: Node3D, at: Vector3, yaw: float, w: int, d: int, floors: int, r: RandomNumberGenerator) -> void:
	var h := Node3D.new()
	h.name = "house_%d" % parent.get_child_count()
	h.position = at
	h.rotation.y = yaw
	h.scale = Vector3.ONE * TOWN_CELL
	parent.add_child(h)
	var wood := r.randf() < 0.4
	for f in floors:
		for cx in w:
			for cz in d:
				var c := Vector3(cx - (w - 1) * 0.5, f, cz - (d - 1) * 0.5)
				var faces := []
				if cx == w - 1: faces.append(0.0)        # +x
				if cz == 0: faces.append(PI * 0.5)       # -z (toward the camp)
				if cx == 0: faces.append(PI)             # -x
				if cz == d - 1: faces.append(-PI * 0.5)  # +z
				for yaw_f in faces:
					var roll := r.randf()
					var kind := "wall-wood" if wood else "wall"
					if roll < 0.45: kind = "wall-wood-window-glass" if wood else "wall-window-glass"
					elif roll < 0.6: kind = "wall-window-shutters"
					if f == 0 and yaw_f == PI * 0.5 and cx == 0: kind = "wall-door"
					_piece(h, kind, Transform3D(Basis(Vector3.UP, yaw_f), c))
	for cx in w:
		for cz in d:
			_piece(h, "roof-gable" if d > 1 else "roof", Transform3D(Basis(Vector3.UP, PI * 0.5 if w >= d else 0.0), Vector3(cx - (w - 1) * 0.5, floors, cz - (d - 1) * 0.5)))
	if r.randf() < 0.5: _piece(h, "chimney", Transform3D(Basis.IDENTITY, Vector3((w - 1) * 0.5, floors + 0.4, 0)))

## The keep: three stone towers with pointed roofs, walls between, above the roofline.
func _keep(parent: Node3D, at: Vector3) -> void:
	var k := Node3D.new()
	k.name = "Keep"
	k.position = at
	k.scale = Vector3.ONE * TOWN_CELL
	parent.add_child(k)
	for t in [-2, 0, 2]:
		var height := 9 if t == 0 else 7
		for y in height: _piece(k, "pillar-stone", Transform3D(Basis.IDENTITY, Vector3(t, y, 0)))
		_piece(k, "roof-high-point", Transform3D(Basis.IDENTITY, Vector3(t, height, 0)))
		if t != 0:
			for y in 3:
				_piece(k, "wall-block", Transform3D(Basis.IDENTITY, Vector3(t * 0.5, y, 0)))
		_piece(k, "wall-window-glass", Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(t, height - 2, 0)))

## Earth.png (the layout pack's original 128 px ground detail) as a night soil.
static var _earth: StandardMaterial3D
static func earth_material() -> StandardMaterial3D:
	if _earth != null: return _earth
	_earth = StandardMaterial3D.new()
	_earth.albedo_color = Color(0.66, 0.6, 0.48)
	if ResourceLoader.exists("res://assets/textures/map1/earth.png"): _earth.albedo_texture = load("res://assets/textures/map1/earth.png")
	_earth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST # [Dark Forest swap 2026-11-24]
	_earth.roughness = 1.0
	return _earth

# ---- pathways ---------------------------------------------------------------------------

## A pathway's centreline from `start`, heading north, `length` metres along the
## ground: seeded pieces (straight, bend = a sideways jog, slope up or down),
## ending in a 10 m straight into the next chunk. Pure (same rng state, same path).
static func pathway_points(r: RandomNumberGenerator, start: Vector3, length: float, dir := Vector2i(0, -1), lean := 0) -> Array:
	var pts: Array = [start]
	var p := start + Vector3(0, 0, -5)
	pts.append(p)
	var coin := r.randf()
	var drift := (5.5 if coin < 0.5 else -5.5) if lean == 0 else 5.5 * float(lean) # `lean`: bends only to that side (two exits on one edge bend apart)
	p += Vector3(drift, 0.8, -8)
	pts.append(p)
	var along := path_length(pts)
	while along < length - 10.0:
		var left := length - 10.0 - along
		var pick := r.randf()
		var step := 0.0
		var q := p
		if pick < 0.4 or left < 8.0: # straight
			step = minf(r.randf_range(8.0, 16.0), left)
			q = p + Vector3(0, 0, -step)
		elif pick < 0.75: # bend: jog sideways and on
			var lat := r.randf_range(3.0, 6.0) * (1.0 if r.randf() < 0.5 else -1.0)
			if lean != 0: lat = absf(lat) * float(lean)
			if absf(drift + lat) > 10.0: lat = 0.0 if lean != 0 else -lat
			drift += lat
			var fwd := minf(12.0, left)
			step = Vector2(lat, fwd).length()
			q = p + Vector3(lat, 0, -fwd)
		else: # slope up or down
			var fwd2 := minf(14.0, left)
			var dy := r.randf_range(1.0, 2.5) * (1.0 if r.randf() < 0.5 else -1.0) * fwd2 / 14.0
			step = Vector2(fwd2, dy).length()
			q = p + Vector3(0, dy, -fwd2)
		pts.append(q)
		p = q
		along += step
	pts.append(p + Vector3(0, 0, -maxf(10.0, length - along)))
	if dir != Vector2i(0, -1): # built heading north, turned to head `dir`
		var yaw := atan2(-float(dir.x), -float(dir.y))
		for i in pts.size(): pts[i] = start + (pts[i] - start).rotated(Vector3.UP, yaw)
	return pts

static func path_length(pts: Array) -> float:
	var n := 0.0
	for i in range(1, pts.size()): n += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	return n

## Ground distance along the centreline to the point nearest `p`, the gap to it,
## and the height there: {along, gap, y}.
static func path_project(pts: Array, p: Vector3) -> Dictionary:
	var best := {"along": 0.0, "gap": INF, "y": float(pts[0].y)}
	var acc := 0.0
	for i in range(1, pts.size()):
		var a := Vector2(pts[i - 1].x, pts[i - 1].z)
		var b := Vector2(pts[i].x, pts[i].z)
		var ab := b - a
		var u := clampf((Vector2(p.x, p.z) - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var gap := Vector2(p.x, p.z).distance_to(a + ab * u)
		if gap < float(best.gap):
			best = {"along": acc + ab.length() * u, "gap": gap, "y": lerpf(pts[i - 1].y, pts[i].y, u)}
		acc += ab.length()
	return best

static func path_point(pts: Array, along: float) -> Vector3:
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		if acc + seg >= along or i == pts.size() - 1:
			return (pts[i - 1] as Vector3).lerp(pts[i], clampf((along - acc) / maxf(seg, 1e-6), 0.0, 1.0))
		acc += seg
	return pts[pts.size() - 1]

## The banks: height over the lane at `lateral` metres from the centreline.
static func bank(lateral: float) -> float:
	var a := absf(lateral)
	return smoothstep(BANK_R.x, BANK_R.y, a) * BANK_H - maxf(0.0, a - FLOOR_HALF) / 3.0 * FALL_OFF

func _build_pathway(start: Vector3, length: float, index: int, from: String, start_field := {}, end_layout := {}, dir := Vector2i(0, -1), lean := 0) -> Dictionary:
	var pts := pathway_points(rng, start, length, dir, lean)
	var end_field := {}
	if not end_layout.is_empty():
		var e: Vector3 = pts[pts.size() - 1]
		end_field = {"layout": end_layout, "centre": e + Vector3(dir.x, 0, dir.y) * HALF, "base_y": e.y}
	var plen := path_length(pts)
	var node := Node3D.new()
	node.name = "Pathway_%d" % index
	add_child(node)
	var solids := []
	# The floor: a strip across the lane and up the banks (one cross-section per
	# centreline point, joined), with a matching collider.
	var mouth_end := 0
	var mouth_visual := Node3D.new()
	mouth_visual.name = "FirstBend"
	node.add_child(mouth_visual)
	var rows := []
	var acc := 0.0
	for i in range(1, pts.size()): # a cross-section every metre or so (the blends into a field are curves)
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var n_sub := maxi(1, int(ceilf(seg / 1.25)))
		for k in range(0 if i == 1 else 1, n_sub + 1):
			var t := float(k) / n_sub
			var c0: Vector3 = a.lerp(b, t)
			# The cross-section faces along the centreline 8 m either side: a bend's turn spreads
			# over ~16 m, so even the floor's outer edge keeps moving forward (no fold on the inside).
			var here := acc + seg * t
			var pa: Vector3 = path_point(pts, maxf(here - TURN_SPREAD_M, 0.0))
			var pb: Vector3 = path_point(pts, minf(here + TURN_SPREAD_M, plen))
			var d := Vector3(pb.x - pa.x, 0, pb.z - pa.z).normalized()
			var side := Vector3(-d.z, 0, d.x)
			var row := []
			for x in STRIP_X:
				var q: Vector3 = c0 + side * float(x) + Vector3(0, bank(x), 0)
				q.y = _blend_field(q, acc + seg * t, plen, start_field, end_field)
				row.append(q)
			rows.append(row)
		if i == 2: mouth_end = rows.size()-1
		acc += seg
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in range(1, rows.size()):
		for k in range(1, STRIP_X.size()):
			var quad := [rows[i - 1][k - 1], rows[i - 1][k], rows[i][k], rows[i][k - 1]]
			if _folded(quad): continue # the inside of a tight bend: the floor overlaps itself there, the rest covers it
			for q in [0, 2, 1, 0, 3, 2]:
				st.set_uv(Vector2(quad[q].x, quad[q].z) * 0.25)
				st.add_vertex(quad[q])
				faces.append(quad[q])
		if i == mouth_end and from == "chunk":
			_path_surface(mouth_visual, st)
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_path_surface(node, st)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
	# Walls along both sides; bamboo ranks and grass verges set into the banks.
	var stems := []
	var tufts := []
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var d := flat.normalized()
		var n := Vector3(-d.z, 0, d.x)
		var seg_len := flat.length()
		for s in [-1.0, 1.0]:
			var off: Vector3 = n * WALL_OFF * float(s)
			_wall(node, a + off, b + off, solids, "wall_%d_%d" % [i, int(s)])
			for k in int(seg_len * CULMS_PER_M): # the stands overlap at the joints (a little past each end)
				var t := rng.randf_range(-1.5, seg_len + 1.5)
				var lat := rng.randf_range(CULM_IN, CULM_OUT)
				var base: Vector3 = a.lerp(b, clampf(t / maxf(seg_len, 0.01), 0.0, 1.0)) + d * (t - clampf(t, 0.0, seg_len)) + n * lat * float(s)
				base.y += bank(lat)
				var ab := path_project(pts, base)
				if float(ab.gap) < CULM_IN - 0.05: continue # a bend's overlap reaching into the next segment's lane
				base.y = _blend_field(base, float(ab.along), plen, start_field, end_field)
				stems.append([base, (lat - CULM_IN) / (CULM_OUT - CULM_IN)])
			for k in int(seg_len * (BANK_R.y + 1.0 - 2.2) * VERGE_DENSITY):
				var t2 := rng.randf() * seg_len
				var lat2 := rng.randf_range(2.2, BANK_R.y + 1.0)
				var q: Vector3 = a.lerp(b, t2 / maxf(seg_len, 0.01)) + n * lat2 * float(s)
				q.y += bank(lat2)
				q.y = _blend_field(q, float(path_project(pts, q).along), plen, start_field, end_field)
				tufts.append(q)
		for k in int(seg_len * 4.4 * VERGE_DENSITY * LANE_TUFTS):
			var q2: Vector3 = a.lerp(b, rng.randf()) + n * rng.randf_range(-2.2, 2.2)
			q2.y = _blend_field(q2, float(path_project(pts, q2).along), plen, start_field, end_field)
			tufts.append(q2)
		if i == 2 and from == "chunk":
			_culms(mouth_visual, stems, "Bamboo")
			_grass(mouth_visual, tufts, "Verge")
			stems = []
			tufts = []
	_culms(node, stems, "Bamboo")
	_grass(node, tufts, "Verge")
	var pw := {"node": node, "pts": pts, "length": plen, "index": index, "sealed": false, "seal_t": -1.0, "curtain": null, "from": from, "solids": solids, "entered": false,
		"start_field": start_field, "end_field": end_field, "dir": dir}
	pathways.append(pw)
	log_lines.append("pathway %d: %.0f m, %d pieces, %d culms" % [index, pw.length, pts.size() - 1, stems.size()])
	return pw

## A floor quad standing steeper than MAX_FLOOR_TILT_DEG (or turned over): only where the
## wide floor overlaps itself on the inside of a bend. Drawn, it is a slab of ground.
const MAX_FLOOR_TILT_DEG := 72.0
static func _folded(quad: Array) -> bool:
	var lim := cos(deg_to_rad(MAX_FLOOR_TILT_DEG))
	for tri in [[0, 2, 1], [0, 3, 2]]:
		var n: Vector3 = ((quad[tri[1]] as Vector3) - quad[tri[0]]).cross((quad[tri[2]] as Vector3) - quad[tri[0]])
		if n.length() < 1e-6: continue
		if -n.normalized().y < lim: return true # facing up is -y for Godot's clockwise front faces
	return false

func _path_surface(parent: Node3D, st: SurfaceTool) -> void:
	st.generate_normals()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = st.commit()
	floor_mesh.material_override = ground_mat # the field's own ground (world-space noise): no seam where the floor blends into a field
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(floor_mesh)

## Bamboo culms (one shared stem mesh, Bamboo.gdshader), [base, darkness] each:
## Tall, leaning culms and a sparse overhead canopy.
func _culms(parent: Node3D, stems: Array, nm: String) -> MultiMeshInstance3D:
	var culm := CylinderMesh.new()
	culm.radial_segments = 5 # [Dark Forest swap 2026-11-24: the pack's culm budget]
	culm.rings = 0
	culm.height = 1.0
	culm.top_radius = 0.5
	culm.bottom_radius = 0.5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = culm
	mm.instance_count = stems.size()
	for i in stems.size():
		var h := rng.randf_range(36.0, 59.0) + 18.0 * float(stems[i][1])
		var w := rng.randf_range(0.23, 0.48)
		var b := Basis(Vector3.FORWARD, rng.randf_range(-0.095, 0.095)) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06))
		var base: Vector3 = stems[i][0]
		mm.set_instance_transform(i, Transform3D(b.scaled_local(Vector3(w, h, w)), base + b * Vector3(0, h * 0.5 - 0.3, 0)))
		mm.set_instance_custom_data(i, Color(float(stems[i][1]), 0, 0, 0))
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	var feet := PackedVector3Array() # the stems' feet (parent space): a multimesh's instances are not readable headless
	for st in stems: feet.append(st[0])
	inst.set_meta("feet", feet)
	var mat := ShaderMaterial.new()
	mat.shader = load(BAMBOO_SHADER)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	if nm != "ClosedThicket" and stems.size() >= 48:
		var fronds := MultiMesh.new()
		fronds.transform_format = MultiMesh.TRANSFORM_3D
		fronds.mesh = _leaf_spray()
		fronds.instance_count = stems.size() / 48
		for i in fronds.instance_count:
			var base: Vector3 = stems[i * 48][0]
			var angle := float(i) * 2.4
			fronds.set_instance_transform(i, Transform3D(Basis(Vector3.UP, angle), base + Vector3.UP * (11.0 + 5.0 * sin(angle))))
		var leaves := MultiMeshInstance3D.new()
		leaves.multimesh = fronds
		leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(leaves)
	return inst

static var leaf_mesh: Mesh
static func _leaf_spray() -> Mesh:
	if leaf_mesh: return leaf_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var base := Vector3(float(i)*0.19, sin(float(i)*0.15)*0.6, 0)
		var side := 1.0 if i%2 == 0 else -1.0
		var tip := base + Vector3(1.0, -0.35, side * 1.1)
		for q in [base, base + Vector3(0.32,0,side*0.68), tip, base, tip, base+Vector3(0.65,0,side*0.32)]: st.add_vertex(q)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color("36483e")
	st.set_material(m)
	leaf_mesh = st.commit()
	return leaf_mesh

## BinbunGrass cards (the project's grass material, fading out with distance) at `spots`.
static var _grass_material: ShaderMaterial
static var _grass_card: QuadMesh
func _grass(parent: Node3D, spots: Array, nm: String) -> MultiMeshInstance3D:
	var GrassField = load("res://scripts/world/grass_field.gd")
	if not GrassField.available() or spots.is_empty(): return null
	if _grass_material == null:
		_grass_material = (load(GrassField.MATERIAL) as ShaderMaterial).duplicate()
		_grass_material.shader = load(GrassField.FADE_SHADER)
		_grass_material.set_shader_parameter("color_gradient", GrassField.night_palette())
		_grass_material.set_shader_parameter("fade_start", GrassField.view_distance * 0.7)
		_grass_material.set_shader_parameter("fade_end", GrassField.view_distance)
		_grass_card = QuadMesh.new()
		_grass_card.size = Vector2(0.85, 0.55)
		_grass_card.subdivide_width = 2
		_grass_card.subdivide_depth = 2
		_grass_card.center_offset = Vector3(0, 0.275, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _grass_card
	mm.instance_count = spots.size()
	for i in spots.size():
		var sc := rng.randf_range(0.8, 1.3)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), spots[i]))
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	inst.material_override = _grass_material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst

## A wall between a and b (a rotated box for the physics) and, for the nav grid,
## 1 m boxes along it (a rotated box's AABB would close the path).
func _wall(parent: Node3D, a: Vector3, b: Vector3, solids: Array, nm: String) -> void:
	var flat := Vector3(b.x - a.x, 0, b.z - a.z)
	var wall_len := flat.length() + 1.2
	var mid := (a + b) * 0.5
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, WALL_H + absf(b.y - a.y), wall_len)
	col.shape = box
	body.add_child(col)
	body.transform = Transform3D(Basis(Vector3.UP, atan2(flat.x, flat.z)), mid + Vector3(0, WALL_H * 0.5, 0))
	parent.add_child(body)
	var n := int(ceilf(wall_len))
	for k in n + 1:
		var p := a.lerp(b, float(k) / maxf(n, 1))
		solids.append(AABB(Vector3(p.x - 0.4, p.y, p.z - 0.4), Vector3(0.8, WALL_H, 0.8)))

## Bamboo clumps (the kit's Bamboo) as one MultiMesh per part; no colliders (walls do that).
func _bamboo(parent: Node3D, stems: Array, nm: String) -> void:
	var parts: Array = DarkForest._kit("Bamboo")
	var holder := Node3D.new()
	holder.name = nm
	parent.add_child(holder)
	var xs := []
	for i in stems.size():
		var s := rng.randf_range(0.75, 1.05)
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), stems[i]))
	if parts.is_empty(): # no kit: green posts
		DarkForest._multimesh(holder, DarkForest._cone_mesh(0.25, 0.35, DarkForest.material("crown")), xs.map(func(x): return x * Transform3D(Basis.from_scale(Vector3(1, 7, 1)), Vector3(0, 3.5, 0))), "Stems", false)
		return
	for e in parts:
		var px := []
		for x in xs: px.append(x * (e[1] as Transform3D))
		DarkForest._multimesh(holder, e[0], px, "Stems", false)

## A fog curtain across a pathway at `along` m: a fog-coloured sheet (its alpha
## is the fog's thickness there).
func _curtain(parent: Node3D, pts: Array, along: float, alpha: float, nm: String) -> MeshInstance3D:
	var at := path_point(pts, along)
	var ahead := path_point(pts, along + 0.5)
	var d := Vector3(ahead.x - at.x, 0, ahead.z - at.z).normalized()
	var m := MeshInstance3D.new()
	m.name = nm
	var q := QuadMesh.new()
	q.size = Vector2(BAMBOO_OFF * 2.0 + 4.0, WALL_H + 2.0)
	m.mesh = q
	var mat: ShaderMaterial = curtain_mat.duplicate()
	mat.set_shader_parameter("cover", alpha)
	m.material_override = mat
	m.position = at - parent.position + Vector3(0, (WALL_H + 2.0) * 0.5 - 0.5, 0)
	m.rotation.y = atan2(d.x, d.z)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	m.set_meta("along", along)
	return m

# ---- the combat chunk ---------------------------------------------------------------------

## A pathway point's floor height: the lane and banks (q.y), blended into the
## field's own surface over the BLEND_M metres next to a field (the seams match).
func _blend_field(q: Vector3, along: float, plen: float, start_field: Dictionary, end_field: Dictionary) -> float:
	var y := q.y
	if not end_field.is_empty():
		var w := smoothstep(BLEND_M, 0.0, plen - along)
		if w > 0.0: y = lerpf(y, field_world(end_field, q), w)
	if not start_field.is_empty():
		var w2 := smoothstep(BLEND_M, 0.0, along)
		if w2 > 0.0: y = lerpf(y, float(start_field.flat) if start_field.has("flat") else field_world(start_field, q), w2)
	return y + (0.035 if not start_field.is_empty() else 0.0)

## A chunk's contents in its own frame (x/z in [-30, 30], 0 = centre): the hills'
## phases and a few half-buried rocks [[x, z, w, d, h, yaw, kind]], clear of the
## entrance (south), the exit mouths (north) and the middle. Pure per seed.
static func chunk_layout(seed_in: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_in
	var phase := Vector3(r.randf_range(0, CHUNK), r.randf_range(0, CHUNK), r.randf_range(0, CHUNK))
	var clear := [[Vector2(0, HALF - 2.0), ENTRANCE_CLEAR], [Vector2.ZERO, CENTRE_CLEAR]]
	for d: Vector2i in EDGES: # an exit may open on any edge, in its middle or SAME_EDGE_OFFSET either side
		for off in [0.0, -SAME_EDGE_OFFSET, SAME_EDGE_OFFSET]:
			clear.append([Vector2(d) * (HALF - 2.0) + Vector2(absf(d.y), absf(d.x)) * off, EXIT_CLEAR])
	var rocks := []
	var want := r.randi_range(ROCKS.x, ROCKS.y)
	var tries := 0
	while rocks.size() < want and tries < 300:
		tries += 1
		var w := r.randf_range(1.4, 3.4)
		var dd := r.randf_range(1.2, 3.0)
		var h := r.randf_range(0.7, 2.0)
		var rad := Vector2(w, dd).length() * 0.5
		var pnt := Vector2(r.randf_range(-HALF + 3.0, HALF - 3.0), r.randf_range(-HALF + 3.0, HALF - 3.0))
		var ok := absf(pnt.x) < HALF - 2.0 - rad and absf(pnt.y) < HALF - 2.0 - rad
		for c in clear: if pnt.distance_to(c[0]) < float(c[1]) + rad: ok = false
		for o in rocks: if pnt.distance_to(Vector2(o[0], o[1])) < rad + 6.0: ok = false
		if ok: rocks.append([pnt.x, pnt.y, w, dd, h, r.randf_range(0, 180), r.randi() % 3])
	return {"seed": seed_in, "phase": phase, "trees": [], "rocks": rocks}

## The hills [layout pass §3]: layout.gd's two 60 m-periodic waves at HILL_K, a
## phase per chunk; the same at opposite edges (the wrap has no seam).
static func waves(phase: Vector3, x: float, z: float) -> float:
	var a := TAU / CHUNK
	return HILL_K * (3.8 * sin(a * (x + phase.x)) * cos(a * (z + phase.y)) + 2.1 * sin(a * (x - 2.0 * z + phase.z)))

static func wave_normal(phase: Vector3, x: float, z: float) -> Vector3:
	var a := TAU / CHUNK
	var dx := HILL_K * (3.8 * a * cos(a * (x + phase.x)) * cos(a * (z + phase.y)) + 2.1 * a * cos(a * (x - 2.0 * z + phase.z)))
	var dz := HILL_K * (-3.8 * a * sin(a * (x + phase.x)) * sin(a * (z + phase.y)) - 4.2 * a * cos(a * (x - 2.0 * z + phase.z)))
	return Vector3(-dx, 1.0, -dz).normalized()

## The field's height over its base, at a grid corner (the entrance's middle is 0).
static func grid_h(lay: Dictionary, x: float, z: float) -> float:
	return waves(lay.phase, x, z) - waves(lay.phase, 0.0, HALF)

## The field's height at local (x, z), on the same triangles as its mesh and collider.
static func field_h(lay: Dictionary, x: float, z: float) -> float:
	x = fposmod(x + HALF, CHUNK) - HALF
	z = fposmod(z + HALF, CHUNK) - HALF
	var gx := floorf((x + HALF) / FIELD_STEP) * FIELD_STEP - HALF
	var gz := floorf((z + HALF) / FIELD_STEP) * FIELD_STEP - HALF
	var fx := (x - gx) / FIELD_STEP
	var fz := (z - gz) / FIELD_STEP
	var g: PackedFloat32Array = _grid(lay)
	var n := int(CHUNK / FIELD_STEP) + 1
	var i := clampi(int(roundf((gx + HALF) / FIELD_STEP)), 0, n - 2)
	var j := clampi(int(roundf((gz + HALF) / FIELD_STEP)), 0, n - 2)
	var y00 := g[j * n + i]
	var y10 := g[j * n + i + 1]
	var y01 := g[(j + 1) * n + i]
	if fx + fz <= 1.0: return y00 + fx * (y10 - y00) + fz * (y01 - y00)
	var y11 := g[(j + 1) * n + i + 1]
	return y11 + (1.0 - fx) * (y01 - y11) + (1.0 - fz) * (y10 - y11)

## The grid corners' heights, computed once per layout (height_at runs for every
## nav waypoint and every actor each tick).
static func _grid(lay: Dictionary) -> PackedFloat32Array:
	if lay.has("grid"): return lay.grid
	var n := int(CHUNK / FIELD_STEP) + 1
	var g := PackedFloat32Array()
	g.resize(n * n)
	for j in n:
		for i in n: g[j * n + i] = grid_h(lay, -HALF + i * FIELD_STEP, -HALF + j * FIELD_STEP)
	lay.grid = g
	return g

## A field's world height at `q` ({layout, centre, base_y}: a chunk, or a chunk to be).
static func field_world(f: Dictionary, q: Vector3) -> float:
	return float(f.base_y) + field_h(f.layout, q.x - (f.centre as Vector3).x, q.z - (f.centre as Vector3).z)

## The field's lowest spots (local, on the ground), apart from each other: where the mist lies.
static func hollows_of(lay: Dictionary) -> Array:
	var pts := []
	var st := 4.0
	for i in int(CHUNK / st):
		for j in int(CHUNK / st):
			var x := -HALF + (i + 0.5) * st
			var z := -HALF + (j + 0.5) * st
			pts.append(Vector3(x, field_h(lay, x, z), z))
	pts.sort_custom(func(a, b): return a.y < b.y)
	var out := []
	for q in pts:
		var ok := true
		for o in out: if Vector2(o.x - q.x, o.z - q.z).length() < 12.0: ok = false
		if ok: out.append(q)
		if out.size() >= HOLLOWS: break
	return out

## How far a seal behind the player has got (0..1): the fog closes in meanwhile.
## The chunk's shared surface: one mesh and one collider shape for all 9 tiles.
static func field_surface(lay: Dictionary) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(CHUNK / FIELD_STEP)
	for i in n:
		for j in n:
			var x0 := -HALF + i * FIELD_STEP
			var z0 := -HALF + j * FIELD_STEP
			for q in [Vector2(0, 0), Vector2(FIELD_STEP, 0), Vector2(0, FIELD_STEP), Vector2(FIELD_STEP, 0), Vector2(FIELD_STEP, FIELD_STEP), Vector2(0, FIELD_STEP)]:
				var vx: float = x0 + q.x
				var vz: float = z0 + q.y
				var v := Vector3(vx, grid_h(lay, vx, vz), vz)
				st.set_normal(wave_normal(lay.phase, vx, vz)) # analytic: identical across the seams
				st.set_uv(Vector2(vx, vz) * 0.31)
				st.add_vertex(v)
	# The collider: the same triangles (a triangle mesh; under Jolt it is cheaper here
	# than a HeightMapShape3D, measured 1.5 vs 2.2 ms of actors per frame [perf]).
	var faces := PackedVector3Array()
	for i in n:
		for j in n:
			var x0 := -HALF + i * FIELD_STEP
			var z0 := -HALF + j * FIELD_STEP
			for q in [Vector2(0, 0), Vector2(FIELD_STEP, 0), Vector2(0, FIELD_STEP), Vector2(FIELD_STEP, 0), Vector2(FIELD_STEP, FIELD_STEP), Vector2(0, FIELD_STEP)]:
				faces.append(Vector3(x0 + q.x, grid_h(lay, x0 + q.x, z0 + q.y), z0 + q.y))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return {"mesh": st.commit(), "shape": shape}

## The field's grass draw distance: the setting's in a fight and on the way, a
## preset's PEACE_GRASS in a closed field (60 m visibility; no fight to pay for).
func set_grass_reach(m: float) -> void:
	if is_equal_approx(m, grass_reach): return
	grass_reach = m
	if _grass_material:
		_grass_material.set_shader_parameter("fade_start", m * 0.7)
		_grass_material.set_shader_parameter("fade_end", m)
	for c in [chunk, next_chunk, old_chunk]:
		if c.is_empty(): continue
		for k in c.tiles:
			var t: Node3D = c.tiles[k]
			if not is_instance_valid(t): continue
			for gi in t.find_children("Grass", "MultiMeshInstance3D", false, false): (gi as GeometryInstance3D).visibility_range_end = m + GRASS_CELL * 0.5

## A combat chunk whose entrance is at `entrance`, reached heading `dir`: closed in
## bamboo (open only where the pathway arrives) until its fight starts.
func _build_chunk(entrance: Vector3, lay := {}, dir := Vector2i(0, -1)) -> Dictionary:
	chunks_built += 1
	if lay.is_empty(): lay = chunk_layout(seed_value * 31 + chunks_built)
	var c := {"centre": entrance + Vector3(dir.x, 0, dir.y) * HALF, "base_y": entrance.y, "layout": lay, "tiles": {}, "tile": Vector2i.ZERO,
		"wrap": false, "entry": -dir, "index": chunks_built, "entered": false, "border": null, "edge_solids": []}
	c.centre.y = entrance.y
	c.surface = field_surface(lay)
	c.grass = _field_grass(lay)
	c.hollows = hollows_of(lay)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var t := _build_tile(c, "Chunk%d_tile_%d_%d" % [c.index, dx + 1, dz + 1])
			c.tiles[Vector2i(dx, dz)] = t
	_place_tiles(c)
	c.border = _build_border(c, [[c.entry, 0.0]])
	log_lines.append("chunk %d at (%.0f, %.0f)" % [c.index, c.centre.x, c.centre.z])
	return c

## The field's grass: GRASS_CELL cells of BinbunGrass cards over the whole surface
## (none inside a rock), built once and shared by the 9 tiles.
func _field_grass(lay: Dictionary) -> Dictionary:
	var out := {}
	var GrassField = load("res://scripts/world/grass_field.gd")
	if not GrassField.available(): return out
	_grass(self, [Vector3.ZERO], "_probe").free() # builds the shared card and material
	var g := RandomNumberGenerator.new()
	g.seed = int(lay.seed) * 7 + 3
	var cells := int(CHUNK / GRASS_CELL)
	for cx in cells:
		for cz in cells:
			var xs := []
			for k in int(GRASS_CELL * GRASS_CELL * FIELD_GRASS):
				var x := -HALF + (cx + g.randf()) * GRASS_CELL
				var z := -HALF + (cz + g.randf()) * GRASS_CELL
				var inside := false
				for rk in lay.rocks:
					if Vector2(x - float(rk[0]), z - float(rk[1])).length() < minf(float(rk[2]), float(rk[3])) * 0.45: inside = true
				if inside: continue
				var sc := g.randf_range(0.8, 1.3)
				xs.append(Transform3D(Basis(Vector3.UP, g.randf() * TAU).scaled(Vector3.ONE * sc), Vector3(x, field_h(lay, x, z), z)))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _grass_card
			mm.instance_count = xs.size()
			for i in xs.size(): mm.set_instance_transform(i, xs[i])
			out[Vector2i(cx, cz)] = mm
	return out

static var _rock_mats := {}
func _build_tile(c: Dictionary, nm: String) -> Node3D:
	var tile := Node3D.new()
	tile.name = nm
	add_child(tile)
	var lay: Dictionary = c.layout
	var solids := []
	var floor_body := StaticBody3D.new()
	floor_body.name = "floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var fcs := CollisionShape3D.new()
	fcs.shape = c.surface.shape
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	fm.name = "Ground"
	fm.mesh = c.surface.mesh
	fm.material_override = ground_mat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_body.add_child(fm)
	tile.add_child(floor_body)
	var GrassField = load("res://scripts/world/grass_field.gd")
	for key in c.grass:
		var gi := MultiMeshInstance3D.new()
		gi.name = "Grass"
		gi.multimesh = c.grass[key]
		gi.material_override = _grass_material
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = grass_reach + GRASS_CELL * 0.5 # past the blades' own fade: not drawn at all [perf trim: far grass]
		tile.add_child(gi)
	# Rocks: kit rocks half-buried in the slope, tinted moss and soil; a box collider
	# over the visible part (Mortus stuns on them; they stop arrows).
	for i in lay.rocks.size():
		var rk: Array = lay.rocks[i]
		var gy := field_h(lay, float(rk[0]), float(rk[1]))
		var low := minf(minf(field_h(lay, float(rk[0]) - float(rk[2]) * 0.5, float(rk[1])), field_h(lay, float(rk[0]) + float(rk[2]) * 0.5, float(rk[1]))), minf(field_h(lay, float(rk[0]), float(rk[1]) - float(rk[3]) * 0.5), field_h(lay, float(rk[0]), float(rk[1]) + float(rk[3]) * 0.5)))
		var top := gy + float(rk[4])
		var box := DarkForest._box(tile, Vector3(rk[0], (low + top) * 0.5, rk[1]), Vector3(float(rk[2]) * 0.9, top - low, float(rk[3]) * 0.9), DarkForest.material("rock"), "rock_%d" % i, solids, true, rk[5])
		for v in box.find_children("*", "MeshInstance3D", true, false): (v as MeshInstance3D).visible = false
		var kind: String = DarkForest.ROCK_KINDS[int(rk[6]) % DarkForest.ROCK_KINDS.size()]
		var e: Array = DarkForest._kit(kind)
		if e.is_empty():
			for v in box.find_children("*", "MeshInstance3D", true, false): (v as MeshInstance3D).visible = true
			continue
		var aabb: AABB = (e[0][1] as Transform3D) * (e[0][0] as Mesh).get_aabb()
		var full_h := float(rk[4]) * 2.0 # half of it under the ground
		var sc := Vector3(float(rk[2]) / maxf(aabb.size.x, 0.1), full_h / maxf(aabb.size.y, 0.1), float(rk[3]) / maxf(aabb.size.z, 0.1))
		var mi := MeshInstance3D.new()
		mi.name = "kit_rock_%d" % i
		mi.mesh = e[0][0]
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(rk[5]))).scaled(sc), Vector3(rk[0], gy - float(rk[4]) - aabb.position.y * sc.y, rk[1])) * (e[0][1] as Transform3D)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for si in (e[0][0] as Mesh).get_surface_count():
			var src := (e[0][0] as Mesh).surface_get_material(si) as BaseMaterial3D
			if src == null: continue
			if not _rock_mats.has(src):
				var t: BaseMaterial3D = src.duplicate()
				t.albedo_color = src.albedo_color * Color(0.58, 0.64, 0.52) # moss and soil, toward the palette
				t.roughness = 1.0
				_rock_mats[src] = t
			mi.set_surface_override_material(si, _rock_mats[src])
		tile.add_child(mi)
	# Low mist in the hollows [layout pass §4]: patches at several angles, faded at every edge.
	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = load(MIST_SHADER)
	for hp in c.hollows:
		for k in 2:
			var mm_i := MeshInstance3D.new()
			mm_i.name = "Mist"
			var qm := QuadMesh.new()
			qm.size = Vector2(11.0, 2.4)
			qm.center_offset = Vector3(0, 1.0, 0)
			mm_i.mesh = qm
			mm_i.material_override = mist_mat
			mm_i.position = hp
			mm_i.rotation.y = float(k) * 1.7 + hp.x * 0.13
			mm_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mm_i.visibility_range_end = ArtDirection.FOG_END + 4.0
			tile.add_child(mm_i)
	tile.set_meta("solids", solids) # in the tile's own frame (y from the chunk's base)
	return tile

## Moves the tiles round the chunk's current tile: all nine while it wraps (combat),
## only its own when it is closed in bamboo (before and after a fight).
func _place_tiles(c: Dictionary) -> void:
	for k in c.tiles:
		var tile: Node3D = c.tiles[k]
		var cell: Vector2i = c.tile + k
		tile.position = Vector3(c.centre.x + cell.x * CHUNK, c.base_y, c.centre.z + cell.y * CHUNK)
		_tile_on(tile, c.wrap or k == Vector2i.ZERO)

func _tile_on(tile: Node3D, on: bool) -> void:
	tile.visible = on
	tile.set_meta("on", on)
	for b in tile.find_children("*", "StaticBody3D", true, false):
		for cs in b.get_children():
			if cs is CollisionShape3D: (cs as CollisionShape3D).disabled = not on

func _free_chunk(c: Dictionary) -> void:
	if c.is_empty(): return
	if is_instance_valid(c.get("border")): c.border.free()
	for k in c.tiles:
		if is_instance_valid(c.tiles[k]): c.tiles[k].free()
	c.tiles = {}

## The chunk's tile holding `p` (in chunk cells; 0,0 = the chunk itself).
static func tile_of(c: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - c.centre.x + HALF) / CHUNK), floori((p.z - c.centre.z + HALF) / CHUNK))

func in_chunk(c: Dictionary, p: Vector3) -> bool:
	if c.is_empty(): return false
	var k: Vector2i = tile_of(c, p) - (c.tile as Vector2i)
	if c.wrap: return absi(k.x) <= 1 and absi(k.y) <= 1
	return k == Vector2i.ZERO

# ---- the frame: where the player is -----------------------------------------------------

## The region at `p`: "camp", "pathway" (with {pathway}), "chunk", or "".
func region_of(p: Vector3) -> Dictionary:
	if not chunk.is_empty() and in_chunk(chunk, p): return {"kind": "chunk", "chunk": chunk}
	for pw in pathways:
		if not is_instance_valid(pw.node): continue
		var pr := path_project(pw.pts, p)
		if float(pr.gap) <= BAMBOO_OFF and float(pr.along) > 0.0 and float(pr.along) < float(pw.length) - 0.01: return {"kind": "pathway", "pathway": pw, "along": pr.along}
	if not next_chunk.is_empty() and in_chunk(next_chunk, p): return {"kind": "chunk", "chunk": next_chunk}
	if not old_chunk.is_empty() and in_chunk(old_chunk, p): return {"kind": "chunk", "chunk": old_chunk}
	if camp_loaded and p.x >= CAMP_BOX[0].x - 2 and p.x <= CAMP_BOX[1].x + 2 and p.z >= CAMP_BOX[0].y - 1 and p.z <= CAMP_BOX[1].y + 2: return {"kind": "camp"}
	return {"kind": ""}

## The ground height under `p` (x/z): the nav grid's and the spawner's surface.
func height_at(p: Vector2) -> float:
	var q := Vector3(p.x, 0, p.y)
	for c in [chunk, next_chunk]:
		if not c.is_empty() and in_chunk(c, q): return field_world(c, q)
	for pw in pathways:
		if not is_instance_valid(pw.node): continue
		var pr := path_project(pw.pts, q)
		if float(pr.gap) <= BAMBOO_OFF + 2.5:
			var lat := float(pr.gap)
			return _blend_field(Vector3(q.x, float(pr.y) + bank(lat), q.z), float(pr.along), float(pw.length), pw.start_field, pw.end_field)
	if not old_chunk.is_empty() and in_chunk(old_chunk, q): return field_world(old_chunk, q)
	if not chunk.is_empty(): return field_world(chunk, q)
	return 0.0

## One frame of the map: entering pathways and chunks, unloading what lies behind
## (past the visibility), the wrap. Returns events for main.gd: {event:
## entered_pathway (pathway) | exit_taken | camp_sealed | sealed | entered_chunk |
## wrap_shift (shift)}.
func update(p: Vector3, dt: float) -> Array:
	var out := []
	var reg := region_of(p)
	if camp_loaded:
		var sky_mat: ShaderMaterial = town.get_node("ValleySky").material_override
		var town_visibility: float = smoothstep(30.0, CAMP_FOG_END, vis_now)
		sky_mat.set_shader_parameter("amount", town_visibility)
		(town.get_node("TownGlow") as OmniLight3D).light_energy = 4.0 * town_visibility
		if _window_mat:
			_window_mat.emission_energy_multiplier = 3.2 * town_visibility
	if reg.kind == "pathway":
		var pw: Dictionary = reg.pathway
		if not pw.entered:
			pw.entered = true
			if pw.get("exit", false) and not chunk.is_empty():
				_take_exit(pw)
				out.append({"event": "exit_taken", "pathway": pw})
			else:
				out.append({"event": "entered_pathway", "pathway": pw})
		if float(reg.along) >= UNLOAD_M and not pw.sealed:
			if String(pw.from) == "camp" and camp_loaded:
				_seal(pw, 2.0, true)
				_unload_camp()
				out.append({"event": "camp_sealed"})
			elif pw.get("taken", false) and not old_chunk.is_empty():
				_seal(pw, 2.0, false)
				_unload_behind(pw)
				out.append({"event": "sealed"})
	if reg.kind == "chunk" and reg.chunk == next_chunk and not next_chunk.is_empty():
		if not old_chunk.is_empty(): _unload_behind({})
		chunk = next_chunk
		next_chunk = {}
		chunk.entered = true
		out.append({"event": "entered_chunk"})
	if not chunk.is_empty() and chunk.wrap:
		var t := tile_of(chunk, p)
		if t != chunk.tile:
			var shift: Vector2i = t - (chunk.tile as Vector2i)
			chunk.tile = t
			_place_tiles(chunk)
			out.append({"event": "wrap_shift", "shift": shift}) # the same obstacles, one field over: the nav grids just move
	return out

## The field and the exits left behind (and any exit not taken), once out of sight.
func _unload_behind(taken: Dictionary) -> void:
	_free_chunk(old_chunk)
	old_chunk = {}
	for pw in pathways.duplicate():
		if pw == taken or not pw.get("exit", false): continue
		if is_instance_valid(pw.node): pw.node.free()
		pathways.erase(pw)
	log_lines.append("the field behind unloaded")

func _seal(pw: Dictionary, along: float, camp_side: bool) -> void:
	pw.sealed = true
	var at := path_point(pw.pts, along)
	var ahead := path_point(pw.pts, along + 0.5)
	var d := Vector3(ahead.x - at.x, 0, ahead.z - at.z).normalized()
	var n := Vector3(-d.z, 0, d.x)
	var wall_solids := []
	_wall(pw.node, at - pw.node.position - n * (WALL_OFF + 0.4), at - pw.node.position + n * (WALL_OFF + 0.4), wall_solids, "no_return" if camp_side else "seal_wall")
	for box: AABB in wall_solids: pw.solids.append(AABB(box.position + pw.node.position, box.size))
	var bank_mesh := MeshInstance3D.new()
	var mound := SphereMesh.new()
	mound.radial_segments = 16
	mound.rings = 6
	bank_mesh.mesh = mound
	bank_mesh.material_override = ground_mat
	bank_mesh.position = at - pw.node.position - d * 5.0 - Vector3.UP * 0.8
	bank_mesh.scale = Vector3(22, 5, 7)
	bank_mesh.rotation.y = atan2(d.x, d.z)
	pw.node.add_child(bank_mesh)
	var closure := []
	for i in 160:
		var behind := at - d * rng.randf_range(0.9, 3.2) + n * rng.randf_range(-6.0, 6.0)
		closure.append([behind - pw.node.position - Vector3.UP * 0.6, rng.randf_range(0.3, 0.9)])
	_culms(pw.node, closure, "ClosedThicket")
	log_lines.append("pathway %d sealed at %.0f m" % [pw.index, along])

func _unload_camp() -> void:
	camp_loaded = false
	for n in [camp, town]:
		if n != null and is_instance_valid(n): n.free()
	camp = null
	town = null
	var fire: Node3D = get_node_or_null("CampFire")
	if fire: fire.visible = false

	log_lines.append("camp unloaded")

## The combat-start blackout's swap [plan-map1-visibility]: the border and every
## pathway (the entrance, or a cooldown's exits) go; the field wraps round.
func start_combat() -> void:
	if chunk.is_empty(): return
	if is_instance_valid(chunk.get("border")): chunk.border.free()
	chunk.border = null
	chunk.edge_solids = []
	for pw in pathways: if is_instance_valid(pw.node): pw.node.free()
	pathways = []
	chunk.entry = Vector2i.ZERO
	chunk.wrap = true
	_place_tiles(chunk)
	log_lines.append("combat: the field opens")

## The combat-end blackout's swap: the field closes round the tile the player is on,
## in bamboo with `count` exits on random edges (a pathway heading straight out of
## each). Returns the tile's middle, where main puts the player.
func end_combat(p: Vector3, count: int) -> Vector3:
	var c := chunk
	c.tile = tile_of(c, p)
	c.wrap = false
	c.entry = Vector2i.ZERO
	_place_tiles(c)
	var tc: Vector3 = c.centre + Vector3(c.tile.x * CHUNK, 0, c.tile.y * CHUNK)
	var field := {"layout": c.layout, "centre": c.centre, "base_y": c.base_y}
	var edges := []
	for i in count: edges.append(EDGES[rng.randi() % EDGES.size()])
	var same: bool = count == 2 and edges[0] == edges[1]
	var gaps := []
	for i in count:
		var d: Vector2i = edges[i]
		var along_edge := Vector3(absf(d.y), 0, absf(d.x))
		var off: float = (SAME_EDGE_OFFSET * (-1.0 if i == 0 else 1.0)) if same else 0.0
		var flip := 1 if d == Vector2i(0, -1) or d == Vector2i(1, 0) else -1 # the pathway's own right is +along_edge heading N or E
		var lean: int = int(signf(off)) * flip if same else 0
		var start: Vector3 = tc + Vector3(d.x, 0, d.y) * HALF + along_edge * off
		start.y = field_world(field, start)
		var lay := chunk_layout(seed_value * 31 + chunks_built + 1 + i * 7)
		var pw := _build_pathway(start, pathway_length_draw(), c.index * 10 + i, "chunk", field, lay, d, lean)
		pw.lay = lay
		pw.exit = true
		gaps.append([d, off])
	if is_instance_valid(c.get("border")): c.border.free()
	c.border = _build_border(c, gaps)
	var at := tc
	at.y = field_world(field, tc)
	log_lines.append("combat over: %d exit(s) on %s" % [count, str(edges)])
	return at

## An exit's pathway is entered: the field behind stops being the chunk (it stays
## loaded, unseen beyond the fog, until UNLOAD_M in); the next chunk is built at the
## pathway's end; any other exit is walled off (invisibly: it is still in view).
func _take_exit(pw: Dictionary) -> void:
	pw.taken = true
	for o in pathways:
		if o == pw or not o.get("exit", false) or not is_instance_valid(o.node): continue
		var a: Vector3 = o.pts[0]
		var b: Vector3 = path_point(o.pts, 0.6)
		var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var n := Vector3(-d.z, 0, d.x)
		_wall(o.node, b - n * (WALL_OFF + 0.4), b + n * (WALL_OFF + 0.4), o.solids, "exit_closed")
	old_chunk = chunk
	chunk = {}
	next_chunk = _build_chunk(pw.pts.back(), pw.lay, pw.dir)
	log_lines.append("exit taken toward %s" % str(pw.dir))

## A closed field's border: on every edge a wall (open only at the gaps, [edge,
## offset] pairs, as wide as a pathway's lane) and, beyond it, a treeline on a strip
## of ground that follows the hills (open as wide as a pathway's floor).
func _build_border(c: Dictionary, gaps: Array) -> Node3D:
	var node := Node3D.new()
	node.name = "Border"
	add_child(node)
	c.edge_solids = []
	var tc: Vector3 = c.centre + Vector3(c.tile.x * CHUNK, 0, c.tile.y * CHUNK)
	var f := {"layout": c.layout, "centre": c.centre, "base_y": c.base_y}
	var lane := FLOOR_HALF
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	var stems := []
	var names := {Vector2i(0, -1): "n", Vector2i(1, 0): "e", Vector2i(0, 1): "s", Vector2i(-1, 0): "w"}
	# The pathways that meet this field (one end on its edge): the treeline closes up to their
	# bamboo and the strip of ground stops under their floor, following their real centrelines.
	var attached: Array = []
	for pw in pathways:
		if not is_instance_valid(pw.node): continue
		for end in [pw.pts[0], pw.pts[pw.pts.size() - 1]]:
			var rel: Vector3 = (end as Vector3) - tc
			if absf(maxf(absf(rel.x), absf(rel.z)) - HALF) < 1.0: attached.append(pw.pts)
	var clear_of := func(q: Vector3, gap: float) -> bool:
		for pts in attached:
			if float(path_project(pts, q).gap) < gap: return false
		return true
	for d: Vector2i in EDGES:
		var out_dir := Vector3(d.x, 0, d.y)
		var along_edge := Vector3(absf(d.y), 0, absf(d.x))
		var offs: Array = []
		for g in gaps: if g[0] == d: offs.append(float(g[1]))
		var span := HALF + EDGE_DEPTH if d.y != 0 else HALF # the north and south strips cover the corners
		var k := 0
		for seg in _open_segments(-HALF, HALF, offs, WALL_OFF):
			var a := _edge_point(f, tc, along_edge, out_dir, seg.x, 0.3)
			var b := _edge_point(f, tc, along_edge, out_dir, seg.y, 0.3)
			_wall(node, a, b, c.edge_solids, "field_edge_%s_%d" % [names[d], k])
			k += 1
		for seg in [Vector2(-span, span)]:
			var u: float = seg.x
			while u < seg.y - 0.01:
				var u1 := minf(u + FIELD_STEP, seg.y)
				var q := [_edge_point(f, tc, along_edge, out_dir, u, 0.0), _edge_point(f, tc, along_edge, out_dir, u1, 0.0),
					_edge_point(f, tc, along_edge, out_dir, u1, EDGE_DEPTH), _edge_point(f, tc, along_edge, out_dir, u, EDGE_DEPTH)]
				if not clear_of.call(_edge_point(f, tc, along_edge, out_dir, (u + u1) * 0.5, EDGE_DEPTH * 0.5), lane - 0.5): # a pathway's floor is there
					u = u1
					continue
				var fall_a := _edge_point(f, tc, along_edge, out_dir, u1, EDGE_DEPTH + 3.0) - Vector3(0, FALL_OFF, 0)
				var fall_b := _edge_point(f, tc, along_edge, out_dir, u, EDGE_DEPTH + 3.0) - Vector3(0, FALL_OFF, 0)
				q.append(fall_a)
				q.append(fall_b)
				for tri in [[0, 1, 2], [0, 2, 3], [3, 2, 4], [3, 4, 5]]: # the strip, then its outer edge sloping into the earth
					var t0: Vector3 = q[tri[0]]
					var t1: Vector3 = q[tri[1]]
					var t2: Vector3 = q[tri[2]]
					if (t1 - t0).cross(t2 - t0).y > 0.0: # face up (Godot's front faces wind clockwise)
						var sw := t1
						t1 = t2
						t2 = sw
					for v in [t0, t1, t2]:
						st.set_uv(Vector2(v.x, v.z) * 0.25)
						st.add_vertex(v)
					faces += 1
				u = u1
			var us: float = seg.x
			while us < seg.y:
				for i in 4:
					var sp := _edge_point(f, tc, along_edge, out_dir, us + rng.randf_range(-0.3, 0.3), rng.randf_range(0.6, EDGE_DEPTH - 0.5))
					if not clear_of.call(sp, CULM_IN): continue # in a pathway's lane
					sp.y -= 0.3
					stems.append([sp, rng.randf()])
				us += 0.6
	if faces > 0: _path_surface(node, st)
	_culms(node, stems, "Treeline")
	return node

## A point by a field's edge: `u` along it, `v` out from it, on the field's hills.
static func _edge_point(f: Dictionary, tc: Vector3, along_edge: Vector3, out_dir: Vector3, u: float, v: float) -> Vector3:
	var q: Vector3 = tc + along_edge * u + out_dir * (HALF + v)
	q.y = field_world(f, q)
	return q

## [lo, hi] with a gap of half-width `gap` round each offset: the open stretches.
static func _open_segments(lo: float, hi: float, offs: Array, gap: float) -> Array:
	var out: Array = []
	var cur := lo
	var sorted := offs.duplicate()
	sorted.sort()
	for o in sorted:
		if float(o) - gap > cur: out.append(Vector2(cur, float(o) - gap))
		cur = maxf(cur, float(o) + gap)
	if cur < hi: out.append(Vector2(cur, hi))
	return out

## Tests and the performance suite: straight into the first combat chunk, wrapped
## round, the camp and the pathways unloaded (as after a combat start).
func skip_to_field() -> void:
	if chunk.is_empty():
		chunk = next_chunk
		next_chunk = {}
	if camp_loaded: _unload_camp()
	chunk.entered = true
	start_combat()

# ---- nav and spawns ------------------------------------------------------------------------

## Every loaded solid as a world AABB (the nav grids).
func solids() -> Array:
	var out := camp_solids.duplicate() if camp_loaded else []
	for pw in pathways: if is_instance_valid(pw.node): out.append_array(pw.solids)
	for c in [chunk, next_chunk, old_chunk]:
		if c.is_empty(): continue
		out.append_array(c.get("edge_solids", []))
		for k in c.tiles:
			var tile: Node3D = c.tiles[k]
			if not is_instance_valid(tile) or not tile.get_meta("on", false): continue
			for b in tile.get_meta("solids"):
				var bb: AABB = b
				out.append(AABB(bb.position + tile.position, bb.size))
	return out

## The nav grid's extent: everything loaded, with a margin.
func nav_bounds() -> Array:
	var pts: Array[Vector2] = []
	if camp_loaded:
		pts.append(CAMP_BOX[0])
		pts.append(CAMP_BOX[1])
	for pw in pathways:
		if not is_instance_valid(pw.node): continue
		for q in pw.pts: pts.append(Vector2(q.x, q.z))
	for c in [chunk, next_chunk, old_chunk]:
		if c.is_empty(): continue
		for k in c.tiles:
			var tile: Node3D = c.tiles[k]
			if not is_instance_valid(tile) or not tile.get_meta("on", false): continue
			pts.append(Vector2(tile.position.x - HALF, tile.position.z - HALF))
			pts.append(Vector2(tile.position.x + HALF, tile.position.z + HALF))
	if pts.is_empty(): return [Vector2(CAMP_BOX[0]), Vector2(CAMP_BOX[1])]
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts: r = r.expand(q)
	return [r.position - Vector2(6, 6), r.end + Vector2(6, 6)]

## The player's visibility (the fog's opaque distance, m) at `p` [plan-map1-visibility]:
## the camp 30, a pathway 20 (reached RAMP_M in), a closed field 60 (likewise), and
## the rules' blackouts and combat while a fight starts, runs or ends.
func visibility_at(p: Vector3, rules: RefCounted) -> float:
	var V: Dictionary = Map1Rules.VIS
	var reg := region_of(p)
	var timed: float = rules.timed_visibility() if rules != null else -1.0
	if reg.kind == "chunk" and reg.chunk == chunk and timed >= 0.0: return timed
	match String(reg.kind):
		"camp": return float(V.camp)
		"pathway":
			var from: float = float(V.camp) if String(reg.pathway.from) == "camp" else float(V.peace)
			return lerpf(from, float(V.pathway), clampf(float(reg.along) / Map1Rules.RAMP_M, 0.0, 1.0))
		"chunk":
			if reg.chunk.wrap: return float(V.combat)
			return lerpf(float(V.pathway), float(V.peace), clampf(depth_into(reg.chunk, p) / Map1Rules.RAMP_M, 0.0, 1.0))
	return float(V.pathway)

## How far `p` is past a closed chunk's entrance edge (very far when it has none).
func depth_into(c: Dictionary, p: Vector3) -> float:
	var e: Vector2i = c.get("entry", Vector2i.ZERO)
	if e == Vector2i.ZERO: return 1.0e9
	var tc: Vector3 = c.centre + Vector3(c.tile.x * CHUNK, 0, c.tile.y * CHUNK)
	return HALF - (p - tc).dot(Vector3(e.x, 0, e.y))

## The player is in the current chunk and RAMP_M past its entrance (full visibility):
## the rules may start a fight.
func settled(p: Vector3) -> bool:
	if chunk.is_empty() or not in_chunk(chunk, p): return false
	return chunk.wrap or depth_into(chunk, p) >= Map1Rules.RAMP_M

