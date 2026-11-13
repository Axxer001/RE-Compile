class_name Projectile3D
extends Area3D

@export var speed: float = 18.0
@export var damage: float = 35.0
@export var knockback_force: float = 6.0
@export var lifetime: float = 2.0

var direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

func _on_area_entered(area: Area3D) -> void:
	if area is Hurtbox3D:
		var hurtbox: Hurtbox3D = area as Hurtbox3D
		var dmg: DamageData = DamageData.new(
			damage,
			direction,
			knockback_force,
			0.25,
			self
		)
		hurtbox.receive_damage(dmg)
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	# Collide with static walls/obstacles (Layer 1)
	if not body.is_in_group("player"):
		queue_free()
