extends Node3D
# A hinged door (this node is the hinge). The panel is an AnimatableBody3D on
# the world + interactable layers, so it blocks movement, rays and sight when
# closed. Open/closed is authoritative state; the swing is instant in M0
# (presentation tween later). Closing refuses if a body would be trapped in
# the panel's closed volume (rule carried over from the 2D build).

signal toggled(door: Node3D, open: bool)

const WIDTH := 1.2
const HEIGHT := 2.1
const THICKNESS := 0.08
const OPEN_ANGLE := 90.0 # degrees about +Y; swings toward +X of the hinge

var door_id := ""
var is_open := false
var locked := false # the Proctor can lock a door shut; E cannot open it
var panel: AnimatableBody3D

func setup(id: String, hinge: Vector3, yaw_deg: float) -> void:
	door_id = id
	name = id
	position = hinge
	_yaw0 = yaw_deg
	rotation_degrees.y = yaw_deg
	panel = AnimatableBody3D.new()
	panel.name = "Panel"
	panel.sync_to_physics = false
	panel.collision_layer = 0b101 # world + interactable
	panel.collision_mask = 0
	panel.set_meta("door", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(THICKNESS, HEIGHT, WIDTH)
	col.shape = box
	panel.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.3, 0.2)
	bm.material = mat
	mesh.mesh = bm
	panel.add_child(mesh)
	panel.position = Vector3(0, HEIGHT * 0.5, WIDTH * 0.5)
	add_child(panel)

# Panel footprint in world space for its current pose (navigation).
func panel_aabb() -> AABB:
	var parent_xf: Transform3D = get_parent().global_transform if get_parent() is Node3D else Transform3D()
	var xf: Transform3D = parent_xf * Transform3D(Basis(Vector3.UP, deg_to_rad(rotation_degrees.y)), position) * Transform3D(Basis(), Vector3(0, HEIGHT * 0.5, WIDTH * 0.5))
	var half := Vector3(THICKNESS, HEIGHT, WIDTH) * 0.5
	var box := AABB(xf.origin, Vector3.ZERO)
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				box = box.expand(xf * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return box

# Closed-panel volume in world space (for the trap check). Built from the
# closed yaw, not the current rotation: an open door must test where it would land.
func closed_volume_transform() -> Transform3D:
	var parent_xf: Transform3D = get_parent().global_transform if get_parent() is Node3D else Transform3D()
	var hinge_closed := Transform3D(Basis(Vector3.UP, deg_to_rad(_yaw0)), position)
	return parent_xf * hinge_closed * Transform3D(Basis(), Vector3(0, HEIGHT * 0.5, WIDTH * 0.5))

var _yaw0 := 0.0 # closed yaw, degrees

func set_open(value: bool) -> void:
	is_open = value
	rotation_degrees.y = _yaw0 + (OPEN_ANGLE if value else 0.0)

# Returns true if the state changed. Closing onto a body is refused.
func toggle(space: PhysicsDirectSpaceState3D) -> bool:
	if locked: return false
	if is_open and occupied(space): return false
	set_open(not is_open)
	toggled.emit(self, is_open)
	return true

func occupied(space: PhysicsDirectSpaceState3D) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(THICKNESS + 0.1, HEIGHT - 0.1, WIDTH - 0.05)
	q.shape = box
	q.transform = closed_volume_transform()
	q.collision_mask = 0b1010 # player + enemy
	q.exclude = [panel.get_rid()]
	return not space.intersect_shape(q, 1).is_empty()
