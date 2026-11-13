extends CanvasLayer
# The Effects tab [Sir R14], on T only (not part of the Tab panel): every
# status on the player, one row each on a parchment page like the
# Grimoire's: the icon, the name, BUFF or DEBUFF, what it does in plain words
# with live numbers, and the time left counting down. "No active effects."
# when there are none. An overlay like the Grimoire: the world keeps running
# and a hit closes it (the session's overlay rule). Presentation only: main
# passes the rows (main.effect_rows()) every publish while it is open.

signal close_requested

const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const WIDTH := 760.0
const ICON := 48.0
const PARCH := Color("dccfab")
const PARCH_DEEP := Color("c9b78e")
const PLAQUE := Color("e6dbbb")
const INK := Color("3a2a1b")
const INK_SOFT := Color("6e5b42")
const LEATHER := Color("2b1d14")
const LEATHER_EDGE := Color("5c3f26")

var panel: PanelContainer
var list: VBoxContainer
var rows: Array = []          # the last rows shown (tests)
var _sig := "-"               # never a real signature: the first refresh always builds
var serif: Font
var serif_bold: Font

func _ready() -> void:
	layer = 6
	visible = false
	var base: Font = load("res://assets/fonts/EBGaramond-Variable.ttf")
	serif = _weight(base, 450)
	serif_bold = _weight(base, 700)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(LEATHER, LEATHER_EDGE, 3, 8, 14))
	add_child(panel)
	var page := PanelContainer.new()
	page.add_theme_stylebox_override("panel", _box(PARCH, PARCH_DEEP, 2, 4, 22))
	page.custom_minimum_size = Vector2(WIDTH, 0)
	panel.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	page.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := _label(head, "Effects", 26, INK, serif_bold)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close (T)"
	close.add_theme_font_override("font", serif_bold)
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", INK)
	close.add_theme_stylebox_override("normal", _box(PLAQUE, INK_SOFT, 1, 3, 6))
	close.add_theme_stylebox_override("hover", _box(Color("efe5c8"), Color("9c7a3c"), 1, 3, 6))
	close.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	col.add_child(list)

static func _weight(base: Font, wght: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
	return v

static func _box(bg: Color, border: Color, bw: int, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

func _label(parent: Control, text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l

func open() -> void:
	visible = true
	_sig = "-"

func close() -> void:
	visible = false

# rows: [{id, name, kind, text, s (time left; 0 = while a condition holds), until_text}]
func refresh(new_rows: Array) -> void:
	rows = new_rows
	var sig := ",".join(new_rows.map(func(r): return r.id))
	if sig != _sig:
		_sig = sig
		_rebuild()
	for i in rows.size():
		var r: Dictionary = rows[i]
		var line := list.get_child(i)
		(line.get_node("Time") as Label).text = time_text(r)
		(line.get_node("Body/Text") as Label).text = r.text
	panel.reset_size()
	panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()

static func time_text(r: Dictionary) -> String:
	if float(r.get("s", 0.0)) > 0.0: return "%.1f s" % float(r.s)
	return String(r.get("until_text", ""))

func _rebuild() -> void:
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	if rows.is_empty():
		var none := _label(list, "No active effects.", 18, INK_SOFT, serif)
		none.name = "Empty"
		return
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		list.add_child(line)
		var def := StatusIcons.icon(r.id)
		var tx := StatusIcons.texture(r.id)
		# The icon at a fixed size (it never draws at its file's 128 px).
		var frame := PanelContainer.new()
		frame.name = "Tile"
		frame.custom_minimum_size = Vector2(ICON, ICON)
		frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		frame.add_theme_stylebox_override("panel", _box(Color("1e1610") if tx else def.color, Color("3a2a1b"), 2, 3, 2))
		line.add_child(frame)
		if tx:
			var ic := TextureRect.new()
			ic.name = "Icon"
			ic.texture = tx
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(ICON - 6, ICON - 6)
			frame.add_child(ic)
		else:
			var g := _label(frame, def.glyph, 22, Color.WHITE, serif_bold)
			g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var body := VBoxContainer.new()
		body.name = "Body"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 0)
		line.add_child(body)
		var name_l := _label(body, "%s   %s" % [r.name, "BUFF" if r.kind == "buff" else "DEBUFF"], 19, Color("2f6b2a") if r.kind == "buff" else Color("8a2a1e"), serif_bold)
		name_l.name = "Name"
		var text := _label(body, "", 17, INK, serif)
		text.name = "Text" # one line: a wrapped label measures at width 0 before layout and balloons the panel
		text.custom_minimum_size.x = WIDTH - 230
		var t := _label(line, "", 18, INK, serif_bold)
		t.name = "Time"
		t.custom_minimum_size.x = 110
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER

# What the panel shows, as text (tests).
func shown_text() -> String:
	if rows.is_empty(): return "No active effects."
	var out := []
	for r in rows: out.append("%s|%s|%s|%s" % [r.name, r.kind, r.text, time_text(r)])
	return "\n".join(out)

func icon_size() -> Vector2:
	var f: Control = list.find_child("Tile", true, false)
	return f.size if f else Vector2.ZERO
