extends RefCounted
# The Phoenix set [Sir, 2026-11-14; docs/plan-phoenix-spells.md]: Flight (pull and
# Concuss, the climb curve and timers, invalid picks, auto-crash, knockback, no
# fall damage, gating), Call (marks, early finish, spend with no marks, 30
# fireballs per area), Rise (burning-kill heal, arming at 20, the rebirth).

const DT := 1.0 / 60.0
const SS = preload("res://scripts/combat/spell_service.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put(c: Node3D, id: String, at: Vector3) -> CharacterBody3D:
	var e: CharacterBody3D = c.enemies[id]
	e.reset_to(at, 0.0)
	e.inert = true
	e.health.max_hp = 1.0e6
	e.health.reset()
	return e

static func logs(c: Node3D, tag: String) -> Array:
	return c.spells.log.filter(func(h): return h.get("spell", "") == tag)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var pc: Node3D = c.pcombat
	var p: CharacterBody3D = c.player
	var ids: Array = c.enemies.keys()
	var home := Vector3(60, 0, 50)
	var reset_player := func() -> void:
		p.global_position = home
		p.velocity = Vector3.ZERO
		p.yaw = deg_to_rad(-90.0)
		p.pitch = 0.0
		p.apply_look()
	reset_player.call()
	steps(c, 0.2)
	var pages := ["flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix"]
	check.call(pages.all(func(id): return s.grimoire.is_unlocked(id)) and s.grimoire.page("rise_of_the_phoenix").kind == 3, "the Phoenix pages are unlocked from the start; Rise is a passive")

	# ---- Flight of the Phoenix ---------------------------------------------------------------------
	var fl: Resource = s.grimoire.page("flight_of_the_phoenix")
	pc.equip("spell_1", fl)
	p.global_position = home + Vector3(0, 3, 0) # in the air
	p.velocity = Vector3.ZERO
	steps(c, 2.0 * DT) # the controller notices it has left the floor
	var mp_air: float = pc.mp
	var r_air: String = pc.use_slot("spell_1", Vector2.ZERO, s.run.time)
	check.call(r_air == "airborne" and is_equal_approx(pc.mp, mp_air) and pc.remaining("spell_1", s.run.time) == 0.0, "Flight cannot be cast in the air: refused, nothing spent")
	reset_player.call()
	steps(c, 0.5)
	var near_a := put(c, ids[0], home + Vector3(12, 0, 0))
	var near_b := put(c, ids[1], home + Vector3(-8, 0, 10))
	var far := put(c, ids[2], home + Vector3(0, 0, 25))
	var far_at := far.global_position
	await tree.physics_frame
	var hp_a: float = near_a.health.hp
	var mp0: float = pc.mp
	var r: String = pc.use_slot("spell_1", Vector2.ZERO, s.run.time)
	var cast_at: Vector3 = c.spells.flight.cast_at
	var pulled: bool = near_a.global_position.distance_to(cast_at) < 2.5 and near_b.global_position.distance_to(cast_at) < 2.5 and far.global_position.distance_to(far_at) < 0.01
	var concussed: bool = c.effects.has(near_a.enemy_id, SS.CONCUSS_ID, s.run.time) and not c.effects.has(far.enemy_id, SS.CONCUSS_ID, s.run.time)
	check.call(r == "ok" and is_equal_approx(pc.mp, mp0 - 80.0) and pulled and concussed and is_equal_approx(near_a.health.hp, hp_a) and c.spells.flight.has("ring"), "Flight: 80 MP; enemies within 20 m are pulled to the cast spot unhurt and Concussed; the one at 25 m stays; the 50 m landing ring shows")
	var cd: float = pc.remaining("spell_1", s.run.time)
	check.call(absf(cd - s.stats.cooldown(60.0, true, s.run.time)) < 0.05, "a 1 min cooldown (x Spell Mastery): %.1f s" % cd)
	steps(c, 0.1)
	check.call(is_equal_approx(near_a.atk_mult, 0.2) and near_a.speed_mult <= 0.2 + 1e-6, "Concussed: -80% move and attack speed")
	steps(c, 2.4)
	var y_climb: float = p.global_position.y - cast_at.y
	var hit_r: String = p.health.apply(DamagePacket.new(980001, "sprite_x", "infected", 50.0, "bite"), s.run.time)
	var gated: bool = pc.use_slot("skill_1", Vector2.ZERO, s.run.time) == "busy" and not pc.can_cast() and not pc.sage_active(s.run.time)
	check.call(absf(y_climb - 30.0 * 0.75) < 1.0 and hit_r == "immune" and gated, "climbing: %.1f m up at 2.5 s (of 30 m over 5 s); invulnerable; no other attack, skill or passive" % y_climb)
	check.call(is_equal_approx(SS.flight_mult(1.0), 1.0) and is_equal_approx(SS.flight_mult(2.0), 1.0) and is_equal_approx(SS.flight_mult(3.5), 3.0) and is_equal_approx(SS.flight_mult(5.0), 5.0) and is_equal_approx(SS.flight_mult(8.0), 5.0), "damage curve: 100% to 2 s, then linear to 500% at 5 s")
	# A spot in the sky is refused.
	p.pitch = deg_to_rad(60.0)
	p.apply_look()
	var rejects0: int = logs(c, "flight_reject").size()
	c.spells.on_input(false, s.run.time)
	c.spells.on_input(true, s.run.time)
	check.call(logs(c, "flight_reject").size() == rejects0 + 1 and c.spells.flight_phase() == "climb", "aiming at the sky: the pick is refused and the climb goes on")
	# Pick straight below at 3.5 s: 300%.
	steps(c, 1.0 - DT)
	p.pitch = deg_to_rad(-89.0)
	p.apply_look()
	c.spells.on_input(false, s.run.time)
	var ok_pick: bool = c.spells.pick_flight_spot(s.run.time)
	var mult: float = c.spells.flight.mult
	var landing: Vector3 = c.spells.flight.chosen
	check.call(ok_pick and c.spells.flight_phase() == "crash" and absf(mult - SS.flight_mult(3.5)) < 0.05, "picking the ground below at 3.5 s: the dive locks %.0f%% damage" % (mult * 100.0))
	var pow: float = pc._pow(s.run.time)
	steps(c, 3.2)
	var imp: Array = logs(c, "flight").filter(func(h): return h.id == near_a.enemy_id)
	var knocked: bool = Vector2(near_a.global_position.x - cast_at.x, near_a.global_position.z - cast_at.z).length() > 19.0
	check.call(not imp.is_empty() and absf(imp[0].amount - pow * mult) < 0.5 and c.effects.has(near_a.enemy_id, "Burn", s.run.time) and knocked, "impact: %.0f damage (Magic Pow x %.1f), Burn, knocked back to 20 m" % [imp[0].amount if not imp.is_empty() else 0.0, mult])
	check.call(c.spells.flight.is_empty() and not p.health.dead and p.global_position.distance_to(landing) < 0.6 and pc.can_cast(), "the player lands at the spot unhurt (no fall damage) and is free again %s" % str([c.spells.flight.is_empty(), p.health.dead, p.global_position, landing, pc.can_cast()]))
	# No pick at all: the dive goes back to the cast spot at 500% when the hover ends.
	c.spells.reset()
	c.park_enemies()
	reset_player.call()
	steps(c, 0.3)
	pc.ready_at.erase("spell_1")
	pc.mp = pc.max_mp(s.run.time)
	pc.use_slot("spell_1", Vector2.ZERO, s.run.time)
	var spot0: Vector3 = c.spells.flight.cast_at
	steps(c, 5.2)
	var hovering: bool = c.spells.flight_phase() == "window" and absf(p.global_position.y - spot0.y - 30.0) < 0.2
	steps(c, 5.0)
	var auto_dive: bool = c.spells.flight_phase() == "crash" and is_equal_approx(c.spells.flight.mult, 5.0) and (c.spells.flight.chosen as Vector3).distance_to(spot0) < 0.01
	steps(c, 3.2)
	check.call(hovering and auto_dive and c.spells.flight.is_empty() and p.global_position.distance_to(spot0) < 0.5, "no pick: hover 5 s at 30 m, then auto-crash to the cast spot at 500%")

	# ---- Call of the Phoenix -----------------------------------------------------------------------
	c.spells.reset()
	c.park_enemies()
	reset_player.call()
	steps(c, 0.3)
	var cl: Resource = s.grimoire.page("call_of_the_phoenix")
	pc.equip("spell_2", cl)
	pc.mp = pc.max_mp(s.run.time)
	var mp1: float = pc.mp
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	var keys := {KEY_W: true}
	var saved: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	steps(c, 2.0)
	s.input.key_source = saved
	var held: bool = p.global_position.distance_to(home) < 0.05 and c.spells.busy() == "call"
	steps(c, 3.2)
	check.call(held and c.spells.calling.is_empty() and c.spells.rain.is_empty() and is_equal_approx(pc.mp, mp1 - 50.0) and pc.remaining("spell_2", s.run.time) > 0.0, "Call: held in place for 5 s; with no marks it ends without rain, MP and cooldown still spent")
	pc.ready_at.erase("spell_2")
	pc.mp = pc.max_mp(s.run.time)
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	p.pitch = deg_to_rad(60.0)
	p.apply_look()
	var bad_mark: bool = not c.spells.mark_call_area(s.run.time)
	p.pitch = deg_to_rad(-35.0)
	p.apply_look()
	var target := put(c, ids[3], Vector3.ZERO)
	var aim_pt: Vector3 = c.spells._aim_ground(30.0).point
	target.reset_to(aim_pt, 0.0)
	target.inert = true
	for i in 2: c.spells.mark_call_area(s.run.time)
	var still_casting: bool = not c.spells.calling.is_empty()
	c.spells.mark_call_area(s.run.time)
	check.call(bad_mark and still_casting and c.spells.calling.is_empty() and c.spells.rain.size() == 3, "the sky cannot be marked; the third area ends the cast at once and the rain begins")
	var hp_t: float = target.health.hp
	steps(c, 5.0 + 2.0)
	check.call(logs(c, "call_drop").size() == 90 and c.spells.rain.is_empty() and target.health.hp < hp_t and c.effects.has(target.enemy_id, "Burn", s.run.time), "3 areas x 30 fireballs fell over 5 s (%d), the enemy in them is hit and burning" % logs(c, "call_drop").size())
	check.call(c.projectiles.shots.size() < c.projectiles.POOL, "the rain never fills the 64-fireball pool")

	# ---- Rise of the Phoenix -----------------------------------------------------------------------
	c.spells.reset()
	c.park_enemies()
	reset_player.call()
	steps(c, 0.3)
	var rise: Resource = s.grimoire.page("rise_of_the_phoenix")
	pc.equip("passive", rise)
	var h: Node = p.health
	h.hp = h.max_hp * 0.5
	pc.mp = pc.max_mp(s.run.time) * 0.5
	pc.rise_kills = 18
	var e1 := put(c, ids[4], home + Vector3(5, 0, 0))
	e1.health.max_hp = 10.0
	e1.health.reset()
	c.effects.apply(e1.enemy_id, "Burn", 5.0, s.run.time, "player", 100.0)
	e1.health.apply(DamagePacket.new(980010, "player", "player", 100.0, "blast"), s.run.time)
	var healed: bool = absf(h.hp - h.max_hp * 0.52) < 0.01 and absf(pc.mp - pc.max_mp(s.run.time) * 0.52) < 0.01
	var e2 := put(c, ids[5], home + Vector3(6, 0, 0))
	e2.health.max_hp = 10.0
	e2.health.reset()
	var hp_before: float = h.hp
	e2.health.apply(DamagePacket.new(980011, "player", "player", 100.0, "blast"), s.run.time)
	check.call(healed and is_equal_approx(h.hp, hp_before) and pc.rise_kills == 20 and pc.rise_armed(), "a burning kill: +2% max HP and MP; a kill without Burn heals nothing; 20 kills: armed")
	var row: Array = c.effect_rows(s.run.time).filter(func(x): return x.id == "Rise of the Phoenix")
	check.call(not row.is_empty() and row[0].until_text == "Rise Armed", "the Effects tab shows Rise: Armed")
	var foe := put(c, ids[6], home + Vector3(8, 0, 0))
	var mp_before: float = pc.mp
	var res: String = h.apply(DamagePacket.new(980012, "sprite_x", "infected", 1.0e6, "bite"), s.run.time)
	var revived: bool = res == "revived" and not h.dead and is_equal_approx(h.hp, h.max_hp) and is_equal_approx(pc.mp, mp_before) and pc.rise_kills == 0 and not c.death_panel.visible
	var again: String = h.apply(DamagePacket.new(980013, "sprite_x", "infected", 10.0, "bite"), s.run.time)
	var blasted: Array = logs(c, "rise").filter(func(x): return x.id == foe.enemy_id)
	check.call(revived and again == "immune" and not blasted.is_empty() and Vector2(foe.global_position.x - home.x, foe.global_position.z - home.z).length() > 19.0, "armed, a lethal hit becomes a rebirth: full HP (MP unchanged), 2 s invulnerable, a 200% blast that knocks enemies to 20 m; the count restarts")
	var row2: Array = c.effect_rows(s.run.time).filter(func(x): return x.id == "Rise of the Phoenix")
	check.call(not row2.is_empty() and row2[0].until_text == "Rise 0/20", "after the rebirth the Effects tab shows Rise 0/20")
	steps(c, 2.2)
	var dead_res: String = h.apply(DamagePacket.new(980014, "sprite_x", "infected", 1.0e6, "bite"), s.run.time)
	check.call(dead_res == "lethal" and h.dead, "not armed, a lethal hit kills as before")
	c.spells.reset()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
