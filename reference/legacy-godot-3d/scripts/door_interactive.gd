extends Node3D

@export var open_angle: float = 90.0
@export var open_speed: float = 6.0

var is_open: bool = false
var target_rotation_y: float = 0.0

@onready var hinge: Node3D = $Hinge
@onready var prompt: Label3D = $PromptLabel
@onready var interaction_area: Area3D = $InteractionArea

func _ready() -> void:
	if prompt:
		prompt.visible = false
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)
		interaction_area.body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	if hinge:
		hinge.rotation_degrees.y = lerp(hinge.rotation_degrees.y, target_rotation_y, open_speed * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and prompt and prompt.visible:
		toggle_door()

func toggle_door() -> void:
	is_open = not is_open
	target_rotation_y = open_angle if is_open else 0.0
	if prompt:
		prompt.text = "[E] CLOSE DOOR" if is_open else "[E] OPEN DOOR"

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and prompt:
		prompt.visible = true
		prompt.text = "[E] CLOSE DOOR" if is_open else "[E] OPEN DOOR"

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player") and prompt:
		prompt.visible = false
