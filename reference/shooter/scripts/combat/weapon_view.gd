extends Node3D
# First-person held weapon (presentation only). Each weapon is a few low-poly
# parts plus a hand, built in code so every MVP weapon has a view without
# outside models; poses follow the combat clock: melee swings, recoil, reload
# dip, throw wind-up. Attached to the player camera, so the lo-fi camera that
# mirrors it sees it too.

const HAND := Color(0.72, 0.56, 0.45)
# Real gun models (Quaternius Ultimate Gun Pack, CC0) built by
# tools/build_viewmodels.gd: real length, muzzle along -Z, origin at the grip,
# Marker3D anchors Grip / Support / Muzzle / Sight / Mag. Weapons without one
# keep the code-built model.
const VIEWMODEL := "res://assets/quaternius/guns/viewmodels/%s.tscn"
const ADS_DIST := 0.3       # the Sight sits this far in front of the eye when fully aimed
const Spring = preload("res://scripts/combat/spring.gd")
var current := ""
var model: Node3D
static var HIP_REST := Transform3D(Basis.from_euler(Vector3(0.05, 0.25, 0.0)), Vector3(0.28, -0.26, -0.5)) # code-built models
static var GUN_REST := Transform3D(Basis(), Vector3(0.12, -0.13, -0.24)) # real gun models: the arms rig's hold point (arms_rig.gd tuning)
var rest := HIP_REST
var reload_dip := 0.0       # 0..1 during a reload (the arms drop the support hand by it)

# Viewmodel feel (presentation only; hit timing stays on the combat clock).
# pose() sets `target`; each frame the model springs toward target + feel offsets
# (bob, look sway, strafe roll, vertical lag), so poses settle instead of snapping.
var feel_enabled := true
var target := rest
var settle_pos := Spring.new(260.0, 28.0) # tracks action poses closely
var settle_rot := Spring.new(260.0, 28.0)
var feel_pos := Spring.new(80.0, 10.0)
var feel_rot := Spring.new(80.0, 10.0)
const BOB_AMP := 0.014      # metres at sprint speed
const BOB_RATE := 2.2       # radians of bob phase per metre walked
const SWAY_GAIN := 0.012    # rad of sway per rad/s of look
const SWAY_MAX := 0.08
const ROLL_GAIN := 0.012    # rad per m/s strafe
const ROLL_MAX := 0.06
const LAG_GAIN := 0.01      # metres per m/s of camera vertical speed
const LAG_MAX := 0.05
const SPRINT_SPEED := 6.0
var bob_phase := 0.0
var ads_t := 0.0            # aim progress from the player (0 hip .. 1 aimed); set each publish
var _prev := {}             # last yaw, pitch, cam_y

func _settle_reset() -> void:
	target = rest
	settle_pos.reset(rest.origin)
	settle_rot.reset(rest.basis.get_euler())
	feel_pos.reset(Vector3.ZERO)
	feel_rot.reset(Vector3.ZERO)

# Feel offsets from player motion. Pure apart from spring state; tests drive it directly.
# right: player's world right axis. Returns the transform applied to the model.
func step_feel(dt: float, velocity: Vector3, right: Vector3, on_floor: bool, yaw: float, pitch: float, cam_y: float) -> Transform3D:
	var pos_off := Vector3.ZERO
	var rot_off := Vector3.ZERO
	if feel_enabled and dt > 0.0:
		var speed := Vector2(velocity.x, velocity.z).length()
		if on_floor and speed > 0.2:
			bob_phase += dt * speed * BOB_RATE
			var amp := BOB_AMP * clampf(speed / SPRINT_SPEED, 0.0, 1.0)
			pos_off += Vector3(sin(bob_phase) * amp, -absf(cos(bob_phase)) * amp, 0.0)
		if not _prev.is_empty():
			var d_yaw := wrapf(yaw - _prev.yaw, -PI, PI) / dt
			var d_pitch: float = (pitch - _prev.pitch) / dt
			var cam_vy: float = (cam_y - _prev.cam_y) / dt
			rot_off += Vector3(clampf(d_pitch * SWAY_GAIN, -SWAY_MAX, SWAY_MAX), clampf(d_yaw * SWAY_GAIN, -SWAY_MAX, SWAY_MAX), 0.0)
			pos_off.y += clampf(-cam_vy * LAG_GAIN, -LAG_MAX, LAG_MAX)
		rot_off.z += clampf(-velocity.dot(right) * ROLL_GAIN, -ROLL_MAX, ROLL_MAX)
	_prev = {"yaw": yaw, "pitch": pitch, "cam_y": cam_y}
	var steady := 1.0 - 0.85 * clampf(ads_t, 0.0, 1.0) # aimed: little bob and sway
	pos_off *= steady
	rot_off *= steady
	var p := settle_pos.step(target.origin, dt) + feel_pos.step(pos_off, dt)
	var r := settle_rot.step(target.basis.get_euler(), dt) + feel_rot.step(rot_off, dt)
	return Transform3D(Basis.from_euler(r), p)

func _player() -> CharacterBody3D:
	var n := get_parent()
	while n != null and not (n is CharacterBody3D): n = n.get_parent()
	return n as CharacterBody3D

func _process(delta: float) -> void:
	if model == null: return
	var body := _player()
	if body == null:
		model.transform = target
		return
	var cam := get_parent() as Node3D
	model.transform = step_feel(delta, body.velocity, body.global_basis.x, body.is_on_floor(),
		float(body.get("yaw")), float(body.get("pitch")), cam.global_position.y if cam else 0.0)

func _part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	m.rotation = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m

static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new(); b.size = size; return b
static func _cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new(); c.top_radius = r_top; c.bottom_radius = r_bot; c.height = h; c.radial_segments = 8; return c

func _build(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "View_" + id
	_part(n, _box(Vector3(0.09, 0.08, 0.12)), Vector3(0, -0.02, 0.04), HAND) # hand (child 0: the floor pickup drops it)
	var path := VIEWMODEL % id
	if id != "" and ResourceLoader.exists(path):
		var gun: Node3D = (load(path) as PackedScene).instantiate()
		gun.name = "Gun"
		n.add_child(gun)
		n.set_meta("real_scale", true)
		return n
	var steel := Color(0.55, 0.57, 0.6)
	var dark := Color(0.12, 0.12, 0.13)
	match id:
		"knife":
			_part(n, _box(Vector3(0.025, 0.03, 0.12)), Vector3(0, 0.0, -0.02), dark)
			_part(n, _box(Vector3(0.008, 0.03, 0.2)), Vector3(0, 0.005, -0.18), steel)
		"baseball_bat":
			_part(n, _cyl(0.035, 0.018, 0.75), Vector3(0, 0.0, -0.33), Color(0.6, 0.42, 0.25), Vector3(PI / 2, 0, 0))
		"katana":
			_part(n, _cyl(0.016, 0.016, 0.22), Vector3(0, 0, -0.02), dark, Vector3(PI / 2, 0, 0))
			_part(n, _box(Vector3(0.07, 0.012, 0.03)), Vector3(0, 0, -0.14), Color(0.75, 0.65, 0.3))
			_part(n, _box(Vector3(0.008, 0.03, 0.75)), Vector3(0, 0.005, -0.53), steel)
		"pistol":
			_part(n, _box(Vector3(0.035, 0.11, 0.05)), Vector3(0, 0.0, -0.01), dark, Vector3(-0.25, 0, 0))
			_part(n, _box(Vector3(0.035, 0.045, 0.2)), Vector3(0, 0.07, -0.08), Color(0.2, 0.2, 0.22))
		"shotgun":
			_part(n, _box(Vector3(0.05, 0.08, 0.3)), Vector3(0, 0.02, 0.12), Color(0.35, 0.22, 0.12))
			_part(n, _cyl(0.018, 0.018, 0.6), Vector3(0, 0.07, -0.3), dark, Vector3(PI / 2, 0, 0))
			_part(n, _box(Vector3(0.045, 0.045, 0.16)), Vector3(0, 0.02, -0.18), Color(0.35, 0.22, 0.12))
		"assault_rifle":
			_part(n, _box(Vector3(0.05, 0.09, 0.42)), Vector3(0, 0.05, -0.12), dark)
			_part(n, _box(Vector3(0.035, 0.13, 0.05)), Vector3(0, -0.04, -0.14), Color(0.18, 0.18, 0.18), Vector3(0.25, 0, 0))
			_part(n, _cyl(0.012, 0.012, 0.3), Vector3(0, 0.07, -0.48), dark, Vector3(PI / 2, 0, 0))
		"molotov":
			_part(n, _cyl(0.025, 0.045, 0.2), Vector3(0, 0.08, -0.02), Color(0.35, 0.55, 0.3))
			_part(n, _box(Vector3(0.02, 0.06, 0.02)), Vector3(0, 0.21, -0.02), Color(0.9, 0.85, 0.75))
		"frag":
			var s := SphereMesh.new(); s.radius = 0.045; s.height = 0.09
			_part(n, s, Vector3(0, 0.05, -0.02), Color(0.25, 0.3, 0.2))
	return n

# Shows the equipped weapon (or the throwable being aimed); "" = hand only.
func show_weapon(w: Resource, aiming_item: String) -> void:
	var id := aiming_item if aiming_item != "" else (String(w.id) if w != null else "")
	if id == current and model != null: return
	if model != null: model.queue_free()
	current = id
	model = _build(id) if id != "" else null
	rest = GUN_REST if model != null and model.has_meta("real_scale") else HIP_REST
	if model != null:
		add_child(model)
		model.transform = rest
		_settle_reset()

# A marker on the current model (Sight, Muzzle, ...), or null.
func marker(name_: String) -> Marker3D:
	if model == null: return null
	return model.find_child(name_, true, false) as Marker3D

# The pose that puts the Sight marker on the camera axis, ADS_DIST ahead.
func ads_pose() -> Transform3D:
	var sight := marker("Sight")
	if sight == null: return rest
	var local: Vector3 = (model.global_transform.affine_inverse() * sight.global_transform).origin if model.is_inside_tree() else _local_of(sight)
	return Transform3D(Basis(), Vector3(0, 0, -ADS_DIST) - local)

static func _local_of(n: Node3D) -> Vector3:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and not (cur.name.begins_with("View_")):
		if cur is Node3D: xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf.origin

# Muzzle position in world space (for the flash light), or null.
func muzzle_global() -> Variant:
	var m := marker("Muzzle")
	return m.global_position if m != null and m.is_inside_tree() else null

# Pose from the combat clock (seconds since the action began).
func pose(combat: RefCounted, aiming: bool) -> void:
	if model == null: return
	var t: float = combat.action_time() if combat.busy() else 0.0
	var a: Dictionary = combat.action
	var xf := rest
	reload_dip = 0.0
	if aiming:
		xf = Transform3D(Basis.from_euler(Vector3(0.9, 0.2, 0)), Vector3(0.25, -0.05, -0.35))
	elif combat.busy() and a.has("weapon") and a.weapon.category == "melee":
		var total: float = a.windup + a.active + a.recovery
		var k := clampf(t / maxf(0.01, a.windup), 0.0, 1.0) # wind back, then sweep across
		var sweep := clampf((t - a.windup) / maxf(0.01, a.active + a.recovery * 0.4), 0.0, 1.0)
		var yaw := lerpf(0.9, -1.1, sweep) if t >= a.windup else lerpf(0.25, 0.9, k)
		var pitch := lerpf(0.05, 0.6, k) * (1.0 - sweep)
		xf = Transform3D(Basis.from_euler(Vector3(pitch, yaw, -0.4 * sweep)), rest.origin + Vector3(0.05 * (1.0 - sweep), 0.05, 0))
		if t > total - 0.05: xf = rest
	elif combat.busy() and a.has("weapon"): # ranged: recoil kick
		var kick := clampf(1.0 - t / 0.12, 0.0, 1.0)
		xf = Transform3D(rest.basis.rotated(Vector3.RIGHT, 0.25 * kick), rest.origin + Vector3(0, 0, 0.06 * kick))
	elif combat.busy() and a.has("reload"):
		var dip := sin(clampf(t / maxf(0.01, a.windup + a.recovery), 0.0, 1.0) * PI)
		reload_dip = dip
		xf = Transform3D(rest.basis.rotated(Vector3.FORWARD, 0.6 * dip), rest.origin + Vector3(0, -0.18 * dip, 0))
	elif combat.busy() and a.has("throw"):
		var k2 := clampf(t / a.windup, 0.0, 1.0)
		xf = Transform3D(Basis.from_euler(Vector3(lerpf(0.9, -0.6, k2), 0.2, 0)), Vector3(0.25, lerpf(-0.05, 0.1, k2), lerpf(-0.35, -0.6, k2)))
	# ADS: blend toward the sight-on-axis pose (keeping a share of the recoil kick).
	if not aiming and ads_t > 0.0 and marker("Sight") != null and not (combat.busy() and combat.action.has("reload")):
		var aimed := ads_pose()
		var kick_off := (xf.origin - rest.origin) * 0.4
		aimed = Transform3D(aimed.basis * (rest.basis.inverse() * xf.basis).orthonormalized(), aimed.origin + kick_off)
		xf = xf.interpolate_with(aimed, smoothstep(0.0, 1.0, ads_t))
	target = xf # _process springs the model here (no snap back to rest)
