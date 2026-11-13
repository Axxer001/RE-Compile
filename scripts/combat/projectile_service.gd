extends RefCounted
# Fireballs in flight and their detonations (Grimoire MVP P2, plan §4.4).
# World-owned like hazards: a fireball outlives its cast. Each tick a fireball
# sweeps its path (world ray + enemy spheres) and detonates on the first
# contact, or, for a targeted special, on reaching its aim point. A detonation
# is one action: one DamagePacket id for every target in the radius (so the
# health dedup counts it once per target), plus the page's effect (Burn) on
# each target hit. Timing runs on the simulation clock.
#   [spec]   Tech Spec §3.2 page 1 (radius 3.5), GDD §5 page 1 (10% / 50% Pow,
#            Burn 5 s / 10 s), plan S7 (special: crosshair point, now up to 30 m [Sir, 2026-11-14])
#   [design] our numbers where neither gives one

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")

const KINDS := {
	# speed: about run speed [Sir, 2026-11-11]; aoe: basic [spec], special 15 x 15 m [Sir]; range [S7] / [design]
	# basic range = 3 s lifetime x 10 m/s [handoff P2]
	"basic":   {"speed": 10.0, "radius": 0.2, "aoe": 3.5, "range": 30.0, "color": Color(1.0, 0.55, 0.15), "noise": 8.0},
	"special": {"speed": 10.0, "radius": 0.5, "aoe": 7.5, "range": 30.0, "color": Color(1.0, 0.35, 0.05), "noise": 14.0},
}

# Ring of Fire orbitals (GDD page 3, plan S6, Sir R12): 6 orbs 60° apart on a
# 3 m ring that follows the caster, moving along it at twice the basic
# fireball's speed [Sir]; each orb is a basic fireball's size (0.2 m) and
# re-hits the same enemy at most every 0.5 s. A hit applies Scorched Slow
# (-90% Mov Spd for 2 s; a re-hit refreshes it, never stacks) [R12, 2 s proposed].
const ORBIT := {"count": 6, "radius": 3.0, "speed_mult": 2.0, "orb_radius": 0.2, "height": 1.0, "rehit_s": 0.5}
const SCORCHED_SLOW := {"id": "Scorched Slow", "s": 2.0, "mult": 0.1}

# A pool of 64 fireballs [handoff P7 perf]: never more in flight; a launch past
# the cap retires the oldest shot (it fizzles), and shot visuals are reused.
const POOL := 64
const BASIC_LIFE_S := 3.0   # [handoff P2] a basic fireball fizzles after 3 s
# Perf option A [Sir, 2026-11-13]: only the shots nearest the camera carry a
# light (re-ranked every tick); Ring of Fire's orbs always keep theirs.
const LIT_MAX := 8

var root: Node3D            # visuals parent (null = headless, no visuals)
var vfx: Node3D             # pooled effects (trails, bursts, scorches); null = none
var effects: RefCounted     # EffectSystem the detonations apply effects to
var shots: Array = []       # {id, kind, pos, vel, travelled, range, damage, effect, effect_s, pow, target_point, node}
var detonations: Array = [] # log: {shot, kind, at, hits: [{id, amount, result}], tick}
var _next := 0
var _flashes: Array = []    # [node, until] (presentation)
var _free_nodes := {"basic": [], "special": []} # pooled shot visuals (presentation)
var detonating := ""        # the kind of shot bursting right now ("" otherwise): presentation hooks read it
var rings: Array = []       # {id, anchor: Callable -> Vector3, start, until, damage, last: {"orb|target": time}, hits, nodes}

func reset() -> void:
	for s in shots: _release(s)
	for f in _flashes: _retire_flash(f[0])
	shots.clear()
	detonations.clear()
	_flashes.clear()
	for r in rings: _free_ring(r)
	rings.clear()

static func orbit_speed() -> float:
	return float(KINDS.basic.speed) * float(ORBIT.speed_mult) # 20 m/s along the ring

static func orbit_omega() -> float:
	return orbit_speed() / float(ORBIT.radius) # rad/s (about 382°/s)

# Summons a ring around `anchor` (called each tick for the centre: the ring moves with it).
func summon_ring(anchor: Callable, now: float, lifetime: float, damage: float) -> Dictionary:
	_next += 1
	var ring := {"id": _next, "anchor": anchor, "start": now, "until": now + lifetime, "damage": damage, "last": {}, "hits": [], "nodes": []}
	if root != null:
		for i in int(ORBIT.count):
			var orb := _take_visual("basic", anchor.call())
			var l: OmniLight3D = orb.find_children("*", "OmniLight3D", false, false)[0] if orb else null
			if l:
				l.light_energy = ORB_GLOW # the orbs glow brighter than a thrown fireball
				l.visible = true # orbs are never subject to the shot light cap
			if orb and orb.has_node("Trail"): orb.get_node("Trail").visible = false # an orb glows, it does not streak
			if vfx != null: vfx.orb_on(orb, true)
			ring.nodes.append(orb)
	rings.append(ring)
	return ring

func orb_positions(ring: Dictionary, now: float) -> Array:
	var c: Vector3 = ring.anchor.call()
	var out := []
	var a0 := orbit_omega() * (now - float(ring.start))
	for i in int(ORBIT.count):
		var a := a0 + TAU * float(i) / float(ORBIT.count)
		out.append(c + Vector3(cos(a) * ORBIT.radius, ORBIT.height, sin(a) * ORBIT.radius))
	return out

func _tick_rings(now: float, ctx: Dictionary) -> void:
	for ring in rings.duplicate():
		if now >= ring.until:
			_free_ring(ring)
			rings.erase(ring)
			continue
		var pos := orb_positions(ring, now)
		for i in pos.size():
			if i < ring.nodes.size() and ring.nodes[i]: ring.nodes[i].global_position = pos[i]
			for tg in ctx.get("targets", []):
				if tg.health.dead or gap_to(pos[i], tg) > float(ORBIT.orb_radius): continue
				var key := "%d|%s" % [i, tg.id]
				if now - float(ring.last.get(key, -INF)) + 1e-6 < float(ORBIT.rehit_s): continue
				ring.last[key] = now
				var result: String = tg.health.apply(DamagePacket.new(CombatController.next_id(), "player", "player", ring.damage, "fire"), now)
				if effects != null and not tg.health.dead and result in ["applied", "lethal", "duplicate"]:
					effects.apply(String(tg.id), SCORCHED_SLOW.id, SCORCHED_SLOW.s, now, "player")
				ring.hits.append({"orb": i, "id": tg.id, "time": now, "result": result})

const ORB_GLOW := 2.6
func _free_ring(ring: Dictionary) -> void:
	for n in ring.nodes: # back to the pool, the glow undone
		if n and is_instance_valid(n):
			var l: OmniLight3D = n.find_children("*", "OmniLight3D", false, false)[0]
			l.light_energy = 1.5
			if n.has_node("Trail"): n.get_node("Trail").visible = true
			if vfx != null: vfx.orb_on(n, false)
			n.visible = false
			_free_nodes.basic.append(n)
	ring.nodes = []

# Launches a fireball. `spec`: {damage, effect, effect_s, pow, target_point (optional)}.
func launch(kind: String, origin: Vector3, dir: Vector3, spec: Dictionary) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	if shots.size() >= POOL: _remove(shots[0]) # the pool is full: the oldest fizzles
	_next += 1
	var shot := {"id": _next, "kind": kind, "pos": origin, "vel": dir.normalized() * float(k.speed), "travelled": 0.0,
		"range": float(k.range), "damage": float(spec.get("damage", 0.0)), "effect": String(spec.get("effect", "")),
		"effect_s": float(spec.get("effect_s", 0.0)), "pow": float(spec.get("pow", 100.0)),
		"target_point": spec.get("target_point", null), "node": _take_visual(kind, origin)}
	if shot.target_point != null:
		shot.range = minf(shot.range, origin.distance_to(shot.target_point))
	shots.append(shot)
	return shot

# Advances every fireball by `delta`. ctx: {targets: [{id, pos, radius, health}], ray: Callable(from, to) -> Dictionary
# (world hit {position, normal} or {}), los: Callable(from, to) -> bool, noise (optional)}.
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	for s in shots.duplicate():
		var step: float = s.vel.length() * delta
		var left: float = s.range - s.travelled
		var dist := minf(step, left)
		var dir: Vector3 = s.vel.normalized()
		var from: Vector3 = s.pos
		var to: Vector3 = from + dir * dist
		var hit := _first_contact(from, to, float(KINDS[s.kind].radius), ctx)
		if not hit.is_empty():
			_detonate(s, hit.point, now, ctx)
			continue
		s.pos = to
		s.travelled += dist
		if s.node:
			s.node.global_position = to
			if dir.length_squared() > 0.0001 and absf(dir.y) < 0.999: s.node.look_at(to + dir, Vector3.UP) # the trail streams behind
		if s.travelled >= s.range - 1e-4:
			if s.target_point != null or s.kind == "special": _detonate(s, to, now, ctx) # aimed: bursts at its point / max range [S7]
			else: _remove(s) # a basic fireball that met nothing fizzles out
	_tick_rings(now, ctx)
	_rank_lights()
	for f in _flashes.duplicate():
		if now >= f[1]:
			_retire_flash(f[0])
			_flashes.erase(f)

# Earliest contact along the segment: the world (ray) or an enemy sphere
# (enemy radius + fireball radius). Returns {point} or {}.
func _first_contact(from: Vector3, to: Vector3, r: float, ctx: Dictionary) -> Dictionary:
	var best_t := INF
	var best := {}
	var seg := to - from
	var len := seg.length()
	if len < 1e-6: return {}
	var d := seg / len
	if ctx.has("ray"):
		var w: Dictionary = ctx.ray.call(from, to + d * r)
		if not w.is_empty():
			var t: float = maxf(0.0, from.distance_to(w.position) - r)
			if t < best_t:
				best_t = t
				best = {"point": from + d * t}
	var reach := len + r + 2.0 # broad phase: a target farther than this from the segment start cannot be touched
	for tg in ctx.get("targets", []):
		if tg.health.dead: continue
		if from.distance_squared_to(tg.pos) > reach * reach: continue
		var t := target_along(from, d, len, tg, r)
		if t >= 0.0 and t < best_t:
			best_t = t
			best = {"point": from + d * t}
	return best

# Distance along a ray to a target: its capsule (axis a-b) when given, else a
# sphere at pos; `extra` widens it (the fireball's own radius). -1 = no contact.
static func target_along(o: Vector3, d: Vector3, len: float, tg: Dictionary, extra := 0.0) -> float:
	var r: float = float(tg.radius) + extra
	if not tg.has("a"): return segment_sphere(o, d, len, tg.pos, r)
	# March the segment in 5 cm steps (a tick's path is under a metre; the
	# crosshair query marches 100 m). Only steps inside the capsule's bounding
	# sphere can hit, so the march visits just that stretch of the same grid:
	# identical result, a few dozen steps instead of 2,000 [perf 2026-11-14].
	var n := maxi(1, ceili(len / 0.05))
	var span := _sphere_span(o, d, len, (tg.a + tg.b) * 0.5, (tg.b - tg.a).length() * 0.5 + r)
	if span.is_empty(): return -1.0
	var i_from := maxi(0, floori(span[0] / len * float(n)) - 1)
	var i_to := mini(n, ceili(span[1] / len * float(n)) + 1)
	for i in range(i_from, i_to + 1):
		var t := len * float(i) / float(n)
		if axis_distance(o + d * t, tg.a, tg.b) <= r:
			if i == 0: return 0.0
			# Refine between the last miss and this hit.
			var lo := len * float(i - 1) / float(n)
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				if axis_distance(o + d * mid, tg.a, tg.b) <= r: hi = mid
				else: lo = mid
			return hi
	return -1.0

# Where the segment o + d*t (t in 0..len) is inside the sphere (c, rad): [t0, t1], or [].
static func _sphere_span(o: Vector3, d: Vector3, len: float, c: Vector3, rad: float) -> Array:
	var oc := o - c
	var qa := d.length_squared()
	if qa < 1e-12: return [0.0, len] if oc.length() <= rad else []
	var qb := oc.dot(d)
	var disc := qb * qb - qa * (oc.length_squared() - rad * rad)
	if disc < 0.0: return []
	var sq := sqrt(disc)
	var t0 := (-qb - sq) / qa
	var t1 := (-qb + sq) / qa
	if t1 < 0.0 or t0 > len: return []
	return [maxf(t0, 0.0), minf(t1, len)]

static func axis_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return p.distance_to(a + ab * u)

# Distance from a point to a target's surface (capsule or sphere), at least 0.
static func gap_to(p: Vector3, tg: Dictionary) -> float:
	var c: float = axis_distance(p, tg.a, tg.b) if tg.has("a") else p.distance_to(tg.pos)
	return maxf(0.0, c - float(tg.radius))

# Distance along a ray (origin o, unit dir d, length len) to a sphere, or -1.
static func segment_sphere(o: Vector3, d: Vector3, len: float, c: Vector3, r: float) -> float:
	var m := o - c
	if m.length_squared() <= r * r: return 0.0
	var b := m.dot(d)
	var cc := m.length_squared() - r * r
	if b > 0.0: return -1.0
	var disc := b * b - cc
	if disc < 0.0: return -1.0
	var t := -b - sqrt(disc)
	return t if t <= len else -1.0

func _detonate(s: Dictionary, at: Vector3, now: float, ctx: Dictionary) -> Dictionary:
	var k: Dictionary = KINDS[s.kind]
	var packet_id := CombatController.next_id()
	var rec := {"shot": s.id, "kind": s.kind, "at": at, "hits": [], "time": now}
	var eye := at + Vector3(0, 0.3, 0)
	detonating = s.kind
	for tg in ctx.get("targets", []):
		if tg.health.dead: continue
		if gap_to(at, tg) > float(k.aoe): continue
		if ctx.has("los") and not ctx.los.call(eye, tg.pos): continue
		var result: String = tg.health.apply(DamagePacket.new(packet_id, "player", "player", s.damage, "blast"), now)
		rec.hits.append({"id": tg.id, "amount": s.damage, "result": result})
		if effects != null and s.effect != "" and not tg.health.dead and (result == "applied" or result == "duplicate"):
			effects.apply(String(tg.id), s.effect, s.effect_s, now, "player", s.pow)
	detonating = ""
	detonations.append(rec)
	if ctx.has("noise"): ctx.noise.emit_noise(at, float(k.noise), "blast", "player", now)
	_burst(at, s.kind, now)
	_remove(s)
	return rec

func _retire_flash(n: Node3D) -> void:
	if not is_instance_valid(n): return
	n.visible = false
	_free_bursts[String(n.get_meta("kind", "basic"))].append(n)

func _remove(s: Dictionary) -> void:
	_release(s)
	shots.erase(s)

# Visual back to the pool (hidden), not freed.
func _release(s: Dictionary) -> void:
	var n: Node3D = s.node
	s.node = null
	if n == null or not is_instance_valid(n): return
	n.visible = false
	_free_nodes[s.kind].append(n)

var visuals_reused := 0   # counters for the performance runner
var visuals_created := 0
var visual_create_us := 0
func _take_visual(kind: String, at: Vector3) -> Node3D:
	if root == null: return null
	while not _free_nodes[kind].is_empty():
		var n: Node3D = _free_nodes[kind].pop_back()
		if is_instance_valid(n):
			n.visible = true
			n.global_position = at
			visuals_reused += 1
			return n
	var t0 := Time.get_ticks_usec()
	var made := _shot_visual(kind, at)
	visuals_created += 1
	visual_create_us += Time.get_ticks_usec() - t0
	return made

# Option A: the LIT_MAX live shots nearest the camera keep their light.
func _rank_lights() -> void:
	if root == null or not root.is_inside_tree(): return
	var cam := root.get_viewport().get_camera_3d()
	var eye: Vector3 = cam.global_position if cam else Vector3.ZERO
	var live: Array = shots.filter(func(sh): return sh.node != null and is_instance_valid(sh.node))
	if live.size() > LIT_MAX:
		live.sort_custom(func(a, b): return eye.distance_squared_to(a.pos) < eye.distance_squared_to(b.pos))
	for i in live.size():
		(live[i].node.get_meta("light") as OmniLight3D).visible = i < LIT_MAX

# Shots whose light is on (test hook).
func lit_shots() -> Array:
	return shots.filter(func(sh): return sh.node != null and (sh.node.get_meta("light") as OmniLight3D).visible)

func pooled_visuals() -> int:
	var n := 0
	for k in _free_nodes: n += _free_nodes[k].size()
	return n

# ---- visuals (presentation) ---------------------------------------------------

func _shot_visual(kind: String, at: Vector3) -> Node3D:
	if root == null: return null
	var k: Dictionary = KINDS[kind]
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	var sph := SphereMesh.new(); sph.radius = k.radius; sph.height = k.radius * 2.0
	m.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = k.color
	mat.emission_enabled = true
	mat.emission = k.color
	mat.emission_energy_multiplier = 3.0
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(m)
	var light := OmniLight3D.new()
	light.light_color = k.color
	light.light_energy = 1.5 if kind == "basic" else 3.0
	light.omni_range = 4.0 if kind == "basic" else 8.0
	n.add_child(light)
	n.set_meta("light", light)
	root.add_child(n)
	n.global_position = at
	if vfx != null: vfx.trail_for(n, kind)
	return n

# Burst visuals are pooled per kind and share one mesh and material each.
var _free_bursts := {"basic": [], "special": []}
static var _burst_res := {}

static func _burst_parts(kind: String) -> Array:
	if _burst_res.has(kind): return _burst_res[kind]
	var k: Dictionary = KINDS[kind]
	var sph := SphereMesh.new(); sph.radius = k.aoe; sph.height = k.aoe * 2.0 # the real blast extent
	sph.radial_segments = 24; sph.rings = 12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(k.color, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burst_res[kind] = [sph, mat]
	return _burst_res[kind]

func _burst(at: Vector3, kind: String, now: float) -> void:
	if root == null: return
	var n: Node3D = null
	while n == null and not _free_bursts[kind].is_empty():
		n = _free_bursts[kind].pop_back()
		if not is_instance_valid(n): n = null
	if n == null:
		var k: Dictionary = KINDS[kind]
		var parts := _burst_parts(kind)
		n = Node3D.new()
		var m := MeshInstance3D.new()
		m.mesh = parts[0]
		m.material_override = parts[1]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = vfx == null # with the Vfx, the Binbun blast is the visual; this keeps only its light flash
		n.add_child(m)
		var light := OmniLight3D.new()
		light.light_color = k.color
		light.light_energy = 5.0 if kind == "basic" else 9.0
		light.omni_range = k.aoe * 2.0
		n.add_child(light)
		n.set_meta("kind", kind)
		root.add_child(n)
	n.visible = true
	n.global_position = at
	_flashes.append([n, now + 0.15])
	if vfx != null: vfx.explosion(at, kind, now)
