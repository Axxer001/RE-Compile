extends RefCounted
# The Forest Ghoul's arrows [Sir, 2026-11-15; docs/plan-dark-forest-roster.md].
# World-owned like the player's fireballs: an arrow outlives its shot.
#   Normal: 10 m/s in a straight line at where the player was, 70 damage.
#   Burst:  gentle homing; 5 m/s until 20 m from the player, ramping to 20 m/s
#           at 10 m (and faster no further); 35 damage. A magic glow, no effect.
# Trees, rocks and the ground stop every arrow; the player cannot destroy one.
# One damage id per arrow. Timing runs on the simulation clock.

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

const SPEED := 10.0          # normal arrows, m/s [Sir 2026-11-15b: was 15]
const HOMING_SLOW := 5.0     # Burst arrows beyond RAMP_FAR
const HOMING_FAST := 20.0    # ... at RAMP_NEAR and closer
const RAMP_FAR := 20.0
const RAMP_NEAR := 10.0
const TURN_RATE := 1.6       # rad/s: gentle homing (a strafe can still slip it)
const HIT_R := 0.25          # arrow radius against the player's capsule
const MAX_S := 8.0           # an arrow that never lands falls apart after this
const MAX_RANGE := 45.0      # a normal arrow flies this far at most

var root: Node3D             # visuals parent (null = headless)
var vfx: Node3D
var arrows: Array = []       # {id, pos, dir, speed, homing, damage, shooter, travelled, born, node}
var log: Array = []          # {id, shooter, homing, result, amount, time} (tests)
var _next := 0
static var _serial := 950000

func reset() -> void:
	for a in arrows: _free(a)
	arrows.clear()
	log.clear()

# One arrow from `from` at `aim` (a world point). Returns its record.
func fire(from: Vector3, aim: Vector3, damage: float, homing: bool, shooter: String, now: float) -> Dictionary:
	_next += 1
	_serial += 1
	var dir := (aim - from).normalized() if from.distance_to(aim) > 0.01 else Vector3.FORWARD
	var a := {"id": _next, "serial": _serial, "pos": from, "dir": dir, "speed": HOMING_SLOW if homing else SPEED, "homing": homing,
		"damage": damage, "shooter": shooter, "travelled": 0.0, "born": now, "node": null}
	if root != null and vfx != null and vfx.has_method("arrow_visual"): a.node = vfx.arrow_visual(homing, from, dir)
	arrows.append(a)
	return a

# Burst arrow speed from the distance to the player: 5 m/s at 20 m and beyond,
# linear to 20 m/s at 10 m, 20 m/s closer still.
static func homing_speed(dist: float) -> float:
	if dist >= RAMP_FAR: return HOMING_SLOW
	if dist <= RAMP_NEAR: return HOMING_FAST
	return lerpf(HOMING_FAST, HOMING_SLOW, (dist - RAMP_NEAR) / (RAMP_FAR - RAMP_NEAR))

# ctx: {player, player_health, ray: Callable(from, to) -> Dictionary}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	if arrows.is_empty(): return
	var p: CharacterBody3D = ctx.player
	var ax: Array = _capsule(p)
	var chest: Vector3 = (ax[0] + ax[1]) * 0.5
	for a in arrows.duplicate():
		if now - float(a.born) > MAX_S or (not a.homing and float(a.travelled) > MAX_RANGE):
			_remove(a)
			continue
		if a.homing:
			var dist: float = (a.pos as Vector3).distance_to(chest)
			a.speed = homing_speed(dist)
			var want: Vector3 = (chest - a.pos).normalized()
			var ang: float = (a.dir as Vector3).angle_to(want)
			if ang > 1e-4:
				var axis: Vector3 = (a.dir as Vector3).cross(want)
				if axis.length() > 1e-6: a.dir = (a.dir as Vector3).rotated(axis.normalized(), minf(ang, TURN_RATE * delta)).normalized()
		var step: float = float(a.speed) * delta
		var from: Vector3 = a.pos
		var to: Vector3 = from + (a.dir as Vector3) * step
		# The player first (an arrow touching the capsule lands), then the world.
		if not ctx.player_health.dead and _seg_axis(from, to, ax[0], ax[1]) <= HIT_R + float(p.RADIUS if "RADIUS" in p else 0.3):
			var r: String = ctx.player_health.apply(DamagePacket.new(int(a.serial), String(a.shooter), "infected", float(a.damage), "bullet"), now)
			log.append({"id": a.id, "shooter": a.shooter, "homing": a.homing, "result": r, "amount": a.damage, "time": now})
			if vfx != null and vfx.has_method("arrow_hit"): vfx.arrow_hit(to, now)
			_remove(a)
			continue
		var w: Dictionary = ctx.ray.call(from, to) if ctx.has("ray") else {}
		if not w.is_empty(): # a tree, a rock or the ground
			log.append({"id": a.id, "shooter": a.shooter, "homing": a.homing, "result": "blocked", "amount": 0.0, "time": now})
			_remove(a)
			continue
		a.pos = to
		a.travelled = float(a.travelled) + step
		if a.node != null and is_instance_valid(a.node):
			a.node.global_position = to
			if absf((a.dir as Vector3).y) < 0.999: a.node.look_at(to + a.dir, Vector3.UP)

func _remove(a: Dictionary) -> void:
	_free(a)
	arrows.erase(a)

func _free(a: Dictionary) -> void:
	if a.get("node") != null and is_instance_valid(a.node): a.node.queue_free()
	a.node = null

static func _capsule(p: Node3D) -> Array:
	var h: float = p.height() if p.has_method("height") else 1.8
	var r: float = p.RADIUS if "RADIUS" in p else 0.3
	return [p.global_position + Vector3(0, r, 0), p.global_position + Vector3(0, maxf(r, h - r), 0)]

# Closest distance between segment from-to and the capsule axis a-b (sampled).
static func _seg_axis(from: Vector3, to: Vector3, a: Vector3, b: Vector3) -> float:
	var best := INF
	var n := maxi(1, ceili(from.distance_to(to) / 0.1))
	for i in range(n + 1):
		var pt := from.lerp(to, float(i) / float(n))
		var ab := b - a
		var u := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, pt.distance_to(a + ab * u))
	return best
