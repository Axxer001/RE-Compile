extends CharacterBody3D
# The Tracer: something that moves through the ceiling ducts. It cannot be
# seen or hurt while up there. Stand still under a working light and it finds
# you: a scraping warning after 4 s, a drop 1.5 m behind you after 6 s. On the
# floor it bites once (0.8 s windup, 20 HP, dodgeable by stepping away), then
# climbs back and rests for 20 s. It can be killed while down (60 HP).
# Counter: keep moving, keep to the dark, or fight it when it drops.

const BodyModel = preload("res://scripts/actors/body_model.gd")
const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Health = preload("res://scripts/combat/health_component.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")

enum State { CEILING, DROPPED, DEAD }

const HP := 60.0
const RADIUS := 0.3
const STILL_SPEED := 0.3   # m/s: slower than this counts as standing still
const WARN_AT := 4.0       # seconds still under a light
const DROP_AT := 6.0
const DROP_BEHIND := 1.5
const BITE_WINDUP := 0.8
const BITE_REACH := 1.6
const BITE_DAMAGE := 20.0
const STAY_DOWN := 2.3     # seconds on the floor (bite + recovery) before climbing back
const REST_S := 20.0

signal warned
signal dropped(at: Vector3)

var enemy_id := "tracer"
var state := State.CEILING
var still := 0.0
var warned_now := false
var timer := 0.0
var rest_until := -INF
var bitten := false
var bites := 0
var health: Node
var model: Node3D
var anim: AnimationPlayer

func setup() -> void:
	name = enemy_id
	collision_layer = 0b1000
	collision_mask = 0b1
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 1.2
	col.shape = cap
	col.position.y = 0.6
	add_child(col)
	health = Health.new()
	health.name = "Health"
	health.max_hp = HP
	health.faction = "infected"
	add_child(health)
	health.died.connect(func(_p) -> void: _die())
	var built := BodyModel.build(self, false, Color(0.45, 0.5, 0.55), {
		"polo": OutfitBuilder.fabric(Color(0.25, 0.27, 0.3), Color(0.1, 0.1, 0.1), 0.6, 3),
		"trousers": OutfitBuilder.fabric(Color(0.18, 0.2, 0.22), Color(0.08, 0.08, 0.08), 0.2, 4),
	}, 0.95)
	model = built.model
	anim = built.anim
	reset()

func reset() -> void:
	state = State.CEILING
	still = 0.0
	warned_now = false
	timer = 0.0
	rest_until = -INF
	bitten = false
	bites = 0
	health.reset()
	_set_down(false)
	if anim != null: anim.play("crouch")

func _set_down(down: bool) -> void:
	visible = down
	$Shape.set_deferred("disabled", not down)
	collision_layer = 0b1000 if down else 0

func is_down() -> bool:
	return state == State.DROPPED

func _die() -> void:
	state = State.DEAD
	$Shape.set_deferred("disabled", true)
	anim.play("death")

# ctx: {player, player_health, lit: Callable(pos) -> bool, nav, los: Callable}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	var p: CharacterBody3D = ctx.player
	match state:
		State.DEAD:
			return
		State.CEILING:
			var speed := Vector2(p.velocity.x, p.velocity.z).length()
			if now < rest_until or ctx.player_health.dead or speed > STILL_SPEED or not ctx.lit.call(p.global_position):
				still = 0.0
				warned_now = false
				return
			still += delta
			if still >= WARN_AT and not warned_now:
				warned_now = true
				warned.emit()
			if still + 1e-6 >= DROP_AT:
				var spot := _drop_spot(p, ctx.nav)
				still = 0.0
				warned_now = false
				if spot == Vector3.INF: return
				global_position = spot
				_face(p.global_position)
				state = State.DROPPED
				timer = 0.0
				bitten = false
				_set_down(true)
				anim.play("crouch")
				dropped.emit(spot)
		State.DROPPED:
			timer += delta
			if not bitten:
				_face(p.global_position)
				if timer + 1e-6 >= BITE_WINDUP:
					bitten = true
					bites += 1
					anim.play("bite")
					_bite(p, ctx.player_health, now, ctx.los)
			if timer + 1e-6 >= STAY_DOWN:
				state = State.CEILING
				rest_until = now + REST_S
				_set_down(false)

# Behind the player first, then to either side; a free floor cell or none.
func _drop_spot(p: CharacterBody3D, nav: RefCounted) -> Vector3:
	var back := p.global_transform.basis.z
	back.y = 0.0
	back = back.normalized()
	var side := back.cross(Vector3.UP)
	for dir in [back, side, -side]:
		var spot: Vector3 = p.global_position + dir * DROP_BEHIND
		spot.y = 0.0
		if not nav.blocked(nav.cell_of(spot)): return spot
	return Vector3.INF

func _face(point: Vector3) -> void:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() > 0.01: rotation.y = atan2(-to.x, -to.z)

func _bite(p: CharacterBody3D, ph: Node, now: float, los: Callable) -> void:
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length() > BITE_REACH: return
	if not los.call(global_position + Vector3(0, 1.0, 0), p.eye_position()): return
	ph.apply(DamagePacket.new(CombatController.next_id(), enemy_id, "infected", BITE_DAMAGE, "bite"), now)
