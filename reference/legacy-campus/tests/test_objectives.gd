extends RefCounted
# R0 objectives (replaces the retired quota/van/phone tests): hacking a
# terminal recovers its file at once; the exit only completes the level with
# every file; death and restart reset the level. Also the TimeService scales.

const DT := 1.0 / 60.0
const Objectives = preload("res://scripts/core/objectives.gd")
const TimeService = preload("res://scripts/core/time_service.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k; e.keycode = k; e.pressed = true
	return e

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()

	# ---- objectives: unit rules ----------------------------------------------------
	var o := Objectives.new(1234)
	check.call(o.total() == 2 and o.count() == 0 and o.current_text() == "Recover research files 0/2", "objectives: 2 files to recover")
	check.call(o.retrieve("research_lab") and not o.retrieve("research_lab") and not o.retrieve("bogus") and o.count() == 1, "a file counts once; unknown ids refused")
	o.retrieve("research_office")
	check.call(o.has_all() and o.current_text() == "Reach the exit", "all files: reach the exit")
	o.reset()
	check.call(o.count() == 0 and not o.hints and o.seed == 1234, "reset keeps the seed, clears progress")

	# ---- time service --------------------------------------------------------------
	var ts := TimeService.new()
	check.call(ts.world_dt(0.1) == 0.1 and ts.player_dt(0.1) == 0.1, "time scales start at 1")
	ts.set_targets(0.25, 0.75)
	for i in 60: ts.tick(DT)
	check.call(absf(ts.world_scale - 0.25) < 0.005 and absf(ts.player_scale - 0.75) < 0.005 and absf(ts.world_dt(0.1) - 0.025) < 0.001, "scales ease to their targets within 1 s (%.4f, %.4f)" % [ts.world_scale, ts.player_scale])
	ts.tick(DT)
	ts.set_targets(1.0, 1.0)
	ts.tick(DT)
	check.call(ts.world_scale > 0.25 and ts.world_scale < 1.0, "scales ease, not snap")
	check.call(s.time != null and s.time.world_scale == 1.0, "the session owns a time service at scale 1")

	# ---- in the world ----------------------------------------------------------------
	c.objectives = Objectives.new(1234)
	s.restart()
	await tree.physics_frame
	c.park_enemies()

	# Exit refused without the files.
	c.player.global_position = Vector3(60, 0, 78.6)
	await tree.physics_frame
	steps(c, 0.2)
	check.call(not c.complete and c.in_extraction(c.player.global_position), "standing in the exit without the files: nothing happens")
	c.publish(0.0)
	check.call("recover every research file" in c.prompt.text, "the exit says why (%s)" % c.prompt.text)

	# Lab terminal: password from the whiteboard; the file counts at once.
	var lab: Node3D = c.terminals["terminal_lab"]
	c.open_terminal(lab)
	check.call(s.input.overlay == "terminal" and c.terminal_panel.visible, "terminal opens")
	c.terminal_panel.submitted.emit("CCS-0000")
	check.call(not lab.solved and c.objectives.count() == 0, "wrong password: no file")
	c.terminal_panel.submitted.emit(lab.password)
	check.call(lab.solved and c.objectives.count() == 1 and "FILE RECOVERED" in c.notice, "right password: FILE RECOVERED (1/2)")
	s.handle_event(key(KEY_ESCAPE))
	# Hints from the grading note.
	var office: Node3D = c.terminals["terminal_office"]
	check.call(c.terminal_view(office).hint == "", "no hint before the grading note")
	c.read_note("note_grading")
	check.call(c.objectives.hints and c.terminal_view(office).hint == office.puzzle.hint, "the grading note unlocks hints")
	c.open_terminal(office)
	c.terminal_panel.submitted.emit(str(office.puzzle.answer))
	s.handle_event(key(KEY_ESCAPE))
	check.call(c.objectives.has_all(), "both files recovered")

	# With both files: the exit completes the level.
	c.player.global_position = Vector3(60, 0, 78.6)
	await tree.physics_frame
	steps(c, 0.2)
	check.call(c.complete and c.objectives.level_complete and c.death_panel.visible and c.death_panel.title.text == "LEVEL COMPLETE" and s.input.context == InputRouter.Context.EXTRACTION, "walking into the exit with both files: LEVEL COMPLETE")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(not c.complete and c.objectives.count() == 0 and not lab.solved and s.input.context == InputRouter.Context.GAMEPLAY, "Restart level: files and terminals reset")
	check.call(not InputMap.has_action("phone") or s.input.press("phone") == "", "P no longer opens a phone overlay")
	s.restart()
	await tree.physics_frame
