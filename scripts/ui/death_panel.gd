extends CanvasLayer
# End-of-night panel (ported from the 2D build). One explicit action: start
# the next night. It only emits a request; the world performs the restart.
# The button takes keyboard focus, so Enter/Space confirm.

signal next_night_requested

var panel: Control
var title: Label
var detail: Label
var button: Button
var box: VBoxContainer

func _ready() -> void:
	layer = 10
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.0, 0.0, 0.85)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(shade)
	box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 220)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	title = Label.new()
	title.text = "YOU DIED"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("e8c9c0"))
	box.add_child(title)
	detail = Label.new()
	detail.add_theme_font_size_override("font_size", 18)
	detail.add_theme_color_override("font_color", Color("b8b0aa"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(detail)
	button = Button.new()
	button.text = "Start the next night"
	button.custom_minimum_size = Vector2(240, 44)
	button.pressed.connect(func() -> void: next_night_requested.emit())
	box.add_child(button)
	hide_panel()

func show_panel(reason: String, heading := "YOU DIED", button_text := "Start the next night") -> void:
	title.text = heading
	detail.text = reason
	button.text = button_text
	# Centred on the viewport (anchors do not apply under a CanvasLayer root).
	box.reset_size()
	box.position = ((panel.get_viewport_rect().size - box.size) * 0.5).floor()
	visible = true
	button.grab_focus()

func hide_panel() -> void:
	visible = false
	if button.has_focus(): button.release_focus()
