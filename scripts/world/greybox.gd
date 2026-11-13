extends RefCounted
# Movement sandbox (Sir, 2026-11-09: "a big and wide gray box to simulate the
# movements"). One flat grey arena, 120 x 80 m with 8 m walls, built from data:
# a slide gap, jump ledges at 1/2/3 m, 30 and 45 degree ramps, a stair run,
# pillars, a crate field, low cover walls, a jump course and two tall
# parallel walls. Since P7 the game world is the Dark Forest (dark_forest.gd);
# this arena stays for the movement and rule tests. Boxes only, so collision
# and visuals always agree; every solid is recorded in `solids` for the
# navigation grid. World axes: +X east, +Z south, +Y up; metres. The lab
# (doors, terminals, notes) is in reference/legacy-campus/.

const SIZE := Vector2(120, 80)
const BOUNDS := [Vector2(0, 0), Vector2(120, 80)]
const ARENA_WALL_H := 8.0      # tall enough for wall running later
const ARENA_WALL_T := 0.4
const SPAWN := {"at": Vector3(60, 0, 40), "yaw": 0.0} # centre, facing north

# Movement test props.
const SLIDE_GAP := {"x": [52.0, 68.0], "z": 30.0, "t": 0.4, "h": 3.0, "gap_x": [58.0, 62.0], "clearance": 1.25}
const LEDGES := [[86.0, 1.0], [92.0, 2.0], [98.0, 3.0]] # [centre x, top]; 4 m (x) by 6 m (z), centred on LEDGE_Z
const LEDGE_Z := 40.0
const RAMPS := [[27.0, 30.0, 2.0], [35.0, 45.0, 2.0], [19.0, 55.0, 2.0]] # (55° is steeper than walkable: a wall)
# [centre x, angle deg, height]; rise toward -Z from RAMP_START_Z, 4 m platform on top
const RAMP_START_Z := 50.0
const RAMP_W := 4.0
const STAIRS := {"x": 46.5, "w": 3.0, "start_z": 50.0, "rise": 0.3, "run": 0.45, "steps": 6}
const PILLARS := [Vector2(40, 28), Vector2(80, 28), Vector2(40, 64), Vector2(80, 64)]
const PILLAR := Vector3(1.6, 8.0, 1.6)
# More obstacles (playtest 2026-11-09: "add more obstacles").
const CRATES := [ # [centre x, centre z, size]: cover field south-east, boxes 1-2 m
	[72.0, 58.0, 1.0], [74.5, 61.0, 1.5], [71.0, 66.0, 2.0], [76.0, 70.0, 1.0], [84.0, 58.5, 1.5],
	[86.0, 63.0, 1.0], [88.5, 68.0, 2.0], [92.0, 59.0, 1.0], [95.0, 64.5, 1.5], [93.0, 71.0, 1.0],
	[98.0, 57.0, 2.0], [99.0, 68.5, 1.5]]
const COVER_WALLS := [[30.0, 38.0, 62.0], [34.0, 42.0, 70.0], [44.0, 50.0, 66.0]] # [x from, x to, z]: 1 m high, 0.4 m thick
const COVER_H := 1.0
const JUMP_COURSE := [[92.5, 0.6], [99.0, 1.2], [105.5, 1.8], [112.0, 2.4]] # [centre x, top]: 5 x 3 m blocks at z 18, 1.5 m gaps (a 10 m/s hop carries ~6 m)
const JUMP_W := 5.0
const JUMP_COURSE_Z := 18.0
const RUN_WALLS := [40.0, 44.0] # two 6 m walls along z 2-22, 4 m apart (wall running later)
const RUN_WALL_Z := [2.0, 22.0]
const RUN_WALL_H := 6.0
# R1e movement props: a drop tower (fall stun, tall climbs, bounce chains) with a
# 41° access ramp, a long 60° surf wedge on the south wall, a two-tier clamber block.
const TOWER := {"x": [2.0, 8.0], "z": [44.0, 50.0], "h": 20.9}
const TOWER_RAMP_RUN := 24.0   # rises toward -Z from z 74 to the tower's south face
const SURF := {"x": [70.0, 110.0], "h": 4.0, "angle": 60.0} # face slopes from the south wall (z 80) down to the floor
const CURB := {"x": [70.0, 74.0], "z": [52.0, 53.0], "h": 0.4} # an overwalkable curb (insta-mantle)
const CLAMBER := [[106.0, 40.0, 4.0, 4.0, 2.0], [106.0, 39.6, 4.0, 3.2, 3.6]] # tier 2 face 0.8 m behind tier 1 # [x, z, w, d, top]

# Grimoire pages lying in the world (P5): Quick Step near the start, Ring of
# Fire and Sage Arts further out (the game's own spots are in dark_forest.gd).
const PAGE_SPOTS := {
	"quick_step": Vector3(66, 0, 46),
	"ring_of_fire": Vector3(20, 0, 66),
	"sage_arts": Vector3(108, 0, 72),
}
# Blighted Sprites (P3): six roam spots round the arena, each over 30 m from the
# player spawn (60, 40) so none aggroes at the start (16 m).
const ENEMIES := [
	{"id": "sprite_1", "kind": "sprite", "at": Vector3(35, 0, 60), "yaw": 0.0},
	{"id": "sprite_2", "kind": "sprite", "at": Vector3(85, 0, 62), "yaw": 0.0},
	{"id": "sprite_3", "kind": "sprite", "at": Vector3(100, 0, 28), "yaw": 90.0},
	{"id": "sprite_4", "kind": "sprite", "at": Vector3(45, 0, 72), "yaw": 0.0},
	{"id": "sprite_5", "kind": "sprite", "at": Vector3(75, 0, 72), "yaw": 0.0},
	{"id": "sprite_6", "kind": "sprite", "at": Vector3(105, 0, 50), "yaw": -90.0},
]
# Every solid box built (world AABBs), for navigation. Filled by build().
static var solids: Array[AABB] = []
static var _mats := {}

# ---- materials (procedural, cached) ----------------------------------------

# A grey grid: a thin line every metre, a heavier one every 5 m, so distances
# and speeds can be judged by eye. One texture tile covers 5 x 5 m.
static func _grid_texture(base: Color, line: Color) -> ImageTexture:
	var px := 32
	var img := Image.create(px * 5, px * 5, false, Image.FORMAT_RGB8)
	for y in px * 5:
		for x in px * 5:
			var c := base
			if x % px == 0 or y % px == 0: c = line
			if x < 2 or y < 2: c = line.darkened(0.35)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func material(kind: String) -> StandardMaterial3D:
	if _mats.has(kind): return _mats[kind]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.9
	match kind:
		"floor", "wall":
			var g := Color(0.46, 0.46, 0.48) if kind == "floor" else Color(0.6, 0.6, 0.62)
			m.albedo_texture = _grid_texture(g, g.darkened(0.22))
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.2, 0.2, 0.2)
		"prop": m.albedo_color = Color(0.85, 0.55, 0.25)    # movement props stand out
		"ledge": m.albedo_color = Color(0.3, 0.55, 0.8)
		"pillar": m.albedo_color = Color(0.38, 0.38, 0.4)
		"crate": m.albedo_color = Color(0.55, 0.45, 0.3)
		_: m.albedo_color = Color(0.5, 0.5, 0.5)
	_mats[kind] = m
	return m

# ---- builders ----------------------------------------------------------------

# A box (StaticBody3D + collider when solid). `basis` rotates it; its world
# AABB (rotated corners) goes into `solids`.
static func _box(parent: Node3D, centre: Vector3, size: Vector3, mat: Material, nm: String, solid := true, visual := true, basis := Basis()) -> Node3D:
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
		var xf := Transform3D(basis, centre)
		var box := AABB(xf * (-size * 0.5), Vector3.ZERO)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					box = box.expand(xf * (Vector3(sx, sy, sz) * size * 0.5))
		solids.append(box)
	else:
		node = Node3D.new()
	node.name = nm
	node.transform = Transform3D(basis, centre)
	if visual:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mesh.mesh = bm
		node.add_child(mesh)
	parent.add_child(node)
	return node

# Wall along X (z fixed) or along Z (x fixed) from a to b, height h, thickness
# t, with openings [[from, to, opening height]] (a lintel fills above each).
static func _wall(parent: Node3D, along_x: bool, fixed: float, a: float, b: float, gaps: Array, h: float, t: float, mat: Material, nm: String) -> void:
	var cuts: Array = [[a, a, 0.0]]
	for g in gaps: cuts.append(g)
	cuts.append([b, b, 0.0])
	for i in range(cuts.size() - 1):
		var s: float = cuts[i][1]
		var e: float = cuts[i + 1][0]
		if e - s > 0.001: _piece(parent, along_x, fixed, s, e, 0.0, h, t, mat, "%s_%d" % [nm, i])
		if i + 1 < cuts.size() - 1:
			var g: Array = cuts[i + 1]
			if h - float(g[2]) > 0.001: _piece(parent, along_x, fixed, float(g[0]), float(g[1]), float(g[2]), h, t, mat, "%s_lintel_%d" % [nm, i])

static func _piece(parent: Node3D, along_x: bool, fixed: float, s: float, e: float, y0: float, y1: float, t: float, mat: Material, nm: String) -> void:
	var mid := (s + e) * 0.5
	var hh := y1 - y0
	var c := Vector3(mid, y0 + hh * 0.5, fixed) if along_x else Vector3(fixed, y0 + hh * 0.5, mid)
	var size := Vector3(e - s, hh, t) if along_x else Vector3(t, hh, e - s)
	_box(parent, c, size, mat, nm)

static func _label(parent: Node3D, text: String, at: Vector3, px := 0.008) -> void:
	var l := Label3D.new()
	l.name = "label_" + text.replace(" ", "_").replace(".", "")
	l.text = text
	l.position = at
	l.pixel_size = px
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.95, 0.95, 0.9)
	parent.add_child(l)

# Horizontal run of a ramp spec.
static func ramp_run(ramp: Array) -> float:
	return float(ramp[2]) / tan(deg_to_rad(float(ramp[1])))

# Builds everything under `parent` (which must be in the scene tree).
static func build(parent: Node3D) -> Dictionary:
	solids.clear()
	var geo := Node3D.new()
	geo.name = "Greybox"
	parent.add_child(geo)
	var w := SIZE.x
	var d := SIZE.y
	_box(geo, Vector3(w * 0.5, -0.1, d * 0.5), Vector3(w + 1.0, 0.2, d + 1.0), material("floor"), "floor")
	var wall := material("wall")
	_wall(geo, true, 0.0, 0.0, w, [], ARENA_WALL_H, ARENA_WALL_T, wall, "arena_north")
	_wall(geo, true, d, 0.0, w, [], ARENA_WALL_H, ARENA_WALL_T, wall, "arena_south")
	_wall(geo, false, 0.0, 0.0, d, [], ARENA_WALL_H, ARENA_WALL_T, wall, "arena_west")
	_wall(geo, false, w, 0.0, d, [], ARENA_WALL_H, ARENA_WALL_T, wall, "arena_east")
	# Slide gap: a 3 m wall with a 4 m wide, 1.25 m high opening (crouch 1.1 m fits, standing 1.8 m does not).
	var sg := SLIDE_GAP
	_wall(geo, true, sg.z, sg.x[0], sg.x[1], [[sg.gap_x[0], sg.gap_x[1], sg.clearance]], sg.h, sg.t, material("prop"), "slide_gap")
	_label(geo, "SLIDE GAP 1.25 m", Vector3((sg.gap_x[0] + sg.gap_x[1]) * 0.5, sg.h + 0.5, sg.z))
	for i in LEDGES.size():
		var l: Array = LEDGES[i]
		_box(geo, Vector3(l[0], l[1] * 0.5, LEDGE_Z), Vector3(4, l[1], 6), material("ledge"), "ledge_%d" % i)
		_label(geo, "%.0f m" % l[1], Vector3(l[0], l[1] + 0.6, LEDGE_Z + 3.3))
	for i in RAMPS.size():
		var r: Array = RAMPS[i]
		var a := deg_to_rad(float(r[1]))
		var h: float = r[2]
		var run := ramp_run(r)
		var t := 0.4
		var length := sqrt(run * run + h * h) + 0.2 # a little extra so the top end tucks into the platform
		var normal := Vector3(0, cos(a), sin(a))      # local +Y after rotating about +X by a
		var centre := Vector3(r[0], h * 0.5, RAMP_START_Z - run * 0.5) - normal * t * 0.5
		_box(geo, centre, Vector3(RAMP_W, t, length), material("prop"), "ramp_%d" % i, true, true, Basis(Vector3.RIGHT, a))
		_box(geo, Vector3(r[0], h * 0.5, RAMP_START_Z - run - 2.0), Vector3(RAMP_W, h, 4.0), material("ledge"), "ramp_%d_top" % i)
		_label(geo, "%.0f deg" % r[1], Vector3(r[0], 0.9, RAMP_START_Z + 0.8))
	var st := STAIRS
	for i in int(st.steps):
		var top: float = st.rise * (i + 1)
		_box(geo, Vector3(st.x, top * 0.5, st.start_z - st.run * (i + 0.5)), Vector3(st.w, top, st.run), material("prop"), "stair_%d" % i)
	_label(geo, "STAIRS 0.3 m", Vector3(st.x, 0.9, st.start_z + 0.8))
	for i in PILLARS.size():
		_box(geo, Vector3(PILLARS[i].x, PILLAR.y * 0.5, PILLARS[i].y), PILLAR, material("pillar"), "pillar_%d" % i)
	for i in CRATES.size():
		var cr: Array = CRATES[i]
		_box(geo, Vector3(cr[0], cr[2] * 0.5, cr[1]), Vector3.ONE * float(cr[2]), material("crate"), "crate_%d" % i)
	for i in COVER_WALLS.size():
		var cw: Array = COVER_WALLS[i]
		_wall(geo, true, cw[2], cw[0], cw[1], [], COVER_H, 0.4, material("prop"), "cover_%d" % i)
	for i in JUMP_COURSE.size():
		var jc: Array = JUMP_COURSE[i]
		_box(geo, Vector3(jc[0], jc[1] * 0.5, JUMP_COURSE_Z), Vector3(JUMP_W, jc[1], 3), material("ledge"), "jump_%d" % i)
	_label(geo, "JUMP COURSE", Vector3(102, 3.4, JUMP_COURSE_Z))
	for i in RUN_WALLS.size():
		_wall(geo, false, RUN_WALLS[i], RUN_WALL_Z[0], RUN_WALL_Z[1], [], RUN_WALL_H, 0.4, material("pillar"), "run_wall_%d" % i)
	# Drop tower and its ramp.
	var tw: Dictionary = TOWER
	var tx: float = (tw.x[0] + tw.x[1]) * 0.5
	var twd: float = tw.x[1] - tw.x[0]
	_box(geo, Vector3(tx, tw.h * 0.5, (tw.z[0] + tw.z[1]) * 0.5), Vector3(twd, tw.h, tw.z[1] - tw.z[0]), material("pillar"), "drop_tower")
	var ta := atan2(tw.h, TOWER_RAMP_RUN)
	var tlen := sqrt(TOWER_RAMP_RUN * TOWER_RAMP_RUN + tw.h * tw.h) + 0.3
	var tnorm := Vector3(0, cos(ta), sin(ta))
	_box(geo, Vector3(tx, tw.h * 0.5, tw.z[1] + TOWER_RAMP_RUN * 0.5) - tnorm * 0.2, Vector3(twd, 0.4, tlen), material("prop"), "tower_ramp", true, true, Basis(Vector3.RIGHT, ta))
	_label(geo, "DROP TOWER %.0f m" % tw.h, Vector3(tx, tw.h + 1.0, (tw.z[0] + tw.z[1]) * 0.5))
	# Surf wedge: a slab whose top face slopes at SURF.angle from the south wall down to the floor.
	var sa := deg_to_rad(float(SURF.angle))
	var srun: float = SURF.h / tan(sa)
	var slen: float = sqrt(srun * srun + SURF.h * SURF.h)
	var snorm := Vector3(0, cos(sa), -sin(sa)) # faces north and up
	var sx: float = (SURF.x[0] + SURF.x[1]) * 0.5
	_box(geo, Vector3(sx, SURF.h * 0.5, SIZE.y - srun * 0.5) - snorm * 0.3, Vector3(SURF.x[1] - SURF.x[0], 0.6, slen), material("ledge"), "surf_wedge", true, true, Basis(Vector3.RIGHT, -sa))
	_label(geo, "SURF %.0f deg" % SURF.angle, Vector3(sx, SURF.h + 0.6, SIZE.y - 1.0))
	for i in CLAMBER.size():
		var cb: Array = CLAMBER[i]
		_box(geo, Vector3(cb[0], cb[4] * 0.5, cb[1]), Vector3(cb[2], cb[4], cb[3]), material("ledge"), "clamber_%d" % i)
	_label(geo, "CLAMBER", Vector3(106, 4.2, 42.2))
	_box(geo, Vector3((CURB.x[0] + CURB.x[1]) * 0.5, CURB.h * 0.5, (CURB.z[0] + CURB.z[1]) * 0.5), Vector3(CURB.x[1] - CURB.x[0], CURB.h, CURB.z[1] - CURB.z[0]), material("prop"), "curb")
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	geo.add_child(sun)
	var lamps: Array[OmniLight3D] = []
	return {"spawn": SPAWN, "solids": solids.duplicate(), "bounds": BOUNDS, "lamps": lamps}

