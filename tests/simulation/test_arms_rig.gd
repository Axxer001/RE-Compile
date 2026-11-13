extends RefCounted
# First-person arms rig (scripts/combat/arms_rig.gd): IK reach onto each gun's
# Grip/Support markers, finger curl, weight blend back to rest. Headless.

const Rig = preload("res://scripts/combat/arms_rig.gd")
const HOLD := Vector3(0.12, -0.13, -0.24) # viewmodel hold point used for tuning

# Grip at the origin, Support offsets as measured from the retired gun
# viewmodels (pistol / two-handed rifle / long pump / one-handed knife), so the
# reach checks keep covering the same hand spreads without the gun assets.
const SUPPORT := {"pistol": Vector3(0, -0.0125, -0.0076), "assault_rifle": Vector3(0, 0.0572, -0.3256),
	"shotgun": Vector3(0, 0.0246, -0.35), "knife": Vector3.ZERO}

class Holder extends Node3D:
	func marker(n: String) -> Node3D: return get_node_or_null(n)

static func holder(id: String) -> Holder:
	var h := Holder.new()
	var g := Marker3D.new(); g.name = "Grip"; h.add_child(g)
	var s := Marker3D.new(); s.name = "Support"; s.position = SUPPORT[id]; h.add_child(s)
	return h

static func settle(tree: SceneTree) -> void:
	for i in 3: await tree.process_frame

static func run(check: Callable, c: Node) -> void:
	var tree := c.get_tree()
	var cam := Camera3D.new()
	c.add_child(cam)
	var rig: Node3D = Rig.new()
	cam.add_child(rig)
	await settle(tree)
	check.call(rig.skeleton != null and rig.skeleton.get_bone_count() == 50, "arms rig loads (50 bones)")

	# Each gun: right wrist on Grip, left within reach of Support.
	var limits := {"pistol": 0.01, "assault_rifle": 0.06, "shotgun": 0.06, "knife": 0.01}
	for id in limits:
		var h := holder(id)
		cam.add_child(h)
		h.position = HOLD
		rig.hold(h)
		if id == "knife": rig.set_weight("l", 0.0)
		await settle(tree)
		var er: float = rig.wrist_global("r").distance_to(rig.targets.r.global_position)
		var el: float = rig.wrist_global("l").distance_to(rig.targets.l.global_position)
		check.call(er < 0.01, "%s: right wrist reaches the grip (%.3f m)" % [id, er])
		check.call(el < limits[id], "%s: left wrist within %.2f m of the support point (%.3f m)" % [id, limits[id], el])
		h.queue_free()
	rig.hold(null)
	rig.set_weight("l", 1.0)

	# Weight 0 returns a hand to its rest pose; 1 puts it back on the target.
	var h2 := holder("pistol")
	cam.add_child(h2)
	h2.position = HOLD
	rig.hold(h2)
	rig.set_weight("r", 0.0)
	await settle(tree)
	var rest_pos: Vector3 = cam.global_transform * (rig.transform * rig.rests.r.origin)
	check.call(rig.targets.r.global_position.distance_to(rest_pos) < 0.001, "weight 0 sends the hand target to rest")
	rig.set_weight("r", 1.0)
	h2.queue_free()

	# Fist curls the fingertips toward the palm socket.
	var sk: Skeleton3D = rig.skeleton
	var d := {}
	var measure := func():
		var sock := sk.get_bone_global_pose(sk.find_bone("socket.r")).origin
		var s := 0.0
		for f in ["index", "middle", "ring", "pinky"]:
			s += sk.get_bone_global_pose(sk.find_bone("finger_%s3.r" % f)).origin.distance_to(sock)
		d["v"] = s
	sk.skeleton_updated.connect(measure)
	rig.set_grip("r", "open")
	await settle(tree)
	var open: float = d.get("v", 0.0)
	rig.set_grip("r", "fist")
	await settle(tree)
	check.call(d.get("v", 99.0) < open * 0.8, "fist curls fingertips toward the palm")
	sk.skeleton_updated.disconnect(measure)

	# Manual target (mantle/climb) overrides the gun markers.
	var ledge := Transform3D(Basis(), Vector3(0.2, -0.05, -0.45))
	rig.set_target("r", ledge)
	await settle(tree)
	check.call(rig.targets.r.transform.origin.distance_to(ledge.origin) < 0.001 and rig.wrist_global("r").distance_to(rig.targets.r.global_position) < 0.01, "manual hand target is reached")
	rig.set_target("r", null)

	# Ledge plant (mantle): both palms land on a ledge top 0.5 m ahead.
	var ledge_pt: Vector3 = cam.global_transform * Vector3(0.0, -0.15, -0.5)
	rig.plant_hand("r", ledge_pt, Vector3.UP)
	rig.plant_hand("l", ledge_pt, Vector3.UP)
	await settle(tree)
	var wr: Vector3 = rig.wrist_global("r")
	var wl: Vector3 = rig.wrist_global("l")
	check.call(wr.distance_to(rig.targets.r.global_position) < 0.02 and wl.distance_to(rig.targets.l.global_position) < 0.02, "both hands reach a planted ledge contact")
	check.call(wr.x > wl.x and absf(wr.y - ledge_pt.y) < 0.05, "planted hands sit side by side on the ledge")
	check.call(rig.grip.r == "open", "planted hand opens")
	rig.release_hand("r"); rig.release_hand("l")
	check.call(not rig.manual.r and not rig.manual.l, "release returns hands to automatic placement")
	cam.queue_free()
