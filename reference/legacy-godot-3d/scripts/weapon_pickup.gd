class_name WeaponPickup
extends Area3D

@export var weapon_data: WeaponData
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
	if weapon_data and not weapon_data.mesh_path.is_empty():
		if ResourceLoader.exists(weapon_data.mesh_path):
			var mesh_res = load(weapon_data.mesh_path)
			if mesh_res is PackedScene:
				visual_instance = mesh_res.instantiate() as Node3D
				visual_instance.scale = weapon_data.mesh_scale
				add_child(visual_instance)

func _process(delta: float) -> void:
	time_passed += delta
	if visual_instance:
		visual_instance.rotate_y(rotation_speed * delta)
		visual_instance.position.y = sin(time_passed * float_speed) * float_amplitude

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("equip_weapon") and weapon_data:
		body.equip_weapon(weapon_data)
		queue_free()
