extends RefCounted
# The ground floor of the WMSU College of Computing Studies, built from data:
# Classroom 104, the east corridor (fallen duct, the level exit), the
# computer lab and the faculty office. Walls, floors and ceilings are boxes
# (collision and visuals always agree); furniture is Kenney models scaled to
# real size, each with a box collider that also blocks enemy navigation.
# World axes: +X east, +Z south, +Y up; metres. Every solid box is recorded in
# `solids` for the navigation grid.

const Door = preload("res://scripts/world/door.gd")
const WALL := 0.2
const CEILING := 3.0
const WAINSCOT := 1.0          # height of the darker lower wall band
const KENNEY := 2.0            # Kenney furniture is modelled at about half scale
const FURN := "res://assets/kenney/furniture/%s.glb"

const ROOMS := {
	"classroom_104": {"min": Vector2(0, 0), "max": Vector2(8, 10), "label": "CLASSROOM 104"},
	"east_corridor": {"min": Vector2(8, 0), "max": Vector2(11, 10), "label": "EAST CORRIDOR"},
	"computer_lab": {"min": Vector2(11, 0), "max": Vector2(19, 6), "label": "COMPUTER LAB 2"},
	"faculty_office": {"min": Vector2(11, 6), "max": Vector2(17, 10), "label": "FACULTY OFFICE"},
}
const BOUNDS := [Vector2(0, 0), Vector2(19, 10)]
# Walls: [along_x, fixed coordinate, from, to, gaps [[from, to, height]]]
const WALLS := [
	[true, 0.0, 0.0, 19.0, []],            # north (outside)
	[true, 10.0, 0.0, 17.0, []],           # south (outside)
	[false, 0.0, 0.0, 10.0, []],           # west (outside)
	[false, 8.0, 0.0, 10.0, [[4.4, 5.6, 2.1]]],                    # classroom | corridor
	[false, 11.0, 0.0, 10.0, [[2.4, 3.6, 2.1], [8.4, 9.6, 2.1]]],  # corridor | lab, office
	[true, 6.0, 11.0, 19.0, []],           # lab | office (and outside)
	[false, 19.0, 0.0, 6.0, []],           # lab east (outside)
	[false, 17.0, 6.0, 10.0, []],          # office east (outside)
]
const DOORS := [
	{"id": "door_104_east", "hinge": Vector3(8, 0, 4.4), "yaw": 0.0},
	{"id": "door_lab", "hinge": Vector3(11, 0, 2.4), "yaw": 0.0},
	{"id": "door_office", "hinge": Vector3(11, 0, 8.4), "yaw": 0.0},
]
const SPAWN := {"at": Vector3(4, 0, 7), "yaw": 0.0}
# Solid boxes with their own collider: [centre, size, colour, model or ""]
const BLOCKS := [
	[Vector3(4, 0.375, 1.6), Vector3(1.6, 0.75, 0.8), Color(0.45, 0.32, 0.22), "desk"],  # teacher's desk
	[Vector3(9.5, 2.15, 7.3), Vector3(3.0, 1.7, 0.6), Color(0.5, 0.52, 0.55), ""],       # fallen duct: 1.3 m clearance
]
const DUCT_CLEARANCE := 1.3
# Furniture: [model, centre x/z, yaw degrees, scale multiplier (x KENNEY), solid]
# Classroom keeps the centre aisle (x 3.4-4.6), the lane to the corridor door
# (x > 4.6, z 4.2-5.8), the z 6.4-10 back area and the front (z < 2.6 apart
# from the teacher's desk) clear.
const FURNITURE := [
	# Classroom 104: two rows of student desks with chairs, a bookcase, a plant.
	["desk", Vector2(1.7, 3.2), 180.0, Vector3(0.7, 1.0, 0.8), true], ["desk", Vector2(2.9, 3.2), 180.0, Vector3(0.7, 1.0, 0.8), true],
	["desk", Vector2(5.1, 3.2), 180.0, Vector3(0.7, 1.0, 0.8), true], ["desk", Vector2(6.3, 3.2), 180.0, Vector3(0.7, 1.0, 0.8), true],
	["desk", Vector2(1.7, 4.8), 180.0, Vector3(0.7, 1.0, 0.8), true], ["desk", Vector2(2.9, 4.8), 180.0, Vector3(0.7, 1.0, 0.8), true],
	["chair", Vector2(1.7, 3.85), 180.0, Vector3.ONE, true], ["chair", Vector2(2.9, 3.85), 180.0, Vector3.ONE, true],
	["chair", Vector2(5.1, 3.85), 180.0, Vector3.ONE, true], ["chair", Vector2(6.3, 3.85), 180.0, Vector3.ONE, true],
	["chair", Vector2(1.7, 5.45), 180.0, Vector3.ONE, true], ["chair", Vector2(2.9, 5.45), 180.0, Vector3.ONE, true],
	["bookcaseOpen", Vector2(0.35, 8.4), 90.0, Vector3.ONE, true],
	["pottedPlant", Vector2(7.6, 9.6), 0.0, Vector3.ONE, true],
	# East corridor: a bin by the classroom door.
	["trashcan", Vector2(10.7, 6.5), 0.0, Vector3(0.6, 0.6, 0.6), true],
	# Computer lab: two rows of workstations against the walls, entry kept clear.
	["desk", Vector2(13.4, 0.55), 0.0, Vector3.ONE, true], ["desk", Vector2(15.0, 0.55), 0.0, Vector3.ONE, true], ["desk", Vector2(16.6, 0.55), 0.0, Vector3.ONE, true], ["desk", Vector2(18.2, 0.55), 0.0, Vector3(0.95, 1.0, 1.0), true],
	["desk", Vector2(13.4, 5.45), 180.0, Vector3.ONE, true], ["desk", Vector2(15.0, 5.45), 180.0, Vector3.ONE, true], ["desk", Vector2(16.6, 5.45), 180.0, Vector3.ONE, true], ["desk", Vector2(18.2, 5.45), 180.0, Vector3(0.95, 1.0, 1.0), true],
	["chairDesk", Vector2(13.4, 1.35), 180.0, Vector3(0.8, 0.8, 0.8), true], ["chairDesk", Vector2(16.6, 1.35), 180.0, Vector3(0.8, 0.8, 0.8), true],
	["chairDesk", Vector2(15.0, 4.65), 0.0, Vector3(0.8, 0.8, 0.8), true], ["chairDesk", Vector2(18.2, 4.65), 0.0, Vector3(0.8, 0.8, 0.8), true],
	# Faculty office: a desk, bookcases, a filing drawer unit, a coat rack.
	["desk", Vector2(15.2, 8.9), 0.0, Vector3(1.1, 1.0, 1.0), true],
	["chairDesk", Vector2(15.2, 8.1), 180.0, Vector3(0.8, 0.8, 0.8), true],
	["bookcaseClosedWide", Vector2(13.2, 6.35), 180.0, Vector3.ONE, true],
	["bookcaseOpen", Vector2(16.65, 7.4), 270.0, Vector3.ONE, true],
	["sideTableDrawers", Vector2(16.5, 9.6), 0.0, Vector3.ONE, true],
	["coatRackStanding", Vector2(12.0, 9.6), 0.0, Vector3.ONE, true],
]
# Desk-top decoration (not solid): [model, position (y = surface), yaw, scale x KENNEY]
const DESKTOP := [
	["computerScreen", Vector3(13.4, 0.76, 0.45), 0.0, 1.0], ["computerScreen", Vector3(15.0, 0.76, 0.45), 0.0, 1.0],
	["computerScreen", Vector3(16.6, 0.76, 0.45), 0.0, 1.0], ["computerScreen", Vector3(18.2, 0.76, 0.45), 0.0, 1.0],
	["computerScreen", Vector3(13.4, 0.76, 5.55), 180.0, 1.0], ["computerScreen", Vector3(16.6, 0.76, 5.55), 180.0, 1.0],
	["computerKeyboard", Vector3(13.4, 0.76, 0.85), 0.0, 1.0], ["computerKeyboard", Vector3(16.6, 0.76, 0.85), 0.0, 1.0],
	["books", Vector3(15.8, 0.76, 9.0), 30.0, 1.0], ["computerScreen", Vector3(14.7, 0.76, 9.15), 0.0, 1.0],
]
# Ceiling lamps: [position, flicker?]
const LAMPS := [
	[Vector3(4, 2.9, 3), false], [Vector3(4, 2.9, 7), false],
	[Vector3(9.5, 2.9, 2.5), true], [Vector3(9.5, 2.9, 8.8), false],
	[Vector3(14.0, 2.9, 3.0), false], [Vector3(17.0, 2.9, 3.0), false],
	[Vector3(14.0, 2.9, 8.0), true],
]
# Enemy spawns: {id, kind, at, yaw (degrees)}.
const ENEMIES := [
	{"id": "shambler_1", "kind": "shambler", "at": Vector3(9.5, 0, 5.0), "yaw": 0.0},
]
# Floor items for each run: {id, item, at, quantity?}. "sling"/"backpack" are bags.
const LOOT := [
	{"id": "bag_sling", "item": "sling", "at": Vector3(2.2, 0.0, 8.8)},
	# Weapons, ammunition and throwables (50% MVP: 3 melee, 3 ranged, 2 throwables).
	{"id": "wpn_bat", "item": "baseball_bat", "at": Vector3(7.2, 0.0, 7.4)},
	{"id": "wpn_knife", "item": "knife", "at": Vector3(10.5, 0.0, 4.0)},
	{"id": "wpn_katana", "item": "katana", "at": Vector3(12.6, 0.0, 7.4)},
	{"id": "wpn_pistol", "item": "pistol", "at": Vector3(18.2, 0.76, 5.45)},
	{"id": "ammo_9mm_lab", "item": "ammo_9mm", "quantity": 30, "at": Vector3(13.4, 0.76, 5.45)},
	{"id": "wpn_shotgun", "item": "shotgun", "at": Vector3(18.3, 0.0, 3.0)},
	{"id": "ammo_shells_office", "item": "ammo_shells", "quantity": 12, "at": Vector3(13.2, 0.0, 9.5)},
	{"id": "wpn_rifle", "item": "assault_rifle", "at": Vector3(16.0, 0.0, 7.2)},
	{"id": "ammo_556_lab", "item": "ammo_556", "quantity": 60, "at": Vector3(12.2, 0.0, 5.3)},
	{"id": "thr_molotov", "item": "molotov", "quantity": 2, "at": Vector3(6.7, 0.0, 9.5)},
	{"id": "thr_frag", "item": "frag", "quantity": 2, "at": Vector3(12.4, 0.0, 0.6)},
]
# Hacking terminals (on workstation desks), readable notes.
const TERMINAL_SPOTS := {"terminal_lab": Vector3(16.6, 0.76, 0.6), "terminal_office": Vector3(14.7, 0.76, 9.0)}
const NOTE_SPOTS := {"note_whiteboard": [Vector3(4.0, 1.05, 0.12), Vector3(2.4, 1.1, 0.12)], "note_grading": [Vector3(13.9, 0.76, 5.3), Vector3(0.3, 0.05, 0.3)],
	"note_bulletin": [Vector3(8.13, 1.2, 1.8), Vector3(0.06, 0.6, 0.8)], "note_memo": [Vector3(16.5, 0.76, 9.6), Vector3(0.3, 0.05, 0.3)],
	"note_lablog": [Vector3(16.6, 0.76, 5.25), Vector3(0.3, 0.05, 0.3)]}
# The level exit at the corridor's north end: walk in with every research file.
const EXTRACTION := {"min": Vector3(8.3, 0.0, 0.2), "max": Vector3(10.7, 2.4, 1.4)}

# Every solid box built (world AABBs), for navigation. Filled by build().
static var solids: Array[AABB] = []
static var furniture_count := 0
static var _mats := {}

# ---- materials (procedural, cached) ----------------------------------------

static func _tile_texture(a: Color, b: Color, grout: Color, cells: int, px: int) -> ImageTexture:
	var img := Image.create(cells * px, cells * px, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 104
	for cy in cells:
		for cx in cells:
			var base := a if (cx + cy) % 2 == 0 else b
			base = base.darkened(rng.randf() * 0.08)
			for y in px:
				for x in px:
					var c := grout if x == 0 or y == 0 else base.darkened(rng.randf() * 0.04)
					img.set_pixel(cx * px + x, cy * px + y, c)
	return ImageTexture.create_from_image(img)

static func material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind): return _mats[kind]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	match kind:
		"floor":
			m.albedo_texture = _tile_texture(Color(0.55, 0.53, 0.5), Color(0.42, 0.42, 0.42), Color(0.25, 0.25, 0.25), 4, 16)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5) # a 4x4-tile texture every 2 m: 0.5 m tiles
			m.roughness = 0.8
		"ceiling":
			m.albedo_texture = _tile_texture(Color(0.78, 0.78, 0.74), Color(0.76, 0.76, 0.72), Color(0.45, 0.45, 0.42), 2, 24)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.83, 0.83, 0.83) # 0.6 m ceiling tiles
		"wall": m.albedo_color = Color(0.8, 0.78, 0.68)        # cream upper wall
		"wainscot": m.albedo_color = Color(0.32, 0.42, 0.36)    # institutional green lower band
		"duct": m.albedo_color = Color(0.5, 0.52, 0.55); m.metallic = 0.6; m.roughness = 0.4
		"board": m.albedo_color = Color(0.9, 0.92, 0.9)         # whiteboard
		_: m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[kind] = m
	return m

# ---- builders ----------------------------------------------------------------

static func _box(parent: Node3D, centre: Vector3, size: Vector3, mat: Material, nm: String, solid := true, visual := true) -> Node3D:
	var node: Node3D
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		node = body
		solids.append(AABB(centre - size * 0.5, size))
	else:
		node = Node3D.new()
	node.name = nm
	node.position = centre
	if visual:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mesh.mesh = bm
		node.add_child(mesh)
	parent.add_child(node)
	return node

# Wall along X (z fixed) or Z (x fixed) from a to b, with door gaps
# [[from, to, height]]. Each piece gets a darker wainscot band (visual only).
static func _wall(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, gaps: Array, nm: String) -> void:
	var cuts := [[a, a, 0.0]]
	for g in gaps: cuts.append(g)
	cuts.append([b, b, 0.0])
	for i in range(cuts.size() - 1):
		var s: float = cuts[i][1]
		var e: float = cuts[i + 1][0]
		if e - s > 0.001:
			_wall_piece(parent, along_x, fixed, s, e, 0.0, CEILING, "%s_%d" % [nm, i], true)
		if i + 1 < cuts.size() - 1:
			var g: Array = cuts[i + 1]
			if CEILING - float(g[2]) > 0.001:
				_wall_piece(parent, along_x, fixed, float(g[0]), float(g[1]), float(g[2]), CEILING, "%s_lintel_%d" % [nm, i], false)

static func _wall_piece(parent: Node3D, along_x: bool, fixed: float, s: float, e: float, y0: float, y1: float, nm: String, band: bool) -> void:
	var mid := (s + e) * 0.5
	var h := y1 - y0
	var c := Vector3(mid, y0 + h * 0.5, fixed) if along_x else Vector3(fixed, y0 + h * 0.5, mid)
	var size := Vector3(e - s, h, WALL) if along_x else Vector3(WALL, h, e - s)
	_box(parent, c, size, material("wall"), nm)
	if band:
		var bc := Vector3(mid, WAINSCOT * 0.5, fixed) if along_x else Vector3(fixed, WAINSCOT * 0.5, mid)
		var bs := Vector3(e - s, WAINSCOT, WALL + 0.02) if along_x else Vector3(WALL + 0.02, WAINSCOT, e - s)
		_box(parent, bc, bs, material("wainscot"), nm + "_band", false)

# A Kenney model scaled to real size, placed so its footprint is centred on
# xz and it stands on y. Solid props get a box collider from the final bounds.
static func prop(parent: Node3D, model: String, xz: Vector2, y: float, yaw: float, scale: Vector3, solid: bool, nm: String) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	parent.add_child(root)
	var inst: Node3D = (load(FURN % model) as PackedScene).instantiate()
	inst.scale = scale * KENNEY
	inst.rotation_degrees.y = yaw
	root.add_child(inst)
	var box := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b: AABB = (root.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	inst.position = Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
	root.position = Vector3(xz.x, y, xz.y)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		col.position = Vector3(0, box.size.y * 0.5, 0)
		body.add_child(col)
		root.add_child(body)
		solids.append(AABB(Vector3(xz.x - box.size.x * 0.5, y, xz.y - box.size.z * 0.5), box.size))
	furniture_count += 1
	return root

# Builds everything under `parent` (which must be in the scene tree).
static func build(parent: Node3D) -> Dictionary:
	solids.clear()
	furniture_count = 0
	var geo := Node3D.new()
	geo.name = "Greybox"
	parent.add_child(geo)
	var w: float = BOUNDS[1].x - BOUNDS[0].x
	var d: float = BOUNDS[1].y - BOUNDS[0].y
	_box(geo, Vector3(w * 0.5, -0.1, d * 0.5), Vector3(w + 0.4, 0.2, d + 0.4), material("floor"), "floor")
	_box(geo, Vector3(w * 0.5, CEILING + 0.1, d * 0.5), Vector3(w + 0.4, 0.2, d + 0.4), material("ceiling"), "ceiling")
	for i in WALLS.size():
		var spec: Array = WALLS[i]
		_wall(geo, spec[0], spec[1], spec[2], spec[3], spec[4], "wall_%d" % i)
	for i in BLOCKS.size():
		var spec: Array = BLOCKS[i]
		if spec[3] == "":
			_box(geo, spec[0], spec[1], material("duct"), "block_%d" % i)
		else:
			# Collider keeps the exact box; the visual is the Kenney model fitted to it.
			_box(geo, spec[0], spec[1], null, "block_%d" % i, true, false)
			var bottom: Vector3 = spec[0] - Vector3(0, spec[1].y * 0.5, 0)
			var fit := prop(geo, spec[3], Vector2(bottom.x, bottom.z), bottom.y, 0.0, Vector3.ONE, false, "block_%d_model" % i)
			var inst: Node3D = fit.get_child(0)
			var raw := AABB()
			var first := true
			for m in inst.find_children("*", "MeshInstance3D", true, false):
				var b: AABB = (fit.global_transform.affine_inverse() * (m as MeshInstance3D).global_transform) * (m as MeshInstance3D).get_aabb()
				raw = b if first else raw.merge(b)
				first = false
			fit.scale = Vector3(spec[1].x / raw.size.x, spec[1].y / raw.size.y, spec[1].z / raw.size.z)
	for i in FURNITURE.size():
		var f: Array = FURNITURE[i]
		prop(geo, f[0], f[1], 0.0, f[2], f[3], f[4], "furn_%d_%s" % [i, f[0]])
	for i in DESKTOP.size():
		var t: Array = DESKTOP[i]
		prop(geo, t[0], Vector2(t[1].x, t[1].z), t[1].y, t[2], Vector3.ONE * t[3], false, "top_%d_%s" % [i, t[0]])
	# Whiteboard on the classroom's front wall (visual only).
	_box(geo, Vector3(4.0, 1.6, 0.12), Vector3(2.4, 1.1, 0.04), material("board"), "whiteboard", false)
	var doors := {}
	for dd in DOORS:
		var door := Door.new()
		geo.add_child(door)
		door.setup(dd.id, dd.hinge, dd.yaw)
		doors[dd.id] = door
	var lamps: Array[OmniLight3D] = []
	for i in LAMPS.size():
		var lamp := OmniLight3D.new()
		lamp.name = "lamp_%d" % i
		lamp.position = LAMPS[i][0]
		lamp.omni_range = 6.5
		lamp.light_energy = 0.7
		lamp.light_color = Color(0.85, 0.95, 0.85)
		lamp.set_meta("flicker", LAMPS[i][1])
		geo.add_child(lamp)
		lamps.append(lamp)
		prop(geo, "lampSquareCeiling", Vector2(LAMPS[i][0].x, LAMPS[i][0].z), CEILING - 0.46, 0.0, Vector3.ONE, false, "lamp_%d_fixture" % i)
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		var sign := Label3D.new()
		sign.name = "sign_" + id
		sign.text = r.label
		sign.pixel_size = 0.003
		sign.modulate = Color(0.85, 0.85, 0.8)
		sign.position = Vector3((r.min.x + r.max.x) * 0.5, 2.6, r.min.y + 0.13)
		geo.add_child(sign)
	var bay := MeshInstance3D.new()
	bay.name = "LoadingBay"
	var pm := PlaneMesh.new()
	var ext_min: Vector3 = EXTRACTION.min
	var ext_max: Vector3 = EXTRACTION.max
	pm.size = Vector2(ext_max.x - ext_min.x, ext_max.z - ext_min.z)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.25, 0.55, 0.3)
	bmat.emission_enabled = true
	bmat.emission = Color(0.05, 0.25, 0.08)
	pm.material = bmat
	bay.mesh = pm
	bay.position = Vector3((ext_min.x + ext_max.x) * 0.5, 0.01, (ext_min.z + ext_max.z) * 0.5)
	geo.add_child(bay)
	var exit_sign := Label3D.new()
	exit_sign.text = "EXIT"
	exit_sign.position = Vector3(9.5, 2.3, 0.15)
	exit_sign.pixel_size = 0.004
	exit_sign.modulate = Color(0.6, 0.9, 0.6)
	geo.add_child(exit_sign)
	return {"doors": doors, "spawn": SPAWN, "extraction": AABB(ext_min, ext_max - ext_min), "solids": solids.duplicate(), "bounds": BOUNDS, "lamps": lamps}

# Which room a point is in ("" outside every room).
static func room_at(p: Vector3) -> String:
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		if p.x >= r.min.x and p.x <= r.max.x and p.z >= r.min.y and p.z <= r.max.y: return id
	return ""
