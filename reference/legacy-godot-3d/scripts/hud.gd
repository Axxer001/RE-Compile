extends CanvasLayer

@onready var stamina_bar: ProgressBar = $HUD/StaminaContainer/StaminaBar
@onready var objective_label: Label = $HUD/TopBar/ObjectiveLabel
var player: CharacterBody3D

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	var terminals = get_tree().get_nodes_in_group("terminals")
	for t in terminals:
		if t.has_signal("terminal_hacked"):
			t.terminal_hacked.connect(_on_terminal_hacked)

func _process(_delta: float) -> void:
	if player and stamina_bar:
		if "current_stamina" in player and "max_stamina" in player:
			stamina_bar.value = (player.current_stamina / player.max_stamina) * 100.0

func _on_terminal_hacked() -> void:
	if objective_label:
		objective_label.text = "OBJECTIVE: REACH THE EXTRACTION POINT"
		objective_label.modulate = Color(0.2, 1.0, 0.4)
