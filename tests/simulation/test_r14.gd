extends RefCounted
# Sir's R14 (handoff §10): the player's effects (rows with name, buff/debuff,
# live description and countdown; empty state), shown on the held book's status
# page since the T overlay was removed [Sir, 2026-11-21], the Burn visual on enemies (on and off
# with the effect, small and faint), and floating damage numbers (one per
# applied hit, none for duplicates, orange Burn ticks that merge, larger for
# the special, the settings toggle, the pool cap of 40).

const DT := 1.0 / 60.0
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")
const Settings = preload("res://scripts/core/settings.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k; e.keycode = k; e.pressed = true
	return e

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"])
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	sh.reset_to(Vector3(60, 0, 50), 0.0)
	sh.inert = true
	var p: CharacterBody3D = c.player
	var pc: Node3D = c.pcombat

	# ---- the player's effects: on the held book's status page (page 5); T removed [Sir, 2026-11-21]
	check.call(not "effects_tab" in Settings.ACTIONS and not InputMap.has_action("effects_tab") and s.input.action_for_event(key(KEY_T)) == "", "T is unassigned: no Effects overlay (the held book's page 5 shows the effects)")
	s.handle_event(key(KEY_T))
	s.step(DT)
	check.call(s.input.context == InputRouter.Context.GAMEPLAY and c.find_child("EffectsPanel", true, false) == null, "pressing T does nothing")
	check.call(c.effect_rows(s.run.time).is_empty() and pc.rig.status_info().effects.is_empty(), "no effects: page 5 lists none")
	pc.ready_at.erase("spell_2")
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time) # Cultivate, 10 s
	c.concuss(s.run.time + 1.5, 0.2)
	var rows: Array = pc.rig.status_info().effects
	var cult: Dictionary = rows.filter(func(r): return r.id == "Cultivate")[0] if rows.any(func(r): return r.id == "Cultivate") else {}
	var conc: Dictionary = rows.filter(func(r): return r.id == "Concuss")[0] if rows.any(func(r): return r.id == "Concuss") else {}
	check.call(not cult.is_empty() and cult.kind == "buff" and cult.text == "+10% Magic Pow, +20% Spell Mastery, +15% Atk Spd." and cult.name == "Cultivate", "page 5: a Cultivate row, buff, '%s'" % cult.get("text", "?"))
	check.call(not conc.is_empty() and conc.kind == "debuff" and conc.text.begins_with("Mov Spd and Atk Spd -80%"), "page 5: a Concussed row, debuff, '%s'" % conc.get("text", "?"))
	var t0: float = cult.s
	steps(c, 1.6) # past Concuss's 1.5 s
	var rows2: Array = pc.rig.status_info().effects
	var cult2: Dictionary = rows2.filter(func(r): return r.id == "Cultivate")[0]
	check.call(absf(t0 - cult2.s - 1.6) < 0.05 and not rows2.any(func(r): return r.id == "Concuss"), "page 5's times count down live; Concuss gone when it ends")
	# Burn on the player: a debuff row with its damage per second.
	c.effects.apply("player", "Burn", 5.0, s.run.time, "test", 150.0)
	var burn_rows: Array = c.effect_rows(s.run.time).filter(func(r): return r.id == "Burn")
	check.call(burn_rows.size() == 1 and burn_rows[0].kind == "debuff" and burn_rows[0].text.begins_with("Takes 3 fire damage every second"), "a Burn row with live numbers: '%s'" % (burn_rows[0].text if burn_rows.size() else "?"))
	c.effects.clear_target("player")
	var gp: CanvasLayer = c.grimoire_panel
	s.handle_action("grimoire")
	gp.show_tab("effects")
	check.call(gp.tab == "grimoire" and gp.VIEWS == ["grimoire", "player_id"], "the Tab panel has only the Grimoire and the Player ID")
	s.handle_action("grimoire")

	# ---- Burn visual on enemies --------------------------------------------------------------
	c.publish(DT)
	var off0: bool = not sh.burning
	c.effects.apply(sh.enemy_id, "Burn", 0.5, s.run.time, "player", 100.0)
	c.publish(DT)
	var flames: int = sh.embers.find_children("*", "GPUParticles3D", true, false).filter(func(g): return g.emitting).size() if sh.embers else 0
	var on: bool = sh.burning and sh.embers != null and sh.embers.visible and flames >= 1 and sh._skin.emission_energy_multiplier <= 0.3 + 1e-6
	steps(c, 0.6)
	var quiet: bool = not sh.embers.visible and sh.embers.find_children("*", "GPUParticles3D", true, false).all(func(g): return not g.emitting)
	check.call(off0 and on and not sh.burning and quiet and is_equal_approx(sh._skin.emission_energy_multiplier, sh._skin_energy), "Burn on an enemy: Binbun flames on the body and a faint glow (<= 30%), gone the moment Burn ends [R14, Phase 2]")
	# Only the nearest burning Sprites wear the flames; the rest glow and flicker [perf, 2026-11-14].
	var keep_full: int = c.vfx.embers_full
	c.vfx.embers_full = 1
	var sh2: CharacterBody3D = c.enemies["sprite_2"] # a second, farther Sprite (parked ones are hidden)
	sh2.visible = true
	sh2.reset_to(sh.global_position + Vector3(0, 0, 12), 0.0)
	var all_ids: Array = ["sprite_1", "sprite_2"]
	for id in all_ids: c.effects.apply(id, "Burn", 5.0, s.run.time, "player", 100.0)
	c.publish(DT)
	var eye: Vector3 = c.get_viewport().get_camera_3d().global_position
	var by_near: Array = all_ids.map(func(id): return c.enemies[id])
	by_near.sort_custom(func(a, b): return eye.distance_squared_to(a.global_position) < eye.distance_squared_to(b.global_position))
	var full_n: int = by_near.filter(func(e): return e.burn_full and e.embers != null and e.embers.visible).size()
	var rest_ok: bool = by_near.slice(1).all(func(e): return e.burning and not e.burn_full and (e.embers == null or not e.embers.visible) and e._skin.emission_energy_multiplier > 0.0 and e._skin.emission_energy_multiplier <= 0.3 + 1e-6)
	check.call(by_near.size() >= 2 and full_n == 1 and by_near[0].burn_full and rest_ok, "of %d burning Sprites only the nearest wears the flames; the rest glow (<= 30%%), flickering" % by_near.size())
	for id in all_ids: c.effects.clear_target(id)
	c.publish(DT)
	check.call(by_near.all(func(e): return not e.burning and is_equal_approx(e._skin.emission_energy_multiplier, e._skin_energy)), "Burn's end puts every Sprite's glow back")
	c.vfx.embers_full = keep_full
	sh2.visible = false

	# ---- damage numbers --------------------------------------------------------------------------
	var dn: Node3D = c.damage_numbers
	dn.clear()
	sh.health.max_hp = 100000.0
	sh.health.reset()
	var n0: int = dn.spawned
	for i in 3: sh.health.apply(DamagePacket.new(93001 + i, "player", "player", 10.0, "blast"), s.run.time)
	sh.health.apply(DamagePacket.new(93001, "player", "player", 10.0, "blast"), s.run.time) # a duplicate
	var direct: Dictionary = dn._live.back()
	check.call(dn.spawned == n0 + 3 and dn.live_count() == 3 and direct.kind == "direct" and direct.label.modulate.is_equal_approx(Color(1, 1, 1)) and direct.label.text == "10", "one white number per applied hit, none for a refused duplicate")
	c.projectiles.detonating = "special"
	sh.health.apply(DamagePacket.new(93010, "player", "player", 50.0, "blast"), s.run.time)
	c.projectiles.detonating = ""
	var big: Dictionary = dn._live.back()
	check.call(big.kind == "special" and big.label.font_size > direct.label.font_size, "the special's blast: a larger number")
	dn.clear()
	c.effects.apply(sh.enemy_id, "Burn", 3.0, s.run.time, "player", 100.0)
	steps(c, 1.05) # the first tick lands
	var burn_n: Array = dn._live.filter(func(n): return n.kind == "burn")
	check.call(burn_n.size() == 1 and burn_n[0].label.modulate.r > 0.9 and burn_n[0].label.modulate.b < 0.4 and burn_n[0].label.text == "2", "a Burn tick: an orange number (%s)" % (burn_n[0].label.text if burn_n.size() else "-"))
	c.effects.clear_target(sh.enemy_id)
	dn.clear()
	dn.spawn(Vector3(60, 2, 50), 2.0, "burn", "sprite_1")
	dn.spawn(Vector3(60, 2, 50), 2.0, "burn", "sprite_1")
	var merged: int = dn.live_count()
	dn.tick(0.3)
	dn.spawn(Vector3(60, 2, 50), 2.0, "burn", "sprite_1")
	check.call(merged == 1 and dn._live[0].label.text == "4" and dn.live_count() == 2, "Burn ticks on one enemy within 0.25 s merge into one number")
	# Rise and fade over 0.8 s.
	dn.clear()
	dn.spawn(Vector3(60, 2, 50), 5.0, "direct", "sprite_1")
	var lbl: Label3D = dn._live[0].label
	dn.tick(0.4)
	var mid_y: float = lbl.position.y
	dn.tick(0.45)
	check.call(absf(mid_y - 2.4) < 0.02 and dn.live_count() == 0 and not lbl.visible, "a number rises (0.4 m at half-life) and is gone after 0.8 s")
	# The cap and the toggle.
	for i in 60: dn.spawn(Vector3(60, 2, 50), 1.0 + i, "direct", "sprite_%d" % i)
	check.call(dn.live_count() == 40 and dn._labels.size() == 40, "at most 40 numbers on screen (pooled)")
	dn.clear()
	s.settings.set_value("damage_numbers", false)
	var n1: int = dn.spawned
	sh.health.apply(DamagePacket.new(93020, "player", "player", 10.0, "blast"), s.run.time)
	check.call(dn.spawned == n1 and dn.live_count() == 0 and not dn.enabled, "the 'Damage numbers' toggle off: none spawn")
	s.settings.set_value("damage_numbers", true)
	var tmp := "user://r14_settings_test.cfg"
	var st := Settings.new()
	st.set_value("damage_numbers", false)
	st.save(tmp)
	var st2 := Settings.new()
	st2.load_from(tmp)
	check.call(not st2.damage_numbers and Settings.new().damage_numbers, "the toggle is saved in settings.cfg (default on)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	sh.health.max_hp = sh.HP
	dn.clear()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
