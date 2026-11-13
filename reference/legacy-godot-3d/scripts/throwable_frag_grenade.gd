class_name ThrowableFragGrenade
extends RigidBody3D

@export var damage: float = 120.0
@export var blast_radius: float = 5.0
@export var blast_force: float = 18.0
@export var fuse_time: float = 2.0

var time_elapsed: float = 0.0
var exploded: bool = false

func _physics_process(delta: float) -> void:
	if exploded:
		return
		
	time_elapsed += delta
	if time_elapsed >= fuse_time:
		_detonate()

func _detonate() -> void:
	exploded = true
	var tree = get_tree()
	if tree == null:
		queue_free()
		return
		
	var enemies = tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node3D:
			var dist = global_position.distance_to(enemy.global_position)
			if dist <= blast_radius:
				var falloff = 1.0 - (dist / blast_radius)
				var dir = (enemy.global_position - global_position).normalized()
				var dmg = DamageData.new(
					damage * falloff,
					dir,
					blast_force * falloff,
					1.2,
					self
				)
				if enemy.has_node("Hurtbox3D"):
					var hb = enemy.get_node("Hurtbox3D")
					if hb.has_method("receive_damage"):
						hb.receive_damage(dmg)

	# Sound alert to whole surrounding area
	for enemy in enemies:
		if enemy.has_method("investigate_noise"):
			if global_position.distance_to(enemy.global_position) <= blast_radius * 4.0:
				enemy.investigate_noise(global_position)

	queue_free()
