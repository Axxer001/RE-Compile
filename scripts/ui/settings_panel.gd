extends CanvasLayer
# Controls settings: hip / ADS sensitivity, invert Y, keybinds.
# Click a binding, then press a key or mouse button to rebind. Esc cancels the
# capture, Backspace clears the slot. A conflict asks to swap. Changes apply
# live through Settings and are saved when the panel closes.

signal closed

const Settings = preload("res://scripts/core/settings.gd")

var settings: RefCounted
var root: Control
var rows := {}           # action -> [Button, Button]
var capture := {}        # {action, slot} while waiting for an input
var pending := {}        # {action, slot, event, other} while asking to swap
var prompt: Label
var swap_box: HBoxContainer
var hip_slider: HSlider
var volume_sliders := {} # bus key -> HSlider [Sir R7]
var ads_slider: HSlider
var hip_value: Label
var ads_value: Label
var toggles := {}
var grass_slider: HSlider
var grass_value: Label
# Graphics tab [Sir, 2026-11-14]
var tab_buttons := {}           # "controls" / "graphics" -> Button
var controls_nodes: Array = []  # the Controls & Audio rows (hidden on the Graphics tab)
var graphics_box: VBoxContainer
var gfx_widgets := {}           # gfx key -> OptionButton / CheckBox / [HSlider, Label]
var tab := "controls"
const GFX_OPTIONS := {
	"preset": [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["custom", "Custom"]],
	"window_mode": [[0, "Windowed"], [1, "Borderless fullscreen"], [2, "Exclusive fullscreen"]],
	"window_size": [[0, "1280 x 720"], [1, "1600 x 900"], [2, "1920 x 1080"], [3, "2560 x 1440"]],
	"pixel_scale": [[1, "1x (full resolution)"], [2, "2x"], [3, "3x (default)"], [4, "4x (chunkiest)"]],
	"fps_cap": [[0, "Unlimited"], [60, "60"], [120, "120"], [144, "144"], [165, "165"]],
	"shadows": [[0, "Off"], [1, "Low"], [2, "High"]],
	"effects": [[0, "Low"], [1, "Medium"], [2, "High"]],
	"film_grain": [[0, "Off"], [1, "Low"], [2, "High"]],
}

func setup(s: RefCounted) -> void:
	settings = s
	layer = 21
	visible = false
	root = PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(620, 600)
	root.position = Vector2(-310, -300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.96)
	style.set_content_margin_all(16)
	root.add_theme_stylebox_override("panel", style)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	for t in [["controls", "Controls & Audio"], ["graphics", "Graphics"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.toggle_mode = true
		tb.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(tb)
		tab_buttons[t[0]] = tb
	col.add_child(tabs)
	var first_control := col.get_child_count()

	var hs := _slider_row(col, "Mouse sensitivity (°/px)", 0.01, 1.0, 0.005)
	hip_slider = hs[0]; hip_value = hs[1]
	hip_slider.value_changed.connect(func(v): settings.set_value("hip", v); _refresh_values())
	var as_ := _slider_row(col, "ADS sensitivity (× hip)", 0.1, 2.0, 0.05)
	ads_slider = as_[0]; ads_value = as_[1]
	ads_slider.value_changed.connect(func(v): settings.set_value("ads_mult", v); _refresh_values())
	for key in [["ads_fov_scale", "Scale ADS by zoom"], ["invert_y", "Invert Y"], ["damage_numbers", "Damage numbers"], ["infinite_mana", "Infinite Mana + No Cooldown (testing)"]]:
		var c := CheckBox.new()
		c.text = key[1]
		c.toggled.connect(func(on): settings.set_value(key[0], on))
		col.add_child(c)
		toggles[key[0]] = c

	for k in [["master", "Master volume"], ["music", "Music"], ["ambience", "Ambience"], ["sfx", "Effects"], ["ui", "Interface"]]:
		var vr := _slider_row(col, k[1], 0.0, 1.0, 0.05)
		volume_sliders[k[0]] = vr[0]
		var key: String = k[0]
		vr[0].value_changed.connect(func(v): settings.set_value("vol_" + key, v))

	prompt = Label.new()
	prompt.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	col.add_child(prompt)
	swap_box = HBoxContainer.new()
	var yes := Button.new(); yes.text = "Swap"; yes.pressed.connect(_confirm_swap)
	var no := Button.new(); no.text = "Cancel"; no.pressed.connect(_cancel_pending)
	swap_box.add_child(yes); swap_box.add_child(no)
	swap_box.visible = false
	col.add_child(swap_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	scroll.add_child(grid)
	for action in Settings.ACTIONS:
		var l := Label.new()
		l.text = Settings.LABELS.get(action, action)
		l.custom_minimum_size = Vector2(200, 0)
		grid.add_child(l)
		var pair := []
		for slot in Settings.SLOTS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(160, 30)
			b.pressed.connect(_begin_capture.bind(action, slot))
			grid.add_child(b)
			pair.append(b)
		rows[action] = pair

	for i in range(first_control, col.get_child_count()): controls_nodes.append(col.get_child(i))
	_build_graphics(col)
	var bottom := HBoxContainer.new()
	var reset := Button.new(); reset.text = "Reset to defaults"
	reset.pressed.connect(func(): settings.reset(); refresh())
	var back := Button.new(); back.text = "Back"; back.pressed.connect(close)
	bottom.add_child(reset); bottom.add_child(back)
	col.add_child(bottom)
	refresh()

func _build_graphics(col: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "GraphicsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 460)
	col.add_child(scroll)
	graphics_box = VBoxContainer.new()
	graphics_box.name = "Graphics"
	graphics_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_box.add_theme_constant_override("separation", 6)
	scroll.add_child(graphics_box)
	scroll.visible = false
	_option_row("preset", "Quality preset")
	_heading("Display")
	_option_row("window_mode", "Window mode")
	_option_row("window_size", "Window size (windowed)")
	_option_row("pixel_scale", "Pixel scale (3D resolution)")
	_check_row("vsync", "VSync")
	_option_row("fps_cap", "Frame rate cap")
	_gfx_slider("fov", "Field of view (deg)", 70.0, 110.0, 1.0)
	_heading("Quality")
	_option_row("shadows", "Shadows")
	_check_row("volumetric_fog", "Volumetric fog")
	_gfx_slider("tree_distance", "Tree detail distance (m)", 20.0, 60.0, 5.0)
	_gfx_slider("grass_distance", "Grass distance (m)", 20.0, 120.0, 5.0)
	_option_row("effects", "Spell effects quality")
	_heading("Look and comfort")
	_check_row("colour16", "16-bit colour")
	_option_row("film_grain", "Film grain")
	_check_row("camera_shake", "Camera shake")

func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	graphics_box.add_child(l)

func _option_row(key: String, text: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = text; l.custom_minimum_size = Vector2(240, 0)
	var ob := OptionButton.new()
	ob.name = "gfx_" + key
	ob.custom_minimum_size = Vector2(260, 28)
	for i in GFX_OPTIONS[key].size(): ob.add_item(String(GFX_OPTIONS[key][i][1]), i)
	ob.item_selected.connect(func(i: int) -> void:
		settings.set_value("gfx_" + key, GFX_OPTIONS[key][i][0])
		refresh())
	row.add_child(l); row.add_child(ob)
	graphics_box.add_child(row)
	gfx_widgets[key] = ob

func _check_row(key: String, text: String) -> void:
	var c := CheckBox.new()
	c.name = "gfx_" + key
	c.text = text
	c.toggled.connect(func(on: bool) -> void:
		settings.set_value("gfx_" + key, on)
		refresh())
	graphics_box.add_child(c)
	gfx_widgets[key] = c

func _gfx_slider(key: String, text: String, lo: float, hi: float, step: float) -> void:
	var sv := _slider_row(graphics_box, text, lo, hi, step)
	sv[0].name = "gfx_" + key
	sv[0].value_changed.connect(func(v: float) -> void:
		settings.set_value("grass_distance" if key == "grass_distance" else "gfx_" + key, v)
		refresh())
	gfx_widgets[key] = sv

func show_tab(which: String) -> void:
	tab = which
	for n in controls_nodes: n.visible = which == "controls"
	if graphics_box: graphics_box.get_parent().visible = which == "graphics"
	for k in tab_buttons: tab_buttons[k].set_pressed_no_signal(k == which)

func _refresh_graphics() -> void:
	for key in gfx_widgets:
		var v = settings.gfx_value(key)
		var w = gfx_widgets[key]
		if w is OptionButton:
			var opts: Array = GFX_OPTIONS[key]
			for i in opts.size():
				if opts[i][0] == v: (w as OptionButton).select(i)
		elif w is CheckBox: (w as CheckBox).set_pressed_no_signal(bool(v))
		elif w is Array:
			(w[0] as HSlider).set_value_no_signal(float(v))
			(w[1] as Label).text = "%d" % int(v)

func _slider_row(parent: Node, text: String, lo: float, hi: float, step: float) -> Array:
	var row := HBoxContainer.new()
	var l := Label.new(); l.text = text; l.custom_minimum_size = Vector2(220, 0)
	var s := HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = step
	s.custom_minimum_size = Vector2(260, 24); s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := Label.new(); v.custom_minimum_size = Vector2(60, 0)
	row.add_child(l); row.add_child(s); row.add_child(v)
	parent.add_child(row)
	return [s, v]

func open() -> void:
	refresh()
	show_tab(tab)
	visible = true

func close() -> void:
	if not visible: return
	capture = {}
	_cancel_pending()
	visible = false
	if settings: settings.save()
	closed.emit()

func capturing() -> bool:
	return visible and not capture.is_empty()

func refresh() -> void:
	hip_slider.set_value_no_signal(settings.hip)
	ads_slider.set_value_no_signal(settings.ads_mult)
	if grass_slider: grass_slider.set_value_no_signal(settings.grass_distance)
	for k in volume_sliders: volume_sliders[k].set_value_no_signal(settings.volumes[k])
	for k in toggles: toggles[k].set_pressed_no_signal(settings.get(k))
	_refresh_values()
	for action in rows:
		for slot in Settings.SLOTS:
			var b: Button = rows[action][slot]
			b.text = "Press a key…" if capture == {"action": action, "slot": slot} else Settings.describe(settings.bindings[action][slot])
	if capture.is_empty() and pending.is_empty(): prompt.text = "Click a binding to change it."
	_refresh_graphics()

func _refresh_values() -> void:
	hip_value.text = "%.3f" % settings.hip
	ads_value.text = "%.2f×" % settings.ads_mult
	if grass_value: grass_value.text = "%d m" % int(settings.grass_distance)

func _begin_capture(action: String, slot: int) -> void:
	if not pending.is_empty(): return
	capture = {"action": action, "slot": slot}
	prompt.text = "Press a key or mouse button for %s. Esc cancels, Backspace clears." % Settings.LABELS.get(action, action)
	refresh()

func _input(event: InputEvent) -> void:
	if not capturing(): return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	var is_mouse: bool = event is InputEventMouseButton and event.pressed
	if not (is_key or is_mouse): return
	get_viewport().set_input_as_handled()
	if is_key and event.physical_keycode == KEY_ESCAPE:
		capture = {}; refresh(); return
	if is_key and event.physical_keycode == KEY_BACKSPACE:
		settings.clear(capture.action, capture.slot); capture = {}; refresh(); return
	submit(Settings.encode(event))

# Binds the captured slot to `ev` (a Settings event dict); asks to swap on conflict.
func submit(ev: Dictionary) -> void:
	if capture.is_empty() or ev.is_empty(): return
	var other: String = settings.rebind(capture.action, capture.slot, ev, false)
	if other != "":
		pending = {"action": capture.action, "slot": capture.slot, "event": ev}
		prompt.text = "%s is already bound to %s. Swap?" % [Settings.describe(ev), Settings.LABELS.get(other, other)]
		swap_box.visible = true
	capture = {}
	refresh()

func _confirm_swap() -> void:
	if pending.is_empty(): return
	settings.rebind(pending.action, pending.slot, pending.event, true)
	_cancel_pending()
	refresh()

func _cancel_pending() -> void:
	pending = {}
	if swap_box: swap_box.visible = false
	if prompt: prompt.text = "Click a binding to change it."
