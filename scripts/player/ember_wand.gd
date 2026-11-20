extends Node3D
# The Ember Wand viewmodel [Sir, 2026-11-20; docs/plan-held-grimoire.md]: the
# GAME ASSETS "Ember Wand" model and its movement clips (assets/held_grimoire/
# ember_wand.glb), ported from the pack's WandView.gd. It replaces the
# code-built wand_view.gd. Presentation only: never changes movement, hits or
# timing.
#   move(clip, next)  locomotion clip (Movement Guide.md names); pick() maps the
#                     controller's state to one each frame
#   trigger(clip)     Cast / Attack (the 0.14 s kick), Channel, Damage, Stagger
#   tip_rest_global() where spells leave from (stable: the wand root never moves;
#                     the clips animate its "Motion" child)
#   set_left(bool)    the wand in the left hand (the book in the right, the
#                     default) mirrors it across the view
#
# Usage (child of the player's camera): var w := EmberWand.new(); w.player = p; camera.add_child(w)

const MODEL := preload("res://assets/held_grimoire/ember_wand.glb")
const REST := Vector3(0.22, -0.2, -0.36)     # right hand, camera space (m)
const REST_ROT := Vector3(0.14, 0.2, -0.12)
const TIP := Vector3(0, 0, -0.24)            # wand space
const GESTURES: Array[StringName] = [&"Cast", &"Attack", &"Channel", &"Damage", &"Stagger"]
const GLOW_S := 0.22
const RUN_SPEED := 6.0                       # above this a ground move is a Run
const LAND_S := 0.3
const WALLRUN_SPEED := 1.5                   # sideways on the wall faster than this is a wall run
const SURF_ANGLE := 0.35                     # rad: a slide on a floor this steep is a slope surf
# One-shot movement events [Movement Guide.md]: a controller counter going up
# plays its clip once (the state clip resumes after it).
const EVENTS := [["geo_jumps", &"Jump"], ["lurches", &"AirStrafe"], ["slide_jumps", &"SlideJump"], ["steps_up", &"StepUp"],
	["mantle_hops", &"MantleHop"], ["mantle_boosts", &"MantleBoost"], ["end_boosts", &"MantleBoost"], ["superglides", &"Superglide"],
	["mantle_cancels", &"LedgeDrop"], ["bounces", &"WallBounce"], ["mini_bounces", &"WallBounce"], ["wallhops", &"WallBounce"],
	["wall_pushes", &"WallPush"], ["lunges", &"Lunge"], ["punch_boosts", &"Lunge"]]

var player: CharacterBody3D
var left := false             # mirrored into the left hand
var asset: Node3D
var motion: AnimationPlayer   # locomotion
var action: AnimationPlayer   # gestures, layered on the Gesture node
var gesture_node: Node3D
var crystal: StandardMaterial3D
var tip_light: OmniLight3D
var lamp: SpotLight3D            # the wand light [graphics direction 2026-11-20]: a warm cone ahead
var glow: OmniLight3D            # and a soft glow round the tip
const LAMP_RANGE := 15.0
const LAMP_ANGLE := 26.0
const LAMP_ENERGY := 2.4
const GLOW_RANGE := 4.0
const GLOW_ENERGY := 0.7
const WARM := Color(1.0, 0.72, 0.42)
var glow_left := 0.0
var channeling := false
var fallback: StringName = &"Idle"
var clip: StringName = &"Idle"  # the locomotion clip playing (tests read it)
var kicks := 0                  # Cast/Attack gestures started (tests)
var _was_air := false
var _land_left := 0.0
var _last_x := 0.0
var _counts := {}               # controller counters last seen (EVENTS)
var _air_jumps := -1
var _prev_state := -1
var _event_left := 0.0          # a one-shot clip holds this long
var stowed := false             # dead: the wand is put away (Stow), Equip on the way back
var played := {}                # clip -> times started (tests: the coverage table)

func _ready() -> void:
	name = "Wand"
	asset = MODEL.instantiate()
	asset.name = "Asset"
	add_child(asset)
	set_left(left)
	motion = asset.find_child("AnimationPlayer", true, false) as AnimationPlayer
	gesture_node = asset.find_child("Gesture", true, false) as Node3D
	action = AnimationPlayer.new()
	motion.get_parent().add_child(action)
	action.root_node = motion.root_node
	var actions := AnimationLibrary.new()
	for key in GESTURES: actions.add_animation(key, motion.get_animation(key))
	action.add_animation_library(&"", actions)
	var gem := asset.find_child("EmberCrystal", true, false) as MeshInstance3D
	crystal = gem.get_active_material(0).duplicate() as StandardMaterial3D
	gem.set_surface_override_material(0, crystal)
	for mesh in asset.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # the player casts no shadow
	tip_light = OmniLight3D.new()
	tip_light.name = "TipLight"
	tip_light.light_color = Color(1, 0.55, 0.18)
	tip_light.omni_range = 0.8
	tip_light.shadow_enabled = false
	tip_light.visible = false
	asset.find_child("Tip", true, false).add_child(tip_light)
	lamp = SpotLight3D.new()
	lamp.name = "WandLamp"
	lamp.light_color = WARM
	lamp.light_energy = LAMP_ENERGY
	lamp.spot_range = LAMP_RANGE
	lamp.spot_angle = LAMP_ANGLE
	lamp.spot_attenuation = 1.2
	lamp.shadow_enabled = true # the one shadowed practical the player carries
	lamp.transform = Transform3D(Basis.from_euler(REST_ROT).inverse(), TIP) # from the tip, along the view
	add_child(lamp)
	glow = OmniLight3D.new()
	glow.name = "WandGlow"
	glow.light_color = WARM
	glow.light_energy = GLOW_ENERGY
	glow.omni_range = GLOW_RANGE
	glow.shadow_enabled = false
	asset.find_child("Tip", true, false).add_child(glow)
	motion.animation_finished.connect(_motion_finished)
	action.animation_finished.connect(_gesture_finished)
	move(&"Idle")

# Mirrors the wand into the left hand (scale x -1: the wand has no text to flip).
func set_left(on: bool) -> void:
	left = on
	position = Vector3(-REST.x if on else REST.x, REST.y, REST.z)
	rotation = Vector3(REST_ROT.x, -REST_ROT.y if on else REST_ROT.y, -REST_ROT.z if on else REST_ROT.z)
	scale = Vector3(-1, 1, 1) if on else Vector3.ONE

func move(next: StringName, next_loop: StringName = &"Idle", blend := 0.085) -> void:
	if motion == null or not motion.has_animation(next) or next in GESTURES: return
	fallback = next_loop
	clip = next
	played[next] = int(played.get(next, 0)) + 1
	if motion.current_animation == next and motion.get_animation(next).loop_mode != Animation.LOOP_NONE: return
	if motion.current_animation == next: motion.stop(true)
	motion.play(next, blend)

func trigger(g: StringName) -> void:
	if action == null or not g in GESTURES: return
	channeling = g == &"Channel"
	played[g] = int(played.get(g, 0)) + 1
	if action.current_animation == g: action.stop(true)
	action.play(g, 0.035 if g in [&"Damage", &"Stagger"] else 0.0)
	if g in [&"Cast", &"Attack"]:
		glow_left = GLOW_S
		kicks += 1

func end_channel() -> void:
	channeling = false
	if action != null and action.current_animation == &"Channel":
		action.stop()
		gesture_node.transform = Transform3D.IDENTITY

func glowing() -> bool:
	return channeling or glow_left > 0.0

# The tip at the wand's rest pose, world space: the root sits still at REST
# (the clips move its Motion child), so this never jitters with the animation.
func tip_rest_global() -> Vector3:
	var cam := get_parent() as Node3D
	if cam == null: return global_position
	var rest := Transform3D(Basis.from_euler(rotation).scaled(scale), position)
	return (cam.global_transform * rest) * TIP

# The locomotion clip for the controller's state (Movement Guide.md).
func pick() -> StringName:
	if player == null: return &"Idle"
	var p := player
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	match p.state:
		p.Move.MANTLE:
			var phase: String = String(p.mantle.get("phase", "pull")) if p.mantle is Dictionary else "pull"
			if phase == "grab": return &"LedgeCatch"
			if phase == "hang":
				var dx: float = p.global_position.dot(p.global_transform.basis.x) - _last_x
				if absf(dx) > 0.002: return &"ShimmyRight" if dx > 0.0 else &"ShimmyLeft"
				return &"LedgeHang"
			return &"MantlePull"
		p.Move.WALLCLIMB:
			var side: float = Vector3(p.velocity.x, 0, p.velocity.z).dot(p.global_transform.basis.x)
			if absf(side) > WALLRUN_SPEED: return &"WallRunRight" if side > 0.0 else &"WallRunLeft"
			return &"WallClimb"
		p.Move.SLIDE:
			if p.is_on_floor() and p.get_floor_normal().angle_to(Vector3.UP) > SURF_ANGLE: return &"SlopeSurf"
			return &"Slide"
		p.Move.DASH: return &"Dash"
		p.Move.AIR: return &"Jump" if p.velocity.y > 1.0 else &"Fall"
	if _land_left > 0.0: return &"Land"
	if p.crouching: return &"CrouchWalk" if speed > 0.3 else &"CrouchHold"
	if speed <= 0.3: return &"Idle"
	if speed > RUN_SPEED: return &"Run"
	var mv: Vector2 = p.last_move
	if mv.y < -0.1: return &"Backpedal"
	if absf(mv.x) > 0.1 and absf(mv.y) < 0.1: return &"StrafeRight" if mv.x > 0.0 else &"StrafeLeft"
	return &"Walk"

func _process(delta: float) -> void:
	step(delta)

# Put away (the player died) and back out (a new run): Stow, then Equip.
func stow(on: bool) -> void:
	if stowed == on: return
	stowed = on
	move(&"Stow" if on else &"Equip", &"Idle")

# One presentation step (tests call it directly).
func step(delta: float) -> void:
	if player != null and not stowed:
		var air: bool = player.state == player.Move.AIR
		if _was_air and not air and player.state == player.Move.GROUND: _land_left = LAND_S
		_was_air = air
		_land_left = maxf(0.0, _land_left - delta)
		_event_left = maxf(0.0, _event_left - delta)
		var ev := _event()
		if ev != &"":
			move(ev, pick())
			_event_left = motion.get_animation(ev).length if motion and motion.has_animation(ev) else 0.25
		elif _event_left <= 0.0:
			var want := pick()
			if want != clip: move(want, &"Idle" if want in [&"Land", &"Jump"] else want)
		_prev_state = player.state
		_last_x = player.global_position.dot(player.global_transform.basis.x)
	glow_left = maxf(0.0, glow_left - delta)
	var strength: float = 1.0 if channeling else smoothstep(0.0, 0.13, glow_left)
	if crystal: crystal.emission_energy_multiplier = lerpf(0.8, 5.0, strength)
	if tip_light:
		tip_light.visible = strength > 0.01
		tip_light.light_energy = 1.5 * strength

# This frame's one-shot movement event, or &"" (a counter rose, a double jump,
# a slide's entry or exit).
func _event() -> StringName:
	var p := player
	var out: StringName = &""
	for e in EVENTS:
		var n: int = int(p.get(e[0])) if p.get(e[0]) != null else 0
		if _counts.has(e[0]) and n > int(_counts[e[0]]) and out == &"": out = e[1]
		_counts[e[0]] = n
	var st: int = int(p.stuns) # a fall stun: the longer Stagger recoil [Movement Guide.md]
	if _counts.has("stuns") and st > int(_counts.stuns): trigger(&"Stagger")
	_counts["stuns"] = st
	var aj: int = int(p.air_jumps)
	if _air_jumps >= 0 and aj < _air_jumps and p.state == p.Move.AIR and out == &"": out = &"DoubleJump"
	_air_jumps = aj
	if _prev_state >= 0 and out == &"":
		if p.state == p.Move.SLIDE and _prev_state != p.Move.SLIDE: out = &"SlideEnter"
		elif _prev_state == p.Move.SLIDE and p.state == p.Move.GROUND and not p.crouching: out = &"SlideExit" # a dead slide stays crouched (CrouchWalk/Hold)
	return out

func _motion_finished(done: StringName) -> void:
	if done != &"Stow": move(fallback)

func _gesture_finished(_g: StringName) -> void:
	gesture_node.transform = Transform3D.IDENTITY
