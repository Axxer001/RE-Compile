extends Node3D
## Orthographic studio for the inventory. Ink UVs and pointer rays share the same physical faces.
const HeldRig = preload("res://scripts/player/held_rig.gd")
const OPEN := Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT)
const CLOSED := Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD)
const CARD_SIZE := Vector2(0.0597, 0.0857)
var ui: CanvasLayer
var ink: SubViewport
var faces: Dictionary = {}
var regions: Dictionary = {}
var prints: Dictionary = {}
var leaf: MeshInstance3D
var sheet := ImmediateMesh.new()
var papers: Array[StandardMaterial3D] = []
var equip: float = 0.0
var book_mix: float = 1.0
var chant_mix: float = 0.0
var card_angle: float = 0.0
# The Player ID card [Sir, 2026-11-20] waits for the View's book to go down,
# then comes up from the bottom middle and flips up (CARD_IN_S); it goes back
# down there before the book comes up. card_in: 0 down, 1 up.
const CARD_IN_S := 0.45
var card_in: float = 0.0
var frozen: ImageTexture = null  # the card's last look, held while the ink draws another tab
var last_pose: float = -1.0
var captured: String = ""
var last_hover: String = ""
@onready var anim: AnimationPlayer = $BookMount/Book.find_child("AnimationPlayer", true, false)

func setup(owner_ui: CanvasLayer, page_texture: SubViewport) -> void:
	ui = owner_ui
	ink = page_texture
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("Equip")
	for side in [-1,1]:
		var key: String = "LeftPaper" if side < 0 else "RightPaper"
		var normal_right := Vector3(0,-0.10 if side < 0 else 0.035,1).normalized()
		var plane := _face(key,$BookMount/Book,Vector2(0.298,0.434))
		plane.basis = Basis(normal_right,Vector3.RIGHT,normal_right.cross(Vector3.RIGHT))
		plane.position = Vector3(0,0.053 + (0.015 if side < 0 else 0.005),side*0.149)
		papers.append(prints[key].duplicate())
		papers.back().cull_mode = BaseMaterial3D.CULL_BACK
	leaf = MeshInstance3D.new()
	leaf.mesh = sheet
	leaf.position.y = 0.036
	$BookMount/Book.add_child(leaf)
	for model in [$Credential,$QuestionCard]:
		var mesh: MeshInstance3D = model.find_children("*","MeshInstance3D",true,false)[0]
		for side in [0,1]:
			var key: String = ("ID" if model == $Credential else "Question")+("Front" if side == 0 else "Back")
			var plane := _face(key,mesh,CARD_SIZE)
			plane.position.z = 0.000485 if side == 0 else -0.000485
			plane.rotation.y = PI if side == 1 else 0.0
			# Pick against the original laminated face and preserve its rounded boundary.
			plane.mesh = null
			plane.set_meta("surface",side)
	set_process(false)

func _face(key: String, parent: Node3D, dimensions: Vector2) -> MeshInstance3D:
	var plane := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = dimensions
	plane.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ink.get_texture()
	plane.material_override = material
	plane.set_meta("dimensions",dimensions)
	parent.add_child(plane)
	faces[key] = plane
	prints[key] = material
	return plane

## The card is all the way down (the View's book may come up).
func card_gone() -> bool:
	return card_in <= 0.0

## Hold the card's look while the ink draws another tab (it would print that
## tab instead: the black card), or give it the live ink back.
func freeze_card(on: bool) -> void:
	var tex: Texture2D = ink.get_texture()
	if on:
		if DisplayServer.get_name() == "headless": return # the dummy renderer has no pixels to hold
		var img: Image = tex.get_image() if tex != null else null
		if img == null or img.is_empty(): return # headless: nothing drawn to hold
		frozen = ImageTexture.create_from_image(img)
		tex = frozen
	else:
		frozen = null
	for key in ["IDFront","IDBack","QuestionBack"]:
		if prints.has(key): prints[key].albedo_texture = tex

func wake() -> void:
	if equip == 0.0:
		book_mix = 1.0 if ui.tab == "grimoire" else 0.0
		card_angle = PI if ui.card_side == "back" else 0.0
		card_in = 0.0
	get_viewport().render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ink.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)

func _bind(key: String, rect: Rect2) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		regions.erase(key)
		return
	if regions.get(key,Rect2()) == rect: return
	regions[key] = rect
	var m: StandardMaterial3D = prints[key]
	var uv: Vector2 = rect.position/Vector2(ink.size)
	var span: Vector2 = rect.size/Vector2(ink.size)
	m.uv1_offset = Vector3(uv.x,uv.y,0)
	m.uv1_scale = Vector3(span.x,span.y,1)

func _card_face(key: String, control: Control) -> void:
	var face: MeshInstance3D = faces[key]
	var mesh: MeshInstance3D = face.get_parent()
	var slot: int = face.get_meta("surface")
	if control != null:
		_bind(key,control.get_global_rect())
		if mesh.get_surface_override_material(slot) != prints[key]: mesh.set_surface_override_material(slot,prints[key])
	else:
		if mesh.get_surface_override_material(slot): mesh.set_surface_override_material(slot,null)
		regions.erase(key)

func _process(delta: float) -> void:
	if ui == null: return
	equip = move_toward(equip,1.0 if ui.visible else 0.0,delta/0.32)
	var card_up: bool = ui.visible and ui.tab == "player_id" and (ui.view == null or ui.view.book_gone())
	card_in = move_toward(card_in,1.0 if card_up else 0.0,delta/CARD_IN_S)
	if equip == 0.0 and card_in == 0.0 and not ui.visible:
		ui.studio_layer.hide()
		get_viewport().render_target_update_mode = SubViewport.UPDATE_DISABLED
		ink.render_target_update_mode = SubViewport.UPDATE_DISABLED
		captured = ""
		last_hover = ""
		set_process(false)
		return
	book_mix = move_toward(book_mix,1.0 if ui.tab == "grimoire" else 0.0,delta/0.38)
	chant_mix = move_toward(chant_mix,1.0 if ui.mode == "chant" and ui.tab == "player_id" else 0.0,delta/0.42)
	card_angle = move_toward(card_angle,PI if ui.card_side == "back" and chant_mix < 0.5 else 0.0,delta*PI/0.42)
	var book_amount: float = smoothstep(0,1,book_mix)*smoothstep(0,1,equip)
	var card_amount: float = smoothstep(0,1,card_in)
	$BookMount.visible = book_amount > 0 and ui.view == null # the Grimoire tab's book is the View's (view_mode.gd) [2026-11-20]
	$Credential.visible = card_amount > 0
	$QuestionCard.visible = card_amount*chant_mix > 0
	if $BookMount.visible:
		_pose_book(book_amount)
	if $Credential.visible:
		var c: float = smoothstep(0,1,chant_mix)
		$Credential.position = Vector3(-0.40*c,-0.012-(1-card_amount)*1.15,0)
		$Credential.scale = Vector3.ONE*9.7*lerpf(1,0.52,c)
		$Credential.rotation = Vector3(-0.06-(1-card_amount)*PI*0.5,card_angle+0.075,-0.018-0.06*c) # flips up as it rises
		_card_alive(delta)
		$Credential.rotation += Vector3(card_tilt.y, card_tilt.x, card_roll)
		$Credential.position += card_shift
		$QuestionCard.position = Vector3(0.20+(1-c)*1.25,-0.012-(1-card_amount)*1.15,0.08)
		$QuestionCard.scale = Vector3.ONE*9.7
		$QuestionCard.rotation = Vector3(-0.025,PI-0.035,0.008)
		if ui.tab == "player_id":
			var card: Control = ui.printed_controls.get("CardFace")
			var chanting: bool = ui.mode == "chant"
			_card_face("IDFront",ui.printed_controls.get("MiniFace") if chanting else (card if ui.card_side=="front" else null))
			_card_face("IDBack",card if not chanting and ui.card_side=="back" else null)
			_card_face("QuestionBack",card if chanting else null)

# ---- the Player ID card is alive [Sir, 2026-11-20], like the View's open book:
# it leans and looks toward the cursor on a spring, drifts toward it and
# breathes. Not in Chant mode: there it eases to rest and holds still.
const CARD_YAW := 0.13          # rad at the screen edge
const CARD_PITCH := 0.10
const CARD_SHIFT := 0.012       # drift toward the cursor (studio units)
const CARD_STIFF := 38.0
const CARD_DAMP := 9.0
const CARD_BREATH_S := 4.2
var card_tilt := Vector2.ZERO   # (yaw, pitch)
var card_vel := Vector2.ZERO
var card_shift := Vector3.ZERO
var card_roll := 0.0
var card_time := 0.0
var card_life := 1.0            # 1 alive, 0 held still (Chant)
var cursor_override := Vector2(-1, -1) # tests: viewport pixels (-1: the real mouse)

func _card_alive(delta: float) -> void:
	var still: bool = ui.mode == "chant"
	card_life = move_toward(card_life, 0.0 if still else 1.0, delta / 0.3)
	card_time += delta * card_life
	var vp := ui.get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size
	var m: Vector2 = cursor_override if cursor_override.x >= 0.0 else vp.get_mouse_position()
	var c: Vector2 = ((m / vs) * 2.0 - Vector2.ONE).clamp(Vector2(-1, -1), Vector2(1, 1)) * card_life
	var target := Vector2(c.x * CARD_YAW, c.y * CARD_PITCH)
	card_vel += ((target - card_tilt) * CARD_STIFF - card_vel * CARD_DAMP) * delta
	card_tilt += card_vel * delta
	if still and card_life <= 0.0: # held: no sway at all
		card_tilt = card_tilt.move_toward(Vector2.ZERO, delta * 0.5)
		card_vel = Vector2.ZERO
	var breath := sin(card_time * TAU / CARD_BREATH_S) * card_life
	card_shift = card_shift.lerp(Vector3(c.x * CARD_SHIFT, -c.y * CARD_SHIFT * 0.7 + 0.0035 * breath, 0), 1.0 - exp(-5.0 * delta))
	card_roll = 0.006 * sin(card_time * TAU / (CARD_BREATH_S * 1.7)) * card_life

func _pose_book(amount: float) -> void:
	var openness: float = smoothstep(0.08,0.95,amount)
	var spin: float = 0.0
	var phase: float = -1.0
	var direction: int = 1
	if ui.get("folio") != null and is_instance_valid(ui.get("folio")): # (the old 2D book; the View owns turns since 2026-11-20)
		var f: Node = ui.folio
		if f.inspecting:
			openness *= 1.0-smoothstep(0,0.52,f.elapsed)+smoothstep(2.22,2.78,f.elapsed)
			spin = PI*(smoothstep(0.55,1.28,f.elapsed)-smoothstep(1.58,2.23,f.elapsed))
			if f.elapsed >= 2.78: phase=fposmod((f.elapsed-2.78)/(f.duration-2.78)*f.count,1.0)
		else:
			direction=f.direction
			phase=fposmod(f.elapsed/f.duration*f.count,1.0)
	if openness != last_pose:
		anim.seek(openness*anim.current_animation_length,true)
		last_pose=openness
	var tilt := Basis.from_euler(Vector3(-0.14,0.065,-0.012))
	var closed_center: Vector3 = tilt * Basis(Vector3.UP,spin) * CLOSED * Vector3(0,0.267,0)
	$BookMount.position = Vector3(0,-0.025-(1-amount)*1.14,0) - closed_center*(1-openness)
	$BookMount.basis = tilt * Basis(Vector3.UP,spin) * CLOSED.slerp(OPEN,openness)
	$BookMount/Book.scale = Vector3(1.78,1.78,2.18)
	for key in ["LeftPaper","RightPaper"]:
		var page: Control = ui.printed_controls.get(key)
		if page:
			_bind(key,page.get_global_rect())
		faces[key].visible = openness > 0.985 and page != null
	leaf.visible = phase >= 0 and openness > 0.985
	if leaf.visible:
		for i in 2:
			var m: StandardMaterial3D = prints["LeftPaper" if i==0 else "RightPaper"]
			papers[i].uv1_offset=m.uv1_offset
			papers[i].uv1_scale=m.uv1_scale
		HeldRig.draw_sheet(sheet,papers,phase,direction)

func _uv_at(key: String, pixel: Vector2) -> Vector2:
	var face: Node3D = faces[key]
	var inverse: Transform3D = face.global_transform.affine_inverse()
	var ray: Vector3 = inverse.basis*$Camera.project_ray_normal(pixel)
	if ray.z >= -0.00001: return Vector2(-10,-10)
	var start: Vector3 = inverse*$Camera.project_ray_origin(pixel)
	var point: Vector3 = start - ray*(start.z/ray.z)
	var dimensions: Vector2 = face.get_meta("dimensions")
	return Vector2(point.x,-point.y)/dimensions+Vector2(0.5,0.5)

func pointer(event: InputEventMouse) -> bool:
	var key: String = captured
	var uv: Vector2
	if key.is_empty():
		var targets: Array = ["LeftPaper","RightPaper"] if ui.tab=="grimoire" else (["QuestionBack"] if ui.mode=="chant" else ["IDFront","IDBack"])
		for candidate in targets:
			if not regions.has(candidate) or not faces[candidate].is_visible_in_tree(): continue
			uv=_uv_at(candidate,event.position)
			if Rect2(Vector2.ZERO,Vector2.ONE).has_point(uv):
				key=candidate
				break
	else:
		uv=_uv_at(key,event.position)
	var local: Vector2 = event.position
	if not key.is_empty() and regions.has(key):
		var rect: Rect2 = regions[key]
		local=rect.position+uv*rect.size
	elif not ui.on_navigation(event.position):
		if last_hover.is_empty(): return false
		local=Vector2(-100,-100)
	last_hover=key if not key.is_empty() else ("navigation" if local.x>=0 else "")
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		captured=key if event.pressed else ""
	var mapped: InputEventMouse = event.duplicate()
	mapped.position=local
	mapped.global_position=local
	ink.push_input(mapped,true)
	return true
