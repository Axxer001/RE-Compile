extends CharacterBody3D
# Blackout: arrives at the night's end. The lights fail room by room (the
# world does that); Blackout then hunts the player through dark rooms only. It
# will not step into a lit room, and it recoils from the flashlight beam (backs
# off for 1.5 s). If it reaches you in the dark it strikes hard (0.5 s windup,
# 35 HP). 150 HP, so guns can drive it off for good.
# Counter: leave before it arrives, stay in lit rooms, keep the beam on it.

const BodyModel = preload("res://scripts/actors/body_model.gd")
const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Health = preload("res://scripts/combat/health_component.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")

enum State { DORMANT, HUNT, REPELLED, ATTACK, DEAD }

const HP := 150.0
const RADIUS := 0.35
const SPEED := 3.0
const RECOIL_SPEED := 2.0
const RECOIL_S := 1.5
const STRIKE_RANGE := 1.4
const STRIKE_REACH := 1.8
const STRIKE_WINDUP := 0.5
const STRIKE_RECOVERY := 0.7
const STRIKE_DAMAGE := 35.0
const REPLAN_S := 0.3

var enemy_id := "blackout"
var state := State.DORMANT
var timer := 0.0
var struck := false
var strikes := 0
var recoils := 0
var path: Array[Vector3] = []
var replan := 0.0
var facing := Vector3.FORWARD
var health: Node
var model: Node3D
var anim: AnimationPlayer

func setup() -> void:
	name = enemy_id
	collision_layer = 0b1000
	collision_mask = 0b11
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.9
	col.shape = cap
	col.position.y = 0.95
	add_child(col)
	health = Health.new()
	health.name = "Health"
	health.max_hp = HP
	health.faction = "infected"
	add_child(health)
	health.died.connect(func(_p) -> void: _die())
	var black := OutfitBuilder.fabric(Color(0.01, 0.01, 0.012), Color(0.0, 0.0, 0.0), 0.0, 21)
	var built := BodyModel.build(self, true, Color(0.02, 0.02, 0.025), {"polo": black, "trousers": black}, 1.05, Color(0.0, 0.0, 0.0))
	model = built.model
	anim = built.anim
	reset()

func reset() -> void:
	state = State.DORMANT
	timer = 0.0
	struck = false
	strikes = 0
	recoils = 0
	path.clear()
	health.reset()
	visible = false
	collision_layer = 0
	$Shape.set_deferred("disabled", true)

func active() -> bool:
	return state in [State.HUNT, State.REPELLED, State.ATTACK]

func activate(at: Vector3) -> void:
	if state != State.DORMANT: return
	global_position = at
	state = State.HUNT
	visible = true
	collision_layer = 0b1000
	$Shape.set_deferred("disabled", false)
	anim.play("idle")

func _die() -> void:
	state = State.DEAD
	$Shape.set_deferred("disabled", true)
	anim.play("death")

# ctx: {player, player_health, nav, los, dark: Callable(pos) -> bool, in_beam: Callable(pos) -> bool}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	if state == State.DORMANT or state == State.DEAD: return
	var p: CharacterBody3D = ctx.player
	timer += delta
	var chest := global_position + Vector3(0, 1.1, 0)
	if state != State.REPELLED and ctx.in_beam.call(chest):
		state = State.REPELLED
		timer = 0.0
		recoils += 1
		path.clear()
	match state:
		State.REPELLED:
			var away := Vector3(global_position.x - p.global_position.x, 0, global_position.z - p.global_position.z).normalized()
			velocity.x = away.x * RECOIL_SPEED
			velocity.z = away.z * RECOIL_SPEED
			if timer >= RECOIL_S:
				state = State.HUNT
				timer = 0.0
		State.HUNT:
			if ctx.player_health.dead:
				velocity.x = 0; velocity.z = 0
			elif Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() <= STRIKE_RANGE and ctx.dark.call(p.global_position):
				state = State.ATTACK
				timer = 0.0
				struck = false
				velocity.x = 0; velocity.z = 0
			else:
				_hunt(p, delta, ctx)
		State.ATTACK:
			velocity.x = 0; velocity.z = 0
			_face(p.global_position)
			if not struck and timer + 1e-6 >= STRIKE_WINDUP:
				struck = true
				strikes += 1
				_strike(p, ctx.player_health, now, ctx.los)
			if timer + 1e-6 >= STRIKE_WINDUP + STRIKE_RECOVERY:
				state = State.HUNT
				timer = 0.0
	velocity.y = 0.0
	move_and_slide()
	rotation.y = atan2(-facing.x, -facing.z)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var want := "bite" if state == State.ATTACK else ("jog" if moving else "idle")
	if anim.current_animation != want: anim.play(want, 0.2)

# Follow the path toward the player, but never step into a lit place.
func _hunt(p: CharacterBody3D, delta: float, ctx: Dictionary) -> void:
	replan -= delta
	if path.is_empty() or replan <= 0.0:
		var r: Dictionary = ctx.nav.find_path(global_position, p.global_position)
		path.clear()
		if r.ok: path.assign(r.path)
		replan = REPLAN_S
	while not path.is_empty() and Vector2(path[0].x - global_position.x, path[0].z - global_position.z).length() < 0.15:
		path.pop_front()
	if path.is_empty() or not ctx.dark.call(path[0]):
		velocity.x = 0; velocity.z = 0
		_face(p.global_position)
		return
	var dir := Vector3(path[0].x - global_position.x, 0, path[0].z - global_position.z).normalized()
	facing = dir
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED

func _face(point: Vector3) -> void:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() > 0.01: facing = to.normalized()

func _strike(p: CharacterBody3D, ph: Node, now: float, los: Callable) -> void:
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() > STRIKE_REACH: return
	if not los.call(global_position + Vector3(0, 1.4, 0), p.eye_position()): return
	ph.apply(DamagePacket.new(CombatController.next_id(), enemy_id, "infected", STRIKE_DAMAGE, "melee"), now)
