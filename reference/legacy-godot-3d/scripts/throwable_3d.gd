class_name Throwable3D
extends RigidBody3D

@export var fuse_time: float = 1.4
@export var blast_radius: float = 4.5
@export var blast_damage: float = 50.0
@export var blast_knockback: float = 14.0

@onready var blast_area: Area3D = $BlastArea
@onready var flash_light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_impact)
	get_tree().create_timer(fuse_time).timeout.connect(_detonate)

func _on_impact(_body: Node) -> void:
	# Optional: ignite or detonate immediately on impact if molotov
	pass

func _detonate() -> void:
	if blast_area:
		var overlapping_areas = blast_area.get_overlapping_areas()
		for area in overlapping_areas:
			if area is Hurtbox3D:
				var hurtbox: Hurtbox3D = area as Hurtbox3D
				var blast_dir: Vector3 = (hurtbox.global_position - global_position).normalized()
				if blast_dir.is_zero_approx():
					blast_dir = Vector3.UP
				var dmg: DamageData = DamageData.new(
					blast_damage,
					blast_dir,
					blast_knockback,
					0.8,
					self
				)
				hurtbox.receive_damage(dmg)

	# Sound alert to nearby roaming entities
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e.has_method("investigate_noise"):
			e.investigate_noise(global_position)

	queue_free()
