extends RefCounted
# Viewmodel feel (spring bob/sway/roll/lag). Presentation only; driven directly via step_feel().

const WeaponView = preload("res://scripts/combat/weapon_view.gd")
const Spring = preload("res://scripts/combat/spring.gd")

static func run(check: Callable, _c: Node3D) -> void:
	# Spring settles on its target, overshooting first when under-damped.
	var s := Spring.new(80.0, 10.0)
	s.v = Vector3(1, 0, 0)
	var peak := 0.0
	for i in 300:
		peak = maxf(peak, s.step(Vector3.ZERO, 1.0 / 60.0).x)
	check.call(peak > 0.05 and s.x.length() < 0.001, "spring kicked by an impulse settles back to target")
	var big := Spring.new(260.0, 28.0)
	big.step(Vector3.ONE, 0.5) # one long frame stays stable
	check.call(big.x.length() < 3.0, "spring stays stable on a long frame")

	var v := WeaponView.new()
	v.show_weapon(null, "")
	v._settle_reset()
	var dt := 1.0 / 60.0
	var still: Transform3D
	for i in 120: still = v.step_feel(dt, Vector3.ZERO, Vector3.RIGHT, true, 0.0, 0.0, 1.6)
	check.call(still.origin.distance_to(v.rest.origin) < 0.001, "standing still rests exactly at the rest pose")

	# Bob: sprinting moves the model, more than walking.
	var walk_dev := 0.0
	var sprint_dev := 0.0
	for i in 180: walk_dev = maxf(walk_dev, v.step_feel(dt, Vector3(0, 0, -3.5), Vector3.RIGHT, true, 0.0, 0.0, 1.6).origin.distance_to(v.rest.origin))
	for i in 180: sprint_dev = maxf(sprint_dev, v.step_feel(dt, Vector3(0, 0, -6.0), Vector3.RIGHT, true, 0.0, 0.0, 1.6).origin.distance_to(v.rest.origin))
	check.call(walk_dev > 0.002 and sprint_dev > walk_dev, "bob scales with speed (walk %.4f, sprint %.4f)" % [walk_dev, sprint_dev])
	check.call(sprint_dev < 0.05, "bob stays small")

	# Strafe roll is clamped and leans against the strafe.
	var roll := 0.0
	for i in 120: roll = v.step_feel(dt, Vector3(50, 0, 0), Vector3.RIGHT, false, 0.0, 0.0, 1.6).basis.get_euler().z - v.rest.basis.get_euler().z
	check.call(roll < 0.0 and roll > -0.09, "strafe roll leans and is clamped (%.3f)" % roll)

	# Look sway follows a fast turn but stays capped.
	var yaw := 0.0
	var sway := 0.0
	for i in 30:
		yaw += 0.2
		sway = maxf(sway, absf(v.step_feel(dt, Vector3.ZERO, Vector3.RIGHT, true, yaw, 0.0, 1.6).basis.get_euler().y - v.rest.basis.get_euler().y))
	check.call(sway > 0.01 and sway < 0.12, "look sway reacts and is capped (%.3f)" % sway)

	# Action pose: the model springs to the target and back without snapping.
	v.target = Transform3D(Basis.from_euler(Vector3(0.6, -1.1, -0.4)), v.rest.origin)
	var first := v.step_feel(dt, Vector3.ZERO, Vector3.RIGHT, true, yaw, 0.0, 1.6)
	check.call(first.basis.get_euler().distance_to(v.rest.basis.get_euler()) < 0.5, "pose change is not an instant snap")
	for i in 60: first = v.step_feel(dt, Vector3.ZERO, Vector3.RIGHT, true, yaw, 0.0, 1.6)
	check.call(first.basis.get_euler().distance_to(v.target.basis.get_euler()) < 0.02, "model reaches the action pose")

	# Disabled feel: only the settle spring remains.
	v.feel_enabled = false
	v.target = v.rest
	var off: Transform3D
	for i in 180: off = v.step_feel(dt, Vector3(6, 0, -6), Vector3.RIGHT, true, yaw, 0.0, 1.6)
	check.call(off.origin.distance_to(v.rest.origin) < 0.001, "feel_enabled=false removes bob, roll and lag")
	v.free()
