extends RefCounted
# One triangulated surface for mesh, collision, navigation and object grounding.
const SIZE := 250.0
const STEP := SIZE / 64.0
const SIDE := 65
var heights := PackedFloat32Array()
static var _topology_key := 0
static var _masks := PackedFloat32Array()

func _init(seed_value: int, clearings: Array, paths: Array) -> void:
	heights.resize(SIDE * SIDE)
	var phase := float(posmod(seed_value, 65521)) * 0.013
	var key := hash([clearings,paths])
	if _masks.is_empty() or key != _topology_key:
		_topology_key = key
		_masks = _make_masks(clearings, paths)
	for z in SIDE:
		for x in SIDE:
			var p := Vector2(x * STEP, z * STEP)
			heights[z*SIDE+x] = _masks[z*SIDE+x] * (6.0 + 2.7*sin(p.x*0.025+phase)*sin(p.y*0.021-phase) + 1.3*sin((p.x+p.y)*0.04+phase))

static func _make_masks(clearings: Array, paths: Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(SIDE*SIDE)
	# Only the camp footprint is level; clearings and former paths follow the hills.
	var camp := Vector2(clearings[0][0], clearings[0][1])
	for z in SIDE:
		for x in SIDE:
			var p := Vector2(x * STEP, z * STEP)
			result[z*SIDE+x] = smoothstep(20.0, 50.0, p.distance_to(camp))
	return result

func height_at(p: Vector2) -> float:
	var gx := clampf(p.x / STEP, 0, SIDE-1.000001)
	var gz := clampf(p.y / STEP, 0, SIDE-1.000001)
	var x := mini(int(gx), SIDE-2)
	var z := mini(int(gz), SIDE-2)
	var u := gx-x
	var v := gz-z
	var a := heights[z*SIDE+x]
	var b := heights[z*SIDE+x+1]
	var c := heights[(z+1)*SIDE+x]
	var d := heights[(z+1)*SIDE+x+1]
	return a*(1-u-v)+b*u+c*v if u+v <= 1 else d*(u+v-1)+b*(1-v)+c*(1-u)

func normal_at(p: Vector2) -> Vector3:
	var x := clampi(int(p.x/STEP),0,SIDE-2)
	var z := clampi(int(p.y/STEP),0,SIDE-2)
	var a := Vector3(x*STEP,heights[z*SIDE+x],z*STEP)
	var b := Vector3((x+1)*STEP,heights[z*SIDE+x+1],z*STEP)
	var c := Vector3(x*STEP,heights[(z+1)*SIDE+x],(z+1)*STEP)
	var d := Vector3((x+1)*STEP,heights[(z+1)*SIDE+x+1],(z+1)*STEP)
	return (c-a).cross(b-a).normalized() if p.x/STEP-x+p.y/STEP-z <= 1 else (c-b).cross(d-b).normalized()

func mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in SIDE:
		for x in SIDE:
			vertices.append(Vector3(x*STEP,heights[z*SIDE+x],z*STEP))
			normals.append(normal_at(Vector2(x*STEP,z*STEP)))
			uv.append(Vector2(x,z))
	for z in SIDE-1:
		for x in SIDE-1:
			var a := z*SIDE+x
			indices.append_array([a,a+1,a+SIDE,a+1,a+SIDE+1,a+SIDE])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func build(parent: Node3D, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = "floor"
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var collision := CollisionShape3D.new()
	collision.shape = mi.mesh.create_trimesh_shape()
	body.add_child(collision)
	parent.add_child(body)
