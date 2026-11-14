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

# What locks the player's hands: "breath", "explosion", "flight", "call" or "".
func busy() -> String:
	if not flight.is_empty(): return "flight"
	if not calling.is_empty(): return "call"
	if not charge.is_empty(): return "explosion"
	if not breath.is_empty(): return "breath"
	return ""

# Explosion's charge freezes movement and look (main.simulate).
func frozen() -> bool:
	return not charge.is_empty()

func hold_position() -> Vector3:
	if not calling.is_empty(): return calling.hold
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
		"flight_of_the_phoenix":
			if not world.player.is_on_floor(): return "airborne"
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
	if world.get("sfx") != null: world.sfx.start_loop("breath", "breath_loop")

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
	if world and world.get("sfx") != null: world.sfx.stop_loop("breath")
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
	if world.get("sfx") != null: world.sfx.play("firefly_launch", origin)
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
			if world.get("sfx") != null: world.sfx.play_capped("firefly_pop", m.pos, now)
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
	if world.get("sfx") != null:
		world.sfx.start_loop("charge", "charge_hum")
		world.sfx.set_loop_build("charge", 0.0)

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
	if world.get("sfx") != null: world.sfx.set_loop_build("charge", charge_fraction(now))
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
	if world.get("sfx") != null: world.sfx.boom(point)
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
	if world.get("sfx") != null: world.sfx.stop_loop("charge", 0.0) # cut off: by the blast, or by the hit that broke it
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
	_tick_flight(now)
	_tick_call(now)
	_tick_decor(now)

func reset() -> void:
	if not breath.is_empty(): end_breath()
	for m in missiles: _free_missile(m)
	missiles.clear()
	if not charge.is_empty():
		charge = {}
		if marker_fx and world and world.get("vfx") != null: world.vfx.set_loop(marker_fx, false)
	if not flight.is_empty(): _end_flight()
	for r in rain:
		if r.ring and is_instance_valid(r.ring): r.ring.queue_free()
	rain.clear()
	if not calling.is_empty():
		for n in calling.rings:
			if is_instance_valid(n): n.queue_free()
		calling = {}
	for r in _rings:
		if is_instance_valid(r.node): r.node.queue_free()
	_rings.clear()
	for k in _loops: if world and world.get("vfx") != null: world.vfx.set_loop(_loops[k], false)
	_fx_until.clear()
	_attack_was = false
	if world and world.get("sfx") != null: world.sfx.stop_all_loops()
	log.clear()

# ---- the Phoenix set [Sir, 2026-11-14; docs/plan-phoenix-spells.md] --------------------------
#   Flight of the Phoenix: on cast, enemies within 20 m are pulled to the cast spot
#   (no damage) and Concussed 3 s (-80% move and attack speed). The player climbs
#   30 m over 5 s, then hovers 5 s at the peak. LMB at any point picks a landing
#   spot: ground inside the 50 m ring round the cast spot (sky, outside or a wall
#   is refused, with a marker). The dive takes 3 s. Damage: 100% Magic Pow up to
#   2 s of climb, then linear to 500% at 5 s (the peak), fixed when the spot is
#   picked. No pick by the end of the hover: the dive goes to the cast spot.
#   Impact: 20 m radius, Burn, everything knocked back to 20 m. Throughout, the
#   player cannot move (looking is free), is invulnerable, takes no fall damage,
#   and nothing else can be cast (Sage Arts and Rise's heal wait too).
#   Call of the Phoenix: a 5 s casting state, held in place (hovering if cast in
#   the air; damage does not break it; looking is free). LMB marks up to 3 areas
#   (7.5 m radius, on the ground, at most 30 m away). A third mark ends the cast
#   at once; otherwise the marks made by the 5 s are kept. Each area then takes 30
#   basic Scorch and Burn fireballs falling over 5 s; tree trunks stop them.
const FLIGHT := {"pull_r": 20.0, "climb_s": 5.0, "height": 30.0, "window_s": 5.0, "crash_s": 3.0, "ring_r": 50.0,
	"impact_r": 20.0, "knock_to": 20.0, "burn_s": 5.0, "concuss_s": 3.0, "concuss_mult": 0.2, "reach": 140.0}
const CALL := {"cast_s": 5.0, "areas": 3, "area_r": 7.5, "reach": 30.0, "per_area": 30, "rain_s": 5.0, "drop_h": 12.0, "burn_s": 5.0}
const CONCUSS_ID := "Phoenix Concuss"
var flight := {}           # {page, slot, phase, start, cast_at, window_at, chosen, crash_from, crash_start, mult, picked_at}
var calling := {}             # {page, slot, start, until, hold, areas: [Vector3]}
var rain: Array = []       # {center, start, fired, ring}
var _attack_was := false
var _rings: Array = []     # {node, until} (decor)
var _fx_until := {}        # loop fx -> time to switch off

# Damage multiplier for a pick at `t` seconds into the climb (the hover counts as the peak).
static func flight_mult(t: float) -> float:
	if t <= 2.0: return 1.0
	if t >= 5.0: return 5.0
	return 1.0 + (t - 2.0) / 3.0 * 4.0

func move_locked() -> bool:
	return not flight.is_empty() or not calling.is_empty()

# LMB, every tick (main.simulate): its press picks Flight's spot or marks Call's area.
func on_input(attack_down: bool, now: float) -> void:
	var edge := attack_down and not _attack_was
	_attack_was = attack_down
	if not edge: return
	if not flight.is_empty() and flight.chosen == null: pick_flight_spot(now)
	elif not calling.is_empty(): mark_call_area(now)

func _aim_ground(reach: float) -> Dictionary:
	var cam: Camera3D = world.player.camera
	var eye: Vector3 = cam.global_position
	var hit: Dictionary = world.world_ray(eye, eye - cam.global_transform.basis.z * reach)
	if hit.is_empty() or hit.normal.y < 0.7: return {"ok": false, "point": hit.get("position", Vector3.INF)}
	return {"ok": true, "point": hit.position}

func _notice(text: String) -> void:
	if world.has_method("show_notice"): world.show_notice(text, 1.2)

# ---- Flight of the Phoenix ----------------------------------------------------------------------

func start_flight(pg: Resource, slot: String, now: float) -> void:
	var p: CharacterBody3D = world.player
	var at: Vector3 = p.global_position
	flight = {"page": pg, "slot": slot, "phase": "climb", "start": now, "cast_at": at, "window_at": INF, "chosen": null,
		"crash_from": at, "crash_start": INF, "mult": 1.0, "picked_at": -1.0}
	p.health.grant_immunity(now + FLIGHT.climb_s + FLIGHT.window_s + FLIGHT.crash_s + 0.5, ["*"], -INF, "flight")
	# The pull: everything within 20 m is dragged to the cast spot, unhurt, and Concussed.
	var k := 0
	for tg in world.combat_targets():
		if tg.health.dead or tg.get("body") == null or (tg.pos as Vector3).distance_to(at) > FLIGHT.pull_r: continue
		var body: Node3D = tg.body
		if not body is CharacterBody3D: continue
		var a := TAU * float(k) / 6.0 + 0.4
		body.global_position = at + Vector3(cos(a), 0, sin(a)) * (1.2 + 0.4 * (k / 6))
		(body as CharacterBody3D).velocity = Vector3.ZERO
		if world.effects != null: world.effects.apply(String(tg.id), CONCUSS_ID, FLIGHT.concuss_s, now, "player")
		log.append({"spell": "flight_pull", "id": tg.id, "time": now})
		k += 1
	if world.get("vfx") != null:
		flight.ring = world.vfx.ring(at, FLIGHT.ring_r, Color(1.0, 0.45, 0.1))
		_loop_fx("phoenix_pull", at, now + 1.5)
		_loop_fx("phoenix_trail", Vector3.INF, INF)
	if world.get("sfx") != null: world.sfx.start_loop("phoenix", "phoenix_climb")

func flight_phase() -> String:
	return String(flight.get("phase", ""))

# Where the player is now: climbing, hovering at the peak, or diving.
func flight_position(now: float) -> Vector3:
	var at: Vector3 = flight.cast_at
	match String(flight.phase):
		"climb":
			var u := clampf((now - float(flight.start)) / FLIGHT.climb_s, 0.0, 1.0)
			return at + Vector3(0, FLIGHT.height * (1.0 - (1.0 - u) * (1.0 - u)), 0)
		"window":
			return at + Vector3(0, FLIGHT.height, 0)
		"crash":
			var u := clampf((now - float(flight.crash_start)) / FLIGHT.crash_s, 0.0, 1.0)
			return (flight.crash_from as Vector3).lerp(flight.chosen, u * u)
	return at

func pick_flight_spot(now: float) -> bool:
	var aim := _aim_ground(FLIGHT.reach)
	var p: Vector3 = aim.point
	var inside: bool = aim.ok and Vector2(p.x - flight.cast_at.x, p.z - flight.cast_at.z).length() <= FLIGHT.ring_r
	if not inside:
		_notice("Choose ground inside the ring")
		if world.get("vfx") != null and p != Vector3.INF: _rings.append({"node": world.vfx.ring(p, 1.2, Color(0.9, 0.1, 0.1)), "until": now + 1.0})
		log.append({"spell": "flight_reject", "time": now})
		return false
	_begin_crash(p, flight_mult(now - float(flight.start)), now)
	return true

func _begin_crash(spot: Vector3, mult: float, now: float) -> void:
	flight.chosen = spot
	flight.mult = mult
	flight.picked_at = now - float(flight.start)
	flight.crash_from = flight_position(now)
	flight.crash_start = now
	flight.phase = "crash"
	if world.get("vfx") != null: flight.marker = world.vfx.ring(spot, 2.0, Color(1.0, 0.8, 0.2))
	if world.get("sfx") != null:
		world.sfx.stop_loop("phoenix")
		world.sfx.play("phoenix_dive", world.player.global_position)

func _tick_flight(now: float) -> void:
	if flight.is_empty(): return
	match String(flight.phase):
		"climb":
			if now - float(flight.start) + 1e-6 >= FLIGHT.climb_s:
				flight.phase = "window"
				flight.window_at = now
		"window":
			if now - float(flight.window_at) + 1e-6 >= FLIGHT.window_s: _begin_crash(flight.cast_at, 5.0, now) # no pick: back to the cast spot
		"crash":
			if now - float(flight.crash_start) + 1e-6 >= FLIGHT.crash_s: _flight_impact(now)

func _flight_impact(now: float) -> void:
	var spot: Vector3 = flight.chosen
	var pg: Resource = flight.page
	var pow: float = world.pcombat._pow(now)
	var dmg: float = pow * pg.damage_pct * float(flight.mult)
	blast(spot, FLIGHT.impact_r, dmg, pg.effect_id, FLIGHT.burn_s, FLIGHT.knock_to, now, "flight")
	var p: CharacterBody3D = world.player
	p.global_position = spot
	p.velocity = Vector3.ZERO
	p.health.grant_immunity(now + 0.1, ["*"], -INF, "flight") # the flight's invulnerability ends with it
	_end_flight()

# A blast: damage and Burn to every enemy within `r`, everything inside pushed out to `knock_to` m.
func blast(spot: Vector3, r: float, dmg: float, effect: String, burn_s: float, knock_to: float, now: float, tag: String) -> void:
	var pow: float = world.pcombat._pow(now)
	var packet := CombatController.next_id()
	for tg in world.combat_targets():
		if tg.health.dead or PS.gap_to(spot, tg) > r: continue
		var result: String = tg.health.apply(DamagePacket.new(packet, "player", "player", dmg, "blast"), now)
		log.append({"spell": tag, "id": tg.id, "amount": dmg, "result": result, "time": now})
		if world.effects != null and not tg.health.dead and result in ["applied", "duplicate"]:
			world.effects.apply(String(tg.id), effect, burn_s, now, "player", pow)
		var body = tg.get("body")
		if knock_to > 0.0 and body is CharacterBody3D and not tg.health.dead:
			var off: Vector3 = (body as Node3D).global_position - spot
			off.y = 0.0
			if off.length() < 0.05: off = Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
			if off.length() < knock_to: (body as Node3D).global_position = spot + off.normalized() * knock_to + Vector3(0, (body as Node3D).global_position.y - spot.y, 0)
	if world.get("vfx") != null: world.vfx.phoenix_impact(spot, now)
	if world.get("sfx") != null: world.sfx.boom(spot)
	if world.get("noise") != null: world.noise.emit_noise(spot, 50.0, "blast", "player", now)

func _end_flight() -> void:
	if world.get("vfx") != null:
		for k in ["ring", "marker"]:
			if flight.has(k) and is_instance_valid(flight[k]): flight[k].queue_free()
		_loop_off("phoenix_trail")
	if world.get("sfx") != null: world.sfx.stop_loop("phoenix")
	flight = {}

# ---- Call of the Phoenix -----------------------------------------------------------------------

func start_call(pg: Resource, slot: String, now: float) -> void:
	calling = {"page": pg, "slot": slot, "start": now, "until": now + CALL.cast_s, "hold": world.player.global_position, "areas": [], "rings": []}

func mark_call_area(now: float) -> bool:
	var aim := _aim_ground(CALL.reach)
	if not aim.ok:
		_notice("Mark the ground within %d m" % int(CALL.reach))
		log.append({"spell": "call_reject", "time": now})
		return false
	calling.areas.append(aim.point)
	if world.get("vfx") != null: calling.rings.append(world.vfx.ring(aim.point, CALL.area_r, Color(1.0, 0.35, 0.1)))
	log.append({"spell": "call_mark", "point": aim.point, "time": now})
	if calling.areas.size() >= int(CALL.areas): _end_call(now)
	return true

func _end_call(now: float) -> void:
	for i in calling.areas.size():
		rain.append({"center": calling.areas[i], "start": now, "fired": 0, "ring": calling.rings[i] if i < calling.rings.size() else null,
			"pow": world.pcombat._pow(now), "page": calling.page})
	if not calling.areas.is_empty() and world.get("sfx") != null: world.sfx.start_loop("rain", "rain_loop")
	calling = {}

func _tick_call(now: float) -> void:
	if not calling.is_empty() and now + 1e-6 >= float(calling.until): _end_call(now)
	for r in rain.duplicate():
		var due := int(floor((now - float(r.start)) / CALL.rain_s * CALL.per_area)) + 1
		due = mini(due, int(CALL.per_area))
		while int(r.fired) < due:
			_drop_fireball(r, now)
			r.fired += 1
		if int(r.fired) >= int(CALL.per_area) and now - float(r.start) > CALL.rain_s + 1.5:
			if r.ring and is_instance_valid(r.ring): r.ring.queue_free()
			rain.erase(r)
	if rain.is_empty() and world.get("sfx") != null and world.sfx.loop_playing("rain"): world.sfx.stop_loop("rain")

func _drop_fireball(r: Dictionary, now: float) -> void:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * CALL.area_r
	var ground: Vector3 = (r.center as Vector3) + Vector3(cos(a) * d, 0, sin(a) * d)
	var origin := ground + Vector3(rng.randf_range(-0.6, 0.6), CALL.drop_h, rng.randf_range(-0.6, 0.6))
	var pg: Resource = r.page
	world.projectiles.launch("basic", origin, (ground - origin).normalized(), {"damage": float(r.pow) * pg.damage_pct,
		"effect": pg.effect_id, "effect_s": CALL.burn_s, "pow": r.pow, "target_point": ground})
	log.append({"spell": "call_drop", "time": now})

func rain_falling() -> int:
	return rain.size()

# ---- small helpers -----------------------------------------------------------------------------

var _loops := {}
func _loop_fx(kind: String, at: Vector3, until: float) -> void:
	var fx: Node3D = _loops.get(kind)
	if fx == null:
		fx = world.vfx.make_loop(kind)
		if fx == null: return
		if kind == "phoenix_trail": world.player.add_child(fx)
		elif root: root.add_child(fx)
		_loops[kind] = fx
	if at != Vector3.INF: fx.global_position = at
	world.vfx.set_loop(fx, true)
	_fx_until[kind] = until

func _loop_off(kind: String) -> void:
	if _loops.has(kind): world.vfx.set_loop(_loops[kind], false)
	_fx_until.erase(kind)

func _tick_decor(now: float) -> void:
	for k in _fx_until.keys():
		if now >= float(_fx_until[k]): _loop_off(k)
	for r in _rings.duplicate():
		if now >= float(r.until):
			if is_instance_valid(r.node): r.node.queue_free()
			_rings.erase(r)
