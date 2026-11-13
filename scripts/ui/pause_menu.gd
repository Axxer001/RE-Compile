extends CanvasLayer
# Esc pause menu: Resume / Settings / Restart run / New game (wipe progress) /
# Quit. UI only: the world wires the signals (resume -> GameSession unpause,
# restart -> a new run that keeps the meta profile, new_game -> wipe the meta
# profile and start from zero [Sir R12], quit). New game needs a second
# click to confirm; anything else disarms it.
# Opens the settings panel itself.

signal resume_requested
signal restart_requested
signal new_game_requested
signal quit_requested

const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

var root: Control
var buttons := {}
var panel: CanvasLayer
var wipe_armed := false
const WIPE_TEXT := "New game (wipe progress)"
const WIPE_CONFIRM := "Confirm: wipe pages, rank and chant tiers"

func setup(settings: RefCounted) -> void:
	layer = 20 # above HUD (1), inventory/terminal (6), death (10)
	visible = false
	root = ColorRect.new()
	(root as ColorRect).color = Color(0, 0, 0, 0.6)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(260, 0)
	box.position = Vector2(-130, -110)
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	for id in ["resume", "settings", "restart", "new_game", "quit"]:
		var b := Button.new()
		b.text = {"restart": "Restart run", "new_game": WIPE_TEXT}.get(id, id.capitalize())
		b.custom_minimum_size = Vector2(260, 40)
		b.pressed.connect(_on.bind(id))
		box.add_child(b)
		buttons[id] = b
	panel = SettingsPanel.new()
	add_child(panel)
	panel.setup(settings)
	panel.closed.connect(func(): root.visible = true)

func open() -> void:
	_disarm()
	visible = true
	root.visible = true
	panel.close()
	buttons.resume.grab_focus()

func close() -> void:
	panel.close()
	visible = false

func is_capturing() -> bool:
	return panel != null and panel.capturing()

# Esc while open: leave settings first, then resume.
func back() -> void:
	if panel.visible: panel.close()
	else: _on("resume")

func _disarm() -> void:
	wipe_armed = false
	if buttons.has("new_game"): buttons.new_game.text = WIPE_TEXT

func _on(id: String) -> void:
	if id != "new_game": _disarm()
	match id:
		"new_game":
			if not wipe_armed:
				wipe_armed = true
				buttons.new_game.text = WIPE_CONFIRM
				return
			_disarm()
			close()
			new_game_requested.emit()
		"resume": close(); resume_requested.emit()
		"settings": root.visible = false; panel.open()
		"restart": close(); restart_requested.emit()
		"quit": quit_requested.emit()
