extends RefCounted
# The held grimoire casting rehaul [Sir, 2026-11-20; docs/plan-held-grimoire.md]:
# Q/E unbound, 1-4 page keys and 5 the status page; 4 spell slots + 1 passive
# (attack and skill pages in spell slots) and the old-loadout migration; LMB/RMB
# on an attack page, a skill cast as a spell; the 0.5 s turn with one flip per
# page between, casting blocked mid-turn; the status page; the book/wand hand
# swap; the HUD's loadout bar gone; the Ember Wand's clips and tip.
# Combat runs on pcombat.simulate with the session clock set by hand, so every
# number is deterministic.

const DT := 1.0 / 60.0
const PC = preload("res://scripts/combat/player_combat.gd")
const Lib = preload("res://scripts/core/page_library.gd")

static func tick(s, pc, intent: Dictionary, n: int) -> void:
	for i in n:
		s.run.time += DT
		pc.simulate(intent, DT, s.run.time)
		pc.rig.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var pc = c.pcombat
	var p: CharacterBody3D = c.player

	# ---- input -----------------------------------------------------------------------
	var keys_ok := true
	for i in 5:
		var ev: Array = InputMap.action_get_events("page_%d" % (i + 1)) if InputMap.has_action("page_%d" % (i + 1)) else []
		if ev.is_empty() or ev[0].physical_keycode != KEY_1 + i: keys_ok = false
	var qe_free := true
	for action in InputMap.get_actions():
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e.physical_keycode == KEY_E or (e.physical_keycode == KEY_Q and action != &"toggle_book")): qe_free = false
	check.call(keys_ok and qe_free and InputMap.action_get_events("toggle_book")[0].physical_keycode == KEY_Q and not InputMap.has_action("skill_1") and not InputMap.has_action("skill_2") and "page_5" in s.input.HELD, "keys 1-5 turn the held grimoire (5: status page); Q toggles the held book; E is unbound")

	# ---- loadout ---------------------------------------------------------------------
	check.call(PC.SLOTS == ["spell_1", "spell_2", "spell_3", "spell_4", "passive"] and String(pc.loadout.spell_1.id) == "scorch_and_burn" and String(pc.loadout.spell_2.id) == "cultivate", "4 spell slots + 1 passive; a run starts with Scorch and Burn on page 1, Cultivate on page 2")
	for id in ["quick_step", "ring_of_fire", "sage_arts", "heads_or_tails"]: s.meta.unlock(id)
	s.progression.rank = "D"
	var qs: Resource = s.grimoire.page("quick_step")
	var ht: Resource = s.grimoire.page("heads_or_tails")
	var sa: Resource = s.grimoire.page("sage_arts")
	var fits: bool = pc.equip("spell_3", ht) == "ok" and pc.equip("spell_4", qs) == "ok" and pc.equip("spell_4", sa) == "wrong_kind" and pc.equip("passive", qs) == "wrong_kind" and pc.equip("passive", sa) == "ok"
	check.call(fits, "attack and skill pages fit spell slots; a passive only the passive slot")
	var old := {"attack": Lib.make("scorch_and_burn"), "skill_1": Lib.make("cultivate"), "skill_2": Lib.make("quick_step"),
		"spell_1": Lib.make("ring_of_fire"), "spell_2": Lib.make("firefly"), "spell_3": Lib.make("explosion"), "passive": Lib.make("sage_arts")}
	var m: Dictionary = PC.migrate_loadout(old)
	var ids := []
	for slot in PC.SLOTS: ids.append(String(m[slot].id) if m[slot] != null else "")
	check.call(ids == ["scorch_and_burn", "cultivate", "quick_step", "ring_of_fire", "sage_arts"], "an old loadout migrates: attack -> 1, then skills and spells in order; extras left out; passive kept (%s)" % str(ids))

	# ---- attack page: LMB basic (held repeats), RMB special --------------------------
	p.global_position = Vector3(60, 0, 57)
	p.velocity = Vector3.ZERO
	p.state = p.Move.GROUND
	await tree.physics_frame
	pc.reset()
	s.stats.modifiers.clear()
	var b0: int = pc.basic_casts
	tick(s, pc, {"attack": true}, 30) # 0.5 s held at Atk Spd 5
	var held: int = pc.basic_casts - b0
	var sp0: int = pc.special_casts
	tick(s, pc, {"special": true}, 2)
	tick(s, pc, {}, 2)
	check.call(pc.active == 0 and pc.page != null and held >= 2 and pc.special_casts == sp0 + 1, "page 1 (an attack page): held LMB repeats the basic (%d casts), RMB the special" % held)
	c.projectiles.reset()

	# ---- turning ----------------------------------------------------------------------
	tick(s, pc, {"page_2": true}, 1)
	var t0: float = s.run.time
	var mid := false
	while s.run.time - t0 < PC.TURN_S - DT * 1.5:
		tick(s, pc, {"attack": true}, 1)
		if pc.active != 0: mid = true
	var blocked: bool = int(pc.casts.get("cultivate", 0)) == 0 and not mid
	tick(s, pc, {}, 3)
	check.call(blocked and pc.active == 1 and pc.page == null, "a turn takes 0.5 s: the page changes when it ends, and casting during it is ignored")
	# Every distance: 0.5 s, one flip per page crossed (the rig draws each).
	var flips_ok := true
	var report := []
	for pair in [[1, 0], [0, 3], [3, 0], [0, 4], [4, 2], [2, 3]]:
		pc.reset()
		tick(s, pc, {}, 2)
		if pair[0] != 0:
			tick(s, pc, {"page_%d" % (pair[0] + 1): true}, 1)
			tick(s, pc, {}, 130)
		var drawn0: int = pc.rig.flips_drawn
		tick(s, pc, {"page_%d" % (pair[1] + 1): true}, 1)
		var start: float = pc.turn_start
		var n: int = pc.flips()
		while pc.turning(s.run.time): tick(s, pc, {}, 1)
		tick(s, pc, {}, 2)
		var took: float = s.run.time - start
		var drawn: int = pc.rig.flips_drawn - drawn0
		report.append("%d->%d: %d flips %.2f s" % [pair[0] + 1, pair[1] + 1, drawn, took])
		if n != absi(pair[1] - pair[0]) or drawn != n or absf(took - PC.TURN_S*n) > DT * 3.5 or pc.active != pair[1]: flips_ok = false
	check.call(flips_ok, "every leaf takes 0.5 s with one flip per page crossed (%s)" % ", ".join(report))

	# ---- skill page as a spell: LMB casts it, RMB nothing, no MP --------------------
	pc.reset()
	tick(s, pc, {"page_2": true}, 1)
	tick(s, pc, {}, 35)
	var mp0: float = pc.mp
	var sp1: int = pc.special_casts
	tick(s, pc, {"attack": true}, 2)
	tick(s, pc, {"special": true}, 2)
	tick(s, pc, {}, 2)
	check.call(pc.active == 1 and int(pc.casts.get("cultivate", 0)) == 1 and is_equal_approx(pc.mp, mp0) and pc.special_casts == sp1 and pc.remaining("spell_2", s.run.time) > 19.0, "page 2 (Cultivate, a skill): LMB casts it once, free; RMB does nothing; its 20 s cooldown holds")

	# ---- status page ------------------------------------------------------------------
	pc.equip("passive", sa)
	c.effects.apply("player", "Burn", 5.0, s.run.time, "test", 100.0)
	tick(s, pc, {"page_5": true}, 1)
	tick(s, pc, {}, 100)
	var info: Dictionary = pc.rig.status_info()
	var names := []
	for e in info.effects: names.append(String(e.id))
	var b1: int = pc.basic_casts
	tick(s, pc, {"attack": true}, 3)
	tick(s, pc, {"special": true}, 2)
	check.call(pc.active == PC.STATUS_PAGE and pc.rig.shown == PC.STATUS_PAGE and info.passive == "Sage Arts" and "Cultivate" in names and "Burn" in names and info.effects.all(func(e): return float(e.s) > 0.0) and pc.basic_casts == b1, "page 5, the status page: the passive (%s) and every effect with time left (%s); nothing casts there" % [info.passive, ", ".join(names)])
	c.effects.clear_target("player")

	# ---- hands, wand, HUD -------------------------------------------------------------
	var w: Node3D = pc.wand
	var book: Node3D = pc.rig.book
	pc.rig.step(DT)
	s.settings.set_value("book_hand", "right")
	pc.rig.step(DT)
	var right_book: bool = book.position.x > 0.1 and w.position.x < -0.1 and w.left
	s.settings.set_value("book_hand", "left")
	pc.rig.step(DT)
	var left_book: bool = book.position.x < -0.1 and w.position.x > 0.1 and not w.left
	s.settings.set_value("book_hand", "right")
	pc.rig.step(DT)
	check.call(right_book and left_book and book.position.x > 0.1, "book in the right hand, wand in the left when selected; Settings swaps the pair")
	check.call(c.hud.find_child("ActionBar", true, false) == null and not "slots" in c.hud, "the HUD's loadout bar is gone (the pages show cooldowns)")
	await tree.physics_frame
	var tip: Vector3 = w.tip_rest_global()
	check.call(pc.hand_origin().is_equal_approx(tip) or pc.hand_origin().is_equal_approx(p.camera.global_position), "spells leave from the wand tip")
	check.call(w.find_children("*", "GeometryInstance3D", true, false).all(func(g): return (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) and book.find_children("*", "GeometryInstance3D", true, false).all(func(g): return (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "neither the wand nor the book casts a shadow")
	# The controller's state -> the Ember Wand's clip (Movement Guide.md).
	var M = p.Move
	var cases := [[M.GROUND, Vector3.ZERO, false, {}, "Idle"], [M.GROUND, Vector3(0, 0, -4), false, {}, "Walk"], [M.GROUND, Vector3(0, 0, -9), false, {}, "Run"],
		[M.GROUND, Vector3.ZERO, true, {}, "CrouchHold"], [M.GROUND, Vector3(0, 0, -3), true, {}, "CrouchWalk"], [M.AIR, Vector3(0, 6, 0), false, {}, "Jump"],
		[M.AIR, Vector3(0, -6, 0), false, {}, "Fall"], [M.SLIDE, Vector3(0, 0, -9), false, {}, "Slide"], [M.DASH, Vector3(0, 0, -15), false, {}, "Dash"],
		[M.WALLCLIMB, Vector3(0, 3, 0), false, {}, "WallClimb"], [M.MANTLE, Vector3.ZERO, false, {"phase": "grab"}, "LedgeCatch"],
		[M.MANTLE, Vector3.ZERO, false, {"phase": "hang"}, "LedgeHang"], [M.MANTLE, Vector3.ZERO, false, {"phase": "pull"}, "MantlePull"]]
	var clips_ok := true
	var bad := []
	var saved_mantle: Dictionary = p.mantle
	for cs in cases:
		p.state = cs[0]
		p.velocity = cs[1]
		p.crouching = cs[2]
		p.mantle = cs[3]
		p.last_move = Vector2(0, 1) if cs[1].z < 0 else Vector2.ZERO
		var got: StringName = w.pick()
		if String(got) != cs[4] or not w.motion.has_animation(got):
			clips_ok = false
			bad.append("%s->%s" % [cs[4], got])
	p.state = M.GROUND
	p.velocity = Vector3.ZERO
	p.crouching = false
	p.mantle = saved_mantle
	check.call(clips_ok, "the controller's states pick the Ember Wand's clips, each present in the model %s" % str(bad))
	# Every Ember Wand clip has a trigger [Sir, 2026-11-20: use every animation].
	# One-shot events: a controller counter rising plays its clip once.
	w.step(DT) # records the counters
	var ev_ok := true
	var ev_bad := []
	for e in w.EVENTS:
		p.set(e[0], int(p.get(e[0])) + 1)
		w.step(DT)
		if w.clip != e[1]:
			ev_ok = false
			ev_bad.append("%s->%s" % [e[0], w.clip])
		for i in 40: w.step(DT) # let it play out
	check.call(ev_ok, "movement events play their clips (geo jump, lurch, slide jump, step-up, mantle hop/boost, end boost, superglide, ledge drop, bounces, wall push, lunge) %s" % str(ev_bad))
	p.state = M.AIR
	w.step(DT)
	p.air_jumps -= 1
	w.step(DT)
	var dj: bool = w.clip == &"DoubleJump"
	p.state = M.GROUND
	p.air_jumps += 1
	for i in 30: w.step(DT)
	p.state = M.SLIDE
	p.velocity = Vector3(0, 0, -9)
	w.step(DT)
	var enter: bool = w.clip == &"SlideEnter"
	p.state = M.GROUND
	p.velocity = Vector3.ZERO
	w.step(DT)
	var exit_ok: bool = w.clip == &"SlideExit"
	for i in 30: w.step(DT)
	p.state = M.WALLCLIMB
	p.velocity = p.global_transform.basis.x * 4.0
	var run_r: StringName = w.pick()
	p.velocity = -p.global_transform.basis.x * 4.0
	var run_l: StringName = w.pick()
	p.state = M.GROUND
	p.velocity = Vector3.ZERO
	var stag0: int = int(w.played.get(&"Stagger", 0))
	p.stuns += 1
	w.step(DT)
	var fall_stun: bool = int(w.played.get(&"Stagger", 0)) == stag0 + 1
	check.call(fall_stun, "a fall stun plays the wand's Stagger")
	check.call(dj and enter and exit_ok and run_r == &"WallRunRight" and run_l == &"WallRunLeft", "double jump, slide enter and exit, wall runs left and right have their clips")
	pc.rig.equip(false)
	for i in 3: pc.rig.step(DT)
	var stowing: bool = w.clip == &"Stow" and pc.rig.book_clip == "Equip" and pc.rig.reveal < 1.0
	pc.rig.equip(true)
	for i in 60: pc.rig.step(DT)
	check.call(stowing and w.played.has(&"Equip") and pc.rig.reveal >= 1.0 and pc.rig.openness == 1.0 and pc.rig.book_clip == "Equip", "death stows (wand Stow, the book's Equip run backwards); a new run equips again (Equip), then the covers remain open")
	pc.reset()
	tick(s, pc, {}, 50)
	tick(s, pc, {"page_3": true}, 1)
	tick(s, pc, {}, 5)
	var first_leaf: bool = pc.rig.leaf.visible and pc.rig.flip == 0
	tick(s, pc, {}, 30)
	var second_leaf: bool = pc.rig.leaf.visible and pc.rig.flip == 1
	tick(s, pc, {}, 30)
	check.call(first_leaf and second_leaf and pc.active == 2 and pc.rig.openness == 1.0 and not pc.rig.leaf.visible, "two successive leaves turn with both covers open")
	pc.reset()
	tick(s, pc, {"page_4":true}, 4)
	tick(s, pc, {"toggle_book":true}, 50)
	var locked: bool = pc.book_closed and pc.rig.openness == 0 and pc.active == 0
	for i in 5:
		tick(s, pc, {"page_%d" % (i+1):true}, 2)
	tick(s, pc, {"attack":true,"special":true}, 2)
	check.call(locked and pc.active == 0 and not pc.turning(s.run.time) and pc.basic_casts > 0 and pc.special_casts == 1, "holding Q closes once; closed spell fires and page keys are locked")
	tick(s, pc, {"toggle_book":true}, 1)
	tick(s, pc, {"page_2":true}, 1)
	tick(s, pc, {}, 50)
	check.call(not pc.book_closed and pc.rig.openness == 1.0 and pc.active == 1, "Q reopens and restores page selection")
	# Gestures: Attack (basic), Cast (spell or skill), Channel (Breath/Explosion), Damage, Stagger.
	p.health.grant_immunity(-1.0, [], -INF)
	p.health.apply(preload("res://scripts/combat/damage_packet.gd").new(997001, "test", "infected", 30.0, "bite"), s.run.time)
	var dmg: bool = w.played.has(&"Damage")
	p.health.apply(preload("res://scripts/combat/damage_packet.gd").new(997002, "test", "infected", 150.0, "bite"), s.run.time + 0.5)
	check.call(dmg and w.played.has(&"Stagger") and w.played.has(&"Cast") and w.played.has(&"Attack"), "hits flinch the wand (Damage) or stagger it (100+); casts play Cast / Attack")
	p.health.reset()
	var k0: int = w.kicks
	pc.reset()
	tick(s, pc, {"attack": true}, 2)
	check.call(w.kicks > k0 and w.glowing(), "a cast plays the wand's kick and lights its tip")
	c.projectiles.reset()
	s.restart()
