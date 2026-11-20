extends RefCounted
const Service = preload("res://scripts/combat/projectile_service.gd")

static func run(check: Callable, c: Node3D) -> void:
	check.call(load("res://tests/performance/baseline.gd").simulate_in_sync(), "benchmark simulate copy matches current gameplay")
	check.call(c.projectiles.has_method("prewarm_visuals"), "projectile pool supports loading-time prewarm")
	check.call(c.has_method("_spawn_candidate"), "final spawn positions are validated")
	if not c.projectiles.has_method("prewarm_visuals") or not c.has_method("_spawn_candidate"): return
	var root := Node3D.new()
	c.add_child(root)
	var ps: RefCounted = Service.new()
	ps.prewarm_visuals()
	check.call(ps.visuals_created == 0, "prewarm without a visual root does nothing")
	ps.root = root
	ps.prewarm_visuals()
	var created: int = ps.visuals_created
	check.call(created == 26 and ps.pooled_visuals() == 26 and ps.shots.is_empty() and ps.rings.is_empty(), "prewarm creates visuals only, no live shots or rings")
	check.call(root.get_children().all(func(n): return not n.visible), "all prewarmed visuals are hidden")
	ps.prewarm_visuals()
	check.call(ps.visuals_created == created, "prewarm is idempotent")
	for i in 24: ps.launch("basic", Vector3.ZERO, Vector3.FORWARD, {})
	for i in 2: ps.launch("special", Vector3.ZERO, Vector3.FORWARD, {})
	check.call(ps.visuals_created == created and ps.shots.size() == 26, "warmed basic and special shots launch without allocating visuals")
	ps.reset()
	check.call(ps.pooled_visuals() == 26 and root.get_children().all(func(n): return not n.visible), "reset returns every warmed visual without a visible orphan")
	root.queue_free()
	c.session.restart()
	c.park_enemies()
	var foe: CharacterBody3D = c.enemies.values()[0]
	var tree: SceneTree = c.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	var at: Vector3 = c.zones[0].at
	# The player must be away from the candidate; the existing arena zones are reachable.
	c.player.global_position = c.spawn.at
	var good: Dictionary = c._spawn_candidate(at, foe)
	check.call(not good.is_empty(), "clear, supported zone is a valid final spawn")
	check.call(c._spawn_candidate(c.player.global_position, foe).is_empty(), "final candidate rejects player proximity")
	check.call(c._spawn_candidate(Vector3(-1000, 0, -1000), foe).is_empty(), "final candidate rejects outside navigation bounds")
	check.call(c._spawn_candidate(at + Vector3(0, 4, 0), foe).is_empty(), "unsupported floating candidate is rejected")
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	shape.shape = box
	blocker.add_child(shape)
	c.add_child(blocker)
	blocker.global_position = at + Vector3(0, 1, 0)
	await tree.physics_frame
	await tree.physics_frame
	check.call(c._spawn_candidate(at, foe).is_empty(), "final candidate rejects a new physical obstacle even before nav rebuild")
	blocker.queue_free()
	await tree.physics_frame
	await tree.physics_frame
	var other: CharacterBody3D = c.enemies.values()[1]
	other.reset_to(at, 0)
	check.call(c._spawn_candidate(at, foe).is_empty(), "candidate rejects an occupied position in the same tick")
	c._to_reserve(other)
	check.call(not c._spawn_candidate(at, foe).is_empty(), "reserve actors do not consume spawn space")
	# Force every jittered attempt outside the map. The spawner must defer, not materialize.
	var saved: Array = c.zones
	c.zones = [{"at": Vector3(-1000, 0, -1000), "yaw": 0.0}]
	foe.inert = false
	c._to_reserve(foe)
	c.spawning = true
	c.next_spawn = 0.0
	var before: int = c.alive_count()
	c._respawn(100.0)
	check.call(c.alive_count() == before and c.next_spawn > 100.0, "blocked sources defer with a bounded retry interval and no actor loss")
	c.zones = saved
	c.session.restart()
	await tree.physics_frame
