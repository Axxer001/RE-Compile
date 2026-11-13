extends CharacterBody3D
# Shambler: an infected student. Hunts by sound, sees in a forward cone that
# walls block, gives a short grace before chasing, bites at close range.
# All decisions happen in tick(), driven by the session clock (deterministic,
# pauses with the game). Ported state set from the 2D shambler:
#   IDLE -> (noise) INVESTIGATE -> (sees player) ALERT -0.5 s-> CHASE -> ATTACK
#   CHASE -(lost 3 s)-> INVESTIGATE last known -> look around -> IDLE; DEAD latched.

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Health = preload("res://scripts/combat/health_component.gd")
const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")
const BODY_MALE := "res://assets/quaternius/base_characters/Superhero_Male_FullBody.gltf"
const BODY_FEMALE := "res://assets/quaternius/base_characters/Superhero_Female_FullBody.gltf"
const ANIMS := "res://assets/quaternius/animations/UAL1_Standard.glb"
const SKIN_TINT := Color(0.55, 0.66, 0.5) # sickly grey-green

enum State { IDLE, INVESTIGATE, ALERT, CHASE, ATTACK, DEAD }

const HP := 80.0
const HEIGHT := 1.75
const HEAD_ZONE := 0.3     # the top 0.3 m of the body takes headshot damage
const RADIUS := 0.3
const EYE := 1.6
const INVESTIGATE_SPEED := 1.4
const CHASE_SPEED := 2.6      # slower than the player's 3.5 m/s walk
const TURN_RATE := 6.0        # rad/s
const SIGHT_RANGE := 14.0
const SIGHT_HALF_ANGLE := 55.0 # degrees (110 deg cone)
const TOUCH_RANGE := 1.5      # noticed regardless of facing
const GRACE_S := 0.5
const LOSE_S := 3.0
const ARRIVE := 0.6
const LOOK_AROUND_S := 3.0
const GIVE_UP_S := 2.0
const REPLAN_S := 0.4
const ATTACK_RANGE := 1.3     # starts a bite
const BITE_REACH := 1.6       # bite connects at commit if still this close and in front
const BITE_ARC := 60.0        # degrees either side
const BITE_WINDUP := 0.45
const BITE_RECOVERY := 0.8
const BITE_DAMAGE := 15.0
const GRAVITY := 12.0

static var _bite_serial := 900000

var enemy_id := ""
var state := State.IDLE
var spawn := Vector3.ZERO
var spawn_yaw := 0.0
var facing := Vector3.FORWARD  # unit, horizontal
var target := Vector3.ZERO     # where it is going (investigate) / last known (chase)
var path: Array[Vector3] = []
var timer := 0.0               # time in the current state
var unseen := 0.0              # chase: time since the player was last seen
var replan := 0.0
var heard_upto := 0            # highest noise id already processed
var bites := 0                 # committed bites (for tests)
var arrived := false           # investigate: reached the spot, now looking around
var bite_done := false         # attack: this bite already committed (one per attack)
var health: Node
var model: Node3D
var anim: AnimationPlayer

func setup(id: String, at: Vector3, yaw_deg: float) -> void:
	enemy_id = id
	name = id
	spawn = at
	spawn_yaw = deg_to_rad(yaw_deg)
	collision_layer = 0b1000 # enemy
	collision_mask = 0b11    # world + player
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	col.shape = cap
	col.position.y = HEIGHT * 0.5
	add_child(col)
	health = Health.new()
	health.name = "Health"
	health.max_hp = HP
	health.faction = "infected"
	add_child(health)
	health.died.connect(func(_p) -> void: _die())
	_build_model()
	reset_to(spawn, rad_to_deg(spawn_yaw))

func _build_model() -> void:
	# Realistic low-poly student body (Quaternius, CC0) in clothes built from
	# the body's own skinned mesh (outfit_builder.gd). Variant by id.
	var female := hash(enemy_id) % 2 == 1
	var scene: PackedScene = load(BODY_FEMALE if female else BODY_MALE)
	model = scene.instantiate()
	model.name = "Model"
	model.rotation.y = PI # Quaternius bodies face +Z; this body faces -Z
	add_child(model)
	var body := OutfitBuilder.body_mesh(model)
	var skin: BaseMaterial3D = body.mesh.surface_get_material(0).duplicate()
	skin.albedo_color = SKIN_TINT
	body.set_surface_override_material(0, skin)
	var seed := hash(enemy_id)
	var top := Color(0.86, 0.9, 0.95) if female else Color(0.92, 0.92, 0.88) # blouse / WMSU-style polo
	OutfitBuilder.dress(model, {
		"polo": OutfitBuilder.fabric(top, Color(0.42, 0.38, 0.3), 0.8, seed),
		"trousers": OutfitBuilder.fabric(Color(0.12, 0.14, 0.2), Color(0.06, 0.06, 0.06), 0.3, seed + 7),
		"shoes": OutfitBuilder.fabric(Color(0.05, 0.05, 0.05), Color(0.02, 0.02, 0.02)),
	})
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", _library())

static var _lib: AnimationLibrary
static func _library() -> AnimationLibrary:
	if _lib != null: return _lib
	_lib = AnimationLibrary.new()
	var src: Node = (load(ANIMS) as PackedScene).instantiate()
	var ap: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	for pair in [["idle", "Idle", true], ["walk", "Walk", true], ["jog", "Jog_Fwd", true], ["bite", "Punch_Jab", false], ["hit", "Hit_Chest", false], ["death", "Death01", false]]:
		var a: Animation = ap.get_animation(pair[1]).duplicate()
		a.loop_mode = Animation.LOOP_LINEAR if pair[2] else Animation.LOOP_NONE
		_lib.add_animation(pair[0], a)
	src.free()
	return _lib

func reset_to(at: Vector3, yaw_deg: float, heard_before := -1) -> void:
	position = at
	velocity = Vector3.ZERO
	facing = Vector3(-sin(deg_to_rad(yaw_deg)), 0, -cos(deg_to_rad(yaw_deg)))
	rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	state = State.IDLE
	path.clear()
	timer = 0.0
	unseen = 0.0
	replan = 0.0
	if heard_before >= 0: heard_upto = heard_before
	bites = 0
	health.reset()
	$Shape.disabled = false
	model.position = Vector3.ZERO
	if anim != null:
		anim.speed_scale = 1.0
		anim.play("idle")
		anim.seek(randf() * anim.current_animation_length, true) # a crowd never moves in lockstep

func eye() -> Vector3:
	return global_position + Vector3(0, EYE, 0)

func _die() -> void:
	state = State.DEAD
	path.clear()
	velocity = Vector3.ZERO
	$Shape.set_deferred("disabled", true)
	if anim != null:
		anim.speed_scale = 1.0
		anim.play("death")

func _go(next: int) -> void:
	state = next
	timer = 0.0
	replan = 0.0
	arrived = false
	bite_done = false

# ctx: {player: CharacterBody3D, player_health, noise: Array, nav, los: Callable(from, to) -> bool}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	timer += delta
	if state == State.DEAD:
		return # the death clip plays out and holds its last frame
	var p: CharacterBody3D = ctx.player
	var player_alive: bool = not ctx.player_health.dead
	var sees := player_alive and can_see(p, ctx.los)
	_listen(ctx.noise)
	match state:
		State.IDLE:
			_turn_toward(position + facing, delta)
			if sees: _go(State.ALERT)
		State.INVESTIGATE:
			if sees:
				_go(State.ALERT)
			elif _walk_to(target, INVESTIGATE_SPEED, delta, ctx.nav):
				if not arrived:
					arrived = true
					timer = 0.0 # look-around time counts from arrival
				_look_around(delta)
		State.ALERT:
			_turn_toward(p.global_position, delta)
			velocity.x = 0; velocity.z = 0
			if not sees:
				target = p.global_position
				_go(State.INVESTIGATE)
			elif timer + 1e-6 >= GRACE_S:
				_go(State.CHASE)
		State.CHASE:
			if not player_alive:
				_go(State.IDLE)
			else:
				if sees:
					target = p.global_position
					unseen = 0.0
				else:
					unseen += delta
				if unseen >= LOSE_S:
					_go(State.INVESTIGATE)
				elif sees and _flat(global_position).distance_to(_flat(p.global_position)) <= ATTACK_RANGE:
					_go(State.ATTACK)
				else:
					_walk_to(target, CHASE_SPEED, delta, ctx.nav)
		State.ATTACK:
			velocity.x = 0; velocity.z = 0
			if not bite_done:
				_turn_toward(p.global_position, delta)
			# One commit per attack: a time-window test fires twice when float
			# ticks land a hair under the boundary (0.4499... then 0.4666...).
			if not bite_done and timer + 1e-6 >= BITE_WINDUP:
				bite_done = true
				_commit_bite(p, ctx.player_health, now, ctx.los)
			if timer + 1e-6 >= BITE_WINDUP + BITE_RECOVERY:
				_go(State.CHASE if player_alive else State.IDLE)
	if not is_on_floor(): velocity.y -= GRAVITY * delta
	else: velocity.y = 0.0
	move_and_slide()
	rotation.y = atan2(-facing.x, -facing.z)
	_animate()

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# Forward cone, range, and a clear line from eye to the player's eye (walls,
# closed doors and low openings block it). Very close bodies are noticed anyway.
func can_see(p: CharacterBody3D, los: Callable) -> bool:
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > SIGHT_RANGE: return false
	if d > TOUCH_RANGE and rad_to_deg(facing.angle_to(to.normalized())) > SIGHT_HALF_ANGLE: return false
	return los.call(eye(), p.eye_position())

# New noise events within their radius send it to the noise's origin (the
# place it was heard, not the emitter's live position). Ignored while chasing.
func _listen(events: Array) -> void:
	for e in events:
		if e.id <= heard_upto: continue
		heard_upto = e.id
		if state in [State.CHASE, State.ATTACK, State.ALERT]: continue
		if global_position.distance_to(e.origin) <= e.radius:
			target = e.origin
			_go(State.INVESTIGATE)

func _look_around(delta: float) -> void:
	velocity.x = 0; velocity.z = 0
	facing = facing.rotated(Vector3.UP, 1.2 * delta).normalized()
	if timer >= LOOK_AROUND_S: _go(State.IDLE)

# Follows the grid path toward goal; true once within ARRIVE (or given up).
func _walk_to(goal: Vector3, speed: float, delta: float, nav: RefCounted) -> bool:
	if _flat(global_position).distance_to(_flat(goal)) <= ARRIVE:
		velocity.x = 0; velocity.z = 0
		return true
	replan -= delta
	if path.is_empty() or replan <= 0.0:
		var r: Dictionary = nav.find_path(global_position, goal)
		path.clear()
		if r.ok: path.assign(r.path)
		replan = REPLAN_S
		if not r.ok:
			velocity.x = 0; velocity.z = 0
			return timer >= GIVE_UP_S # unreachable: stand, then give up
	while not path.is_empty() and _flat(global_position).distance_to(_flat(path[0])) < 0.15:
		path.pop_front()
	if path.is_empty(): return false
	var dir := Vector3(path[0].x - global_position.x, 0, path[0].z - global_position.z).normalized()
	_turn_toward(global_position + dir, delta)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	return false

func _turn_toward(point: Vector3, delta: float) -> void:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() < 0.01: return
	var want := to.normalized()
	var ang := facing.signed_angle_to(want, Vector3.UP)
	var step := clampf(ang, -TURN_RATE * delta, TURN_RATE * delta)
	facing = facing.rotated(Vector3.UP, step).normalized()

# One bite at the commit moment: connects only if the player is still in
# reach, in front, and not behind a wall. Each bite has its own damage id.
func _commit_bite(p: CharacterBody3D, ph: Node, now: float, los: Callable) -> void:
	bites += 1
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() > BITE_REACH: return
	if to.length() > 0.05 and rad_to_deg(facing.angle_to(to.normalized())) > BITE_ARC: return
	if not los.call(eye(), p.eye_position()): return
	_bite_serial += 1
	ph.apply(DamagePacket.new(_bite_serial, enemy_id, "infected", BITE_DAMAGE, "bite"), now)

# Clip per state. Walk/jog playback speed follows ground speed so feet do not
# skate (Walk ~1.4 m/s, Jog ~3.0 m/s at speed 1). The bite clip is timed so
# its strike lands on the gameplay commit (BITE_WINDUP).
const WALK_CLIP_SPEED := 1.4
const JOG_CLIP_SPEED := 3.0
const BITE_STRIKE_AT := 0.35 # seconds into Punch_Jab where the arm is extended
func _animate() -> void:
	if anim == null: return
	var speed := Vector2(velocity.x, velocity.z).length()
	var want := "idle"
	var scale := 1.0
	if state == State.ATTACK:
		want = "bite"
		scale = BITE_STRIKE_AT / BITE_WINDUP
	elif speed > 0.1:
		want = "jog" if state == State.CHASE else "walk"
		scale = speed / (JOG_CLIP_SPEED if want == "jog" else WALK_CLIP_SPEED)
	if anim.current_animation != want:
		anim.play(want, 0.2) # blend, not snap
	anim.speed_scale = scale

# Hurt by the player: skip the grace and go straight for them (unless dead or
# already fighting).
func alert_to(pos: Vector3) -> void:
	if state in [State.DEAD, State.CHASE, State.ATTACK]: return
	target = pos
	unseen = 0.0
	_go(State.CHASE)

func state_name() -> String:
	return State.keys()[state]
