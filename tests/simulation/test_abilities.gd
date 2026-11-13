extends RefCounted
# P4 abilities (GDD §3.1.3 and §5 pages 2-5, Codex handoff §4): the loadout and
# its equip rules, Cultivate, Quick Step, Ring of Fire, Sage Arts, rank gates,
# MP and cooldowns per slot, the action bar. Driven through the session with
# synthetic keys, like play.

const DT := 1.0 / 60.0
const Health = preload("res://scripts/combat/health_component.gd")
const Projectiles = preload("res://scripts/combat/projectile_service.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement()

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# One press: down a tick, then up a tick (a press needs an up tick before the next).
static func tap(c: Node3D, keys: Dictionary, k: int) -> void:
	keys[k] = true; c.session.step(DT); keys.erase(k); c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset() # a fresh profile: only the two start pages unlocked
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"])
	var foe: CharacterBody3D = c.enemies["sprite_1"]
	foe.reset_to(Vector3(112, 0, 74), 90.0); foe.inert = true
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var pc: Node3D = c.pcombat
	var p: CharacterBody3D = c.player
	var lo: Dictionary = pc.loadout

	# ---- loadout ----------------------------------------------------------------------
	check.call(String(lo.attack.id) == "scorch_and_burn" and String(lo.skill_1.id) == "cultivate" and lo.skill_2 == null and lo.spell_1 == null and lo.passive == null, "start loadout: Scorch and Burn, Cultivate on E; the rest empty")
	check.call(pc.equip("skill_2", PageLibrary.make("quick_step")) == "locked", "a page not yet unlocked cannot be equipped")
	for id in ["quick_step", "ring_of_fire", "sage_arts"]: s.meta.unlock(id) # as if solved (P5 unlocks are tested in test_grimoire)
	var ring: Resource = PageLibrary.make("ring_of_fire")
	var sage: Resource = PageLibrary.make("sage_arts")
	check.call(ring.mp_cost == 30.0 and ring.cooldown_s == 15.0 and ring.rank_req == "D" and ring.damage_pct == 0.15 and ring.duration_s == 10.0 and ring.mastery_applies and sage.rank_req == "D", "pages: Ring of Fire 30 MP, 15 s x Mastery, rank D, 15% Pow, 10 s; Sage Arts rank D [GDD]")
	check.call(pc.equip("spell_1", ring) == "rank" and pc.equip("passive", sage) == "rank" and lo.spell_1 == null, "rank E: Ring of Fire and Sage Arts cannot be equipped")
	check.call(pc.equip("spell_1", PageLibrary.make("cultivate")) == "wrong_kind" and pc.equip("skill_2", PageLibrary.make("quick_step")) == "ok" and pc.equip("skill_1", PageLibrary.make("quick_step")) == "duplicate" and pc.equip("slot_9", ring) == "unknown_slot", "equip refuses a wrong slot kind, the same page twice, an unknown slot")
	pc._default_loadout() # whatever a broken rule let through above, the rest starts from the start loadout
	lo = pc.loadout
	check.call(pc.equip("skill_2", s.grimoire.page("quick_step")) == "ok", "an unlocked Quick Step equips on Q")

	# ---- Cultivate -----------------------------------------------------------------------
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	tap(c, keys, KEY_E)
	var t0: float = s.run.time
	var st: RefCounted = s.stats
	check.call(is_equal_approx(st.value("magic_pow", t0), 110.0) and is_equal_approx(st.value("spell_mastery", t0), 0.20) and is_equal_approx(st.value("atk_spd", t0), 5.75) and absf(st.attack_interval(t0) - 1.0 / 5.75) < 1e-6, "E: Cultivate gives Pow 110, Mastery 20%%, Atk Spd 5.75 (basic every %.4f s)" % st.attack_interval(t0))
	check.call(absf(pc.remaining("skill_1", s.run.time) - 20.0) < 0.05 and pc.aura != null, "Cultivate's cooldown is 20 s")
	pc.publish()
	var glowing: bool = pc.aura.visible
	while s.run.time - t0 < 9.95: s.step(DT)
	var still_on: bool = is_equal_approx(st.value("magic_pow", s.run.time), 110.0)
	steps(c, 6)
	pc.publish()
	check.call(glowing and still_on and is_equal_approx(st.value("magic_pow", s.run.time), 100.0) and is_equal_approx(st.value("atk_spd", s.run.time), 5.0) and is_equal_approx(st.value("spell_mastery", s.run.time), 0.0) and not pc.aura.visible, "the buff (and its hand glow) lasts 10 s and ends exactly")
	tap(c, keys, KEY_E)
	check.call(pc.casts.get("cultivate", 0) == 1, "E on cooldown does nothing")
	# Skills ignore Spell Mastery: at 30% Mastery the cooldown is still 20 s.
	pc.ready_at.erase("skill_1")
	st.add_modifier("test_mastery", "spell_mastery", 1.0, 0.30, s.run.time + 60.0)
	tap(c, keys, KEY_E)
	check.call(absf(pc.remaining("skill_1", s.run.time) - 20.0) < 0.05, "a skill's cooldown ignores Spell Mastery (%.2f s at 50%%)" % pc.remaining("skill_1", s.run.time))
	# Re-casting refreshes the buff by id (no stacking).
	pc.ready_at.erase("skill_1")
	tap(c, keys, KEY_E)
	var n_cult := 0
	for m in st.modifiers: if m.id == "cultivate": n_cult += 1
	check.call(n_cult == 3 and is_equal_approx(st.value("magic_pow", s.run.time), 110.0), "re-cast Cultivate refreshes its 3 modifiers, no stacking (Pow %.0f)" % st.value("magic_pow", s.run.time))
	st.modifiers.clear()
	pc.ready_at.clear()

	# ---- Quick Step ----------------------------------------------------------------------
	for case in [["none", {}, 0.0], ["W+D", {KEY_W: true, KEY_D: true}, 45.0], ["S", {KEY_S: true}, 180.0], ["A", {KEY_A: true}, -90.0]]:
		place(c, Vector3(60, 0, 57), 0.0)
		await tree.physics_frame
		steps(c, 2)
		pc.ready_at.erase("skill_2")
		var a: Vector3 = p.global_position
		for k in case[1]: keys[k] = true
		keys[KEY_Q] = true; s.step(DT); keys.erase(KEY_Q)
		for k in case[1]: keys.erase(k)
		var d := flat(p.global_position - a)
		# The held keys also walk a tick or so: allow a few cm.
		var head := rad_to_deg(atan2(d.x, -d.y))
		check.call(absf(d.length() - 5.0) < 0.25 and absf(wrapf(head - float(case[2]), -180.0, 180.0)) < 2.0, "Quick Step (%s): %.2f m at %.0f deg (expected 5 m at %.0f)" % [case[0], d.length(), head, case[2]])
	steps(c, 2)
	var q0: int = pc.casts.get("quick_step", 0)
	tap(c, keys, KEY_Q)
	check.call(pc.casts.get("quick_step", 0) == q0 and absf(pc.remaining("skill_2", s.run.time) - (10.0 - 3.0 * DT)) < 0.05, "Quick Step's cooldown is 10 s (a press inside it does nothing)")
	# A wall 2 m ahead: it stops short, never inside the wall.
	place(c, Vector3(110, 0, 2.6), 0.0) # the north wall's face is about 2 m away
	await tree.physics_frame
	steps(c, 2)
	pc.ready_at.erase("skill_2")
	var b: Vector3 = p.global_position
	var moved: float = pc.quick_step(Vector2.ZERO)
	await tree.physics_frame
	var inside: bool = p.test_move(p.global_transform, Vector3.ZERO)
	check.call(moved < 2.2 and moved > 1.5 and p.global_position.z > 0.5 and not inside, "Quick Step into a wall 2 m away stops before it (%.2f m, z %.2f)" % [moved, p.global_position.z])
	pc.ready_at.clear()

	# ---- Ring of Fire (rank D) ---------------------------------------------------------
	s.progression.rank = "D"
	check.call(pc.equip("spell_1", ring) == "ok" and pc.equip("passive", sage) == "ok", "rank D: Ring of Fire and Sage Arts equip")
	pc.equip("passive", null) # Sage Arts would refill MP during the spell checks
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	steps(c, 2)
	pc.mp = 29.0
	tap(c, keys, KEY_1)
	check.call(c.projectiles.rings.is_empty() and is_equal_approx(pc.mp, 29.0) and pc.remaining("spell_1", s.run.time) == 0.0, "at 29 MP the spell does not cast (no MP spent, no cooldown)")
	pc.mp = 100.0
	tap(c, keys, KEY_1)
	var rg: Dictionary = c.projectiles.rings[0] if not c.projectiles.rings.is_empty() else {}
	var pos: Array = c.projectiles.orb_positions(rg, s.run.time) if not rg.is_empty() else []
	var even := pos.size() == 6
	var centre: Vector3 = p.global_position
	for i in pos.size():
		var off: Vector3 = pos[i] - centre
		if absf(flat(off).length() - 3.0) > 0.01 or absf(off.y - 1.0) > 0.01: even = false
		var nxt: Vector3 = pos[(i + 1) % 6] - centre
		if absf(rad_to_deg(flat(off).angle_to(flat(nxt))) - 60.0) > 0.5 and absf(rad_to_deg(flat(off).angle_to(flat(nxt))) + 60.0) > 0.5: even = false
	check.call(c.projectiles.rings.size() == 1 and even and is_equal_approx(pc.mp, 70.0) and is_equal_approx(float(Projectiles.ORBIT.orb_radius), float(Projectiles.KINDS.basic.radius)), "1: Ring of Fire spends 30 MP; 6 orbs 60 deg apart on a 3 m ring at chest height, each a basic fireball's size [R12]")
	var p0: Array = c.projectiles.orb_positions(rg, s.run.time)
	var p1: Array = c.projectiles.orb_positions(rg, s.run.time + DT)
	var orb_v: float = flat(p1[0] - p0[0]).length() / DT
	check.call(absf(orb_v - 20.0) < 0.1 and is_equal_approx(Projectiles.orbit_speed(), 2.0 * Projectiles.KINDS.basic.speed), "each orb moves at %.2f m/s along the ring: twice the fireball's 10 m/s [Sir]" % orb_v)
	keys[KEY_W] = true
	steps(c, 30)
	keys.erase(KEY_W)
	var c2: Vector3 = p.global_position
	var q: Array = c.projectiles.orb_positions(rg, s.run.time)
	check.call(flat(c2 - centre).length() > 2.0 and absf(flat((q[0] as Vector3) - c2).length() - 3.0) < 0.01, "the ring moves with the player")
	check.call(absf(pc.remaining("spell_1", s.run.time) - (15.0 - 31.0 * DT)) < 0.05, "Ring of Fire's cooldown is 15 s at 0%% Mastery (%.2f left)" % pc.remaining("spell_1", s.run.time))
	# An enemy on the ring's path is hit as the orbs sweep by, 15% of Pow per hit.
	foe.reset_to(p.global_position + Vector3(3.0, 0, 0), 0.0); foe.inert = true
	foe.health.max_hp = 1000.0 # tough enough to outlast 2 s of the ring
	foe.health.reset()
	await tree.physics_frame
	var fhp: float = foe.health.hp
	var h0: int = rg.hits.size()
	steps(c, 120) # 2 s
	var ring_hits: int = rg.hits.size() - h0
	check.call(ring_hits >= 11 and ring_hits <= 15 and is_equal_approx(fhp - foe.health.hp, 15.0 * ring_hits), "an enemy on the ring: %d hits of 15 in 2 s (6 orbs, about 1.06 turns/s)" % ring_hits)
	# Scorched Slow [R12]: a ring hit slows the enemy's movement by 90% for 2 s; re-hits refresh it, never stack.
	var slow_id: String = Projectiles.SCORCHED_SLOW.id
	var slowed: bool = c.effects.has(foe.enemy_id, slow_id, s.run.time) and is_equal_approx(foe.speed_mult, 0.1)
	var left0: float = c.effects.remaining(foe.enemy_id, slow_id, s.run.time)
	var n_eff: int = c.effects.active.get(foe.enemy_id, {}).keys().filter(func(k): return k == slow_id).size()
	check.call(slowed and left0 > 1.4 and left0 <= 2.0 + 1e-3 and n_eff == 1, "ring hits apply Scorched Slow: Mov Spd x0.1, refreshed to %.2f s of 2, one instance" % left0)
	foe.health.max_hp = foe.HP
	foe.health.reset()
	while not c.projectiles.rings.is_empty() and s.run.time < 30.0 + rg.start: s.step(DT)
	check.call(c.projectiles.rings.is_empty() and absf(s.run.time - rg.until) < 2.0 * DT, "the ring lasts 10 s")
	# Spell Mastery shortens a spell's cooldown: 20% -> 12 s.
	pc.ready_at.erase("spell_1")
	pc.mp = 100.0
	st.add_modifier("test_mastery", "spell_mastery", 1.0, 0.20, s.run.time + 60.0)
	tap(c, keys, KEY_1)
	check.call(absf(pc.remaining("spell_1", s.run.time) + DT - 12.0) < 0.05, "at 20%% Mastery the spell's cooldown is 12 s")
	st.modifiers.clear()
	c.projectiles.reset()
	# Re-hit rule at service level: a target touching all six orbs for 2 s takes
	# 4 hits per orb (one every 0.5 s), 24 in all.
	var ps: RefCounted = Projectiles.new()
	var big: Node = Health.new(); big.faction = "infected"; big.max_hp = 10000.0
	c.add_child(big)
	var tg := {"id": "big", "pos": Vector3(0, 1, 0), "radius": 3.1, "health": big}
	var rr: Dictionary = ps.summon_ring(func() -> Vector3: return Vector3.ZERO, 0.0, 10.0, 15.0)
	for i in 120: ps.tick(DT, i * DT, {"targets": [tg]})
	var per_orb := [0, 0, 0, 0, 0, 0]
	for h in rr.hits: per_orb[h.orb] += 1
	check.call(per_orb == [4, 4, 4, 4, 4, 4], "each orb re-hits the same enemy at most every 0.5 s (%s in 2 s) [S6]" % [per_orb])
	big.queue_free()

	# ---- Sage Arts (rank D) --------------------------------------------------------------
	pc.equip("passive", sage)
	place(c, Vector3(60, 0, 57), 0.0)
	await tree.physics_frame
	c.director.reset()
	p.health.hp = 50.0
	pc.mp = 40.0
	steps(c, 60)
	check.call(absf(p.health.hp - 53.0) < 0.1 and absf(pc.mp - 45.0) < 0.1, "Sage Arts out of combat: +3%% max HP and +5%% max MP per second (HP %.1f, MP %.1f) [S4]" % [p.health.hp, pc.mp])
	foe.reset_to(Vector3(60, 0, 50), 0.0); foe.inert = true
	foe.aggroed = true # an enemy has aggroed
	s.step(DT) # the tracker sees it at the end of the tick
	var hp_c: float = p.health.hp
	steps(c, 60)
	var flat_in_combat: bool = is_equal_approx(p.health.hp, hp_c)
	foe.aggroed = false # it drops
	var t_drop: float = s.run.time
	while s.run.time - t_drop < 2.8: s.step(DT)
	var flat_in_grace: bool = is_equal_approx(p.health.hp, hp_c)
	steps(c, 60)
	check.call(flat_in_combat and flat_in_grace and p.health.hp > hp_c + 2.0, "no regen in combat or the 3 s grace [R12], then it resumes")
	p.health.hp = 99.5
	pc.mp = 99.0
	steps(c, 60)
	check.call(is_equal_approx(p.health.hp, 100.0) and is_equal_approx(pc.mp, 100.0), "regen stops at the max")
	pc.equip("passive", null)
	p.health.hp = 50.0
	steps(c, 30)
	check.call(is_equal_approx(p.health.hp, 50.0), "no regen without Sage Arts equipped")

	# ---- Max HP stat, action bar, restart -------------------------------------------------
	st.add_modifier("test_hp", "max_hp", 1.0, 50.0, s.run.time + 60.0)
	s.step(DT)
	check.call(is_equal_approx(p.health.max_hp, 150.0), "the Max HP stat sizes the player's HP pool (%.0f)" % p.health.max_hp)
	st.modifiers.clear()
	s.step(DT)
	check.call(is_equal_approx(p.health.max_hp, 100.0) and p.health.hp <= 100.0, "and shrinks back (HP clamped)")
	var bar: String = pc.action_bar_text(s.run.time)
	check.call(bar.begins_with("[E] Cultivate") and bar.find("[Q] Quick Step") > 0 and bar.find("[1] Ring of Fire") > 0 and bar.find("[P] -") > 0, "action bar: E, Q, 1-3, P in order (%s)" % bar)
	s.progression.rank = "E"
	check.call(pc.use_slot("spell_1", Vector2.ZERO, s.run.time + 100.0) == "rank", "a rank-locked page cannot be used below its rank")
	s.restart()
	await tree.physics_frame
	check.call(pc.loadout.spell_1 == null and String(pc.loadout.skill_1.id) == "cultivate" and pc.ready_at.is_empty() and c.projectiles.rings.is_empty() and s.stats.modifiers.is_empty(), "restart: start loadout, no cooldowns, no ring, no buffs")

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.meta.reset()
	s.restart()
	await tree.physics_frame
