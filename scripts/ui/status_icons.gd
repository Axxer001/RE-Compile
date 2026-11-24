extends RefCounted
# Status-effect icons [Sir R12, R14]: one definition per effect, used by the
# HUD (the player's row under the HP/MP bars), the Effects tab and each
# Blighted Sprite (a row under its HP bar). Art: Akami Assets "Buff & Debuff
# Icon Pack - Free Vol.1" (CC0, assets/akami/buff_debuff_vol1/, ledgered).
# `color` tints the tile behind the icon; `glyph` is the fallback when an
# icon file is missing.

const DIR := "res://assets/akami/buff_debuff_vol1/"
const ICONS := {
	"Burn": {"color": Color(0.95, 0.42, 0.1), "glyph": "B", "label": "Burn", "debuff": true, "file": "debuff_shadow_burn.png"},
	"Scorched Slow": {"color": Color(0.7, 0.2, 0.55), "glyph": "S", "label": "Scorched Slow", "debuff": true, "file": "debuff_slow.png"},
	"Concuss": {"color": Color(0.9, 0.8, 0.2), "glyph": "!", "label": "Concussed", "debuff": true, "file": "debuff_stun.png"},
	"Phoenix Concuss": {"color": Color(1.0, 0.55, 0.15), "glyph": "!", "label": "Concussed (Phoenix)", "debuff": true, "file": "debuff_stun.png"},
	"Cultivate": {"color": Color(0.35, 0.7, 0.35), "glyph": "C", "label": "Cultivate", "debuff": false, "file": "buff_focus.png"},
	"Sage Arts": {"color": Color(0.85, 0.75, 0.3), "glyph": "+", "label": "Sage Arts", "debuff": false, "file": "buff_regen_potion.png"},
	"Pocket Change": {"color": Color(0.95, 0.8, 0.25), "glyph": "$", "label": "Pocket Change", "debuff": true, "file": "debuff_curse.png"},
	"Heavy Pockets": {"color": Color(0.75, 0.6, 0.2), "glyph": "H", "label": "Heavy Pockets", "debuff": true, "file": "debuff_freeze.png"},
	"Gambler's High": {"color": Color(0.35, 0.85, 0.4), "glyph": "G", "label": "Gambler's High", "debuff": false, "file": "buff_luck.png"},
	"Jackpot": {"color": Color(1.0, 0.85, 0.2), "glyph": "J", "label": "I JUST HIT THE JACKPOT!", "debuff": false, "file": "buff_strength.png"},
	"All In": {"color": Color(0.9, 0.9, 1.0), "glyph": "I", "label": "All In: Invincible", "debuff": false, "file": "buff_nature_shield.png"},
	"All In: Won": {"color": Color(0.9, 0.2, 0.3), "glyph": "W", "label": "All In: Won", "debuff": false, "file": "buff_energy_burst.png"},
	"All In: Bust": {"color": Color(0.4, 0.4, 0.5), "glyph": "X", "label": "All In: Bust", "debuff": true, "file": "debuff_heartbreak.png"},
	"Gambling Addiction": {"color": Color(0.55, 0.25, 0.7), "glyph": "A", "label": "Gambling Addiction", "debuff": true, "file": "debuff_confusion.png"},
}

static var _tex := {}

static func icon(id: String) -> Dictionary:
	return ICONS.get(id, {"color": Color(0.6, 0.6, 0.65), "glyph": id.left(1), "label": id, "debuff": true, "file": ""})

# The icon's texture, or null (then the glyph is drawn instead).
static func texture(id: String) -> Texture2D:
	if _tex.has(id): return _tex[id]
	var f: String = icon(id).get("file", "")
	var t: Texture2D = load(DIR + f) if f != "" and ResourceLoader.exists(DIR + f) else null
	_tex[id] = t
	return t

# The icon row over an actor [R12; 2026-11-14 for every debuff, Sprites and
# training dummies alike]: one billboard icon per effect, side by side, centred,
# ICON_M across. Drawn through grass and trunks (no depth test) so a debuffed
# enemy always reads as one. `row` is reused (null: made at height `y`).
const ICON_M := 0.3
const ICON_GAP := 0.04
static func update_row(owner: Node3D, row: Node3D, ids: Array, y: float) -> Node3D:
	if row == null:
		row = Node3D.new()
		row.name = "StatusRow"
		row.position.y = y
		owner.add_child(row)
	for ch in row.get_children():
		row.remove_child(ch)
		ch.queue_free()
	for i in ids.size():
		var def := icon(ids[i])
		var tx := texture(ids[i])
		var x := (i - (ids.size() - 1) * 0.5) * (ICON_M + ICON_GAP)
		if tx:
			var sp := Sprite3D.new()
			sp.texture = tx
			sp.pixel_size = ICON_M / float(tx.get_width())
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = false
			sp.no_depth_test = true
			sp.render_priority = 3
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sp.offset = Vector2(x / sp.pixel_size, 0)
			sp.set_meta("status", ids[i])
			row.add_child(sp)
			continue
		var l := Label3D.new()
		l.text = def.glyph
		l.modulate = def.color
		l.outline_modulate = Color(0, 0, 0)
		l.outline_size = 6
		l.font_size = 60
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 3
		l.offset = Vector2(x / l.pixel_size, 0)
		l.set_meta("status", ids[i])
		row.add_child(l)
	row.visible = not ids.is_empty()
	return row
