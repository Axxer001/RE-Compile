extends Node3D
# First-person arms (WRAD ARMS by wriks, CC0) driven procedurally:
#   TwoBoneIK3D puts each wrist on a target; HandPose (a SkeletonModifier3D
#   running after the IK) turns each wrist to its target's basis and curls the
#   fingers. Presentation only.
# Usage (child of the camera, next to the WeaponView):
#   rig.hold(view)          # hands follow view.marker("Grip") / ("Support")
#   rig.hold(null)          # hands free (rest pose)
#   rig.set_weight("l", w)  # 0 = free rest, 1 = on its target (reload, throw…)
#   rig.set_grip("r", "pistol")  # finger curl preset per hand
# Hand targets can also be set directly for mantle/climb: rig.set_target("l", xform).

const ARMS := "res://assets/wriks/arms/arms.glb"
const ARM_SCALE := 0.13             # model units -> metres; viewmodel arms run long (reach ≈ 0.66 m) so a rifle's handguard is in reach
const REST_OFFSET := Vector3(0, -0.26, 0.08) # shoulders below/behind the eye
const ELBOW_DIR := Vector3(0.95, -0.3, 0.3)  # elbow aim from each shoulder (x mirrored for the left)

# Finger curl presets: per finger [proximal, middle, distal] radians.
const GRIPS := {
	"open":   {"thumb": [0.1, 0.1, 0.1], "index": [0.1, 0.1, 0.1], "middle": [0.1, 0.1, 0.1], "ring": [0.1, 0.1, 0.1], "pinky": [0.1, 0.1, 0.1]},
	"relaxed": {"thumb": [0.2, 0.2, 0.2], "index": [0.35, 0.4, 0.3], "middle": [0.45, 0.5, 0.35], "ring": [0.55, 0.55, 0.4], "pinky": [0.6, 0.6, 0.45]},
	"pistol": {"thumb": [0.5, 0.5, 0.4], "index": [0.55, 0.7, 0.5], "middle": [1.45, 1.5, 1.1], "ring": [1.5, 1.55, 1.15], "pinky": [1.55, 1.6, 1.2]},
	"support": {"thumb": [0.6, 0.5, 0.4], "index": [1.2, 1.3, 0.95], "middle": [1.3, 1.4, 1.0], "ring": [1.35, 1.4, 1.05], "pinky": [1.4, 1.45, 1.1]},
	"fist":   {"thumb": [0.7, 0.8, 0.6], "index": [1.5, 1.6, 1.2], "middle": [1.5, 1.6, 1.2], "ring": [1.5, 1.6, 1.2], "pinky": [1.5, 1.6, 1.2]},
}
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]
# Bend axis in each finger bone's local space (tuned against renders).
const CURL_AXIS := Vector3(0, 0, 1) # measured: +Z closes fingertips onto socket.r (0.085 -> 0.059 m)

# Hand placement relative to a gun marker. euler is applied on top of the hand's
# rest orientation (palm down, fingers forward), so (0,0,0) = rest hand; the
# grips roll the palm onto the side of the grip / handguard. origin puts the
# wrist back from the palm (marker space, metres).
const HAND_ON_MARKER := {
	"r": {"origin": Vector3(0.03, -0.015, 0.06), "euler": Vector3(0.25, 0.0, -1.45)},
	"l": {"origin": Vector3(-0.035, -0.02, 0.05), "euler": Vector3(0.0, 0.0, 1.3)},
}

# Bone names per rig. The WRAD arms are the default; rebind() switches to a
# full-body skeleton (the Quaternius/UAL rig) without changing any caller.
const WRAD_BONES := {"upper": "bicep.%s", "mid": "forearm.%s", "end": "wrist.%s", "finger": "finger_%s%d.%s"}
const UAL_BONES := {"upper": "upperarm_%s", "mid": "lowerarm_%s", "end": "hand_%s", "finger": "%s_0%d_%s"}

class HandPose extends SkeletonModifier3D:
	var rig: Node3D
	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or rig == null: return
		# Bones hidden from the first-person camera (head inside the view).
		for hb in rig.hidden_bones:
			var hi := sk.find_bone(hb)
			if hi >= 0: sk.set_bone_pose_scale(hi, Vector3.ONE * 0.001)
		for side in ["r", "l"]:
			var w: float = rig.weight[side]
			var wrist := sk.find_bone(rig.bones.end % side)
			if wrist >= 0 and w > 0.0:
				var want: Basis = (sk.global_transform.affine_inverse() * rig.targets[side].global_transform).basis.orthonormalized()
				var parent := sk.get_bone_parent(wrist)
				var parent_g: Basis = sk.get_bone_global_pose(parent).basis.orthonormalized()
				var local := (parent_g.inverse() * want).get_rotation_quaternion()
				var cur := sk.get_bone_pose_rotation(wrist)
				sk.set_bone_pose_rotation(wrist, cur.slerp(local, w))
			var grip: Dictionary = GRIPS.get(rig.grip[side], GRIPS.relaxed)
			for f in FINGERS:
				for j in 3:
					var b := sk.find_bone(rig.bones.finger % [f, j + 1, side])
					if b < 0: continue
					var rest := sk.get_bone_rest(b).basis.get_rotation_quaternion()
					sk.set_bone_pose_rotation(b, rest * Quaternion(CURL_AXIS, float(grip[f][j])))

var model: Node3D
var skeleton: Skeleton3D
var ik: TwoBoneIK3D
var pose_mod: HandPose
var view: Node3D                  # WeaponView being held (has marker(name)), or null
var targets := {}                 # "r"/"l" -> Node3D (wrist target)
var poles := {}
var rests := {}                   # "r"/"l" -> Transform3D wrist rest, rig-local
var weight := {"r": 1.0, "l": 1.0}
var grip := {"r": "relaxed", "l": "relaxed"}
var manual := {"r": false, "l": false} # target set directly (mantle, climb…)
var bones: Dictionary = WRAD_BONES
var hidden_bones: Array = []
var body_mode := false          # true after rebind() onto a full body
const IK_FADE_RATE := 8.0       # influence per second (~0.12 s fade)

func _ready() -> void:
	model = (load(ARMS) as PackedScene).instantiate()
	model.name = "Arms"
	model.scale = Vector3.ONE * ARM_SCALE
	model.position = REST_OFFSET
	add_child(model)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var gi := m as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for side in ["r", "l"]:
		var t := Node3D.new(); t.name = "Target_" + side; add_child(t); targets[side] = t
		var p := Node3D.new(); p.name = "Pole_" + side; add_child(p); poles[side] = p
		var i := skeleton.find_bone("wrist." + side)
		rests[side] = transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_rest(i) if is_inside_tree() \
			else model.transform * skeleton.get_bone_global_rest(i)
		t.transform = rests[side]
		# Elbows point down and out from the shoulder.
		var sh := model.transform * skeleton.get_bone_global_rest(skeleton.find_bone("bicep." + side)).origin
		var d := ELBOW_DIR * Vector3(1.0 if side == "r" else -1.0, 1.0, 1.0)
		p.position = sh + d.normalized() * 0.5
	ik = TwoBoneIK3D.new()
	ik.name = "ArmIK"
	skeleton.add_child(ik)
	ik.setting_count = 2
	for idx in 2:
		var side: String = ["r", "l"][idx]
		ik.set_root_bone_name(idx, "bicep." + side)
		ik.set_middle_bone_name(idx, "forearm." + side)
		ik.set_end_bone_name(idx, "wrist." + side)
		ik.set_target_node(idx, ik.get_path_to(targets[side]))
		ik.set_pole_node(idx, ik.get_path_to(poles[side]))
	pose_mod = HandPose.new()
	pose_mod.name = "HandPose"
	pose_mod.rig = self
	skeleton.add_child(pose_mod) # after the IK: runs second
	skeleton.skeleton_updated.connect(_cache_wrists)

# Moves the IK and hand posing onto another skeleton (the player's full body,
# player_body.gd) and hides the WRAD arms. Targets, rests, grips and every caller
# (hold, set_target, plant_hand, release_hand) keep working unchanged.
func rebind(sk: Skeleton3D, bone_map: Dictionary, hide: Array = []) -> void:
	if sk == null: return
	if ik: ik.queue_free()
	if pose_mod: pose_mod.queue_free()
	if skeleton and skeleton.skeleton_updated.is_connected(_cache_wrists):
		skeleton.skeleton_updated.disconnect(_cache_wrists)
	if model: model.visible = false
	skeleton = sk
	body_mode = true
	bones = bone_map
	hidden_bones = hide
	ik = TwoBoneIK3D.new()
	ik.name = "ArmIK"
	skeleton.add_child(ik)
	ik.setting_count = 2
	for idx in 2:
		var side: String = ["r", "l"][idx]
		ik.set_root_bone_name(idx, bones.upper % side)
		ik.set_middle_bone_name(idx, bones.mid % side)
		ik.set_end_bone_name(idx, bones.end % side)
		ik.set_target_node(idx, ik.get_path_to(targets[side]))
		ik.set_pole_node(idx, ik.get_path_to(poles[side]))
	pose_mod = HandPose.new()
	pose_mod.name = "HandPose"
	pose_mod.rig = self
	skeleton.add_child(pose_mod)
	skeleton.skeleton_updated.connect(_cache_wrists)

func hold(v: Node3D) -> void:
	view = v
	grip.r = "pistol" if v != null else "relaxed"
	grip.l = "support" if v != null else "relaxed"

func set_weight(side: String, w: float) -> void:
	weight[side] = clampf(w, 0.0, 1.0)

func set_grip(side: String, preset: String) -> void:
	grip[side] = preset if GRIPS.has(preset) else "relaxed"

# Direct target (rig-local transform) for mantle/climb/throw; null returns to auto.
func set_target(side: String, xform: Variant) -> void:
	manual[side] = xform != null
	if xform != null: targets[side].transform = xform

func _process(_delta: float) -> void:
	update_targets()

# Places the wrist targets: on the held gun's markers, blended to rest by weight.
func update_targets() -> void:
	for side in ["r", "l"]:
		if manual[side]: continue
		var goal: Transform3D = rests[side]
		var marker: Node3D = null
		if view != null and view.has_method("marker"):
			marker = view.marker("Grip" if side == "r" else "Support")
		if marker != null:
			var h: Dictionary = HAND_ON_MARKER[side]
			var m := global_transform.affine_inverse() * marker.global_transform
			var on := Transform3D(m.basis.orthonormalized() * Basis.from_euler(h.euler) * rests[side].basis.orthonormalized(), m * (h.origin as Vector3))
			goal = rests[side].interpolate_with(on, weight[side])
		targets[side].transform = goal
	if ik:
		# On a full body, idle hands belong to the animation: the IK fades out
		# when no hand is planted/posed (manual) and nothing is held, and back in
		# when a cast or ledge grab sets a target. The WRAD arms keep it at 1.
		var busy: bool = manual.r or manual.l or view != null
		var want := 1.0 if (busy or not body_mode) else 0.0
		ik.influence = move_toward(ik.influence, want, get_process_delta_time() * IK_FADE_RATE) if is_inside_tree() else want

# Modifier results are applied only during the skeleton update and are not kept
# in the stored pose, so wrist positions are cached from skeleton_updated.
var _wrist_cache := {}
func _cache_wrists() -> void:
	for side in ["r", "l"]:
		_wrist_cache[side] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bones.end % side)).origin

# Wrist position after IK, as last rendered.
func wrist_global(side: String) -> Vector3:
	return _wrist_cache.get(side, Vector3.ZERO)

# Mantle/climb: plant a hand on a world-space contact. point = where the palm
# lands (ledge top or wall), normal = surface normal there (up for a ledge top,
# outward for a wall). The palm faces into the surface, fingers point away from
# the player along it; the wrist sits a palm-length back. Call each frame while
# the hand is planted; release_hand() hands it back to the gun/rest logic.
const PALM_BACK := 0.07   # wrist behind the palm centre (m)
const HAND_SPREAD := 0.18 # left/right hand offset across the contact (m)

func plant_hand(side: String, point: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	var to_rig := global_transform.affine_inverse()
	var fwd := -global_transform.basis.z
	var along := (fwd - n * fwd.dot(n)) # player-forward projected onto the surface
	if along.length() < 0.01: along = n.cross(global_transform.basis.x)
	along = along.normalized()
	var across := along.cross(n).normalized() * (1.0 if side == "r" else -1.0) # forward × up = player right
	var palm := point + across * HAND_SPREAD * 0.5 + n * 0.015
	# Hand basis: fingers along `along`, palm facing -n (into the surface).
	var b := Basis(across, n, -along).orthonormalized()
	var wrist := palm - along * PALM_BACK
	set_grip(side, "open")
	set_weight(side, 1.0)
	set_target(side, to_rig * Transform3D(b * rests[side].basis.orthonormalized(), wrist))

func release_hand(side: String) -> void:
	set_target(side, null)
	if view != null: hold(view)
	else: set_grip(side, "relaxed")
