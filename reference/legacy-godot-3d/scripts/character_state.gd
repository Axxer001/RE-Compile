class_name CharacterState
extends Node

static var current_character_type: int = 0

static func toggle_character() -> void:
	current_character_type = 1 if current_character_type == 0 else 0
