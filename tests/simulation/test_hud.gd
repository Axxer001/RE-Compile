extends RefCounted
# P7 HUD (handoff §7): Lvl | Rank, HP and MP bars (cur/max), the mission
# tracker, the action bar (E Q 1 2 3 P: icon, cooldown sweep and seconds,
# greyed for rank or MP, empty when unequipped), the special cooldown ring and
# the notifications (refused presses, stacking, refresh, cap).

const DT := 1.0 / 60.0

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var hud: CanvasLayer = c.hud
	var pc: Node3D = c.pcombat
	var h: Node = c.player.health
	s.step(DT)
	check.call(hud.status.text == "Lvl 1 | Rank E" and hud.mission.text.begins_with("Mission: Defeat 20 enemies (0/20)"), "HUD: 'Lvl 1 | Rank E' top-left, the mission with progress top-right (%s)" % hud.mission.text.replace("\n", " "))
	h.hp = 40.0
	pc.mp = 30.0
	s.step(DT)
	check.call(absf(hud.hp_bar.frac - 0.4) < 0.01 and hud.hp_bar.label.text == "HP 40/100" and absf(hud.mp_bar.frac - 0.3) < 0.02 and hud.mp_bar.label.text.begins_with("MP 30/100"), "HP and MP bars: fill = cur/max, text cur/max (%s, %s)" % [hud.hp_bar.label.text, hud.mp_bar.label.text])
	h.reset()
	# Action bar: Cultivate in E (ready), Q and 1-3 empty, P empty.
	check.call(hud.slot_state("skill_1") == "ready" and hud.slots.skill_1.initial.text == "C" and hud.slot_state("skill_2") == "empty" and hud.slot_state("spell_1") == "empty" and hud.slot_state("passive") == "empty", "action bar: Cultivate ready in [E] (icon 'C'), the rest empty")
	var first: String = pc.use_slot("skill_1", Vector2.ZERO, s.run.time)
	s.step(DT)
	var sw: Dictionary = hud.slots.skill_1
	check.call(first == "ok" and hud.slot_state("skill_1") == "cooldown" and sw.sweep.size.y > sw.icon.size.y * 0.95 and sw.secs.text == "20", "used: the cooldown sweep covers the icon and counts the seconds (%s)" % sw.secs.text)
	for i in 600: s.step(DT) # 10 s of the 20 s cooldown
	check.call(absf(sw.cd - 0.5) < 0.02 and sw.secs.text == "10", "half way: the sweep is half (%.2f), 10 s left" % sw.cd)
	# A refused press is announced.
	pc._notify(pc.use_slot("skill_1", Vector2.ZERO, s.run.time), "skill_1")
	check.call(c.notice == "Cultivate is on cooldown", "a press on cooldown: 'Cultivate is on cooldown'")
	# Rank-locked and MP-short slots are greyed.
	pc.loadout.spell_1 = s.grimoire.page("ring_of_fire")
	s.step(DT)
	check.call(hud.slot_state("spell_1") == "locked" and hud.slots.spell_1.secs.text == "RD" and hud.slots.spell_1.root.modulate.r < 0.6, "a rank-D page at rank E: greyed, marked RD")
	pc._notify(pc.use_slot("spell_1", Vector2.ZERO, s.run.time), "spell_1")
	check.call(c.notice == "Ring of Fire needs rank D", "a press below the rank: 'Ring of Fire needs rank D'")
	s.progression.rank = "D"
	pc.mp = 10.0
	s.step(DT)
	check.call(hud.slot_state("spell_1") == "mp" and hud.slots.spell_1.root.modulate.r < 0.6, "too little MP for a 30 MP spell: greyed")
	pc._notify(pc.use_slot("spell_1", Vector2.ZERO, s.run.time), "spell_1")
	check.call(c.notice == "Not enough MP", "a press without the MP: 'Not enough MP'")
	pc.mp = 100.0
	s.step(DT)
	check.call(hud.slot_state("spell_1") == "ready" and hud.slots.spell_1.root.modulate.r > 0.95, "rank D and the MP: ready, full colour")
	# Notifications stack (newest last), refresh in place, cap at 4 and expire.
	var n0: int = c.notices.size()
	c.show_notice("Not enough MP", 1.0)
	var refreshed: bool = c.notices.size() == n0
	for t in ["a", "b", "c", "d", "e"]: c.show_notice(t, 1.0)
	s.step(DT)
	check.call(refreshed and c.notices.size() == 4 and hud.notice_box.get_child_count() == 4 and (hud.notice_box.get_child(3) as Label).text == "e", "notifications: the same text refreshes, at most 4 shown, newest last")
	for i in 70: s.step(DT)
	check.call(c.notices.is_empty() and hud.notice_box.get_child_count() == 0, "notifications expire on their timers")
	# [R12] No crosshair ring: the basic and special attacks are smaller tiles at the bar's two ends.
	var ab: Control = hud.find_child("ActionBar", true, false)
	var order := []
	for ch in ab.get_children(): order.append((ch.get_child(ch.get_child_count() - 1) as Label).text)
	check.call(hud.find_child("SpecialRing", true, false) == null and order == ["LMB", "E", "Q", "1", "2", "3", "P", "RMB"] and hud.slots.basic.root.custom_minimum_size.x < hud.slots.skill_1.root.custom_minimum_size.x and hud.slots.special.root.custom_minimum_size.x < hud.slots.skill_1.root.custom_minimum_size.x, "action bar %s: LMB and RMB smaller at the ends; no crosshair ring" % str(order))
	pc.cast_special(s.run.time)
	s.step(DT)
	var full: float = hud.slots.special.cd
	for i in 180: s.step(DT)
	var later: float = hud.slots.special.cd
	pc.special_ready = s.run.time
	s.step(DT)
	check.call(full > 0.9 and later < full and later > 0.0 and hud.slot_state("special") == "ready" and hud.slots.special.cd == 0.0, "the RMB tile shows the special's cooldown: full after the cast (%.2f), drains (%.2f), clear when ready" % [full, later])
	c.player.health.reset()
	var keys := {MOUSE_BUTTON_LEFT: true}
	var saved_m: Callable = s.input.mouse_source
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	s.step(DT)
	s.input.mouse_source = saved_m
	s.step(DT)
	check.call(hud.slot_state("basic") == "cooldown" and hud.slots.basic.cd > 0.5, "the LMB tile shows the basic attack's interval after a cast (%.2f)" % hud.slots.basic.cd)
	s.meta.reset()
	s.restart()
	await tree.physics_frame
