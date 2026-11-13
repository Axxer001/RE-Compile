extends CharacterBody3D

@export_group("Stats")
@export var max_health: float = 80.0        # PZ: Shambler HP=80 (3–6 hits to kill with Bat)
@export var speed: float = 2.4
@export var chase_speed: float = 4.8
@export var base_detection_radius: float = 2.5
@export var flashlight_detection_radius: float = 12.0

# PZ: Zombie_Idle_Lunge — 0.5s grace window before committing to chase (SpeedScale 0.80)
# Zombie commits attack at SpeedScale 1.04; bite collision fires at TimePc=0.20
@export_group("AI Tuning")
@export var alert_grace_duration: float = 0.5  # PZ: Zombie_Idle_Lunge grace window
@export var attack_bite_pct: float = 0.20       # PZ: bite collision at TimePc=0.20 into attack anim

enum State { IDLE, ALERTED, INVESTIGATING, CHASING, ATTACKING, STUNNED }
var current_state: State = State.IDLE

var current_health: float
var stun_timer: float = 0.0
var alert_timer: float = 0.0   # Grace period before committing chase
var investigate_target: Vector3 = Vector3.ZERO
var investigate_timer: float = 0.0
var attack_timer: float = 0.0

@onready var hurtbox: Hurtbox3D = $Hurtbox3D
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
var player: Node3D

# Visual flash nodes
var mesh_instances: Array[MeshInstance3D] = []
var flash_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	if hurtbox and not hurtbox.damage_received.is_connected(_on_damage_received):
		hurtbox.damage_received.connect(_on_damage_received)
	var tree = get_tree()
	if tree != null:
		player = tree.get_first_node_in_group("player")
	_find_mesh_instances(self)

func _find_mesh_instances(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			mesh_instances.append(child)
		_find_mesh_instances(child)

func _physics_process(delta: float) -> void:
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			_reset_material_color()

	if current_state == State.STUNNED:
		stun_timer -= delta
		if stun_timer <= 0.0:
			current_state = State.IDLE
		velocity.x = lerp(velocity.x, 0.0, 10.0 * delta)
		velocity.z = lerp(velocity.z, 0.0, 10.0 * delta)
	else:
		_process_ai_state(delta)

	if not is_on_floor():
		velocity.y -= 19.6 * delta

	move_and_slide()

func _process_ai_state(delta: float) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return

	var dist_to_player: float = global_position.distance_to(player.global_position)

	# Light sensitivity: flashlight quadruples detection radius
	var is_player_illuminated: bool = false
	if player.has_node("FlashlightPivot/Flashlight"):
		var light = player.get_node("FlashlightPivot/Flashlight")
		if light.visible:
			is_player_illuminated = true

	var current_detection_radius: float = flashlight_detection_radius if is_player_illuminated else base_detection_radius

	# --- PZ GRACE PERIOD (Δ2) ---
	# Zombie_Idle_Lunge: zombie spots player, 0.5s hesitation at SpeedScale=0.80
	# before committing to full chase at SpeedScale=1.04. Bite fires at TimePc=0.20.
	if current_state == State.ALERTED:
		alert_timer -= delta
		# Face player slowly during grace window (slow approach, not full chase)
		var dir: Vector3 = (player.global_position - global_position).normalized()
		dir.y = 0.0
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)
		velocity.x = lerp(velocity.x, dir.x * (speed * 0.5), 6.0 * delta)
		velocity.z = lerp(velocity.z, dir.z * (speed * 0.5), 6.0 * delta)
		if animation_tree:
			animation_tree.set("parameters/playback", &"Idle")
			animation_tree.set("parameters/TimeScale/scale", 0.80)
		# Player fled during grace window → reset
		if dist_to_player > current_detection_radius:
			current_state = State.IDLE
			alert_timer = 0.0
			return
		# Grace expired → commit to chase
		if alert_timer <= 0.0:
			current_state = State.CHASING
		return

	# Priority 1: Player in range → trigger grace window (or sustain committed chase)
	if dist_to_player <= current_detection_radius:
		if current_state != State.CHASING and current_state != State.ATTACKING:
			# Fresh spot → start 0.5s grace
			current_state = State.ALERTED
			alert_timer = alert_grace_duration
			return

		# Committed chase at PZ SpeedScale=1.04
		if animation_tree:
			animation_tree.set("parameters/playback", &"Chase")
			animation_tree.set("parameters/TimeScale/scale", 1.04)
		var dir: Vector3 = (player.global_position - global_position).normalized()
		dir.y = 0.0
		velocity.x = dir.x * chase_speed
		velocity.z = dir.z * chase_speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)

		# Melee bite at close range (bite collision fires at TimePc=0.20 into anim)
		if dist_to_player <= 1.2 and current_state != State.ATTACKING:
			current_state = State.ATTACKING
			attack_timer = 1.0
			if animation_tree:
				animation_tree.set("parameters/playback", &"Attack")
		return

	# Lost sight while chasing/attacking → investigate last known position
	if current_state == State.CHASING or current_state == State.ATTACKING:
		current_state = State.INVESTIGATING
		investigate_target = player.global_position
		investigate_timer = 4.0
		if animation_tree:
			animation_tree.set("parameters/TimeScale/scale", 0.80)

	# Priority 2: Investigating noise/last known position
	if current_state == State.INVESTIGATING:
		if animation_tree:
			animation_tree.set("parameters/playback", &"Walk")
		var dir_to_noise: Vector3 = (investigate_target - global_position).normalized()
		dir_to_noise.y = 0.0
		velocity.x = dir_to_noise.x * speed
		velocity.z = dir_to_noise.z * speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir_to_noise.x, -dir_to_noise.z), 6.0 * delta)
		if global_position.distance_to(investigate_target) < 1.5:
			investigate_timer -= delta
			if investigate_timer <= 0.0:
				current_state = State.IDLE
		return

	# Priority 3: Idle
	if animation_tree:
		animation_tree.set("parameters/playback", &"Idle")
		animation_tree.set("parameters/TimeScale/scale", 0.80)  # PZ: idle SpeedScale=0.80
	velocity.x = lerp(velocity.x, 0.0, 5.0 * delta)
	velocity.z = lerp(velocity.z, 0.0, 5.0 * delta)

func investigate_noise(noise_pos: Vector3) -> void:
	# Noise interrupts idle/investigation but not active chase or attack
	if current_state != State.CHASING and current_state != State.ATTACKING and current_state != State.STUNNED:
		current_state = State.INVESTIGATING
		investigate_target = noise_pos
		investigate_timer = 4.0

func _on_damage_received(data: DamageData) -> void:
	current_health -= data.amount
	current_state = State.STUNNED
	stun_timer = data.stun_time

	if animation_tree:
		animation_tree.set("parameters/playback", &"Stun")

	if data.knockback_force > 0.0:
		velocity = data.knockback_dir * data.knockback_force

	_flash_hurt()

	if current_health <= 0.0:
		_die()

func _flash_hurt() -> void:
	flash_timer = 0.12
	for mesh in mesh_instances:
		mesh.set_instance_shader_parameter("hit_flash", 1.0)
		# Fallback standard material override modulation
		if mesh.material_override == null:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.5, 0.3, 0.3, 1.0)
			mesh.material_override = mat

func _reset_material_color() -> void:
	for mesh in mesh_instances:
		mesh.material_override = null

func _die() -> void:
	if animation_tree:
		animation_tree.set("parameters/playback", &"Death")
	# Small delay or immediate cleanup
	queue_free()
