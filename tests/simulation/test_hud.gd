extends RefCounted
# P7 HUD (handoff §7): Lvl | Rank, HP and MP bars (cur/max), the mission
# tracker, no action bar (the held grimoire's pages show each slot's state,
# cooldown and ready since 2026-11-20) and the notifications (refused presses,
# stacking, refresh, cap).

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
	h.hp = 400.0
	pc.mp = 30.0
	s.step(DT)
	check.call(absf(hud.hp_bar.frac - 0.4) < 0.01 and hud.hp_bar.label.text == "HP 400/1000" and absf(hud.mp_bar.frac - 0.3) < 0.02 and hud.mp_bar.label.text.begins_with("MP 30/100"), "HP and MP bars: fill = cur/max, text cur/max (%s, %s)" % [hud.hp_bar.label.text, hud.mp_bar.label.text])
	h.reset()
	# No action bar [Sir, 2026-11-20]: the held grimoire's pages show each slot's
	# page, cooldown and ready state (rig.page_info feeds the page ink).
	var rig: Node3D = pc.rig
	var p2: Dictionary = rig.page_info(1)
	check.call(hud.find_child("ActionBar", true, false) == null and p2.title == "Cultivate" and p2.state == "ready" and rig.page_info(2).get("empty", false) and rig.page_info(3).get("empty", false), "no HUD loadout bar; the book's page 2 shows Cultivate ready, pages 3-4 empty")
	var first: String = pc.use_slot("spell_2", Vector2.ZERO, s.run.time)
	s.step(DT)
	p2 = rig.page_info(1)
	check.call(first == "ok" and p2.state == "cooldown" and p2.frac > 0.95 and absf(float(p2.left) - 20.0) < 0.1, "used: the page shows the cooldown (ring %.2f, %.1f s left)" % [p2.frac, p2.left])
	for i in 600: s.step(DT) # 10 s of the 20 s cooldown
	p2 = rig.page_info(1)
	check.call(absf(float(p2.frac) - 0.5) < 0.02 and absf(float(p2.left) - 10.0) < 0.1, "half way: the ring is half (%.2f), 10 s left" % p2.frac)
	# A refused press is announced.
	pc._notify(pc.use_slot("spell_2", Vector2.ZERO, s.run.time), "spell_2")
	check.call(c.notice == "Cultivate is on cooldown", "a press on cooldown: 'Cultivate is on cooldown'")
	# Rank-locked and MP-short pages say so.
	pc.loadout.spell_3 = s.grimoire.page("ring_of_fire")
	s.step(DT)
	check.call(rig.page_info(2).state == "locked", "a rank-D page at rank E: the page reads 'Needs a higher rank'")
	pc._notify(pc.use_slot("spell_3", Vector2.ZERO, s.run.time), "spell_3")
	check.call(c.notice == "Ring of Fire needs rank D", "a press below the rank: 'Ring of Fire needs rank D'")
	s.progression.rank = "D"
	pc.mp = 10.0
	s.step(DT)
	check.call(rig.page_info(2).state == "mp", "too little MP for a 30 MP spell: the page reads 'Not enough mana'")
	pc._notify(pc.use_slot("spell_3", Vector2.ZERO, s.run.time), "spell_3")
	check.call(c.notice == "Not enough MP", "a press without the MP: 'Not enough MP'")
	pc.mp = 100.0
	s.step(DT)
	check.call(rig.page_info(2).state == "ready", "rank D and the MP: ready")
	# Notifications stack (newest last), refresh in place, cap at 4 and expire.
	var n0: int = c.notices.size()
	c.show_notice("Not enough MP", 1.0)
	var refreshed: bool = c.notices.size() == n0
	for t in ["a", "b", "c", "d", "e"]: c.show_notice(t, 1.0)
	s.step(DT)
	check.call(refreshed and c.notices.size() == 4 and hud.notice_box.get_child_count() == 4 and (hud.notice_box.get_child(3) as Label).text == "e", "notifications: the same text refreshes, at most 4 shown, newest last")
	for i in 70: s.step(DT)
	check.call(c.notices.is_empty() and hud.notice_box.get_child_count() == 0, "notifications expire on their timers")
	# [R12] No crosshair ring; the attack page shows its special's cooldown.
	check.call(hud.find_child("SpecialRing", true, false) == null, "no crosshair cooldown ring")
	pc.cast_special(s.run.time)
	s.step(DT)
	var full: float = float(rig.page_info(0).frac)
	for i in 180: s.step(DT)
	var later: float = float(rig.page_info(0).frac)
	pc.special_ready = s.run.time
	s.step(DT)
	check.call(full > 0.9 and later < full and later > 0.0 and float(rig.page_info(0).frac) == 0.0 and rig.page_info(0).attack, "page 1 shows the special's cooldown: full after the cast (%.2f), drains (%.2f), clear when ready" % [full, later])
	c.player.health.reset()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
