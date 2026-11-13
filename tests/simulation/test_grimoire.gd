extends RefCounted
# P5 Grimoire (GDD §3.1-3.2, handoff §5 and §10): the kept profile and the
# death model (R5), page pickups, the Code Assembly banks (R2: fresh,
# topic-bound, never the last attempt's, never pre-solved), the validator,
# the panel's unlock / equip / Player ID flows, and hits while it is open (R1).

const DT := 1.0 / 60.0
const MetaProfile = preload("res://scripts/core/meta_profile.gd")
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const Validator = preload("res://scripts/core/code_order_validator.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")
const PROFILE := "user://test_profile.cfg"

static func place(c: Node3D, at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = deg_to_rad(pitch_deg)
	p.apply_look()
	p.reset_movement()

# Solve an attempt by clicking: put the line that belongs at each position there.
static func solve(gp: CanvasLayer) -> void:
	for k in gp.attempt.order.size():
		var at: int = gp.attempt.order.find(k)
		if at != k:
			gp.pick(k)
			gp.pick(at)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var g: RefCounted = s.grimoire
	var gp: CanvasLayer = c.grimoire_panel
	check.call(g.listed() == ["scorch_and_burn", "cultivate", "dragons_breath", "firefly", "explosion"] and g.is_unlocked("cultivate") and g.is_unlocked("explosion") and not g.is_found("quick_step"), "fresh profile: Scorch and Burn, Cultivate and the three Rank E spells known and unlocked (spells for testing [Sir]); the other pages unseen")

	# ---- banks and validator -------------------------------------------------------------
	var banks_ok := true
	var shown_ok := true
	for id in PageLibrary.IDS:
		if CodeAssembly.variants(id).size() < 8 or CodeAssembly.topic(id) == "": banks_ok = false
		if Array(g.page(id).code_lines) != CodeAssembly.shown(id).lines: shown_ok = false
	check.call(banks_ok and shown_ok, "every page has >= 8 Code Assembly variants on its topic; variant 0 (the Tech Spec block) is the one on the page [R2]")
	var rng := RandomNumberGenerator.new()
	var presolved := 0
	for id in PageLibrary.IDS:
		for v in CodeAssembly.variants(id):
			for seed in 200:
				rng.seed = seed
				if Validator.check(v, CodeAssembly.shuffled(v, rng)).ok: presolved += 1
	check.call(presolved == 0, "8,000 shuffles (every variant, 200 seeds): none starts out solved")
	var repeats := 0
	var topics_ok := true
	var last := -1
	rng.seed = 7
	for i in 200:
		var d: Dictionary = CodeAssembly.draw("ring_of_fire", rng, last)
		if d.index == last: repeats += 1
		if not d.variant in CodeAssembly.variants("ring_of_fire"): topics_ok = false
		last = d.index
	check.call(repeats == 0 and topics_ok, "200 draws: never the previous attempt's variant, always from the page's own bank")
	var v0: Dictionary = CodeAssembly.shown("scorch_and_burn")
	var right := range(v0.lines.size())
	var swapped := right.duplicate(); swapped[1] = 2; swapped[2] = 1
	var r1: Dictionary = Validator.check(v0, right)
	var r2: Dictionary = Validator.check(v0, swapped)
	check.call(r1.ok and not r2.ok and r2.wrong_indices == [1, 2], "validator: the right order passes; two swapped lines fail at exactly those positions (%s)" % [r2.wrong_indices])
	# Identical lines (C++ closing braces) are interchangeable; distinct ones are not.
	var braces: Dictionary = CodeAssembly.variants("ring_of_fire")[5] # two { } blocks
	var bl: Array = braces.lines
	var b_right := range(bl.size())
	var b_swap := b_right.duplicate()
	var i1: int = bl.find("  }")
	var i2: int = bl.rfind("  }")
	b_swap[i1] = i2; b_swap[i2] = i1
	var cv: Dictionary = CodeAssembly.shown("cultivate")
	var c_bad := range(cv.lines.size())
	c_bad[3] = 4; c_bad[4] = 3 # its two couts swapped: the output order changes
	check.call(i1 != i2 and Validator.check(braces, b_swap).ok and not Validator.check(cv, c_bad).ok, "identical lines (two closing braces) may trade places; two different statements may not")
	var dup := range(cv.lines.size())
	dup[1] = 0
	check.call(not Validator.check(v0, [0, 1, 2, 3]).ok and not Validator.check(cv, dup).ok, "a short or duplicated arrangement fails")

	# ---- page pickup ------------------------------------------------------------------------
	var qs_spot: Vector3 = c.page_spots.quick_step
	place(c, qs_spot + Vector3(0, 0, 1.4), 0.0, -20.0)
	await tree.physics_frame
	s.step(DT)
	var aimed: Dictionary = c.target_in_view()
	var got: String = c.try_interact(true)
	c.try_interact(false)
	check.call(aimed.kind == "page" and got == "page" and g.is_found("quick_step") and not g.is_unlocked("quick_step") and g.listed().has("quick_step"), "F on a page in the world: found, listed as locked")
	check.call(c.notice.begins_with("New page: Quick Step") and not c.page_pickups.quick_step.visible, "a 'New page' notice; the page leaves the world")
	check.call(c.try_interact(true) == "" and gp.page_text("quick_step").find("(locked)") >= 0 and gp.page_text("ring_of_fire") == "", "the picked-up page is gone; a locked page shows only its name and topic; an unfound one shows nothing")
	c.try_interact(false)

	# ---- Tab, Code Assembly unlock ------------------------------------------------------------
	s.handle_action("grimoire")
	check.call(gp.visible and s.input.context == InputRouter.Context.OVERLAY and s.input.overlay == "grimoire", "Tab opens the Grimoire (an overlay: the world keeps running)")
	var t0: float = s.run.time
	s.step(DT)
	check.call(s.run.time > t0, "the clock runs with the Grimoire open (Tab does not pause) [Sir]")
	var a: Dictionary = gp.start_assembly("quick_step")
	check.call(not a.is_empty() and gp.mode == "assembly" and not Validator.check(a.variant, a.order).ok, "Solve to unlock: a shuffled Code Assembly (not already solved)")
	var lvl0: int = s.progression.level
	var pts0: int = s.stats.unspent
	gp.pick(0); gp.pick(1) # one swap (likely still wrong)
	var bad: Dictionary = {"ok": false}
	if not Validator.check(gp.attempt.variant, gp.attempt.order).ok:
		bad = gp.submit()
	check.call(not bad.ok and not g.is_unlocked("quick_step") and s.stats.unspent == pts0 and gp.mode == "assembly" and gp.wrong.size() > 0, "a wrong submit flags the misplaced lines; no penalty, no reward, retry")
	# A hit mid-puzzle restarts it with a fresh question; the panel stays [R1].
	var idx0: int = gp.attempt.index
	var n0: int = gp.attempts
	c.player.health.apply(DamagePacket.new(97001, "test", "infected", 5.0, "bite"), s.run.time)
	check.call(gp.visible and gp.mode == "assembly" and gp.attempts == n0 + 1 and int(gp.attempt.get("index", idx0)) != idx0 and s.input.context == InputRouter.Context.OVERLAY, "a hit during the unlock restarts it with a fresh question (variant %d -> %d), panel open [R1]" % [idx0, int(gp.attempt.get("index", -1))])
	# A dash-immune hit does nothing.
	c.player.health.grant_immunity(s.run.time + 1.0, ["*"], s.run.time)
	var n1: int = gp.attempts
	c.player.health.apply(DamagePacket.new(97002, "test", "infected", 5.0, "bite"), s.run.time)
	check.call(gp.attempts == n1 and gp.visible, "a hit blocked by dash i-frames neither closes nor restarts it")
	c.player.health.grant_immunity(-1.0, [], -INF)
	solve(gp)
	var ok: Dictionary = gp.submit()
	check.call(ok.ok and g.is_unlocked("quick_step") and s.meta.unlocked.has("quick_step") and gp.mode == "browse", "solved: the page unlocks (kept in the profile)")
	check.call(s.progression.level == lvl0 + 1 and s.progression.exp == 50 and s.stats.unspent == pts0 + 3 + 1, "unlock reward: +3 stat points and +150 EXP (a level-up from 0/100: level %d, %d EXP, %d points)" % [s.progression.level, s.progression.exp, s.stats.unspent])
	check.call(gp.start_assembly("quick_step").is_empty() and not g.unlock("quick_step") and s.stats.unspent == pts0 + 4, "an unlocked page cannot be solved or unlocked again (no second reward)")
	check.call(gp.page_text("quick_step").find("01: #include <iostream>") >= 0 and gp.page_text("quick_step").find("Lesson: C++ Output:") >= 0 and gp.page_text("quick_step").find("Cooldown: 10.0 s") >= 0, "the unlocked page shows its C++ code with line numbers, lesson, tip and cooldown")

	# ---- equip -------------------------------------------------------------------------------
	gp.select_page("quick_step")
	check.call(gp.equip_selected("skill_2") == "ok" and String(c.pcombat.loadout.skill_2.id) == "quick_step", "click-to-equip: Quick Step onto [Q]")
	check.call(gp.equip_selected("spell_1") == "wrong_kind" and gp.equip_selected("skill_1") == "duplicate", "the panel shows the loadout's refusals (wrong slot, already equipped)")
	s.meta.unlock("sage_arts"); g.find("sage_arts")
	gp.select_page("sage_arts")
	check.call(gp.equip_selected("passive") == "rank" and gp.status_text.begins_with("Requires Rank D"), "a rank-D page at rank E: refused, with the reason")
	check.call(gp.unequip("skill_2") == "ok" and c.pcombat.loadout.skill_2 == null, "a slot can be emptied")
	gp.select_page("quick_step"); gp.equip_selected("skill_2")

	# ---- hits while browsing close it [R1] ---------------------------------------------------
	gp.select_page("cultivate")
	c.player.health.apply(DamagePacket.new(97003, "test", "infected", 5.0, "bite"), s.run.time)
	check.call(not gp.visible and s.input.context == InputRouter.Context.GAMEPLAY, "a hit while browsing closes the Grimoire")

	# ---- Player ID ----------------------------------------------------------------------------
	s.handle_action("grimoire")
	gp.show_tab("player_id")
	var st: RefCounted = s.stats
	var pow0: float = st.value("magic_pow", s.run.time)
	var spent: bool = gp.allocate("magic_pow")
	check.call(spent and st.value("magic_pow", s.run.time) > pow0 and st.unspent == pts0 + 3, "[+] Magic Pow spends a point and raises the stat")
	st.points.mov_spd = 48 # 10 + 48 x 0.25 = the 22 m/s cap
	check.call(not gp.allocate("mov_spd") and gp.status_text.ends_with("at its cap."), "[+] at the hard cap is refused")
	st.points.mov_spd = 0
	st.unspent = 0
	check.call(not gp.allocate("max_hp") and gp.mode == "chant" and st.points.max_hp == 0 and gp.player_id_text().find("Unspent stat points: 0") >= 0, "no points: [+] spends nothing and opens a Spell Chant instead [R9]")
	gp.cancel_chant()
	s.handle_action("grimoire")
	check.call(not gp.visible and s.input.context == InputRouter.Context.GAMEPLAY, "Tab again closes it")

	# ---- death model [R5] -----------------------------------------------------------------------
	g.find("ring_of_fire") # found this run but never unlocked
	s.restart()
	await tree.physics_frame
	s.step(DT)
	g = s.grimoire
	check.call(g.is_unlocked("quick_step") and g.listed().has("quick_step") and not g.is_found("ring_of_fire") and c.page_pickups.ring_of_fire.visible and not c.page_pickups.quick_step.visible, "after a death: unlocked pages are kept; a found-but-locked page is lost and back in the world")
	check.call(s.progression.level == 1 and s.stats.unspent == 0 and c.pcombat.loadout.skill_2 == null and String(c.pcombat.loadout.skill_1.id) == "cultivate", "level, points and the loadout reset (start loadout again)")
	check.call(c.pcombat.equip("skill_2", g.page("quick_step")) == "ok", "a kept page can be equipped in the next run")

	# ---- the profile on disk ---------------------------------------------------------------
	var m := MetaProfile.new()
	m.unlock("ring_of_fire")
	m.set_rank("D")
	m.chant_tier = {"magic_pow": 2}
	check.call(m.save(PROFILE) == OK, "profile saves")
	var m2 := MetaProfile.new()
	check.call(m2.load_from(PROFILE) and m2.unlocked.has("ring_of_fire") and m2.unlocked.has("scorch_and_burn") and m2.rank == "D" and int(m2.chant_tier.get("magic_pow", 0)) == 2, "profile round-trip: pages, rank, chant tiers")
	m.rank = "C"
	check.call(m.save(PROFILE) == OK, "second save preserves a backup")
	var broken := FileAccess.open(PROFILE, FileAccess.WRITE)
	broken.store_string("# truncated profile: meta section missing")
	broken.close()
	check.call(m2.load_from(PROFILE) and m2.rank == "D", "corrupt primary recovers previous profile")
	check.call(m.save(PROFILE) == OK and m2.load_from(PROFILE) and m2.rank == "C", "recovered profile can be saved again")
	var errors := []
	m.save_failed.connect(func(err): errors.append(err))
	check.call(m.save(PROFILE + "/missing/profile.cfg") != OK and errors.size() == 1, "save failure reaches the caller")
	for suffix in [".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	check.call(s.meta.path == "" and not FileAccess.file_exists("user://profile.cfg") or s.meta.path == "", "tests never write the player's profile (path is empty)")

	s.meta.reset()
	s.restart()
	await tree.physics_frame

