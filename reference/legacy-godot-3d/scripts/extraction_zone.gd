extends Area3D

signal extraction_success()

var is_unlocked: bool = false
@onready var prompt_label: Label3D = $PromptLabel
@onready var beacon_light: OmniLight3D = $BeaconLight

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var terminals = get_tree().get_nodes_in_group("terminals")
	for t in terminals:
		if t.has_signal("terminal_hacked"):
			t.terminal_hacked.connect(_on_data_secured)
	_update_visuals()

func _on_data_secured() -> void:
	is_unlocked = true
	_update_visuals()

func _update_visuals() -> void:
	if is_unlocked:
		if prompt_label:
			prompt_label.text = "[ EXTRACTION VAN READY - ENTER TO ESCAPE ]"
			prompt_label.modulate = Color(0.2, 1.0, 0.4)
		if beacon_light:
			beacon_light.light_color = Color(0.2, 1.0, 0.4)
	else:
		if prompt_label:
			prompt_label.text = "[ EXTRACTION LOCKED: SECURE RESEARCH DATA FIRST ]"
			prompt_label.modulate = Color(1.0, 0.3, 0.3)
		if beacon_light:
			beacon_light.light_color = Color(1.0, 0.2, 0.2)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and is_unlocked:
		extraction_success.emit()
		print("[VICTORY] Player escaped with the research files!")
