extends RefCounted
# Sir's R14 (handoff §10): the Effects tab on T (rows with icon, name,
# buff/debuff, live description and countdown; empty state; a hit closes it;
# also a tab in the Grimoire panel), the Burn visual on enemies (on and off
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
	var ep: CanvasLayer = c.effects_panel

	# ---- the Effects tab -------------------------------------------------------------------
	check.call(Settings.LAYOUT == 3 and "effects_tab" in Settings.ACTIONS and s.input.action_for_event(key(KEY_T)) == "effects_tab", "T is the rebindable Effects action (key layout 3) [R14]")
	s.handle_event(key(KEY_T))
	s.step(DT)
	check.call(ep.visible and s.input.context == InputRouter.Context.OVERLAY and ep.shown_text() == "No active effects." and ep.list.get_child(0).name == "Empty", "T opens the Effects tab: 'No active effects.' with none")
	s.handle_event(key(KEY_T))
	check.call(not ep.visible and s.input.context == InputRouter.Context.GAMEPLAY, "T again closes it")
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, s.run.time) # Cultivate, 10 s
	c.concuss(s.run.time + 1.5, 0.2)
	s.handle_event(key(KEY_T))
	s.step(DT)
	var rows: Array = ep.rows
	var cult: Dictionary = rows.filter(func(r): return r.id == "Cultivate")[0] if rows.any(func(r): return r.id == "Cultivate") else {}
	var conc: Dictionary = rows.filter(func(r): return r.id == "Concuss")[0] if rows.any(func(r): return r.id == "Concuss") else {}
	check.call(not cult.is_empty() and cult.kind == "buff" and cult.text == "+10% Magic Pow, +20% Spell Mastery, +15% Atk Spd." and cult.name == "Cultivate", "a Cultivate row: buff, '%s'" % cult.get("text", "?"))
	check.call(not conc.is_empty() and conc.kind == "debuff" and conc.text.begins_with("Mov Spd and Atk Spd -80%") and ep.list.get_child_count() == rows.size(), "a Concussed row: debuff, '%s'; one line per effect, each with its icon" % conc.get("text", "?"))
	var t0: float = cult.s
	var shown0: String = (ep.list.get_child(rows.find(cult)).get_node("Time") as Label).text
	steps(c, 1.6) # past Concuss's 1.5 s
	var cult2: Dictionary = ep.rows.filter(func(r): return r.id == "Cultivate")[0]
	var shown1: String = (ep.list.get_child(ep.rows.find(cult2)).get_node("Time") as Label).text
	check.call(absf(t0 - cult2.s - 1.6) < 0.05 and shown0 != shown1 and shown1.ends_with(" s") and not ep.rows.any(func(r): return r.id == "Concuss"), "the times count down live (%s -> %s); Concuss gone when it ends" % [shown0, shown1])
	# A hit closes it (the overlay rule).
	p.health.apply(DamagePacket.new(94001, "test", "infected", 3.0, "bite"), s.run.time)
	check.call(not ep.visible and s.input.context == InputRouter.Context.GAMEPLAY, "a hit closes the Effects tab")
	# Burn on the player: a debuff row with its damage per second.
	c.effects.apply("player", "Burn", 5.0, s.run.time, "test", 150.0)
	var burn_rows: Array = c.effect_rows(s.run.time).filter(func(r): return r.id == "Burn")
	check.call(burn_rows.size() == 1 and burn_rows[0].kind == "debuff" and burn_rows[0].text.begins_with("Takes 3 fire damage every second"), "a Burn row with live numbers: '%s'" % (burn_rows[0].text if burn_rows.size() else "?"))
	c.effects.clear_target("player")
	# Effects live on T only [Sir]: the Tab panel has no Effects view.
	var gp: CanvasLayer = c.grimoire_panel
	s.handle_action("grimoire")
	gp.show_tab("effects")
	check.call(gp.tab == "grimoire" and gp.VIEWS == ["grimoire", "player_id"], "the Tab panel has only the Grimoire and the Player ID; Effects is T's own")
	s.handle_action("grimoire")
	# The T panel draws each icon at a fixed 48 px tile (it once drew the file's 128 px).
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, s.run.time)
	s.handle_event(key(KEY_T))
	s.step(DT)
	var tile: Control = ep.list.find_child("Tile", true, false)
	var ic: TextureRect = tile.find_child("Icon", true, false) if tile else null
	check.call(tile != null and tile.custom_minimum_size == Vector2(48, 48) and ic != null and ic.expand_mode == TextureRect.EXPAND_IGNORE_SIZE and ic.custom_minimum_size.x <= 48.0, "the T panel's icons sit in fixed 48 px tiles")
	s.handle_event(key(KEY_T))

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
