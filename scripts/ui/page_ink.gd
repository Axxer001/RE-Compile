extends Control
# Live page ink for the held grimoire (held_rig.gd), ported from the GAME ASSETS
# "Held Grimoire" pack's PageInk.gd [Sir, 2026-11-20]. One Control per page
# texture (440 x 608): the left page is the open folio, the right page the index.
#   pages 0-3  a spell slot: title, MP, cooldown, a timer ring, Ready / time left
#   page 4     the status page (key 5): the passive, then every effect, buff and
#              debuff on the player with time left, in the same design and fonts
# Reads only rig.shown, rig.page_info(i) and rig.status_info(); draws nothing else.

const SERIF = preload("res://assets/fonts/EBGaramond-Variable.ttf")
const SANS = preload("res://assets/fonts/Archivo-Variable.ttf")
const INK = Color("#33291e")
const FAINT = Color("#715e44")
const GOLD = Color("#997243")
const ROMAN = ["I", "II", "III", "IV", "V"]
const COLORS = [Color("#923d2c"), Color("#ae5526"), Color("#36685e"), Color("#5f547b"), Color("#6b5a2e")]
const BUFF := Color("#36685e")
const DEBUFF := Color("#923d2c")
const STATUS_ROWS := 3           # rows on the right page, large enough to read at the held view [Sir, 2026-11-21];
								 # at 90 FOV, 16:9, only the page's top ~440 px is on screen
const STATUS_NAME_PX := 40       # an effect's name (shrinks only for a name too long for the page)
const STATUS_TIME_PX := 32       # its time left, bold, on the line below
const STATUS_X := Vector2(74, 380) # the row's left and right edges (the book's curve hides the page's far edge)
const STATUS_TOP := 214.0
const STATUS_PITCH := 76.0

var rig: Node
var index_page: bool
static var SANS_BOLD: FontVariation = _bold()

static func _bold() -> FontVariation:
	var v := FontVariation.new()
	v.base_font = SANS
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	return v

func text(s: String, y: float, font: Font, px: int, c: Color = INK, x: float = 0, width: float = 440, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	draw_string(font, Vector2(x, y), s, align, width, px, c)

func rule(y: float) -> void:
	draw_line(Vector2(38, y), Vector2(402, y), GOLD, 1.6, true)
	var p := Vector2(220, y)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(0, -4), p + Vector2(6, 0), p + Vector2(0, 4)]), GOLD)

func timer_ring(center: Vector2, radius: float, slot: int, fraction: float) -> void:
	draw_arc(center, radius, 0, TAU, 72, Color("#b5a17c"), 2.5, true)
	if fraction <= 0: return
	var end: float = -PI / 2 + TAU * fraction
	var color: Color = COLORS[slot]
	draw_arc(center, radius, -PI / 2, end, 64, color, 5, true)
	match slot:
		0: draw_circle(center + Vector2.from_angle(end) * radius, 4, color)
		1: draw_arc(center, radius - 6, -PI / 2, end, 48, color, 2, true)
		2:
			for i in 3: draw_circle(center + Vector2.from_angle(end - i * 0.16) * radius, 3 - i * 0.55, color)
		3:
			for i in 8:
				var angle: float = -PI / 2 + i * TAU / 8
				if angle < end: draw_circle(center + Vector2.from_angle(angle) * (radius - 6), 2.4, color)

func _paper() -> void:
	draw_rect(Rect2(0, 0, 440, 608), Color("#eadaaf"))
	for j in 12: draw_rect(Rect2(j, j, 440 - j * 2, 608 - j * 2), Color(0.43, 0.31, 0.14, 0.22 - j * 0.015), false, 1)
	draw_rect(Rect2(18, 18, 404, 572), GOLD, false, 1.25)
	text("FIELD GRIMOIRE", 61, SANS, 20, FAINT)
	rule(84)

func _draw() -> void:
	if not rig: return
	var slot: int = rig.shown
	_paper()
	if slot >= 4:
		_status(rig.status_info())
	elif not index_page:
		_folio(slot, rig.page_info(slot))
	else:
		_index(slot)
	text(ROMAN[slot] if not index_page else "1  –  5", 573, SERIF, 19, FAINT)

func _folio(slot: int, page: Dictionary) -> void:
	text("FOLIO  " + ROMAN[slot], 132, SANS, 22, COLORS[slot])
	var c := Vector2(220, 222)
	draw_arc(c, 48, 0, TAU, 64, GOLD, 1, true) # medallion reserved for the spell's icon
	if page.get("empty", false):
		text("Empty page", 345, SERIF, 46, FAINT)
		rule(373)
		text("Equip a page from the Grimoire (Tab)", 440, SANS, 20, FAINT)
		return
	timer_ring(c, 57, slot, float(page.frac))
	text(page.title, 345, SERIF, 51 if String(page.title).length() <= 15 else 40)
	rule(373)
	text("MANA", 420, SANS, 21, FAINT, 43, 155)
	text("SPECIAL" if page.attack else "COOLDOWN", 420, SANS, 21, FAINT, 236, 161)
	text("%d MP" % roundi(page.mp), 464, SERIF, 39, INK, 43, 155)
	text("%d s" % roundi(page.cd), 464, SERIF, 39, INK, 236, 161)
	var st: String = page.state
	if float(page.left) > 0.0: text("%s  ·  %.1f s" % ["Special" if page.attack else "Cast", float(page.left)], 529, SANS, 24, COLORS[slot])
	elif st == "mp": text("Not enough mana", 529, SERIF, 29, FAINT)
	elif st == "locked": text("Needs a higher rank", 529, SERIF, 29, FAINT)
	elif st == "addicted": text("Sealed by Addiction", 529, SERIF, 29, FAINT)
	else: text("Ready", 529, SERIF, 31, COLORS[slot])

func _index(slot: int) -> void:
	text("Spell index", 157, SERIF, 48)
	for i in 5:
		var y: float = 194 + i * 52
		var info: Dictionary = rig.page_info(i) if i < 4 else {"title": "Active passive"}
		if i == slot: draw_rect(Rect2(36, y - 25, 368, 49), Color("#dbc69d"))
		timer_ring(Vector2(63, y), 16, i, float(info.get("frac", 0.0)))
		text(str(i + 1), y + 7, SANS, 20, INK, 45, 36)
		text(String(info.get("title", "")), y + 10, SERIF, 30, FAINT if info.get("empty", false) else INK, 94, 298, HORIZONTAL_ALIGNMENT_LEFT)
	rule(448)
	var page: Dictionary = rig.page_info(slot)
	text("LMB   Cast", 492, SANS, 25)
	if page.get("attack", false): text("RMB   Special  ·  %d s" % roundi(page.cd), 530, SANS, 23, COLORS[slot])


# Page 5: left, the passive; right, the effects with time left.
func _status(info: Dictionary) -> void:
	var effects: Array = info.get("effects", [])
	if not index_page:
		text("FOLIO  V", 132, SANS, 22, COLORS[4])
		text("Active passive", 200, SERIF, 56)
		rule(232)
		text("EQUIPPED IN LOADOUT", 290, SANS, 21, FAINT)
		var passive: String = info.get("passive", "")
		text(passive if passive != "" else "None equipped", 340, SERIF, 40 if passive != "" else 32, INK if passive != "" else FAINT)
		rule(388)
		text("ACTIVE EFFECTS", 440, SANS, 21, FAINT)
		text("%d" % effects.size(), 492, SERIF, 44)
		text("Not castable: turn to 1 – 4", 535, SANS, 19, FAINT)
		return
	text("Effects", 157, SERIF, 48)
	if effects.is_empty():
		text("No buffs or debuffs", 260, SERIF, 30, FAINT)
		return
	var w: float = STATUS_X.y - STATUS_X.x
	var shown: int = effects.size() if effects.size() <= STATUS_ROWS else STATUS_ROWS - 1 # the last row says how many more
	for i in shown:
		var e: Dictionary = effects[i]
		var y: float = STATUS_TOP + i * STATUS_PITCH
		var col: Color = DEBUFF if String(e.get("kind", "")) == "debuff" else BUFF
		draw_circle(Vector2(STATUS_X.x - 20, y - 13), 9, col)
		var nm := String(e.get("name", e.get("id", "")))
		var px := STATUS_NAME_PX
		while px > 26 and SERIF.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w: px -= 2
		text(nm, y, SERIF, px, INK, STATUS_X.x, w, HORIZONTAL_ALIGNMENT_LEFT)
		var s: float = float(e.get("s", 0.0))
		var left: String = String(e.get("until_text", "")) if String(e.get("until_text", "")) != "" else ("%.1f s" % s if s < 1e6 else "")
		text(left, y + 32, SANS_BOLD, STATUS_TIME_PX, col, STATUS_X.x, w, HORIZONTAL_ALIGNMENT_LEFT)
	if effects.size() > shown: text("+%d more" % (effects.size() - shown), STATUS_TOP + shown * STATUS_PITCH + 8, SANS_BOLD, STATUS_TIME_PX, FAINT, STATUS_X.x, w, HORIZONTAL_ALIGNMENT_LEFT)
