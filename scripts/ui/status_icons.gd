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
	"Cultivate": {"color": Color(0.35, 0.7, 0.35), "glyph": "C", "label": "Cultivate", "debuff": false, "file": "buff_focus.png"},
	"Sage Arts": {"color": Color(0.85, 0.75, 0.3), "glyph": "+", "label": "Sage Arts", "debuff": false, "file": "buff_regen_potion.png"},
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
