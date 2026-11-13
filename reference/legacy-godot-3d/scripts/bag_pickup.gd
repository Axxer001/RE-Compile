class_name BagPickup
extends Area3D

@export var tier_upgrade: InventoryManager.BagTier = InventoryManager.BagTier.SLINGBAG
@export var display_name: String = "Canvas Slingbag"
@export var rotation_speed: float = 2.0
@export var float_speed: float = 3.0
@export var float_amplitude: float = 0.08

var start_y: float = 0.0
var time_passed: float = 0.0
var visual_instance: Node3D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 # Player layer
	body_entered.connect(_on_body_entered)
	start_y = position.y
	_setup_visual()

func _setup_visual() -> void:
	var mesh_path = "res://assets/props/bedroll-packed.glb" if tier_upgrade == InventoryManager.BagTier.SLINGBAG else "res://assets/props/box.glb"
	if ResourceLoader.exists(mesh_path):
		var res = load(mesh_path)
		if res is PackedScene:
			visual_instance = res.instantiate() as Node3D
			visual_instance.scale = Vector3(0.5, 0.5, 0.5)
			add_child(visual_instance)

func _process(delta: float) -> void:
	time_passed += delta
	if visual_instance:
		visual_instance.rotate_y(rotation_speed * delta)
		visual_instance.position.y = sin(time_passed * float_speed) * float_amplitude

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("upgrade_inventory_bag"):
		if body.upgrade_inventory_bag(tier_upgrade):
			queue_free()
