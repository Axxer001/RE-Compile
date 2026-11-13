extends StaticBody3D
# A world item (per run). Sits on the interactable layer only, so the crosshair
# ray finds it but bodies walk through it. Holds the owned entry itself
# (ItemStack / WeaponInstance) or a bag id, so a dropped item comes back with
# the same instance id. The world decides whether taking it succeeds.

const ItemDefinition = preload("res://scripts/items/item_definition.gd")
const SIZE := Vector3(0.45, 0.35, 0.45) # interaction box, metres

var pickup_id := ""
var entry: RefCounted  # ItemStack | WeaponInstance, or null for a bag
var bag_id := ""

func setup(id: String, at: Vector3, owned: RefCounted, bag := "") -> void:
	pickup_id = id
	name = id
	entry = owned
	bag_id = bag
	position = at
	collision_layer = 0b100 # interactable
	collision_mask = 0
	set_meta("pickup", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = SIZE
	col.shape = box
	col.position.y = SIZE.y * 0.5
	add_child(col)
	add_child(_visual())

func definition() -> Resource:
	if bag_id != "": return ItemDefinition.lookup(bag_id)
	return entry.item if "magazine" in entry else entry.definition

func label() -> String:
	var d: Resource = definition()
	if bag_id != "" or "magazine" in entry or entry.quantity == 1: return d.label
	return "%s x%d" % [d.label, entry.quantity]

func value() -> int:
	if entry == null or "magazine" in entry: return 0
	return int(entry.definition.value) * int(entry.quantity)

func _visual() -> Node3D:
	var d: Resource = definition()
	if d != null and d.weapon != null:
		# Weapons and throwables lie on the floor as their first-person model.
		var builder: Node3D = preload("res://scripts/combat/weapon_view.gd").new()
		var view: Node3D = builder._build(String(d.id))
		builder.free() # only its part builder was needed
		view.name = "Model"
		view.get_child(0).queue_free() # no hand on the floor
		view.rotation = Vector3(0, 0.6, PI / 2)
		view.scale = Vector3.ONE * (1.0 if view.has_meta("real_scale") else 1.5) # real gun models are true size
		view.position.y = 0.06
		return view
	if d != null and d.model_path != "":
		var scene: PackedScene = load(d.model_path)
		var model := scene.instantiate()
		model.name = "Model"
		return model
	var mesh := MeshInstance3D.new()
	mesh.name = "Model"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.06, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.7, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.28, 0.05)
	bm.material = mat
	mesh.mesh = bm
	mesh.position.y = 0.03
	return mesh
