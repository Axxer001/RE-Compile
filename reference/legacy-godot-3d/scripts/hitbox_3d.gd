class_name Hitbox3D
extends Area3D

@export var damage: float = 20.0
@export var knockback_force: float = 6.0
@export var stun_duration: float = 0.4
@export var is_shove: bool = false

func _ready() -> void:
	monitoring = false
	monitorable = true
	area_entered.connect(_on_area_entered)

func activate() -> void:
	monitoring = true

func deactivate() -> void:
	monitoring = false

func _on_area_entered(area: Area3D) -> void:
	if area is Hurtbox3D:
		var hurtbox: Hurtbox3D = area as Hurtbox3D
		var forward_dir: Vector3 = -global_transform.basis.z.normalized()
		var dmg: DamageData = DamageData.new(
			damage,
			forward_dir,
			knockback_force,
			stun_duration,
			owner
		)
		hurtbox.receive_damage(dmg)
