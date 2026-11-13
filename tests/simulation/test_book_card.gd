extends RefCounted
const PageLibrary = preload("res://scripts/core/page_library.gd")
# Sir's Grimoire / Player ID rework (2026-11-12): the book (one ability per
# page, flipped; live numbers on each page; the loadout rows), the guild ID
# card (front records, back stats, the chant on the back with a hint after
# 10 s that only names the page), syntax-only chant blanks, and the lifetime
# records kept in the profile.

const DT := 1.0 / 60.0
const Chant = preload("res://scripts/core/chant_engine.gd")
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const MetaProfile = preload("res://scripts/core/meta_profile.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"])
	var gp: CanvasLayer = c.grimoire_panel
	var all5 := ["scorch_and_burn", "cultivate", "ring_of_fire", "quick_step", "sage_arts"]

	# ---- chant blanks are syntax, never numbers --------------------------------------------------
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var numeric := 0
	var unreadable := 0
	for i in 400:
		var pr: Dictionary = Chant.draw(rng.randi_range(0, 9), all5, rng)
		var lines: Array = CodeAssembly.variants(pr.page)[pr.variant].lines
		for a in pr.answers:
			if String(a).is_valid_float(): numeric += 1
			# A blanked variable name must appear elsewhere in its snippet (it can be read back).
			if String(a).is_valid_identifier() and pr.tier == Chant.VAR_TIER:
				var seen := 0
				for l in lines:
					if RegEx.create_from_string("\\b%s\\b" % a).search(l) != null: seen += 1
				if seen < 2: unreadable += 1
	check.call(numeric == 0 and unreadable == 0 and Chant.TIER_NAMES[1] == "program structure", "400 chants: no blank is a number; a blanked variable always appears again in its code [Sir]")

	# ---- the book: one ability per page, live numbers -------------------------------------------
	for id in ["quick_step", "ring_of_fire", "sage_arts"]: s.grimoire.find(id)
	for id in all5: s.meta.unlock(id)
	s.handle_action("grimoire")
	var order: Array = [""] + s.grimoire.listed() # page 1 is the contents
	check.call(gp.selected == "" and gp.panel.find_child("Contents", true, false) != null and gp.panel.find_child("Search", true, false) != null, "the Grimoire opens on page 1, the Table of Contents, with a search bar [Sir]")
	var seen_pages := [gp.selected]
	for i in order.size():
		gp.handle_key(KEY_RIGHT)
		seen_pages.append(gp.selected)
	check.call(seen_pages.slice(0, order.size()) == order and seen_pages.back() == "" and gp.panel.find_child("NextPage", true, false) != null, "Right arrow turns through every page in order and wraps to the contents")
	gp.handle_key(KEY_LEFT)
	check.call(gp.selected == order.back(), "Left arrow goes back (from the contents to the last page)")
	# The Previous button sits at the page's bottom-left, Next at its bottom-right.
	await tree.process_frame
	await tree.process_frame
	var pv: Rect2 = gp.view_rect("PrevPage")
	var nx: Rect2 = gp.view_rect("NextPage")
	check.call(pv.size.x > 0.0 and nx.position.x > pv.position.x + 300.0 and absf(pv.position.y - nx.position.y) < 2.0, "Previous page bottom-left, Next page bottom-right")
	# The loadout is always the left page.
	gp.select_page("ring_of_fire")
	var on_page: bool = gp.panel.find_child("slot_attack", true, false) != null
	gp.show_contents()
	check.call(on_page and gp.panel.find_child("slot_attack", true, false) != null and gp.panel.find_child("ToContents", true, false) != null, "the loadout stays on the left page on every page; the contents button is at the top-left")
	# The contents: one column, icon + name + short line + page number; locked rows show no line.
	var rows: Array = gp.toc_list.get_children()
	var r0: Control = gp.toc_list.find_child("toc_scorch_and_burn", false, false)
	check.call(rows.size() == s.grimoire.listed().size() and r0 != null and r0.find_child("Info", true, false) != null and (r0.find_child("PageNo", true, false) as Label).text == "p. %d" % gp.page_number("scorch_and_burn"), "the contents: one row per ability with its icon, name, short line and page number")
	s.grimoire.meta.unlocked.erase("ring_of_fire")
	gp.show_contents()
	var locked_row: Control = gp.toc_list.find_child("toc_ring_of_fire", false, false)
	check.call(locked_row.find_child("Info", true, false) == null and locked_row.find_child("Lock", true, false) != null, "a locked ability: a locked icon and no description")
	s.grimoire.meta.unlock("ring_of_fire")
	gp.set_search("ring")
	var hits: Array = gp.toc_list.get_children().map(func(n): return String(n.name))
	gp.set_search("")
	check.call(hits == ["toc_ring_of_fire"] and gp.toc_list.get_child_count() == s.grimoire.listed().size(), "the search narrows the contents (%s)" % str(hits))
	gp.toc_list.find_child("toc_sage_arts", false, false).pressed.emit()
	check.call(gp.selected == "sage_arts", "clicking a row jumps to its page")
	gp.show_contents()
	check.call(gp.equip_selected("spell_1") == "no_page" and c.pcombat.loadout.spell_1 == null, "on the contents a slot click equips nothing (no page open)")
	# A / D switch the two views; equal heights [Sir].
	await tree.process_frame
	await tree.process_frame
	var book_h: float = gp.view_rect("Book").size.y
	gp.handle_key(KEY_D)
	await tree.process_frame
	await tree.process_frame
	var card_h: float = gp.view_rect("CardFace").size.y
	check.call(gp.tab == "player_id" and (gp.panel.find_child("ViewTitle", true, false) as Label).text == "Player ID" and book_h > 800.0 and absf(book_h - card_h) < 1.0, "D switches to the Player ID; the book and the card are the same height (%.0f, %.0f)" % [book_h, card_h])
	gp.handle_key(KEY_A)
	check.call(gp.tab == "grimoire", "A switches back")
	var tall := []
	var book_w := -1.0
	for pid in gp.pages(): # every page of the book keeps the same size [Sir]
		if pid == "": gp.show_contents()
		else: gp.select_page(pid)
		await tree.process_frame
		await tree.process_frame
		var r: Rect2 = gp.view_rect("Book")
		if book_w < 0.0: book_w = r.size.x
		if absf(r.size.y - card_h) >= 1.0 or absf(r.size.x - book_w) >= 1.0: tall.append("%s %.0fx%.0f" % [pid if pid != "" else "contents", r.size.x, r.size.y])
	s.grimoire.meta.unlocked.erase("quick_step")
	gp.start_assembly("quick_step")
	await tree.process_frame
	await tree.process_frame
	var ar: Rect2 = gp.view_rect("Book")
	if absf(ar.size.y - card_h) >= 1.0 or absf(ar.size.x - book_w) >= 1.0: tall.append("assembly %.0fx%.0f" % [ar.size.x, ar.size.y])
	gp.cancel_assembly()
	s.grimoire.meta.unlock("quick_step")
	check.call(tall.is_empty() and book_w > 1000.0, "every page of the book, the Code Assembly too, is the same size, the card's height %s" % str(tall))
	# The switcher is centred on the title; Close sits under the book [Sir].
	await tree.process_frame
	await tree.process_frame
	var title_r: Rect2 = gp.view_rect("ViewTitle")
	var vp_w: float = gp.panel.get_viewport_rect().size.x
	var close_r: Rect2 = gp.view_rect("Close")
	check.call(absf(title_r.get_center().x - vp_w * 0.5) < 3.0 and close_r.position.y >= gp.view_rect("Book").end.y - 0.5 and gp.panel.find_child("Switcher", true, false).find_child("Close", true, false) == null, "'< [A] Grimoire [D] >' centred; Close (Tab) at the bottom (title %.0f of %.0f; close %.0f, book end %.0f)" % [title_r.get_center().x, vp_w, close_r.position.y, gp.view_rect("Book").end.y])
	var blur: ColorRect = gp.blur
	check.call(blur != null and blur.visible and is_equal_approx(float(blur.material.get_shader_parameter("amount")), 0.5), "the world behind is blurred 50%")
	var pow: float = s.stats.value("magic_pow", s.run.time)
	var sc: Array = gp.page_stats("scorch_and_burn")
	var row := func(rows: Array, k: String) -> String:
		for r in rows: if r[0] == k: return r[1]
		return ""
	check.call(row.call(sc, "Basic fireball").begins_with("%d damage" % roundi(pow * 0.10)) and row.call(sc, "Special (RMB)").begins_with("%d damage" % roundi(pow * 0.5)) and row.call(sc, "Burn").begins_with("2 damage/s for 5 s"), "Scorch and Burn's page: its damage from Magic Pow (%s; %s)" % [row.call(sc, "Basic fireball"), row.call(sc, "Burn")])
	s.stats.points.magic_pow = 4 # +20 Pow: the numbers follow
	var sc2: Array = gp.page_stats("scorch_and_burn")
	check.call(row.call(sc2, "Basic fireball").begins_with("12 damage"), "the numbers are live: +20 Magic Pow -> %s" % row.call(sc2, "Basic fireball"))
	s.stats.points.magic_pow = 0
	var sage: Array = gp.page_stats("sage_arts")
	var ring: Array = gp.page_stats("ring_of_fire")
	check.call(row.call(sage, "Healing").begins_with("3 HP/s") and row.call(sage, "Mana").begins_with("5 MP/s") and row.call(ring, "Orbs").begins_with("6 at 3 m") and row.call(ring, "Scorched Slow").begins_with("-90%"), "Sage Arts heals 3 HP/s and 5 MP/s; Ring of Fire: 6 orbs, Scorched Slow -90%")
	gp.select_page("ring_of_fire")
	var stats_box: Control = gp.panel.find_child("PageStats", true, false)
	var labels: Array = stats_box.find_children("*", "Label", true, false).map(func(l): return l.text) if stats_box else []
	check.call(labels.has("Damage per hit") and gp.page_text("ring_of_fire").contains("Damage per hit: 15"), "the page shows its numbers as a ledger, and page_text carries them")
	var slots := ["attack", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "passive"]
	check.call(slots.all(func(sl): return gp.panel.find_child("slot_" + sl, true, false) != null), "the loadout: I Attack, II Skills, III Spells, IV Passive as slot circles")
	s.handle_action("grimoire")

	# ---- records and the card front ---------------------------------------------------------------
	s.meta.records = MetaProfile.RECORDS.duplicate()
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	sh.reset_to(Vector3(60, 0, 50), 0.0)
	sh.inert = true
	sh.health.apply(DamagePacket.new(92001, "player", "player", 37.0, "blast"), s.run.time)
	sh.health.apply(DamagePacket.new(92002, "player", "player", 12.0, "blast"), s.run.time)
	sh.health.apply(DamagePacket.new(92003, "player", "player", 500.0, "blast"), s.run.time) # applied: what was left (71)
	var rec: Dictionary = s.meta.records
	check.call(is_equal_approx(float(rec.best_hit), 71.0) and int(rec.total_kills) == 1 and int(rec.best_kills) == 1, "records: the highest damage dealt (%.0f) and kills are kept" % float(rec.best_hit))
	s.handle_action("grimoire")
	gp.show_tab("player_id")
	var lr: String = (gp.panel.find_child("LevelRank", true, false) as Label).text
	var loc: String = (gp.panel.find_child("Location", true, false) as Label).text
	var r_texts: Array = gp.panel.find_child("Records", true, false).find_children("*", "Label", true, false).map(func(l): return l.text)
	var cl: TextureRect = gp.panel.find_child("CrestLeft", true, false)
	var cr: TextureRect = gp.panel.find_child("CrestRight", true, false)
	check.call(cl != null and cl.texture != null and cr != null and cr.texture != null and (gp.panel.find_child("BandTop", true, false) as Label).text == "GUILD OF THE CRIMSONS" and (gp.panel.find_child("BandHouse", true, false) as Label).text == "House of the Pythons", "the band: the academy seal left, the House of the Pythons crest right, 'Guild of the Crimsons' and 'House of the Pythons' [Sir]")
	check.call(gp.panel.find_child("CardNo", true, false) == null and lr == "LV 1  -  RANK E" and loc.begins_with("Training Arena") and loc.ends_with("World Level 1") and gp.panel.find_child("Portrait", true, false) != null, "the card front: portrait, '%s', '%s'; no card number, no signatory" % [lr, loc])
	await tree.process_frame
	await tree.process_frame
	var front_h: float = gp.view_rect("CardFace").size.y
	var band_sb: StyleBoxFlat = (gp.panel.find_child("Band", true, false) as PanelContainer).get_theme_stylebox("panel")
	check.call(band_sb.corner_radius_top_left == 22 and band_sb.corner_radius_top_right == 22, "the band's top corners are rounded like the card")
	check.call((gp.panel.find_child("Records", true, false) as GridContainer).columns == 4, "the records sit in two columns (label and value each)")
	check.call(r_texts.has("Highest damage dealt") and r_texts.has("71") and r_texts.has("Pages unlocked") and r_texts.has("%d / %d" % [s.meta.unlocked.size(), PageLibrary.IDS.size()]) and r_texts.has("Spell chants done") and r_texts.has("Most kills in one run"), "the front lists the records (pages, kinds obtained, chants, best hit, kills...)")
	gp.handle_key(KEY_SPACE)
	await tree.process_frame
	await tree.process_frame
	var back_h: float = gp.view_rect("CardFace").size.y
	check.call(gp.card_side == "back" and gp.panel.find_child("StatTable", true, false) != null and gp.panel.find_child("raise_magic_pow", true, false) != null, "Space flips the card: the back, the stats table with a raise button per stat")
	gp.reset_stats()
	var conf: Label = gp.panel.find_child("ResetConfirm", true, false)
	check.call(conf != null and conf.text == "Press Reset stats again to confirm." and gp.status_text == "", "'press again to confirm' shows by the Reset button, not at the top")
	gp.reset_armed = false
	gp.refresh()
	gp.handle_key(KEY_SPACE)
	check.call(gp.card_side == "front" and front_h > 800.0 and absf(front_h - back_h) < 1.0, "Space flips it back; front and back are the same height")

	# ---- the chant on the card's back, with its hint ------------------------------------------------
	s.stats.unspent = 0
	var p0: Dictionary = gp.start_chant("max_hp")
	await tree.process_frame
	await tree.process_frame
	var chant_h: float = gp.view_rect("CardFace").size.y
	check.call(absf(chant_h - front_h) < 1.0 and not gp.handle_key(KEY_SPACE), "the chant card is the same height; Space does not flip it mid-chant")
	check.call(gp.card_side == "back" and gp.panel.find_child("ChantCode", true, false) != null and gp.panel.find_child("StatTable", true, false) == null and gp.panel.find_child("FlipCard", true, false) == null, "a chant takes over the card's back (code and blanks only)")
	var hb: Button = gp.panel.find_child("Hint", true, false)
	check.call(hb != null and hb.disabled and not gp.hint_ready() and gp.use_hint() == "", "the hint is locked at first")
	# A fixed code box, whatever the problem: the card never grows; the font fits the box.
	var odd := []
	var keep: Dictionary = gp.problem
	for lv in [0, 1, 2, 3, 6, 7]:
		s.meta.chant_tier["max_hp"] = lv
		gp._draw_chant()
		gp.refresh()
		await tree.process_frame
		await tree.process_frame
		var box: Control = gp.panel.find_child("ChantBox", true, false)
		var lab: Label = box.find_child("ChantCode", true, false)
		var csc: ScrollContainer = box.find_child("ChantScroll", true, false)
		if absf(gp.view_rect("CardFace").size.y - front_h) >= 1.0 or box.size != gp.chant_box_size() or csc == null or csc.size.y > box.size.y or lab.get_theme_font_size("font_size") < gp.CHANT_MIN_FONT:
			odd.append("lv%d card %s box %s want %s label %s fs %d" % [lv, str(gp.view_rect("CardFace").size), str(box.size), str(gp.chant_box_size()), str(lab.size), lab.get_theme_font_size("font_size")])
	check.call(odd.is_empty(), "every chant keeps the card's size: a fixed code box, its font fitted %s" % str(odd))
	# A question longer than the box scrolls inside it [Sir].
	gp.problem = gp.problem.duplicate()
	var long_lines: Array = []
	for k in 24: long_lines.append("total = total + (spark_power * %d)  # a long line that has to wrap" % k)
	gp.problem.lines = long_lines
	gp.refresh()
	await tree.process_frame
	await tree.process_frame
	var lsc: ScrollContainer = gp.panel.find_child("ChantScroll", true, false)
	var bar: VScrollBar = lsc.get_v_scroll_bar()
	var llab: Label = lsc.find_child("ChantCode", true, false)
	check.call(absf(gp.view_rect("CardFace").size.y - front_h) < 1.0 and llab.size.y > lsc.size.y and bar.max_value > lsc.size.y and llab.get_theme_font_size("font_size") == gp.CHANT_MIN_FONT, "a long question scrolls inside its box (text %.0f px in a %.0f px box); the card keeps its size" % [llab.size.y, lsc.size.y])
	s.meta.chant_tier["max_hp"] = 0
	gp._draw_chant()
	gp.refresh()
	p0 = gp.problem
	# Visit the Grimoire mid-chant [Sir]: nothing is cancelled, and what was typed is still there.
	var blank: LineEdit = gp.panel.find_child("blank_1", true, false)
	blank.text = "fireball"
	blank.text_changed.emit("fireball")
	gp.handle_key(KEY_D)
	var in_book: bool = gp.tab == "grimoire" and gp.mode == "chant" and gp.problem.key == p0.key
	gp.select_page("scorch_and_burn")
	gp.handle_key(KEY_RIGHT)
	var still: bool = gp.mode == "chant" and gp.problem.key == p0.key
	gp.handle_key(KEY_A)
	var back_blank: LineEdit = gp.panel.find_child("blank_1", true, false)
	check.call(in_book and still and gp.tab == "player_id" and gp.panel.find_child("ChantBox", true, false) != null and back_blank != null and back_blank.text == "fireball", "a chant survives a visit to the Grimoire (pages turned): back on the card, the same problem and the typed answer")
	steps(c, 9.8)
	var early: bool = gp.hint_ready()
	steps(c, 0.3)
	hb = gp.panel.find_child("Hint", true, false)
	var wait_l: Label = gp.panel.find_child("HintWait", true, false)
	check.call(wait_l != null and wait_l.text.begins_with("Ready"), "the hint line turns to 'Ready' by itself when the hint unlocks")
	var title: String = s.grimoire.page(String(p0.page)).title
	var said: String = gp.use_hint()
	check.call(not early and not hb.disabled and said == "Hint: study the page \"%s\" in your Grimoire." % title and gp.panel.find_child("HintText", true, false) != null, "after 10 s the hint unlocks and only names the page: '%s'" % said)
	check.call(not said.contains(String(p0.answers[0])), "the hint never gives the answer away")
	c.player.health.apply(DamagePacket.new(92010, "test", "infected", 2.0, "bite"), s.run.time)
	check.call(gp.mode == "chant" and not gp.hint_ready() and not gp.hint_shown, "a hit draws a fresh chant: its hint waits 10 s again")
	var n0: int = int(s.meta.records.chants)
	gp.submit_chant(gp.problem.answers)
	check.call(int(s.meta.records.chants) == n0 + 1, "a successful chant counts on the card")
	gp.start_chant("max_mp")
	s.handle_action("grimoire") # leaving the Player ID (closing the panel) ends the chant
	var ended: bool = gp.mode != "chant" and gp.problem.is_empty()
	s.handle_action("grimoire")
	check.call(ended and gp.mode == "browse", "closing the panel cancels a chant; the next opening is fresh")
	s.handle_action("grimoire")

	# ---- the records persist with the profile, and New game clears them ------------------------------------
	var tmp := "user://book_card_profile_test.cfg"
	s.meta.save(tmp)
	var m2 := MetaProfile.new()
	m2.load_from(tmp)
	check.call(is_equal_approx(float(m2.records.best_hit), 71.0) and m2.card_no == s.meta.card_no and int(m2.records.chants) == n0 + 1, "records and the card number are saved with the profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	m2.reset()
	check.call(float(m2.records.best_hit) == 0.0 and m2.card_no == "", "New game (a profile reset) clears the records")
	sh.health.max_hp = sh.HP
	s.meta.reset()
	s.restart()
	await tree.physics_frame
