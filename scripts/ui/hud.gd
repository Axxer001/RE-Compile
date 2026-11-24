extends CanvasLayer
# The in-game HUD (Grimoire MVP P7, handoff §7). Presentation only: main
# builds a view model each tick and calls refresh(); nothing here changes the
# simulation.
#   top-left      Lvl N | Rank X, HP bar cur/max, MP bar cur/max, and under
#                 them the player's buffs and debuffs, each icon with a
#                 remaining-time sweep [R12]
#   top-right     mission and progress, IN COMBAT
#   (no action bar since 2026-11-20: the held grimoire's pages show the
#   loadout, cooldowns and ready state)
#   top-centre    notifications (newest at the bottom), the interaction prompt

const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const SLOT_PX := 58
const STATUS_PX := 26
const BAR_W := 260
const HP_COLOR := Color(0.78, 0.2, 0.2)
const MP_COLOR := Color(0.25, 0.45, 0.9)
const MAX_NOTICES := 4

var status: Label
var hp_bar: Dictionary        # {back, fill, label}
var mp_bar: Dictionary
var mission: Label
var prompt: Label
var notice_box: VBoxContainer
var status_row: HBoxContainer # the player's buffs and debuffs [R12]
var cross: Label
var pause_label: Label
var cast_bar: Dictionary      # {back, fill, label}: Dragon's Breath / Explosion progress [2026-11-14]
# The Gambler set [2026-11-14]: Let it Ride's die, the coin purse, the Jackpot's
# gold flash and Gambling Addiction's purple, desaturated view (under the HUD).
const DiceView = preload("res://scripts/ui/dice_view.gd")
const JACKPOT_FLASH_S := 0.8
var die: SubViewportContainer
var coin_label: Label
var gold_flash: ColorRect
var addict_tint: ColorRect
const CAST_W := 320.0

func _ready() -> void:
	layer = 1
	addict_tint = ColorRect.new()
	addict_tint.name = "AddictionTint"
	addict_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	addict_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.75;
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 p = mix(c, vec3(g) * vec3(0.85, 0.55, 1.15), amount);
	COLOR = vec4(p, 1.0);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	addict_tint.material = sm
	addict_tint.visible = false
	add_child(addict_tint)
	gold_flash = ColorRect.new()
	gold_flash.name = "JackpotFlash"
	gold_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	gold_flash.color = Color(1.0, 0.82, 0.2, 0.0)
	gold_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_flash.visible = false
	add_child(gold_flash)
	cross = Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.add_theme_font_size_override("font_size", 22)
	add_child(cross)
	status = Label.new()
	status.position = Vector2(24, 16)
	status.add_theme_font_size_override("font_size", 18)
	add_child(status)
	hp_bar = _bar(Vector2(24, 44), HP_COLOR, "HP")
	mp_bar = _bar(Vector2(24, 72), MP_COLOR, "MP")
	status_row = HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.position = Vector2(24, 100)
	status_row.add_theme_constant_override("separation", 4)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_row)
	coin_label = Label.new()
	coin_label.name = "Coins"
	coin_label.position = Vector2(24 + BAR_W + 14, 48)
	coin_label.add_theme_font_size_override("font_size", 18)
	coin_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	coin_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	coin_label.add_theme_constant_override("outline_size", 4)
	coin_label.visible = false
	add_child(coin_label)
	die = DiceView.new()
	die.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	die.position += Vector2(DiceView.PX * 0.5 + 250, -SLOT_PX - 40 - DiceView.PX)
	add_child(die)
	mission = Label.new()
	mission.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mission.position += Vector2(-340, 20)
	mission.custom_minimum_size = Vector2(316, 0)
	mission.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mission.add_theme_font_size_override("font_size", 18)
	add_child(mission)
	notice_box = VBoxContainer.new()
	notice_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_box.position += Vector2(-300, 180) # below the level/rank banner [R15]
	notice_box.custom_minimum_size = Vector2(600, 0)
	notice_box.add_theme_constant_override("separation", 4)
	add_child(notice_box)
	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position += Vector2(-260, -130)
	prompt.custom_minimum_size = Vector2(520, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)
	# No loadout bar [Sir, 2026-11-20]: the held grimoire's live page ink shows the
	# open page, its cooldowns and ready state.
	var cb := ColorRect.new()
	cb.name = "CastBar"
	cb.color = Color(0.05, 0.05, 0.07, 0.8)
	cb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cb.position += Vector2(-CAST_W * 0.5, -SLOT_PX - 64)
	cb.size = Vector2(CAST_W, 16)
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.visible = false
	add_child(cb)
	var cf := ColorRect.new()
	cf.color = Color(1.0, 0.55, 0.15)
	cf.position = Vector2(2, 2)
	cf.size = Vector2(CAST_W - 4, 12)
	cf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb.add_child(cf)
	var cl := Label.new()
	cl.position = Vector2(0, -24)
	cl.size = Vector2(CAST_W, 22)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_theme_font_size_override("font_size", 15)
	cl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cl.add_theme_constant_override("outline_size", 4)
	cb.add_child(cl)
	cast_bar = {"back": cb, "fill": cf, "label": cl}
	pause_label = Label.new()
	pause_label.text = "PAUSED  -  ESC to resume"
	pause_label.set_anchors_preset(Control.PRESET_CENTER)
	pause_label.position += Vector2(-120, -60)
	pause_label.visible = false
	add_child(pause_label)

# A channelled spell's bar: hidden when nothing channels.
func _set_cast(c: Dictionary) -> void:
	if cast_bar.is_empty(): return
	cast_bar.back.visible = not c.is_empty()
	if c.is_empty(): return
	cast_bar.fill.size.x = (CAST_W - 4) * clampf(float(c.get("frac", 0.0)), 0.0, 1.0)
	cast_bar.label.text = String(c.get("label", ""))

func cast_shown() -> bool:
	return not cast_bar.is_empty() and cast_bar.back.visible

func _bar(at: Vector2, color: Color, nm: String) -> Dictionary:
	var back := ColorRect.new()
	back.name = nm + "Bar"
	back.color = Color(0.05, 0.05, 0.07, 0.75)
	back.position = at
	back.size = Vector2(BAR_W, 22)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 18)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	var label := Label.new()
	label.position = Vector2(8, 0)
	label.size = Vector2(BAR_W - 16, 22)
	label.add_theme_font_size_override("font_size", 14)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(label)
	return {"back": back, "fill": fill, "label": label, "name": nm, "frac": 1.0}

# m: {level, rank, hp, max_hp, mp, max_mp, mission, slots (unused since the loadout bar went)
#     (basic and special included), statuses: [{id, frac, s}], prompt, notices: [String]}
func refresh(m: Dictionary) -> void:
	status.text = "Lvl %d | Rank %s" % [m.level, m.rank]
	_set_bar(hp_bar, m.hp, m.max_hp)
	_set_bar(mp_bar, m.mp, m.max_mp)
	mission.text = m.mission
	prompt.text = m.get("prompt", "")
	_set_cast(m.get("channel", {}))
	_set_statuses(m.get("statuses", []))
	var now: float = float(m.get("now", 0.0))
	die.update(m.get("die", {}), now)
	var coins: int = int(m.get("coins", -1))
	coin_label.visible = coins >= 0
	if coins >= 0: coin_label.text = "Coins %d/10" % coins
	var jt: float = now - float(m.get("jackpot_at", -INF))
	gold_flash.visible = jt >= 0.0 and jt < JACKPOT_FLASH_S
	if gold_flash.visible: gold_flash.color.a = 0.35 * (1.0 - jt / JACKPOT_FLASH_S)
	addict_tint.visible = bool(m.get("addicted", false))
	var lines: Array = m.get("notices", [])
	while notice_box.get_child_count() > lines.size():
		var ch := notice_box.get_child(notice_box.get_child_count() - 1)
		notice_box.remove_child(ch)
		ch.queue_free()
	while notice_box.get_child_count() < lines.size():
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 4)
		notice_box.add_child(l)
	for i in lines.size(): (notice_box.get_child(i) as Label).text = lines[i]

func _set_bar(b: Dictionary, cur: float, mx: float) -> void:
	var f := clampf(cur / maxf(mx, 1.0), 0.0, 1.0)
	b.frac = f
	b.fill.size.x = (BAR_W - 4) * f
	b.label.text = "%s %d/%d" % [b.name, roundi(cur), roundi(mx)]

# One tile per active effect: its colour and glyph, a dark sweep for the time
# already gone, the seconds left. frac = time left / full time (1 = fresh).
func _set_statuses(list: Array) -> void:
	while status_row.get_child_count() > list.size():
		var ch := status_row.get_child(status_row.get_child_count() - 1)
		status_row.remove_child(ch)
		ch.queue_free()
	while status_row.get_child_count() < list.size():
		var tile := ColorRect.new()
		tile.custom_minimum_size = Vector2(STATUS_PX, STATUS_PX)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Label.new()
		g.name = "Glyph"
		g.size = Vector2(STATUS_PX, STATUS_PX)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_theme_font_size_override("font_size", 15)
		tile.add_child(g)
		var tex := TextureRect.new()
		tex.name = "Icon"
		tex.size = Vector2(STATUS_PX, STATUS_PX)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(tex)
		var sw := ColorRect.new()
		sw.name = "Sweep"
		sw.color = Color(0, 0, 0, 0.55)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(sw)
		status_row.add_child(tile)
	for i in list.size():
		var st: Dictionary = list[i]
		var def := StatusIcons.icon(st.id)
		var tile := status_row.get_child(i) as ColorRect
		var tx := StatusIcons.texture(st.id)
		tile.color = Color(0.06, 0.06, 0.08, 0.75) if tx else def.color
		tile.tooltip_text = def.label
		tile.set_meta("status", st.id)
		(tile.get_node("Icon") as TextureRect).texture = tx
		(tile.get_node("Glyph") as Label).text = "" if tx else def.glyph
		var sw := tile.get_node("Sweep") as ColorRect
		var gone := 1.0 - clampf(float(st.get("frac", 1.0)), 0.0, 1.0)
		sw.position = Vector2.ZERO
		sw.size = Vector2(STATUS_PX, STATUS_PX * gone)
		tile.set_meta("gone", gone)

func status_ids() -> Array:
	var out := []
	for ch in status_row.get_children(): out.append(ch.get_meta("status", ""))
	return out

