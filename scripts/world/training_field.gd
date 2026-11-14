extends Node3D
# The Training Field [Sir, 2026-11-14]: a separate 200 x 200 m practice ground,
# in daylight, reached only by the player through a portal beside the camp.
#   - Movement drills: the movement sandbox's props (slide gap, 1/2/3 m ledges,
#     ramps, stairs, jump course, run walls, drop tower, surf wedge, clamber)
#     in the north-west.
#   - Rock formations in the north-east: a boulder field, a rising rock
#     staircase, a climbing tower with a side ledge, and an arch to slide under.
#   - A dummy yard in the south-west: training dummies that never die and take
#     no damage, but show every hit as a damage number and a running total.
#     Some stand on platforms, some strafe.
#   - A target range in the south-east: boards at 10, 20, 30, 50 and 80 m from a
#     firing line; a hit flashes the board and counts.
#   - The return portal behind the arrival pad.
# It lives far from the forest (ORIGIN), with no trees and no enemies. Entering
# turns the world to day (sun, sky, fog) and hides the forest; leaving restores
# the night. Portals are checked against the player only, so nothing else can
# pass, and both are sealed while the player is in combat.
#
# Usage (main): var t := TrainingField.new(); add_child(t); t.build(self)
#   simulate -> t.check_portals(now); combat_targets -> += t.targets();
#   effects_step -> t.tick(delta, now); _effect_ticks -> t.health_of(id)

const Greybox = preload("res://scripts/world/greybox.gd")
const Forest = preload("res://scripts/world/dark_forest.gd")
const Health = preload("res://scripts/combat/health_component.gd")
const BodyModel = preload("res://scripts/actors/body_model.gd")

const ORIGIN := Vector3(1000, 0, 0)    # the field's north-west corner, far from the forest
const SIZE := 200.0
const WALL_H := 40.0                   # invisible boundary
const ARRIVE := Vector3(100, 0, 190)   # local: the arrival pad, facing north
const RETURN_PORTAL := Vector3(100, 0, 196)
const FOREST_PORTAL := Vector3(88, 0, 131) # world: east of the camp fire, facing the camp (west)
const FOREST_ARRIVE := Vector3(85, 0, 131)
const PORTAL_SIZE := Vector2(2.4, 3.2)
const PORTAL_R := 1.1                  # stepping this close to a portal's centre goes through
const PORTAL_COOLDOWN := 1.0
const DRILLS_AT := Vector3(5, 0, 6)    # local offset of the movement sandbox (120 x 80 m)
const DUMMY_LAYER := 0b1000            # the enemy layer: the player bumps into them, sight lines pass
const TOTAL_RESET_S := 3.0             # a dummy's running total clears after this long without a hit

# Dummies: [local x, local z, platform height, strafe half-width (0 = still)].
const DUMMIES := [
	[25, 150, 0, 0], [37, 150, 0, 0], [49, 150, 0, 0], [61, 150, 0, 0], [73, 150, 0, 0],
	[25, 135, 0, 0], [40, 135, 0, 0], [55, 135, 0, 0], [70, 135, 0, 0],
	[30, 165, 2.0, 0], [55, 165, 2.0, 0], [80, 165, 3.0, 0],
	[35, 118, 0, 4.0], [60, 118, 0, 5.0], [85, 125, 0, 3.0],
	[85, 145, 0, 0], [85, 175, 0, 0], [15, 175, 0, 0],
]
const STRAFE_SPEED := 2.5
# Target range: boards at these distances from the firing line (local z 190), three per distance.
const RANGE_LINE_Z := 190.0
const RANGE_X := [125.0, 150.0, 175.0]
const RANGE_DIST := [10.0, 20.0, 30.0, 50.0, 80.0]
const BOARD_R := {10.0: 0.6, 20.0: 0.7, 30.0: 0.8, 50.0: 1.0, 80.0: 1.3}
# Rock formations (local): [x, z, w, d, h] boxes, each dressed with a kit rock.
const ROCKS := [
	# boulder field: mantle practice, 1 to 2.5 m
	[148, 20, 2.5, 2.5, 1.0], [154, 26, 3.0, 2.5, 1.6], [146, 31, 2.0, 2.0, 1.2], [160, 18, 3.0, 3.0, 2.2],
	[158, 34, 2.5, 3.0, 2.5], [166, 28, 2.0, 2.5, 1.4], [150, 40, 3.0, 2.0, 1.8], [168, 40, 2.5, 2.5, 2.0],
	# rock staircase: 1, 2, 3, 4, 5 m, one mantle each
	[176, 15, 4.0, 4.0, 1.0], [176, 19.5, 4.0, 4.0, 2.0], [176, 24, 4.0, 4.0, 3.0], [176, 28.5, 4.0, 4.0, 4.0], [176, 33, 4.0, 4.0, 5.0],
	# climbing tower 7 m with a 3.5 m side ledge
	[188, 55, 5.0, 5.0, 7.0], [182, 55, 3.0, 4.0, 3.5],
	# arch: two pillars and a slab with a 1.2 m slide gap beneath
	[150, 70, 2.5, 3.0, 4.0], [158, 70, 2.5, 3.0, 4.0],
	# scattered cover near the range
	[145, 88, 3.0, 2.0, 1.5], [165, 85, 2.5, 2.5, 2.2], [185, 80, 3.0, 3.0, 3.0],
]
const ARCH_SLAB := [154, 70, 10.5, 3.0, 4.0, 1.2] # [x, z, w, d, top, thickness]

var main: Node3D
var active := false           # the player is in the field
var field: Node3D             # everything at ORIGIN
var sun: DirectionalLight3D
var dummies: Array = []       # {id, body, health, label, base, strafe, pos, total, last_hit_t, hits}
var boards: Array = []        # {id, body, health, mat, dist, hits, flash}
var forest_portal: Node3D
var return_portal: Node3D
var _portal_ready_at := 0.0
var _locked_notice_at := -INF
var _night := {}              # the forest's environment, restored on leaving
var _phase := 0.0
var log: Array = []           # {id, amount, time}: hits recorded (tests)

func build(world: Node3D) -> void:
	main = world
	name = "TrainingField"
	field = Node3D.new()
	field.name = "Field"
	field.position = ORIGIN
	add_child(field)
	_ground()
	_drills()
	_rocks()
	_dummy_yard()
	_range()
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.visible = false
	add_child(sun)
	return_portal = _portal(field, RETURN_PORTAL, 0.0, "ReturnPortal")
	_label(field, "TO THE FOREST", RETURN_PORTAL + Vector3(0, PORTAL_SIZE.y + 0.6, 0), 0.012)
	forest_portal = _portal(self, FOREST_PORTAL, 90.0, "ForestPortal")
	_label(self, "TRAINING FIELD", FOREST_PORTAL + Vector3(0, PORTAL_SIZE.y + 0.6, 0), 0.012)
	field.visible = false

# ---- the field ------------------------------------------------------------------------------

func _ground() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _field_grid()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.1, 0.1, 0.1)
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_solid(field, Vector3(SIZE * 0.5, -0.1, SIZE * 0.5), Vector3(SIZE + 2.0, 0.2, SIZE + 2.0), m, "ground")
	for side in [[Vector3(SIZE * 0.5, WALL_H * 0.5, -0.2), Vector3(SIZE + 1, WALL_H, 0.4)], [Vector3(SIZE * 0.5, WALL_H * 0.5, SIZE + 0.2), Vector3(SIZE + 1, WALL_H, 0.4)],
			[Vector3(-0.2, WALL_H * 0.5, SIZE * 0.5), Vector3(0.4, WALL_H, SIZE + 1)], [Vector3(SIZE + 0.2, WALL_H * 0.5, SIZE * 0.5), Vector3(0.4, WALL_H, SIZE + 1)]]:
		_solid(field, side[0], side[1], null, "bound")
	# The arrival pad and the firing line, painted on the ground.
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.85, 0.8, 0.6)
	_solid(field, ARRIVE + Vector3(0, 0.02, 2), Vector3(8, 0.04, 8), pad, "arrival_pad", false)
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.95, 0.85, 0.2)
	line.emission_enabled = true
	line.emission = Color(0.95, 0.85, 0.2)
	line.emission_energy_multiplier = 0.3
	_solid(field, Vector3(150, 0.02, RANGE_LINE_Z), Vector3(80, 0.04, 0.4), line, "firing_line", false)
	_label(field, "TARGET RANGE", Vector3(150, 2.6, RANGE_LINE_Z + 1.5), 0.014)
	_label(field, "TRAINING DUMMIES", Vector3(50, 3.2, 180), 0.014)
	_label(field, "MOVEMENT DRILLS", Vector3(65, 4.5, 92), 0.016)
	_label(field, "ROCK FORMATIONS", Vector3(165, 4.5, 8), 0.016)

# The movement sandbox's props, as they are, without its floor, walls and light.
func _drills() -> void:
	var holder := Node3D.new()
	holder.name = "Drills"
	holder.position = DRILLS_AT
	field.add_child(holder)
	Greybox.build(holder)
	var geo: Node3D = holder.get_node("Greybox")
	for ch in geo.get_children():
		var nm := String(ch.name)
		if nm == "floor" or nm.begins_with("arena_") or ch is DirectionalLight3D:
			geo.remove_child(ch)
			ch.free()

func _rocks() -> void:
	var kinds := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.52)
	for i in ROCKS.size():
		var r: Array = ROCKS[i]
		var centre := Vector3(r[0], float(r[4]) * 0.5, r[1])
		var size := Vector3(r[2], r[4], r[3])
		var have_kit := _kit_rock(field, kinds[i % kinds.size()], Vector3(r[0], 0, r[1]), size, (i * 37) % 360, "rock_%d" % i)
		_solid(field, centre, size, null if have_kit else mat, "rock_col_%d" % i)
	var a: Array = ARCH_SLAB
	var slab_c := Vector3(a[0], float(a[4]) - float(a[5]) * 0.5, a[1])
	var slab := Vector3(a[2], a[5], a[3])
	var have := _kit_rock(field, "Rock_Medium_2", Vector3(a[0], float(a[4]) - float(a[5]), a[1]), slab, 90.0, "arch_slab")
	_solid(field, slab_c, slab, null if have else mat, "arch_col")
	_label(field, "ARCH: slide under", Vector3(154, 0.9, 72.5), 0.008)
	_label(field, "ROCK STAIRS 1-5 m", Vector3(176, 6.0, 33), 0.008)
	_label(field, "CLIMB 7 m", Vector3(188, 7.6, 55), 0.008)

# A Nature-kit rock stretched to a box (it stands on `base`); false if the kit is missing.
func _kit_rock(parent: Node3D, kind: String, base: Vector3, size: Vector3, yaw: float, nm: String) -> bool:
	var e: Array = Forest._kit(kind)
	if e.is_empty(): return false
	var aabb: AABB = (e[0][1] as Transform3D) * (e[0][0] as Mesh).get_aabb()
	var sc := Vector3(size.x / maxf(aabb.size.x, 0.1), size.y / maxf(aabb.size.y, 0.1), size.z / maxf(aabb.size.z, 0.1)) * 1.06
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = e[0][0]
	var yb := Basis(Vector3.UP, PI if int(yaw) % 360 >= 180 else 0.0) # 0 or 180 deg: the collider box stays aligned
	mi.transform = Transform3D(yb * Basis.from_scale(sc), base + Vector3(0, -aabb.position.y * sc.y, 0)) * (e[0][1] as Transform3D)
	parent.add_child(mi)
	return true

func _dummy_yard() -> void:
	var plat := StandardMaterial3D.new()
	plat.albedo_color = Color(0.55, 0.5, 0.42)
	for i in DUMMIES.size():
		var d: Array = DUMMIES[i]
		var h: float = d[2]
		if h > 0.0: _solid(field, Vector3(d[0], h * 0.5, d[1]), Vector3(3, h, 3), plat, "dummy_platform_%d" % i)
		dummies.append(_dummy(i, Vector3(d[0], h, d[1]), float(d[3])))

func _dummy(i: int, local_at: Vector3, strafe: float) -> Dictionary:
	var body := StaticBody3D.new()
	body.name = "dummy_%d" % i
	body.collision_layer = DUMMY_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	body.add_child(col)
	body.position = local_at
	body.rotation.y = 0.0 # faces south, toward the arrival pad
	field.add_child(body)
	var built: Dictionary = BodyModel.build(body, i % 3 == 1, Color(0.85, 0.72, 0.45), {})
	built.model.rotation.y = 0.0 # a dummy faces +Z (the player comes from the south)
	if built.anim.has_animation("idle"):
		built.anim.play("idle")
		built.anim.seek(float(i) * 0.37, true)
	var hp: Node = Health.new()
	hp.name = "Health"
	hp.max_hp = 1.0e12
	hp.faction = "training"
	body.add_child(hp)
	hp.reset()
	var lbl := Label3D.new()
	lbl.name = "Total"
	lbl.position.y = 2.25
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.outline_size = 8
	lbl.modulate = Color(1.0, 0.95, 0.75)
	lbl.text = ""
	body.add_child(lbl)
	var d := {"id": "dummy_%d" % i, "kind": "dummy", "body": body, "health": hp, "label": lbl, "base": local_at, "strafe": strafe,
		"total": 0.0, "last_hit_t": -INF, "hits": 0, "radius": 0.35}
	hp.damaged.connect(_on_hit.bind(d))
	return d

func _range() -> void:
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.35, 0.3, 0.25)
	for dist in RANGE_DIST:
		var z: float = RANGE_LINE_Z - float(dist)
		_label(field, "%d m" % int(dist), Vector3(112, 0.6, z), 0.01)
		for x in RANGE_X:
			var r: float = BOARD_R[dist]
			var cy := 1.4 + r
			_solid(field, Vector3(x, cy * 0.5, z - 0.15), Vector3(0.15, cy, 0.15), post, "post", false)
			var body := StaticBody3D.new()
			body.name = "board_%d_%d" % [int(dist), int(x)]
			body.collision_layer = DUMMY_LAYER
			body.collision_mask = 0
			var col := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = r
			cyl.height = 0.12
			col.shape = cyl
			col.rotation.x = PI * 0.5
			body.add_child(col)
			body.position = Vector3(x, cy, z)
			field.add_child(body)
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = 0.12
			cm.radial_segments = 24
			mi.mesh = cm
			mi.rotation.x = PI * 0.5
			var mat := StandardMaterial3D.new()
			mat.albedo_texture = _bullseye()
			mat.emission_enabled = true
			mat.emission = Color(1, 0.3, 0.2)
			mat.emission_energy_multiplier = 0.0
			mi.material_override = mat
			body.add_child(mi)
			var hp: Node = Health.new()
			hp.name = "Health"
			hp.max_hp = 1.0e12
			hp.faction = "training"
			body.add_child(hp)
			hp.reset()
			var b := {"id": "board_%d_%d" % [int(dist), int(x)], "kind": "board", "body": body, "health": hp, "mat": mat, "dist": dist, "hits": 0, "flash": 0.0, "radius": r,
				"total": 0.0, "last_hit_t": -INF, "label": null}
			hp.damaged.connect(_on_hit.bind(b))
			boards.append(b)

# A 10 m grass-green tile with even 2 m lines (no darker seam: the sandbox grid's
# tile edge drew a stripe straight ahead of the arrival pad).
static var _grid: ImageTexture
static func _field_grid() -> ImageTexture:
	if _grid: return _grid
	var px := 32
	var img := Image.create(px * 5, px * 5, false, Image.FORMAT_RGB8)
	var base := Color(0.42, 0.56, 0.3)
	var line := Color(0.37, 0.5, 0.27)
	for y in px * 5:
		for x in px * 5:
			img.set_pixel(x, y, line if (x % px == 0 or y % px == 0) else base)
	img.generate_mipmaps()
	_grid = ImageTexture.create_from_image(img)
	return _grid

static var _bull: ImageTexture
static func _bullseye() -> ImageTexture:
	if _bull: return _bull
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var ring := int(d * 5.0)
			img.set_pixel(x, y, Color(0.85, 0.15, 0.12) if ring % 2 == 0 else Color(0.95, 0.93, 0.88))
	_bull = ImageTexture.create_from_image(img)
	return _bull

# ---- portals ------------------------------------------------------------------------------

const PORTAL_SCENE := "res://assets/BinbunVFX/portal_vfx/effects/simple/simple_portal_vfx.tscn"
const OPEN_COLOR := Color(0.35, 0.75, 1.0)
const LOCKED_COLOR := Color(0.85, 0.15, 0.12)

func _portal(parent: Node3D, at: Vector3, yaw: float, nm: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	holder.position = at
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	if ResourceLoader.exists(PORTAL_SCENE):
		var p: Node3D = (load(PORTAL_SCENE) as PackedScene).instantiate()
		p.name = "Portal"
		p.position.y = PORTAL_SIZE.y * 0.5 + 0.05
		holder.add_child(p)
		if "size" in p: p.size = PORTAL_SIZE
		if "primary_color" in p: p.primary_color = OPEN_COLOR
		if "secondary_color" in p: p.secondary_color = Color(0.05, 0.12, 0.25)
		for l in p.find_children("*", "OmniLight3D", true, false): (l as OmniLight3D).omni_range = 4.0
	# A stone frame either side (solid: the portal is walked through, not round).
	for side in [-1.0, 1.0]:
		var c := Vector3(side * (PORTAL_SIZE.x * 0.5 + 0.35), PORTAL_SIZE.y * 0.5 + 0.1, 0)
		var size := Vector3(0.6, PORTAL_SIZE.y + 0.2, 0.7)
		if not _kit_rock(holder, "Rock_Medium_3", c - Vector3(0, c.y, 0), size, 0.0, "frame"):
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.45, 0.45, 0.47)
			_solid(holder, c, size, m, "frame_col")
		else:
			_solid(holder, c, size, null, "frame_col")
	return holder

func portal_open() -> bool:
	return not main.director.in_combat

func _tint_portals(open: bool) -> void:
	for h in [forest_portal, return_portal]:
		var p: Node3D = h.get_node_or_null("Portal") if h else null
		if p and "primary_color" in p:
			var want: Color = OPEN_COLOR if open else LOCKED_COLOR
			if p.primary_color != want: p.primary_color = want

# Called after the player moves each tick. Only the player is ever checked.
func check_portals(now: float) -> String:
	var p: CharacterBody3D = main.player
	if p.health.dead: return ""
	var open := portal_open()
	_tint_portals(open)
	var near_forest := _flat(p.global_position).distance_to(_flat(FOREST_PORTAL)) < PORTAL_R and not active
	var near_return := _flat(p.global_position).distance_to(_flat(ORIGIN + RETURN_PORTAL)) < PORTAL_R and active
	if not (near_forest or near_return): return ""
	if now < _portal_ready_at: return ""
	if not open:
		if now - _locked_notice_at > 2.0:
			_locked_notice_at = now
			if main.has_method("show_notice"): main.show_notice("The portal is sealed while you are in combat", 1.5)
		return "locked"
	_portal_ready_at = now + PORTAL_COOLDOWN
	if near_forest:
		enter()
		return "entered"
	leave()
	return "left"

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# ---- day and night ------------------------------------------------------------------------

func _env() -> Environment:
	var we: Array = main.find_children("*", "WorldEnvironment", true, false)
	return (we[0] as WorldEnvironment).environment if not we.is_empty() else null

func _moon() -> DirectionalLight3D:
	return main.find_child("Moon", true, false) as DirectionalLight3D

func enter() -> void:
	if active: return
	active = true
	_teleport(ORIGIN + ARRIVE, 0.0)
	field.visible = true
	if main._forest_node: main._forest_node.visible = false
	var e := _env()
	var moon := _moon()
	if e:
		_night = {"fog_density": e.fog_density, "fog_light_color": e.fog_light_color, "ambient_light_color": e.ambient_light_color,
			"ambient_light_energy": e.ambient_light_energy, "vfog": e.volumetric_fog_density, "vfog_albedo": e.volumetric_fog_albedo}
		e.fog_density = 0.0012
		e.fog_light_color = Color(0.6, 0.72, 0.88)
		e.ambient_light_color = Color(0.72, 0.76, 0.82)
		e.ambient_light_energy = 1.0
		e.volumetric_fog_density = 0.0
		e.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
		var sky: ShaderMaterial = e.sky.sky_material as ShaderMaterial if e.sky else null
		if sky:
			_night.sky = {}
			for k in ["day_night_mix", "cloud_color", "cloud_density", "sky_day", "horizon_day"]: _night.sky[k] = sky.get_shader_parameter(k)
			sky.set_shader_parameter("day_night_mix", 1.0)
			sky.set_shader_parameter("sky_day", Color(0.12, 0.38, 0.78))
			sky.set_shader_parameter("horizon_day", Color(0.62, 0.78, 0.92))
			sky.set_shader_parameter("cloud_color", Color(0.96, 0.97, 1.0))
			sky.set_shader_parameter("cloud_density", 0.5)
	if moon:
		_night.moon = moon.visible
		moon.visible = false
	sun.visible = true

func leave() -> void:
	if not active: return
	active = false
	_restore_night()
	_teleport(FOREST_ARRIVE, 90.0)

func _restore_night() -> void:
	field.visible = false
	sun.visible = false
	if main._forest_node: main._forest_node.visible = true
	var e := _env()
	if e and not _night.is_empty():
		e.fog_density = _night.fog_density
		e.fog_light_color = _night.fog_light_color
		e.ambient_light_color = _night.ambient_light_color
		e.ambient_light_energy = _night.ambient_light_energy
		e.volumetric_fog_density = _night.vfog
		e.volumetric_fog_albedo = _night.vfog_albedo
		var sky: ShaderMaterial = e.sky.sky_material as ShaderMaterial if e.sky else null
		if sky and _night.has("sky"):
			for k in _night.sky: sky.set_shader_parameter(k, _night.sky[k])
	var moon := _moon()
	if moon and _night.has("moon"): moon.visible = _night.moon
	_night = {}

# A run restart or death: back in the forest at night (the caller places the player).
func reset() -> void:
	if active:
		active = false
		_restore_night()
	for d in dummies + boards:
		d.total = 0.0
		d.hits = 0
		d.last_hit_t = -INF
		if d.label: d.label.text = ""
	log.clear()
	_portal_ready_at = 0.0

func _teleport(at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = main.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	if main.lofi: main.lofi.sync()

# ---- targets ------------------------------------------------------------------------------

# Combat targets (as main.combat_targets): the dummies (capsules) and boards (spheres), while active.
func targets() -> Array:
	if not active: return []
	var out := []
	for d in dummies:
		var at: Vector3 = d.body.global_position
		out.append({"id": d.id, "pos": at + Vector3(0, 1.0, 0), "radius": d.radius, "health": d.health, "body": d.body,
			"a": at + Vector3(0, d.radius, 0), "b": at + Vector3(0, 1.8 - d.radius, 0)})
	for b in boards:
		out.append({"id": b.id, "pos": b.body.global_position, "radius": b.radius, "health": b.health, "body": b.body})
	return out

func health_of(id: String) -> Node:
	for d in dummies + boards:
		if d.id == id: return d.health
	return null

# A hit: never any damage (full health back), but the number shows and the total grows.
func _on_hit(_packet: RefCounted, applied: float, t: Dictionary) -> void:
	var now: float = main.session.run.time
	t.health.hp = t.health.max_hp
	if t.health._seen.size() > 2048: t.health._seen.clear()
	if applied <= 0.0: return
	if now - float(t.last_hit_t) > TOTAL_RESET_S: t.total = 0.0
	t.total += applied
	t.hits += 1
	t.last_hit_t = now
	log.append({"id": t.id, "amount": applied, "time": now})
	if log.size() > 512: log = log.slice(-256)
	if t.label: t.label.text = "%s\n%d hits" % [_fmt(t.total), t.hits]
	if t.kind == "board": t.flash = 1.0
	if main.damage_numbers:
		var kind := "burn" if main._burn_ticking else ("special" if main.projectiles.detonating == "special" else "direct")
		var at: Vector3 = t.body.global_position + (Vector3(0, 2.0, 0) if t.kind == "dummy" else Vector3(0, float(t.radius) + 0.4, 0))
		main.damage_numbers.spawn(at, applied, kind, t.id)

static func _fmt(v: float) -> String:
	return ("%.0f" % v) if v >= 10.0 else ("%.1f" % v)

func tick(delta: float, now: float) -> void:
	if not active: return
	_phase += delta
	for d in dummies:
		if float(d.strafe) > 0.0:
			var w := STRAFE_SPEED / float(d.strafe)
			d.body.position = d.base + Vector3(sin(_phase * w + float(d.base.x)) * float(d.strafe), 0, 0)
		if d.total > 0.0 and now - float(d.last_hit_t) > TOTAL_RESET_S:
			d.total = 0.0
			d.hits = 0
			d.label.text = ""
	for b in boards:
		if b.flash > 0.0:
			b.flash = maxf(0.0, b.flash - delta * 3.0)
			b.mat.emission_energy_multiplier = b.flash * 2.5

# ---- helpers ------------------------------------------------------------------------------

func _solid(parent: Node3D, centre: Vector3, size: Vector3, mat: Material, nm: String, solid := true) -> Node3D:
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
	else:
		node = Node3D.new()
	node.name = nm
	node.position = centre
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		node.add_child(mi)
	parent.add_child(node)
	return node

func _label(parent: Node3D, text: String, at: Vector3, px := 0.01) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = at
	l.pixel_size = px
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 10
	l.modulate = Color(0.98, 0.96, 0.9)
	parent.add_child(l)

# The forest portal's frame for the enemies' navigation grid (world AABBs).
func forest_solids() -> Array:
	var out := []
	for side in [-1.0, 1.0]:
		var c := FOREST_PORTAL + Vector3(0, 0, side * (PORTAL_SIZE.x * 0.5 + 0.35))
		out.append(AABB(c - Vector3(0.35, 0, 0.3), Vector3(0.7, PORTAL_SIZE.y + 0.2, 0.6)))
	return out
