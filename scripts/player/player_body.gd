extends Node3D
# The player's full body, seen in first person [Sir: rig the player, animate its
# movement; attacks later]. A Quaternius base body (the same 65-bone UAL rig as
# the Blighted Sprites) plays UAL1+UAL2 locomotion clips picked from the
# controller's state. The existing ArmsRig is re-bound onto the body's arm bones,
# so casting poses, ledge plants and the shimmy keep driving the hands. The head
# and neck are shrunk on the visible body (the camera sits inside them).
# Presentation only: never changes movement, hits or timing.
#
# Usage (child of the player CharacterBody3D, origin at the feet):
#   var body := PlayerBody.new(); player.add_child(body); body.setup(player, arms)

const BodyModel = preload("res://scripts/actors/body_model.gd")
const ArmsRig = preload("res://scripts/combat/arms_rig.gd")

const SKIN := Color(0.86, 0.72, 0.62)
const BACK_OFFSET := 0.24     # body sits behind the eye so the camera clears the chest and shoulders
const HIDE := ["Head", "neck_01"]
const BLEND := 0.15
const LAND_S := 0.25          # landing clip held after touching down from a fall
const WALK_CLIP_SPEED := 1.4  # m/s at 1x [design]
const RUN_CLIP_SPEED := 6.5
const CROUCH_CLIP_SPEED := 1.2

var player: CharacterBody3D
var arms: Node3D
var model: Node3D
var anim: AnimationPlayer
var skeleton: Skeleton3D
var clip := ""
var _was_air := false
var _land_left := 0.0

func setup(p: CharacterBody3D, rig: Node3D = null) -> void:
	player = p
	arms = rig
	var built: Dictionary = BodyModel.build(self, false, SKIN, {})
	model = built.model
	anim = built.anim
	model.position = Vector3(0, 0, BACK_OFFSET)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if arms != null:
		if arms.skeleton == null: await arms.ready
		arms.rebind(skeleton, ArmsRig.UAL_BONES, HIDE)
	_play("idle")

# The clip for the controller's current state.
func pick() -> String:
	if player == null: return "idle"
	var st: String = String(player.Move.keys()[player.state]) if "state" in player else "GROUND"
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	match st:
		"MANTLE", "WALLCLIMB": return "climb"
		"SLIDE": return "slide"
		"DASH": return "run"
		"AIR": return "jump_air"
	if _land_left > 0.0: return "land"
	if player.get("crouching"): return "crawl" if speed > 0.3 else "crouch"
	if speed > 5.0: return "run"
	if speed > 0.3: return "walk"
	return "idle"

func _process(delta: float) -> void:
	if player == null or anim == null: return
	var air: bool = player.state == player.Move.AIR if "state" in player else false
	if _was_air and not air: _land_left = LAND_S
	_was_air = air
	_land_left = maxf(0.0, _land_left - delta)
	var want := pick()
	if want != clip: _play(want)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	match clip:
		"walk": anim.speed_scale = clampf(speed / WALK_CLIP_SPEED, 0.5, 2.5)
		"run": anim.speed_scale = clampf(speed / RUN_CLIP_SPEED, 0.6, 2.5)
		"crawl": anim.speed_scale = clampf(speed / CROUCH_CLIP_SPEED, 0.5, 2.0)
		_: anim.speed_scale = 1.0

func _play(name: String) -> void:
	if not anim.has_animation(name): name = "idle"
	clip = name
	anim.play(name, BLEND)
