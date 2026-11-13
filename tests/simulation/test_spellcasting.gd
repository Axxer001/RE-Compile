extends RefCounted
# P2 combat core (docs/pivot-grimoire-plan.md §4.3-4.4, GDD §5 page 1):
# basic fireball on the Atk Spd interval, the special at the crosshair point
# on a Spell Mastery cooldown, 3.5 m AOE detonations (one action per blast),
# Burn (2% Pow/s, 5 s / 10 s, refresh not stack), the MP pool, the casting
# hands, and a restart clearing it all. Driven through the session with
# synthetic keys and mouse buttons, like play.

const DT := 1.0 / 60.0
const Health = preload("res://scripts/combat/health_component.gd")
const Projectiles = preload("res://scripts/combat/projectile_service.gd")
const Effects = preload("res://scripts/core/effect_system.gd")

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)
	p.apply_look()
	p.reset_movement()

static func dummy(c: Node3D, id: String, pos: Vector3) -> Dictionary:
	var h: Node = Health.new()
	h.faction = "infected"
	c.add_child(h)
	return {"id": id, "pos": pos, "radius": 0.3, "health": h}

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"]) # one inert target dummy; enemy AI is tested in test_threat
	var foe: CharacterBody3D = c.enemies["sprite_1"]
	foe.reset_to(Vector3(112, 0, 74), 90.0, c.noise.last_id()); foe.inert = true # out of the way, far corner
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var pc: Node3D = c.pcombat
	var page: Resource = pc.page
	check.call(page.title == "Scorch and Burn" and page.damage_pct == 0.10 and page.special_damage_pct == 0.50 and page.special_cooldown_s == 15.0 and page.effect_s == 5.0 and page.special_effect_s == 10.0 and page.effect_id == "Burn", "attack page: Scorch and Burn (10% / 50% Pow, 15 s special, Burn 5 s / 10 s) [GDD §5]")
	check.call(is_equal_approx(pc.mp, 100.0) and is_equal_approx(pc.max_mp(), 100.0) and pc.special_remaining(s.run.time) == 0.0, "fresh run: MP 100/100, special ready")
	check.call(Projectiles.KINDS.basic.aoe == 3.5 and Projectiles.KINDS.special.aoe == 7.5 and Projectiles.KINDS.basic.speed == 10.0 and Projectiles.KINDS.special.speed == 10.0, "blast radius 3.5 m basic [spec], 7.5 m special (15 x 15 m); fireballs fly at run speed, 10 m/s [Sir]")

	# ---- detonation rules (service level, dummy targets) -----------------------------
	var fx: RefCounted = Effects.new()
	var ps: RefCounted = Projectiles.new()
	ps.effects = fx
	var near := dummy(c, "near", Vector3(2.8, 1, 0))     # edge 2.7 m from the blast (it bursts at x -0.2)
	var edge := dummy(c, "edge", Vector3(3.5, 1, 0))     # edge 3.4 m: inside
	var far := dummy(c, "far", Vector3(3.8, 1, 0))       # edge 3.7 m: outside 3.5
	var hidden := dummy(c, "hidden", Vector3(0, 1, 2.0)) # behind a wall (los says no)
	var tgts := [near, edge, far, hidden]
	var los := func(_a: Vector3, b: Vector3) -> bool: return b.z < 1.0
	ps.launch("basic", Vector3(-5, 1, 0), Vector3(1, 0, 0), {"damage": 10.0, "effect": "Burn", "effect_s": 5.0, "pow": 100.0})
	var wall_ray := func(a: Vector3, b: Vector3) -> Dictionary:
		# a wall face at x = 0 (the fireball comes from -x)
		if a.x < 0.0 and b.x >= 0.0:
			var t := -a.x / (b.x - a.x)
			return {"position": a.lerp(b, t), "normal": Vector3(-1, 0, 0)}
		return {}
	for i in 60: ps.tick(DT, i * DT, {"targets": tgts, "ray": wall_ray, "los": los})
	var det: Dictionary = ps.detonations[0] if ps.detonations.size() > 0 else {}
	var hit_ids := []
	for h in det.get("hits", []): hit_ids.append(h.id)
	check.call(ps.detonations.size() == 1 and ps.shots.is_empty() and absf(det.at.x + 0.2) < 0.05, "a fireball bursts on the wall it meets (x %.2f: its radius short of the face)" % (det.at.x if det.has("at") else INF))
	check.call(hit_ids == ["near", "edge"] and is_equal_approx(near.health.hp, 90.0) and is_equal_approx(far.health.hp, 100.0) and is_equal_approx(hidden.health.hp, 100.0), "the blast hits everything within 3.5 m of its edge, nothing past it or behind cover (%s)" % [hit_ids])
	check.call(fx.has("near", "Burn", 0.5) and fx.has("edge", "Burn", 0.5) and not fx.has("far", "Burn", 0.5), "Burn on every target the blast hit")
	# One blast = one action: offering the same packet twice lands once.
	check.call(near.health._seen.size() == 1, "a detonation is one action per target (dedup id)")
	# Enemy contact before the wall: a target in the path takes the burst.
	ps.reset()
	var inpath := dummy(c, "inpath", Vector3(-2.0, 1, 0))
	ps.launch("basic", Vector3(-10, 1, 0), Vector3(1, 0, 0), {"damage": 10.0, "effect": "", "pow": 100.0})
	for i in 90: ps.tick(DT, i * DT, {"targets": [inpath], "ray": wall_ray})
	check.call(ps.detonations.size() == 1 and absf(ps.detonations[0].at.x + 2.5) < 0.05 and is_equal_approx(inpath.health.hp, 90.0), "a fireball bursts on the first enemy it meets (x %.2f)" % (ps.detonations[0].at.x if ps.detonations.size() > 0 else INF))
	# A basic fireball that meets nothing fizzles after 3 s (30 m); a special bursts at its range.
	ps.reset()
	ps.launch("basic", Vector3.ZERO, Vector3(1, 0, 0), {"damage": 10.0})
	ps.launch("special", Vector3.ZERO, Vector3(-1, 0, 0), {"damage": 50.0})
	for i in 400: ps.tick(DT, i * DT, {"targets": []})
	check.call(ps.shots.is_empty() and ps.detonations.size() == 1 and ps.detonations[0].kind == "special" and absf(ps.detonations[0].at.x + 30.0) < 0.05, "past its range a basic fireball fizzles; a special bursts at 30 m [Sir, 2026-11-14]")
	ps.reset()
	ps.launch("basic", Vector3.ZERO, Vector3(1, 0, 0), {"damage": 10.0})
	var alive_at := -1.0
	for i in 200:
		ps.tick(DT, i * DT, {"targets": []})
		if ps.shots.is_empty() and alive_at < 0.0: alive_at = (i + 1) * DT
	check.call(absf(alive_at - ps.BASIC_LIFE_S) < DT * 1.5 and is_equal_approx(float(ps.KINDS.basic.range), float(ps.KINDS.basic.speed) * ps.BASIC_LIFE_S), "a basic fireball lives 3 s (gone at %.2f s), 30 m at 10 m/s [handoff P2]" % alive_at)
	ps.reset()
	var first: Dictionary = ps.launch("basic", Vector3.ZERO, Vector3(1, 0, 0), {"damage": 1.0})
	for i in ps.POOL: ps.launch("basic", Vector3(0, 0, i), Vector3(1, 0, 0), {"damage": 1.0})
	check.call(ps.shots.size() == ps.POOL and not first in ps.shots, "the pool holds 64 fireballs: one more retires the oldest")
	ps.reset()
	for d in [near, edge, far, hidden, inpath]: d.health.queue_free()

	# ---- Burn (effect system through the world) --------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	foe.reset_to(Vector3(60, 0, 49), 180.0, c.noise.last_id()); foe.inert = true # 8 m ahead, facing the player
	steps(c, 2)
	keys[MOUSE_BUTTON_LEFT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_LEFT)
	var t_cast: float = s.run.time
	var hit_at := -1.0
	for i in 90:
		s.step(DT)
		if foe.health.hp < 120.0 and foe.health.hp < foe.health.max_hp and hit_at < 0.0:
			hit_at = s.run.time
			break
	var after_hit: float = foe.health.hp
	check.call(hit_at > 0.0 and is_equal_approx(foe.health.max_hp - after_hit, 10.0) and hit_at - t_cast < 1.0, "LMB: a basic fireball reaches the enemy 8 m ahead in %.2f s for 10%% of Pow (%.1f)" % [hit_at - t_cast, foe.health.max_hp - after_hit])
	check.call(c.effects.has("sprite_1", "Burn", s.run.time) and absf(c.effects.remaining("sprite_1", "Burn", s.run.time) - 5.0) < 0.1, "the hit burns: Burn on the enemy for 5 s")
	foe.health.hp = after_hit
	for i in 30: s.step(DT) # sample mid-way between ticks (they fall every 1 s from the hit)
	var hp0: float = foe.health.hp
	for i in int(round(2.0 / DT)): s.step(DT)
	check.call(absf((hp0 - foe.health.hp) - 4.0) < 0.01, "Burn: 2%% of Pow per second (%.1f in 2 s)" % (hp0 - foe.health.hp))
	# Re-apply at 2 s: the timer refreshes, the rate does not stack.
	var refresh: String = c.effects.apply("sprite_1", "Burn", 5.0, s.run.time, "player", 100.0)
	var hp1: float = foe.health.hp
	for i in int(round(2.0 / DT)): s.step(DT)
	check.call(refresh == "refreshed" and absf((hp1 - foe.health.hp) - 4.0) < 0.01 and absf(c.effects.remaining("sprite_1", "Burn", s.run.time) - 3.0) < 0.1, "re-applied Burn refreshes to full, same 2/s rate (%.1f in 2 s, %.1f s left)" % [hp1 - foe.health.hp, c.effects.remaining("sprite_1", "Burn", s.run.time)])
	for i in int(round(3.5 / DT)): s.step(DT) # past the refreshed 5 s
	var hp2: float = foe.health.hp
	for i in 60: s.step(DT)
	check.call(not c.effects.has("sprite_1", "Burn", s.run.time) and is_equal_approx(hp2, foe.health.hp), "Burn ends with its timer: no more ticks")

	# ---- basic: Atk Spd interval ----------------------------------------------------
	foe.reset_to(Vector3(112, 0, 74), 90.0, c.noise.last_id()); foe.inert = true
	place(c, Vector3(60, 0, 57), 0.0, 20.0) # aim up into the open
	await tree.physics_frame
	steps(c, 2)
	var b0: int = pc.basic_casts
	keys[MOUSE_BUTTON_LEFT] = true
	steps(c, 60)
	keys.erase(MOUSE_BUTTON_LEFT)
	var per_s: int = pc.basic_casts - b0
	check.call(per_s == 5 and is_equal_approx(s.stats.attack_interval(s.run.time), 0.2), "LMB held 1 s at Atk Spd 5: %d fireballs (every 0.2 s) [GDD]" % per_s)
	steps(c, 30)
	s.stats.add_modifier("test_haste", "atk_spd", 1.0, 3.0, s.run.time + 5.0) # Atk Spd 8
	b0 = pc.basic_casts
	keys[MOUSE_BUTTON_LEFT] = true
	steps(c, 120)
	keys.erase(MOUSE_BUTTON_LEFT)
	s.stats.modifiers.clear()
	check.call(pc.basic_casts - b0 == 16, "Atk Spd 8: %d fireballs in 2 s (the fractional 0.125 s interval is kept)" % (pc.basic_casts - b0))
	# Tapping faster than the interval does not beat it.
	steps(c, 30)
	b0 = pc.basic_casts
	for i in 10:
		keys[MOUSE_BUTTON_LEFT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_LEFT); s.step(DT) # 30 clicks/s for 1/3 s
	check.call(pc.basic_casts - b0 == 2, "clicking at 30/s for 0.33 s casts only on the interval (%d)" % (pc.basic_casts - b0))
	check.call(is_equal_approx(pc.mp, 100.0), "basic fireballs cost no MP")
	steps(c, 90)

	# ---- special: crosshair point, 15 s cooldown x Spell Mastery ----------------------
	place(c, Vector3(60, 0, 57), 0.0, -30.0) # looking down at the floor ahead
	await tree.physics_frame
	steps(c, 2)
	var aim: Dictionary = pc.crosshair_point(40.0)
	var d0: int = c.projectiles.detonations.size()
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT)
	var t_sp: float = s.run.time
	steps(c, 2)
	keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(pc.special_casts == 1 and absf(pc.special_remaining(s.run.time) - (15.0 - (s.run.time - t_sp))) < 0.05, "RMB: special cast, 15 s cooldown (%.1f s left)" % pc.special_remaining(s.run.time))
	for i in 90:
		s.step(DT)
		if c.projectiles.detonations.size() > d0: break
	var sd: Dictionary = c.projectiles.detonations.back() if c.projectiles.detonations.size() > d0 else {}
	check.call(sd.get("kind", "") == "special" and (sd.at as Vector3).distance_to(aim.point) < 0.6 and aim.hit, "the special bursts at the crosshair's floor point (%.2f m off)" % ((sd.at as Vector3).distance_to(aim.point) if sd.has("at") else INF))
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(pc.special_casts == 1, "RMB on cooldown does nothing")
	# Damage and Burn: 50% of Pow, Burn 10 s.
	foe.reset_to(Vector3(60, 0, 47), 180.0, c.noise.last_id()); foe.inert = true
	pc.special_ready = 0.0
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	var fhp: float = foe.health.hp
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	for i in 120:
		s.step(DT)
		if foe.health.hp < fhp: break
	check.call(absf((fhp - foe.health.hp) - 50.0) < 0.01 and absf(c.effects.remaining("sprite_1", "Burn", s.run.time) - 10.0) < 0.1, "the special hits for 50%% of Pow (%.1f) and burns for 10 s" % (fhp - foe.health.hp))
	# A targeted area: the special flies to the point under the crosshair and bursts
	# there even when the enemy it was aimed at has moved off.
	steps(c, 30)
	foe.reset_to(Vector3(60, 0, 42), 180.0, c.noise.last_id()); foe.inert = true # 15 m ahead
	pc.special_ready = 0.0
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	var spot: Dictionary = pc.crosshair_point(40.0)
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	foe.reset_to(Vector3(20, 0, 74), 90.0, c.noise.last_id()); foe.inert = true # gone before impact
	await tree.physics_frame
	var dn: int = c.projectiles.detonations.size()
	for i in 150:
		s.step(DT)
		if c.projectiles.detonations.size() > dn: break
	var burst_at: Vector3 = c.projectiles.detonations.back().at if c.projectiles.detonations.size() > dn else Vector3.INF
	check.call(spot.enemy and burst_at.distance_to(spot.point) < 0.6, "the special bursts at the targeted spot after its target moved off (%.2f m off)" % burst_at.distance_to(spot.point))
	# Spell Mastery 20% cuts the cooldown to 12 s [spec §1.2 example].
	s.stats.add_modifier("test_mastery", "spell_mastery", 1.0, 0.20, s.run.time + 30.0)
	pc.special_ready = 0.0
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	var cd: float = pc.special_remaining(s.run.time) + DT
	s.stats.modifiers.clear()
	check.call(absf(cd - 12.0) < 0.05, "at 20%% Spell Mastery the special's cooldown is %.2f s (12)" % cd)
	# Magic Pow scales the hit.
	s.stats.add_modifier("test_pow", "magic_pow", 1.0, 50.0, s.run.time + 30.0) # Pow 150
	var shot: Dictionary = pc.cast_basic(s.run.time)
	s.stats.modifiers.clear()
	check.call(is_equal_approx(shot.damage, 15.0) and is_equal_approx(shot.pow, 150.0), "Magic Pow 150: a basic fireball carries 15 damage")
	steps(c, 60)

	# ---- MP pool ---------------------------------------------------------------------
	check.call(pc.spend_mp(30.0) and is_equal_approx(pc.mp, 70.0) and not pc.spend_mp(80.0) and is_equal_approx(pc.mp, 70.0), "MP: a 30 MP spell spends it; 80 more is refused and spends nothing")
	check.call(pc.hud_text(s.run.time).begins_with("MP 70/100"), "HUD shows MP (%s)" % pc.hud_text(s.run.time))

	# ---- hands -----------------------------------------------------------------------
	if pc.arms.skeleton != null:
		place(c, Vector3(60, 0, 57), 0.0, 20.0)
		await tree.physics_frame
		steps(c, 30)
		pc.publish()
		var rest_r: Vector3 = pc.arms.rests.r.origin # the free hand (targets follow it each frame)
		keys[MOUSE_BUTTON_LEFT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_LEFT)
		pc.publish()
		var out_r: Vector3 = pc.arms.targets.r.position
		var left_free: bool = not pc.arms.manual.l
		var grip_r: String = pc.arms.grip.r
		steps(c, 12)
		pc.publish()
		check.call(out_r.z < rest_r.z - 0.2 and left_free and grip_r == "open", "a basic cast pushes the right palm forward, open (%.2f m), left hand free" % (rest_r.z - out_r.z))
		check.call(not pc.arms.manual.r and pc.arms.grip.r == "relaxed", "the palm returns after the cast")
	# No casting while the hands are on a ledge.
	var cp: CharacterBody3D = c.player
	cp.state = cp.Move.MANTLE
	var bc: int = pc.basic_casts
	pc.simulate({"attack": true}, DT, s.run.time + 5.0)
	cp.state = cp.Move.GROUND
	check.call(pc.basic_casts == bc, "no casting while mantling or climbing (hands busy)")

	# ---- restart ---------------------------------------------------------------------
	pc.spend_mp(20.0)
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	pc.special_ready = s.run.time + 10.0
	pc.cast_basic(s.run.time)
	c.effects.apply("sprite_1", "Burn", 5.0, s.run.time, "player", 100.0)
	s.restart()
	check.call(c.projectiles.shots.is_empty() and c.effects.active.is_empty() and is_equal_approx(pc.mp, 100.0) and pc.special_remaining(s.run.time) == 0.0 and pc.basic_casts == 0, "restart: no fireballs, no effects, full MP, special ready")

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
