extends SceneTree
const Forest = preload("res://scripts/world/dark_forest.gd")
var failures := []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	check(Forest.SIZE == Vector2(250,250) and Forest.Terrain.SIZE == 250, "250 metre bounds agree")
	check(Forest.PATHS.is_empty() and not Forest.near_path(Vector2(75,100),8), "no path network")
	var fewest := 100000
	var most := 0
	for sd in 100:
		var m := Forest.generate(sd)
		check(not m.is_empty(), "valid seed %d" % sd)
		if m.is_empty(): continue
		fewest = mini(fewest,m.trees.size())
		most = maxi(most,m.trees.size())
		var surface = Forest.Terrain.new(sd,Forest.CLEARINGS,Forest.PATHS)
		var valid: bool = m.zones.size() == 24
		var tree_counts := PackedInt32Array()
		var rock_counts := PackedInt32Array()
		tree_counts.resize(25)
		rock_counts.resize(25)
		for group in [m.trees,m.rocks,m.ledges]:
			for p in group:
				valid = valid and p[0] >= 0 and p[0] < 250 and p[1] >= 0 and p[1] < 250
		for t in m.trees: tree_counts[int(t[1]/50)*5+int(t[0]/50)] += 1
		for r in m.rocks: rock_counts[int(r[1]/50)*5+int(r[0]/50)] += 1
		check(valid and Array(tree_counts).min() > 0 and Array(rock_counts).min() > 0, "bounds and vegetation coverage seed %d" % sd)
		for p in m.pages.values(): valid = valid and is_equal_approx(p.y,surface.height_at(Vector2(p.x,p.z)))
		for zone in m.zones: valid = valid and is_equal_approx(zone.at.y,surface.height_at(Vector2(zone.at.x,zone.at.z)))
		check(valid, "pages and zones grounded seed %d" % sd)
		var lowest := 1.0
		for z in 64:
			for x in 64:
				for offset in [0.25,0.75]:
					lowest = minf(lowest,surface.normal_at(Vector2(x+offset,z+offset)*surface.STEP).y)
		check(lowest > cos(PI/4) and surface.height_at(Vector2(35,80)) > 0.5 and surface.height_at(Vector2(108,32)) > 0.5, "walkable hills replace flat core seed %d" % sd)
	check(fewest > 400 and most < 1500,"reduced tree density")
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"trees_min":fewest,"trees_max":most,"status":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)

