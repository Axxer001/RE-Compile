extends RefCounted
# The Grimoire's View mode (Tab) [Sir, 2026-11-20; ported from GAME ASSETS
# "Grimoire View Mode"]: it opens on the Table of Contents with the loadout on
# the left; jumps take 1.0 s in all (one leaf per page between), manual turns
# 0.5 s; 10 s idle starts the inspection (close, covers, open, riffle back to
# the contents), a click or key cuts it short, Tab closes; the open book leans
# and looks toward the cursor on a spring, drifts and breathes; it comes out of
# the held pose and goes back. Tab [Sir, 2026-11-20]: the held book closes and
# tucks down, then the View's rises closed from the bottom middle and opens;
# closing reverses it; Grimoire <-> Player ID go down and come up there. The Player ID card is alive the same way, except
# in Chant mode. Real systems behind it: equip rules, rank, unlocks.
# The View is stepped by hand (fixed deltas) so the timings are exact.

const DT := 1.0 / 60.0
const VM = preload("res://scripts/ui/view_mode.gd")

static func run_for(v: Node, seconds: float) -> void:
	var n := int(round(seconds / DT))
	var rig = v._held_rig()
	for i in n:
		if rig != null: rig.step(DT) # the held book tucks and comes back on the same clock
		v.step(DT)

static func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e

static func click(at: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	return e

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var gp: CanvasLayer = c.grimoire_panel
	for id in ["quick_step", "ring_of_fire", "sage_arts"]: s.grimoire.find(id)
	s.meta.unlock("quick_step")
	s.meta.unlock("ring_of_fire")
	if gp.view != null: run_for(gp.view, VM.CLOSE_TOTAL_S + DT) # an earlier test's close finishes: the book is in the hand

	# ---- opening: the held book tucks away, the View's rises from the bottom middle --------------
	var rig = c.pcombat.rig
	s.handle_action("grimoire")
	var v: Node = gp.view
	run_for(v, DT)
	var first_open: float = rig.openness
	check.call(v != null and v.mode == "tuck" and rig.tucked and not v.holder.visible and first_open < 1.0 and rig.reveal >= 1.0, "Tab: the held book closes first (openness %.2f, still in the hand), the View's book is not out yet" % first_open)
	run_for(v, rig.TUCK_S + 2 * DT)
	var shut_in_hand: bool = rig.openness <= 0.0 and rig.reveal < 1.0
	run_for(v, rig.TUCK_S)
	check.call(shut_in_hand and v.mode == "equip" and rig.reveal <= 0.0, "then it tucks down out of view; only then does the View's book come (%s)" % v.mode)
	var start: Dictionary = v._pose_now()
	var bottom_px: Vector2 = v.book_cam.unproject_position(v.bottom_point())
	var vsz := Vector2(v.book_vp.size)
	var cover_up: float = (start.basis as Basis).y.normalized().dot(Vector3.UP) # the book's spine axis lies flat
	check.call(v.holder.visible and v.openness < 0.05 and (v.from_pose.pos as Vector3).distance_to(v._bottom_pose().pos) < 0.01 and absf(bottom_px.x - vsz.x * 0.5) < 2.0 and bottom_px.y > vsz.y and absf(cover_up) < 0.05, "it starts closed, lying cover up, below the bottom middle of the screen (%s of %s)" % [bottom_px, vsz])
	run_for(v, VM.RISE_S * 0.6)
	var mid_rise: float = v.openness
	run_for(v, VM.RISE_S * 0.4)
	check.call(mid_rise < 0.05 and (v._pose_now().pos as Vector3).distance_to(v._closed_pose(Vector3.ZERO, 1.0).pos) < 0.03, "it rises closed (openness %.2f mid-rise) to the centre" % mid_rise)
	run_for(v, VM.OPEN_S + DT)
	check.call(v.mode == "view" and v.openness > 0.99, "then it opens")
	check.call(v.mode == "view" and gp.selected == "" and v.current == 0 and v.right_vp.find_child("Contents", true, false) != null and v.left_vp.find_child("slot_spell_1", true, false) != null, "View opens on the Table of Contents; the left page is the loadout")
	gp.select_page("ring_of_fire")
	s.handle_action("grimoire")
	run_for(v, VM.SHUT_S + DT)
	var shut_first: bool = v.mode == "sink" and v.openness < 0.02 and rig.tucked
	run_for(v, VM.SINK_S)
	var sunk_px: Vector2 = v.book_cam.unproject_position(v.bottom_point())
	var sunk_at: bool = (v._pose_now().pos as Vector3).distance_to(v._bottom_pose().pos) < 0.01
	check.call(shut_first and sunk_at and v.mode == "untuck" and not v.holder.visible and sunk_px.y > vsz.y and not rig.tucked, "Tab closes: the book closes, goes down to the bottom middle (%s), then the held book is called back" % sunk_px)
	run_for(v, rig.TUCK_S * 0.5)
	var up_closed: bool = rig.reveal > 0.0 and rig.reveal < 1.0 and rig.openness <= 0.0
	run_for(v, rig.TUCK_S * 1.5 + DT)
	check.call(up_closed and v.mode == "held" and not v.book_layer.visible and rig.home() and rig.openness >= 1.0, "it comes back up to the hand closed, then opens")
	s.handle_action("grimoire")
	run_for(v, VM.OPEN_TOTAL_S + DT)
	check.call(gp.selected == "" and v.current == 0, "it reopens on the contents, whatever page was open")

	# ---- turn timings -------------------------------------------------------------------------
	var timings := []
	var ok_t := true
	for target in ["quick_step", "ring_of_fire", "sage_arts"]:
		gp.show_contents()
		v.flip = {}
		var n: int = gp.page_number(target)
		gp._jump_to(target)
		var leaves: int = int(v.flip.n)
		var took := 0.0
		v.step(DT) # the frame that starts it does not count
		while not v.flip.is_empty() and took < 3.0:
			v.step(DT)
			took += DT
		timings.append("%s: %d leaves %.2f s" % [target, leaves, took])
		if leaves != n or absf(took - VM.JUMP_FLIP_S) > DT * 1.5 or v.current != n: ok_t = false
	check.call(ok_t, "a contents jump flips every page between and takes 1.0 s in all (%s)" % ", ".join(timings))
	gp.flip(-1)
	var back := 0.0
	v.step(DT)
	while not v.flip.is_empty() and back < 2.0:
		v.step(DT)
		back += DT
	check.call(absf(back - VM.MANUAL_FLIP_S) < DT * 1.5 and v.current == gp.page_number(gp.selected), "a manual turn takes 0.5 s (%.2f s)" % back)

	# ---- real systems: equip from the page, the rank rule, an unlock ---------------------------
	gp.select_page("ring_of_fire")
	v.flip = {}
	v.rebuild()
	v.on_slot("spell_3")
	var rank_refused: bool = c.pcombat.loadout.spell_3 == null and gp.status_text.contains("Rank")
	s.progression.rank = "D"
	v.on_slot("spell_3")
	check.call(rank_refused and c.pcombat.loadout.spell_3 != null and String(c.pcombat.loadout.spell_3.id) == "ring_of_fire" and v.left_vp.find_child("unequip_spell_3", true, false) != null, "a slot click equips the open page under the loadout's rules (refused below its rank, then equipped)")
	v.on_unequip("spell_3")
	check.call(c.pcombat.loadout.spell_3 == null, "x unequips")
	gp.select_page("sage_arts")
	v.on_start_assembly("sage_arts")
	check.call(gp.mode == "assembly" and v.right_vp.find_child("line_0", true, false) != null and v.right_vp.find_child("Submit", true, false) != null, "a sealed page's Solve opens the real Code Assembly on the page")
	gp.attempt.order = range(gp.attempt.order.size()) # put it right (the variant's own order)
	v.on_submit()
	check.call(s.grimoire.is_unlocked("sage_arts") and gp.mode == "browse", "Submit unlocks the page (the session grimoire)")
	s.progression.rank = "E"

	# ---- idle inspection ---------------------------------------------------------------------
	gp.show_contents()
	v.flip = {}
	v._go("view")
	v.idle = 0.0
	run_for(v, VM.IDLE_AFTER_S - 0.1)
	var not_yet: bool = v.mode == "view"
	run_for(v, 0.2)
	check.call(not_yet and v.mode == "inspect", "10 s without input starts the idle inspection")
	run_for(v, VM.IN_CLOSE)
	var closed: bool = v.openness < 0.05
	run_for(v, VM.IN_FRONT + VM.IN_TURN * 0.5)
	var turning_over: bool = v.openness < 0.05 and v.holder.basis.get_scale().x < 0.95
	var done_at := -1.0
	var tt := VM.IN_CLOSE + VM.IN_FRONT + VM.IN_TURN * 0.5
	while tt < 10.0 and done_at < 0.0:
		v.step(DT)
		tt += DT
		if v.mode == "view": done_at = tt
	check.call(closed and turning_over and absf(done_at - VM.INSPECT_S) < 0.1 and v.current == 0, "the inspection closes the book, turns it over its covers, opens it and riffles back to the contents (%.2f s of %.2f)" % [done_at, VM.INSPECT_S])
	v.idle = VM.IDLE_AFTER_S
	v.step(DT)
	run_for(v, 1.0)
	gp._input(click(Vector2(400, 300)))
	var resumed: bool = v.mode == "resume"
	run_for(v, VM.RESUME_S + DT)
	check.call(resumed and v.mode == "view" and gp.visible, "a click cuts the inspection short: back to the open view")
	v.idle = VM.IDLE_AFTER_S
	v.step(DT)
	gp._input(key(KEY_LEFT))
	check.call(v.mode == "resume", "so does a key")
	run_for(v, VM.RESUME_S + DT)
	v.idle = VM.IDLE_AFTER_S
	v.step(DT)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.keycode = KEY_TAB
	ev.pressed = true
	gp._input(ev)
	check.call(not gp.visible and v.mode == "sink", "Tab during the inspection closes the Grimoire (back to the hand)")
	run_for(v, VM.CLOSE_TOTAL_S + DT)

	# ---- the open book is alive ------------------------------------------------------------------
	s.handle_action("grimoire")
	run_for(v, VM.OPEN_TOTAL_S + DT)
	var vs: Vector2 = gp.get_viewport().get_visible_rect().size
	v.cursor_override = Vector2(vs.x * 0.98, vs.y * 0.5) # far right
	run_for(v, 0.12)
	var overshoot_seen := false
	var peak := 0.0
	for i in 120:
		v.step(DT)
		peak = maxf(peak, v.alive_tilt.x)
	overshoot_seen = peak > VM.LOOK_YAW * 0.96 * 1.0 and peak > v.alive_tilt.x + 0.0005
	var right_tilt: float = v.alive_tilt.x
	var right_shift: float = v.alive_shift.x
	v.cursor_override = Vector2(vs.x * 0.5, vs.y * 0.02) # top
	run_for(v, 2.0)
	var up_tilt: float = v.alive_tilt.y
	check.call(right_tilt > VM.LOOK_YAW * 0.9 and right_shift > 0.0 and up_tilt < -VM.LOOK_PITCH * 0.8 and overshoot_seen, "the book turns to look at the cursor on a spring (right %.3f rad with a small overshoot, up %.3f) and drifts toward it" % [right_tilt, up_tilt])
	v.cursor_override = Vector2(vs.x * 0.5, vs.y * 0.5)
	run_for(v, 2.0)
	var ys := []
	for i in int(VM.BREATH_S / DT):
		v.step(DT)
		ys.append(v.alive_shift.y)
	check.call(ys.max() > 0.003 and ys.min() < -0.003, "it breathes: a slow %.1f s rise and fall" % VM.BREATH_S)
	v.cursor_override = Vector2(-1, -1)

	# ---- the Player ID card is alive, but still in Chant ------------------------------------------
	gp.show_tab("player_id")
	var st: Node3D = gp.stage
	for i in 6: st._process(DT)
	var card_waits: bool = v.mode == "sink" and st.card_in <= 0.0
	run_for(v, VM.UNEQUIP_S + DT)
	check.call(card_waits and v.mode == "away" and v.book_gone() and rig.tucked, "D: the book closes and goes down; the card waits for it (the held book stays tucked)")
	var cred0: Node3D = st.get_node("Credential")
	st._process(DT)
	var lying: float = cred0.rotation.x
	for i in int(st.CARD_IN_S / DT) + 1: st._process(DT)
	check.call(st.card_in >= 1.0 and lying < -1.2 and absf(cred0.rotation.x + 0.06) < 0.2, "then the card comes up from the bottom and flips up (%.2f -> %.2f rad)" % [lying, cred0.rotation.x])
	gp.show_tab("grimoire")
	run_for(v, DT)
	for i in 6: st._process(DT)
	var book_waits: bool = v.mode == "wait_card" and not v.holder.visible and st.card_in > 0.0
	for i in int(st.CARD_IN_S / DT) + 1: st._process(DT)
	run_for(v, DT)
	check.call(book_waits and st.card_gone() and v.mode == "equip", "A: the card goes down first; then the book comes up from there")
	run_for(v, VM.EQUIP_S + DT)
	gp.show_tab("player_id")
	run_for(v, VM.UNEQUIP_S + DT)
	for i in int(st.CARD_IN_S / DT) + 1: st._process(DT)
	st.cursor_override = Vector2(vs.x * 0.98, vs.y * 0.5)
	for i in 120: st._process(DT)
	var card_lean: float = st.card_tilt.x
	var cred: Node3D = st.get_node("Credential")
	var rot0: float = cred.rotation.y
	check.call(card_lean > 0.1 and st.card_shift.x > 0.0, "the Player ID card leans and looks toward the cursor (%.3f rad) and drifts" % card_lean)
	s.stats.unspent = 0
	gp.start_chant("magic_pow")
	for i in 90: st._process(DT)
	var still_a: Vector2 = st.card_tilt
	var shift_a: Vector3 = st.card_shift
	for i in 120: st._process(DT)
	check.call(gp.mode == "chant" and st.card_tilt.length() < 0.01 and still_a.distance_to(st.card_tilt) < 0.005 and shift_a.distance_to(st.card_shift) < 0.002 and is_equal_approx(st.card_life, 0.0), "in Chant mode the card holds still (no lean, no breath: tilt %.4f)" % st.card_tilt.length())
	gp.cancel_chant()
	for i in 60: st._process(DT)
	check.call(st.card_life > 0.9 and st.card_tilt.x > 0.05, "after the Chant it comes alive again")
	st.cursor_override = Vector2(-1, -1)
	s.handle_action("grimoire")
	run_for(v, DT)
	var card_first: bool = v.mode == "wait_card_close" and rig.tucked
	for i in int(st.CARD_IN_S / DT) + 1: st._process(DT)
	run_for(v, VM.CLOSE_TOTAL_S + DT)
	check.call(card_first and v.mode == "held" and rig.home(), "Tab on the Player ID: the card goes down, then the held book comes back")
	s.meta.reset()
	s.restart()
