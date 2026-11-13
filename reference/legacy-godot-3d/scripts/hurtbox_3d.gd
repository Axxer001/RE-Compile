class_name Hurtbox3D
extends Area3D

signal damage_received(damage_data: DamageData)

@export var is_invulnerable: bool = false

func receive_damage(data: DamageData) -> void:
	if is_invulnerable:
		return
	damage_received.emit(data)
