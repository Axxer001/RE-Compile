extends "res://tests/render/run_render.gd"
## The Spell Chant's Unity flow [Sir, 2026-11-21]: captures only (no verdicts).
##   godot --path . res://tests/render/chant_capture.tscn -- --out=<dir>

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7
	add_child(main)
	chant.call_deferred(main)

func settle(c: Node3D, seconds: float) -> void:
	var stg: Node3D = c.grimoire_panel.stage
	var vw: Node = c.grimoire_panel.view
	for i in int(seconds * 60.0):
		if vw: vw.step(1.0 / 60.0)
		stg._process(1.0 / 60.0)
	await frame()
	await frame()

func chant(c: Node3D) -> void:
	c.park_enemies()
	var gp = c.grimoire_panel
	c.session.handle_action("grimoire")
	gp.show_tab("player_id")
	await settle(c, 2.5)
	c.session.stats.unspent = 0
	c.session.meta.chant_tier["magic_pow"] = 1
	gp.start_chant("magic_pow")
	await settle(c, 1.5)
	shot("chant-start.png")
	var decoy: String = String(gp.problem.choices.filter(func(t): return not t in gp.problem.answers)[0])
	gp.choose(decoy)
	await settle(c, 0.1)
	shot("chant-one-placed.png")
	gp.choose(decoy) # the last blank: submits, wrong
	await frame()
	shot("chant-rejected-shaking.png")
	await settle(c, 0.5)
	gp.finish_rejection()
	await settle(c, 0.3)
	shot("chant-new-problem.png")
	for a in gp.problem.answers: gp.choose(String(a))
	await frame()
	await frame()
	await frame()
	shot("chant-success-sparkle.png")
	await get_tree().create_timer(0.85).timeout
	shot("chant-success-sparkle-later.png")
	var hs: Control = gp.body.find_child("StatSparkle", true, false)
	if hs: print("CHANT sparkle parent=%s pos=%s grect=%s kids=%d a0=%.2f facerect=%s" % [hs.get_parent().name, hs.position, hs.get_global_rect(), hs.get_child_count(), (hs.get_child(0) as CanvasItem).modulate.a if hs.get_child_count() > 0 else -1.0, (gp.body.find_child("CardFace", true, false) as Control).get_global_rect()])
	else: print("CHANT no sparkle at the later shot")
	var cell: Control = gp.body.find_child("value_magic_pow", true, false)
	var lab: Label = cell.find_children("*", "Label", true, false)[0] if cell else null
	print("CHANT value=%.1f label=%s sparkle=%s" % [c.session.stats.value("magic_pow", c.session.run.time), lab.text if lab else "none", gp.body.find_child("StatSparkle", true, false) != null])
	print("CHANT done: mode=%s" % gp.mode)
	get_tree().quit()
