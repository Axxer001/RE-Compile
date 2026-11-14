extends RefCounted
# Authoritative action clock for one actor, in 3D (ported from the 2D build).
# READY -> WINDUP -> (commit) ACTIVE -> RECOVERY -> READY.
# - request() validates everything up front and has no side effects on rejection.
# - Endurance is paid at the commit point, so an interrupted windup costs nothing.
# - advance(delta) walks phase boundaries in order; one large delta still emits
#   every transition exactly once, so the frame rate cannot add or drop commits.
# Action definitions: {id, windup, active, recovery, cost, weapon?, instance?,
# reload?, auto?, dodge?, throw?}. Times in seconds, distances in metres
# (weapon `*_tiles` fields are read as metres in the first-person build).
# World queries are injected, so the rules stay testable without rendering:
#   origin_fn() -> Vector3 eye position;  targets_fn() -> [{id, pos, radius, health, body?}]
#   los_fn(from, to) -> bool (nothing solid between)
#   ray_fn(from, dir, range) -> {target: Dictionary or null, distance: float}
#   motion_fn(direction: Vector3, metres) for dodges.

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

# Dodge (Alt): commits at once; 2.0 m of swept motion over 0.28 s; melee/bite
# immunity only between 0.07 and 0.22 s after commit; fire and blast still land.
const DODGE := {"id": "dodge", "windup": 0.0, "active": 0.28, "recovery": 0.0, "cost": 20.0,
	"cooldown": 0.5, "dodge": {"distance": 2.0}, "immunity": {"from": 0.07, "to": 0.22, "kinds": ["melee", "bite"]}}

enum Phase { READY, WINDUP, ACTIVE, RECOVERY }
const EPSILON := 1e-6 # seconds
const MELEE_HEIGHT := 1.2 # metres: targets this far above/below the eye line are out of reach

signal committed(action: Dictionary, action_id: int)
signal transition(phase: int, action: Dictionary, action_id: int)
signal fizzled(action: Dictionary, action_id: int)
signal hit(target_id: String, result: String, action_id: int)

var health: Node
var endurance: Node
var phase := Phase.READY
var action: Dictionary = {}
var action_id := 0
var elapsed := 0.0
var now := 0.0
static var _issued := 0     # action and packet ids are unique across controllers
var aim := Vector3.FORWARD  # unit vector, fixed at request
var source_id := "player"
var faction := "player"
var origin_fn: Callable
var targets_fn: Callable
var los_fn: Callable
var ray_fn: Callable
var motion_fn: Callable
var cooldown_until := {}
# Automatic fire: while true, an "auto" action re-requests itself at the exact
# end of its recovery inside advance(), so the rate does not depend on tick rate.
var repeat := false

func _init(health_node: Node, endurance_node: Node) -> void:
	health = health_node
	endurance = endurance_node

func reset() -> void:
	phase = Phase.READY
	action = {}
	action_id = 0
	elapsed = 0.0
	now = 0.0
	cooldown_until.clear()
	repeat = false

func busy() -> bool:
	return phase != Phase.READY

static func next_id() -> int:
	_issued += 1
	return _issued

# "accepted" or "rejected:<reason>". Rejection changes nothing.
func request(definition: Dictionary, aim_dir := Vector3.ZERO) -> String:
	for key in ["id", "windup", "active", "recovery", "cost"]:
		if not definition.has(key): return "rejected:invalid"
	if definition.windup < 0 or definition.active < 0 or definition.recovery < 0: return "rejected:invalid"
	if not health.accepts_actions(): return "rejected:dead"
	if busy(): return "rejected:busy"
	if now < float(cooldown_until.get(definition.id, -INF)) - EPSILON: return "rejected:cooldown"
	if not endurance.can_afford(definition.cost): return "rejected:endurance"
	if definition.has("instance") and definition.instance.magazine < 1: return "rejected:empty"
	if definition.has("reload"):
		var r: Dictionary = definition.reload
		var w: RefCounted = r.instance
		if w.magazine >= w.definition.magazine_size: return "rejected:full"
		if r.inventory.count(w.definition.ammo_type) < 1: return "rejected:no_ammo"
	action = definition
	action_id = next_id()
	if aim_dir.length_squared() > 0.0: aim = aim_dir.normalized()
	_enter(Phase.WINDUP)
	if is_zero_approx(definition.windup): _commit(now)
	return "accepted"

# Cancels only before commit. Returns true if something was cancelled.
func interrupt() -> bool:
	if phase != Phase.WINDUP: return false
	_enter(Phase.READY)
	return true

# Death cancels any uncommitted action; committed effects are never refunded.
func on_death() -> void:
	if phase == Phase.WINDUP:
		_enter(Phase.READY)

# `clock_now` is the simulation time after this tick; the step covered
# [clock_now - delta, clock_now].
func advance(delta: float, clock_now: float) -> void:
	var start := clock_now - delta
	now = clock_now
	var left := delta
	while phase != Phase.READY:
		var remaining := _phase_length() - elapsed
		if left < remaining - EPSILON:
			elapsed += left
			if phase == Phase.ACTIVE:
				_dodge_motion(left)
				resolve_melee()
			return
		if phase == Phase.ACTIVE: _dodge_motion(maxf(0.0, remaining))
		left = maxf(0.0, left - remaining)
		match phase:
			Phase.WINDUP: _commit(start + delta - left)
			Phase.ACTIVE:
				resolve_melee()
				_enter(Phase.RECOVERY)
			Phase.RECOVERY:
				var again := action
				var again_aim := aim
				_enter(Phase.READY)
				if repeat and again.get("auto", false):
					now = start + delta - left
					var r := request(again, again_aim)
					now = clock_now
					if r != "accepted": repeat = false

# Movement multiplier while acting; a dodge supplies its own motion.
func movement_factor() -> float:
	if action.has("dodge") and phase != Phase.READY: return 0.0
	match phase:
		Phase.WINDUP, Phase.ACTIVE: return 0.6
		Phase.RECOVERY: return 0.8
	return 1.0

func _phase_length() -> float:
	match phase:
		Phase.WINDUP: return float(action.windup)
		Phase.ACTIVE: return float(action.active)
		Phase.RECOVERY: return float(action.recovery)
	return 0.0

func _enter(next: int) -> void:
	phase = next
	elapsed = 0.0
	var done := action
	var id := action_id
	if next == Phase.READY:
		action = {}
		action_id = 0
	transition.emit(next, done, id)

# Commit = end of windup: pay endurance once, spend the round, move reload
# rounds, emit once, enter ACTIVE and resolve the hit.
func _commit(at: float) -> void:
	if not endurance.spend(float(action.cost), at):
		fizzled.emit(action, action_id)
		_enter(Phase.READY)
		return
	if action.has("cooldown"):
		cooldown_until[action.id] = at + float(action.cooldown)
	if action.has("immunity"):
		var imm: Dictionary = action.immunity
		health.grant_immunity(at + float(imm.to), imm.kinds, at + float(imm.from), "action")
	if action.has("instance"): action.instance.magazine -= 1 # one round per committed shot
	if action.has("reload"): _transfer_rounds(action.reload)
	committed.emit(action, action_id)
	_enter(Phase.ACTIVE)
	resolve_melee()
	resolve_shot()

func _transfer_rounds(r: Dictionary) -> void:
	var w: RefCounted = r.instance
	var need: int = w.definition.magazine_size - w.magazine
	w.magazine += r.inventory.take_units(w.definition.ammo_type, need)

func action_time() -> float:
	match phase:
		Phase.WINDUP: return elapsed
		Phase.ACTIVE: return float(action.windup) + elapsed
		Phase.RECOVERY: return float(action.windup) + float(action.active) + elapsed
	return 0.0

# Melee reach test: horizontal distance to the target's surface within reach,
# within the arc around the flattened aim, and roughly at body height.
static func in_sector(origin: Vector3, aim_dir: Vector3, target: Vector3, radius: float, reach: float, arc_degrees: float) -> bool:
	if absf(target.y - origin.y) > MELEE_HEIGHT: return false
	var to := Vector2(target.x - origin.x, target.z - origin.z)
	var distance := to.length()
	if distance - radius > reach: return false
	if distance <= radius: return true
	var flat := Vector2(aim_dir.x, aim_dir.z)
	if flat.length_squared() < 1e-6: return false
	var half := deg_to_rad(arc_degrees) * 0.5 + asin(clampf(radius / distance, 0.0, 1.0))
	return absf(flat.normalized().angle_to(to)) <= half

# Every living target inside the sector with a clear line is hit once per swing
# (HealthComponent deduplicates by action id), nearest first.
func resolve_melee() -> void:
	if not action.has("weapon") or action.weapon.category != "melee": return
	if not (origin_fn.is_valid() and targets_fn.is_valid()): return
	var weapon: Resource = action.weapon
	var origin: Vector3 = origin_fn.call()
	var list: Array = targets_fn.call()
	list.sort_custom(func(a, b): return a.pos.distance_squared_to(origin) < b.pos.distance_squared_to(origin))
	for t in list:
		if t.health.dead: continue
		if not in_sector(origin, aim, t.pos, t.radius, weapon.reach_tiles, weapon.arc_degrees): continue
		if los_fn.is_valid() and not los_fn.call(origin, t.pos): continue
		var result: String = t.health.apply(DamagePacket.new(action_id, source_id, faction, weapon.damage_hp, weapon.damage_kind), now)
		if result in ["applied", "lethal"]:
			hit.emit(t.id, result, action_id)

var headshots := 0 # head hits landed (tests, HUD)

# A direction inside a cone of `half_deg` around `dir`, uniform over the
# cone's disc; the same seed gives the same direction.
static func cone_dir(dir: Vector3, half_deg: float, seed: int) -> Vector3:
	if half_deg <= 0.0: return dir
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed)
	var r := tan(deg_to_rad(half_deg)) * sqrt(rng.randf())
	var a := rng.randf() * TAU
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-6: right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	return (dir + right * cos(a) * r + up * sin(a) * r).normalized()

# Pellet directions: a horizontal fan across spread_deg around the aim, with a
# small alternating vertical offset (deterministic, no RNG).
static func pellet_dirs(aim_dir: Vector3, pellets: int, spread_deg: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var right := aim_dir.cross(Vector3.UP)
	if right.length_squared() < 1e-6: right = Vector3.RIGHT
	right = right.normalized()
	for i in pellets:
		var f := 0.0 if pellets == 1 else float(i) / float(pellets - 1) - 0.5
		var d := aim_dir.rotated(Vector3.UP, deg_to_rad(spread_deg) * f)
		if pellets > 1: d = d.rotated(right, deg_to_rad(spread_deg * 0.15) * (1.0 if i % 2 == 0 else -1.0))
		out.append(d.normalized())
	return out

# Ranged shot at commit: each pellet is its own ray with its own damage id; the
# world's ray stops at walls and returns the first body hit, if any.
func resolve_shot() -> void:
	if not action.has("weapon") or action.weapon.category != "ranged": return
	if not (origin_fn.is_valid() and ray_fn.is_valid()): return
	var weapon: Resource = action.weapon
	var origin: Vector3 = origin_fn.call()
	# One random cone offset per shot (the pellet fan moves with it), seeded
	# by the action id so a replay of the same inputs lands the same way.
	var shot_dir := cone_dir(aim, float(action.get("cone", 0.0)), action_id)
	for dir in pellet_dirs(shot_dir, maxi(1, weapon.pellets), weapon.spread_deg):
		var r: Dictionary = ray_fn.call(origin, dir, weapon.range_tiles)
		var t = r.get("target")
		if t == null or t.health.dead: continue
		var amount: float = weapon.damage_hp * (float(action.get("head_mult", 1.0)) if r.get("head", false) else 1.0)
		var result: String = t.health.apply(DamagePacket.new(next_id(), source_id, faction, amount, weapon.damage_kind), now)
		if r.get("head", false): headshots += 1
		if result in ["applied", "lethal"]:
			hit.emit(t.id, result, action_id)

# Dodge: distance spread evenly over ACTIVE, applied as swept motion.
func _dodge_motion(active_seconds: float) -> void:
	if not action.has("dodge") or not motion_fn.is_valid() or active_seconds <= 0.0: return
	if health.dead: return
	var flat := Vector3(aim.x, 0, aim.z)
	if flat.length_squared() < 1e-6: return
	motion_fn.call(flat.normalized(), float(action.dodge.distance) * active_seconds / float(action.active))
