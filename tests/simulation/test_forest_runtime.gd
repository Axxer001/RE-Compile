extends SceneTree
var failures := []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ", label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = true
	c.fixed_map_seed = 60
	root.add_child(c)
	await physics_frame
	await physics_frame
	check(c.enemies.size() < 100 and c.alive_count() > 0 and c.alive_count() <= 64, "reduced pool and at most 64 residents")
	var blocked := []
	for e in c.enemies.values():
		if not e.reserve and c.nav.blocked(c.nav.cell_of(e.position)): blocked.append(e.enemy_id)
	check(blocked.is_empty(), "initial spawns clear of navigation obstacles: " + str(blocked))
	var alive: Array = c.enemies.values().filter(func(e): return not e.reserve)
	var overlaps := 0
	for i in alive.size():
		for j in range(i+1,alive.size()):
			if alive[i].position.distance_to(alive[j].position)<0.65: overlaps += 1
	check(overlaps == 0,"initial residents do not overlap")
	var unreachable := []
	for z in c.zones:
		if not c.nav.find_path(c.spawn.at,z.at).ok: unreachable.append(z.id)
	check(unreachable.is_empty(), "24 connected spawn zones: " + str(unreachable))
	var t0 := Time.get_ticks_usec()
	for i in 120:
		c.actors_step(1.0/60.0,i/60.0)
		await physics_frame
	var asleep := 0
	var far
	for e in c.enemies.values():
		if e.dormant and not e.reserve: asleep += 1; far = e
	check(asleep > 0 and asleep < alive.size(), "distant idle residents sleep")
	if far:
		c.player.position = far.position + Vector3(0,0,10)
		c.actors_step(1.0/60.0,3.0)
		check(not far.dormant and far.anim.active, "approaching wakes resident animation and AI")
	var surface = c.map.terrain
	var highest := Vector2.ZERO
	for z in range(10,240,10):
		for x in range(10,240,10):
			if surface.height_at(Vector2(x,z)) > surface.height_at(highest): highest = Vector2(x,z)
	var h: float = surface.height_at(highest)
	var hit: Dictionary = c.world_ray(Vector3(highest.x,h+0.1,highest.y),Vector3(highest.x,h-1,highest.y))
	print("HILL ", highest, " height=",h," hit=",hit)
	check(h > 4 and not hit.is_empty() and absf(hit.position.y-h)<0.01, "hill mesh and physics agree")
	c.park_enemies()
	c.player.position = Vector3(highest.x,h+0.2,highest.y)
	c.player.velocity = Vector3.ZERO
	for i in 60: c.session.step(1.0/60.0)
	check(c.player.is_on_floor() and absf(c.player.position.y-h)<0.15, "player settles on elevated terrain")
	var gf = c.find_child("GrassField",true,false)
	if gf:
		for p in [Vector3(50,0,50),Vector3(125,0,125),Vector3(225,0,225)]:
			gf.focus_fn = func(): return p
			gf.update(999)
		check(gf.chunks.size()<200, "grass residency remains bounded after crossing map")
	print("RUNTIME build_ms=",c.map_ms," sleeping=",asleep," ticks_elapsed_ms=",(Time.get_ticks_usec()-t0)/1000.0)
	check(c.FOREST_SPAWN_EVERY_S == 8.0, "forest replenishment interval is eight seconds")
	for sd in 20:
		check(c.new_map(sd), "build navigation seed %d" % sd)
		c._rebuild_navs()
		var destinations: Array = c.page_spots.values()
		for zone in c.zones: destinations.append(zone.at)
		var connected := true
		for destination in destinations:
			connected = connected and c.nav.find_path(c.spawn.at,destination).ok
		check(connected, "all pages and zones reachable without paths seed %d" % sd)
	print("RESULT ",JSON.stringify({"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures}))
	c.free()
	quit(0 if failures.is_empty() else 1)
