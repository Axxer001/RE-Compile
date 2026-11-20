extends CanvasLayer
# The Grimoire overlay on Tab (GDD §3.1-3.2, handoff §5; layout per Sir's
# design references and notes, 2026-11-12; fonts EB Garamond and Archivo, OFL).
# Two views, switched with A / D (or the arrows beside the title):
#   Grimoire: an open parchment book. The left page is always the loadout
#     (I Attack, II Skills, III Spells, IV Passive slot circles). The right
#     page opens on the unnumbered Table of Contents: a search bar, then every
#     known ability in one scrolling column (icon, name, a short line, its
#     page number; a locked one shows a locked icon and no description).
#     Clicking a row jumps to its page; each ability has its own page (live
#     numbers, code, lesson, tip; a locked page shows its topic and the Code
#     Assembly). Left / Right arrow keys and the corner buttons turn pages;
#     the button at the book's top-left returns to the contents.
#   Player ID: the academy's ID card. Front: the two crests, portrait, level
#     and rank, location and world level, lifetime records. Back: the six
#     stats with [+] per stat, chant tiers, Reset stats; while chanting the
#     back is the Spell Chant (code, blanks, a hint after 10 s). Space flips it.
# The Effects list is its own overlay on T (effects_panel.gd). The world keeps
# running (Tab does not pause [Sir]) behind a 50% blur. All rules live in the
# session's systems; this panel calls them and shows the result, so tests can
# drive the same methods headless.

const ViewMode = preload("res://scripts/ui/view_mode.gd") # the Grimoire tab's 3D book [Sir, 2026-11-20]
const ViewPages = preload("res://scripts/ui/view_pages.gd")
const AbilityPage = preload("res://scripts/core/ability_page.gd")
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const Validator = preload("res://scripts/core/code_order_validator.gd")
const ChantEngine = preload("res://scripts/core/chant_engine.gd")
const ProjectileService = preload("res://scripts/combat/projectile_service.gd")
const SpellService = preload("res://scripts/combat/spell_service.gd")
const GamblerService = preload("res://scripts/combat/gambler_service.gd")
const EffectSystem = preload("res://scripts/core/effect_system.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")
const STAT_LABELS := {"max_hp": "Max HP", "max_mp": "Max MP", "magic_pow": "Magic Pow", "mov_spd": "Mov Spd", "atk_spd": "Atk Spd", "spell_mastery": "Spell Mastery"}
const SLOT_LABELS := {"spell_1": "[1] Page 1", "spell_2": "[2] Page 2", "spell_3": "[3] Page 3", "spell_4": "[4] Page 4", "passive": "[5] Passive"} # held grimoire [2026-11-20]
const SLOT_KEYS := {"spell_1": "1", "spell_2": "2", "spell_3": "3", "spell_4": "4", "passive": "5"}
const LOADOUT_ROWS := [["I", "Spells", ["spell_1", "spell_2", "spell_3", "spell_4"]], ["II", "Passive", ["passive"]]] # attack and skill pages go in spell slots [Sir, 2026-11-20]
const KIND_SECTIONS := [[0, "Attacks"], [1, "Skills"], [2, "Spells"], [3, "Passives"]] # AbilityPage.Kind order
const PAGE_ICONS := {"scorch_and_burn": "debuff_shadow_burn.png", "cultivate": "buff_focus.png", "ring_of_fire": "buff_magic_orb.png", "quick_step": "buff_speed.png", "sage_arts": "buff_regen_potion.png",
	"dragons_breath": "buff_energy_burst.png", "firefly": "buff_luck.png", "explosion": "buff_strength.png",
	"flight_of_the_phoenix": "buff_levelup.png", "call_of_the_phoenix": "debuff_poison_cloud.png", "rise_of_the_phoenix": "buff_guardian_spirit.png",
	"heads_or_tails": "buff_luck.png", "where_are_my_coins": "debuff_curse.png", "let_it_ride": "debuff_confusion.png", "all_in": "buff_nature_shield.png"}
const ICON_DIR := "res://assets/akami/buff_debuff_vol1/"
const HINT_S := 10.0           # a chant's hint unlocks after this long [Sir]
const WIDTH := 1500.0          # the book
const PAGE_W := 720.0
const VIEW_H := 860.0          # the book and the card are the same height [Sir]
const PAGE_H := VIEW_H - 92.0  # a page inside the book's frame and its contents row
const CARD := Vector2(600, VIEW_H) # the ID card (portrait, like the reference)
const CREST_L := "res://assets/wmsu/wmma_seal.png" # the academy's seal (re-lettered, Sir)
const CREST_R := "res://assets/wmsu/hop_logo.png"  # the House of the Pythons crest
const BLUR := 0.5              # background blur while open [Sir: 50%]
const VIEWS := ["grimoire", "player_id"]
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.5;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 6.0).rgb;
	COLOR = vec4(mix(c, c * 0.12, amount), 1.0);
}
"""

# Book palette (the spellbook reference): leather, parchment, ink, brass.
const LEATHER := Color("422724")
const LEATHER_EDGE := Color("5c3f26")
const PARCH := Color("eadaaf")
const PARCH_DEEP := Color("c9b78e")
const PLAQUE := Color("e6dbbb")
const INK := Color("33291e")
const INK_SOFT := Color("6e5b42")
const BRASS := Color("9c7a3c")
const RED_INK := Color("8a2a1e")
# Card palette (the ID card reference): crimson band, white card, maroon accents.
const CRIMSON := Color("a3262a")
const MAROON := Color("7a1d22")
const PHOTO_RED := Color("a8343a")
const CARD_WHITE := Color("f2f1ec")
const CARD_INK := Color("1d1d1d")

signal close_requested

var world: Node3D
var tab := "grimoire"          # "grimoire" | "player_id"
var mode := "browse"           # "browse" | "assembly" | "chant"
var selected := ""             # page id on the right-hand page ("" = the unnumbered Table of Contents)
var toc_query := ""            # the contents' search text
var toc_kind := -1             # the contents' type filter: -1 all, else AbilityPage.Kind [Sir, 2026-11-14]
const KIND_FILTERS := [[-1, "All types"], [0, "Attacks"], [1, "Skills"], [2, "Spells"], [3, "Passives"]]
var toc_list: VBoxContainer    # the contents' rows (rebuilt as the search changes)
var blur: ColorRect
var card_side := "front"       # Player ID: "front" | "back"
var attempt := {}              # current Code Assembly attempt {page, index, variant, order}
var last_index := {}           # page id -> index of the previous attempt's variant (never repeated)
var picked := -1               # position picked for a swap (-1 = none)
var wrong := []                # positions flagged by the last submit
var status_text := ""
var rng := RandomNumberGenerator.new()
var attempts := 0              # attempts drawn (tests)
var chant_stat := ""           # Spell Chant: the stat being chanted for
var problem := {}              # the current chant problem (ChantEngine.draw)
var last_chant := {}           # stat -> key of the previous attempt's problem (never repeated)
var chant_slots: Array = []    # the token placed in each blank ("" = empty; kept across rebuilds) [Sir, 2026-11-14: tap, don't type]
var chant_bad := {}            # tokens a wrong try showed don't belong (greyed, still usable)
var chant_right := []          # blanks a wrong try showed are right (green)
var chant_wrong := []
var chant_started := 0.0       # session time this chant's problem was drawn
var hint_shown := false
var hint_was_ready := false
var reset_armed := false       # Reset stats asks for a second press

var panel: PanelContainer
var body: VBoxContainer
var mono: Font
var serif: Font
var serif_bold: Font
var sans_bold: Font
var sans_black: Font
var _icons := {}
var view: Node                 # ViewMode: the held book opened for the Grimoire tab
const StageScene = preload("res://scenes/inspection_stage.tscn")
var printed_controls: Dictionary = {}
var studio_layer: CanvasLayer
var stage: Node3D
var studio: SubViewport
var ink: SubViewport
var navigation: Control
var nav_controls: Array[Control] = []

func on_navigation(point: Vector2) -> bool:
	for control in nav_controls:
		if is_instance_valid(control) and control.get_global_rect().has_point(point): return true
	return false

func _size_view() -> void:
	var pixels := Vector2i(get_viewport().get_visible_rect().size)
	ink.size = pixels
	if studio: studio.size = pixels
	if panel: panel.position = ((Vector2(pixels)-panel.size)*0.5).floor()

func _studio() -> void:
	if stage == null:
		studio_layer = CanvasLayer.new()
		studio_layer.layer = layer + 1
		get_parent().add_child(studio_layer)
		studio = SubViewport.new()
		studio.transparent_bg = true
		studio.own_world_3d = true
		studio.msaa_3d = Viewport.MSAA_2X
		studio_layer.add_child(studio)
		stage = StageScene.instantiate()
		studio.add_child(stage)
		stage.setup(self,ink)
		var screen := TextureRect.new()
		screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.texture = studio.get_texture()
		studio_layer.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_size_view()
	studio_layer.show()
	stage.wake()


# The View (view_mode.gd), made once beside the panel.
func _view() -> Node:
	if view == null and world != null:
		view = ViewMode.new()
		get_parent().add_child(view)
		view.setup(self)
	return view

func _input(event: InputEvent) -> void:
	if not visible: return
	var on_book: bool = tab == "grimoire" and view != null
	var press: bool = (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed()
	if press and on_book: view.poke() # any press resets the idle clock
	if event is InputEventKey and event.pressed and not event.echo:
		if session().input.action_for_event(event) == "grimoire" or (event.keycode == KEY_ESCAPE and not _popup_open()):
			close_requested.emit() # Tab closes, mid-inspection too (the book goes back to the hand)
			get_viewport().set_input_as_handled()
			return
		if on_book and view.inspecting(): # a key cuts the idle inspection short
			view.interrupt()
			get_viewport().set_input_as_handled()
			return
		var focus: Control = view.right_vp.gui_get_focus_owner() if on_book else ink.gui_get_focus_owner()
		if focus is LineEdit or _popup_open():
			(view.right_vp if on_book else ink).push_input(event, true)
			get_viewport().set_input_as_handled()
			return
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if handle_key(code):
			get_viewport().set_input_as_handled()
			return
	if on_book and event is InputEventMouse:
		if view.inspecting():
			if event is InputEventMouseButton and event.pressed: # a click cuts it short
				view.interrupt()
				get_viewport().set_input_as_handled()
			return
		if view.pointer(event):
			get_viewport().set_input_as_handled()
			return
	if not on_book and event is InputEventMouse and stage and stage.pointer(event):
		get_viewport().set_input_as_handled()
	elif not on_book and event is InputEventKey and ink.gui_get_focus_owner():
		ink.push_input(event,true)
		get_viewport().set_input_as_handled()

## A control by name on the Grimoire's pages (the View's left and right page),
## else in the panel itself (title, status, Close; the Player ID card). Tests use it.
func page_control(nm: String) -> Control:
	if view != null:
		for v in [view.right_vp, view.left_vp]:
			var c: Control = (v as Node).find_child(nm, true, false)
			if c != null: return c
	return panel.find_child(nm, true, false) as Control

func _popup_open() -> bool:
	var vps: Array = [ink]
	if view != null: vps.append(view.right_vp)
	for v in vps:
		if (v as Viewport).get_embedded_subwindows().any(func(w: Window): return w.visible): return true
	return false

func _process(_delta: float) -> void:
	if visible: navigation.queue_redraw()

func _face() -> Control:
	return body.find_child("CardFace" if tab == "player_id" else "Book", true, false)

func _stat_feedback(stat: String, ok: bool) -> void:
	var target: Control = body.find_child("value_"+stat if ok else "ChantBox",true,false)
	if target == null: return
	target.pivot_offset = target.size * 0.5
	target.modulate = Color("#80e9a0") if ok else Color("#ff8780")
	var t: Tween = target.create_tween().set_parallel(true)
	t.tween_property(target,"modulate",Color.WHITE,0.72)
	if ok:
		target.scale = Vector2.ONE*1.12
		t.tween_property(target,"scale",Vector2.ONE,0.45).set_trans(Tween.TRANS_SINE)
	else:
		target.rotation = -0.025
		t.tween_property(target,"rotation",0.0,0.38).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func setup(main: Node3D) -> void:
	world = main
	rng.seed = 0x6A11 # deterministic in tests; the world reseeds per run

func _ready() -> void:
	layer = 6
	mono = load("res://assets/fonts/JetBrainsMono-Regular.ttf")
	# Bundled OFL fonts (assets/fonts, ledgered): EB Garamond for the book,
	# Archivo Black for the card's headings, Archivo for its body text.
	serif = _weight(load("res://assets/fonts/EBGaramond-Variable.ttf"), 450)
	serif_bold = _weight(load("res://assets/fonts/EBGaramond-Variable.ttf"), 700)
	sans_bold = _weight(load("res://assets/fonts/Archivo-Variable.ttf"), 600) # the card's body text (OFL)
	sans_black = load("res://assets/fonts/ArchivoBlack-Regular.ttf")
	blur = ColorRect.new() # the world behind, blurred [Sir]
	blur.name = "Blur"
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_STOP
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", BLUR)
	blur.material = mat
	add_child(blur)
	panel = PanelContainer.new()
	panel.name = "GrimoirePanel"
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	ink = SubViewport.new()
	ink.name = "PrintedControls"
	ink.disable_3d = true
	ink.transparent_bg = true
	ink.gui_embed_subwindows = true
	ink.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(ink)
	ink.add_child(panel)
	navigation = Control.new()
	navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(navigation)
	navigation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation.draw.connect(func() -> void:
		for control in nav_controls:
			if is_instance_valid(control):
				var region := control.get_global_rect()
				navigation.draw_texture_rect_region(ink.get_texture(),region,region))
	get_viewport().size_changed.connect(_size_view)
	_size_view()
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	panel.add_child(body)
	visible = false

# A weight of a variable font (EB Garamond, Archivo: the "wght" axis).
static func _weight(base: Font, wght: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): wght}
	return v

func session() -> RefCounted:
	return world.session

func grimoire() -> RefCounted:
	return world.session.grimoire

# ---- open / close --------------------------------------------------------------

func open(which := "grimoire") -> void:
	tab = which if which in VIEWS else "grimoire"
	mode = "browse"
	card_side = "front"
	selected = "" # always opens on the unnumbered Table of Contents [Sir]
	toc_query = ""
	status_text = ""
	visible = true
	toc_kind = -1
	_view()
	refresh()
	_studio()
	if stage != null: stage.freeze_card(false)
	if tab == "grimoire" and view != null: view.open() # the held book tucks away; the View's comes up, on the contents [Sir]

func close() -> void:
	if tab == "player_id" and visible and stage != null: stage.freeze_card(true) # it goes down as it looked
	if view != null: view.close() # down, then the held book back into the hand
	visible = false
	mode = "browse"
	attempt = {}
	picked = -1
	wrong = []
	problem = {}
	chant_stat = ""
	reset_armed = false

# ---- Grimoire tab: browse and equip ------------------------------------------------

func select_page(id: String) -> void:
	if not grimoire().is_found(id): return
	selected = id
	if mode != "chant": mode = "browse" # a chant in progress waits on the card [Sir]
	attempt = {}
	status_text = ""
	refresh()

# The book's pages in order: the unnumbered contents, then one per known ability.
func pages() -> Array:
	return [""] + grimoire().listed()

func page_number(id: String) -> int:
	return pages().find(id)

# Turn to the next / previous page (wrapping); "" is the contents.
func flip(step: int) -> void:
	var l := pages()
	var i: int = maxi(0, l.find(selected))
	var to: String = l[(i + step + l.size()) % l.size()]
	if to == selected: return
	var from_i: int = page_number(selected)
	if to == "": show_contents()
	else: select_page(to)
	if view != null: view.turn(from_i, page_number(selected), ViewMode.MANUAL_FLIP_S) # one page: 0.5 s [Sir]

func _jump_to(id: String) -> void:
	var origin: int = page_number(selected)
	var distance: int = page_number(id)-origin
	if id == "": show_contents()
	else: select_page(id)
	if view != null and distance != 0: view.turn(origin, page_number(id), ViewMode.JUMP_FLIP_S) # however far: 1.0 s [Sir]

func show_contents() -> void:
	selected = ""
	if mode != "chant": mode = "browse"
	attempt = {}
	status_text = ""
	refresh()

# The contents' rows that match the search (name or kind, any case) and the type
# filter, in page order (ascending) [Sir, 2026-11-14].
func toc_ids() -> Array:
	var q := toc_query.strip_edges().to_lower()
	var ids: Array = grimoire().listed().filter(func(id):
		var pg: Resource = grimoire().page(id)
		if toc_kind >= 0 and int(pg.kind) != toc_kind: return false
		return q == "" or pg.title.to_lower().contains(q) or pg.kind_name().to_lower().contains(q))
	ids.sort_custom(func(a, b): return page_number(a) < page_number(b))
	return ids

func set_kind_filter(kind: int) -> void:
	toc_kind = kind
	_refill_toc()

func set_search(text: String) -> void:
	toc_query = text
	_refill_toc()

func _refill_toc() -> void:
	if view != null and view.toc_list != null and is_instance_valid(view.toc_list):
		ViewPages.fill_toc(view, view.toc_list)
		toc_list = view.toc_list

# A short line for the contents: the description's first sentence, trimmed.
static func short_info(pg: Resource) -> String:
	var d: String = pg.description
	var cut := d.find(". ")
	var first := d.substr(0, cut + 1) if cut > 0 else d
	return first if first.length() <= 90 else first.substr(0, 87) + "..."

# Keys while open [Sir]: A / D switch Grimoire and Player ID, Space flips the
# card, Left / Right turn the book's pages. Returns true if it used the key.
func handle_key(code: int) -> bool:
	if not visible: return false
	match code:
		KEY_A, KEY_D: # a chant may visit the Grimoire to study its hint [Sir]
			if mode == "assembly": return false
			show_tab(VIEWS[(VIEWS.find(tab) + (1 if code == KEY_D else -1) + VIEWS.size()) % VIEWS.size()])
			return true
		KEY_SPACE:
			if tab == "player_id" and mode != "chant":
				flip_card()
				return true
		KEY_LEFT, KEY_RIGHT:
			if tab == "grimoire" and mode != "assembly":
				flip(1 if code == KEY_RIGHT else -1)
				return true
	return false

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo: return
	var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if handle_key(code): get_viewport().set_input_as_handled()

# Click-to-equip: the selected (unlocked) page goes into `slot`; with nothing
# selectable it empties the slot. Returns the loadout's answer.
func equip_selected(slot: String) -> String:
	if selected == "":
		status_text = "Open an ability's page, then click a slot to equip it."
		refresh()
		return "no_page"
	var pc: Node3D = world.pcombat
	var pg: Resource = grimoire().page(selected) if selected != "" else null
	var r: String = pc.equip(slot, pg)
	status_text = {"ok": "Equipped %s." % (pg.title if pg else "nothing"), "locked": "Unlock this page first.",
		"wrong_kind": "That page does not fit that slot.", "rank": "Requires Rank %s." % (pg.rank_req if pg else ""),
		"duplicate": "Already equipped in another slot.", "unknown_slot": "No such slot."}.get(r, r)
	refresh()
	return r

func unequip(slot: String) -> String:
	var was: Resource = world.pcombat.loadout.get(slot)
	var r: String = world.pcombat.equip(slot, null)
	if r == "ok": status_text = ("Unequipped %s." % was.title) if was else "Nothing to unequip."
	refresh()
	return r

# ---- Code Assembly ------------------------------------------------------------------

func start_assembly(id: String) -> Dictionary:
	if not grimoire().is_found(id) or grimoire().is_unlocked(id): return {}
	if mode == "chant":
		status_text = "Finish or cancel your Spell Chant first."
		refresh()
		return {}
	selected = id
	mode = "assembly"
	_draw_attempt()
	status_text = "Put the lines in order: click one, then the line to swap it with."
	refresh()
	return attempt

func restart_assembly(note := "") -> void:
	if mode != "assembly": return
	_draw_attempt()
	status_text = note
	refresh()

func _draw_attempt() -> void:
	attempt = CodeAssembly.draw(selected, rng, int(last_index.get(selected, -1)))
	last_index[selected] = attempt.get("index", -1)
	attempts += 1
	picked = -1
	wrong = []

# Click a line: the first click picks it, the second swaps the two.
func pick(pos: int) -> void:
	if mode != "assembly" or pos < 0 or pos >= attempt.order.size(): return
	if picked < 0:
		picked = pos
	elif picked == pos:
		picked = -1
	else:
		var o: Array = attempt.order
		var t = o[picked]; o[picked] = o[pos]; o[pos] = t
		picked = -1
	wrong = []
	refresh()

# Submit: right -> unlock, +3 points and +150 EXP once [GDD]; wrong -> flag
# the misplaced lines, no penalty, keep the arrangement to fix.
func submit() -> Dictionary:
	if mode != "assembly": return {"ok": false, "wrong_indices": []}
	var res: Dictionary = Validator.check(attempt.variant, attempt.order)
	if res.ok:
		if grimoire().unlock(selected):
			session().progression.on_page_unlocked()
		mode = "browse"
		attempt = {}
		status_text = "Page unlocked: %s  (+3 stat points, +150 EXP)" % grimoire().page(selected).title
		if world.has_method("show_notice"): world.show_notice("Page unlocked: %s" % grimoire().page(selected).title, 2.5)
	else:
		wrong = res.wrong_indices
		status_text = "%d line(s) out of place. No penalty - try again." % wrong.size()
	refresh()
	return res

func cancel_assembly() -> void:
	mode = "browse"
	attempt = {}
	refresh()

# ---- Player ID tab ----------------------------------------------------------------

func flip_card() -> void:
	card_side = "back" if card_side == "front" else "front"
	refresh()

# [+] per stat [Sir R9]: with unspent points it allocates one; with none it
# starts a Spell Chant for that stat. Returns true when a point was spent.
func allocate(stat: String) -> bool:
	if session().stats.unspent <= 0:
		start_chant(stat)
		return false
	var ok: bool = session().stats.allocate(stat)
	status_text = ("+1 %s" % STAT_LABELS.get(stat, stat)) if ok else ("No stat points to spend." if session().stats.unspent <= 0 else "%s is at its cap." % STAT_LABELS.get(stat, stat))
	refresh()
	if ok: _stat_feedback(stat,true)
	return ok

# Reset stats [Sir R4]: a first press arms it, the second resets (every stat to
# base; allocated points refunded; each chant gain becomes a point).
func reset_stats() -> int:
	if not reset_armed:
		reset_armed = true # the card shows "press again to confirm" by the button [Sir]
		refresh()
		return -1
	reset_armed = false
	var n: int = session().stats.reset_stats()
	status_text = "Stats reset: %d point(s) to spend." % n
	refresh()
	return n

# ---- Spell Chant (P6) --------------------------------------------------------------

func chant_level(stat: String) -> int:
	return int(session().meta.chant_tier.get(stat, 0))

# Only with no unspent points [GDD 3.4.4]. Returns the problem ({} = refused).
func start_chant(stat: String) -> Dictionary:
	if world.has_method("grimoire_blocked") and world.grimoire_blocked() != "": # Gambling Addiction [Sir, 2026-11-15]
		if world.has_method("show_notice"): world.show_notice(world.grimoire_blocked(), 1.4)
		return {}
	var st: RefCounted = session().stats
	if st.unspent > 0:
		status_text = "Spend your stat points first; chanting is for when you have none."
		refresh()
		return {}
	if not st.can_rise(stat): # a capped stat refuses before the chant starts [R9]
		status_text = "That stat cannot rise further."
		refresh()
		return {}
	tab = "player_id"
	card_side = "back" # the back of the card is the chant [Sir]
	chant_stat = stat
	mode = "chant"
	_draw_chant()
	status_text = ChantEngine.PLATEAU_HINT if problem.get("plateau", false) else "Fill in the blanks."
	refresh()
	return problem

func _draw_chant() -> void:
	problem = ChantEngine.draw(chant_level(chant_stat), session().meta.unlocked, rng, String(last_chant.get(chant_stat, "")))
	last_chant[chant_stat] = problem.get("key", "")
	chant_wrong = []
	chant_right = []
	chant_bad = {}
	problem["choices"] = ChantEngine.choices(problem, session().meta.unlocked, rng) if not problem.is_empty() else []
	chant_slots = []
	for i in problem.get("answers", []).size(): chant_slots.append("")
	chant_started = session().run.time # a fresh problem: the hint waits again
	hint_shown = false
	hint_was_ready = false

# The hint [Sir]: after HINT_S seconds on a problem it names the Grimoire page
# whose code the chant comes from, and nothing more.
func hint_left() -> float:
	return maxf(0.0, HINT_S - (session().run.time - chant_started)) if mode == "chant" else HINT_S

func hint_ready() -> bool:
	return mode == "chant" and not problem.is_empty() and hint_left() <= 0.0

func hint_text() -> String:
	if problem.is_empty(): return ""
	var pg: Resource = grimoire().page(String(problem.page))
	return "Hint: study the page \"%s\" in your Grimoire." % (pg.title if pg else String(problem.page))

func use_hint() -> String:
	if not hint_ready(): return ""
	hint_shown = true
	refresh()
	return hint_text()

# Called each frame while open: the hint button counts down and lights up.
var _hint_secs := -1
func tick() -> void:
	if not visible or mode != "chant": return
	var secs := ceili(hint_left())
	if secs != _hint_secs:
		_hint_secs = secs
		var hb: Button = body.find_child("Hint", true, false)
		if hb != null:
			hb.disabled = secs > 0
			hb.text = "Hint" if secs <= 0 else "Hint (in %d s)" % secs
		var wait: Label = body.find_child("HintWait", true, false)
		if wait != null and secs <= 0: wait.text = "Ready: press Hint to see which page to study."

# Right: the stat's flat chant gain [R9] (no EXP), the stat's chant tier rises
# (kept). Wrong: the streak resets, the same problem stays.
func submit_chant(answers: Array) -> Dictionary:
	if mode != "chant" or problem.is_empty(): return {"ok": false, "wrong": []}
	var res: Dictionary = ChantEngine.check(problem, answers)
	if res.ok:
		var tier: int = problem.tier
		session().progression.on_chant_success(chant_stat, tier)
		session().meta.chant_tier[chant_stat] = chant_level(chant_stat) + 1
		session().meta.note_chant()
		session().meta.save()
		var gain: float = session().stats.gain_for(chant_stat, tier)
		var gain_text := ("+%.2f%%" % (gain * 100.0)) if chant_stat == "spell_mastery" else ("+%.2f" % gain if chant_stat in ["mov_spd", "atk_spd"] else "+%.2f" % gain).trim_suffix(".00")
		status_text = "The chant takes hold: %s %s." % [STAT_LABELS.get(chant_stat, chant_stat), gain_text]
		if world.has_method("show_notice"): world.show_notice("Chant: %s %s" % [STAT_LABELS.get(chant_stat, chant_stat), gain_text], 2.0)
		mode = "browse"
		problem = {}
	else:
		session().progression.on_chant_fail()
		chant_wrong = res.wrong
		chant_right = []
		for i in problem.answers.size():
			if not i in res.wrong: chant_right.append(i)
			elif i < answers.size() and String(answers[i]) != "" and not String(answers[i]) in problem.answers: chant_bad[String(answers[i])] = true
		status_text = "Arcane fizzle: %d blank(s) wrong. Try again or cancel." % res.wrong.size()
		if world.get("sfx") and world.sfx: world.sfx.play("click", world.player.global_position)
	refresh()
	_stat_feedback(chant_stat,res.ok)
	return res

# ---- tapping tokens into the blanks [Sir, 2026-11-14] ----------------------------------------------
# A choice fills the first empty blank; tapping a filled blank empties it. The
# code above shows each placed token in its blank. Chant is enabled once every
# blank holds a token. A wrong try turns the right blanks green and the wrong
# ones red, and greys the tokens that belong nowhere (they stay usable).
func choose(token: String) -> int:
	if mode != "chant" or problem.is_empty(): return -1
	var i := chant_slots.find("")
	if i < 0: return -1
	chant_slots[i] = token
	chant_wrong.erase(i)
	chant_right.erase(i)
	refresh()
	return i

func clear_slot(i: int) -> void:
	if i < 0 or i >= chant_slots.size(): return
	chant_slots[i] = ""
	chant_wrong.erase(i)
	chant_right.erase(i)
	refresh()

func slots_full() -> bool:
	return not chant_slots.is_empty() and not chant_slots.has("")

func submit_slots() -> Dictionary:
	if not slots_full(): return {"ok": false, "wrong": []}
	return submit_chant(chant_slots.duplicate())

# The problem's lines with each placed token shown in its blank: [?1] -> [cout].
func slot_lines() -> Array:
	var out: Array = []
	for l in problem.get("lines", []):
		var t := String(l)
		for i in chant_slots.size():
			if String(chant_slots[i]) != "": t = t.replace("[?%d]" % (i + 1), "[%s]" % chant_slots[i])
		out.append(t)
	return out

func _chant_slots_row(col: VBoxContainer) -> void:
	var cc := CenterContainer.new()
	col.add_child(cc)
	var row := HBoxContainer.new()
	row.name = "ChantSlots"
	row.add_theme_constant_override("separation", 12)
	cc.add_child(row)
	for i in chant_slots.size():
		var tok := String(chant_slots[i])
		var b := Button.new()
		b.name = "slot_%d" % (i + 1)
		b.text = ("%d: %s" % [i + 1, tok]) if tok != "" else ("%d: ____" % (i + 1))
		b.custom_minimum_size = Vector2(170, 56)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 24)
		var fill := Color("fbfaf6")
		var edge := CARD_INK
		if i in chant_wrong:
			fill = Color("f6d6d0")
			edge = MAROON
		elif i in chant_right:
			fill = Color("d4efd2")
			edge = Color("2f7a35")
		for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, _box(fill, edge, 2, 4, 8))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(fc, CARD_INK)
		b.tooltip_text = "Tap to empty this blank"
		b.pressed.connect(clear_slot.bind(i))
		row.add_child(b)

func _chant_choices(col: VBoxContainer) -> void:
	var cc := CenterContainer.new()
	col.add_child(cc)
	var grid := GridContainer.new()
	grid.name = "ChantChoices"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	cc.add_child(grid)
	for tok in problem.get("choices", []):
		var b := Button.new()
		b.name = "choice_" + String(tok).validate_node_name()
		b.text = String(tok)
		b.custom_minimum_size = Vector2(150, 52)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 24)
		var bad: bool = chant_bad.has(String(tok))
		var fill := Color("cfcabd") if bad else Color("efe6cc")
		for st in ["normal", "focus"]: b.add_theme_stylebox_override(st, _box(fill, CARD_INK, 2, 4, 8))
		b.add_theme_stylebox_override("hover", _box(Color("f7efd6"), BRASS, 2, 4, 8))
		b.add_theme_stylebox_override("pressed", _box(Color("f7efd6"), BRASS, 3, 4, 8))
		for fc in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(fc, Color("6b665c") if bad else CARD_INK)
		b.disabled = slots_full()
		b.pressed.connect(func() -> void: choose(String(tok)))
		grid.add_child(b)

func cancel_chant() -> void:
	mode = "browse"
	problem = {}
	refresh()

func show_tab(which: String) -> void:
	if not which in VIEWS: return # the Effects list is its own overlay on T [Sir]
	var switching: bool = which != tab
	if switching:
		status_text = ""
		if which == "grimoire": selected = ""
	tab = which
	if which == "player_id" and mode == "assembly": mode = "browse"
	# Grimoire <-> Player ID [Sir, 2026-11-20]: the outgoing one goes down to the
	# bottom middle, then the other comes up from there. The card keeps its own
	# look while it goes (the ink is about to draw the Grimoire: the black card).
	if switching and visible and stage != null: stage.freeze_card(which != "player_id")
	if switching and view != null and visible:
		if which == "grimoire": view.from_card()
		else: view.to_card()
	if mode == "chant": # the chant carries on: back on the card it is waiting
		card_side = "back"
		status_text = "Spell Chant in progress: press D for the Player ID to finish it." if which == "grimoire" else "Fill in the blanks."
	refresh()

# ---- text views (tests read these) ----------------------------------------------------

# Text of the page view.
func page_text(id: String) -> String:
	var g: RefCounted = grimoire()
	var pg: Resource = g.page(id)
	if pg == null or not g.is_found(id): return ""
	if not g.is_unlocked(id):
		return "%s\n(locked)\nTopic: %s\nSolve its Code Assembly to unlock." % [pg.title, CodeAssembly.topic(id)]
	var lines := ["%s  -  %s" % [pg.title, pg.kind_name()], pg.description]
	for row in page_stats(id): lines.append("%s: %s" % [row[0], row[1]])
	lines.append("Rank requirement: %s" % pg.rank_req)
	lines.append("")
	var code: Array = pg.code_lines
	for i in code.size(): lines.append("%02d: %s" % [i + 1, code[i]])
	lines.append("")
	lines.append("Lesson: " + pg.lesson.replace("`", ""))
	lines.append("Tip: " + pg.hints)
	return "\n".join(lines)

static func _n(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x

# An ability's numbers at the player's current stats [Sir]: [[label, value]].
func page_stats(id: String) -> Array:
	var pg: Resource = grimoire().page(id)
	if pg == null: return []
	var st: RefCounted = session().stats
	var now: float = session().run.time
	var pow: float = st.value("magic_pow", now)
	var burn_dps: float = pow * float(EffectSystem.DEFS.Burn.dps_pct)
	var K: Dictionary = ProjectileService.KINDS
	var pc: Node3D = world.pcombat
	var rows := []
	match id:
		"scorch_and_burn":
			rows.append(["Basic fireball", "%s damage (%d%% of Magic Pow)" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0)]])
			rows.append(["Blast radius", "%s m" % _n(K.basic.aoe)])
			rows.append(["Casts per second", "%s (Atk Spd)" % _n(1.0 / st.attack_interval(now))])
			rows.append(["Burn", "%s damage/s for %s s (%s in all)" % [_n(burn_dps), _n(pg.effect_s), _n(burn_dps * pg.effect_s)]])
			rows.append(["Special (RMB)", "%s damage (%d%% of Magic Pow)" % [_n(pow * pg.special_damage_pct), roundi(pg.special_damage_pct * 100.0)]])
			rows.append(["Special blast", "%s x %s m, Burn %s s" % [_n(K.special.aoe * 2.0), _n(K.special.aoe * 2.0), _n(pg.special_effect_s)]])
			rows.append(["Special cooldown", "%.1f s" % st.cooldown(pg.special_cooldown_s, pg.mastery_applies, now)])
		"cultivate":
			rows.append(["Magic Pow", "+%d%% (to %s)" % [roundi((pc.CULTIVATE.magic_pow[0] - 1.0) * 100.0), _n(pow * pc.CULTIVATE.magic_pow[0])]])
			rows.append(["Spell Mastery", "+%d%%" % roundi(pc.CULTIVATE.spell_mastery[1] * 100.0)])
			rows.append(["Atk Spd", "+%d%%" % roundi((pc.CULTIVATE.atk_spd[0] - 1.0) * 100.0)])
			rows.append(["Duration", "%s s" % _n(pg.duration_s)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, false, now)])
		"ring_of_fire":
			var O: Dictionary = ProjectileService.ORBIT
			var S: Dictionary = ProjectileService.SCORCHED_SLOW
			rows.append(["Orbs", "%d at %s m, for %s s" % [O.count, _n(O.radius), _n(pg.duration_s)]])
			rows.append(["Damage per hit", "%s (%d%% of Magic Pow), each orb every %s s" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(O.rehit_s)]])
			rows.append(["Scorched Slow", "-%d%% Mov Spd for %s s" % [roundi((1.0 - S.mult) * 100.0), _n(S.s)]])
			rows.append(["MP cost", "%d" % roundi(pg.mp_cost)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"quick_step":
			rows.append(["Distance", "%s m, never into a wall" % _n(pc.QUICK_STEP_M)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, false, now)])
		"sage_arts":
			rows.append(["Healing", "%s HP/s (%d%% of Max HP)" % [_n(st.value("max_hp", now) * pc.SAGE_HP), roundi(pc.SAGE_HP * 100.0)]])
			rows.append(["Mana", "%s MP/s (%d%% of Max MP)" % [_n(st.value("max_mp", now) * pc.SAGE_MP), roundi(pc.SAGE_MP * 100.0)]])
			rows.append(["When", "out of combat (%s s after the last aggro)" % _n(world.director.OUT_OF_COMBAT_S)])
		"dragons_breath":
			var B: Dictionary = SpellService.BREATH
			rows.append(["Damage per tick", "%s (%d%% of Magic Pow), every %s s for %s s (%d ticks)" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(B.tick_s), _n(B.s), B.ticks]])
			rows.append(["Cone", "%s m long, widening to %s m; trees and walls block it" % [_n(B.length), _n(B.end_radius * 2.0)]])
			rows.append(["Burn", "%s s" % _n(B.burn_s)])
			rows.append(["While breathing", "move and look freely; no other attack, skill or spell"])
			rows.append(["MP cost", "%d" % roundi(pg.mp_cost)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"firefly":
			var F: Dictionary = SpellService.FIREFLY
			rows.append(["Missiles", "%d, split over up to %d locked enemies (5: 6 each, 1: 30)" % [F.missiles, F.max_targets]])
			rows.append(["Damage per missile", "%s (%d%% of Magic Pow), Burn %s s" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(F.burn_s)]])
			rows.append(["Lock-on", "within %s m, in view and line of sight; none: nothing is spent" % _n(F.range)])
			rows.append(["MP cost", "%d" % roundi(pg.mp_cost)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"explosion":
			var X: Dictionary = SpellService.EXPLOSION
			rows.append(["Damage", "%s (%d%% of Magic Pow), Burn %s s" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(X.burn_s)]])
			rows.append(["Blast", "%s m circle at the crosshair point (up to %s m)" % [_n(X.radius * 2.0), _n(X.reach)]])
			rows.append(["Charge", "%s s: no moving, looking or acting; any hit breaks it" % _n(X.charge_s)])
			rows.append(["MP cost", "all of it (needs full MP)"])
			rows.append(["Cooldown", "%.1f s, from when the charge ends" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"flight_of_the_phoenix":
			var F2: Dictionary = SpellService.FLIGHT
			rows.append(["Pull", "enemies within %s m to you, Concussed %s s (-80%% move and attack speed)" % [_n(F2.pull_r), _n(F2.concuss_s)]])
			rows.append(["Climb", "%s m over %s s, then %s s at the peak to choose" % [_n(F2.height), _n(F2.climb_s), _n(F2.window_s)]])
			rows.append(["Dive damage", "%s (100%%) up to 2 s of climb, rising to %s (500%%) at the peak" % [_n(pow), _n(pow * 5.0)]])
			rows.append(["Impact", "%s m radius, Burn %s s, knocks back to %s m" % [_n(F2.impact_r), _n(F2.burn_s), _n(F2.knock_to)]])
			rows.append(["Landing", "LMB on ground inside the %s m ring; none chosen: back to the start" % _n(F2.ring_r)])
			rows.append(["MP cost", "%d" % roundi(pg.mp_cost)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"call_of_the_phoenix":
			var C2: Dictionary = SpellService.CALL
			rows.append(["Areas", "up to %d, %s m across, on the ground within %s m (LMB)" % [C2.areas, _n(C2.area_r * 2.0), _n(C2.reach)]])
			rows.append(["Rain", "%d fireballs per area over %s s" % [C2.per_area, _n(C2.rain_s)]])
			rows.append(["Each fireball", "%s damage (%d%% of Magic Pow), %s m blast, Burn %s s" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(ProjectileService.KINDS.basic.aoe), _n(C2.burn_s)]])
			rows.append(["Casting", "%s s, held in place; ends early at the third area" % _n(C2.cast_s)])
			rows.append(["MP cost", "%d" % roundi(pg.mp_cost)])
			rows.append(["Cooldown", "%.1f s" % st.cooldown(pg.cooldown_s, pg.mastery_applies, now)])
		"rise_of_the_phoenix":
			var R2: Dictionary = pc.RISE
			rows.append(["Burning kill", "+%d%% max HP and +%d%% max MP" % [roundi(R2.heal * 100.0), roundi(R2.heal * 100.0)]])
			rows.append(["Rebirth", "after %d kills this run (now %s)" % [R2.arm_kills, pc.rise_label()]])
			rows.append(["On rising", "full HP, %s s invulnerable, a %s (200%%) blast that knocks back to %s m" % [_n(R2.invuln_s), _n(pow * pg.damage_pct), _n(R2.blast_r)]])
		"heads_or_tails":
			var GC: Dictionary = GamblerService.COIN
			var GG: Dictionary = GamblerService.GIANT
			rows.append(["Heads (LMB)", "%s damage (%d%% of Magic Pow) to one enemy, %s m at %s m/s" % [_n(pow * pg.damage_pct), roundi(pg.damage_pct * 100.0), _n(GC.range), _n(GC.speed)]])
			rows.append(["Tails (RMB)", "%s damage (%d%%) in a %s m radius, Pocket Change %s s" % [_n(pow * pg.special_damage_pct), roundi(pg.special_damage_pct * 100.0), _n(GG.aoe), _n(pg.special_effect_s)]])
			rows.append(["Pocket Change", "Heads bounces to another marked enemy within %s m, up to %d times, +%d%% each (110/120/130%%)" % [_n(GC.bounce_r), GC.bounces, roundi(GC.bounce_step * 100.0)]])
			rows.append(["Fire rate", "%.1f coins/s (Atk Spd)" % st.value("atk_spd", now)])
			rows.append(["Tails cooldown", "%.1f s" % st.cooldown(pg.special_cooldown_s, pg.mastery_applies, now)])
		"where_are_my_coins":
			var GP: Dictionary = GamblerService.PURSE
			rows.append(["Coins", "+1 a kill, %d at most (now %d); none while any enemy has Heavy Pockets" % [GP.max, world.gambler.purse]])
			rows.append(["Spill", "at %d coins, any buff spends them all" % GP.max])
			rows.append(["Heavy Pockets", "every enemy within %s m: -%d%% Mov Spd, easing to 0 over %s s" % [_n(GP.spill_r), roundi(GP.slow * 100.0), _n(GP.heavy_s)]])
		"let_it_ride":
			var GL: Dictionary = GamblerService.LET
			rows.append(["1-3", "every buff ends; the next cooldown is %s s. Two in a row: Gambling Addiction" % _n(GL.cd_low)])
			rows.append(["4-5", "Gambler's High %s s: +100%% Pow, +30%% Atk Spd and Mov Spd, +20%% Mastery" % _n(GL.high_s)])
			rows.append(["6", "the Jackpot %s s: +500%% Pow, +100%% Atk Spd, Mov Spd and Mastery" % _n(GL.jackpot_s)])
			rows.append(["Addiction", "only Let it Ride (no cooldown, no stats); Pow x0.1, Mov Spd +50%%; ends after %d rolls above 3" % GL.addict_rolls])
			rows.append(["MP cost", "0"])
			rows.append(["Cooldown", "%s s" % _n(GL.cd)])
		"all_in":
			var GA: Dictionary = GamblerService.ALL_IN
			rows.append(["Stake", "%d%% of your current HP; Invincible for %s s" % [roundi(GA.hp_cost * 100.0), _n(GA.invuln_s)]])
			rows.append(["Win (a buff active as it ends)", "every lost HP back, +200%% Magic Pow (to %s) for %s s" % [_n(pow * GA.win_pow), _n(GA.win_s)]])
			rows.append(["Bust (no buff)", "-%d%% Mov Spd and Atk Spd for %s s" % [roundi((1.0 - GA.bust_mult) * 100.0), _n(GA.bust_s)]])
			rows.append(["MP cost", "0"])
			rows.append(["Cooldown", "%s s" % _n(pg.cooldown_s)])
	return rows

func assembly_lines() -> Array:
	var out := []
	if attempt.is_empty(): return out
	for k in attempt.order.size(): out.append(attempt.variant.lines[int(attempt.order[k])])
	return out

func player_id_text() -> String:
	var pr: RefCounted = session().progression
	var st: RefCounted = session().stats
	var now: float = session().run.time
	var lines := ["Level %d   EXP %d / %d   Rank %s" % [pr.level, pr.exp, pr.exp_required(pr.level), pr.rank], "Unspent stat points: %d" % st.unspent, ""]
	for stat in st.STATS:
		var v: float = st.value(stat, now)
		var tier_note := "  (chant tier %d)" % ChantEngine.difficulty(chant_level(stat), session().meta.unlocked).tier
		lines.append("%-14s %s%s" % [STAT_LABELS[stat], _stat_text(stat, v), tier_note])
	return "\n".join(lines)

static func _stat_text(stat: String, v: float) -> String:
	return ("%.1f%%" % (v * 100.0)) if stat == "spell_mastery" else ("%.2f" % v if stat in ["mov_spd", "atk_spd"] else "%d" % roundi(v))

# The card front's records: [[label, value]].
func card_records() -> Array:
	var m: RefCounted = session().meta
	var r: Dictionary = m.records
	var counts := [[0, 0], [0, 0], [0, 0], [0, 0]]
	for id in PageLibrary.IDS:
		var pg: Resource = grimoire().page(id)
		if pg == null: continue
		counts[pg.kind][1] += 1
		if id in m.unlocked: counts[pg.kind][0] += 1
	return [
		["Pages unlocked", "%d / %d" % [m.unlocked.size(), PageLibrary.IDS.size()]],
		["Attacks", "%d / %d" % counts[0]], ["Skills", "%d / %d" % counts[1]],
		["Spells", "%d / %d" % counts[2]], ["Passives", "%d / %d" % counts[3]],
		["Spell chants done", str(int(r.chants))],
		["Highest damage dealt", _n(float(r.best_hit))],
		["Most kills in one run", str(int(r.best_kills))],
		["Total kills", str(int(r.total_kills))],
		["Highest level", str(maxi(int(r.best_level), session().progression.level))],
		["Deaths", str(int(r.deaths))],
	]

# ---- drawing helpers ----------------------------------------------------------------------

func _icon(file: String) -> Texture2D:
	if _icons.has(file): return _icons[file]
	var t: Texture2D = load(ICON_DIR + file) if file != "" and ResourceLoader.exists(ICON_DIR + file) else null
	_icons[file] = t
	return t

func page_icon(id: String) -> Texture2D:
	return _icon(String(PAGE_ICONS.get(id, "")))

static func _box(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 0, margin := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s

func _panel(parent: Control, style: StyleBox, min_size := Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.custom_minimum_size = min_size
	parent.add_child(p)
	return p

# The lesson [Sir, 2026-11-14]: its title ("C++ Variables") as a heading, then
# the text with every `code` span in the code font, so the breakdown reads
# against the incantation above it.
func _lesson(parent: Control, text: String) -> RichTextLabel:
	var cut := text.find(":")
	var head := text.substr(0, cut) if cut > 0 else "Lesson"
	var body := text.substr(cut + 1).strip_edges() if cut > 0 else text
	_text(parent, "Lesson: " + head, 18, INK, serif_bold).name = "LessonHead"
	var r := RichTextLabel.new()
	r.name = "Lesson"
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size.x = PAGE_W - 60
	r.add_theme_font_override("normal_font", serif)
	r.add_theme_font_override("mono_font", mono)
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("mono_font_size", 14)
	r.add_theme_color_override("default_color", INK)
	r.add_theme_constant_override("line_separation", 3)
	if body.length() > 0: body = body.left(1).to_upper() + body.substr(1)
	var esc := body.replace("[", "[lb]")
	var parts := esc.split("`")
	var out := ""
	for i in parts.size(): out += ("[color=#5a2a12][code]%s[/code][/color]" % parts[i]) if i % 2 == 1 else parts[i]
	r.text = out
	parent.add_child(r)
	return r

func _text(parent: Control, text: String, size: int, color: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, wrap_w := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else serif)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if wrap_w > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wrap_w
	parent.add_child(l)
	return l

# A mono label (the Effects rows; tests read them from `body`).
func _label(parent: Control, text: String, size: int) -> Label:
	return _text(parent, text, size, INK, mono, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 80.0)

func _button(parent: Control, text: String, flat := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", sans_bold)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", RED_INK)
	b.add_theme_color_override("font_pressed_color", RED_INK)
	b.add_theme_color_override("font_disabled_color", Color(INK_SOFT, 0.55))
	var n := _box(PLAQUE if not flat else Color(0, 0, 0, 0), INK_SOFT if not flat else Color(0, 0, 0, 0), 1, 3, 6)
	n.content_margin_left = 12; n.content_margin_right = 12
	var h: StyleBoxFlat = n.duplicate(); h.bg_color = Color("efe5c8") if not flat else Color(1, 1, 1, 0.12); h.border_color = BRASS
	var d: StyleBoxFlat = n.duplicate(); d.bg_color = Color(PLAQUE, 0.5)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	parent.add_child(b)
	return b

func _gap(parent: Control, px: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = px
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(g)

# A centred ornament: a rule with a diamond and two small curls (drawn).
func _ornament(parent: Control, w: float, color := INK_SOFT) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 14)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		var cx := c.size.x * 0.5
		var y := 7.0
		c.draw_line(Vector2(cx - w * 0.42, y), Vector2(cx - 12, y), color, 1.0, true)
		c.draw_line(Vector2(cx + 12, y), Vector2(cx + w * 0.42, y), color, 1.0, true)
		c.draw_colored_polygon(PackedVector2Array([Vector2(cx, y - 5), Vector2(cx + 5, y), Vector2(cx, y + 5), Vector2(cx - 5, y)]), color)
		c.draw_arc(Vector2(cx - w * 0.42 - 4, y), 4, 0.0, PI * 1.5, 8, color, 1.0, true)
		c.draw_arc(Vector2(cx + w * 0.42 + 4, y), 4, PI, PI * 2.5, 8, color, 1.0, true))
	parent.add_child(c)
	return c

# Display titles use the held folio's serif; small controls use its sans face.
func _plaque(parent: Control, title: String, _w := 300.0) -> void:
	_text(parent, title, 32, INK, serif_bold, HORIZONTAL_ALIGNMENT_CENTER)

# An icon in a dark frame (like the spellbook's spell tiles).
func _icon_tile(parent: Control, tex: Texture2D, px: float, dim := false, frame := INK) -> Control:
	var p := _panel(parent, _box(Color("1e1610"), frame, 2, 3, 2), Vector2(px, px))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(px - 6, px - 6)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if dim: tr.modulate = Color(0.45, 0.42, 0.38)
		p.add_child(tr)
	return p

# ---- the view ---------------------------------------------------------------------------------

func refresh() -> void:
	if body == null: return
	if blur != null: blur.visible = visible and tab != "grimoire" # the View blurs and darkens behind the book
	for ch in body.get_children(): # out of the layout now (queue_free alone keeps them until the frame ends, doubling the height)
		body.remove_child(ch)
		ch.queue_free()
	toc_list = null
	_switcher()
	var st := _text(body, status_text, 16, Color(1.0, 0.86, 0.55), serif_bold, HORIZONTAL_ALIGNMENT_CENTER, WIDTH)
	st.name = "Status" # under the title: clear of the HUD's action bar
	st.custom_minimum_size.y = 24
	if tab == "player_id": _card()
	elif view != null:
		view.rebuild() # the book's pages: view_pages.gd on the 3D book
		toc_list = view.toc_list if is_instance_valid(view.toc_list) else null
		var space := Control.new() # the 3D book's place: the title sits above it, Close below [Sir, 2026-11-20]
		space.name = "BookSpace"
		space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		space.custom_minimum_size = Vector2(WIDTH, maxf(0.0, get_viewport().get_visible_rect().size.y - 120.0))
		body.add_child(space)
	else: _book()
	_close_row()
	printed_controls.clear()
	for key in ["LeftPaper","RightPaper","CardFace","MiniFace"]:
		printed_controls[key] = body.find_child(key,true,false)
	nav_controls.clear()
	for name_in_view in ["Switcher","Status","FlipCard","CloseRow"]:
		var control: Control = body.find_child(name_in_view,true,false)
		if control: nav_controls.append(control)
	navigation.queue_redraw()
	navigation.queue_redraw.call_deferred()
	_hint_secs = -1
	panel.reset_size()
	if panel.is_inside_tree():
		panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()

# The title with its switches [Sir]: "<  [A]   Grimoire   [D]  >".
func _switcher() -> void:
	var row := HBoxContainer.new()
	row.name = "Switcher"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.x = WIDTH
	body.add_child(row)
	var prev := _button(row, "<  [A]", true)
	prev.name = "PrevView"
	prev.custom_minimum_size.x = 90
	prev.add_theme_color_override("font_color", Color("e6dbbb"))
	prev.pressed.connect(handle_key.bind(KEY_A))
	var title := _text(row, "Grimoire" if tab == "grimoire" else "Player ID", 30, Color("f0e4c2"), serif_bold, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "ViewTitle"
	title.custom_minimum_size.x = 220
	var nxt := _button(row, "[D]  >", true)
	nxt.name = "NextView"
	nxt.custom_minimum_size.x = 90
	nxt.add_theme_color_override("font_color", Color("e6dbbb"))
	nxt.pressed.connect(handle_key.bind(KEY_D))
# Close sits under the book or the card [Sir].
func _close_row() -> void:
	var row := HBoxContainer.new()
	row.name = "CloseRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size = Vector2(WIDTH, 40)
	body.add_child(row)
	var close_b := _button(row, "Close  [Tab]", true)
	close_b.name = "Close"
	close_b.add_theme_color_override("font_color", Color("cdbf9e"))
	close_b.add_theme_font_size_override("font_size", 17)
	close_b.pressed.connect(func() -> void: close_requested.emit())

func _book() -> void:
	var leather := _panel(body, _box(LEATHER, LEATHER_EDGE, 3, 8, 14), Vector2(0, VIEW_H))
	leather.name = "Book"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	leather.add_child(col)
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 14)
	col.add_child(spread)
	var left := _parchment_page(spread)
	left.get_parent().name = "LeftPaper"
	_loadout_page(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	var toc := _button(top, "<<  Table of Contents")
	toc.name = "ToContents"
	toc.disabled = selected == ""
	toc.pressed.connect(_jump_to.bind(""))
	var right := _parchment_page(spread)
	right.get_parent().name = "RightPaper"
	if selected == "": _contents_page(right)
	else: _right_page(right)

func _parchment_page(parent: Control) -> VBoxContainer:
	var page := _panel(parent, _box(PARCH, PARCH_DEEP, 2, 4, 24), Vector2(PAGE_W, PAGE_H))
	page.clip_contents = true
	page.draw.connect(func() -> void:
		page.draw_rect(Rect2(Vector2(9,9),page.size-Vector2(18,18)),BRASS,false,1.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)
	return col

# The left page, always [Sir]: the loadout, large.
func _loadout_page(col: VBoxContainer) -> void:
	_plaque(col, "Loadout", 240)
	var hint := "Click a slot to equip the open page." if selected != "" else "Open an ability's page, then click a slot to equip it."
	_text(col, hint, 15, INK_SOFT, serif, HORIZONTAL_ALIGNMENT_CENTER, PAGE_W - 60)
	_gap(col, 18)
	for section in LOADOUT_ROWS:
		_ornament(col, PAGE_W - 80, BRASS)
		_text(col, "%s   %s" % [section[0],section[1]],25,INK,serif_bold,HORIZONTAL_ALIGNMENT_CENTER)
		var slots := HBoxContainer.new()
		slots.alignment = BoxContainer.ALIGNMENT_CENTER
		slots.add_theme_constant_override("separation",14)
		col.add_child(slots)
		for slot in section[2]: _slot_circle(slots, slot)
		_gap(col, 12)

# One loadout slot: a circle with the page's icon, its key and name; an x empties it.
func _slot_circle(parent: Control, slot: String) -> void:
	var pg: Resource = world.pcombat.loadout.get(slot)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	parent.add_child(col)
	var b := Button.new()
	b.name = "slot_" + slot
	b.custom_minimum_size = Vector2(86, 86)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = SLOT_LABELS[slot] + (": " + pg.title if pg else ": empty")
	var ring := _box(Color("e9dfc2") if pg == null else Color("1e1610"), INK_SOFT if pg == null else BRASS, 2, 43, 0)
	var hov: StyleBoxFlat = ring.duplicate(); hov.border_color = RED_INK
	b.add_theme_stylebox_override("normal", ring)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(equip_selected.bind(slot))
	col.add_child(b)
	if pg:
		var tr := TextureRect.new()
		tr.texture = page_icon(String(pg.id))
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(68, 68)
		tr.position = Vector2(9, 9)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(foot)
	_text(foot, "[%s]" % SLOT_KEYS[slot], 14, INK_SOFT, serif_bold, HORIZONTAL_ALIGNMENT_CENTER)
	if pg != null: # every slot can be emptied, the attack slot too [R12]
		var u := Button.new()
		u.name = "unequip_" + slot
		u.text = "x"
		u.flat = true
		u.tooltip_text = "Unequip"
		u.add_theme_color_override("font_color", RED_INK)
		u.add_theme_font_size_override("font_size", 14)
		u.pressed.connect(unequip.bind(slot))
		foot.add_child(u)
	var nm := _text(col, pg.title if pg else "empty", 17, INK if pg else Color(INK_SOFT, 0.7), serif, HORIZONTAL_ALIGNMENT_CENTER)
	nm.custom_minimum_size.x = 138
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# Opening spread: the Table of Contents, a search bar, then one row per ability.
func _contents_page(col: VBoxContainer) -> void:
	_plaque(col, "Table of Contents", 300)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search the Grimoire..."
	search.text = toc_query
	search.add_theme_font_override("font", serif)
	search.add_theme_font_size_override("font_size", 17)
	search.add_theme_color_override("font_color", INK)
	search.add_theme_color_override("font_placeholder_color", Color(INK_SOFT, 0.7))
	search.add_theme_stylebox_override("normal", _box(Color("efe6cc"), INK_SOFT, 1, 3, 8))
	search.add_theme_stylebox_override("focus", _box(Color("f3ebd3"), BRASS, 2, 3, 8))
	search.text_changed.connect(set_search)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new() # the search box with the type filter beside it [Sir, 2026-11-14]
	bar.name = "SearchBar"
	bar.add_theme_constant_override("separation", 8)
	col.add_child(bar)
	bar.add_child(search)
	var kf := OptionButton.new()
	kf.name = "TypeFilter"
	kf.tooltip_text = "Show one type of ability"
	for f in KIND_FILTERS: kf.add_item(String(f[1]), int(f[0]) + 1)
	kf.select(toc_kind + 1)
	kf.add_theme_font_override("font", serif)
	kf.add_theme_font_size_override("font_size", 16)
	kf.add_theme_color_override("font_color", INK)
	kf.add_theme_color_override("font_hover_color", INK)
	kf.add_theme_color_override("font_pressed_color", INK)
	kf.add_theme_color_override("font_focus_color", INK)
	kf.add_theme_stylebox_override("normal", _box(Color("efe6cc"), INK_SOFT, 1, 3, 8))
	kf.add_theme_stylebox_override("hover", _box(Color("f3ebd3"), BRASS, 1, 3, 8))
	kf.add_theme_stylebox_override("pressed", _box(Color("f3ebd3"), BRASS, 2, 3, 8))
	kf.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	kf.custom_minimum_size = Vector2(150, 0)
	kf.item_selected.connect(func(i: int) -> void: set_kind_filter(int(KIND_FILTERS[i][0])))
	bar.add_child(kf)
	var scroll := ScrollContainer.new()
	scroll.name = "ContentsScroll"
	scroll.custom_minimum_size = Vector2(PAGE_W - 48, PAGE_H - 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "Contents"
	list.add_theme_constant_override("separation", 6)
	list.custom_minimum_size.x = PAGE_W - 64
	scroll.add_child(list)
	toc_list = list
	_fill_toc(list)
	var foot := HBoxContainer.new()
	col.add_child(foot)
	var prev := _button(foot, "<  Previous page", true)
	prev.name = "PrevPage"
	prev.pressed.connect(flip.bind(-1))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fill)
	var nxt := _button(foot, "Next page  >", true)
	nxt.name = "NextPage"
	nxt.pressed.connect(flip.bind(1))

func _fill_toc(list: VBoxContainer) -> void:
	for ch in list.get_children():
		list.remove_child(ch)
		ch.queue_free()
	var ids := toc_ids()
	if ids.is_empty():
		_text(list, "No pages found." if grimoire().listed().size() > 0 else "No pages yet. Pages lie hidden in the forest.", 16, INK_SOFT, serif, HORIZONTAL_ALIGNMENT_CENTER, PAGE_W - 80)
		return
	for sec in [0]: # one column in page order (ascending) [Sir, 2026-11-14]
		for id in ids:
			var pg: Resource = grimoire().page(id)
			var open: bool = grimoire().is_unlocked(id)
			var b := Button.new()
			b.name = "toc_" + id
			b.custom_minimum_size = Vector2(PAGE_W - 70, 70)
			b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.12), PARCH_DEEP, 1, 3, 0))
			b.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.24), BRASS, 1, 3, 0))
			b.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.3), BRASS, 2, 3, 0))
			b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			b.pressed.connect(_jump_to.bind(id))
			list.add_child(b)
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 14)
			row.position = Vector2(8, 7)
			row.size = Vector2(PAGE_W - 86, 56)
			b.add_child(row)
			var tile := _icon_tile(row, page_icon(id), 56, not open)
			if not open: _lock_badge(tile)
			var mid := VBoxContainer.new()
			mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mid.add_theme_constant_override("separation", 0)
			mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(mid)
			var nm := _text(mid, pg.title, 19, INK if open else Color(INK_SOFT, 0.85), serif_bold)
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			nm.name = "Name"
			if open:
				var info := _text(mid, short_info(pg), 14, INK_SOFT, serif, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 260)
				info.name = "Info"
				info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				var sealed := _text(mid, "Sealed - solve its Code Assembly", 14, Color(INK_SOFT, 0.7), serif)
				sealed.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var pn := _text(row, "p. %d" % page_number(id), 17, INK, serif_bold, HORIZONTAL_ALIGNMENT_RIGHT)
			pn.name = "PageNo"
			pn.custom_minimum_size.x = 56
			pn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pn.mouse_filter = Control.MOUSE_FILTER_IGNORE

# A small drawn padlock over a locked icon.
func _lock_badge(tile: Control) -> void:
	var lock := Control.new()
	lock.name = "Lock"
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.custom_minimum_size = Vector2(56, 56)
	lock.draw.connect(func() -> void:
		var c := Vector2(28, 32)
		lock.draw_arc(c + Vector2(0, -8), 8, PI, TAU, 12, Color("e6dbbb"), 3.0, true)
		lock.draw_rect(Rect2(c + Vector2(-11, -6), Vector2(22, 17)), Color("e6dbbb"))
		lock.draw_circle(c + Vector2(0, 2), 2.5, Color("33291e")))
	tile.add_child(lock)

# An ability's own page.
func _right_page(col: VBoxContainer) -> void:
	var pg: Resource = grimoire().page(selected)
	var open: bool = grimoire().is_unlocked(selected)
	_plaque(col, pg.title, 320)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var tile := _icon_tile(head, page_icon(selected), 76, not open, BRASS)
	if not open: _lock_badge(tile)
	var meta_col := VBoxContainer.new()
	head.add_child(meta_col)
	var rank_ok: bool = pg.rank_ok(session().progression.rank)
	_text(meta_col, pg.kind_name(), 19, INK, serif_bold)
	_text(meta_col, "Rank %s%s" % [pg.rank_req, "" if rank_ok else "  (yours: %s)" % session().progression.rank], 16, INK if rank_ok else RED_INK, serif)
	_text(meta_col, "Page %d of %d" % [page_number(selected), pages().size()-1], 15, INK_SOFT, serif)
	_ornament(col, PAGE_W - 60)
	if not open:
		if mode == "assembly" and not attempt.is_empty(): _assembly_view(col)
		else:
			_text(col, "This page is sealed.", 19, INK, serif_bold, HORIZONTAL_ALIGNMENT_CENTER, PAGE_W - 60)
			_text(col, "Topic: " + CodeAssembly.topic(selected), 17, INK, serif, HORIZONTAL_ALIGNMENT_CENTER, PAGE_W - 60)
			_text(col, "Put its incantation back in order to unlock it.", 16, INK_SOFT, serif, HORIZONTAL_ALIGNMENT_CENTER, PAGE_W - 60)
			var c := CenterContainer.new()
			col.add_child(c)
			_button(c, "Solve to unlock").pressed.connect(start_assembly.bind(selected))
		_page_footer(col)
		return
	# The body scrolls inside a fixed height, so every page is the same size.
	var scroll := ScrollContainer.new()
	scroll.name = "PageBody"
	scroll.custom_minimum_size = Vector2(PAGE_W - 48, PAGE_H - 270)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var outer := col
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	scroll.add_child(col)
	_text(col, pg.description, 16, INK, serif, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 70)
	# The live numbers, as a ledger: label on the left, value on the right.
	var stats := _panel(col, _box(Color(1, 1, 1, 0.16), PARCH_DEEP, 1, 3, 10))
	stats.name = "PageStats"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	stats.add_child(grid)
	for row in page_stats(selected):
		var k := _text(grid, row[0], 15, INK_SOFT, serif_bold)
		k.custom_minimum_size.x = 170
		_text(grid, row[1], 15, INK, serif, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 280)
	if pg.kind == AbilityPage.Kind.ATTACK:
		_text(col, "Special: " + pg.special_description, 15, INK, serif, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 60)
	_text(col, "Incantation", 17, INK, serif_bold)
	var code := _panel(col, _box(Color("efe6cc"), PARCH_DEEP, 1, 3, 10))
	var code_lines := ""
	var src: Array = pg.code_lines
	for i in src.size(): code_lines += ("%02d  %s" % [i + 1, src[i]]) + ("\n" if i < src.size() - 1 else "")
	var cl := _text(code, code_lines, 13, Color("2c2418"), mono)
	cl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY # long lines wrap: the page never widens
	cl.custom_minimum_size.x = PAGE_W - 100
	_lesson(col, pg.lesson)
	_text(col, "Tip: " + pg.hints, 15, INK_SOFT, serif, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 70)
	_page_footer(outer)

func _assembly_view(col: VBoxContainer) -> void:
	_text(col, "Code Assembly  -  Topic: %s" % CodeAssembly.topic(selected), 17, INK, serif_bold, HORIZONTAL_ALIGNMENT_LEFT, PAGE_W - 60)
	_text(col, "Click a line, then the line to swap it with.", 14, INK_SOFT, serif)
	var shown := assembly_lines()
	for k in shown.size():
		var b := _button(col, "%02d  %s" % [k + 1, shown[k]])
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 13)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true # a long line is clipped, never widens the page
		b.custom_minimum_size.x = PAGE_W - 70
		b.tooltip_text = shown[k]
		if k == picked: b.add_theme_stylebox_override("normal", _box(Color("f3e3a0"), BRASS, 2, 3, 6))
		elif k in wrong: b.add_theme_stylebox_override("normal", _box(Color("efc2b4"), RED_INK, 2, 3, 6))
		b.pressed.connect(pick.bind(k))
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 10)
	col.add_child(act)
	_button(act, "Submit").pressed.connect(submit)
	_button(act, "Cancel").pressed.connect(cancel_assembly)

# Previous page at the bottom-left corner, next at the bottom-right [Sir].
func _page_footer(col: VBoxContainer) -> void:
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	_ornament(col, PAGE_W - 60)
	var row := HBoxContainer.new()
	col.add_child(row)
	var prev := _button(row, "<  Previous page", true)
	prev.name = "PrevPage"
	prev.pressed.connect(flip.bind(-1))
	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var nxt := _button(row, "Next page  >", true)
	nxt.name = "NextPage"
	nxt.pressed.connect(flip.bind(1))

# ---- the Player ID card -----------------------------------------------------------------------

func _card() -> void:
	var wrap := VBoxContainer.new()
	wrap.name = "Card"
	wrap.custom_minimum_size.x = WIDTH
	wrap.add_theme_constant_override("separation", 8)
	body.add_child(wrap)
	var center := CenterContainer.new()
	wrap.add_child(center)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation",72)
	center.add_child(pair)
	if mode == "chant" and not problem.is_empty():
		var miniature := Control.new()
		miniature.custom_minimum_size = Vector2(CARD.x*0.52,CARD.y)
		pair.add_child(miniature)
		var small := _panel(miniature,_box(CARD_WHITE,Color("c9c6bd"),1,22,0),CARD)
		small.name = "MiniFace"
		small.scale = Vector2.ONE*0.52
		small.position.y = CARD.y*0.24
		small.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
		small.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
		var summary := VBoxContainer.new()
		small.add_child(summary)
		_card_front(summary)
	var holder := Control.new()
	holder.custom_minimum_size = CARD
	pair.add_child(holder)
	var card := _panel(holder, _box(CARD_WHITE, Color("c9c6bd"), 1, 22, 0), CARD)
	card.name = "CardFace"
	card.clip_contents = true
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	if mode == "chant" and not problem.is_empty(): _card_chant(col)
	elif card_side == "front": _card_front(col)
	else: _card_back(col)
	if mode != "chant":
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(row)
		var f := _button(row, "[Space]  Flip card  (%s)" % ("show stats" if card_side == "front" else "show front"), true)
		f.name = "FlipCard"
		f.add_theme_color_override("font_color", Color("cdbf9e"))
		f.pressed.connect(flip_card)

func _card_text(parent: Control, text: String, size: int, color: Color, font: Font, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := _text(parent, text, size, color, font, align)
	l.custom_minimum_size.x = CARD.x - 48
	return l

# A row of the card, inset from its edges.
func _card_row(parent: Control) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 24)
	m.add_theme_constant_override("margin_right", 24)
	parent.add_child(m)
	return m

func _crest(parent: Control, path: String, px: float, nm: String) -> void:
	var tr := TextureRect.new()
	tr.name = nm
	tr.texture = load(path) if ResourceLoader.exists(path) else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(tr)

# Front: the crimson band with both crests, portrait, level and rank, name,
# location, and the records in large type.
func _card_front(col: VBoxContainer) -> void:
	var pr: RefCounted = session().progression
	var band_box := _box(CRIMSON, Color(0, 0, 0, 0), 0, 0, 12)
	band_box.corner_radius_top_left = 22 # the card's own corner radius
	band_box.corner_radius_top_right = 22
	var band := _panel(col, band_box, Vector2(CARD.x, 168))
	band.name = "Band"
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	band.add_child(bh)
	_crest(bh, CREST_L, 118, "CrestLeft")
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -6)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(titles)
	_text(titles, "GUILD OF THE CRIMSONS", 15, Color(1, 1, 1, 0.92), sans_bold, HORIZONTAL_ALIGNMENT_CENTER).name = "BandTop"
	_text(titles, "WESTERN MINDANAO", 27, Color.WHITE, sans_black, HORIZONTAL_ALIGNMENT_CENTER)
	_text(titles, "MAGIC ACADEMY", 27, Color.WHITE, sans_black, HORIZONTAL_ALIGNMENT_CENTER)
	_text(titles, "House of the Pythons", 18, Color(1, 1, 1, 0.94), sans_bold, HORIZONTAL_ALIGNMENT_CENTER).name = "BandHouse"
	_crest(bh, CREST_R, 104, "CrestRight")
	_gap(col, 16)
	var pc := CenterContainer.new()
	col.add_child(pc)
	var photo := _panel(pc, _box(PHOTO_RED, Color(0, 0, 0, 0), 0, 12, 0), Vector2(230, 240))
	photo.name = "Portrait"
	var who := Control.new() # the character's portrait: a robed mage, drawn
	who.custom_minimum_size = Vector2(230, 240)
	who.draw.connect(func() -> void:
		var w := who.size.x
		var h := who.size.y
		who.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.12, h), Vector2(w * 0.2, h * 0.72), Vector2(w * 0.5, h * 0.62), Vector2(w * 0.8, h * 0.72), Vector2(w * 0.88, h)]), Color("5c1418"))
		who.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.43, h * 0.64), Vector2(w * 0.5, h * 0.82), Vector2(w * 0.57, h * 0.64)]), Color("e8d4c0"))
		who.draw_circle(Vector2(w * 0.5, h * 0.44), w * 0.15, Color("d9b79a"))
		who.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.29, h * 0.38), Vector2(w * 0.5, h * 0.05), Vector2(w * 0.71, h * 0.38)]), Color("3a1012"))
		who.draw_line(Vector2(w * 0.22, h * 0.39), Vector2(w * 0.78, h * 0.39), Color("3a1012"), 6.0, true))
	photo.add_child(who)
	_gap(col, 10)
	_card_text(_card_row(col), "LV %d  -  RANK %s" % [pr.level, pr.rank], 36, MAROON, sans_black).name = "LevelRank"
	_card_text(_card_row(col), "APPRENTICE MAGE", 28, CARD_INK, sans_black)
	_card_text(_card_row(col), "%s  -  World Level %d" % [world.location_name(), world.world_level()], 17, CARD_INK, sans_bold).name = "Location"
	_gap(col, 12)
	var rc := CenterContainer.new()
	col.add_child(rc)
	var rec := GridContainer.new()
	rec.name = "Records"
	rec.columns = 4 # two columns of label + value
	rec.add_theme_constant_override("h_separation", 10)
	rec.add_theme_constant_override("v_separation", 8)
	rc.add_child(rec)
	for r in card_records():
		var k := _text(rec, r[0], 16, Color("4a4a4a"), sans_bold, HORIZONTAL_ALIGNMENT_RIGHT)
		k.custom_minimum_size.x = 176
		var v := _text(rec, r[1], 18, CARD_INK, sans_black)
		v.custom_minimum_size.x = 76

# A black pill header (the card back's bars).
func _pill(parent: Control, text: String, size := 16) -> void:
	var c := CenterContainer.new()
	parent.add_child(c)
	var p := _panel(c, _box(Color("1b1b1b"), Color(0, 0, 0, 0), 0, 16, 7), Vector2(CARD.x - 40, 0))
	_text(p, text, size, Color.WHITE, sans_black, HORIZONTAL_ALIGNMENT_CENTER)

# Back: the "if found" line, the stats table with [+] and chant-tier stamps,
# unspent points and EXP, how points are earned, Reset stats.
func _card_back(col: VBoxContainer) -> void:
	var pr: RefCounted = session().progression
	var st: RefCounted = session().stats
	var now: float = session().run.time
	_gap(col, 18)
	_card_text(_card_row(col), "If found, this card is to be returned to the", 15, CARD_INK, sans_bold)
	_card_text(_card_row(col), "OFFICE OF THE GUILD, WESTERN MINDANAO MAGIC ACADEMY", 14, CARD_INK, sans_black)
	_gap(col, 12)
	_pill(col, "CHARACTER STATUS")
	_card_text(_card_row(col), "LEVEL %d  -  RANK %s" % [pr.level, pr.rank], 28, CARD_INK, sans_black)
	_card_text(_card_row(col), "EXP %d / %d" % [pr.exp, pr.exp_required(pr.level)], 18, CARD_INK, sans_bold)
	var up := _card_text(_card_row(col), ("%d STAT POINT%s TO SPEND" % [st.unspent, "" if st.unspent == 1 else "S"]) if st.unspent > 0 else "NO POINTS: CHANT TO RAISE A STAT", 19, MAROON if st.unspent > 0 else CARD_INK, sans_black)
	up.name = "Unspent"
	_gap(col, 10)
	_pill(col, "THESE STATS ARE VALID FOR THIS RUN ONLY")
	_gap(col, 6)
	var tc := CenterContainer.new()
	col.add_child(tc)
	var table := GridContainer.new()
	table.name = "StatTable"
	table.columns = 4
	table.add_theme_constant_override("h_separation", 0)
	table.add_theme_constant_override("v_separation", 0)
	tc.add_child(table)
	var widths := [160.0, 120.0, 140.0, 120.0]
	var heads := ["STAT", "VALUE", "CHANT TIER", "RAISE"]
	for k in heads.size(): _cell(table, heads[k], widths[k], sans_black)
	var stamp_colors := [Color("e88f3a"), Color("8a6ad6"), Color("d9465a"), Color("3f6fd6")]
	var i := 0
	for stat in st.STATS:
		_cell(table, STAT_LABELS[stat], widths[0], sans_black)
		_cell(table, _stat_text(stat, st.value(stat, now)), widths[1], sans_bold).name = "value_" + stat
		var tier: int = maxi(1, ChantEngine.difficulty(chant_level(stat), session().meta.unlocked).tier)
		var tp := _cell(table, "", widths[2], sans_bold)
		var stamp := _panel(tp, _box(stamp_colors[(tier - 1) % 4], Color("1b1b1b"), 1, 2, 3), Vector2(104, 28))
		stamp.rotation = deg_to_rad(-5.0 + (i % 3) * 3.0)
		stamp.pivot_offset = Vector2(52, 14)
		var sl := _text(stamp, "TIER %d" % tier, 15, Color.WHITE, sans_bold, HORIZONTAL_ALIGNMENT_CENTER)
		sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var bp := _cell(table, "", widths[3], sans_bold)
		var b := _button(bp, "+" if st.unspent > 0 else "Chant")
		b.name = "raise_" + stat
		b.disabled = not st.can_rise(stat)
		b.pressed.connect(allocate.bind(stat))
		i += 1
	_gap(col, 12)
	_pill(col, "STAT POINTS ARE EARNED BY")
	_card_text(_card_row(col), "Level up  +1     Unlock a page  +3     Rank up  +5", 16, CARD_INK, sans_bold)
	_card_text(_card_row(col), "With none left, a stat rises by Spell Chant.", 15, Color("444444"), sans_bold)
	_gap(col, 10)
	var sc := CenterContainer.new()
	col.add_child(sc)
	var sigbox := _panel(sc, _box(Color(0, 0, 0, 0), CARD_INK, 2, 18, 12), Vector2(CARD.x - 90, 0))
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sigbox.add_child(sv)
	_text(sv, "Re-spec: every stat back to base, points and chants refunded.", 14, Color("444444"), sans_bold, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 130)
	var rcc := CenterContainer.new()
	sv.add_child(rcc)
	_button(rcc, "Confirm reset" if reset_armed else "Reset stats").pressed.connect(reset_stats)
	if reset_armed:
		var conf := _text(sv, "Press Reset stats again to confirm.", 15, MAROON, sans_bold, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 130)
		conf.name = "ResetConfirm"

# A ruled table cell (the card back's validity table).
func _cell(table: Control, text: String, w: float, font: Font) -> PanelContainer:
	var p := _panel(table, _box(Color(0, 0, 0, 0), CARD_INK, 1, 0, 6), Vector2(w, 54))
	if text != "":
		var l := _text(p, text, 17, CARD_INK, font, HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return p

# The back during a Spell Chant [Sir]: nothing but the chant, in large type.
func _card_chant(col: VBoxContainer) -> void:
	_gap(col, 20)
	_card_text(_card_row(col), "SPELL CHANT", 46, CARD_INK, sans_black)
	_card_text(_card_row(col), "Speak the missing syntax to raise a stat.", 20, CARD_INK, sans_bold)
	_gap(col, 12)
	_pill(col, "CHANTING FOR: %s" % STAT_LABELS[chant_stat].to_upper(), 22)
	_gap(col, 6)
	_card_text(_card_row(col), "Tier %d  -  %s  -  %d blank%s" % [problem.tier, ChantEngine.TIER_NAMES[problem.tier], problem.blanks, "" if problem.blanks == 1 else "s"], 20, MAROON, sans_bold).name = "ChantInfo"
	_gap(col, 10)
	var cc := CenterContainer.new()
	col.add_child(cc)
	var box_size := chant_box_size()
	var box := Panel.new() # a fixed box (not a container): the code never resizes the card
	box.name = "ChantBox"
	box.custom_minimum_size = box_size
	box.clip_contents = true
	box.add_theme_stylebox_override("panel", _box(Color("fbfaf6"), CARD_INK, 2, 6, 0))
	cc.add_child(box)
	var code := ""
	var shown: Array = slot_lines()
	for i in shown.size(): code += ("%02d  %s" % [i + 1, shown[i]]) + ("\n" if i < shown.size() - 1 else "")
	var inner := box_size - Vector2(28, 24)
	# The question scrolls inside the box [Sir]: the font fits it where it can
	# (down to CHANT_MIN_FONT), and anything longer scrolls instead of shrinking further.
	var scroll := ScrollContainer.new()
	scroll.name = "ChantScroll"
	scroll.position = Vector2(14, 12)
	scroll.size = inner
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)
	var cl := Label.new()
	cl.name = "ChantCode"
	cl.text = code
	cl.add_theme_font_override("font", mono)
	cl.add_theme_font_size_override("font_size", chant_font_size(problem.lines, inner - Vector2(14, 0)))
	cl.add_theme_color_override("font_color", CARD_INK)
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cl.custom_minimum_size.x = inner.x - 14 # room for the scroll bar
	scroll.add_child(cl)
	_gap(col, 22)
	_pill(col, "TAP THE SYNTAX INTO THE BLANKS", 22)
	_gap(col, 14)
	_chant_slots_row(col)
	_gap(col, 14)
	_chant_choices(col)
	_gap(col, 20)
	var act := HBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 16)
	col.add_child(act)
	var go := _button(act, "Chant")
	go.name = "ChantGo"
	go.add_theme_font_size_override("font_size", 24)
	go.disabled = not slots_full()
	go.pressed.connect(submit_slots)
	if not chant_wrong.is_empty():
		var retry := _button(act,"Retry")
		retry.name = "ChantRetry"
		retry.pressed.connect(func() -> void:
			for i in chant_wrong: chant_slots[i] = ""
			chant_wrong.clear()
			status_text = "Replace the missing tokens."
			refresh())
	var cb := _button(act, "Cancel")
	cb.add_theme_font_size_override("font_size", 24)
	cb.pressed.connect(cancel_chant)
	var hb := _button(act, "Hint" if hint_ready() else "Hint (in %d s)" % ceili(hint_left()))
	hb.name = "Hint"
	hb.add_theme_font_size_override("font_size", 24)
	hb.disabled = not hint_ready()
	hb.pressed.connect(use_hint)
	_gap(col, 22)
	_pill(col, "HINT", 22)
	_gap(col, 8)
	var ht := _card_text(_card_row(col), hint_text() if hint_shown else ("Ready: press Hint to see which page to study." if hint_ready() else "Unlocks after %d seconds on this chant." % int(HINT_S)), 21, MAROON if hint_shown else Color("444444"), sans_bold)
	ht.name = "HintText" if hint_shown else "HintWait"
	ht.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# The chant's code box: one fixed size for the card [Sir] (the blanks sit in a
# single row and the 6 choices in two, whatever the number of blanks).
func chant_box_size() -> Vector2:
	return Vector2(CARD.x - 40, 214.0)

const CHANT_MIN_FONT := 15     # below this the question scrolls rather than shrinks
# The largest code font (24 down to CHANT_MIN_FONT) whose word-wrapped text
# fits the box (measured with the font itself, as the label will wrap it).
func chant_font_size(lines: Array, inner: Vector2) -> int:
	var text := ""
	for i in lines.size(): text += ("%02d  %s" % [i + 1, lines[i]]) + ("
" if i < lines.size() - 1 else "")
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	for fs in range(24, CHANT_MIN_FONT - 1, -1):
		var h: float = mono.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, inner.x, fs, -1, flags).y
		if h <= inner.y - 4.0: return fs
	return CHANT_MIN_FONT

# ---- shared sizes (tests) -----------------------------------------------------------------------

func view_rect(name: String) -> Rect2:
	var n: Control = panel.find_child(name, true, false)
	return Rect2(n.global_position, n.size) if n else Rect2()
