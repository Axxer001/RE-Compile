extends Camera3D

@export var target_node: NodePath
@export var follow_speed: float = 8.0
@export var camera_offset: Vector3 = Vector3(0.0, 11.0, 7.5)

var target: Node3D

func _ready() -> void:
	if not target_node.is_empty():
		target = get_node(target_node)
	# Look towards the player target
	rotation_degrees = Vector3(-55.0, 0.0, 0.0)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var target_pos: Vector3 = target.global_position + camera_offset
	global_position = global_position.lerp(target_pos, follow_speed * delta)
