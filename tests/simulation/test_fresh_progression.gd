extends SceneTree
const Meta = preload("res://scripts/core/meta_profile.gd")
const Lib = preload("res://scripts/core/page_library.gd")
const Book = preload("res://scripts/core/grimoire.gd")
const Forest = preload("res://scripts/world/dark_forest.gd")
var failures := []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _initialize() -> void:
	var meta := Meta.new()
	meta.unlocked = Lib.IDS.duplicate()
	meta.reset()
	var book := Book.new(meta)
	check(book.listed() == ["scorch_and_burn", "cultivate"], "fresh reset lists exactly the two starter pages")
	var expected: Array = Lib.IDS.filter(func(id): return id not in ["scorch_and_burn", "cultivate"])
	for sd in 20:
		var m := Forest.generate(sd)
		check(not m.is_empty(), "valid map seed %d" % sd)
		if m.is_empty(): continue
		check(m.pages.size() == expected.size() and expected.all(func(id): return m.pages.has(id)), "every non-starter has a pickup seed %d" % sd)
	run.call_deferred()

func run() -> void:
	var c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = true
	c.fixed_map_seed = 60
	root.add_child(c)
	await physics_frame
	await physics_frame
	var session = c.session
	var profile := "user://test_fresh_progression.cfg"
	session.meta.path = profile
	session.meta.unlocked = Lib.IDS.duplicate()
	session.meta.save()
	session.restart()
	session.handle_action("pause")
	c.pause_menu.buttons.new_game.pressed.emit()
	check(session.meta.unlocked.size() == Lib.IDS.size(), "first wipe click only arms confirmation")
	c.pause_menu.buttons.new_game.pressed.emit()
	await physics_frame
	c.park_enemies()
	session.handle_action("grimoire")
	check(c.grimoire_panel.pages() == ["", "scorch_and_burn", "cultivate"], "Tab after confirmed wipe exposes only starters")
	session.handle_action("grimoire")
	var reloaded := Meta.new()
	check(reloaded.load_from(profile) and reloaded.unlocked == ["scorch_and_burn", "cultivate"], "saved fresh profile reload does not grant extra pages")
	var expected: Array = Lib.IDS.filter(func(id): return id not in ["scorch_and_burn", "cultivate"])
	check(c.page_pickups.size() == expected.size(), "actual world contains every collectible pickup")
	for id in expected:
		check(c.page_pickups.has(id), "pickup exists: " + id)
		if not c.page_pickups.has(id): continue
		var pickup = c.page_pickups[id]
		check(pickup.visible and not session.grimoire.is_found(id), "uncollected page visible in world, absent from book: " + id)
		check(c.pcombat.equip("spell_1", session.grimoire.page(id)) == "locked", "uncollected page cannot equip: " + id)
		check(c.nav.find_path(c.spawn.at,c.page_spots[id]).ok, "pickup reachable: " + id)
		c.player.position = c.page_spots[id]
		await physics_frame
		var result: String = c.try_interact(true)
		c.try_interact(false)
		check(result == "page" and session.grimoire.is_found(id) and not session.grimoire.is_unlocked(id) and not pickup.visible, "interaction finds but does not unlock: " + id)
	session.handle_action("grimoire")
	var gp = c.grimoire_panel
	var attempt: Dictionary = gp.start_assembly("firefly")
	check(not attempt.is_empty(), "newly scattered page can start Code Assembly")
	if not attempt.is_empty():
		for k in gp.attempt.order.size():
			var at: int = gp.attempt.order.find(k)
			if at != k:
				gp.pick(k)
				gp.pick(at)
		check(gp.submit().ok and session.grimoire.is_unlocked("firefly"), "solving the collected page unlocks it")
	session.restart()
	check(session.grimoire.is_unlocked("firefly") and not c.page_pickups.firefly.visible and not session.grimoire.is_found("explosion") and c.page_pickups.explosion.visible, "normal restart keeps unlocked pages and returns unsolved pickups")
	check(reloaded.load_from(profile) and reloaded.unlocked.has("firefly") and not reloaded.unlocked.has("explosion"), "only solved page persists to disk")
	session.meta.path = ""
	c.free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(profile + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(profile + suffix))
	print("RESULT ",JSON.stringify({"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
