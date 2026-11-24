extends RefCounted
# The Dark Forest roster [Sir, 2026-11-15; docs/plan-dark-forest-roster.md]:
# the Forest Ghoul (kiting, arrows, Burst with homing and the speed ramp, trees
# block), Kostas Mortus (wind-up, charge, hit = damage + 10 m knockback + Concuss,
# stopped and stunned by a rock, cooldown, half damage from the front, every effect
# halved, no knockback), the player's casting lockout on knockback (Concuss does not
# lock it), kill EXP per enemy, effects at full value on Sprite and Ghoul.
# run_forest: Map 1 starts with every enemy in the pool; more are made on demand; 12 idle Sprites awake at most.

const DT := 1.0 / 60.0
const Arrows = preload("res://scripts/combat/enemy_arrows.gd")
const Sprite = preload("res://scripts/actors/blighted_sprite.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put_player(c: Node3D, at: Vector3) -> void:
	c.player.global_position = at
	c.player.velocity = Vector3.ZERO
	c.player.pitch = 0.0
	c.player.apply_look()

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func wake(c: Node3D, e: CharacterBody3D, at: Vector3, yaw: float) -> void:
	c.park_enemies([e.enemy_id])
	e.reset_to(at, yaw)
	e.inert = false

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	var p: CharacterBody3D = c.player
	var h: Node = p.health
	var pc: Node3D = c.pcombat
	# An open east-west sight line of the arena (the ranged checks need sight).
	var row := -1.0
	for z in [76.0, 74.0, 56.0, 54.0, 48.0, 44.0, 36.0, 34.0, 20.0, 16.0, 6.0, 4.0]:
		if c.clear_line(Vector3(4, 1.6, z), Vector3(56, 1.6, z)): row = z; break
	check.call(row > 0.0, "an open sight line for the roster checks (z %.0f)" % row)

	# ---- Forest Ghoul ----------------------------------------------------------------------------
	var r: CharacterBody3D = c.enemies["ghoul_1"]
	check.call(r.kind == "ghoul" and r.hp_max == 250.0 and r.health.max_hp == 250.0 and r.move_speed == 5.0 and r.aggro_r == 35.0 and r.deaggro_r == 45.0 and not r.can_climb and r.damage == 70.0 and absf(r.attack_interval - 1.0 / 1.5) < 1e-6 and r.kill_exp == 35, "Forest Ghoul (renamed from Forest Ranger [15b]): 250 HP, 70 an arrow at 1.5/s, 5 m/s, detection 35 m, gives up past 45 m [Map 1 spec §4], cannot climb, 35 EXP")
	check.call(Arrows.SPEED == 10.0 and is_equal_approx(Arrows.homing_speed(25.0), 5.0) and is_equal_approx(Arrows.homing_speed(20.0), 5.0) and is_equal_approx(Arrows.homing_speed(15.0), 12.5) and is_equal_approx(Arrows.homing_speed(10.0), 20.0) and is_equal_approx(Arrows.homing_speed(4.0), 20.0), "arrows: 10 m/s [15b]; Burst arrows 5 m/s beyond 20 m, ramping to 20 m/s at 10 m")
	h.reset()
	h.grant_immunity(INF, ["*"], -INF, "test") # the Ghoul's arrows are read from their log
	wake(c, r, Vector3(6, 0, row), -90.0)
	put_player(c, Vector3(26, 0, row)) # 20 m: in its 22 m range [Map 1 spec §4], in sight
	await tree.physics_frame
	c.arrows.reset()
	var shot_times: Array = []
	var last_shots := 0
	for i in int(round(5.0 / DT)):
		s.step(DT)
		if r.shots > last_shots:
			for k in r.shots - last_shots: shot_times.append(s.run.time)
			last_shots = r.shots
	var burst_arrows: Array = c.arrows.log.filter(func(a): return a.homing)
	var first_three := shot_times.slice(0, 3)
	var gap_burst: float = (float(first_three[2]) - float(first_three[0])) / 2.0 if first_three.size() == 3 else -1.0
	var gap_normal: float = float(shot_times[4]) - float(shot_times[3]) if shot_times.size() >= 5 else -1.0
	check.call(r.state == Sprite.State.CHASE and flat(r.global_position).distance_to(flat(Vector3(6, 0, row))) < 0.5 and r.bursts == 1, "at 20 m it holds its ground and draws (%d shots, %d Burst)" % [r.shots, r.bursts])
	check.call(absf(gap_burst - 1.0 / 3.0) < 0.04 and absf(gap_normal - 1.0 / 1.5) < 0.04, "its first attack is a Burst: 3 arrows at double rate (%.2f s apart), then normal shots %.2f s apart" % [gap_burst, gap_normal])
	var homing_ok: bool = burst_arrows.all(func(a): return is_equal_approx(float(a.amount), 35.0) and a.result != "blocked") and c.arrows.log.filter(func(a): return not a.homing).all(func(a): return is_equal_approx(float(a.amount), 70.0))
	check.call(c.arrows.log.size() >= 4 and homing_ok and burst_arrows.size() == 3, "Burst arrows home in for 35 each; the rest fly straight for 70 (%d landed)" % c.arrows.log.size())
	# A normal arrow flies at 10 m/s; a pillar stops it.
	c.arrows.reset()
	h.grant_immunity(-1.0, [], -INF, "test")
	var a1: Dictionary = c.arrows.fire(Vector3(80, 1.5, 40), Vector3(80, 1.5, 20), 70.0, false, "test", s.run.time) # the pillar at (80, 28) in its way
	for i in 30: c.arrows.tick(DT, s.run.time + i * DT, {"player": p, "player_health": h, "ray": c.world_ray})
	var flown: float = float(a1.travelled)
	for i in 60: c.arrows.tick(DT, s.run.time + (30 + i) * DT, {"player": p, "player_health": h, "ray": c.world_ray})
	check.call(absf(flown - 5.0) < 0.1 and c.arrows.log.size() == 1 and c.arrows.log[0].result == "blocked" and c.arrows.arrows.is_empty(), "an arrow flies 10 m/s (%.2f m in 0.5 s) and a pillar stops it" % flown)
	# A Burst arrow bends after a player who moved (gently).
	c.arrows.reset()
	h.reset()
	put_player(c, Vector3(36, 0, row))
	await tree.physics_frame
	c.arrows.fire(Vector3(6, 1.5, row), Vector3(36, 1.2, row + 6.0), 35.0, true, "test", s.run.time) # aimed 6 m off
	var t_hit := -1.0
	for i in int(round(6.0 / DT)):
		c.arrows.tick(DT, s.run.time + i * DT, {"player": p, "player_health": h, "ray": c.world_ray})
		if not c.arrows.log.is_empty():
			t_hit = i * DT
			break
	check.call(t_hit > 0.0 and c.arrows.log[0].result == "applied" and is_equal_approx(h.hp, 965.0), "a Burst arrow aimed 6 m off homes in and lands 35 (hp %.0f, %.1f s)" % [h.hp, t_hit])
	# Keeps its distance: inside 10 m it backs off; beyond 22 m it closes in.
	wake(c, r, Vector3(30, 0, row), -90.0)
	put_player(c, Vector3(37, 0, row)) # 7 m
	await tree.physics_frame
	r._go(Sprite.State.CHASE)
	steps(c, 1.0)
	var backed: float = r.distance_to_player(p)
	wake(c, r, Vector3(6, 0, row), -90.0)
	put_player(c, Vector3(46, 0, row)) # 40 m
	await tree.physics_frame
	r._go(Sprite.State.CHASE)
	steps(c, 1.0)
	var closed: float = r.distance_to_player(p)
	check.call(backed > 9.0 and closed < 39.0, "it backs off inside 10 m (7 -> %.1f m) and closes in beyond 22 m (40 -> %.1f m)" % [backed, closed])
	# Every player effect lands on it at full value.
	c.effects.apply(r.enemy_id, "Burn", 5.0, s.run.time, "player", 1000.0)
	c.effects.apply(r.enemy_id, c.projectiles.SCORCHED_SLOW.id, 2.0, s.run.time, "player")
	s.step(DT)
	check.call(absf(c.effects.remaining(r.enemy_id, "Burn", s.run.time) - 5.0) < 0.05 and is_equal_approx(r.speed_mult, 0.1), "Burn and Scorched Slow land on a Ghoul at full value (Burn %.1f s, speed x%.2f)" % [c.effects.remaining(r.enemy_id, "Burn", s.run.time), r.speed_mult])
	c.effects.clear_target(r.enemy_id)

	# ---- Kostas Mortus ----------------------------------------------------------------------------
	var m: CharacterBody3D = c.enemies["mortus_1"]
	check.call(m.kind == "mortus" and m.health.max_hp == 3000.0 and m.damage == 80.0 and is_equal_approx(m.attack_interval, 2.0) and m.move_speed == 3.0 and m.aggro_r == 25.0 and m.deaggro_r == 35.0 and not m.can_climb and m.windup_r == 1.5 and m.kill_exp == 200 and m.resist == 0.5 and m.displace_immune, "Kostas Mortus: 3000 HP, 80 at 0.5/s, 3 m/s, detection 25 m, gives up past 35 m [Map 1 spec §4], range 1.5 m, cannot climb [15b], 200 EXP; effects halved, no knockback")
	# No climbing [Sir, 2026-11-15b]: walking at the 2 m ledge (x 90-94, z 37-43) toward a
	# player on top, it stays on the ground (a Sprite climbs it: test_r12).
	h.reset()
	wake(c, m, Vector3(92, 0, 48), 180.0)
	put_player(c, Vector3(92, 2.0, 40)) # 8 m: inside detection, under the charge's 12 m
	await tree.physics_frame
	m.alert_to(p.global_position)
	var m_top := -INF
	for i in int(round(4.0 / DT)):
		p.global_position = Vector3(92, 2.0, 40)
		p.velocity = Vector3.ZERO
		s.step(DT)
		m_top = maxf(m_top, m.global_position.y)
	check.call(m.climbs == 0 and not m.climbing and m_top < 0.5 and m.state != Sprite.State.DEAD, "Kostas Mortus cannot climb: 4 s at a 2 m ledge's foot, still on the ground (up to %.2f m)" % m_top)
	var probe_sprite := Sprite.new()
	check.call(probe_sprite.can_climb, "a Blighted Sprite can climb [15b]")
	probe_sprite.free()
	# The charge: 1.5 s wind-up, then 20 m/s at where it saw the player; 100 damage, 10 m back, Concuss 3 s.
	h.reset()
	s.stats.modifiers.clear()
	wake(c, m, Vector3(6, 0, row), -90.0)
	put_player(c, Vector3(26, 0, row)) # 20 m
	await tree.physics_frame
	m.alert_to(p.global_position)
	s.step(DT); s.step(DT)
	var winding: bool = m.state == Sprite.State.CHARGE
	steps(c, 1.4)
	var still: bool = m.state == Sprite.State.CHARGE and flat(m.global_position).distance_to(flat(Vector3(6, 0, row))) < 0.05 and h.hp == 1000.0
	var p0: Vector3 = p.global_position
	var hit_at := -1.0
	var locked := false
	for i in int(round(2.0 / DT)):
		s.step(DT)
		if hit_at < 0.0 and h.hp < 1000.0:
			hit_at = s.run.time
			locked = pc.controlled() and not pc.can_cast() and pc.use_slot("spell_2", Vector2.ZERO, s.run.time) == "controlled"
		if hit_at > 0.0 and c.player_knock.is_empty(): break
	var pushed: float = flat(p.global_position).distance_to(flat(p0))
	check.call(winding and still, "Mortus winds up 1.5 s before it charges (standing, no damage)")
	check.call(hit_at > 0.0 and is_equal_approx(h.hp, 900.0) and m.charge_hits == 1 and pushed > 9.0 and pushed < 11.5, "the charge hits: 100 damage (hp %.0f), knocked back %.1f m" % [h.hp, pushed])
	check.call(locked, "knocked back: no casting while it lasts")
	steps(c, 0.2)
	var concussed: bool = absf(p.run_top() - 2.0) < 0.01
	check.call(concussed and not pc.controlled() and pc.can_cast(), "Concussed afterwards (run %.1f m/s), yet free to cast: Concuss never locks casting" % p.run_top())
	check.call(absf(m.charge_ready - (hit_at - (hit_at - m.charge_ready + 15.0)) - 0.0) < 100.0 and m.charge_ready > s.run.time + 12.0, "the charge goes on a 15 s cooldown (%.1f s left)" % (m.charge_ready - s.run.time))
	s.stats.modifiers.clear()
	# A crate in the way: the charge stops on it and Mortus stands stunned 1.5 s.
	h.reset()
	wake(c, m, Vector3(72.2, 0, 50), 180.0)
	put_player(c, Vector3(72.2, 0, 72)) # 22 m; the 1 m crate at (72, 58) between (sight passes over it)
	await tree.physics_frame
	m.alert_to(p.global_position)
	var stunned_at := -1.0
	for i in int(round(4.0 / DT)):
		s.step(DT)
		if m.state == Sprite.State.STUN and stunned_at < 0.0: stunned_at = s.run.time
		if stunned_at > 0.0 and s.run.time - stunned_at > 1.2: break
	var still_stunned: bool = m.state == Sprite.State.STUN
	steps(c, 0.4)
	check.call(stunned_at > 0.0 and m.stuns == 1 and m.charge_hits == 0 and still_stunned and m.state != Sprite.State.STUN and h.hp == 1000.0, "a crate stops the charge: Mortus is stunned 1.5 s, the player untouched")
	# 50% less damage from the front.
	wake(c, m, Vector3(40, 0, row), -90.0) # facing +x
	m.inert = true
	put_player(c, Vector3(50, 0, row)) # in front
	m._player_pos = p.global_position
	var hp0: float = m.health.hp
	m.health.apply(DamagePacket.new(990501, "player", "player", 100.0, "blast"), s.run.time)
	var front_dmg: float = hp0 - m.health.hp
	m._player_pos = Vector3(30, 0, row) # behind it
	hp0 = m.health.hp
	m.health.apply(DamagePacket.new(990502, "player", "player", 100.0, "blast"), s.run.time)
	var back_dmg: float = hp0 - m.health.hp
	check.call(is_equal_approx(front_dmg, 50.0) and is_equal_approx(back_dmg, 100.0), "from the front it takes half (%.0f of 100), from behind full (%.0f)" % [front_dmg, back_dmg])
	# Every effect halved: duration, stat reduction, damage.
	m.inert = false
	c.effects.apply(m.enemy_id, "Burn", 5.0, s.run.time, "player", 1000.0)
	c.effects.apply(m.enemy_id, c.projectiles.SCORCHED_SLOW.id, 2.0, s.run.time, "player")
	c.effects.apply(m.enemy_id, c.spells.CONCUSS_ID, 3.0, s.run.time, "player")
	put_player(c, Vector3(100, 0, 10))
	s.step(DT)
	var burn_e: Dictionary = c.effects.active.get(m.enemy_id, {}).get("Burn", {})
	check.call(absf(c.effects.remaining(m.enemy_id, "Burn", s.run.time) - 2.5) < 0.05 and is_equal_approx(float(burn_e.get("pow", 0.0)), 500.0) and is_equal_approx(m.speed_mult, 0.55) and is_equal_approx(m.atk_mult, 0.6), "every effect on Mortus is halved: Burn 2.5 s at half damage, Scorched Slow -45%%, Concuss -40%% (speed x%.2f, attack x%.2f)" % [m.speed_mult, m.atk_mult])
	c.effects.clear_target(m.enemy_id)
	# No knockback (a blast that throws a Sprite leaves Mortus standing).
	var sp: CharacterBody3D = c.enemies["sprite_2"]
	sp.reset_to(Vector3(44, 0, row), 0.0)
	sp.inert = true
	var mp0: Vector3 = m.global_position
	c.spells.blast(Vector3(42, 0, row), 20.0, 1.0, "Burn", 1.0, 20.0, s.run.time, "test")
	check.call(flat(m.global_position).distance_to(flat(mp0)) < 0.01 and flat(sp.global_position).distance_to(Vector2(42, row)) > 19.0, "a knockback blast throws a Sprite 20 m but not Mortus")
	# Kill EXP per enemy: Sprite 25, Ghoul 35, Mortus 200.
	var got: Array = []
	var on_exp := func(amount: int, source: String) -> void: if source == "kill": got.append(amount)
	s.progression.exp_gained.connect(on_exp)
	for e in [sp, r, m]:
		e.inert = true
		e.health.apply(DamagePacket.new(990600 + got.size(), "player", "player", 1.0e6, "blast"), s.run.time)
	s.progression.exp_gained.disconnect(on_exp)
	check.call(got == [25, 35, 200], "kill EXP: Sprite 25, Ghoul 35, Mortus 200 (%s)" % str(got))
	h.reset()
	s.stats.modifiers.clear()
	s.restart()
	await tree.physics_frame

# Map 1's pool [spec §4]: nothing out at the camp; spawns bring kinds from the
# pool (more are made when it runs out), and at most 12 idle Sprites stay awake.
static func run_forest(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	var pool := {"sprite": 0, "ghoul": 0, "mortus": 0}
	for e in c.enemies.values(): pool[e.kind] += 1
	check.call(c.alive_count() == 0 and pool.sprite >= int(c.M1_POOL.sprite) and pool.ghoul >= int(c.M1_POOL.ghoul) and pool.mortus >= int(c.M1_POOL.mortus), "Map 1 starts with every enemy in the pool (%d Sprites, %d Ghouls, %d Mortus): the camp is safe" % [pool.sprite, pool.ghoul, pool.mortus])
	var n0: int = c.enemies.size()
	var made := []
	for i in int(c.M1_POOL.mortus) + 2: made.append(c._m1_place("mortus", c.player.global_position + Vector3(4.0 + 1.5 * i, 0, -12)))
	check.call(c.enemies.size() == n0 + 2 and made.all(func(e): return e != null and e.kind == "mortus" and not e.reserve), "past the pool, more are made on demand (%d -> %d)" % [n0, c.enemies.size()])
	for e in made: c._to_reserve(e)
	for i in 30: s.step(DT)
	var awake := 0
	for e in c.enemies.values():
		if e.kind == "sprite" and not e.reserve and not e.dormant and not e.health.dead and e.visible: awake += 1
	check.call(awake <= c.AWAKE_SPRITES, "at most 20 Sprites awake at once (%d)" % awake)
