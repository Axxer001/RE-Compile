extends RefCounted
# Sir's Grimoire updates [2026-11-14]: the Table of Contents in page order with a
# type filter beside the search; Spell Chants answered by tapping ready-typed
# syntax into the blanks (Wordle-like marks after a wrong try); page pickups
# within 5 m without looking at them (run_pages, in the forest).

const DT := 1.0 / 60.0
const Chant = preload("res://scripts/core/chant_engine.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var gp: CanvasLayer = c.grimoire_panel
	for id in ["ring_of_fire", "quick_step", "sage_arts"]: s.grimoire.find(id) # a mix of kinds, found in any order
	s.handle_action("grimoire")
	gp.show_tab("grimoire")
	gp.show_contents()

	# ---- the Table of Contents ---------------------------------------------------------------------
	var rows: Array = gp.toc_list.get_children().map(func(n): return String(n.name).trim_prefix("toc_"))
	var nums: Array = rows.map(func(id): return gp.page_number(id))
	var sorted := nums.duplicate()
	sorted.sort()
	check.call(rows.size() == s.grimoire.listed().size() and nums == sorted and nums[0] == 1 and gp.page_number("") == 0, "the contents list every page in page order, ascending: %s" % str(nums))
	var search: Control = gp.page_control("Search")
	var tf: OptionButton = gp.page_control("TypeFilter")
	check.call(tf != null and search != null and tf.get_parent() == search.get_parent() and tf.item_count == 5, "a type filter sits beside the search box (All, Attacks, Skills, Spells, Passives)")
	for k in [0, 1, 2, 3]:
		tf.select(k + 1)
		tf.item_selected.emit(k + 1)
		var ids: Array = gp.toc_list.get_children().map(func(n): return String(n.name).trim_prefix("toc_"))
		var kinds_ok: bool = not ids.is_empty() and ids.all(func(id): return int(s.grimoire.page(id).kind) == k)
		var want: int = s.grimoire.listed().filter(func(id): return int(s.grimoire.page(id).kind) == k).size()
		var pn: Array = ids.map(func(id): return gp.page_number(id))
		var pn_sorted := pn.duplicate()
		pn_sorted.sort()
		check.call(kinds_ok and ids.size() == want and pn == pn_sorted, "filter %s: only those pages (%d), still in page order" % [gp.KIND_FILTERS[k + 1][1], ids.size()])
	gp.set_search("fire")
	gp.set_kind_filter(2)
	var both: Array = gp.toc_list.get_children().map(func(n): return String(n.name).trim_prefix("toc_"))
	check.call(both.size() >= 1 and both.all(func(id): return int(s.grimoire.page(id).kind) == 2 and s.grimoire.page(id).title.to_lower().contains("fire")), "search and filter combine: %s" % str(both))
	gp.set_search("")
	tf.select(0)
	tf.item_selected.emit(0)
	check.call(gp.toc_kind == -1 and gp.toc_list.get_child_count() == s.grimoire.listed().size(), "All types brings every page back")

	# ---- the Spell Chant: tap, don't type ---------------------------------------------------------
	gp.show_tab("player_id")
	s.stats.unspent = 0
	s.meta.chant_tier["magic_pow"] = 1 # two blanks: one can be placed and emptied before the last one submits
	gp.start_chant("magic_pow")
	var pr: Dictionary = gp.problem
	var ch: Array = pr.get("choices", [])
	var uniq := {}
	for t in ch: uniq[t] = true
	check.call(gp.mode == "chant" and ch.size() == Chant.CHOICES_MAX and uniq.size() == ch.size() and pr.answers.all(func(a): return a in ch), "the chant offers %d ready-typed choices, the answers among them: %s" % [ch.size(), str(ch)])
	var choice_btns: Array = gp.page_control("ChantChoices").get_children()
	var slot_btns: Array = gp.page_control("ChantSlots").get_children()
	check.call(choice_btns.size() == ch.size() and slot_btns.size() == pr.answers.size() and gp.page_control("blank_1") == null, "the card shows the blanks and the choice buttons (no typing box)")
	# [Sir, 2026-11-21, the Unity flow]: no Chant or Retry button, only Hint and Cancel.
	var cancel_btn: Control = gp.page_control("ChantCancel")
	check.call(gp.page_control("ChantGo") == null and gp.page_control("ChantRetry") == null and gp.page_control("Hint") != null and cancel_btn != null, "the chant's only buttons are Hint and Cancel")
	var decoy: String = String(ch.filter(func(t): return not t in pr.answers)[0])
	(gp.page_control("ChantChoices").get_child(ch.find(decoy)) as Button).pressed.emit()
	check.call(gp.chant_slots[0] == decoy and gp.slot_lines().any(func(l): return String(l).contains("[%s]" % decoy)), "tapping a choice fills the first blank; the code shows it in place")
	(gp.page_control("slot_1") as Button).pressed.emit()
	check.call(gp.chant_slots[0] == "", "tapping a filled blank empties it")
	s.progression.chant_streak = 2
	for i in pr.answers.size(): gp.choose(decoy) # the last pick submits by itself
	check.call(s.progression.chant_streak == 0 and gp.rejecting() and gp.mode == "chant", "filling the last blank submits at once; a wrong answer fizzles (the streak resets) and the card shakes")
	gp.finish_rejection()
	check.call(gp.problem.get("key", "") != pr.key and not gp.chant_slots.is_empty() and not gp.chant_slots.has(decoy) and gp.mode == "chant" and not gp.rejecting(), "after the shake a new chant replaces it by itself, the blanks empty")
	var pr2: Dictionary = gp.problem
	var pow0: float = s.stats.value("magic_pow", s.run.time)
	for a in pr2.answers: gp.choose(String(a))
	check.call(s.stats.value("magic_pow", s.run.time) > pow0 and gp.mode == "browse", "the right tokens in the blanks: the chant takes hold the moment the last one is placed")
	var csp: Node = null
	var t_wait := Time.get_ticks_msec()
	while csp == null and Time.get_ticks_msec() - t_wait < 3000: # once the card has turned to its stats (CHANT_SPARKLE_DELAY)
		await tree.process_frame
		csp = gp.body.find_child("StatSparkle", true, false)
	var waited := (Time.get_ticks_msec() - t_wait) / 1000.0
	check.call(csp != null and csp.get_meta("stat_cell", "") == "value_magic_pow", "a successful chant sparkles over the raised stat, once the card shows it (after %.2f s)" % waited)
	s.stats.unspent = 1
	await tree.process_frame
	await tree.process_frame
	gp.allocate("max_hp")
	await tree.process_frame
	await tree.process_frame
	var sp: Node = gp.body.find_child("StatSparkle", true, false)
	check.call(sp != null and sp.get_meta("stat_cell", "") == "value_max_hp", "spending a stat point sparkles over that stat")
	s.handle_action("grimoire")

# Page pickups [Sir, 2026-11-14]: within 5 m, no need to look at the page.
static func run_pages(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var p: CharacterBody3D = c.player
	var id: String = c.drop_page(c.player.global_position + Vector3(0, 0, -8)) # Map 1: pages drop from enemies [spec §3]
	var pk: Node3D = c.page_pickups[id]
	var spot: Vector3 = pk.global_position - Vector3(0, 0.6, 0)
	p.global_position = spot + Vector3(0, 0, 6.5) # 6.5 m away, looking straight at it
	p.yaw = 0.0
	p.pitch = 0.0
	p.apply_look()
	await tree.physics_frame
	var far: Dictionary = c.target_in_view()
	p.global_position = spot + Vector3(0, 0, 4.5) # 4.5 m away, facing away and up at the sky
	p.yaw = PI
	p.pitch = deg_to_rad(60.0)
	p.apply_look()
	await tree.physics_frame
	var near: Dictionary = c.target_in_view()
	check.call(far.kind != "page" and near.kind == "page" and near.target == pk, "a page counts within 5 m without looking at it (not at 6.5 m)")
	c.publish(DT)
	var prompt_ok: bool = String(c.hud.prompt.text).contains("Pick up page")
	var r_up: String = c.try_interact(true)
	c.try_interact(false)
	check.call(prompt_ok and r_up == "page" and s.grimoire.is_found(id) and not pk.visible, "F picks it up from there (the prompt shows)")
	s.meta.reset()
	s.restart()
	await tree.physics_frame
