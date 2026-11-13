extends SceneTree
# Navigation rebuild: the optimised NavigationGrid.rebuild against the original
# (kept here as Reference), cell for cell and path for path, plus paired timing.
#   godot --headless --path . -s res://tests/performance/navigation_compare.gd
# Coverage: forest seeds 60, 7, 4242, 123, 999 (standing and climbing grids);
# synthetic edge cases (overlapping boxes, boxes past the map edges, gaps of
# exactly the agent radius on both sides, the height-filter boundaries, a low
# body_high grid); a rebuild with changed obstacles after a previous one; an
# empty rebuild; and find_path between the camp, every page and every zone.
const Nav = preload("res://scripts/world/navigation_grid.gd")
const Forest = preload("res://scripts/world/dark_forest.gd")
const SEEDS := [60, 7, 4242, 123, 999]
class Reference extends "res://scripts/world/navigation_grid.gd":
	func rebuild(solids: Array) -> void:
		astar.fill_solid_region(astar.region, false)
		for box in solids:
			var b: AABB = box
			if b.end.y <= BODY_LOW or b.position.y >= body_high: continue
			var lo := cell_of(Vector3(b.position.x - AGENT_RADIUS, 0, b.position.z - AGENT_RADIUS))
			var hi := cell_of(Vector3(b.end.x + AGENT_RADIUS, 0, b.end.z + AGENT_RADIUS))
			for x in range(maxi(lo.x, 0), mini(hi.x, size.x - 1) + 1):
				for y in range(maxi(lo.y, 0), mini(hi.y, size.y - 1) + 1):
					var c := Vector2i(x,y)
					if astar.is_point_solid(c): continue
					var centre := centre_of(c)
					if _footprint_gap(Vector2(centre.x, centre.z), b) < AGENT_RADIUS: astar.set_point_solid(c,true)
		revision += 1

var mismatches := 0
var notes := []

func _initialize() -> void:
	run.call_deferred()

func cells_differ(a, b) -> int:
	var n := 0
	for x in a.size.x:
		for y in a.size.y:
			if a.blocked(Vector2i(x, y)) != b.blocked(Vector2i(x, y)): n += 1
	return n

func compare(label: String, solids: Array, high := Nav.BODY_HIGH) -> void:
	var old := Reference.new()
	var updated := Nav.new()
	old.setup(Vector2.ZERO, Vector2(150, 150))
	updated.setup(Vector2.ZERO, Vector2(150, 150))
	old.body_high = high
	updated.body_high = high
	old.rebuild(solids)
	updated.rebuild(solids)
	var d := cells_differ(old, updated)
	mismatches += d
	notes.append("%s: %d cell mismatches" % [label, d])

func run() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.external_driver = true
	world.fixed_map_seed = 60
	root.add_child(world)
	await physics_frame
	var results := {}
	var climb_max: float = world.BlightedSprite.CLIMB_MAX
	# ---- paired timing on the dense seed (one warm-up, three timed rebuilds) ----
	var old := Reference.new()
	var updated := Nav.new()
	old.setup(Vector2.ZERO, Vector2(150, 150))
	updated.setup(Vector2.ZERO, Vector2(150, 150))
	for kind in ["standing", "climbing"]:
		var solids: Array = world.level_solids()
		if kind == "climbing": solids = solids.filter(func(b: AABB): return b.end.y > climb_max + 0.01)
		var before := []
		var after := []
		for i in 4:
			var start := Time.get_ticks_usec()
			old.rebuild(solids)
			var middle := Time.get_ticks_usec()
			updated.rebuild(solids)
			var end := Time.get_ticks_usec()
			if i > 0:
				before.append((middle - start) / 1000.0)
				after.append((end - middle) / 1000.0)
		var d := cells_differ(old, updated)
		mismatches += d
		notes.append("seed 60 %s: %d cell mismatches" % [kind, d])
		results[kind] = {"old_ms": before, "new_ms": after}
	# ---- more forest seeds, both grids ----
	for sd in SEEDS:
		if sd == 60: continue
		world.new_map(sd)
		await physics_frame
		var all: Array = world.level_solids()
		compare("seed %d standing" % sd, all)
		compare("seed %d climbing" % sd, all.filter(func(b: AABB): return b.end.y > climb_max + 0.01))
	# ---- synthetic edge cases ----
	var r := Nav.AGENT_RADIUS
	var cs := Nav.CELL
	# A box whose edge sits exactly AGENT_RADIUS from a row of cell centres (the strict < boundary),
	# and one just inside it.
	var cx := 40.0 * cs + cs * 0.5 # a cell centre x
	var edge := [AABB(Vector3(cx + r, 0, 20), Vector3(1, 1, 1)), AABB(Vector3(cx + r - 0.0001, 0, 30), Vector3(1, 1, 1))]
	compare("exact agent-radius boundary", edge)
	compare("overlapping boxes", [AABB(Vector3(50, 0, 50), Vector3(3, 2, 3)), AABB(Vector3(51, 0, 51), Vector3(3, 2, 3)), AABB(Vector3(52.2, 0, 50.4), Vector3(0.3, 3, 0.3))])
	compare("boxes past the map edges", [AABB(Vector3(-2, 0, -2), Vector3(3, 2, 3)), AABB(Vector3(149, 0, 60), Vector3(4, 2, 2)), AABB(Vector3(70, 0, 148.9), Vector3(2, 2, 5)), AABB(Vector3(-10, 0, -10), Vector3(1, 1, 1))])
	compare("height filter boundaries", [AABB(Vector3(10, 0, 10), Vector3(1, Nav.BODY_LOW, 1)), AABB(Vector3(12, 0, 10), Vector3(1, Nav.BODY_LOW + 0.0001, 1)),
		AABB(Vector3(14, Nav.BODY_HIGH, 10), Vector3(1, 1, 1)), AABB(Vector3(16, Nav.BODY_HIGH - 0.0001, 10), Vector3(1, 1, 1))])
	compare("low body_high grid (crouch height)", [AABB(Vector3(20, 1.3, 20), Vector3(2, 1, 2)), AABB(Vector3(24, 1.2999, 20), Vector3(2, 1, 2)), AABB(Vector3(28, 0, 20), Vector3(1, 1, 1))], 1.3)
	compare("thin and zero-size boxes", [AABB(Vector3(60, 0, 60), Vector3(0, 2, 0)), AABB(Vector3(62, 0, 60), Vector3(0.01, 2, 5)), AABB(Vector3(64.125, 0, 60.125), Vector3(0, 1, 0))])
	# ---- changed obstacles after a previous rebuild: must equal a fresh rebuild ----
	world.new_map(7)
	await physics_frame
	var a1: Array = world.level_solids()
	world.new_map(4242)
	await physics_frame
	var a2: Array = world.level_solids()
	var reused := Nav.new()
	reused.setup(Vector2.ZERO, Vector2(150, 150))
	reused.rebuild(a1)
	reused.rebuild(a2)
	var fresh := Reference.new()
	fresh.setup(Vector2.ZERO, Vector2(150, 150))
	fresh.rebuild(a2)
	var dr := cells_differ(reused, fresh)
	mismatches += dr
	notes.append("rebuild after a previous map vs fresh reference: %d cell mismatches" % dr)
	# ---- paths: camp to every page and zone, on both implementations ----
	var path_bad := 0
	var path_n := 0
	var pn := Nav.new()
	var po := Reference.new()
	pn.setup(Vector2.ZERO, Vector2(150, 150))
	po.setup(Vector2.ZERO, Vector2(150, 150))
	pn.rebuild(a2)
	po.rebuild(a2)
	var goals: Array = world.page_spots.values()
	for z in world.zones: goals.append(z.at)
	for g in goals:
		var p1: Dictionary = pn.find_path(world.spawn.at, g)
		var p2: Dictionary = po.find_path(world.spawn.at, g)
		path_n += 1
		if p1.ok != p2.ok or str(p1.path) != str(p2.path) or p1.path.is_empty() != (not p1.ok): path_bad += 1
	mismatches += path_bad
	notes.append("paths camp -> %d pages/zones: %d differ, %d reachable (diagonal mode %d on both)" % [path_n, path_bad, goals.filter(func(g): return pn.find_path(world.spawn.at, g).ok).size(), pn.astar.diagonal_mode])
	# ---- empty rebuild clears everything ----
	updated.rebuild([])
	var left := 0
	for x in updated.size.x:
		for y in updated.size.y:
			if updated.blocked(Vector2i(x, y)): left += 1
	mismatches += left
	notes.append("empty rebuild: %d cells left blocked" % left)
	for n in notes: print("  ", n)
	print("RESULT ", JSON.stringify({"status": "PASS" if mismatches == 0 else "FAIL", "mismatches": mismatches, "cases": notes.size(), "metrics": results}))
	quit(0 if mismatches == 0 else 1)
