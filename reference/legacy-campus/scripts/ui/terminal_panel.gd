extends CanvasLayer
# Hacking terminal overlay. Shows a password prompt or a "which line is
# wrong?" code listing; issues `submitted(answer)` and `close_requested`; it
# never decides right or wrong (the world does) and only shows what it is told.

signal submitted(answer: String)
signal close_requested

var panel: PanelContainer
var title: Label
var body: Label
var hint: Label
var status: Label
var password: LineEdit
var options: Array[Button] = []
var option_box: HBoxContainer
var close_button: Button

const WIDTH := 760.0
const MARGIN := 18.0

func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.03, 0.96)
	style.border_color = Color(0.3, 0.8, 0.45)
	style.set_border_width_all(2)
	style.set_content_margin_all(MARGIN)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var mono: Font = load("res://assets/fonts/JetBrainsMono-Regular.ttf")
	title = _label(box, mono, 22, Color(0.55, 1.0, 0.65))
	body = _label(box, mono, 18, Color(0.75, 0.95, 0.8))
	hint = _label(box, mono, 15, Color(0.95, 0.85, 0.45))
	password = LineEdit.new()
	password.add_theme_font_override("font", mono)
	password.placeholder_text = "password"
	password.text_submitted.connect(func(t: String) -> void: submitted.emit(t))
	box.add_child(password)
	option_box = HBoxContainer.new()
	option_box.add_theme_constant_override("separation", 12)
	box.add_child(option_box)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 40)
		b.add_theme_font_override("font", mono)
		b.pressed.connect(func() -> void: submitted.emit(str(i)))
		option_box.add_child(b)
		options.append(b)
	status = _label(box, mono, 16, Color(1.0, 0.55, 0.45))
	close_button = Button.new()
	close_button.text = "Log out (Esc)"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	box.add_child(close_button)
	visible = false

func _label(parent: Control, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapped label measures its height at its current width; before the
	# first layout that is ~0, so every character wrapped and the panel asked
	# for thousands of pixels (the code listing sat off-screen). Give it the
	# content width up front.
	l.custom_minimum_size.x = WIDTH - 2.0 * MARGIN
	parent.add_child(l)
	return l

# view: {label, kind, lines?, options?, hint (or ""), status, solved, locked}
# Centred on the viewport (anchors do not apply directly under a CanvasLayer).
func _centre() -> void:
	panel.reset_size()
	panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()

func open(view: Dictionary) -> void:
	refresh(view)
	_centre()
	visible = true
	if view.kind == "password": password.grab_focus()
	else: options[0].grab_focus()

func refresh(view: Dictionary) -> void:
	title.text = "%s  //  %s" % [view.label, "ACCESS GRANTED" if view.solved else "LOGIN"]
	var is_pw: bool = view.kind == "password"
	password.visible = is_pw and not view.solved
	option_box.visible = not is_pw and not view.solved
	if is_pw:
		body.text = "Restricted system. Enter the administrator password."
	else:
		var lines: Array = view.lines
		var text := String(view.get("title", "")) + "\n\n"
		for i in lines.size(): text += "%2d  %s\n" % [i + 1, lines[i]]
		text += "\nWhich line is wrong?"
		body.text = text
		for i in 3: options[i].text = "%d) line %d" % [i + 1, view.options[i]]
	hint.text = ("HINT: " + view.hint) if view.hint != "" else ""
	status.text = view.status
	for b in options: b.disabled = view.locked
	password.editable = not view.locked
	if view.solved: body.text = "FILE RECOVERED."
	if visible: _centre() # the text changed: size and centre again

func close() -> void:
	visible = false
	password.text = ""
	var f := panel.get_viewport().gui_get_focus_owner() if panel.is_inside_tree() else null
	if f != null and panel.is_ancestor_of(f): f.release_focus()
