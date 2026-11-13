extends RefCounted
# Settings (docs/settings-menu-plan.md): persistence, rebinding, conflicts,
# sensitivity and the settings panel's capture flow. Headless; uses its own
# config path so it never touches the player's real settings.

const Settings = preload("res://scripts/core/settings.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
const PATH := "user://test_settings.cfg"

static func key(code: int) -> Dictionary:
	return {"type": "key", "code": code}

static func run(check: Callable, c: Node) -> void:
	var s := Settings.new()
	check.call(s.bindings.jump[0] == s.defaults.jump[0] and not s.defaults.jump[0].is_empty(), "defaults captured from the InputMap")

	# Round trip.
	s.set_value("hip", 0.3)
	s.set_value("ads_mult", 0.5)
	s.set_value("invert_y", true)
	s.rebind("jump", 1, key(KEY_F9))
	check.call(s.save(PATH) == OK, "settings save")
	var t := Settings.new()
	check.call(t.load_from(PATH), "settings load")
	check.call(is_equal_approx(t.hip, 0.3) and is_equal_approx(t.ads_mult, 0.5) and t.invert_y, "values round-trip")
	check.call(t.bindings.jump[1] == key(KEY_F9), "bindings round-trip")

	# Rebind reaches the InputMap.
	var f := InputEventKey.new(); f.physical_keycode = KEY_F9; f.pressed = true
	check.call(InputMap.event_is_action(f, "jump"), "rebound key triggers its action")

	# Conflict: F is on jump; binding it to dash asks first, swap moves it.
	var dash_old: Dictionary = t.bindings.dash[0].duplicate()
	check.call(t.rebind("dash", 0, key(KEY_F9)) == "jump" and t.bindings.dash[0] == dash_old, "conflict reported, nothing bound without swap")
	t.rebind("dash", 0, key(KEY_F9), true)
	check.call(t.bindings.dash[0] == key(KEY_F9) and t.bindings.jump[1] == dash_old, "swap gives the other action the old key")
	t.clear("dash", 0)
	check.call(t.bindings.dash[0].is_empty(), "clear empties the slot")

	# Sensitivity: hip, ADS (with and without FOV scaling), invert.
	t.set_value("hip", 0.2); t.set_value("ads_mult", 0.5); t.set_value("ads_fov_scale", false)
	check.call(is_equal_approx(t.sensitivity(0.0), 0.2) and is_equal_approx(t.sensitivity(1.0), 0.1), "hip and ADS sensitivity")
	check.call(is_equal_approx(t.sensitivity(0.5), 0.15), "ADS blends with aim progress")
	t.set_value("ads_fov_scale", true)
	var ratio := tan(deg_to_rad(65.0) * 0.5) / tan(deg_to_rad(90.0) * 0.5)
	check.call(is_equal_approx(t.sensitivity(1.0, 90.0, 65.0), 0.1 * ratio), "ADS scales by zoom ratio")
	check.call(t.look_degrees(Vector2(100, 50)).y < 0.0, "invert Y flips pitch")
	t.set_value("hip", 9.0)
	check.call(is_equal_approx(t.hip, 1.0), "hip sensitivity is clamped")

	# Missing file: defaults, no error, file written (same fallback as a corrupt file).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var u := Settings.new()
	check.call(not u.load_from(PATH) and is_equal_approx(u.hip, Settings.DEFAULT_HIP), "missing file falls back to defaults")
	var reread := ConfigFile.new()
	check.call(reread.load(PATH) == OK, "missing file is written with defaults")
	# A shooter-era file (no layout version; interact on E, no Grimoire actions):
	# its mouse settings stay, its binds give way to the new defaults, and it is
	# rewritten in the new layout.
	var legacy := ConfigFile.new()
	legacy.set_value("mouse", "hip", 0.25)
	legacy.set_value("bindings", "interact", [key(KEY_E), {}])
	legacy.set_value("bindings", "reload", [key(KEY_R), {}])
	legacy.save(PATH)
	var v := Settings.new()
	check.call(v.load_from(PATH) and is_equal_approx(v.hip, 0.25) and v.bindings.interact == v.defaults.interact and v.bindings.skill_1 == v.defaults.skill_1, "an old-layout file keeps the sensitivity, not the shooter binds")
	var rewritten := ConfigFile.new()
	rewritten.load(PATH)
	check.call(int(rewritten.get_value("meta", "layout", 0)) == Settings.LAYOUT and not rewritten.has_section_key("bindings", "reload"), "and is rewritten in the Grimoire layout")
	v.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

	# Defaults come from project.godot, not the live InputMap: t's earlier
	# rebinds (F9, swaps) are in the InputMap now, a new instance must not inherit them.
	var fresh := Settings.new()
	check.call(fresh.defaults.jump[1] != key(KEY_F9) and fresh.defaults == s.defaults, "defaults ignore earlier rebinds")

	# Reset.
	t.reset()
	check.call(t.bindings == t.defaults and is_equal_approx(t.hip, Settings.DEFAULT_HIP), "reset restores defaults")

	# Panel capture flow (no real input: drive submit()).
	var p := SettingsPanel.new()
	c.add_child(p)
	p.setup(t)
	p.open()
	p._begin_capture("skill_1", 0)
	check.call(p.capturing() and p.rows.skill_1[0].text.begins_with("Press"), "panel enters capture mode")
	p.submit(key(KEY_F10))
	check.call(t.bindings.skill_1[0] == key(KEY_F10) and not p.capturing(), "panel binds the captured key")
	var jump_key: Dictionary = t.bindings.jump[0]
	p._begin_capture("skill_1", 0)
	p.submit(jump_key)
	check.call(p.swap_box.visible and t.bindings.skill_1[0] == key(KEY_F10), "panel asks before swapping")
	p._confirm_swap()
	check.call(t.bindings.skill_1[0] == jump_key and not p.swap_box.visible, "panel swap applies")
	t.reset()
	p.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
