extends Node3D

@export var male_player_scene: PackedScene = preload("res://scenes/player/player.tscn")
@export var female_player_scene: PackedScene = preload("res://scenes/player/player_female.tscn")
@export var phone_modal_scene: PackedScene = preload("res://scenes/ui/smartphone_modal.tscn")

@onready var camera: Camera3D = $TopDownCamera

var phone_modal: Control = null

func _ready() -> void:
	_spawn_active_character()
	_setup_phone_modal()

func _setup_phone_modal() -> void:
	phone_modal = phone_modal_scene.instantiate() as Control
	add_child(phone_modal)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_character_respawn"):
		CharacterState.toggle_character()
		get_tree().reload_current_scene()
		
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_P:
			if phone_modal and phone_modal.has_method("toggle_phone"):
				phone_modal.toggle_phone()

func _spawn_active_character() -> void:
	# Remove any existing player instance in scene
	var existing_player = get_tree().get_first_node_in_group("player")
	var spawn_pos: Vector3 = Vector3(0, 0.1, 7)
	
	if existing_player:
		spawn_pos = existing_player.global_position
		existing_player.queue_free()
	
	# Instantiate chosen archetype
	var new_player: CharacterBody3D
	if CharacterState.current_character_type == 1:
		new_player = female_player_scene.instantiate() as CharacterBody3D
	else:
		new_player = male_player_scene.instantiate() as CharacterBody3D
		
	new_player.add_to_group("player")
	add_child(new_player)
	new_player.global_position = spawn_pos
	
	# Rebind camera tracking target
	if camera and "target" in camera:
		camera.target = new_player
