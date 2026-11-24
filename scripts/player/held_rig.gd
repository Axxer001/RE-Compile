extends Node3D
# The held grimoire and the Ember Wand [Sir, 2026-11-20; docs/plan-held-grimoire.md],
# ported from the GAME ASSETS "Held Grimoire" pack (HeldRig.gd). The book shows
# the open loadout page in live ink (page_ink.gd); a turn flips every page
# between, over the session's 0.5 s turn; the wand casts. Book in the left
# hand, wand in the right by default (Settings mirrors the pair).
# Presentation only: what is open, what casts, MP and cooldowns all come from
# player_combat (the pack's own mana, timers and attack gate are not used).
#
# Usage (child of the player's camera): var r := HeldRig.new(); r.pc = pcombat; camera.add_child(r)

const Ink = preload("res://scripts/ui/page_ink.gd")
const EmberWand = preload("res://scripts/player/ember_wand.gd")
const BOOK := preload("res://assets/held_grimoire/rose_compass_grimoire.glb")
const EQUIP_TIME := 0.72
const BOOK_AT := Vector3(-0.37, -0.34, -0.64)   # the pack's left-hand pose; mirrored for the right
const BOOK_SCALE := 0.84
const REPAINT_S := 0.075

var pc: Node3D                  # player_combat

# Tab [Sir, 2026-11-20]: the held book closes, then tucks down out of view
# (TUCK_S each); untucked, it comes back up to the hand, then opens. The wand stays.
const TUCK_S := 0.3
var tucked := false
var _untucking := false
var book_right := false          # [Sir] default: book left, wand right
var book: Node3D
var wand: Node3D
var animation: AnimationPlayer
var leaf: MeshInstance3D
var sheet: ImmediateMesh
var leaf_faces: Array[StandardMaterial3D] = []
var motion: Node3D
var pages: Array[SubViewport] = []
var closed_basis: Basis
var book_basis: Basis
var reveal := 0.0
var openness := 0.0
var snap := 0.0
var impact := 0.0
var shown := 0                  # the page the ink shows (follows the turn's flips)
var flip := -1                  # the flip in progress (-1 none)
var flips_drawn := 0            # flips finished (tests)
var held := true                # equipped (false: stowed, the player is dead)
var book_clip := ""             # the book clip posed this frame (tests): Equip, Idle, PageFlip1-4
var played := {}                # book clip -> frames posed (tests: the coverage table)
var _turn_seen := -INF
var _redraw := 0.0

func _ready() -> void:
	name = "HeldRig"
	book = BOOK.instantiate()
	book.name = "Book"
	add_child(book)
	wand = EmberWand.new()
	wand.player = pc.world.player if pc != null else null
	add_child(wand)
	animation = book.find_child("AnimationPlayer", true, false) as AnimationPlayer
	animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	motion = wand.asset.find_child("Motion", true, false) as Node3D
	var left_page := _paper(false)
	var right_page := _paper(true)
	for face in [left_page, right_page]: # the turning leaf: thin, two-sided
		var paper: StandardMaterial3D = face.duplicate()
		paper.cull_mode = BaseMaterial3D.CULL_BACK
		leaf_faces.append(paper)
	sheet = ImmediateMesh.new()
	leaf = MeshInstance3D.new()
	leaf.name = "Leaf"
	leaf.mesh = sheet
	leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaf.visible = false
	book.add_child(leaf)
	for mesh in book.find_children("*", "MeshInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(s)
			if material == null: continue
			if material.resource_name.begins_with("Folio"): mesh.set_surface_override_material(s, left_page)
			elif material.resource_name == "Endpapers": mesh.set_surface_override_material(s, right_page)
			elif material.resource_name == "Gilt-tooled oxblood leather":
				var cover := material.duplicate() as StandardMaterial3D
				cover.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.set_surface_override_material(s, cover)
	set_book_right(book_right)
	animation.play("Equip")
	wand.move(&"Equip")

# Equip (a new run) or stow (death): the book's Equip clip forwards or backwards
# over EQUIP_TIME, with the wand's Equip / Stow.
func equip(on: bool) -> void:
	if held == on: return
	held = on
	if wand: wand.stow(not on)
	repaint()

# Poses the book on one of its clips at `t` seconds (manual mode: the rig drives time).
func _pose(clip_name: String, t: float) -> void:
	if animation.current_animation != clip_name: animation.play(clip_name)
	animation.seek(clamp(t, 0.0, animation.get_animation(clip_name).length), true)
	book_clip = clip_name
	played[clip_name] = int(played.get(clip_name, 0)) + 1

func set_book_right(on: bool) -> void:
	book_right = on
	# The pack's pose is for the left hand. The right hand's mirrors it: M * B * M
	# (M the x reflection) tilts the book the other way, but as a rotation it also
	# turns the page content upside down, so the book is then spun half a turn about
	# its own page normal (local y) to read upright again.
	var left_pose := Basis.looking_at(Vector3(0.24, -1, 0.26).normalized(), Vector3(1, 0.14, 0)).inverse()
	var mirror := Basis.from_scale(Vector3(-1, 1, 1))
	book_basis = mirror * left_pose * mirror * Basis(Vector3.UP, PI) if on else left_pose
	var to_eye := -Vector3(-BOOK_AT.x if on else BOOK_AT.x, BOOK_AT.y, BOOK_AT.z).normalized()
	var across := Vector3.UP.cross(to_eye).normalized()
	closed_basis = Basis(to_eye.cross(across), across, -to_eye)
	if wand: wand.set_left(on)

func _paper(index_page: bool) -> StandardMaterial3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(440, 608)
	viewport.disable_3d = true
	add_child(viewport)
	var ink: Control = Ink.new()
	ink.rig = self
	ink.index_page = index_page
	ink.size = viewport.size
	viewport.add_child(ink)
	pages.append(viewport)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var m := StandardMaterial3D.new()
	m.resource_name = "Held ink"
	m.albedo_texture = viewport.get_texture()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if index_page else BaseMaterial3D.CULL_BACK
	return m

func repaint() -> void:
	for v in pages:
		v.get_child(0).queue_redraw()
		v.render_target_update_mode = SubViewport.UPDATE_ONCE

func now() -> float:
	return pc.world.session.run.time if pc != null else 0.0

# What the ink draws for a slot (0-3): {title, mp, cd, frac, left, state, special}.
func page_info(i: int) -> Dictionary:
	if pc == null or i >= pc.SPELL_SLOTS.size(): return {}
	var slot: String = pc.SPELL_SLOTS[i]
	var pg: Resource = pc.loadout.get(slot)
	if pg == null: return {"title": "Empty page", "empty": true}
	var t := now()
	var view: Dictionary = pc.slot_view(t).get(slot, {})
	var attack: bool = pg.kind == pc.AbilityPage.Kind.ATTACK
	var left: float = pc.special_remaining(t) if attack else pc.remaining(slot, t)
	var frac: float = pc.special_fraction(t) if attack else pc.fraction(slot, t)
	return {"title": pg.title, "mp": pg.mp_cost, "cd": pg.special_cooldown_s if attack else pg.cooldown_s,
		"left": left if left < INF else 0.0, "frac": frac, "state": String(view.get("state", "ready")), "special": attack, "attack": attack}

# The status page: the passive and every effect, buff and debuff with time left.
func status_info() -> Dictionary:
	if pc == null: return {"passive": "", "effects": []}
	var pg: Resource = pc.loadout.get("passive")
	var rows: Array = pc.world.effect_rows(now()) if pc.world.has_method("effect_rows") else []
	return {"passive": pg.title if pg else "", "effects": rows}

# A cast was accepted (player_combat): the wand's kick and the book's snap.
func cast(special: bool, attack: bool) -> void:
	snap = 1.35 if special else 1.0
	if wand: wand.trigger(&"Attack" if attack and not special else &"Cast")

func damage(stagger: bool) -> void:
	impact = 1.65 if stagger else 1.0
	if wand: wand.trigger(&"Stagger" if stagger else &"Damage")

func _process(delta: float) -> void:
	step(delta)

## The book is tucked away (closed and down): the View may take over.
func tuck_done() -> bool:
	return tucked and reveal <= 0.0

## The book is back in the hand and open again.
func home() -> bool:
	return not tucked and not _untucking and reveal >= 1.0

## A new run: no Grimoire View is holding the book any more.
func clear_tuck() -> void:
	tucked = false
	_untucking = false

func tuck(on: bool) -> void:
	if tucked == on: return
	tucked = on
	_untucking = not on

func step(delta: float) -> void:
	var open_target: bool = held and (pc == null or not pc.book_closed)
	var before := openness
	if tucked: # close first, then down
		openness = move_toward(openness, 0.0, delta / TUCK_S)
		if openness <= 0.0: reveal = move_toward(reveal, 0.0, delta / TUCK_S)
	elif _untucking: # up first (closed), then open
		reveal = move_toward(reveal, 1.0, delta / TUCK_S)
		if reveal >= 1.0: openness = move_toward(openness, 1.0 if open_target else 0.0, delta / TUCK_S)
		if reveal >= 1.0 and (openness >= 1.0 or not open_target): _untucking = false
	else:
		reveal = move_toward(reveal, 1.0 if held else 0.0, delta / EQUIP_TIME)
		openness = move_toward(openness, 1.0 if open_target else 0.0, delta / EQUIP_TIME)
	if openness != before or book_clip == "":
		_pose("Equip", openness * animation.get_animation("Equip").length)
	_follow_turn(openness >= 1.0 and open_target)
	book.visible = reveal > 0.0
	snap = move_toward(snap, 0.0, delta * 4.6)
	impact = move_toward(impact, 0.0, delta * 3.2)
	var carry: Vector3 = motion.position if motion else Vector3.ZERO
	var roll: Vector3 = motion.rotation if motion else Vector3.ZERO
	var lift := smoothstep(0.0, 1.0, reveal)
	var mx := -1.0 if book_right else 1.0 # mirror the left-hand pose for the right hand
	# the wand's Motion is already mirrored by its scale when it is in the left hand
	var cx := carry.x * (-1.0 if (wand and wand.left) else 1.0)
	book.position = Vector3(BOOK_AT.x * mx, BOOK_AT.y, BOOK_AT.z) + Vector3(-cx * 0.72 * mx, carry.y * 0.72, carry.z * 0.52) + Vector3(0, -0.52 * (1.0 - lift), 0.04 * snap)
	var angles := Vector3(roll.x * 0.63 + snap * 0.10, -roll.y * 0.65 * mx, (-roll.z * 0.68 + impact * 0.20 + (1.0 - lift) * 0.31) * mx)
	book.basis = (Basis.from_euler(angles) * closed_basis.slerp(book_basis, smoothstep(0, 1, openness))).scaled(Vector3.ONE * BOOK_SCALE)
	_redraw += delta
	if _redraw >= REPAINT_S:
		_redraw = 0.0
		if visible and reveal > 0.0: repaint()

# The session's turn, drawn: flips() leaves over TURN_S, each its own share;
# the ink changes page halfway through each flip.
func _follow_turn(posing := true) -> void:
	if pc == null: return
	var t := now()
	if posing and pc.turning(t):
		var n: int = pc.flips()
		var u: float = clampf((t - pc.turn_start) / pc.TURN_S, 0.0, n)
		var k := mini(int(u), n - 1)
		var local := u - k
		var dir := signi(pc.turn_to - pc.turn_from)
		if pc.turn_start != _turn_seen:
			_turn_seen = pc.turn_start
			flip = -1
		if k != flip:
			if flip >= 0: flips_drawn += k - flip # a long frame may cross more than one
			flip = k
		var want: int = pc.turn_from + dir * (k + (1 if local >= 0.5 else 0))
		if want != shown:
			shown = want
			repaint()
		_draw_leaf(local, dir)

	else:
		if flip >= 0:
			flips_drawn += 1
			flip = -1
		leaf.visible = false
		if shown != pc.active:
			shown = pc.active
			repaint()

func _draw_leaf(progress: float, direction: int) -> void:
	draw_sheet(sheet, leaf_faces, progress, direction)
	leaf.visible = true

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
				# Integrate the paper tangent: the free edge trails the spine,
				# and the upper corner leads slightly as the sheet curls.
				if column > 0:
					var angle := PI * phase + lift * (0.66 - 1.20*u + 0.24*(0.5-top)*u)
					edge[top] += Vector2(-cos(angle), sin(angle)) * (0.298/32.0)
				var yz: Vector2 = edge[top]
				var height := 0.028 + lerpf(0.038, 0.014, phase)*u + yz.y
				target.surface_set_uv(Vector2(1-u if face == 0 else u, top))
				target.surface_add_vertex(Vector3(0.217*(1-2*top), height, yz.x))
		target.surface_end()
