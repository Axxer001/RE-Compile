extends CharacterBody3D

@export_group("Stats")
@export var max_health: float = 100.0
@export var current_health: float = 100.0

@export_group("Movement")
@export var walk_speed: float = 3.5    # PZ walk cadence — deliberate, not snappy
@export var sprint_speed: float = 6.5  # PZ sprint — fast but not superhuman
@export var acceleration: float = 10.0 # PZ feel: slightly sluggish on acceleration
@export var friction: float = 12.0     # PZ feel: committed movement, not instant stop

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 25.0
@export var stamina_regen_rate: float = 15.0
@export var stamina_regen_delay: float = 1.0
@export var shove_stamina_cost: float = 25.0
@export var throw_stamina_cost: float = 15.0
@export var dodge_stamina_cost: float = 20.0

@export_group("Combat")
# PZ-extracted: grappleGrab.xml — shove BlendTime=0.20s, SpeedScale=0.80, SetMeleeDelay=8 frames recovery
# Collision fires at TimePc=0.10 into shove anim (GrappleGrabCollisionCheck BwdDrag)
@export var shove_duration: float = 0.5         # Full shove anim length (0.80 SpeedScale applied by AnimTree)
@export var shove_cooldown: float = 0.8          # SetMeleeDelay=8 frames @ 24fps ≈ 0.33s + blend
@export var shove_collision_at_pct: float = 0.10 # Fire knockback at 10% through shove anim
@export var shove_damage: float = 5.0
@export var shove_knockback: float = 12.0        # BwdDrag knockback distance (~2.5m)
@export var shove_stun: float = 1.0
@export var dodge_duration: float = 0.28
@export var dodge_cooldown: float = 0.5
@export var dodge_speed: float = 11.0
@export var projectile_scene: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
@export var molotov_scene: PackedScene = preload("res://scenes/projectiles/throwable_molotov.tscn")
@export var grenade_scene: PackedScene = preload("res://scenes/projectiles/throwable_frag_grenade.tscn")
@export var throw_force_forward: float = 12.0
@export var throw_force_up: float = 4.0

@export_group("Flashlight")
@export var flashlight_turn_speed: float = 15.0

@export_group("Default Weapon")
@export var default_weapon: WeaponData

enum State { IDLE, ATTACKING, SHOVING, SHOOTING, DODGING }

var current_state: State = State.IDLE
var equipped_weapon: WeaponData
var inventory: InventoryManager

var current_stamina: float
var is_sprinting: bool = false
var regen_timer: float = 0.0
var combat_timer: float = 0.0
var cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO
var is_invulnerable: bool = false

# Throwables index: 0 = Molotov, 1 = Frag Grenade
var active_throwable_index: int = 0

@onready var flashlight_pivot: Node3D = $FlashlightPivot
@onready var flashlight: SpotLight3D = $FlashlightPivot/Flashlight
@onready var melee_hitbox: Hitbox3D = $MeleeHitbox
@onready var shove_hitbox: Hitbox3D = $ShoveHitbox
@onready var projectile_spawn: Marker3D = $ProjectileSpawn
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var hand_socket: Marker3D = get_node_or_null("ModelRoot/RightHandSocket")

var camera: Camera3D = null
var current_weapon_instance: Node3D = null

func _get_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	var vp = get_viewport()
	if vp != null:
		camera = vp.get_camera_3d()
	return camera

func _ready() -> void:
	current_health = max_health
	current_stamina = max_stamina
	inventory = InventoryManager.new(InventoryManager.BagTier.POCKETS)
	inventory.active_weapon_changed.connect(_on_active_weapon_changed)
	
	if melee_hitbox:
		melee_hitbox.monitoring = false
	if shove_hitbox:
		shove_hitbox.monitoring = false
		shove_hitbox.damage = shove_damage
		shove_hitbox.knockback_force = shove_knockback
		shove_hitbox.stun_duration = shove_stun
		shove_hitbox.is_shove = true

	if default_weapon != null:
		equip_weapon(default_weapon)
	else:
		var starter_knife = load("res://resources/weapons/melee_knife.tres") as WeaponData
		if starter_knife:
			equip_weapon(starter_knife)

func equip_weapon(weapon: WeaponData) -> void:
	if inventory:
		inventory.add_item(weapon)
	else:
		_set_equipped_weapon(weapon)

func _on_active_weapon_changed(weapon: WeaponData) -> void:
	_set_equipped_weapon(weapon)

func _set_equipped_weapon(weapon: WeaponData) -> void:
	equipped_weapon = weapon
	if melee_hitbox and equipped_weapon:
		melee_hitbox.damage = equipped_weapon.damage
		melee_hitbox.knockback_force = equipped_weapon.knockback_force
		melee_hitbox.stun_duration = equipped_weapon.stun_duration
	_update_weapon_visual()

func upgrade_inventory_bag(new_tier: InventoryManager.BagTier) -> bool:
	if inventory:
		return inventory.upgrade_bag(new_tier)
	return false

func _update_weapon_visual() -> void:
	if hand_socket == null:
		var model_root: Node3D = get_node_or_null("ModelRoot")
		if model_root:
			hand_socket = Marker3D.new()
			hand_socket.name = "RightHandSocket"
			hand_socket.transform.origin = Vector3(0.35, 0.9, -0.2)
			model_root.add_child(hand_socket)
			
	if hand_socket == null:
		return

	if current_weapon_instance != null and is_instance_valid(current_weapon_instance):
		current_weapon_instance.queue_free()
		current_weapon_instance = null

	if equipped_weapon == null or equipped_weapon.mesh_path.is_empty():
		return

	if ResourceLoader.exists(equipped_weapon.mesh_path):
		var mesh_res = load(equipped_weapon.mesh_path)
		if mesh_res is PackedScene:
			current_weapon_instance = mesh_res.instantiate() as Node3D
			current_weapon_instance.scale = equipped_weapon.mesh_scale
			current_weapon_instance.rotation_degrees = equipped_weapon.mesh_rotation_degrees
			current_weapon_instance.position = equipped_weapon.mesh_offset
			hand_socket.add_child(current_weapon_instance)

func _process(_delta: float) -> void:
	_handle_flashlight_toggle()
	_handle_weapon_cycle()

func _physics_process(delta: float) -> void:
	_handle_timers(delta)
	_handle_combat_input()
	_handle_stamina(delta)
	_handle_movement(delta)
	_aim_at_mouse(delta)
	move_and_slide()
	_update_animation_tree()

func _handle_timers(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		
	if combat_timer > 0.0:
		combat_timer -= delta
		if combat_timer <= 0.0:
			_end_combat_action()

func _handle_weapon_cycle() -> void:
	if Input.is_action_just_pressed("switch_weapon") and current_state == State.IDLE:
		if inventory:
			inventory.cycle_weapon(true)

	# Number keys 1-4 for quick slot selection
	for i in range(4):
		if Input.is_key_pressed(KEY_1 + i) and current_state == State.IDLE:
			if inventory:
				inventory.select_weapon_slot(i)

	# T toggles between Molotov and Frag Grenade
	if Input.is_key_pressed(KEY_T):
		active_throwable_index = 1 if active_throwable_index == 0 else 0

func _handle_combat_input() -> void:
	if current_state != State.IDLE or cooldown_timer > 0.0:
		return
		
	# Space: Dodge Roll in move direction (or back if stationary)
	if Input.is_action_just_pressed("ui_select") and current_stamina >= dodge_stamina_cost:
		_execute_dodge()
		return

	# RMB: Defensive shove resetting spacing
	if Input.is_action_just_pressed("shove") and current_stamina >= shove_stamina_cost:
		_execute_shove()
		return

	# G: Tactical throwables (Molotov or Frag)
	if Input.is_action_just_pressed("throw_item") and current_stamina >= throw_stamina_cost:
		_execute_throw()
		return

	# LMB: Primary attack via equipped weapon
	if Input.is_action_just_pressed("attack"):
		if equipped_weapon == null:
			return
			
		if equipped_weapon.category == WeaponData.WeaponCategory.MELEE:
			if current_stamina >= equipped_weapon.stamina_cost:
				_execute_melee_attack()
		elif equipped_weapon.category == WeaponData.WeaponCategory.RANGED:
			if current_stamina >= equipped_weapon.stamina_cost:
				_execute_ranged_attack()

func _execute_dodge() -> void:
	current_state = State.DODGING
	current_stamina -= dodge_stamina_cost
	regen_timer = stamina_regen_delay
	combat_timer = dodge_duration
	cooldown_timer = dodge_cooldown
	is_invulnerable = true
	
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.01:
		dodge_direction = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	else:
		dodge_direction = global_transform.basis.z.normalized() # Dodge backwards
		
	velocity = dodge_direction * dodge_speed
	_emit_noise(4.0)

func _execute_melee_attack() -> void:
	current_state = State.ATTACKING
	var cost: float = equipped_weapon.stamina_cost if equipped_weapon else 20.0
	var dur: float = equipped_weapon.attack_duration if equipped_weapon else 0.25
	var cd: float = equipped_weapon.attack_cooldown if equipped_weapon else 0.45
	
	current_stamina -= cost
	regen_timer = stamina_regen_delay
	combat_timer = dur
	cooldown_timer = cd
	if melee_hitbox:
		melee_hitbox.monitoring = true
		
	_emit_noise(equipped_weapon.noise_radius if equipped_weapon else 8.0)
	
	if animation_tree:
		animation_tree.set("parameters/playback", &"Attack_Melee")

func _execute_ranged_attack() -> void:
	current_state = State.SHOOTING
	var cost: float = equipped_weapon.stamina_cost if equipped_weapon else 15.0
	current_stamina -= cost
	regen_timer = stamina_regen_delay
	combat_timer = 0.12
	cooldown_timer = equipped_weapon.attack_cooldown if equipped_weapon else 0.5
	
	_emit_noise(equipped_weapon.noise_radius if equipped_weapon else 25.0)
	
	if animation_tree:
		animation_tree.set("parameters/playback", &"Shoot")

	if projectile_scene and projectile_spawn:
		var pellets_count = equipped_weapon.pellets if equipped_weapon else 1
		var spread_deg = equipped_weapon.spread_angle_deg if equipped_weapon else 0.0
		
		for p in range(pellets_count):
			var proj: Projectile3D = projectile_scene.instantiate() as Projectile3D
			get_parent().add_child(proj)
			proj.global_position = projectile_spawn.global_position
			
			var base_dir = -global_transform.basis.z.normalized()
			if spread_deg > 0.0:
				var rand_angle = deg_to_rad(randf_range(-spread_deg, spread_deg))
				base_dir = base_dir.rotated(Vector3.UP, rand_angle)
				
			proj.direction = base_dir
			if equipped_weapon:
				proj.damage = equipped_weapon.damage
				proj.speed = 35.0

func _execute_shove() -> void:
	current_state = State.SHOVING
	current_stamina -= shove_stamina_cost
	regen_timer = stamina_regen_delay
	combat_timer = shove_duration
	cooldown_timer = shove_cooldown
	# PZ: GrappleGrabCollisionCheck(BwdDrag) fires at TimePc=0.10 into shove anim
	var shove_hit_delay: float = shove_duration * shove_collision_at_pct
	get_tree().create_timer(shove_hit_delay).timeout.connect(_activate_shove_hitbox)
	_emit_noise(5.0)
	if animation_tree:
		animation_tree.set("parameters/playback", &"Shove")

func _activate_shove_hitbox() -> void:
	if shove_hitbox and current_state == State.SHOVING:
		shove_hitbox.monitoring = true

func _execute_throw() -> void:
	current_stamina -= throw_stamina_cost
	regen_timer = stamina_regen_delay
	cooldown_timer = 0.4
	
	var active_scene = grenade_scene if active_throwable_index == 1 else molotov_scene
	if active_scene and projectile_spawn:
		var item: RigidBody3D = active_scene.instantiate() as RigidBody3D
		get_parent().add_child(item)
		item.global_position = projectile_spawn.global_position
		
		var forward_dir: Vector3 = -global_transform.basis.z.normalized()
		var impulse: Vector3 = (forward_dir * throw_force_forward) + (Vector3.UP * throw_force_up)
		item.apply_central_impulse(impulse)

func _emit_noise(radius: float) -> void:
	var tree = get_tree()
	if tree == null:
		return
	var enemies = tree.get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("investigate_noise"):
			if global_position.distance_to(enemy.global_position) <= radius:
				enemy.investigate_noise(global_position)

func _end_combat_action() -> void:
	if melee_hitbox:
		melee_hitbox.monitoring = false
	if shove_hitbox:
		shove_hitbox.monitoring = false
	is_invulnerable = false
	current_state = State.IDLE

func _handle_movement(delta: float) -> void:
	if current_state == State.DODGING:
		velocity.x = lerp(velocity.x, dodge_direction.x * dodge_speed, 8.0 * delta)
		velocity.z = lerp(velocity.z, dodge_direction.z * dodge_speed, 8.0 * delta)
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	
	var move_speed_mult: float = 1.0
	if current_state == State.ATTACKING or current_state == State.SHOOTING:
		move_speed_mult = 0.35
	elif current_state == State.SHOVING:
		move_speed_mult = 0.5
		
	var can_sprint: bool = Input.is_action_pressed("sprint") and current_stamina > 0.0 and move_direction.length_squared() > 0.01 and current_state == State.IDLE
	is_sprinting = can_sprint
	
	var base_speed: float = sprint_speed if is_sprinting else walk_speed
	var target_velocity: Vector3 = move_direction * (base_speed * move_speed_mult)
	
	if move_direction.length_squared() > 0.01:
		velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		if is_sprinting:
			_emit_noise(6.0)
	else:
		velocity.x = lerp(velocity.x, 0.0, friction * delta)
		velocity.z = lerp(velocity.z, 0.0, friction * delta)
	
	if not is_on_floor():
		velocity.y -= 19.6 * delta

func _handle_stamina(delta: float) -> void:
	if is_sprinting:
		current_stamina = max(0.0, current_stamina - stamina_drain_rate * delta)
		regen_timer = stamina_regen_delay
	else:
		if regen_timer > 0.0:
			regen_timer -= delta
		else:
			current_stamina = min(max_stamina, current_stamina + stamina_regen_rate * delta)

func _aim_at_mouse(delta: float) -> void:
	var active_cam = _get_camera()
	if active_cam == null:
		return
			
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = active_cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = active_cam.project_ray_normal(mouse_pos)
	
	var player_plane: Plane = Plane(Vector3.UP, global_position.y)
	var hit_pos = player_plane.intersects_ray(ray_origin, ray_normal)
	
	if hit_pos != null:
		var target_look: Vector3 = Vector3(hit_pos.x, global_position.y, hit_pos.z)
		var dir_to_mouse: Vector3 = target_look - global_position
		if dir_to_mouse.length_squared() > 0.05:
			var target_rot_y: float = atan2(-dir_to_mouse.x, -dir_to_mouse.z)
			rotation.y = lerp_angle(rotation.y, target_rot_y, flashlight_turn_speed * delta)

func _handle_flashlight_toggle() -> void:
	if Input.is_action_just_pressed("toggle_flashlight"):
		if flashlight:
			flashlight.visible = not flashlight.visible

func _update_animation_tree() -> void:
	if animation_tree == null:
		return
	var speed_ratio: float = velocity.length() / sprint_speed
	animation_tree.set("parameters/MoveBlend/blend_amount", speed_ratio)
	# PZ: idle/run SpeedScale=0.80 (slightly padded animations)
	var anim_speed_scale: float = 0.80
	if current_state == State.ATTACKING:
		anim_speed_scale = 1.04  # PZ: committed attack anim plays slightly faster
	animation_tree.set("parameters/TimeScale/scale", anim_speed_scale)
	if current_state == State.IDLE:
		if speed_ratio > 0.05:
			var travel_target: StringName = &"Run" if is_sprinting else &"Walk"
			animation_tree.set("parameters/playback", travel_target)
		else:
			animation_tree.set("parameters/playback", &"Idle")
