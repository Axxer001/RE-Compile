extends RefCounted
# The player's full first-person body (Sir: rig the player, animate its
# movement): it exists under the player, the arms rig is re-bound onto its
# skeleton, its clip follows the controller's state, and the arm IK hands idle
# arms to the animation but takes them back for a planted hand.

const DT := 1.0 / 60.0

static func clip_for(body: Node3D, p: CharacterBody3D, state: int, vel: Vector3, crouch := false) -> String:
	p.state = state
	p.velocity = vel
	p.crouching = crouch
	body._process(DT)
	return body.clip

# Plays out the landing clip so the next pick is not "land".
static func _settle(body: Node3D, p: CharacterBody3D) -> String:
	p.state = p.Move.GROUND
	p.velocity = Vector3.ZERO
	for i in 20: body._process(DT)
	return "_"

# Waits real frames (the IK fade runs on process delta) until done() or 1.5 s.
static func until(tree: SceneTree, done: Callable) -> bool:
	var t0 := Time.get_ticks_msec()
	while not done.call() and Time.get_ticks_msec() - t0 < 1500:
		await tree.process_frame
	return done.call()

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var p: CharacterBody3D = c.player
	var body: Node3D = p.get_node_or_null("Body")
	var arms: Node3D = c.pcombat.arms
	check.call(body != null and body.skeleton != null and arms.skeleton == body.skeleton and arms.body_mode and not arms.model.visible, "the player has a full body; the arms rig drives its skeleton (the WRAD arms are hidden)")

	# The clip follows the controller's state.
	var M = p.Move
	var got := {
		"idle": clip_for(body, p, M.GROUND, Vector3.ZERO),
		"walk": clip_for(body, p, M.GROUND, Vector3(2, 0, 0)),
		"run": clip_for(body, p, M.GROUND, Vector3(7, 0, 0)),
		"jump_air": clip_for(body, p, M.AIR, Vector3(3, -2, 0)),
		"land": clip_for(body, p, M.GROUND, Vector3.ZERO),
		"slide": clip_for(body, p, M.SLIDE, Vector3(9, 0, 0)),
		"climb": clip_for(body, p, M.MANTLE, Vector3(0, 3, 0)),
		"_": _settle(body, p),
		"crouch": clip_for(body, p, M.GROUND, Vector3.ZERO, true),
	}
	var wrong := []
	for want in got:
		if got[want] != want: wrong.append("%s->%s" % [want, got[want]])
	check.call(wrong.is_empty() and body.anim.current_animation != "", "the body's clip follows the state: idle, walk, run, air, land, slide, climb, crouch %s" % str(wrong))
	clip_for(body, p, M.GROUND, Vector3.ZERO)
	for i in 20: body._process(DT) # past the landing clip

	# IK: off for idle arms (the animation plays), on for a planted hand.
	arms.release_hand("r")
	arms.release_hand("l")
	var idle_off: bool = await until(tree, func() -> bool: return arms.ik.influence < 0.01)
	arms.plant_hand("r", p.global_position + Vector3(0, 1.2, -0.6), Vector3.UP)
	var planted_on: bool = await until(tree, func() -> bool: return arms.ik.influence > 0.99)
	arms.release_hand("r")
	check.call(idle_off and planted_on, "the arm IK is off for idle arms and on while a hand is planted (now %.2f)" % arms.ik.influence)
	s.restart()
	await tree.physics_frame
