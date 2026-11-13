extends RefCounted
# Thrown items in flight, frag explosions and molotov fires (world-owned: a
# throw outlives its thrower). All timing runs on the simulation clock, so
# pausing freezes fuses and fires. Damage reaches the player and enemies alike
# (faction "hazard"); walls shield blasts. Visuals are presentation only.
#   Frag: 2 s fuse from the throw, one explosion, 4 m reach, 120 HP at the
#         centre falling linearly to 25% at the edge, line of sight required.
#   Molotov: on landing a 1.6 m fire for 6 s; each body inside takes 8 HP at
#         most every 0.5 s (rate-limited per body and per fire).

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")

const THROW_SPEED := 12.0
const ARC_HEIGHT := 1.2
const FRAG := {"fuse": 2.0, "radius": 4.0, "damage": 120.0, "edge": 0.25, "noise": 20.0}
const FIRE := {"radius": 1.6, "duration": 6.0, "tick": 0.5, "damage": 8.0, "noise": 6.0}

var throws: Array = []      # {id, item, from, to, t, dur, fuse_at, landed, node}
var fires: Array = []       # {id, at, until, next: {target_id: time}, node}
var explosions: Array = []  # {id, at, time, hits: [{id, amount, result}]} (log for tests/HUD)
var fire_ticks: Array = []  # {fire_id, target, amount, time}
var root: Node3D            # parent for visuals
var _serial := 0

func reset() -> void:
	for t in throws: if is_instance_valid(t.node): t.node.queue_free()
	for f in fires: if is_instance_valid(f.node): f.node.queue_free()
	throws.clear()
	fires.clear()
	explosions.clear()
	fire_ticks.clear()

static func falloff(distance: float, radius: float, edge: float) -> float:
	if distance > radius: return 0.0
	return 1.0 - (1.0 - edge) * clampf(distance / radius, 0.0, 1.0)

# A throw leaves the hand (the commit). Landing is decided by the thrower
# (already swept against walls). Returns the throw record.
func launch(item: String, from: Vector3, to: Vector3, now: float) -> Dictionary:
	_serial += 1
	var rec := {"id": "thr_%d" % _serial, "item": item, "from": from, "to": to, "t": 0.0,
		"dur": maxf(0.15, from.distance_to(to) / THROW_SPEED), "fuse_at": now + FRAG.fuse if item == "frag" else INF,
		"landed": false, "node": _throw_visual(item)}
	throws.append(rec)
	return rec

func position_of(rec: Dictionary) -> Vector3:
	var f: float = clampf(rec.t / rec.dur, 0.0, 1.0)
	return rec.from.lerp(rec.to, f) + Vector3(0, 4.0 * ARC_HEIGHT * f * (1.0 - f), 0)

# ctx: {targets: [{id, pos, radius, health}], los: Callable(from, to) -> bool, noise: NoiseService}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	for rec in throws.duplicate():
		rec.t = minf(rec.t + delta, rec.dur)
		if is_instance_valid(rec.node): rec.node.position = position_of(rec)
		if not rec.landed and rec.t >= rec.dur:
			rec.landed = true
			if rec.item == "molotov":
				_ignite(rec.to, now, ctx)
				_drop(rec)
		if rec.item == "frag" and now + 1e-6 >= rec.fuse_at:
			explode(position_of(rec), now, ctx)
			_drop(rec)
	for f in fires.duplicate():
		if now >= f.until:
			if is_instance_valid(f.node): f.node.queue_free()
			fires.erase(f)
			continue
		for t in ctx.targets:
			if t.health.dead: continue
			var flat := Vector2(t.pos.x - f.at.x, t.pos.z - f.at.z).length()
			if flat > FIRE.radius + t.radius or t.pos.y - f.at.y > 2.0: continue
			if now + 1e-6 < float(f.next.get(t.id, -INF)): continue
			f.next[t.id] = now + FIRE.tick
			var result: String = t.health.apply(DamagePacket.new(CombatController.next_id(), f.id, "hazard", FIRE.damage, "fire"), now)
			fire_ticks.append({"fire_id": f.id, "target": t.id, "amount": FIRE.damage, "result": result, "time": now})

func _drop(rec: Dictionary) -> void:
	if is_instance_valid(rec.node): rec.node.queue_free()
	throws.erase(rec)

func _ignite(at: Vector3, now: float, ctx: Dictionary) -> void:
	_serial += 1
	var f := {"id": "fire_%d" % _serial, "at": Vector3(at.x, 0.0, at.z), "until": now + FIRE.duration, "next": {}, "node": _fire_visual(at)}
	fires.append(f)
	if ctx.has("noise"): ctx.noise.emit_noise(f.at, FIRE.noise, "fire", "hazard", now)

# One explosion: every body within reach with a clear line takes falloff damage.
func explode(at: Vector3, now: float, ctx: Dictionary) -> Dictionary:
	var packet_id := CombatController.next_id()
	var rec := {"id": "blast_%d" % packet_id, "at": at, "time": now, "hits": []}
	var eye := at + Vector3(0, 0.3, 0)
	for t in ctx.targets:
		if t.health.dead: continue
		var d := maxf(0.0, t.pos.distance_to(at) - t.radius)
		var f := falloff(d, FRAG.radius, FRAG.edge)
		if f <= 0.0: continue
		if ctx.has("los") and not ctx.los.call(eye, t.pos): continue
		var amount: float = FRAG.damage * f
		var result: String = t.health.apply(DamagePacket.new(packet_id, rec.id, "hazard", amount, "blast"), now)
		rec.hits.append({"id": t.id, "amount": amount, "result": result})
	explosions.append(rec)
	if ctx.has("noise"): ctx.noise.emit_noise(at, FRAG.noise, "blast", "hazard", now)
	_flash(at)
	return rec

func _throw_visual(item: String) -> Node3D:
	if root == null: return null
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	if item == "frag":
		var s := SphereMesh.new(); s.radius = 0.06; s.height = 0.12; m.mesh = s
		mat.albedo_color = Color(0.25, 0.3, 0.2)
	else:
		var c := CylinderMesh.new(); c.top_radius = 0.025; c.bottom_radius = 0.045; c.height = 0.22; m.mesh = c
		mat.albedo_color = Color(0.35, 0.55, 0.3, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	root.add_child(m)
	return m

func _fire_visual(at: Vector3) -> Node3D:
	if root == null: return null
	var n := Node3D.new()
	n.position = Vector3(at.x, 0.02, at.z)
	var disc := MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = FIRE.radius; c.bottom_radius = FIRE.radius; c.height = 0.04
	disc.mesh = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material_override = mat
	n.add_child(disc)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position.y = 0.6
	n.add_child(light)
	root.add_child(n)
	return n

func _flash(at: Vector3) -> void:
	if root == null: return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 6.0
	light.omni_range = 8.0
	light.position = at + Vector3(0, 0.5, 0)
	root.add_child(light)
	light.get_tree().create_timer(0.15).timeout.connect(light.queue_free) if light.is_inside_tree() else light.queue_free()
