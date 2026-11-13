extends CharacterBody3D
# The Proctor: a tall faculty silhouette that patrols the ground floor on a
# fixed route, opening doors with its keys. It ignores you unless it sees you
# carrying research (a research file from a terminal or a research drive).
# Then it follows, keeping 3 m away, and locks the door nearest to you. It
# never attacks and cannot be hurt. Lose it (out of sight for 5 s) or stop
# carrying research and it returns to its route and unlocks what it locked.
# Counter: hide the research (drop it or deliver it), break line of sight.

const BodyModel = preload("res://scripts/actors/body_model.gd")
const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")

enum State { PATROL, FOLLOW }

const RADIUS := 0.3
const EYE := 1.85
const PATROL_SPEED := 1.2
const FOLLOW_SPEED := 1.8
const KEEP_DISTANCE := 3.0
const SIGHT_RANGE := 16.0
const SIGHT_HALF_ANGLE := 55.0
const LOSE_S := 5.0
const LOCK_REACH := 4.0     # locks a door this close to the player
const DOOR_REACH := 1.3     # opens closed doors this close to itself on patrol
const ARRIVE := 0.4
const REPLAN_S := 0.5
# Patrol route (ground floor): corridor, computer lab, classroom, and back.
const ROUTE := [Vector3(9.5, 0, 1.8), Vector3(9.5, 0, 6.2), Vector3(13.0, 0, 3.0), Vector3(17.6, 0, 3.0),
	Vector3(13.0, 0, 3.0), Vector3(6.2, 0, 5.0), Vector3(4.0, 0, 8.6), Vector3(6.2, 0, 5.0)]

signal locked_door(door: Node3D)

var enemy_id := "proctor"
var enabled := true # tests can take it out of play; it then neither moves nor reacts
var state := State.PATROL
var waypoint := 0
var facing := Vector3.FORWARD
var path: Array[Vector3] = []
var replan := 0.0
var unseen := 0.0
var locks: Array = []       # doors this Proctor locked
var model: Node3D
var anim: AnimationPlayer

func setup() -> void:
	name = enemy_id
	collision_layer = 0b1000
	collision_mask = 0b11
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 2.0
	col.shape = cap
	col.position.y = 1.0
	add_child(col)
	var built := BodyModel.build(self, false, Color(0.08, 0.08, 0.09), {
		"polo": OutfitBuilder.fabric(Color(0.06, 0.06, 0.07), Color(0.03, 0.03, 0.03), 0.0, 11),
		"trousers": OutfitBuilder.fabric(Color(0.05, 0.05, 0.06), Color(0.02, 0.02, 0.02), 0.0, 12),
		"shoes": OutfitBuilder.fabric(Color(0.02, 0.02, 0.02), Color(0.01, 0.01, 0.01)),
	}, 1.1)
	model = built.model
	anim = built.anim
	reset()

func reset() -> void:
	state = State.PATROL
	waypoint = 1
	position = ROUTE[0]
	velocity = Vector3.ZERO
	facing = (ROUTE[1] - ROUTE[0]).normalized()
	path.clear()
	replan = 0.0
	unseen = 0.0
	locks.clear()
	if anim != null:
		anim.play("idle") # never a T-pose before its first tick
		anim.seek(randf() * anim.current_animation_length, true)

func can_see(p: CharacterBody3D, los: Callable) -> bool:
	var to: Vector3 = p.global_position - global_position
	to.y = 0.0
	if to.length() > SIGHT_RANGE: return false
	if to.length() > 1.5 and rad_to_deg(facing.angle_to(to.normalized())) > SIGHT_HALF_ANGLE: return false
	return los.call(global_position + Vector3(0, EYE, 0), p.eye_position())

# ctx: {player, carrying: bool, doors: {id: door}, staff_nav, los, lock: Callable(door) -> bool,
#       unlock: Callable(door), opened: Callable(door)}
func tick(delta: float, _now: float, ctx: Dictionary) -> void:
	if not enabled: return
	var p: CharacterBody3D = ctx.player
	var sees := can_see(p, ctx.los)
	match state:
		State.PATROL:
			if sees and ctx.carrying:
				state = State.FOLLOW
				unseen = 0.0
				path.clear()
			else:
				_open_doors_ahead(ctx)
				if _walk_to(ROUTE[waypoint], PATROL_SPEED, delta, ctx.staff_nav):
					waypoint = (waypoint + 1) % ROUTE.size()
					path.clear()
		State.FOLLOW:
			unseen = 0.0 if sees else unseen + delta
			if unseen >= LOSE_S or not ctx.carrying:
				_give_up(ctx)
			else:
				var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
				if d > KEEP_DISTANCE:
					_open_doors_ahead(ctx)
					_walk_to(p.global_position, FOLLOW_SPEED, delta, ctx.staff_nav)
				else:
					velocity.x = 0; velocity.z = 0
					_turn(p.global_position)
				_lock_near(p, ctx)
	velocity.y = 0.0
	move_and_slide()
	rotation.y = atan2(-facing.x, -facing.z)
	var moving := Vector2(velocity.x, velocity.z).length() > 0.1
	var want := "walk" if moving else "idle"
	if anim.current_animation != want: anim.play(want, 0.2)

func _give_up(ctx: Dictionary) -> void:
	state = State.PATROL
	path.clear()
	for d in locks: ctx.unlock.call(d)
	locks.clear()

func _lock_near(p: CharacterBody3D, ctx: Dictionary) -> void:
	var best: Node3D = null
	var best_d := LOCK_REACH
	for id in ctx.doors:
		var door: Node3D = ctx.doors[id]
		if door.locked: continue
		var d: float = Vector2(door.global_position.x - p.global_position.x, door.global_position.z - p.global_position.z).length()
		if d < best_d:
			best_d = d
			best = door
	if best != null and ctx.lock.call(best):
		locks.append(best)
		locked_door.emit(best)

func _open_doors_ahead(ctx: Dictionary) -> void:
	for id in ctx.doors:
		var door: Node3D = ctx.doors[id]
		if door.is_open or door.locked: continue
		var mid: Vector3 = door.global_position + Vector3(0, 0, 0.6)
		if Vector2(mid.x - global_position.x, mid.z - global_position.z).length() < DOOR_REACH:
			door.set_open(true)
			ctx.opened.call(door)

func _walk_to(goal: Vector3, speed: float, delta: float, nav: RefCounted) -> bool:
	if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() <= ARRIVE:
		velocity.x = 0; velocity.z = 0
		return true
	replan -= delta
	if path.is_empty() or replan <= 0.0:
		var r: Dictionary = nav.find_path(global_position, goal)
		path.clear()
		if r.ok: path.assign(r.path)
		replan = REPLAN_S
	while not path.is_empty() and Vector2(path[0].x - global_position.x, path[0].z - global_position.z).length() < 0.15:
		path.pop_front()
	if path.is_empty():
		velocity.x = 0; velocity.z = 0
		return false
	var dir := Vector3(path[0].x - global_position.x, 0, path[0].z - global_position.z).normalized()
	_turn(global_position + dir)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	return false

func _turn(point: Vector3) -> void:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() > 0.01: facing = to.normalized()
