extends Node
## The Grimoire's View mode (Tab) [Sir, 2026-11-20], ported from the GAME ASSETS
## "Grimoire View Mode" preview (view_mode.gd) and wired to the real systems.
##   - opens on the Table of Contents; the left page is always the loadout
##   - the book comes out of the held pose (lower corner, the book's hand) and
##     goes back into it on close; the world keeps running behind a blurred,
##     darkened screen
##   - a contents jump takes JUMP_FLIP_S in all, every page between flipped; a
##     manual turn (arrows, buttons) MANUAL_FLIP_S
##   - IDLE_AFTER_S without input: the idle inspection (close, front cover, back
##     cover, open, riffle to the contents); a click or key cuts it short
##   - alive: the open book leans and looks toward the cursor on a spring,
##     drifts toward it and breathes (BREATH_S)
## Rules stay in grimoire_panel.gd (the session grimoire, the loadout's equip
## rules, the rank, page_stats, Code Assembly, unlocks): this node is the host
## view_pages.gd builds the pages from, and it forwards every action there.

const Pages = preload("res://scripts/ui/view_pages.gd")
const BOOK := preload("res://assets/held_grimoire/rose_compass_grimoire.glb")
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const PAGE_PX := Vector2i(860, 1248)
const PAGE_W := 0.302          # one page, spine to fore-edge (book-local z)
const PAGE_H := 0.438          # head to foot (book-local x)
const PAGE_TOP := 0.219
const PAGE_Y := 0.030          # the page surface's height for picking
# The transitions [Sir, 2026-11-20]: Tab -> the held book closes and tucks down
# (held_rig.gd, up to TUCK_WAIT_S), then the View book rises closed from the
# bottom middle (RISE_S) and opens (OPEN_S). Close -> it closes (SHUT_S) and
# sinks back to the bottom middle (SINK_S), then the held book comes back up
# to the hand and opens. Grimoire <-> Player ID: the outgoing one goes down to
# the bottom middle, then the other comes up from there (the card flips up).
const TUCK_WAIT_S := 0.62      # the held rig's close + tuck (2 x TUCK_S), with a margin
const RISE_S := 0.45
const OPEN_S := 0.35
const SHUT_S := 0.3
const SINK_S := 0.4
const UNTUCK_WAIT_S := 0.62
const EQUIP_S := RISE_S + OPEN_S
const UNEQUIP_S := SHUT_S + SINK_S
const OPEN_TOTAL_S := TUCK_WAIT_S + EQUIP_S     # Tab to the open View, at most
const CLOSE_TOTAL_S := UNEQUIP_S + UNTUCK_WAIT_S # Tab to the book back open in the hand, at most
const MANUAL_FLIP_S := 0.5     # one page by the buttons or the arrow keys [Sir]
const JUMP_FLIP_S := 1.0       # contents <-> any page, however far [Sir]
const IDLE_AFTER_S := 10.0     # [Sir]
const RESUME_S := 0.5
const RIFFLE_S := 1.2
const CAM_H := 0.84            # the book camera's height over the open book (m)
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, amount * 5.5).rgb;
	vec2 d = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(d, d) * 0.55 * amount;
	COLOR = vec4(mix(c, c * 0.58, amount) * vig, 1.0);
}
"""

var gp: CanvasLayer             # grimoire_panel.gd: the rules and the state
var toc_list: VBoxContainer     # the contents' rows (view_pages fills it)

# ---- scene
var blur_layer: CanvasLayer
var book_layer: CanvasLayer
var book_vp: SubViewport
var book_cam: Camera3D
var holder: Node3D
var book: Node3D
var anim: AnimationPlayer
var left_vp: SubViewport
var right_vp: SubViewport
var leaf_vp: SubViewport
var leaf: MeshInstance3D
var sheet: ImmediateMesh
var leaf_faces: Array[StandardMaterial3D] = []
var blur: ShaderMaterial

# ---- state
var mode := "held"              # held, tuck, equip, view, inspect, resume, sink, away, wait_card, wait_card_close, untuck
var t := 0.0                    # time in the current mode
var current := 0                # the page on the right (0 = contents) as shown
var flip := {}                  # {from, to, n, each, t, dir, k}
var idle := 0.0
var from_pose := {}
var openness := 1.0
var log_lines: Array = []       # timings (tests)
var blur_amount := 0.0
var _right_built := -99
var _page_cache: Array = []

func setup(panel: CanvasLayer) -> void:
	gp = panel
	name = "ViewMode"
	Pages.fonts()
	blur_layer = CanvasLayer.new()
	blur_layer.name = "ViewBlur"
	blur_layer.layer = gp.layer - 1 # under the panel's title and Close row
	add_child(blur_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	blur = ShaderMaterial.new()
	blur.shader = sh
	rect.material = blur
	blur_layer.add_child(rect)
	_book_world()
	_set_pose(_held_pose())
	_show(false)

func _show(on: bool) -> void:
	blur_layer.visible = on
	book_layer.visible = on
	set_process(on)
	book_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for v in [left_vp, right_vp, leaf_vp]: v.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

func _held_rig() -> Node3D:
	return gp.world.pcombat.rig if gp != null and gp.world != null and gp.world.get("pcombat") != null else null

# ================================================================ scene building

func _book_world() -> void:
	book_layer = CanvasLayer.new()
	book_layer.name = "ViewBook"
	book_layer.layer = gp.layer + 2 # above the panel and the Player ID studio
	add_child(book_layer)
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book_layer.add_child(box)
	book_vp = SubViewport.new()
	book_vp.transparent_bg = true
	book_vp.own_world_3d = true
	book_vp.msaa_3d = Viewport.MSAA_4X
	book_vp.handle_input_locally = false
	box.add_child(book_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.9, 0.78)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	book_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, -28, 0)
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.25
	book_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.light_energy = 0.45
	book_vp.add_child(rim)
	book_cam = Camera3D.new()
	book_cam.fov = 40
	book_vp.add_child(book_cam)
	# A little further back than the preview (0.70 m): the open book leaves a clear
	# band above for the panel's title and below for its Close label [Sir, 2026-11-20].
	book_cam.look_at_from_position(Vector3(0, CAM_H, 0.16 * CAM_H / 0.70), Vector3(0, 0, 0.012), Vector3(0, 0, -1))
	holder = Node3D.new()
	book_vp.add_child(holder)
	book = BOOK.instantiate()
	holder.add_child(book)
	anim = book.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("Equip")
	left_vp = _page_vp("Left")
	right_vp = _page_vp("Right")
	leaf_vp = _page_vp("Leaf")
	var left_mat := _ink(left_vp, BaseMaterial3D.CULL_DISABLED)
	var right_mat := _ink(right_vp, BaseMaterial3D.CULL_DISABLED)
	for m in book.find_children("*", "MeshInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in m.mesh.get_surface_count():
			var mat: Material = m.get_active_material(s)
			if mat == null: continue
			if mat.resource_name.begins_with("Folio"): m.set_surface_override_material(s, left_mat)
			elif mat.resource_name == "Endpapers": m.set_surface_override_material(s, right_mat)
	leaf_faces = [_ink(left_vp, BaseMaterial3D.CULL_BACK), _ink(leaf_vp, BaseMaterial3D.CULL_BACK)]
	sheet = ImmediateMesh.new()
	leaf = MeshInstance3D.new()
	leaf.name = "Leaf"
	leaf.mesh = sheet
	leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaf.visible = false
	book.add_child(leaf)

func _page_vp(n: String) -> SubViewport:
	var v := SubViewport.new()
	v.name = n
	v.size = PAGE_PX
	v.disable_3d = true
	v.transparent_bg = false
	v.gui_embed_subwindows = true
	v.handle_input_locally = true
	v.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(v)
	return v

func _ink(v: SubViewport, cull: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = v.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = cull
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m

func _fill(v: SubViewport, page: Control) -> void:
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	v.add_child(page)

func _build_left() -> void:
	_fill(left_vp, Pages.loadout(self))

func _build_right(idx: int) -> void:
	_fill(right_vp, Pages.page(self, idx))
	_right_built = idx

func _build_leaf(idx: int) -> void:
	_fill(leaf_vp, Pages.page(self, idx))

## The panel's state changed (equip, unlock, assembly, a search...): redraw the
## pages as they are. The right page follows the panel unless a turn is drawing.
func rebuild() -> void:
	_page_cache = []
	_build_left()
	if not flip.is_empty() and gp.page_number(gp.selected) != int(flip.to): # the panel moved on mid-turn: that turn is over
		flip = {}
		leaf.visible = false
	if flip.is_empty():
		current = gp.page_number(gp.selected)
		_build_right(current)

# ================================================================ the host view_pages.gd reads

var pages: Array:
	get: return _pages()
var loadout: Dictionary:
	get:
		var out := {}
		for slot in Pages.SLOTS:
			var pg: Resource = gp.world.pcombat.loadout.get(slot)
			out[slot] = String(pg.id) if pg != null else ""
		return out
var rank: String:
	get: return String(gp.session().progression.rank)
var notice: String:
	get: return gp.status_text
var toc_query: String:
	get: return gp.toc_query
var toc_kind: int:
	get: return gp.toc_kind
var assembly: Dictionary:
	get:
		if gp.mode != "assembly" or gp.attempt.is_empty(): return {}
		return {"id": gp.selected, "lines": gp.assembly_lines(), "picked": gp.picked, "wrong": gp.wrong, "note": gp.status_text if not gp.wrong.is_empty() else ""}

# One page as view_pages wants it, from the live page resource.
func _page_dict(id: String) -> Dictionary:
	var g: RefCounted = gp.grimoire()
	var pg: Resource = g.page(id)
	if pg == null: return {}
	var atk: bool = int(pg.kind) == 0
	return {"id": id, "title": pg.title, "kind": pg.kind_name(), "kind_i": int(pg.kind), "rank": pg.rank_req,
		"short": gp.short_info(pg), "description": pg.description, "special": pg.special_description if atk else "",
		"stats": gp.page_stats(id), "code": pg.code_lines, "lesson": pg.lesson, "tip": pg.hints,
		"topic": CodeAssembly.topic(id), "icon": gp.page_icon(id)}

func _pages() -> Array:
	if _page_cache.is_empty():
		for id in gp.grimoire().listed(): _page_cache.append(_page_dict(id))
	return _page_cache

func page_at(idx: int) -> Dictionary:
	var l := _pages()
	return l[idx - 1] if idx >= 1 and idx <= l.size() else {}

func page_by_id(id: String) -> Dictionary:
	for p in _pages():
		if p.id == id: return p
	return {}

func index_of(id: String) -> int:
	return maxi(0, gp.page_number(id))

func is_unlocked(id: String) -> bool:
	return gp.grimoire().is_unlocked(id)

func unlocked_count() -> int:
	return _pages().filter(func(p): return is_unlocked(p.id)).size()

func rank_ok(req: String) -> bool:
	return "EDCBAS".find(rank) >= "EDCBAS".find(req)

func selected_page() -> Dictionary:
	return page_at(current)

func equipped_on(id: String) -> String:
	for s in Pages.SLOTS:
		if loadout.get(s, "") == id: return "Passive [5]" if s == "passive" else "Page %s [%s]" % [Pages.ROMAN[int(s.right(1)) - 1], s.right(1)]
	return ""

func can_equip_selected(slot: String) -> bool:
	var pg := selected_page()
	if pg.is_empty() or not is_unlocked(pg.id) or not rank_ok(pg.rank): return false
	return (int(pg.kind_i) == 3) == (slot == "passive")

func toc_ids() -> Array:
	return gp.toc_ids()

# ---- page actions: forwarded to the panel's rules
func on_search(text: String) -> void:
	gp.toc_query = text
	if is_instance_valid(toc_list): Pages.fill_toc(self, toc_list)

func on_kind(kind: int) -> void:
	gp.toc_kind = kind
	if is_instance_valid(toc_list): Pages.fill_toc(self, toc_list)

func on_slot(slot: String) -> void:
	if gp.selected == "":
		var id: String = loadout.get(slot, "")
		if id != "": jump_to(index_of(id)) # from the contents: open that slot's page
		else: gp.equip_selected(slot)
		return
	gp.equip_selected(slot)

func on_unequip(slot: String) -> void:
	gp.unequip(slot)

func on_start_assembly(id: String) -> void:
	gp.start_assembly(id)

func on_pick(k: int) -> void:
	gp.pick(k)

func on_submit() -> void:
	gp.submit()

func on_cancel_assembly() -> void:
	gp.cancel_assembly()

func jump_to(idx: int) -> void:
	var l: Array = gp.pages()
	if idx < 0 or idx >= l.size(): return
	gp._jump_to(String(l[idx]))

func manual_flip(step: int) -> void:
	gp.flip(step)

# ================================================================ open / close (the panel calls these)

var _after := ""                # where a sink leads: "untuck" (closing) or "away" (to the Player ID)

func _prepare_pages() -> void:
	flip = {}
	leaf.visible = false
	idle = 0.0
	_page_cache = []
	current = 0 # View always opens on the contents [Sir]
	_build_right(0)
	_build_left()

## Tab: the held book tucks away, then this one rises from the bottom middle.
func open() -> void:
	_prepare_pages()
	var rig = _held_rig()
	if rig != null: rig.tuck(true)
	holder.visible = false
	_show(true)
	_go("tuck")

## Tab again (or Esc): the open book goes down, then the held book comes back.
func close() -> void:
	flip = {}
	leaf.visible = false
	right_vp.gui_release_focus()
	match mode:
		"held", "untuck": return
		"away", "wait_card", "wait_card_close": _go("wait_card_close") # the card goes down first
		_:
			_after = "untuck"
			_go("sink")

## D: to the Player ID. The book goes down; the card comes up once it is gone.
func to_card() -> void:
	flip = {}
	leaf.visible = false
	right_vp.gui_release_focus()
	if mode in ["held", "untuck", "away", "wait_card_close"]: return
	if mode in ["tuck", "wait_card"]:
		holder.visible = false
		_go("away")
		return
	_after = "away"
	_go("sink")

## A: back to the Grimoire. The card goes down; then the book comes up and opens.
func from_card() -> void:
	if is_open(): return
	if mode == "sink": # A straight after D: the card never came up, so the book turns back
		_go("equip")
		return
	_prepare_pages()
	var rig = _held_rig()
	if rig != null: rig.tuck(true) # opened on the Player ID: the held book is still out
	holder.visible = false
	_show(true)
	_go("wait_card")

func is_open() -> bool:
	return mode in ["equip", "view", "inspect", "resume"]

## No book on screen (the Player ID card may come up).
func book_gone() -> bool:
	return mode in ["away", "held", "untuck", "wait_card_close"]

func _card_gone() -> bool:
	var st = gp.stage if gp != null else null
	return st == null or not st.has_method("card_gone") or st.card_gone()

## The transitions carry the book closed, lying front cover up (as the idle
## inspection shows it: _cover_pose at -90 deg), its cover centred on `at`.
func _closed_pose(at: Vector3, s: float) -> Dictionary:
	var rot := Basis(Vector3.BACK, -PI / 2)
	return {"pos": at - rot * Vector3(0, 0.155, 0) * s, "basis": rot * Basis(Vector3.UP, PI / 2), "scale": s, "open": 0.0}

## Where the book comes up from and goes down to: below the bottom middle.
func bottom_point() -> Vector3:
	var vs := Vector2(book_vp.size) if book_vp and book_vp.size.x > 0 else Vector2(1920, 1080)
	return book_cam.project_position(Vector2(vs.x * 0.5, vs.y * 1.45), CAM_H)

func _bottom_pose() -> Dictionary:
	return _closed_pose(bottom_point(), 0.8)

## Opening `w` 0..1 at the centre, the way a book lying closed opens: the back
## half stays flat while the front cover swings over (the whole book turns
## about its spine as the Equip clip opens both halves). `tilt`: the alive lean.
func _opening_pose(w: float, tilt: Basis) -> Dictionary:
	var top := _closed_pose(Vector3.ZERO, 1.0)
	var v := _view_pose()
	var rot := Basis(Vector3.BACK, -PI / 2 * (1.0 - w))
	return {"pos": (top.pos as Vector3).lerp(v.pos, w), "basis": tilt * rot * Basis(Vector3.UP, PI / 2), "scale": 1.0, "open": w}

func _alive_basis() -> Basis:
	return Basis(Vector3.FORWARD, alive_tilt.x) * Basis(Vector3.RIGHT, alive_tilt.y) * Basis(Vector3.UP, alive_roll)

func _start_rise() -> void:
	_set_pose(_bottom_pose())
	holder.visible = true
	_go("equip")

# ================================================================ flipping

## The panel turned the book from page `from` to `to`: draw it, every page
## between flipped, `total` seconds in all (the panel's state already moved).
func turn(from: int, to: int, total: float) -> void:
	if not flip.is_empty(): _end_flip() # a new turn mid-turn: the last one lands at once
	if from == to or not is_open():
		current = to
		_build_right(to)
		return
	var n := absi(to - from)
	var dir := signi(to - from)
	flip = {"from": from, "to": to, "n": n, "each": total / n, "t": 0.0, "dir": dir, "k": -1, "started": Time.get_ticks_msec(), "fresh": true, "total": total}
	current = from
	if dir > 0: _build_right(to)   # forward: the target lies under the lifting leaves
	else: _build_right(from)

func _end_flip() -> void:
	log_lines.append("flip %d -> %d: %d leaves in %.2f s total (%.3f s each)" % [flip.from, flip.to, flip.n, float(flip.each) * int(flip.n), flip.each])
	current = int(flip.to)
	if _right_built != current: _build_right(current)
	_build_left()
	flip = {}
	leaf.visible = false

func _step_flip(delta: float) -> void:
	if flip.is_empty():
		leaf.visible = false
		return
	if flip.fresh: flip.fresh = false   # the frame that started it does not count
	else: flip.t += delta
	var n: int = flip.n
	var each: float = flip.each
	var k := mini(int(flip.t / each), n - 1)
	if k != int(flip.k):
		flip.k = k
		# forward: the leaf is the page being turned away (from + k); backward:
		# the page that lands (from - k - 1), the last one being the target
		_build_leaf(int(flip.from) + k if int(flip.dir) > 0 else int(flip.from) - k - 1)
	var local := clampf((flip.t - k * each) / each, 0.0, 1.0)
	draw_sheet(sheet, leaf_faces, local, int(flip.dir))
	leaf.visible = true
	if flip.t >= n * each: _end_flip()

## The turning leaf (from the Held grimoire rig): a thin two-sided sheet
## whose free edge trails the spine and curls as it crosses.
static func draw_sheet(target: ImmediateMesh, faces: Array[StandardMaterial3D], progress: float, direction: int) -> void:
	var phase := smoothstep(0.0, 1.0, progress)
	if direction > 0: phase = 1.0 - phase
	target.clear_surfaces()
	for face in 2:
		target.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, faces[face])
		var edge := [Vector2.ZERO, Vector2.ZERO]
		var lift := sin(PI * phase)
		for column in 33:
			var u := column / 32.0
			for row in 2:
				var top := row if face == 0 else 1 - row
				if column > 0:
					var angle := PI * phase + lift * (0.66 - 1.20 * u + 0.24 * (0.5 - top) * u)
					edge[top] += Vector2(-cos(angle), sin(angle)) * (0.298 / 32.0)
				var yz: Vector2 = edge[top]
				var height := 0.028 + lerpf(0.038, 0.014, phase) * u + yz.y
				target.surface_set_uv(Vector2(1 - u if face == 0 else u, top))
				target.surface_add_vertex(Vector3(0.217 * (1 - 2 * top), height, yz.x))
		target.surface_end()

# ================================================================ poses and modes

func _view_pose() -> Dictionary:
	# the open book, plus its "alive" sway toward the cursor (_update_alive)
	var b := Basis(Vector3.FORWARD, alive_tilt.x) * Basis(Vector3.RIGHT, alive_tilt.y) * Basis(Vector3.UP, alive_roll) * Basis(Vector3.UP, PI / 2)
	return {"pos": alive_shift, "basis": b, "scale": 1.0, "open": 1.0}

# ---- alive: the book leans and looks toward the cursor [Sir, 2026-11-20]
const LOOK_YAW := 0.13          # rad (~7.5 deg) at the screen edge, left / right
const LOOK_PITCH := 0.10        # rad (~5.7 deg) at the screen edge, up / down
const LOOK_SHIFT := 0.014       # m it drifts toward the cursor
const LOOK_STIFF := 38.0        # spring: how eagerly it turns
const LOOK_DAMP := 9.0          # spring: how quickly it settles (a small overshoot)
const BREATH_S := 4.2           # one slow breath
var alive_tilt := Vector2.ZERO   # (yaw, pitch) now
var alive_vel := Vector2.ZERO
var alive_shift := Vector3.ZERO
var alive_roll := 0.0
var alive_time := 0.0
var cursor_override := Vector2(-1, -1) # tests: a cursor in viewport pixels (-1: the real mouse)

## The cursor as -1..1 across the view (0 at the centre).
func cursor_unit() -> Vector2:
	var vp := gp.get_viewport()
	var vs := vp.get_visible_rect().size
	var m: Vector2 = cursor_override if cursor_override.x >= 0.0 else vp.get_mouse_position()
	return ((m / vs) * 2.0 - Vector2.ONE).clamp(Vector2(-1, -1), Vector2(1, 1))

func _update_alive(delta: float) -> void:
	alive_time += delta
	var c := cursor_unit()
	if mode != "view" and mode != "resume": c = Vector2.ZERO
	# the face turns to look at the cursor: right -> it turns right, up -> it tips up
	var target := Vector2(c.x * LOOK_YAW, c.y * LOOK_PITCH)
	var acc := (target - alive_tilt) * LOOK_STIFF - alive_vel * LOOK_DAMP
	alive_vel += acc * delta
	alive_tilt += alive_vel * delta
	var breath := sin(alive_time * TAU / BREATH_S)
	alive_shift = alive_shift.lerp(Vector3(c.x * LOOK_SHIFT, 0.004 * breath, c.y * LOOK_SHIFT * 0.7), 1.0 - exp(-5.0 * delta))
	alive_roll = 0.006 * sin(alive_time * TAU / (BREATH_S * 1.7))

## The Held mode's place: the lower corner on the book's side, tilted to the eye.
func _held_pose() -> Dictionary:
	var vs := Vector2(book_vp.size) if book_vp and book_vp.size.x > 0 else Vector2(1920, 1080)
	var right := _book_right()
	var pos := book_cam.project_position(Vector2(vs.x * (0.82 if right else 0.18), vs.y * 0.93), 0.62)
	var left_pose := Basis.looking_at(Vector3(0.24, -1, 0.26).normalized(), Vector3(1, 0.14, 0)).inverse()
	var mirror := Basis.from_scale(Vector3(-1, 1, 1))
	var pose := mirror * left_pose * mirror * Basis(Vector3.UP, PI) if right else left_pose
	return {"pos": pos, "basis": book_cam.global_transform.basis * pose, "scale": 0.4, "open": 1.0}

func _book_right() -> bool:
	var rig = _held_rig()
	return rig == null or bool(rig.book_right)

func _pose_now() -> Dictionary:
	return {"pos": holder.position, "basis": holder.basis.orthonormalized(), "scale": holder.basis.get_scale().x, "open": openness}

func _set_pose(p: Dictionary) -> void:
	holder.position = p.pos
	holder.basis = (p.basis as Basis).orthonormalized().scaled(Vector3.ONE * float(p.scale))
	openness = float(p.open)
	anim.seek(clampf(openness, 0.0, 1.0) * anim.get_animation("Equip").length, true)

func _blend(a: Dictionary, b: Dictionary, w: float, arc := 0.0) -> Dictionary:
	var q := (a.basis as Basis).get_rotation_quaternion().slerp((b.basis as Basis).get_rotation_quaternion(), w)
	var pos: Vector3 = (a.pos as Vector3).lerp(b.pos, w) + Vector3(0, arc * sin(PI * w), 0)
	return {"pos": pos, "basis": Basis(q), "scale": lerpf(a.scale, b.scale, w), "open": lerpf(a.open, b.open, w)}

func _go(m: String) -> void:
	mode = m
	t = 0.0
	from_pose = _pose_now()
	log_lines.append("mode %s" % m)

func _process(delta: float) -> void:
	step(delta)

## One frame of the View (tests call it with a fixed delta).
func step(delta: float) -> void:
	t += delta
	_update_alive(delta)
	var b := 0.0
	match mode:
		"held":
			holder.visible = false
		"tuck": # the held book closes and tucks down first
			holder.visible = false
			b = minf(t / TUCK_WAIT_S, 1.0) * 0.5
			var rig = _held_rig()
			if (rig != null and rig.tuck_done()) or t >= TUCK_WAIT_S: _start_rise()
		"wait_card": # the Player ID card goes down first
			holder.visible = false
			b = 0.5
			var rig = _held_rig()
			var tucked: bool = rig == null or rig.tuck_done() or t >= TUCK_WAIT_S
			if _card_gone() and tucked: _start_rise()
		"wait_card_close":
			holder.visible = false
			if _card_gone():
				var rig = _held_rig()
				if rig != null: rig.tuck(false)
				_go("untuck")
		"equip": # up from the bottom middle, closed and cover up, then open
			holder.visible = true
			var w := smoothstep(0.0, 1.0, minf(t / RISE_S, 1.0))
			if t < RISE_S: _set_pose(_blend(from_pose, _closed_pose(Vector3.ZERO, 1.0), w))
			else: _set_pose(_opening_pose(smoothstep(0.0, 1.0, minf((t - RISE_S) / OPEN_S, 1.0)), _alive_basis()))
			b = 0.5 + 0.5 * w
			if t >= EQUIP_S:
				_go("view")
				idle = 0.0
		"sink": # it closes (the front cover swings back over), then goes down to the bottom middle
			var shut := smoothstep(0.0, 1.0, minf(t / SHUT_S, 1.0))
			var w := smoothstep(0.0, 1.0, clampf((t - SHUT_S) / SINK_S, 0.0, 1.0))
			if t < SHUT_S:
				var open_now := lerpf(float(from_pose.open), 0.0, shut)
				var lean := Basis(Quaternion((from_pose.basis as Basis) * Basis(Vector3.UP, PI / 2).inverse()).slerp(Quaternion.IDENTITY, shut))
				var p := _opening_pose(open_now, lean if from_pose.open > 0.5 else Basis.IDENTITY)
				if float(from_pose.open) <= 0.5: p = _blend(from_pose, _closed_pose(Vector3.ZERO, 1.0), shut) # shut already (the idle inspection): just settle
				_set_pose(p)
			else:
				_set_pose(_blend(_closed_pose(Vector3.ZERO, 1.0), _bottom_pose(), w))
			b = 1.0 - w
			if t >= UNEQUIP_S:
				holder.visible = false
				if _after == "untuck":
					var rig = _held_rig()
					if rig != null: rig.tuck(false)
					_go("untuck")
				else: _go("away")
		"away": # the Player ID has the screen
			holder.visible = false
		"untuck": # the held book comes back up to the hand and opens
			holder.visible = false
			var rig = _held_rig()
			if rig == null or rig.home() or t >= UNTUCK_WAIT_S:
				_go("held")
				_show(false)
		"view":
			_set_pose(_view_pose())
			b = 1.0
			_step_flip(delta)
			if flip.is_empty() and gp.mode == "browse" and not _typing():
				idle += delta
				if idle >= IDLE_AFTER_S: _start_inspect()
		"inspect":
			b = 1.0
			_step_inspect(delta)
		"resume":
			var w := smoothstep(0.0, 1.0, minf(t / RESUME_S, 1.0))
			_set_pose(_blend(from_pose, _view_pose(), w))
			b = 1.0
			_step_flip(delta)
			if t >= RESUME_S:
				_go("view")
				idle = 0.0
	blur_amount = b
	blur.set_shader_parameter("amount", b)

func _typing() -> bool:
	return right_vp.gui_get_focus_owner() is LineEdit

## Any press resets the idle clock (the panel calls this from its input).
func poke() -> void:
	idle = 0.0

# ---- the idle inspection [Sir]: closes, front cover, back cover, opens, riffles every page
const IN_CLOSE := 0.6
const IN_FRONT := 0.9
const IN_TURN := 1.8
const IN_BACK := 0.5
const IN_DOWN := 0.9
const IN_OPEN := 0.5
const INSPECT_S := IN_CLOSE + IN_FRONT + IN_TURN + IN_BACK + IN_DOWN + IN_OPEN + RIFFLE_S

func _start_inspect() -> void:
	idle = 0.0
	gp.show_contents() # it ends on the contents
	_go("inspect")
	log_lines.append("idle inspection after %.1f s" % IDLE_AFTER_S)

func _step_inspect(delta: float) -> void:
	var v := _view_pose()
	var tt := t
	var lift := Vector3(0, -0.06, 0.0)
	if tt < IN_CLOSE:                                            # 1. close
		var w := smoothstep(0.0, 1.0, tt / IN_CLOSE)
		_set_pose({"pos": Vector3.ZERO, "basis": v.basis, "scale": 1.0, "open": 1.0 - w})
		return
	tt -= IN_CLOSE
	if tt < IN_FRONT:                                            # 2. raise it, front cover to the eye
		var w := smoothstep(0.0, 1.0, tt / IN_FRONT)
		_cover_pose(-PI / 2 * w, lift * w, lerpf(1.0, 0.86, w))
		return
	tt -= IN_FRONT
	if tt < IN_TURN:                                             # 3. turn it over: spine, then the back cover
		var w := smoothstep(0.0, 1.0, tt / IN_TURN)
		_cover_pose(-PI / 2 + PI * w, lift, 0.86)
		return
	tt -= IN_TURN
	if tt < IN_BACK:                                             # hold the back cover
		_cover_pose(PI / 2, lift, 0.86)
		return
	tt -= IN_BACK
	if tt < IN_DOWN:                                             # 4. back down, spine first
		var w := smoothstep(0.0, 1.0, tt / IN_DOWN)
		_cover_pose(PI / 2 * (1.0 - w), lift * (1.0 - w), lerpf(0.86, 1.0, w))
		return
	tt -= IN_DOWN
	var last: int = _pages().size()
	if tt < IN_OPEN:                                             # 5. open, on the last page
		if _right_built != last: _build_right(last)
		var w := smoothstep(0.0, 1.0, tt / IN_OPEN)
		_set_pose({"pos": Vector3.ZERO, "basis": v.basis, "scale": 1.0, "open": w})
		return
	tt -= IN_OPEN
	_set_pose(v)                                                 # 6. riffle every page back to the contents
	if flip.is_empty() and tt < RIFFLE_S and last > 0:
		turn(last, 0, RIFFLE_S)
	_step_flip(delta)
	if flip.is_empty() and tt >= RIFFLE_S:
		log_lines.append("idle inspection done in %.2f s" % t)
		_go("view")
		idle = 0.0

## The closed book turned about its spine (theta 0 = standing, -90 front cover
## up, +90 back cover up), re-centred on the cover so it turns in place.
func _cover_pose(theta: float, lift: Vector3, s: float) -> void:
	var r := Basis(Vector3.BACK, theta)
	var centre := r * Vector3(0, 0.155, 0)
	_set_pose({"pos": lift - centre * s, "basis": r * Basis(Vector3.UP, PI / 2), "scale": s, "open": 0.0})

func inspecting() -> bool:
	return mode == "inspect"

## A click or a key during the inspection: back to the open view on the contents.
func interrupt() -> void:
	if mode != "inspect": return
	flip = {}
	leaf.visible = false
	current = 0
	_build_right(0)
	_build_left()
	_go("resume")
	log_lines.append("idle inspection interrupted")

# ================================================================ input

## A mouse event from the panel: onto a page's controls, or nothing. True if used.
func pointer(event: InputEventMouse) -> bool:
	if mode != "view" or not flip.is_empty(): return false
	var hit := page_hit(event.position)
	if hit.is_empty():
		if event is InputEventMouseButton and event.pressed: right_vp.gui_release_focus()
		return false
	var e: InputEventMouse = event.duplicate()
	e.position = hit.px
	e.global_position = hit.px
	(hit.vp as SubViewport).push_input(e, true)
	return true

## Where a screen point meets a page: {vp, px, left} or {}. It follows the
## tilted book (the ray is taken into the book holder's space).
func page_hit(screen: Vector2) -> Dictionary:
	var o := book_cam.project_ray_origin(screen)
	var d := book_cam.project_ray_normal(screen)
	var inv := holder.global_transform.affine_inverse()
	var ol := inv * o
	var dl := inv.basis * d
	if absf(dl.y) < 1e-5: return {}
	var s := (PAGE_Y - ol.y) / dl.y
	if s < 0: return {}
	var p := ol + dl * s
	var v := (PAGE_TOP - p.x) / PAGE_H
	if v < 0.0 or v > 1.0: return {}
	if p.z >= -PAGE_W and p.z < 0.0:
		return {"vp": left_vp, "px": Vector2((p.z + PAGE_W) / PAGE_W, v) * Vector2(PAGE_PX), "left": true}
	if p.z >= 0.0 and p.z <= PAGE_W:
		return {"vp": right_vp, "px": Vector2(p.z / PAGE_W, v) * Vector2(PAGE_PX), "left": false}
	return {}

## The open book's screen rect: its four page corners projected (tests).
func book_screen_rect() -> Rect2:
	var r := Rect2(screen_of(true, Vector2.ZERO), Vector2.ZERO)
	for left in [true, false]:
		for px in [Vector2.ZERO, Vector2(PAGE_PX.x, 0), Vector2(0, PAGE_PX.y), Vector2(PAGE_PX)]:
			r = r.expand(screen_of(left, px))
	return r

## The screen point over a page pixel (tests click through real input).
func screen_of(left: bool, px: Vector2) -> Vector2:
	var uv := px / Vector2(PAGE_PX)
	var z := uv.x * PAGE_W - (PAGE_W if left else 0.0)
	var local := Vector3(PAGE_TOP - uv.y * PAGE_H, PAGE_Y, z)
	return book_cam.unproject_position(holder.global_transform * local)

## A page control's centre in window pixels, for a synthetic click: the screen
## point mapped through the canvas transform (window stretch), as real input arrives.
func window_point_of(control: Control, left: bool) -> Vector2:
	return gp.get_viewport().get_screen_transform() * screen_of(left, control.get_global_rect().get_center())
