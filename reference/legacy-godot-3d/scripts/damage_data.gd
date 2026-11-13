class_name DamageData
extends RefCounted

var amount: float
var knockback_dir: Vector3
var knockback_force: float
var stun_time: float
var source: Node3D

func _init(p_amount: float = 10.0, p_knockback_dir: Vector3 = Vector3.ZERO, p_knockback_force: float = 0.0, p_stun_time: float = 0.0, p_source: Node3D = null) -> void:
	amount = p_amount
	knockback_dir = p_knockback_dir
	knockback_force = p_knockback_force
	stun_time = p_stun_time
	source = p_source
