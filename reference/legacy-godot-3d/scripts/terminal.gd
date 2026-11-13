extends Area3D

signal terminal_hacked()

@export var alert_radius: float = 14.0
@export var requires_password: bool = false
@export var puzzle_modal_scene: PackedScene = preload("res://scenes/ui/terminal_puzzle_modal.tscn")

var is_player_in_range: bool = false
var is_completed: bool = false
var puzzle_modal: Control = null

@onready var prompt_label: Label3D = $PromptLabel
@onready var screen_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	
	# Instantiate modal to canvas layer or parent scene deferred
	call_deferred("_init_modal")

func _init_modal() -> void:
	var canvas = get_tree().root.get_node_or_null("MasterPlayground")
	if canvas:
		puzzle_modal = puzzle_modal_scene.instantiate() as Control
		canvas.add_child(puzzle_modal)
		puzzle_modal.hack_completed.connect(_on_hack_completed)
		puzzle_modal.closed.connect(_on_modal_closed)

func _process(_delta: float) -> void:
	if is_completed:
		return
		
	if is_player_in_range and Input.is_action_just_pressed("interact"):
		_open_hack_terminal()

func _open_hack_terminal() -> void:
	if puzzle_modal == null:
		var canvas = get_tree().root.get_node_or_null("MasterPlayground")
		if canvas:
			puzzle_modal = puzzle_modal_scene.instantiate() as Control
			canvas.add_child(puzzle_modal)
			puzzle_modal.hack_completed.connect(_on_hack_completed)
			puzzle_modal.closed.connect(_on_modal_closed)

	if puzzle_modal and puzzle_modal.has_method("open_terminal"):
		puzzle_modal.open_terminal(requires_password)
		prompt_label.visible = false
		_emit_noise_pulse()

func _on_hack_completed() -> void:
	is_completed = true
	prompt_label.visible = true
	prompt_label.text = "[ DATA SECURED - REACH EXTRACTION ]"
	prompt_label.modulate = Color(0.2, 1.0, 0.4)
	if screen_light:
		screen_light.light_color = Color(0.2, 1.0, 0.4)
	terminal_hacked.emit()

func _on_modal_closed() -> void:
	if not is_completed and is_player_in_range:
		prompt_label.visible = true
		prompt_label.text = "[ PRESS E TO ACCESS WORKSTATION ]"

func _emit_noise_pulse() -> void:
	var tree = get_tree()
	if tree == null:
		return
	var enemies = tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("investigate_noise"):
			var dist = global_position.distance_to(enemy.global_position)
			if dist <= alert_radius:
				enemy.investigate_noise(global_position)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not is_completed:
		is_player_in_range = true
		prompt_label.visible = true
		prompt_label.text = "[ PRESS E TO ACCESS WORKSTATION ]"

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		is_player_in_range = false
		if not is_completed:
			prompt_label.visible = false
