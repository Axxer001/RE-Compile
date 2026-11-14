extends SubViewportContainer
# Let it Ride's die [Sir, 2026-11-14]: a code-built cube with pips in its own
# small 3D world, drawn in a HUD SubViewport (only the player sees it). Each roll
# tumbles for TUMBLE_S, then eases onto the rolled face, holds, and fades.
# Presentation only: the result is decided by GamblerService before it shows.

const PX := 160
const TUMBLE_S := 0.7
const SETTLE_S := 0.25
const HOLD_S := 1.6
const FADE_S := 0.4
const SIZE := 1.0
const PIP_R := 0.09
# Face value -> its outward normal (the camera looks down -Z, so the face shown is +Z).
const FACES := {1: Vector3(0, 0, 1), 6: Vector3(0, 0, -1), 2: Vector3(1, 0, 0), 5: Vector3(-1, 0, 0), 3: Vector3(0, 1, 0), 4: Vector3(0, -1, 0)}
const LAYOUT := {1: [[0, 0]], 2: [[-1, -1], [1, 1]], 3: [[-1, -1], [0, 0], [1, 1]], 4: [[-1, -1], [1, -1], [-1, 1], [1, 1]],
	5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]], 6: [[-1, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [1, 1]]}

var vp: SubViewport
var cube: Node3D
var face := 0           # the face being shown (0 = none yet)
var rolled_at := -INF   # sim time of the roll on show
var shown_n := -1       # which roll is on show (two rolls can share a tick)
var _spin := Vector3.ZERO
var _from := Basis()

func _ready() -> void:
	name = "Die"
	stretch = true
	custom_minimum_size = Vector2(PX, PX)
	size = Vector2(PX, PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 3.2)
	cam.fov = 40.0
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	cube = build_die()
	vp.add_child(cube)
	visible = false

# The die: an ivory cube with dark pips on all six faces (opposite faces sum to 7).
static func build_die() -> Node3D:
	var root := Node3D.new()
	root.name = "Cube"
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.92, 0.84)
	mat.roughness = 0.6
	body.material_override = mat
	root.add_child(body)
	var pip_mat := StandardMaterial3D.new()
	pip_mat.albedo_color = Color(0.08, 0.06, 0.1)
	pip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pip_mesh := CylinderMesh.new()
	pip_mesh.top_radius = PIP_R
	pip_mesh.bottom_radius = PIP_R
	pip_mesh.height = 0.02
	pip_mesh.radial_segments = 12
	for v in FACES:
		var n: Vector3 = FACES[v]
		var b := _face_basis(n)
		for xy in LAYOUT[v]:
			var pip := MeshInstance3D.new()
			pip.mesh = pip_mesh
			pip.material_override = pip_mat
			var off: Vector3 = b.x * float(xy[0]) * 0.27 + b.y * float(xy[1]) * 0.27 + n * (SIZE * 0.5 + 0.005)
			pip.transform = Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), off) # the cylinder's axis along the face normal
			root.add_child(pip)
	return root

# A basis whose z is the face normal (x, y span the face).
static func _face_basis(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var x := up.cross(n).normalized()
	return Basis(x, n.cross(x), n)

# The rotation that turns face `v` toward the camera (+Z).
static func show_basis(v: int) -> Basis:
	var n: Vector3 = FACES[v]
	if n.is_equal_approx(Vector3(0, 0, 1)): return Basis()
	if n.is_equal_approx(Vector3(0, 0, -1)): return Basis(Vector3.UP, PI)
	var axis := n.cross(Vector3(0, 0, 1)).normalized()
	return Basis(axis, n.angle_to(Vector3(0, 0, 1)))

# Called every HUD refresh with the newest roll.
func update(roll: Dictionary, now: float) -> void:
	if roll.is_empty():
		visible = false
		return
	var t: float = now - float(roll.time)
	if int(roll.get("n", 0)) != shown_n:
		shown_n = int(roll.get("n", 0))
		rolled_at = float(roll.time)
		face = int(roll.face)
		_spin = Vector3(9.0 + float(face) * 1.3, 7.0 + float(face % 3), 5.0) # varied but fixed per face (no RNG)
		_from = Basis()
	var total := TUMBLE_S + SETTLE_S + HOLD_S + FADE_S
	visible = t < total
	if not visible: return
	if t < TUMBLE_S:
		cube.basis = Basis.from_euler(_spin * t)
		_from = cube.basis
	elif t < TUMBLE_S + SETTLE_S:
		var u: float = (t - TUMBLE_S) / SETTLE_S
		cube.basis = _from.orthonormalized().slerp(show_basis(face), 1.0 - pow(1.0 - u, 3.0))
	else: cube.basis = show_basis(face)
	cube.position.y = absf(sin(t * 12.0)) * 0.25 * maxf(0.0, 1.0 - t / TUMBLE_S) # little bounces as it lands
	modulate.a = 1.0 - clampf((t - TUMBLE_S - SETTLE_S - HOLD_S) / FADE_S, 0.0, 1.0)

func landed(now: float) -> bool:
	return now - rolled_at >= TUMBLE_S + SETTLE_S
