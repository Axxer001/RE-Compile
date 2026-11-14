extends RefCounted
# The Dark Forest (Grimoire MVP P7, handoff §7 and Sir's R11): the game world.
# A 150 x 150 m forest. Fixed and hand-made: the clearing network and the
# paths between clearings, the start camp with its lit fire, the ground,
# the boundary and the moon. Drawn fresh from a seed on every run (R11): the
# trees (positions and density; trunks and crowns as two MultiMeshes, a
# cylinder collider each), the rocks and mantle ledges, the 3 page spots and
# the 6 Sprite spawn zones. generate(seed) is pure data (same seed, same
# map); rule_violations() checks a map against R11's rules; build() makes the
# fixed part once and scatter() makes a generated map under it. Every solid is
# returned as a world AABB for the navigation grid. World axes: +X east, +Z
# south (the camp is in the south), +Y up; metres.
# The movement arena (greybox.gd) stays for the movement tests.

const SIZE := Vector2(150, 150)
const BOUNDS := [Vector2(0, 0), Vector2(150, 150)]
const WALL_H := 10.0             # invisible boundary, behind the tree line

# Clearings [centre x, centre z, radius]: index 0 is the camp.
const CLEARINGS := [
	[75.0, 130.0, 14.0],  # 0 camp
	[75.0, 95.0, 15.0],   # 1 the crossing
	[35.0, 80.0, 14.0],   # 2 west hollow
	[115.0, 76.0, 14.0],  # 3 east hollow
	[75.0, 58.0, 13.0],   # 4 the stones
	[45.0, 38.0, 15.0],   # 5 north-west glade
	[108.0, 32.0, 15.0],  # 6 north-east glade
]
# Paths between clearings (indices), 8 m wide, along the centre-to-centre line.
const PATHS := [[0, 1], [1, 2], [1, 3], [1, 4], [4, 5], [4, 6], [2, 5], [3, 6]]
const PATH_HALF_W := 4.0
const TREE_CLEAR := 1.2          # trees stay this far outside a clearing or path

const SPAWN := {"at": Vector3(75, 0, 134), "yaw": 0.0} # the camp, facing north up the path
const CAMPFIRE := Vector3(75, 0, 129)
const CAMP := 0

# R11 rules (handoff §10).
const PAGE_MIN_FROM_START := 25.0
const PAGE_MIN_APART := 20.0
const PAGE_MIN_FROM_ZONE := 15.0
const CENTRELINE_CLEAR := 3.0    # no tree, rock or spawn zone this close to a path centreline
const ZONE_MIN_FROM_START := 30.0 # [design] none aggroes at the start (16 m) or comes out on top of it
const ZONE_MIN_APART := 8.0      # [design]
const ZONE_COUNT := 6
# Which clearings each page may lie in: Quick Step the nearest beyond the camp
# ("near the start" [§7], still >= 25 m [R11]); the others deeper in.
const PAGE_CLEARINGS := {"quick_step": [1], "ring_of_fire": [2, 4, 5], "sage_arts": [3, 4, 6]}
const LEDGE_TOPS := [1.0, 2.0, 3.0] # always one each: mantle tech [§7]
const AGENT_MARGIN := 0.6        # a walker's radius plus a little, round every obstacle

static var _mats := {}

static func material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind): return _mats[kind]
	var m := StandardMaterial3D.new()
	m.roughness = 0.95
	match kind:
		"ground": m.albedo_color = Color(0.16, 0.19, 0.13)
		"path": m.albedo_color = Color(0.24, 0.21, 0.16)
		"trunk": m.albedo_color = Color(0.22, 0.17, 0.13)
		"crown": m.albedo_color = Color(0.09, 0.16, 0.11)
		"rock": m.albedo_color = Color(0.36, 0.37, 0.38)
		"ledge": m.albedo_color = Color(0.3, 0.32, 0.33)
		"log": m.albedo_color = Color(0.3, 0.2, 0.12)
		"ember":
			m.albedo_color = Color(1.0, 0.5, 0.15)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.45, 0.1)
			m.emission_energy_multiplier = 4.0
		_: m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[kind] = m
	return m

# ---- geometry helpers (pure) ----------------------------------------------------------

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * u)

static func _closest_on(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return a + ab * u

static func _centre(i: int) -> Vector2:
	return Vector2(CLEARINGS[i][0], CLEARINGS[i][1])

# Distance to the nearest path centreline, and the point on it.
static func centreline_dist(p: Vector2) -> float:
	var best := INF
	for pa in PATHS: best = minf(best, _seg_dist(p, _centre(pa[0]), _centre(pa[1])))
	return best

static func centreline_point(p: Vector2) -> Vector2:
	var best := INF
	var out := p
	for pa in PATHS:
		var q := _closest_on(p, _centre(pa[0]), _centre(pa[1]))
		if q.distance_to(p) < best:
			best = q.distance_to(p)
			out = q
	return out

# True when a point is in a clearing or on a path (no trees there).
static func is_open(p: Vector2, margin := 0.0) -> bool:
	for c in CLEARINGS:
		if p.distance_to(Vector2(c[0], c[1])) <= float(c[2]) + margin: return true
	return centreline_dist(p) <= PATH_HALF_W + margin

static func in_camp(p: Vector2, margin := 0.0) -> bool:
	return p.distance_to(_centre(CAMP)) <= float(CLEARINGS[CAMP][2]) + margin

# Which clearing a point is in (-1 = in the trees or on a path).
static func clearing_at(p: Vector3) -> int:
	for i in CLEARINGS.size():
		var c: Array = CLEARINGS[i]
		if Vector2(p.x, p.z).distance_to(Vector2(c[0], c[1])) <= float(c[2]): return i
	return -1

# A footprint's half-diagonal: a box of w x d turned any way fits in this circle.
static func _reach(w: float, d: float) -> float:
	return Vector2(w, d).length() * 0.5

# Obstacles (rocks and ledges) as circles [centre, radius] for the rule checks.
static func obstacles(layout: Dictionary) -> Array:
	var out := []
	for r in layout.rocks: out.append([Vector2(r[0], r[1]), _reach(r[2], r[3])])
	for l in layout.ledges: out.append([Vector2(l[0], l[1]), _reach(l[2], l[3])])
	return out

# ---- generation (pure data, deterministic per seed) -------------------------------------

# A point inside clearing `ci`, at most `inset` from its edge.
static func _in_clearing(rng: RandomNumberGenerator, ci: int, inset: float) -> Vector2:
	var c: Array = CLEARINGS[ci]
	var r := sqrt(rng.randf()) * maxf(0.5, float(c[2]) - inset)
	var a := rng.randf() * TAU
	return Vector2(c[0], c[1]) + Vector2(cos(a), sin(a)) * r

static func _clear_of(p: Vector2, obs: Array, gap: float) -> bool:
	for o in obs:
		if p.distance_to(o[0]) < float(o[1]) + gap: return false
	return true

# The whole generated part of a map for `seed`: {seed, step, trees: [[x, z, r, h]],
# rocks: [[x, z, w, d, h, yaw]], ledges: [[x, z, w, d, top]], pages: {id: Vector3},
# zones: [{id, at, yaw}]}. A draw that breaks a rule is redrawn from the same
# generator, so the result is still one fixed map per seed.
static func generate(seed: int, attempts := 50) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for attempt in attempts:
		var layout := _draw(rng, seed)
		if rule_violations(layout).is_empty(): return layout
	push_warning("DarkForest: seed %d gave no valid map in %d draws" % [seed, attempts])
	return {}

static func _draw(rng: RandomNumberGenerator, seed: int) -> Dictionary:
	var layout := {"seed": seed, "step": rng.randf_range(4.0, 5.2), "trees": [], "rocks": [], "ledges": [], "pages": {}, "zones": []}
	var obs := []
	var wild := range(1, CLEARINGS.size()) # every clearing but the camp
	# Ledges: one each of 1 / 2 / 3 m together in one clearing (a mantle course), plus a few loose ones.
	var course: int = wild[rng.randi() % wild.size()]
	for top in LEDGE_TOPS + [rng.randf_range(1.4, 2.6), rng.randf_range(1.4, 2.6)]:
		var w := rng.randf_range(2.5, 4.0)
		var d := rng.randf_range(2.5, 4.0)
		var ci: int = course if top in LEDGE_TOPS else wild[rng.randi() % wild.size()]
		var at := _place(rng, ci, _reach(w, d), obs)
		if at.x == INF: continue
		layout.ledges.append([at.x, at.y, w, d, float(top)])
		obs.append([at, _reach(w, d)])
	# Rocks: low cover, one or two per clearing.
	for ci in wild:
		for k in 1 + rng.randi() % 2:
			var w := rng.randf_range(1.2, 2.6)
			var d := rng.randf_range(1.0, 2.0)
			var at := _place(rng, ci, _reach(w, d), obs)
			if at.x == INF: continue
			layout.rocks.append([at.x, at.y, w, d, rng.randf_range(0.6, 1.2), rng.randf_range(-60.0, 60.0)])
			obs.append([at, _reach(w, d)])
	# Pages, from candidate spots in their clearings.
	for id in ["quick_step", "ring_of_fire", "sage_arts"]:
		var opts: Array = PAGE_CLEARINGS[id].duplicate()
		for tries in 60:
			var ci: int = opts[rng.randi() % opts.size()]
			var pt := _in_clearing(rng, ci, 1.5)
			if pt.distance_to(Vector2(SPAWN.at.x, SPAWN.at.z)) < PAGE_MIN_FROM_START: continue
			if not _clear_of(pt, obs, AGENT_MARGIN + 0.6): continue
			var near := false
			for other in layout.pages.values():
				if pt.distance_to(Vector2(other.x, other.z)) < PAGE_MIN_APART: near = true
			if near: continue
			layout.pages[id] = Vector3(pt.x, 0, pt.y)
			break
	# Spawn zones.
	for tries in 400:
		if layout.zones.size() >= ZONE_COUNT: break
		var ci: int = wild[rng.randi() % wild.size()]
		var pt := _in_clearing(rng, ci, 1.0)
		if pt.distance_to(Vector2(SPAWN.at.x, SPAWN.at.z)) < ZONE_MIN_FROM_START: continue
		if centreline_dist(pt) < CENTRELINE_CLEAR or in_camp(pt): continue
		if not _clear_of(pt, obs, AGENT_MARGIN + 0.4): continue
		var bad := false
		for pg in layout.pages.values():
			if pt.distance_to(Vector2(pg.x, pg.z)) < PAGE_MIN_FROM_ZONE: bad = true
		for z in layout.zones:
			if pt.distance_to(Vector2(z.at.x, z.at.z)) < ZONE_MIN_APART: bad = true
		if bad: continue
		layout.zones.append({"id": "zone_%d" % (layout.zones.size() + 1), "at": Vector3(pt.x, 0, pt.y), "yaw": rng.randf_range(-180.0, 180.0)})
	# Trees on a jittered grid at this map's density, never in the open.
	var step: float = layout.step
	var n := int(SIZE.x / step)
	for gz in n + 1:
		for gx in n + 1:
			var p := Vector2(gx * step + rng.randf_range(-0.35, 0.35) * step, gz * step + rng.randf_range(-0.35, 0.35) * step)
			var r := rng.randf_range(0.3, 0.6)
			var h := rng.randf_range(13.0, 21.0)
			if p.x < 1.0 or p.y < 1.0 or p.x > SIZE.x - 1.0 or p.y > SIZE.y - 1.0: continue
			if is_open(p, TREE_CLEAR + r): continue
			layout.trees.append([p.x, p.y, r, h])
	return layout

# A spot in clearing `ci` for an obstacle of `reach`: clear of the path
# centrelines by 3 m plus a walker's width, of the camp, and of other obstacles.
static func _place(rng: RandomNumberGenerator, ci: int, reach: float, obs: Array) -> Vector2:
	for tries in 40:
		var pt := _in_clearing(rng, ci, reach + 0.5)
		if centreline_dist(pt) < CENTRELINE_CLEAR + reach + AGENT_MARGIN: continue
		if in_camp(pt, reach + 1.0): continue
		if not _clear_of(pt, obs, reach + AGENT_MARGIN * 2.0): continue
		return pt
	return Vector2(INF, INF)

# R11's rules for a generated map ([] = valid):
#   every page spot and spawn zone reachable from the start (the camp joins
#   the path network; a spot is reachable when it is clear of every obstacle
#   and the straight walk to its nearest path centreline is too, since the
#   centrelines are kept 3 m clear of everything);
#   pages >= 25 m from the start, >= 20 m apart, >= 15 m from any spawn zone;
#   no tree, rock or spawn zone within 3 m of a path centreline or in the camp;
#   plus the MVP's own needs: 3 pages, 6 zones, the 1 / 2 / 3 m ledges.
static func rule_violations(layout: Dictionary) -> Array:
	var bad := []
	var start := Vector2(SPAWN.at.x, SPAWN.at.z)
	var obs := obstacles(layout)
	if layout.pages.size() != 3: bad.append("pages: %d of 3" % layout.pages.size())
	if layout.zones.size() != ZONE_COUNT: bad.append("zones: %d of %d" % [layout.zones.size(), ZONE_COUNT])
	var tops := []
	for l in layout.ledges: tops.append(l[4])
	for t in LEDGE_TOPS:
		if not t in tops: bad.append("no %.0f m ledge" % t)
	var spots := []
	for id in layout.pages: spots.append([id, Vector2(layout.pages[id].x, layout.pages[id].z)])
	for z in layout.zones: spots.append([z.id, Vector2(z.at.x, z.at.z)])
	for sp in spots:
		var p: Vector2 = sp[1]
		if not is_open(p): bad.append("%s is in the trees" % sp[0])
		if not _clear_of(p, obs, AGENT_MARGIN): bad.append("%s is inside an obstacle" % sp[0])
		var q := centreline_point(p)
		var steps := maxi(1, ceili(p.distance_to(q) / 0.25))
		for i in steps + 1:
			if not _clear_of(p.lerp(q, float(i) / steps), obs, AGENT_MARGIN):
				bad.append("%s: the way to the path is blocked" % sp[0])
				break
	var ids: Array = layout.pages.keys()
	for i in ids.size():
		var a := Vector2(layout.pages[ids[i]].x, layout.pages[ids[i]].z)
		if a.distance_to(start) < PAGE_MIN_FROM_START: bad.append("%s %.1f m from the start" % [ids[i], a.distance_to(start)])
		for j in range(i + 1, ids.size()):
			var b := Vector2(layout.pages[ids[j]].x, layout.pages[ids[j]].z)
			if a.distance_to(b) < PAGE_MIN_APART: bad.append("%s and %s %.1f m apart" % [ids[i], ids[j], a.distance_to(b)])
		for z in layout.zones:
			if a.distance_to(Vector2(z.at.x, z.at.z)) < PAGE_MIN_FROM_ZONE: bad.append("%s %.1f m from %s" % [ids[i], a.distance_to(Vector2(z.at.x, z.at.z)), z.id])
	for z in layout.zones:
		var p := Vector2(z.at.x, z.at.z)
		if centreline_dist(p) < CENTRELINE_CLEAR: bad.append("%s on a path" % z.id)
		if in_camp(p): bad.append("%s in the camp" % z.id)
		if p.distance_to(start) < ZONE_MIN_FROM_START: bad.append("%s %.1f m from the start" % [z.id, p.distance_to(start)])
	for o in obs:
		if centreline_dist(o[0]) < CENTRELINE_CLEAR + float(o[1]): bad.append("an obstacle within 3 m of a path at %s" % o[0])
		if in_camp(o[0], float(o[1])): bad.append("an obstacle in the camp at %s" % o[0])
	for t in layout.trees:
		var p := Vector2(t[0], t[1])
		if centreline_dist(p) < CENTRELINE_CLEAR + float(t[2]) or in_camp(p, float(t[2])):
			bad.append("a tree on a path or in the camp at %s" % p)
			break
	return bad

# ---- builders -----------------------------------------------------------------------------

static func _box(parent: Node3D, centre: Vector3, size: Vector3, mat: Material, nm: String, solids: Array, visual := true, yaw_deg := 0.0) -> Node3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), centre)
	var xf := body.transform
	var box := AABB(xf * (-size * 0.5), Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				box = box.expand(xf * (Vector3(sx, sy, sz) * size * 0.5))
	solids.append(box)
	if visual:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mesh.mesh = bm
		body.add_child(mesh)
	parent.add_child(body)
	return body

static func _flat_patch(parent: Node3D, centre: Vector2, size: Vector2, yaw: float, mat: Material, nm: String) -> void:
	var m := MeshInstance3D.new()
	m.name = nm
	var pm := PlaneMesh.new()
	pm.size = size
	pm.material = mat
	m.mesh = pm
	m.position = Vector3(centre.x, 0.01, centre.y)
	m.rotation.y = yaw
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)

static func _multimesh(parent: Node3D, mesh: Mesh, xforms: Array, nm: String, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size(): mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst

static func _cone_mesh(top: float, bottom: float, mat: Material) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 1
	m.material = mat
	return m

# The fixed part, built once under `parent` (which must be in the scene tree):
# ground, boundary, worn paths, the camp and its fire, the moon. Returns
# {node, spawn, solids, bounds, lamps}.
static func build(parent: Node3D) -> Dictionary:
	var solids := []
	var geo := Node3D.new()
	geo.name = "DarkForest"
	parent.add_child(geo)
	var w := SIZE.x
	var d := SIZE.y
	var floor_solids := []
	_box(geo, Vector3(w * 0.5, -0.1, d * 0.5), Vector3(w + 2.0, 0.2, d + 2.0), material("ground"), "floor", floor_solids) # not an obstacle
	_box(geo, Vector3(w * 0.5, WALL_H * 0.5, -0.2), Vector3(w + 1.0, WALL_H, 0.4), null, "bound_north", solids, false)
	_box(geo, Vector3(w * 0.5, WALL_H * 0.5, d + 0.2), Vector3(w + 1.0, WALL_H, 0.4), null, "bound_south", solids, false)
	_box(geo, Vector3(-0.2, WALL_H * 0.5, d * 0.5), Vector3(0.4, WALL_H, d + 1.0), null, "bound_west", solids, false)
	_box(geo, Vector3(w + 0.2, WALL_H * 0.5, d * 0.5), Vector3(0.4, WALL_H, d + 1.0), null, "bound_east", solids, false)
	for pa in PATHS:
		var va := _centre(pa[0])
		var vb := _centre(pa[1])
		var dir := vb - va
		_flat_patch(geo, (va + vb) * 0.5, Vector2(PATH_HALF_W * 1.6, dir.length()), -atan2(dir.x, dir.y), material("path"), "path_%d_%d" % [pa[0], pa[1]])
	var camp := Node3D.new()
	camp.name = "Camp"
	geo.add_child(camp)
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		var at := CAMPFIRE + Vector3(cos(a) * 2.6, 0.0, sin(a) * 2.6)
		var has_bench := prop_available("Bench")
		_box(camp, at + Vector3(0, 0.2, 0), Vector3(1.8, 0.4, 0.45), material("log"), "log_%d" % i, solids, not has_bench, rad_to_deg(-a) + 90.0)
		if has_bench: # Phase 4: a Fantasy Props bench on each seat's collider, facing the fire
			var b := prop("Bench", 1.8)
			b.name = "bench_%d" % i
			b.position = at
			b.rotation.y = -a + PI * 0.5
			camp.add_child(b)
	_dress_camp(camp, solids)
	var fire := OmniLight3D.new()
	fire.name = "CampFire"
	fire.position = CAMPFIRE + Vector3(0, 1.2, 0)
	fire.light_color = Color(1.0, 0.55, 0.25)
	fire.light_energy = 3.5
	fire.omni_range = 16.0
	fire.shadow_enabled = false # perf trim 2 (2026-11-13): the camp light casts no shadow
	fire.set_meta("base_energy", 3.5)
	fire.set_meta("flicker", "fire")
	camp.add_child(fire)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_energy = 0.9
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 50.0
	geo.add_child(moon)
	var lamps: Array[OmniLight3D] = [fire]
	return {"node": geo, "spawn": SPAWN, "solids": solids, "bounds": BOUNDS, "lamps": lamps}

# A generated map under `geo` (the fixed part's node), replacing any earlier
# one: trees, rocks, ledges. Returns their solids.
static func scatter(geo: Node3D, layout: Dictionary) -> Array:
	var old := geo.get_node_or_null("Scatter")
	if old != null:
		geo.remove_child(old)
		old.queue_free()
	var root := Node3D.new()
	root.name = "Scatter"
	geo.add_child(root)
	var solids := []
	var trunk_x := []
	var crown_x := []
	var colliders := Node3D.new()
	colliders.name = "TreeColliders"
	root.add_child(colliders)
	var kit_trees := not _kit(TREE_KINDS[0][0]).is_empty() and not OS.has_environment("RC_NO_KIT")
	for ti in layout.trees.size():
		var t: Array = layout.trees[ti]
		var x: float = t[0]
		var z: float = t[1]
		var r: float = t[2]
		var h: float = t[3]
		# [Sir, 2026-11-13: clipping through trees] the collider is as wide as the
		# drawn kit trunk (less the player's reach), never thinner than the layout's.
		if kit_trees: r = maxf(r, float(tree_look(t, ti, int(layout.seed)).trunk) - TRUNK_SLACK)
		trunk_x.append(Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(x, h * 0.5, z)))
		var cr := r * 6.0
		crown_x.append(Transform3D(Basis.from_scale(Vector3(cr, h * 0.55, cr)), Vector3(x, h * 0.72, z)))
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = h
		col.shape = cyl
		body.add_child(col)
		body.position = Vector3(x, h * 0.5, z)
		colliders.add_child(body)
		solids.append(AABB(Vector3(x - r, 0.0, z - r), Vector3(r * 2.0, h, r * 2.0)))
	_multimesh(root, _cone_mesh(0.8, 1.0, material("trunk")), trunk_x, "Trunks", true)
	_multimesh(root, _cone_mesh(0.0, 1.0, material("crown")), crown_x, "Crowns", false)
	for i in layout.rocks.size():
		var rk: Array = layout.rocks[i]
		_box(root, Vector3(rk[0], rk[4] * 0.5, rk[1]), Vector3(rk[2], rk[4], rk[3]), material("rock"), "rock_%d" % i, solids, true, rk[5])
	for i in layout.ledges.size():
		var lg: Array = layout.ledges[i]
		_box(root, Vector3(lg[0], lg[4] * 0.5, lg[1]), Vector3(lg[2], lg[4], lg[3]), material("ledge"), "ledge_%d" % i, solids)
	dress(root, layout)
	return solids

# ---- Fantasy Props (Phase 4) ---------------------------------------------------------
const PROPS := "res://assets/quaternius/props/"
const Vfx = preload("res://scripts/render/vfx.gd")

static func prop_available(name: String) -> bool:
	return ResourceLoader.exists(PROPS + name + ".gltf") and not OS.has_environment("RC_NO_PROPS")

# A Fantasy Props model, scaled so its longest side is `size_m` (0 = as made),
# standing on y = 0. No collision (callers add a collider where one is needed).
static func prop(name: String, size_m := 0.0) -> Node3D:
	var n: Node3D = (load(PROPS + name + ".gltf") as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: AABB = _local_to(n, mi) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var holder := Node3D.new()
	holder.add_child(n)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := size_m / longest if size_m > 0.0 and longest > 0.001 else 1.0
	n.scale = Vector3.ONE * s
	n.position = Vector3(-(box.position.x + box.size.x * 0.5) * s, -box.position.y * s, -(box.position.z + box.size.z * 0.5) * s)
	holder.set_meta("size", box.size * s)
	return holder

# The camp [Sir, Phase 4]: a Binbun fire in a ring of stones, firewood, and a
# few supplies off the path north (the spawn's walk out stays clear). Solid
# props get box colliders so the player and the nav grid treat them as cover.
const CAMP_PROPS := [
	# [name, size m, offset from the fire (x, z), yaw deg, solid]
	["Barrel", 0.9, Vector2(-5.2, 1.6), 0.0, true],
	["Crate_Wooden", 0.9, Vector2(-5.6, 3.0), 20.0, true],
	["Bag", 0.6, Vector2(-4.4, 3.4), 60.0, false],
	["Cauldron", 0.8, Vector2(5.0, 2.2), 0.0, true],
	["Pouch_Large", 0.45, Vector2(4.4, 3.4), -30.0, false],
	["Anvil_Log", 0.9, Vector2(5.6, 0.4), 40.0, true],
	["Torch_Metal", 1.6, Vector2(-2.6, -6.0), 0.0, false],
	["Torch_Metal", 1.6, Vector2(2.6, -6.0), 0.0, false],
]
static func _dress_camp(camp: Node3D, solids: Array) -> void:
	var fire_fx := Vfx.make_loop("campfire")
	if fire_fx:
		fire_fx.name = "CampFlames"
		fire_fx.position = CAMPFIRE
		camp.add_child(fire_fx)
		Vfx.set_loop(fire_fx, true)
	else:
		var embers := MeshInstance3D.new()
		embers.name = "Embers"
		embers.mesh = _cone_mesh(0.2, 0.6, material("ember"))
		embers.scale.y = 0.5
		embers.position = CAMPFIRE + Vector3(0, 0.25, 0)
		embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		camp.add_child(embers)
	var stones: Array = _kit("Pebble_Round_1")
	if not stones.is_empty():
		for i in 9: # a ring of stones round the fire
			var a := TAU * float(i) / 9.0
			var mi := MeshInstance3D.new()
			mi.name = "fire_stone_%d" % i
			mi.mesh = stones[0][0]
			var sc := 0.9 + 0.15 * float(i % 3)
			mi.transform = Transform3D(Basis(Vector3.UP, a * 1.7).scaled(Vector3.ONE * sc), CAMPFIRE + Vector3(cos(a) * 0.75, 0.0, sin(a) * 0.75)) * (stones[0][1] as Transform3D)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			camp.add_child(mi)
	for p in CAMP_PROPS:
		if not prop_available(p[0]): continue
		var n := prop(p[0], p[1])
		n.name = "camp_%s_%d" % [String(p[0]).to_lower(), camp.get_child_count()]
		var off: Vector2 = p[2]
		n.position = CAMPFIRE + Vector3(off.x, 0.0, off.y)
		n.rotation_degrees.y = p[3]
		camp.add_child(n)
		if p[4]:
			var sz: Vector3 = n.get_meta("size")
			_box(camp, n.position + Vector3(0, sz.y * 0.5, 0), sz * 0.9, null, n.name + "_col", solids, false, p[3])

# The densest of the first `n` seeds (the perf suite runs on it [R11]).
static func densest_seed(n := 64) -> int:
	var best := 0
	var most := -1.0
	for s in n:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var step := rng.randf_range(4.0, 5.2) # the first draw of generate() is the density
		if 1.0 / step > most:
			most = 1.0 / step
			best = s
	return best

# --- Stylized Nature MegaKit visuals (CC0) [Sir: modify the terrain] ------------
# Presentation only: the layout, rules, colliders and nav stay as generated.
# Trees are drawn per CHUNK as MultiMeshes of real models with a visibility range
# (near), over the cheap cones (far, faded in beyond NEAR_END). Ground cover is
# scattered from a separate RNG seeded by the map seed, so generate() is unchanged.
const KIT := "res://assets/quaternius/nature/"
const TREE_KINDS := [["Pine_5", 0.85], ["DeadTree_1", 0.15]] # perf-tuned 2026-11-13: Pine_5 (1.6k tris) plus opaque dead trees for the eerie look; leafy trees cost ~2 ms
const ROCK_KINDS := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
const CHUNK := 10.0           # small chunks: the visibility range culls close to the real distance
const NEAR_END := 40.0          # real trees up to here, impostors beyond [Sir, 2026-11-13: trees turned low-poly at 20 m]
const NEAR_FADE := 8.0
static var near_end := NEAR_END # Settings > Tree detail distance (applied live by set_tree_distance)

# Moves the detailed-tree / impostor hand-over of an already built forest to `m` metres.
static func set_tree_distance(forest: Node, m: float) -> void:
	near_end = m
	if forest == null: return
	var kit := forest.find_child("KitTrees", true, false)
	if kit: for g in kit.find_children("*", "GeometryInstance3D", true, false): (g as GeometryInstance3D).visibility_range_end = m
	var far := forest.find_child("FarTrees", true, false)
	if far: for g in far.find_children("*", "GeometryInstance3D", true, false): (g as GeometryInstance3D).visibility_range_begin = m - NEAR_FADE          # the hand-over to the impostors is a wide, dithered cross-fade (no snap)
# Trunk radius of each kit tree at scale 1 (measured at 1-2 m up the bark).
const TRUNK_R := {"Pine_5": 0.52, "DeadTree_1": 0.74}
const TRUNK_MAX := 0.85         # drawn trunk radius cap (m): taller trees stop getting fatter
const TRUNK_SLACK := 0.15       # collider = drawn trunk - this (the player's capsule covers the rest)

# One tree's kit model, scale and yaw, the same for its drawing and its
# collider: seeded by the map and the tree's index. Heights follow the layout
# (h / kit height) but the trunk never exceeds TRUNK_MAX.
static func tree_look(t: Array, i: int, seed: int, kinds: Array = TREE_KINDS) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(seed, i))
	var kind := _pick(rng, kinds)
	var e: Array = _kit(kind)
	var h_kit: float = float(e[0][2]) if not e.is_empty() else 8.5
	var s: float = float(t[3]) / h_kit * rng.randf_range(0.85, 1.05)
	var tr: float = float(TRUNK_R.get(kind, 0.6))
	s = minf(s, TRUNK_MAX / tr)
	return {"kind": kind, "scale": s, "yaw": rng.randf() * TAU, "trunk": tr * s}
static var _kit_cache := {}

# [mesh, local transform, kit height] per mesh in a kit scene (cached).
static func _kit(name: String) -> Array:
	if _kit_cache.has(name): return _kit_cache[name]
	var out := []
	var path := KIT + name + ".gltf"
	if ResourceLoader.exists(path):
		var n: Node3D = (load(path) as PackedScene).instantiate()
		var h := 0.0
		for m in n.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			_tune(mi.mesh)
			var x: Transform3D = n.global_transform.affine_inverse() * mi.global_transform if n.is_inside_tree() else _local_to(n, mi)
			out.append([mi.mesh, x])
			h = maxf(h, (x * mi.mesh.get_aabb()).end.y)
		for e in out: e.append(maxf(h, 0.1))
		n.free()
	_kit_cache[name] = out
	return out

# The kit's materials alpha-test every surface (bark too) and draw both sides,
# which defeats early depth rejection; with many moving lights (64 fireballs)
# that cost ~11 ms p95. Bark -> opaque, one-sided; leaves keep the cut-out; all
# use per-vertex lighting (the stepped, low-poly look hides the difference).
static func _tune(mesh: Mesh) -> void:
	if mesh == null or mesh.has_meta("rc_tuned"): return
	mesh.set_meta("rc_tuned", true)
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i) as BaseMaterial3D
		if mat == null: continue
		var t: BaseMaterial3D = mat.duplicate()
		var leafy := t.resource_name.to_lower().contains("leaf") or t.resource_name.to_lower().contains("leaves") or t.resource_name.to_lower().contains("grass") or t.resource_name.to_lower().contains("flower")
		if not leafy:
			t.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			t.cull_mode = BaseMaterial3D.CULL_BACK
		t.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		mesh.surface_set_material(i, t)

# kind -> crossed-quad Mesh textured with the baked impostor, in kit units (the
# same transform as the real tree places it). Empty when not baked.
const IMPOSTORS := KIT + "impostors/"
static var _imp_cache := {}
static func _impostors() -> Dictionary:
	if not _imp_cache.is_empty(): return _imp_cache
	if not FileAccess.file_exists(IMPOSTORS + "impostors.json"): return {}
	var info = JSON.parse_string(FileAccess.get_file_as_string(IMPOSTORS + "impostors.json"))
	if not info is Array: return {}
	for e in info:
		var tex_path: String = IMPOSTORS + String(e.kind) + ".png"
		if not ResourceLoader.exists(tex_path): continue
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(tex_path)
		mat.albedo_color = Color(0.72, 0.72, 0.72) # baked under flat studio light: darken to sit with the lit near trees
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var w: float = float(e.view_w)
		var h: float = float(e.view_h)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for plane in 2: # two quads crossed at right angles
			var ax := Vector3(w * 0.5, 0, 0) if plane == 0 else Vector3(0, 0, w * 0.5)
			var n := Vector3(0, 0, 1) if plane == 0 else Vector3(1, 0, 0)
			var c := [-ax, ax, ax + Vector3(0, h, 0), -ax + Vector3(0, h, 0)]
			var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(n.lerp(Vector3.UP, 0.6).normalized()) # soft top light, like the canopy
				st.set_uv(uv[idx])
				st.add_vertex(c[idx])
		var mesh := st.commit()
		mesh.surface_set_material(0, mat)
		_imp_cache[String(e.kind)] = mesh
	return _imp_cache

static func _local_to(root: Node3D, n: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D: x = (cur as Node3D).transform * x
		cur = cur.get_parent()
	return x

static func _pick(rng: RandomNumberGenerator, table: Array) -> String:
	var r := rng.randf()
	for e in table:
		r -= float(e[1])
		if r <= 0.0: return e[0]
	return table[0][0]

static func _kit_multimeshes(parent: Node3D, name: String, xforms: Array, nm: String, shadows: bool, vis_end: float) -> void:
	for e in _kit(name):
		var parts := []
		for x in xforms: parts.append(x * (e[1] as Transform3D))
		var inst := _multimesh(parent, e[0], parts, nm, shadows)
		inst.visibility_range_end = vis_end
		inst.visibility_range_end_margin = NEAR_FADE
		inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

static func dress(root: Node3D, layout: Dictionary) -> void:
	if _kit(TREE_KINDS[0][0]).is_empty() or OS.has_environment("RC_NO_KIT"): return # kit not imported (or diagnosis): keep the greybox
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout.seed) * 7919 + 17
	var chunk_m: float = float(OS.get_environment("RC_CHUNK")) if OS.has_environment("RC_CHUNK") else CHUNK
	var near_m: float = float(OS.get_environment("RC_NEAR")) if OS.has_environment("RC_NEAR") else near_end
	var kinds: Array = [["Pine_5", 1.0]] if OS.has_environment("RC_PINES") else TREE_KINDS
	var chunks := {} # Vector2i -> {kind: [xform]}
	var far_by_kind := {} # kind -> [xform], every tree (the far LOD)
	for ti in layout.trees.size():
		var t: Array = layout.trees[ti]
		var look := tree_look(t, ti, int(layout.seed), kinds)
		var kind: String = look.kind
		var s: float = look.scale
		var x := Transform3D(Basis(Vector3.UP, float(look.yaw)).scaled(Vector3.ONE * s), Vector3(t[0], 0.0, t[1]))
		if not far_by_kind.has(kind): far_by_kind[kind] = []
		far_by_kind[kind].append(x)
		var key := Vector2i(int(t[0] / chunk_m), int(t[1] / chunk_m))
		if not chunks.has(key): chunks[key] = {}
		if not chunks[key].has(kind): chunks[key][kind] = []
		chunks[key][kind].append(x)
	var trees := Node3D.new()
	trees.name = "KitTrees"
	root.add_child(trees)
	for key in chunks:
		var c := Node3D.new()
		c.name = "chunk_%d_%d" % [key.x, key.y]
		trees.add_child(c)
		for kind in chunks[key]:
			_kit_multimeshes(c, kind, chunks[key][kind], kind, false, near_m)
	# Far LOD: baked impostors on crossed quads (tools/bake_tree_impostors.gd).
	# The cone MultiMeshes stay in the tree (tests key on "Trunks") but hide when
	# impostors exist; without them the cones are the far LOD as before.
	var imp := _impostors()
	var have_imp := not imp.is_empty()
	if have_imp:
		var far := Node3D.new()
		far.name = "FarTrees"
		root.add_child(far)
		for kind in far_by_kind:
			if not imp.has(kind): continue
			var inst := _multimesh(far, imp[kind], far_by_kind[kind], "far_" + kind, false)
			inst.visibility_range_begin = near_m - NEAR_FADE
			inst.visibility_range_begin_margin = NEAR_FADE
			inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for nm in ["Trunks", "Crowns"]:
		var cone: GeometryInstance3D = root.get_node_or_null(nm)
		if cone and have_imp: cone.visible = false
	# Without impostors, the cones become the far LOD: visible only beyond the real trees.
	for nm in ([] if have_imp else ["Trunks", "Crowns"]):
		var far: GeometryInstance3D = root.get_node_or_null(nm)
		if far:
			far.visibility_range_begin = near_m - 5.0
			far.visibility_range_begin_margin = 5.0
			far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Rocks: a kit rock sized to each rock's collider box (the box itself hidden).
	for i in layout.rocks.size():
		var rk: Array = layout.rocks[i]
		var box: Node3D = root.get_node_or_null("rock_%d" % i)
		var kind: String = ROCK_KINDS[rng.randi() % ROCK_KINDS.size()]
		var e: Array = _kit(kind)
		if e.is_empty() or box == null: continue
		var aabb: AABB = (e[0][1] as Transform3D) * (e[0][0] as Mesh).get_aabb()
		var sc := Vector3(float(rk[2]) / maxf(aabb.size.x, 0.1), float(rk[4]) / maxf(aabb.size.y, 0.1), float(rk[3]) / maxf(aabb.size.z, 0.1)) * 1.08
		var mi := MeshInstance3D.new()
		mi.name = "kit_rock_%d" % i
		mi.mesh = e[0][0]
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(rk[5]))).scaled(sc), Vector3(rk[0], 0.0, rk[1])) * (e[0][1] as Transform3D)
		root.add_child(mi)
		for v in box.find_children("*", "MeshInstance3D", true, false): (v as MeshInstance3D).visible = false
		if box is MeshInstance3D: (box as MeshInstance3D).visible = false
	# Ledges [Phase 3]: a kit rock sized to each mantle ledge's box. The box
	# collider stays exactly as it was (1 / 2 / 3 m mantle tech), only hidden;
	# the rock's height matches the ledge top.
	for i in layout.ledges.size():
		var lg: Array = layout.ledges[i]
		var lbox: Node3D = root.get_node_or_null("ledge_%d" % i)
		var lkind: String = ROCK_KINDS[rng.randi() % ROCK_KINDS.size()]
		var le: Array = _kit(lkind)
		if le.is_empty() or lbox == null: continue
		var la: AABB = (le[0][1] as Transform3D) * (le[0][0] as Mesh).get_aabb()
		var lsc := Vector3(float(lg[2]) / maxf(la.size.x, 0.1) * 1.05, float(lg[4]) / maxf(la.size.y, 0.1), float(lg[3]) / maxf(la.size.z, 0.1) * 1.05)
		var lm := MeshInstance3D.new()
		lm.name = "kit_ledge_%d" % i
		lm.mesh = le[0][0]
		lm.transform = Transform3D(Basis.IDENTITY.scaled(lsc), Vector3(lg[0], -la.position.y * lsc.y, lg[1])) * (le[0][1] as Transform3D)
		root.add_child(lm)
		for v in lbox.find_children("*", "MeshInstance3D", true, false): (v as MeshInstance3D).visible = false
	# Ground: Binbun grass over the floor, grown near the camera (grass_field.gd);
	# no Nature-kit ground cover [Sir, 2026-11-13].
	var GrassField = load("res://scripts/world/grass_field.gd")
	if GrassField.available():
		var g: Node3D = GrassField.new()
		root.add_child(g)
		g.setup(int(layout.seed))
