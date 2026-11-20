extends RefCounted
## The Grimoire's View-mode pages [Sir, 2026-11-20], ported from the GAME ASSETS
## "Grimoire View Mode" preview (page_ui.gd). One Control per page, drawn into a
## SubViewport and shown on the 3D book (view_mode.gd). The host (view_mode.gd)
## answers from the real systems: the session grimoire, the loadout and its
## equip rules, the rank, page_stats and the Code Assembly. Same paper, ink, gold rules and fonts
## as the Held grimoire's page ink (EB Garamond + Archivo), with every block of
## the current Tab grimoire kept: the loadout (left page, always), the Table of
## Contents (search, type filter, every page with icon / short line / page
## number / seal), and each ability page (kind, rank, page n of m, description,
## live numbers, special, incantation, lesson, tip; sealed pages show their
## topic and the Code Assembly).

const W := 860
const H := 1248
const PAPER := Color("#eadaaf")
const PAPER_DEEP := Color("#d9c597")
const INK := Color("#33291e")
const FAINT := Color("#715e44")
const GOLD := Color("#997243")
const RED := Color("#923d2c")
const COLORS := [Color("#923d2c"), Color("#ae5526"), Color("#36685e"), Color("#5f547b"), Color("#6b5a2e")]
const ROMAN := ["I", "II", "III", "IV", "V"]
const KIND_WORD := ["ATTACK", "SKILL", "SPELL", "PASSIVE"]
const KIND_COLOR := [Color("#923d2c"), Color("#36685e"), Color("#5f547b"), Color("#6b5a2e")]
const KIND_FILTERS := [[-1, "All types"], [0, "Attacks"], [1, "Skills"], [2, "Spells"], [3, "Passives"]]
const SLOTS := ["spell_1", "spell_2", "spell_3", "spell_4", "passive"]
const SIDE := 74            # inner margin left / right
const TOP := 168            # below the header rule
const BOTTOM := 118         # above the footer

static var serif: Font
static var serif_bold: Font
static var serif_italic: Font
static var sans: Font
static var sans_bold: Font
static var mono: Font

static func fonts() -> void:
	if serif != null: return
	var garamond: Font = load("res://assets/fonts/EBGaramond-Variable.ttf")
	var archivo: Font = load("res://assets/fonts/Archivo-Variable.ttf")
	serif = _weight(garamond, 420)
	serif_bold = _weight(garamond, 700)
	serif_italic = _weight(garamond, 420, 0.18)
	sans = _weight(archivo, 500)
	sans_bold = _weight(archivo, 700)
	mono = load("res://assets/fonts/JetBrainsMono-Regular.ttf")

static func _weight(f: Font, w: int, slant := 0.0) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = f
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): w}
	if slant != 0.0: v.variation_transform = Transform2D(Vector2(1, 0), Vector2(slant, 1), Vector2.ZERO)
	return v

# ---------------------------------------------------------------- the paper

## The page itself: parchment, a burnt edge, the gold frame, the running header
## and the folio line at the foot (as the Held grimoire's ink draws them).
class Paper extends Control:
	var header := "FIELD GRIMOIRE"
	var footer := ""
	var accent := Color("#997243")
	func _draw() -> void:
		draw_rect(Rect2(0, 0, size.x, size.y), Color("#eadaaf"))
		for j in 24: draw_rect(Rect2(j, j, size.x - j * 2, size.y - j * 2), Color(0.43, 0.31, 0.14, 0.20 - j * 0.0082), false, 1.2)
		draw_rect(Rect2(36, 36, size.x - 72, size.y - 72), Color("#997243"), false, 2.2)
		draw_rect(Rect2(46, 46, size.x - 92, size.y - 92), Color(0.6, 0.45, 0.26, 0.45), false, 1.0)
		var f: Font = load("res://scripts/ui/view_pages.gd").sans_bold
		draw_string(f, Vector2(0, 112), header, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("#715e44"))
		_rule(140)
		_rule(size.y - 104)
		var s: Font = load("res://scripts/ui/view_pages.gd").serif_italic
		draw_string(s, Vector2(0, size.y - 60), footer, HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color("#715e44"))
	func _rule(y: float) -> void:
		draw_line(Vector2(74, y), Vector2(size.x - 74, y), Color("#997243"), 2.6, true)
		var p := Vector2(size.x / 2, y)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-11, 0), p + Vector2(0, -7), p + Vector2(11, 0), p + Vector2(0, 7)]), Color("#997243"))

## A thin gold rule with the diamond, for inside the page body.
class Rule extends Control:
	var width := 600.0
	func _init(w := 600.0) -> void:
		width = w
		custom_minimum_size = Vector2(w, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var y := size.y / 2
		var x0 := (size.x - width) / 2
		draw_line(Vector2(x0, y), Vector2(x0 + width, y), Color("#997243"), 2.0, true)
		var p := Vector2(size.x / 2, y)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 0), p + Vector2(0, -5), p + Vector2(8, 0), p + Vector2(0, 5)]), Color("#997243"))

## The slot medallion: a gold-ringed disc, the page's colour arc, its icon.
class Medallion extends Control:
	var tex: Texture2D
	var ring := Color("#997243")
	var lit := false
	var dim := false
	var radius := 70.0
	func _draw() -> void:
		var c := size / 2
		if lit: for k in 6: draw_circle(c, radius + 16 - k * 2, Color(0.95, 0.75, 0.35, 0.10))
		draw_circle(c, radius, Color("#1e1610") if tex else Color("#e3d2a5"))
		draw_arc(c, radius, 0, TAU, 72, ring, 5.0, true)
		draw_arc(c, radius - 9, 0, TAU, 72, Color("#997243"), 1.4, true)
		if tex:
			var s := radius * 1.32
			draw_texture_rect(tex, Rect2(c - Vector2(s, s) / 2, Vector2(s, s)), false, Color(1, 1, 1, 0.45 if dim else 1.0))
		else:
			draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), Color("#b5a17c"), 3.0, true)
			draw_line(c + Vector2(0, -14), c + Vector2(0, 14), Color("#b5a17c"), 3.0, true)

## A small drawn padlock over a sealed page's icon.
class Lock extends Control:
	func _draw() -> void:
		var c := size / 2 + Vector2(0, 6)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.09, 0.06, 0.55))
		draw_arc(c + Vector2(0, -12), 11, PI, TAU, 14, Color("#e6dbbb"), 4.0, true)
		draw_rect(Rect2(c + Vector2(-15, -10), Vector2(30, 23)), Color("#e6dbbb"))
		draw_circle(c + Vector2(0, 1), 3.5, Color("#33291e"))

# ---------------------------------------------------------------- helpers

static func _box(bg: Color, border: Color, bw := 1, radius := 4, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s

static func label(parent: Control, text: String, font: Font, px: int, color := INK, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func gap(parent: Control, px: float) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)

static func link(parent: Control, text: String, px := 30, color := INK) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", serif_bold)
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", RED)
	b.add_theme_color_override("font_pressed_color", RED)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(b)
	return b

static func plate(parent: Control, text: String, px := 26) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", sans_bold)
	b.add_theme_font_size_override("font_size", px)
	b.add_theme_color_override("font_color", Color("#f1e6c8"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color("#5a2f26"), GOLD, 2, 6, 14))
	b.add_theme_stylebox_override("hover", _box(Color("#7a3a2c"), Color("#d2a55c"), 2, 6, 14))
	b.add_theme_stylebox_override("pressed", _box(Color("#4a2620"), GOLD, 2, 6, 14))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(b)
	return b

static func section(parent: Control, roman: String, text: String, color: Color) -> void:
	var l := label(parent, "%s   ·   %s" % [roman, text], sans_bold, 28, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("line_spacing", 0)

static func icon(src) -> Texture2D:
	if src is Texture2D: return src
	return null

static func paper(header: String, footer: String) -> Array:
	fonts()
	var root := Paper.new()
	root.header = header
	root.footer = footer
	root.size = Vector2(W, H)
	root.custom_minimum_size = Vector2(W, H)
	var body := VBoxContainer.new()
	body.position = Vector2(SIDE, TOP)
	body.size = Vector2(W - SIDE * 2, H - TOP - BOTTOM)
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	return [root, body]

# ---------------------------------------------------------------- left page: loadout

static func loadout(host: Node) -> Control:
	var pr := paper("FIELD GRIMOIRE", "Loadout")
	var root: Control = pr[0]
	var col: VBoxContainer = pr[1]
	label(col, "Loadout", serif, 70, INK, HORIZONTAL_ALIGNMENT_CENTER)
	var sel: Dictionary = host.selected_page()
	var hint := "Open an ability's page, then click a slot to equip it."
	if not sel.is_empty():
		hint = ("Click a slot to equip " + sel.title + ".") if host.is_unlocked(sel.id) else (sel.title + " is sealed: solve it to equip it.")
	var note: String = host.notice
	label(col, note if note != "" else hint, serif_italic, 27, RED if note != "" else FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	gap(col, 6)
	col.add_child(Rule.new(560))
	section(col, "I", "SPELLS", COLORS[0])
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 46)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	for i in 4: _slot(grid, host, SLOTS[i], i)
	gap(col, 4)
	col.add_child(Rule.new(560))
	section(col, "II", "PASSIVE", COLORS[4])
	var c := CenterContainer.new()
	col.add_child(c)
	_slot(c, host, "passive", 4)
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fill)
	return root

static func _slot(parent: Control, host: Node, slot: String, i: int) -> void:
	var pg: Dictionary = host.page_by_id(host.loadout.get(slot, ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.custom_minimum_size = Vector2(290, 0)
	parent.add_child(box)
	var b := Button.new()
	b.name = "slot_" + slot
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 140)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	b.pressed.connect(host.on_slot.bind(slot))
	box.add_child(b)
	var m := Medallion.new()
	m.tex = icon(pg.get("icon", "")) if not pg.is_empty() else null
	m.ring = COLORS[i]
	m.lit = host.can_equip_selected(slot)
	m.size = Vector2(150, 140)
	m.radius = 58.0
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	b.mouse_entered.connect(func() -> void: m.ring = RED; m.queue_redraw())
	b.mouse_exited.connect(func() -> void: m.ring = COLORS[i]; m.queue_redraw())
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 10)
	box.add_child(foot)
	label(foot, "[%s]  %s" % ["5" if slot == "passive" else str(i + 1), ROMAN[i]], sans_bold, 24, COLORS[i], HORIZONTAL_ALIGNMENT_CENTER, false)
	if not pg.is_empty():
		var x := link(foot, "×", 30, RED)
		x.name = "unequip_" + slot
		x.tooltip_text = "Unequip"
		x.pressed.connect(host.on_unequip.bind(slot))
	label(box, pg.get("title", "Empty page"), serif if not pg.is_empty() else serif_italic, 28, INK if not pg.is_empty() else FAINT, HORIZONTAL_ALIGNMENT_CENTER)

# ---------------------------------------------------------------- right page: contents

static func contents(host: Node) -> Control:
	var pr := paper("FIELD GRIMOIRE", "Contents")
	var root: Control = pr[0]
	var col: VBoxContainer = pr[1]
	label(col, "Table of Contents", serif, 70, INK, HORIZONTAL_ALIGNMENT_CENTER)
	label(col, "%d of %d pages unlocked" % [host.unlocked_count(), host.pages.size()], serif_italic, 26, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	gap(col, 4)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	col.add_child(bar)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search the Grimoire..."
	search.text = host.toc_query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_override("font", serif)
	search.add_theme_font_size_override("font_size", 28)
	search.add_theme_color_override("font_color", INK)
	search.add_theme_color_override("font_placeholder_color", Color(FAINT, 0.75))
	search.add_theme_color_override("caret_color", INK)
	search.add_theme_stylebox_override("normal", _box(Color("#efe4c4"), Color(FAINT, 0.7), 2, 5, 14))
	search.add_theme_stylebox_override("focus", _box(Color("#f4ebd2"), GOLD, 2, 5, 14))
	search.text_changed.connect(host.on_search)
	bar.add_child(search)
	var kf := OptionButton.new()
	kf.name = "TypeFilter"
	kf.focus_mode = Control.FOCUS_NONE
	for f in KIND_FILTERS: kf.add_item(String(f[1]), int(f[0]) + 1)
	kf.select(host.toc_kind + 1)
	kf.add_theme_font_override("font", serif)
	kf.add_theme_font_size_override("font_size", 26)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: kf.add_theme_color_override(k, INK)
	kf.add_theme_stylebox_override("normal", _box(Color("#efe4c4"), Color(FAINT, 0.7), 2, 5, 14))
	kf.add_theme_stylebox_override("hover", _box(Color("#f4ebd2"), GOLD, 2, 5, 14))
	kf.add_theme_stylebox_override("pressed", _box(Color("#f4ebd2"), GOLD, 2, 5, 14))
	kf.custom_minimum_size = Vector2(230, 0)
	var popup := kf.get_popup()
	popup.add_theme_font_override("font", serif)
	popup.add_theme_font_size_override("font_size", 26)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", RED)
	popup.add_theme_stylebox_override("panel", _box(Color("#efe4c4"), GOLD, 2, 5, 8))
	popup.add_theme_stylebox_override("hover", _box(Color("#dfcfa2"), Color(0, 0, 0, 0), 0, 3, 4))
	kf.item_selected.connect(func(i: int) -> void: host.on_kind(int(KIND_FILTERS[i][0])))
	bar.add_child(kf)
	gap(col, 4)
	var scroll := ScrollContainer.new()
	scroll.name = "ContentsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "Contents"
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	host.toc_list = list
	fill_toc(host, list)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill)
	var nxt := link(foot, "Next page  ›", 30)
	nxt.name = "NextPage"
	nxt.pressed.connect(host.manual_flip.bind(1))
	return root

static func fill_toc(host: Node, list: VBoxContainer) -> void:
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	var ids: Array = host.toc_ids()
	if ids.is_empty():
		label(list, "No pages found.", serif_italic, 28, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		return
	for id in ids:
		var pg: Dictionary = host.page_by_id(id)
		var open: bool = host.is_unlocked(id)
		var b := Button.new()
		b.name = "toc_" + id
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 100)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.10), Color(PAPER_DEEP, 0.9), 1, 4, 0))
		b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.26), GOLD, 2, 4, 0))
		b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.34), GOLD, 2, 4, 0))
		b.pressed.connect(host.jump_to.bind(host.index_of(id)))
		list.add_child(b)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 18)
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -16
		row.offset_top = 10
		row.offset_bottom = -10
		b.add_child(row)
		var tile := TextureRect.new()
		tile.texture = icon(pg.icon)
		tile.custom_minimum_size = Vector2(80, 80)
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.modulate = Color(1, 1, 1, 1.0 if open else 0.55)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tile)
		if not open:
			var lock := Lock.new()
			lock.name = "Lock"
			lock.set_anchors_preset(Control.PRESET_FULL_RECT)
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(lock)
		var mid := VBoxContainer.new()
		mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_theme_constant_override("separation", -2)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(mid)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 12)
		mid.add_child(top)
		label(top, pg.title, serif_bold, 33, INK if open else FAINT, HORIZONTAL_ALIGNMENT_LEFT, false)
		label(top, KIND_WORD[int(pg.kind_i)], sans_bold, 18, KIND_COLOR[int(pg.kind_i)], HORIZONTAL_ALIGNMENT_LEFT, false).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var info := label(mid, pg.short if open else "Sealed - solve its Code Assembly", serif if open else serif_italic, 23, FAINT)
		if open: info.name = "Info" # a sealed row shows no description
		var pn := label(row, "p. %d" % host.index_of(id), serif_bold, 29, INK, HORIZONTAL_ALIGNMENT_RIGHT, false)
		pn.name = "PageNo"
		pn.custom_minimum_size.x = 76
		pn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

# ---------------------------------------------------------------- right page: one ability

static func ability(host: Node, idx: int) -> Control:
	var pg: Dictionary = host.page_at(idx)
	var open: bool = host.is_unlocked(pg.id)
	var kind := int(pg.kind_i)
	var pr := paper("FIELD GRIMOIRE", "p. %d" % idx)
	var root: Control = pr[0]
	(root as Paper).accent = KIND_COLOR[kind]
	var col: VBoxContainer = pr[1]
	var top := HBoxContainer.new()
	col.add_child(top)
	label(top, KIND_WORD[kind] + "  ·  RANK " + String(pg.rank), sans_bold, 24, KIND_COLOR[kind], HORIZONTAL_ALIGNMENT_LEFT)
	label(top, "Page %d of %d" % [idx, host.pages.size()], sans, 22, FAINT, HORIZONTAL_ALIGNMENT_RIGHT)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	col.add_child(head)
	var med := Medallion.new()
	med.tex = icon(pg.icon)
	med.dim = not open
	med.radius = 58
	med.ring = KIND_COLOR[kind]
	med.custom_minimum_size = Vector2(136, 136)
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(med)
	var meta := VBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_theme_constant_override("separation", -4)
	head.add_child(meta)
	label(meta, pg.title, serif, 60 if String(pg.title).length() <= 16 else 48)
	var rank_ok: bool = host.rank_ok(pg.rank)
	label(meta, "%s  ·  Rank %s%s" % [pg.kind, pg.rank, "" if rank_ok else "   (yours: %s)" % host.rank], serif_italic, 26, FAINT if rank_ok else RED)
	if open:
		label(meta, "Equipped on " + host.equipped_on(pg.id) if host.equipped_on(pg.id) != "" else "Click a slot on the left to equip it.", serif_italic, 24, COLORS[2])
	col.add_child(Rule.new(620))
	if not open:
		_sealed(host, col, pg)
	else:
		_body(col, pg)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	var prev := link(foot, "‹  Previous", 30)
	prev.name = "PrevPage"
	prev.pressed.connect(host.manual_flip.bind(-1))
	var f1 := Control.new()
	f1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(f1)
	var toc := link(foot, "Contents", 28, FAINT)
	toc.name = "ToContents"
	toc.pressed.connect(host.jump_to.bind(0))
	var f2 := Control.new()
	f2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(f2)
	var nxt := link(foot, "Next  ›", 30)
	nxt.name = "NextPage"
	nxt.disabled = idx >= host.pages.size()
	nxt.pressed.connect(host.manual_flip.bind(1))
	return root

static func _body(col: VBoxContainer, pg: Dictionary) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "PageBody"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 10)
	scroll.add_child(b)
	label(b, pg.description, serif, 29, INK)
	# the live numbers as a ledger
	var ledger := PanelContainer.new()
	ledger.name = "PageStats"
	ledger.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.14), PAPER_DEEP, 2, 5, 16))
	b.add_child(ledger)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	ledger.add_child(grid)
	for row in pg.stats:
		var k := label(grid, String(row[0]), sans_bold, 21, FAINT, HORIZONTAL_ALIGNMENT_LEFT, false)
		k.custom_minimum_size.x = 236
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label(grid, String(row[1]), serif, 26, INK)
	if String(pg.special) != "":
		_heading(b, "Special")
		label(b, pg.special, serif, 27, INK)
	_heading(b, "Incantation")
	var code := PanelContainer.new()
	code.add_theme_stylebox_override("panel", _box(Color("#efe4c4"), PAPER_DEEP, 2, 5, 16))
	b.add_child(code)
	var lines := ""
	var src: Array = pg.code
	for i in src.size(): lines += ("%02d  %s" % [i + 1, src[i]]) + ("\n" if i < src.size() - 1 else "")
	var cl := label(code, lines, mono, 20, Color("#2c2418"))
	cl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_heading(b, "Lesson")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rt.add_theme_font_override("normal_font", serif)
	rt.add_theme_font_override("bold_font", serif_bold)
	rt.add_theme_font_override("mono_font", mono)
	rt.add_theme_font_size_override("normal_font_size", 27)
	rt.add_theme_font_size_override("bold_font_size", 27)
	rt.add_theme_font_size_override("mono_font_size", 22)
	rt.add_theme_color_override("default_color", INK)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.text = _lesson_bbcode(String(pg.lesson))
	b.add_child(rt)
	var tip := PanelContainer.new()
	tip.add_theme_stylebox_override("panel", _box(Color(0.6, 0.45, 0.26, 0.10), GOLD, 2, 5, 14))
	b.add_child(tip)
	label(tip, "Tip  ·  " + String(pg.tip), serif_italic, 26, FAINT)

static func _heading(parent: Control, text: String) -> void:
	gap(parent, 4)
	label(parent, text.to_upper(), sans_bold, 22, GOLD)

static func _lesson_bbcode(s: String) -> String:
	s = s.replace("[", "[lb]")
	var out := ""
	var parts := s.split("`")
	for i in parts.size():
		out += ("[code]" + parts[i] + "[/code]") if i % 2 == 1 else parts[i]
	var lines := out.split("\n")
	if lines.size() > 0 and lines[0].contains(":"):
		var c := lines[0].find(":")
		lines[0] = "[b]" + lines[0].substr(0, c + 1) + "[/b]" + lines[0].substr(c + 1)
	return "\n".join(lines)

static func _sealed(host: Node, col: VBoxContainer, pg: Dictionary) -> void:
	var a: Dictionary = host.assembly
	if not a.is_empty() and a.id == pg.id:
		label(col, "Code Assembly", serif, 44, INK, HORIZONTAL_ALIGNMENT_CENTER)
		label(col, "Topic: " + String(pg.topic), serif_italic, 24, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		label(col, "Click a line, then the line to swap it with.", sans, 21, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		var lines: Array = a.lines
		for k in lines.size():
			var b := Button.new()
			b.name = "line_%d" % k
			b.text = "%02d   %s" % [k + 1, lines[k]]
			b.focus_mode = Control.FOCUS_NONE
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.add_theme_font_override("font", mono)
			b.add_theme_font_size_override("font_size", 21)
			b.add_theme_color_override("font_color", INK)
			b.add_theme_color_override("font_hover_color", RED)
			var st := _box(Color("#efe4c4"), PAPER_DEEP, 1, 4, 9)
			if k == int(a.picked): st = _box(Color("#f3e3a0"), GOLD, 3, 4, 9)
			elif k in a.wrong: st = _box(Color("#efc2b4"), RED, 2, 4, 9)
			b.add_theme_stylebox_override("normal", st)
			b.add_theme_stylebox_override("hover", _box(Color("#f6ecd0"), GOLD, 2, 4, 9))
			b.add_theme_stylebox_override("pressed", st)
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			b.pressed.connect(host.on_pick.bind(k))
			col.add_child(b)
		gap(col, 6)
		var act := HBoxContainer.new()
		act.alignment = BoxContainer.ALIGNMENT_CENTER
		act.add_theme_constant_override("separation", 18)
		col.add_child(act)
		var sub := plate(act, "Submit")
		sub.name = "Submit"
		sub.pressed.connect(host.on_submit)
		var can := plate(act, "Cancel")
		can.name = "Cancel"
		can.pressed.connect(host.on_cancel_assembly)
		if String(a.note) != "": label(col, a.note, serif_italic, 25, RED, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		gap(col, 40)
		label(col, "This page is sealed.", serif, 50, INK, HORIZONTAL_ALIGNMENT_CENTER)
		gap(col, 6)
		label(col, "Topic: " + String(pg.topic), serif_italic, 27, FAINT, HORIZONTAL_ALIGNMENT_CENTER)
		gap(col, 10)
		label(col, "Put its incantation back in order to unlock it.", serif, 28, INK, HORIZONTAL_ALIGNMENT_CENTER)
		gap(col, 24)
		var c := CenterContainer.new()
		col.add_child(c)
		var solve := plate(c, "Solve to unlock", 28)
		solve.name = "Solve"
		solve.pressed.connect(host.on_start_assembly.bind(pg.id))
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fill)

## A page between the source and the target of a fast flip that is not drawn
## in full (none at present: every flip shows its real page).
static func page(host: Node, idx: int) -> Control:
	return contents(host) if idx == 0 else ability(host, idx)
