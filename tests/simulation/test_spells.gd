extends RefCounted
# The three Rank E spells [Sir, 2026-11-14; docs/plan-cpp-lessons-and-new-spells.md]:
# Dragon's Breath (cone, 10 ticks, locks other actions), Firefly (lock-on split,
# retarget, fails with nothing spent), Explosion (full MP, frozen charge held in
# the air, a hit breaks it, 25 m blast, cooldown from the end).

const DT := 1.0 / 60.0
const SpellService = preload("res://scripts/combat/spell_service.gd")
const Lib = preload("res://scripts/core/page_library.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put(c: Node3D, id: String, at: Vector3) -> CharacterBody3D:
	var e: CharacterBody3D = c.enemies[id]
	e.reset_to(at, 0.0)
	e.inert = true
	e.health.max_hp = 1.0e6
	e.health.reset()
	return e

static func hits(c: Node3D, spell: String, id: String) -> Array:
	return c.spells.log.filter(func(h): return h.get("spell", "") == spell and h.get("id", "") == id and not h.has("cancelled"))

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	var pc: Node3D = c.pcombat
	var p: CharacterBody3D = c.player
	var ids: Array = c.enemies.keys()
	var home := Vector3(60, 0, 50)
	var face_x := func() -> void:
		p.global_position = home
		p.velocity = Vector3.ZERO
		p.yaw = deg_to_rad(-90.0) # facing +X
		p.pitch = 0.0
		p.apply_look()
	c.park_enemies()
	face_x.call()
	await tree.physics_frame
	var pages := ["dragons_breath", "firefly", "explosion"]
	check.call(pages.all(func(id): return s.grimoire.is_unlocked(id) and Lib.make(id).kind == Lib.AbilityPage.Kind.SPELL and Lib.make(id).rank_req == "E"), "Dragon's Breath, Firefly and Explosion: Rank E spells, unlocked from the start (for testing)")

	# ---- Dragon's Breath ---------------------------------------------------------------------------
	var br: Resource = s.grimoire.page("dragons_breath")
	pc.equip("spell_1", br)
	var inside := put(c, ids[0], home + Vector3(10, 0, 0))   # in the cone
	var wide := put(c, ids[1], home + Vector3(10, 0, 4.5))   # 10 m out, 4.5 m to the side: outside (1.25 m + body)
	var behind := put(c, ids[2], home + Vector3(-6, 0, 0))   # behind the mouth
	var far := put(c, ids[3], home + Vector3(23, 0, 0))      # past 20 m
	await tree.physics_frame
	var pow: float = pc._pow(s.run.time)
	var mp0: float = pc.mp
	var r: String = pc.use_slot("spell_1", Vector2.ZERO, s.run.time)
	var busy_in: String = c.spells.busy()
	var blocked: String = pc.use_slot("skill_1", Vector2.ZERO, s.run.time)
	var no_lmb: bool = not pc.can_cast()
	var moving: bool = not c.spells.frozen()
	steps(c, 0.25)
	var bar: Dictionary = c.channel_view(s.run.time)
	steps(c, 10.0)
	var in_h := hits(c, "dragons_breath", inside.enemy_id)
	var per: float = in_h[0].amount if not in_h.is_empty() else 0.0
	check.call(r == "ok" and is_equal_approx(pc.mp, mp0 - 50.0) and busy_in == "breath" and blocked == "busy" and no_lmb and moving and bar.get("label", "") == "Dragon's Breath", "Dragon's Breath: 50 MP; while breathing no other attack, skill or spell, but the player moves; the HUD shows its bar")
	check.call(in_h.size() == 20 and is_equal_approx(per, pow * 0.02) and c.effects.has(inside.enemy_id, "Burn", s.run.time), "the cone hits every 0.5 s for 10 s: 20 ticks of %.2f (2%% of Magic Pow) and Burn" % per)
	check.call(hits(c, "dragons_breath", wide.enemy_id).is_empty() and hits(c, "dragons_breath", behind.enemy_id).is_empty() and hits(c, "dragons_breath", far.enemy_id).is_empty(), "outside the cone (to the side, behind, past 20 m) nothing is hit")
	var cd_br: float = pc.remaining("spell_1", s.run.time)
	check.call(c.spells.busy() == "" and pc.can_cast() and cd_br > 0.0 and cd_br <= 20.0 * (1.0 - s.stats.value("spell_mastery", s.run.time)) - 10.0 + 0.2, "after 10 s the hands are free; the 20 s cooldown (x Spell Mastery) is running (%.1f s left)" % cd_br)
	# The cone itself: a wall between the mouth and an enemy blocks it.
	var mouth: Vector3 = c.spells.breath_mouth()
	var fwd: Vector3 = pc.aim_dir()
	var cone_ids: Array = c.spells.in_cone(mouth, fwd).map(func(t): return t.id)
	check.call(inside.enemy_id in cone_ids and not wide.enemy_id in cone_ids and SpellService.BREATH.length == 20.0 and SpellService.BREATH.end_radius * 2.0 == 5.0, "the cone is 20 m long and widens to 5 m")

	# ---- Firefly ----------------------------------------------------------------------------------
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	await tree.physics_frame
	var ff: Resource = s.grimoire.page("firefly")
	pc.equip("spell_2", ff)
	pc.mp = pc.max_mp(s.run.time)
	var mp1: float = pc.mp
	var none: String = pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	check.call(none == "no_target" and is_equal_approx(pc.mp, mp1) and pc.remaining("spell_2", s.run.time) == 0.0, "Firefly with no enemy in sight fails: nothing spent, no cooldown")
	var a := put(c, ids[0], home + Vector3(12, 0, -2))
	var b := put(c, ids[1], home + Vector3(14, 0, 2))
	await tree.physics_frame
	pow = pc._pow(s.run.time)
	var r2: String = pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	var flying: int = c.spells.missiles.size()
	var split := {}
	for m in c.spells.missiles: split[m.target] = int(split.get(m.target, 0)) + 1
	var rising: bool = c.spells.missiles.all(func(m): return m.rising)
	steps(c, 4.0)
	var ha := hits(c, "firefly", a.enemy_id)
	var hb := hits(c, "firefly", b.enemy_id)
	check.call(r2 == "ok" and is_equal_approx(pc.mp, mp1 - 70.0) and flying == 30 and split.get(a.enemy_id, 0) == 15 and split.get(b.enemy_id, 0) == 15 and rising, "2 locked enemies: 70 MP, 30 missiles rise, 15 for each")
	check.call(ha.size() == 15 and hb.size() == 15 and is_equal_approx(ha[0].amount, pow * 0.3) and c.spells.missiles.is_empty() and c.effects.has(a.enemy_id, "Burn", s.run.time), "every missile homes in and hits: 15 + 15 hits of %.1f (30%% of Magic Pow), Burn" % (ha[0].amount if not ha.is_empty() else 0.0))
	# Missiles per target = floor(30 / targets); more than 5 in sight: 5 locked.
	var counts := {}
	for n in [5, 4, 3, 1]:
		c.spells.reset()
		c.park_enemies()
		face_x.call()
		for i in n: put(c, ids[i], home + Vector3(10 + i, 0, -3 + i * 1.5))
		await tree.physics_frame
		pc.ready_at.erase("spell_2")
		pc.mp = pc.max_mp(s.run.time)
		pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
		var per_t := {}
		for m in c.spells.missiles: per_t[m.target] = int(per_t.get(m.target, 0)) + 1
		counts[n] = [per_t.size(), per_t.values().max() if not per_t.is_empty() else 0]
	check.call(counts[5] == [5, 6] and counts[4] == [4, 7] and counts[3] == [3, 10] and counts[1] == [1, 30], "missiles per target = floor(30 / targets): 5 -> 6, 4 -> 7, 3 -> 10, 1 -> 30 %s" % str(counts))
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	for i in 7: put(c, ids[i], home + Vector3(9 + i, 0, -4 + i * 1.3))
	await tree.physics_frame
	var locked: Array = c.spells.lock_targets()
	check.call(locked.size() == 5, "7 enemies in sight: 5 are locked (picked at random by the spell's own generator)")
	# A target dies mid-flight: its missiles go to the other locked enemy.
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	var dying := put(c, ids[0], home + Vector3(12, 0, -2))
	var other := put(c, ids[1], home + Vector3(14, 0, 2))
	await tree.physics_frame
	pc.ready_at.erase("spell_2")
	pc.mp = pc.max_mp(s.run.time)
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	steps(c, 0.2) # still rising
	dying.health.apply(c.DamagePacket.new(97001, "test", "player", 1.0e7, "blast"), s.run.time)
	steps(c, 4.0)
	check.call(hits(c, "firefly", other.enemy_id).size() == 30, "a locked enemy dies mid-flight: all its missiles retarget to the other (%d hits)" % hits(c, "firefly", other.enemy_id).size())

	# ---- Explosion --------------------------------------------------------------------------------
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	await tree.physics_frame
	var ex: Resource = s.grimoire.page("explosion")
	pc.equip("spell_3", ex)
	pc.mp = pc.max_mp(s.run.time) - 1.0
	var notfull: String = pc.use_slot("spell_3", Vector2.ZERO, s.run.time)
	check.call(notfull == "mp_full" and pc.remaining("spell_3", s.run.time) == 0.0 and is_equal_approx(pc.mp, pc.max_mp(s.run.time) - 1.0), "Explosion needs full MP: one short and nothing is spent")
	# In the air: cast 4 m up, held there; W held and the mouse moved change nothing.
	p.global_position = home + Vector3(0, 4, 0)
	p.velocity = Vector3.ZERO
	pc.mp = pc.max_mp(s.run.time)
	var r3: String = pc.use_slot("spell_3", Vector2.ZERO, s.run.time)
	var keys := {KEY_W: true}
	var saved: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	var yaw0: float = p.yaw
	p.queue_look(Vector2(40, 10))
	steps(c, 2.0)
	s.input.key_source = saved
	var held: bool = p.global_position.distance_to(home + Vector3(0, 4, 0)) < 0.01 and is_equal_approx(p.yaw, yaw0)
	var all_locked: bool = pc.use_slot("spell_1", Vector2.ZERO, s.run.time) == "busy" and not pc.can_cast()
	var frac: float = c.spells.charge_fraction(s.run.time)
	check.call(r3 == "ok" and pc.mp == 0.0 and c.spells.frozen() and held and all_locked and frac > 0.09 and frac < 0.11 and c.channel_view(s.run.time).label.begins_with("Explosion"), "Explosion spends all MP; charging, the player cannot move, look or act, held 4 m up in the air (charge %d%%)" % roundi(frac * 100.0))
	# A hit breaks it: MP stays spent, the full cooldown starts.
	p.health.apply(c.DamagePacket.new(97002, "sprite_x", "infected", 5.0, "bite"), s.run.time)
	var cd_ex: float = pc.remaining("spell_3", s.run.time)
	var want_cd: float = s.stats.cooldown(300.0, true, s.run.time)
	check.call(not c.spells.frozen() and c.spells.log.any(func(h): return h.has("cancelled")) and pc.mp < 1.0 and is_equal_approx(cd_ex, want_cd), "taking damage breaks the charge: MP stays spent, the full %.0f s cooldown starts" % want_cd)
	# A full charge: everything within 25 m of the point takes 1000%%, nothing beyond; never the caster.
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	p.health.reset()
	await tree.physics_frame
	pc.ready_at.erase("spell_3")
	pc.mp = pc.max_mp(s.run.time)
	pc.use_slot("spell_3", Vector2.ZERO, s.run.time)
	var point := home + Vector3(40, 0, 0)
	c.spells.charge.point = point
	var near := put(c, ids[0], point + Vector3(20, 0, 0))
	var edge := put(c, ids[1], point + Vector3(0, 0, 24.5))
	var out := put(c, ids[2], point + Vector3(0, 0, 27))
	var hp0: float = p.health.hp
	pow = pc._pow(s.run.time)
	steps(c, 19.5)
	var before_end: bool = hits(c, "explosion", near.enemy_id).is_empty()
	steps(c, 0.7)
	var nh := hits(c, "explosion", near.enemy_id)
	check.call(before_end and nh.size() == 1 and is_equal_approx(nh[0].amount, pow * 10.0) and hits(c, "explosion", edge.enemy_id).size() == 1 and hits(c, "explosion", out.enemy_id).is_empty() and is_equal_approx(p.health.hp, hp0), "after 20 s the point erupts: %.0f (1000%% of Magic Pow) to all within 25 m, none beyond, never the caster" % (nh[0].amount if not nh.is_empty() else 0.0))
	check.call(not c.spells.frozen() and is_equal_approx(pc.remaining("spell_3", s.run.time), s.stats.cooldown(300.0, true, s.run.time) - (s.run.time - c.spells.log.filter(func(h): return h.get("spell", "") == "explosion")[0].time)), "the 5 min cooldown (x Spell Mastery) starts when the charge ends")
	# The lock point: the crosshair point up to 80 m, on the ground when nothing is hit.
	var lp: Vector3 = c.spells.lock_point()
	var aim: Dictionary = pc.crosshair_point(80.0)
	var lp_ok: bool = lp.distance_to(aim.point) < 0.01 if aim.hit else (lp.y < 1.0 and Vector2(lp.x, lp.z).distance_to(Vector2(aim.point.x, aim.point.z)) < 0.01)
	p.pitch = deg_to_rad(15.0) # aim up at the sky: nothing within 80 m
	p.apply_look()
	var sky: Dictionary = pc.crosshair_point(80.0)
	var lp2: Vector3 = c.spells.lock_point()
	var lp2_ok: bool = sky.hit or (lp2.y < 1.0 and Vector2(lp2.x, lp2.z).distance_to(Vector2(sky.point.x, sky.point.z)) < 0.01)
	check.call(lp_ok and lp2_ok and lp.distance_to(p.camera.global_position) <= 80.5, "the locked point: what the crosshair hits within 80 m (%s), else the point 80 m out dropped to the ground (%s)" % [str(lp), str(lp2)])
	# ---- Settings > "Infinite Mana + No Cooldown" (testing; off by default) ------------------------
	c.spells.reset()
	c.park_enemies()
	face_x.call()
	await tree.physics_frame
	var st_s: RefCounted = s.settings
	var off_default: bool = not st_s.infinite_mana and not pc.free_casting()
	st_s.set_value("infinite_mana", true)
	pc.mp = 5.0
	pc.ready_at["spell_3"] = s.run.time + 999.0
	var ex_free: String = pc.use_slot("spell_3", Vector2.ZERO, s.run.time) # Explosion with 5 MP and a cooldown pending
	var mp_kept: bool = is_equal_approx(pc.mp, 5.0)
	c.spells.reset()
	pc.ready_at.erase("spell_3")
	var a2 := put(c, ids[0], home + Vector3(12, 0, 0))
	await tree.physics_frame
	var r_ff1: String = pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	var r_ff2: String = pc.use_slot("spell_2", Vector2.ZERO, s.run.time) # again at once: no cooldown
	var free_view: Dictionary = pc.slot_view(s.run.time)
	st_s.set_value("infinite_mana", false)
	var back_cd: bool = pc.remaining("spell_2", s.run.time) > 0.0
	check.call(off_default and ex_free == "ok" and mp_kept and r_ff1 == "ok" and r_ff2 == "ok" and is_equal_approx(pc.mp, 5.0) and free_view.spell_2.state == "ready" and pc.special_remaining(s.run.time) == 0.0 or false, "Infinite Mana + No Cooldown: off by default; on, Explosion starts at 5 MP, Firefly casts twice in a row, nothing is spent and every cooldown reads 0")
	check.call(back_cd, "switched off again, the real cooldowns are back")
	c.spells.reset()
	c.park_enemies()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
