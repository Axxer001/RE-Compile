extends RefCounted
# The three channelled / multi-hit spells [Sir, 2026-11-14; docs/plan-cpp-lessons-and-new-spells.md]:
#   Dragon's Breath  10 s cone of flame from the mouth (20 m long, widening to 5 m),
#                    2% Magic Pow per tick every 0.5 s (20 ticks), Burn 5 s; trees and
#                    walls block it; the player moves and looks freely, but no other
#                    attack, skill or spell while breathing.
#   Firefly          locks up to 5 enemies in view and line of sight within 30 m (more
#                    than 5: 5 at random, own RNG), launches floor(30 / targets) missiles
#                    per target that rise, then home; 30% Magic Pow each, Burn 5 s; a dead
#                    target's missiles retarget to another locked enemy. No target: the
#                    cast fails and nothing is spent.
#   Explosion        locks the crosshair point (up to 80 m; nothing hit: the point 80 m
#                    out, dropped to the ground) and charges 20 s, during which the
#                    player cannot move, look or act (held in the air if cast there).
#                    Any damage taken cancels it (MP stays spent, the full cooldown
#                    starts). Complete: 1000% Magic Pow to every enemy within 25 m of the
#                    point (a 50 m circle), never the caster, Burn 5 s.
# World-owned like the projectile service: ticked on the simulation clock from
# main.effects_step. Presentation goes through the Vfx (null = headless).

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")
const PS = preload("res://scripts/combat/projectile_service.gd")

const BREATH := {"length": 20.0, "end_radius": 2.5, "tick_s": 0.5, "ticks": 20, "s": 10.0, "burn_s": 5.0} # [Sir, 2026-11-14: 2% per tick for 10 s]
const FIREFLY := {"missiles": 30, "max_targets": 5, "range": 30.0, "rise_s": 0.55, "rise_speed": 9.0,
	"spread": 4.0, "speed": 26.0, "turn": 10.0, "hit_gap": 0.25, "life_s": 6.0, "burn_s": 5.0}
const EXPLOSION := {"charge_s": 20.0, "reach": 80.0, "radius": 25.0, "burn_s": 5.0}

var world: Node3D          # main: player, pcombat, combat_targets(), clear_line(), world_ray(), effects, vfx
var rng := RandomNumberGenerator.new() # Firefly's target picks: never the global sequence
var breath := {}           # {page, slot, start, until, next_tick, ticks, hits}
var missiles: Array = []   # {target, pos, vel, born, rising, damage, pow, node, id}
var charge := {}           # {page, slot, start, until, point, hold, airborne}
var log: Array = []        # {spell, id, amount, result, time}: what each spell hit (tests)
var _missile_free: Array = []
var root: Node3D           # visuals parent (null = headless)
var breath_fx: Node3D
var marker_fx: Node3D
var _next_missile := 0

func setup(main: Node3D) -> void:
	world = main
	rng.seed = 0x51F7

# What locks the player's hands: "breath", "explosion" or "".
func busy() -> String:
	if not charge.is_empty(): return "explosion"
	if not breath.is_empty(): return "breath"
	return ""

# Explosion's charge freezes movement and look (main.simulate).
func frozen() -> bool:
	return not charge.is_empty()

func hold_position() -> Vector3:
	return charge.get("hold", Vector3.ZERO)

# ---- checks before anything is spent ---------------------------------------------------

# "" if the spell can start now, else why not ("no_target", "mp_full").
func precheck(id: String, now: float) -> String:
	match id:
		"firefly":
			if lock_targets().is_empty(): return "no_target"
		"explosion":
			var pc = world.pcombat
			if pc.mp < pc.max_mp(now) - 0.001 and not pc.free_casting(): return "mp_full"
	return ""

# Firefly's locks: enemies within range, on screen and in line of sight; 5 at most.
func lock_targets() -> Array:
	var cam: Camera3D = world.player.camera
	var eye: Vector3 = cam.global_position
	var seen := []
	for tg in world.combat_targets():
		if tg.health.dead: continue
		if eye.distance_to(tg.pos) > float(FIREFLY.range): continue
		if not cam.is_position_in_frustum(tg.pos): continue
		if not world.clear_line(eye, tg.pos): continue
		seen.append(tg)
	if seen.size() > int(FIREFLY.max_targets):
		for i in range(seen.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = seen[i]; seen[i] = seen[j]; seen[j] = t
		seen = seen.slice(0, int(FIREFLY.max_targets))
	return seen

# ---- Dragon's Breath ----------------------------------------------------------------------

func start_breath(pg: Resource, slot: String, now: float) -> void:
	breath = {"page": pg, "slot": slot, "start": now, "until": now + float(BREATH.s), "next_tick": now + float(BREATH.tick_s), "ticks": 0, "hits": 0}
	if world.get("vfx") != null:
		if breath_fx == null:
			breath_fx = world.vfx.breath_cone()
			if breath_fx: world.player.camera.add_child(breath_fx)
		world.vfx.set_breath(breath_fx, true)

func breath_mouth() -> Vector3:
	var cam: Camera3D = world.player.camera
	var b := cam.global_transform.basis
	return cam.global_position - b.y * 0.12 - b.z * 0.3

# Every target the cone reaches now, past trees and walls: [target].
func in_cone(mouth: Vector3, dir: Vector3) -> Array:
	var out := []
	var length: float = BREATH.length
	for tg in world.combat_targets():
		if tg.health.dead: continue
		var v: Vector3 = tg.pos - mouth
		var along := v.dot(dir)
		if along <= 0.0 or along > length + float(tg.radius): continue
		var perp := (v - dir * along).length()
		if perp > float(BREATH.end_radius) * minf(along, length) / length + float(tg.radius): continue
		if not world.clear_line(mouth, tg.pos): continue
		out.append(tg)
	return out

func _tick_breath(now: float) -> void:
	if breath.is_empty(): return
	var pc = world.pcombat
	while not breath.is_empty() and now + 1e-6 >= float(breath.next_tick) and int(breath.ticks) < int(BREATH.ticks):
		var at: float = breath.next_tick
		breath.ticks += 1
		breath.next_tick = at + float(BREATH.tick_s)
		var pow: float = pc._pow(at)
		var pg: Resource = breath.page
		var packet := CombatController.next_id()
		for tg in in_cone(breath_mouth(), pc.aim_dir()):
			var result: String = tg.health.apply(DamagePacket.new(packet, "player", "player", pow * pg.damage_pct, "fire"), at)
			log.append({"spell": "dragons_breath", "id": tg.id, "amount": pow * pg.damage_pct, "result": result, "time": at})
			breath.hits += 1
			if world.effects != null and not tg.health.dead and result in ["applied", "duplicate"]:
				world.effects.apply(String(tg.id), pg.effect_id, float(BREATH.burn_s), at, "player", pow)
	if not breath.is_empty() and (int(breath.ticks) >= int(BREATH.ticks) or now >= float(breath.until) - 1e-6):
		end_breath()

func end_breath() -> void:
	breath = {}
	if breath_fx and world.get("vfx") != null: world.vfx.set_breath(breath_fx, false)

# ---- Firefly ---------------------------------------------------------------------------------

func start_firefly(pg: Resource, now: float) -> int:
	var targets := lock_targets()
	if targets.is_empty(): return 0
	var pc = world.pcombat
	var per := int(FIREFLY.missiles) / targets.size()
	var origin: Vector3 = pc.hand_origin()
	var pow: float = pc._pow(now)
	var launched := 0
	for tg in targets:
		for k in per:
			var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.5, 1.0) * float(FIREFLY.spread)
			var m := {"target": tg.id, "locked": targets.map(func(x): return x.id), "pos": origin, "vel": Vector3(0, float(FIREFLY.rise_speed) * rng.randf_range(0.85, 1.15), 0) + side,
				"born": now, "rising": true, "damage": pow * pg.damage_pct, "pow": pow, "effect": pg.effect_id, "node": _missile_node(origin), "id": _next_missile}
			_next_missile += 1
			missiles.append(m)
			launched += 1
	return launched

func _missile_node(at: Vector3) -> Node3D:
	if root == null or world.get("vfx") == null: return null
	var n: Node3D = _missile_free.pop_back() if not _missile_free.is_empty() else null
	if n == null or not is_instance_valid(n):
		n = Node3D.new()
		n.name = "Firefly"
		root.add_child(n)
		world.vfx.trail_for(n, "missile")
	n.visible = true
	n.global_position = at
	return n

func _free_missile(m: Dictionary) -> void:
	var n: Node3D = m.node
	m.node = null
	if n and is_instance_valid(n):
		n.visible = false
		_missile_free.append(n)

func _tick_missiles(delta: float, now: float) -> void:
	if missiles.is_empty(): return
	var by_id := {}
	for tg in world.combat_targets():
		if not tg.health.dead: by_id[tg.id] = tg
	for m in missiles.duplicate():
		if now - float(m.born) > float(FIREFLY.life_s):
			_free_missile(m); missiles.erase(m); continue
		if not by_id.has(m.target): # the target died: another locked one, else fizzle
			var alive: Array = (m.locked as Array).filter(func(id): return by_id.has(id))
			if alive.is_empty():
				_free_missile(m); missiles.erase(m); continue
			m.target = alive[rng.randi_range(0, alive.size() - 1)]
		var tg: Dictionary = by_id[m.target]
		if m.rising and now - float(m.born) >= float(FIREFLY.rise_s): m.rising = false
		if m.rising:
			m.vel = (m.vel as Vector3) * (1.0 - 1.5 * delta)
		else:
			var want: Vector3 = ((tg.pos as Vector3) - (m.pos as Vector3)).normalized() * float(FIREFLY.speed)
			m.vel = (m.vel as Vector3).lerp(want, clampf(float(FIREFLY.turn) * delta, 0.0, 1.0))
		var step: Vector3 = (m.vel as Vector3) * delta
		var from: Vector3 = m.pos
		m.pos = from + step
		var hit: bool = not m.rising and (PS.gap_to(m.pos, tg) <= float(FIREFLY.hit_gap) or PS.target_along(from, step.normalized(), step.length(), tg, float(FIREFLY.hit_gap)) >= 0.0)
		if m.node and is_instance_valid(m.node):
			m.node.global_position = m.pos
			var d := (m.vel as Vector3)
			if d.length_squared() > 0.01 and absf(d.normalized().y) < 0.999: m.node.look_at(m.pos + d, Vector3.UP)
		if hit:
			var result: String = tg.health.apply(DamagePacket.new(CombatController.next_id(), "player", "player", m.damage, "fire"), now)
			log.append({"spell": "firefly", "id": tg.id, "amount": m.damage, "result": result, "time": now, "missile": m.id})
			if world.effects != null and not tg.health.dead and result in ["applied", "duplicate"]:
				world.effects.apply(String(tg.id), m.effect, float(FIREFLY.burn_s), now, "player", m.pow)
			if world.get("vfx") != null: world.vfx.missile_hit(m.pos, now)
			_free_missile(m)
			missiles.erase(m)

# ---- Explosion -------------------------------------------------------------------------------

func start_explosion(pg: Resource, slot: String, now: float) -> void:
	var pc = world.pcombat
	if not pc.free_casting(): pc.mp = 0.0 # spends 100% of max MP (it needed full MP to start)
	var p: CharacterBody3D = world.player
	charge = {"page": pg, "slot": slot, "start": now, "until": now + float(EXPLOSION.charge_s), "point": lock_point(),
		"hold": p.global_position, "airborne": not p.is_on_floor()}
	if world.get("vfx") != null:
		if marker_fx == null:
			marker_fx = world.vfx.make_loop("marker")
			if marker_fx and root: root.add_child(marker_fx)
		if marker_fx:
			marker_fx.global_position = charge.point
			world.vfx.set_loop(marker_fx, true)

# The crosshair point up to 80 m; nothing hit: 80 m out, dropped to the ground.
func lock_point() -> Vector3:
	var pc = world.pcombat
	var aim: Dictionary = pc.crosshair_point(float(EXPLOSION.reach))
	var at: Vector3 = aim.point
	if aim.hit: return at
	var down: Dictionary = world.world_ray(at + Vector3(0, 60, 0), at + Vector3(0, -60, 0))
	return down.position if not down.is_empty() else Vector3(at.x, 0.0, at.z)

func charge_fraction(now: float) -> float:
	if charge.is_empty(): return 0.0
	return clampf((now - float(charge.start)) / float(EXPLOSION.charge_s), 0.0, 1.0)

func _tick_charge(now: float) -> void:
	if charge.is_empty(): return
	if now + 1e-6 < float(charge.until): return
	var pg: Resource = charge.page
	var pow: float = world.pcombat._pow(now)
	var packet := CombatController.next_id()
	var point: Vector3 = charge.point
	for tg in world.combat_targets(): # never the caster: only enemies are targets
		if tg.health.dead or PS.gap_to(point, tg) > float(EXPLOSION.radius): continue
		var result: String = tg.health.apply(DamagePacket.new(packet, "player", "player", pow * pg.damage_pct, "blast"), now)
		log.append({"spell": "explosion", "id": tg.id, "amount": pow * pg.damage_pct, "result": result, "time": now})
		if world.effects != null and not tg.health.dead and result in ["applied", "duplicate"]:
			world.effects.apply(String(tg.id), pg.effect_id, float(EXPLOSION.burn_s), now, "player", pow)
	if world.get("vfx") != null: world.vfx.cataclysm(point, now)
	if world.get("noise") != null: world.noise.emit_noise(point, 60.0, "blast", "player", now)
	_end_charge(now)

# Damage taken while charging breaks the spell: MP stays spent, the cooldown starts.
func on_player_hurt(applied: float, now: float) -> void:
	if applied > 0.0 and not charge.is_empty():
		log.append({"spell": "explosion", "cancelled": true, "time": now})
		_end_charge(now)

func _end_charge(now: float) -> void:
	var slot: String = charge.get("slot", "")
	var pg: Resource = charge.get("page")
	charge = {}
	if marker_fx and world.get("vfx") != null: world.vfx.set_loop(marker_fx, false)
	if slot != "" and pg != null: world.pcombat.start_cooldown(slot, pg, now) # the 5 min starts when it ends

# ---- clock ------------------------------------------------------------------------------------

func tick(delta: float, now: float) -> void:
	if world == null: return
	if world.player.health.dead:
		reset()
		return
	_tick_breath(now)
	_tick_missiles(delta, now)
	_tick_charge(now)

func reset() -> void:
	if not breath.is_empty(): end_breath()
	for m in missiles: _free_missile(m)
	missiles.clear()
	if not charge.is_empty():
		charge = {}
		if marker_fx and world and world.get("vfx") != null: world.vfx.set_loop(marker_fx, false)
	log.clear()
