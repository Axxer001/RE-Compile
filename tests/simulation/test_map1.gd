extends RefCounted
# Map 1, the Dark Forest [Sir, 2026-11-20; docs/spec-map1-dark-forest.md §6]:
# the rules over many seeds (encounter odds, the spawn mix, drop rates, two
# exits), the state machine (3 s start, a roll every 3 s, at most 5 alive,
# spawning stops at the objective, combat ends only on a clear field, the
# cooldown, no combat in a pathway), then the world as the game builds it: the
# camp walled off from the town and unloaded past the point of no return,
# pathways fogging over and unloading behind, the wrap (seamless tiles, enemies
# re-centred and reaching the player across the edge), page drops, the
# objectives line, and death back to the camp with found pages kept.

const DT := 1.0 / 60.0
const Rules = preload("res://scripts/core/map1_rules.gd")
const World = preload("res://scripts/world/map1_world.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const N := 20000

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put(c: Node3D, at: Vector3) -> void:
	var p: CharacterBody3D = c.player
	at.y = c.map1.height_at(Vector2(at.x, at.z)) if c.map1 else at.y # on the ground (the field has hills)
	p.global_position = at + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	c.fall_speed = 0.0

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func kill(c: Node3D, e: CharacterBody3D, serial: int) -> void:
	e.health.apply(DamagePacket.new(serial, "player", "player", 1.0e7, "blast"), c.session.run.time)

static func live(c: Node3D) -> Array:
	return c.enemies.values().filter(func(e): return not e.reserve and e.visible and not e.health.dead)

## Gaps in the bamboo round a closed field: points just outside each edge (1.5 m and
## 4 m out) with no stem within 1.5 m and not in a pathway's lane. Returns their count.
static func bamboo_gaps(m: Node3D, c: Dictionary) -> int:
	var tc: Vector3 = c.centre + Vector3(c.tile.x * World.CHUNK, 0, c.tile.y * World.CHUNK)
	var stems: Array = []
	var holders: Array = [c.border] + m.pathways.map(func(q): return q.node)
	for h in holders:
		if not is_instance_valid(h): continue
		for mmi in (h as Node).find_children("*", "MultiMeshInstance3D", true, false):
			if not String(mmi.name) in ["Treeline", "Bamboo"]: continue
			var off: Vector3 = ((mmi as Node3D).get_parent() as Node3D).global_position
			for f3 in (mmi.get_meta("feet", PackedVector3Array()) as PackedVector3Array): stems.append(Vector2(f3.x + off.x, f3.z + off.z))
	var gaps := 0
	for d: Vector2i in World.EDGES:
		var out := Vector3(d.x, 0, d.y)
		var along := Vector3(absf(d.y), 0, absf(d.x))
		for k in range(-28, 29, 2):
			for v in [1.5, 4.0]:
				var q: Vector3 = tc + along * float(k) + out * (World.HALF + v)
				var in_lane := false
				for pw in m.pathways:
					if is_instance_valid(pw.node) and float(World.path_project(pw.pts, q).gap) < World.WALL_OFF + 0.4: in_lane = true
				if in_lane: continue
				var near := false
				for st in stems:
					if (st as Vector2).distance_to(Vector2(q.x, q.z)) < 1.5:
						near = true
						break
				if not near: gaps += 1
	return gaps

## The steepest ground face (smallest normal.y) of the Floor meshes under `node`: a hanging
## wall of ground (a vertical face) reads as a flat slab [Sir, 2026-11-22 bug].
static func flattest_up(node: Node) -> float:
	var lowest := 1.0
	for fm in node.find_children("Floor", "MeshInstance3D", true, false):
		var mesh: Mesh = (fm as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var nrm: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_NORMAL]
			var vtx: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for vi in nrm.size():
				if absf(nrm[vi].y) < lowest:
					lowest = absf(nrm[vi].y)
					node.set_meta("steepest_at", vtx[vi])
					var t0 := vi - vi % 3
					node.set_meta("steepest_tri", [vtx[t0], vtx[t0 + 1], vtx[t0 + 2]])
	return lowest

static func run(check: Callable, c: Node3D) -> void:
	_rules(check)
	await _world(check, c)

# ---- the rules, pure ----------------------------------------------------------------------
static func _rules(check: Callable) -> void:
	var r := Rules.new()
	r.reset(7)
	check.call(not r.has_method("encounter_roll"), "no pathway encounters: enemies only in a fight [Sir, 2026-11-22]")
	var mix := {"sprite": 0, "ghoul": 0, "mortus": 0}
	for i in N: mix[r.pick_kind()] += 1
	check.call(absf(mix.sprite / float(N) - 0.4) < 0.015 and absf(mix.ghoul / float(N) - 0.4) < 0.015 and absf(mix.mortus / float(N) - 0.2) < 0.012, "spawn mix: Sprite %.1f%%, Ghoul %.1f%%, Mortus %.1f%% (spec 40/40/20)" % [100.0 * mix.sprite / N, 100.0 * mix.ghoul / N, 100.0 * mix.mortus / N])
	# Drop rates over many seeds: kills on a page objective, one kind at a time.
	var drops := {"sprite": [0, 0], "ghoul": [0, 0], "mortus": [0, 0]}
	for sd in 200:
		r.reset(1000 + sd)
		for kind in drops:
			for k in 50:
				r.phase = "combat"
				r.objective = {"kind": "page", "kills": 0, "goal": 20, "met": false}
				drops[kind][1] += 1
				if r.on_kill(kind): drops[kind][0] += 1
	var rate := func(k: String) -> float: return float(drops[k][0]) / float(drops[k][1])
	check.call(absf(rate.call("sprite") - 0.2) < 0.015 and absf(rate.call("ghoul") - 0.2) < 0.015 and absf(rate.call("mortus") - 0.5) < 0.02, "page drops per kill over 200 seeds: Sprite %.1f%%, Ghoul %.1f%%, Mortus %.1f%% (spec 20/20/50)" % [100 * rate.call("sprite"), 100 * rate.call("ghoul"), 100 * rate.call("mortus")])
	r.reset(3)
	r.phase = "combat"
	r.objective = {"kind": "kills", "kills": 0, "goal": 20, "met": false}
	var any_drop := false
	for k in 200: any_drop = r.on_kill("mortus") or any_drop
	check.call(not any_drop and r.objective.met, "a kill objective never drops a page (pages drop only on a first fight's page objective)")

	# The state machine.
	r.reset(11)
	check.call(r.phase == "camp" and r.hud_line(0).begins_with("Camp"), "a run starts at the camp")
	r.enter_pathway()
	var in_path := []
	for i in int(200.0 / DT): in_path.append_array(r.step(DT, false, 0, true))
	check.call(r.phase == "pathway" and in_path.is_empty() and r.hud_line(0) == "Pathway", "in a pathway no combat ever starts (200 s)")
	r.enter_chunk()
	var ev := []
	for i in int(20.0 / DT): ev.append_array(r.step(DT, false, 0, true))
	check.call(r.phase == "entering" and ev.is_empty() and r.timed_visibility() < 0.0, "in a chunk short of 3 m in (not at full visibility), no fight starts (20 s)")
	ev = r.step(DT, true, 0, true)
	check.call(r.phase == "starting" and ev.size() == 1 and ev[0].event == "combat_starting", "3 m in (60 m visibility): the fight's blackout begins")
	for i in int(1.0 / DT): ev.append_array(r.step(DT, true, 0, true))
	var mid_fade: float = r.timed_visibility()
	ev = r.step(DT, false, 0, true)
	check.call(mid_fade < 60.0 and mid_fade > 5.0 and r.phase == "entering" and ev.size() == 1 and ev[0].event == "start_cancelled", "stepping back out mid-fade (%.0f m) cancels it" % mid_fade)
	ev = []
	for i in int((Rules.swap_s() - 0.1) / DT): ev.append_array(r.step(DT, true, 0, true))
	var dark: float = r.timed_visibility()
	var before_swap: bool = r.phase == "starting" and not ev.any(func(e): return e.event == "combat_start")
	for i in int(0.2 / DT): ev.append_array(r.step(DT, true, 0, true))
	var starts: Array = ev.filter(func(e): return e.event == "combat_start")
	check.call(before_swap and absf(dark - 5.0) < 0.01 and r.phase == "combat" and starts.size() == 1 and starts[0].objective == "page", "the fade reaches 5 m in 3 s; the fight starts at the hold's middle (%.2f s); the first fight with pages missing wants a page" % Rules.swap_s())
	var v0: float = r.timed_visibility()
	for i in int((float(Rules.T.hold_s) * 0.5 + float(Rules.T.fade_up_s) + 0.05) / DT): r.step(DT, true, 9, true)
	check.call(absf(v0 - 5.0) < 0.01 and absf(r.timed_visibility() - 30.0) < 0.01, "then visibility opens out from 5 m to the fight's 30 m in %.1f s" % Rules.T.fade_up_s)
	r.spawn_s = 0.0
	check.call(r.hud_line(0) == "Find a page", "objectives line: Find a page")
	var spawned := 0
	var alive := 0
	var at_cap := true
	for i in int(60.0 / DT):
		for e in r.step(DT, true, alive, true):
			if e.event == "spawn":
				spawned += 1
				alive += 1
		if alive > 5: at_cap = false
	check.call(alive == 5 and at_cap and spawned == 5, "a roll every 3 s spawns enemies, never more than 5 alive (%d spawned in 60 s)" % spawned)
	alive = 2
	var rolls := 0
	r.spawn_s = 0.0
	for i in int(3000.0 / DT):
		for e in r.step(DT, true, alive, true): if e.event == "spawn": rolls += 1
		alive = 2 # the test keeps it below the cap
	check.call(rolls >= 650 and rolls <= 750, "about 70%% of the rolls spawn (%d of 1000 in 3000 s)" % rolls)
	r.objective.met = true
	var after_met := []
	for i in int(30.0 / DT): after_met.append_array(r.step(DT, true, 3, true))
	check.call(after_met.is_empty() and r.phase == "combat" and r.hud_line(3) == "Clear the field · 3 left", "at the objective spawning stops; combat goes on while enemies are alive ('Clear the field · 3 left')")
	var ended := r.step(DT, true, 0, true)
	check.call(r.phase == "ending" and ended.size() == 1 and ended[0].event == "combat_end", "the field clear: the fight ends and its blackout begins")
	var opened := []
	for i in int((Rules.swap_s() + 0.05) / DT): opened.append_array(r.step(DT, true, 0, true))
	check.call(r.phase == "cooldown" and opened.size() == 1 and opened[0].event == "exits_open" and int(opened[0].count) in [1, 2], "at the hold's middle the cooldown opens %d exit(s)" % (int(opened[0].count) if opened.size() > 0 else 0))
	for i in int((float(Rules.T.hold_s) * 0.5 + float(Rules.T.fade_up_s)) / DT): r.step(DT, true, 0, true)
	check.call(absf(r.timed_visibility() - 60.0) < 0.05, "then visibility opens out to the closed field's 60 m")
	var cd: String = r.hud_line(0)
	var idle := []
	for i in int(130.0 / DT): idle.append_array(r.step(DT, false, 0, true))
	var waits: bool = idle.is_empty() and r.phase == "cooldown" and r.cooldown_left == 0.0
	idle = r.step(DT, true, 0, true)
	var restarted: bool = idle.size() == 1 and idle[0].event == "combat_starting"
	for i in int((Rules.swap_s() + 0.05) / DT): idle.append_array(r.step(DT, true, 0, true))
	var again: Array = idle.filter(func(e): return e.event in ["exits_close", "combat_start"])
	check.call(cd == "Choose a path" and waits and restarted and again.size() == 2 and again[0].event == "exits_close" and again[1].objective == "kills" and r.hud_line(0) == "Defeat 20 · 0/20", "the cooldown lasts 2 min (the objectives line: '%s', no timer); past it a fight restarts only with the player in the field, its blackout closing the exits; a later fight wants 20 kills" % cd)
	r.reset(5)
	r.enter_chunk()
	var first_kills := []
	for i in int((Rules.swap_s() + 0.1) / DT): first_kills.append_array(r.step(DT, true, 0, false))
	var fk: Array = first_kills.filter(func(e): return e.event == "combat_start")
	check.call(fk.size() == 1 and fk[0].objective == "kills", "a first fight with every page found wants 20 kills")
	for k in 19: r.on_kill("sprite")
	var nineteen: bool = not r.objective.met
	r.on_kill("ghoul")
	check.call(nineteen and r.objective.met, "the 20th kill meets the objective")
	var twos := 0
	for sd in 2000:
		r.reset(5000 + sd)
		r.phase = "ending"
		r.phase_t = Rules.swap_s()
		for e in r.step(DT, true, 0, true): if e.event == "exits_open" and int(e.count) == 2: twos += 1
	check.call(absf(twos / 2000.0 - 0.3) < 0.03, "a second exit opens %.1f%% of the time (spec 30%%)" % (100.0 * twos / 2000.0))
	# Pathway pieces.
	var g := RandomNumberGenerator.new()
	var lens_ok := true
	var kinds := {"straight": 0, "bend": 0, "slope": 0}
	for sd in 300:
		g.seed = sd
		var L := g.randf_range(30.0, 90.0)
		var pts: Array = World.pathway_points(g, Vector3.ZERO, L)
		var got: float = World.path_length(pts)
		if got < 30.0 - 0.01 or got > 92.0 or absf(got - L) > 3.0: lens_ok = false
		for i in range(1, pts.size()):
			var d: Vector3 = pts[i] - pts[i - 1]
			if absf(d.x) > 0.01: kinds.bend += 1
			elif absf(d.y) > 0.01: kinds.slope += 1
			else: kinds.straight += 1
		if pts[pts.size() - 1].z > -20.0: lens_ok = false
	check.call(lens_ok and kinds.bend > 0 and kinds.slope > 0 and kinds.straight > 0, "pathways are seeded pieces (straight %d, bend %d, slope %d), 30-90 m long" % [kinds.straight, kinds.bend, kinds.slope])
	var dirs_ok := true
	var lean_ok := true
	for sd in 100:
		for d: Vector2i in World.EDGES:
			g.seed = sd
			var pts2: Array = World.pathway_points(g, Vector3.ZERO, 50.0, d, 1)
			var end2: Vector3 = pts2[pts2.size() - 1]
			if Vector2(end2.x, end2.z).dot(Vector2(d)) < 35.0: dirs_ok = false
			var last_side := -1.0
			for q in pts2:
				var side: float = Vector2(q.x, q.z).dot(Vector2(absf(d.y), absf(d.x)) * (1.0 if d == Vector2i(0, -1) or d == Vector2i(1, 0) else -1.0))
				if side < last_side - 0.01: lean_ok = false
				last_side = maxf(last_side, side)
	check.call(dirs_ok and lean_ok, "a pathway can head out of any edge; one leaning to a side only ever bends that way")
	# The combat field [layout pass §3, Sir]: grass only, a few rocks, hills under 25 degrees.
	var l1: Dictionary = World.chunk_layout(77)
	var l2: Dictionary = World.chunk_layout(77)
	var inside := true
	for rk in l1.rocks: if absf(rk[0]) > 28.0 or absf(rk[1]) > 28.0 or Vector2(rk[0], rk[1]).distance_to(Vector2(0, 28)) < 9.0: inside = false
	for sd in 40:
		for rk in World.chunk_layout(500 + sd).rocks:
			for d: Vector2i in World.EDGES:
				for off in [0.0, -World.SAME_EDGE_OFFSET, World.SAME_EDGE_OFFSET]:
					var mouth_l: Vector2 = Vector2(d) * (World.HALF - 2.0) + Vector2(absf(d.y), absf(d.x)) * off
					if Vector2(rk[0], rk[1]).distance_to(mouth_l) < World.EXIT_CLEAR: inside = false
	check.call(str(l1) == str(l2) and l1.trees.is_empty() and l1.rocks.size() >= World.ROCKS.x and l1.rocks.size() <= World.ROCKS.y and inside, "a combat chunk: no trees, %d rocks (the only cover), seeded, clear of the entrance and of every edge's exit mouths" % l1.rocks.size())
	var steepest := 0.0
	var seam := 0.0
	for sd in 40:
		var lay: Dictionary = World.chunk_layout(9000 + sd)
		var st: float = World.FIELD_STEP
		for i in int(World.CHUNK / st):
			for j in int(World.CHUNK / st):
				var x0: float = -World.HALF + i * st
				var z0: float = -World.HALF + j * st
				for tri in [[Vector2(0, 0), Vector2(st, 0), Vector2(0, st)], [Vector2(st, 0), Vector2(st, st), Vector2(0, st)]]:
					var v: Array = tri.map(func(q): return Vector3(x0 + q.x, World.grid_h(lay, x0 + q.x, z0 + q.y), z0 + q.y))
					var nrm: Vector3 = ((v[1] as Vector3) - v[0]).cross((v[2] as Vector3) - v[0]).normalized()
					steepest = maxf(steepest, rad_to_deg(acos(absf(nrm.y))))
		for k in 30:
			var t := -World.HALF + k * 2.0
			seam = maxf(seam, absf(World.field_h(lay, t, -World.HALF) - World.field_h(lay, t, World.HALF - 0.0001)))
			seam = maxf(seam, absf(World.field_h(lay, -World.HALF, t) - World.field_h(lay, World.HALF - 0.0001, t)))
			seam = maxf(seam, World.wave_normal(lay.phase, t, -World.HALF).distance_to(World.wave_normal(lay.phase, t, World.HALF)))
	check.call(steepest < 25.0 and steepest > 10.0, "the hills over 40 seeds: the steepest face is %.1f degrees (under 25)" % steepest)
	check.call(seam < 0.002, "the field is the same at opposite edges, heights and normals (largest gap %.4f): the wrap has no seam" % seam)

# ---- the world, as the game builds it ----------------------------------------------------
static func _world(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	c.fixed_map_seed = 4242
	s.restart()
	await tree.physics_frame
	await tree.physics_frame
	var m: Node3D = c.map1
	var p: CharacterBody3D = c.player
	check.call(c.world_kind == "forest" and m != null and m.camp_loaded and m.find_child("Town", false, false) != null and flat(p.global_position).distance_to(flat(World.SPAWN.at)) < 0.5 and c.rules.phase == "camp", "a run starts at the camp, the town in the valley behind it")
	check.call(c.alive_count() == 0, "the camp is safe: nothing spawns")
	var wall: Dictionary = c.world_ray(World.CAMPFIRE + Vector3(0, 1.5, 0), Vector3(World.TOWN_AT.x, 1.5, World.CAMP_BOX[1].y + 12.0)) # toward the town, level
	check.call(not wall.is_empty() and String(wall.collider.name) == "camp_wall_town", "an invisible wall keeps the town out of reach (%s)" % (wall.collider.name if not wall.is_empty() else "nothing"))
	check.call(is_equal_approx(m.visibility_at(p.global_position, c.rules), Rules.VIS.camp), "the camp: 30 m visibility (%.0f m)" % m.visibility_at(p.global_position, c.rules))
	# Into Pathway #0.
	var pw0: Dictionary = m.pathways[0]
	var floor_mesh: Mesh = pw0.node.get_node("Floor").mesh
	var normals: PackedVector3Array = floor_mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	check.call(normals[0].y > 0.5 and normals[normals.size()/2].y > 0.5, "pathway renders its top face")

	put(c, World.path_point(pw0.pts, 1.5))
	steps(c, 0.1)
	var half_in: float = m.visibility_at(p.global_position, c.rules)
	put(c, World.path_point(pw0.pts, 8.0))
	steps(c, 0.1)
	check.call(c.rules.phase == "pathway" and half_in < Rules.VIS.camp and half_in > Rules.VIS.pathway and is_equal_approx(m.visibility_at(p.global_position, c.rules), Rules.VIS.pathway) and m.camp_loaded, "into Pathway #0: visibility closes from 30 to 20 m over its first 3 m (%.1f m half-way); the camp stays loaded" % half_in)
	put(c, World.path_point(pw0.pts, World.UNLOAD_M + 1.0))
	steps(c, 0.1)
	await tree.physics_frame
	var back: Dictionary = c.world_ray(World.path_point(pw0.pts, 3.0) + Vector3(0, 1.2, 0), World.path_point(pw0.pts, 1.0) + Vector3(0, 1.2, 0)) # across the wall at 2 m (straight there)
	check.call(not m.camp_loaded and m.camp == null and m.find_child("Town", false, false) == null and not back.is_empty() and String(back.collider.name) == "no_return", "%.0f m in (past the 20 m visibility) the camp unloads, a thicket and a wall closing the way back (camp %s, hit %s)" % [World.UNLOAD_M, m.camp_loaded, back.collider.name if not back.is_empty() else "nothing"])
	var fp: Node3D = c.training.forest_portal if c.training else null
	var fp_solid := false
	if fp:
		for cs in fp.find_children("*", "CollisionShape3D", true, false): fp_solid = fp_solid or not (cs as CollisionShape3D).disabled
	check.call(fp != null and not fp.visible and not fp_solid and not fp.is_visible_in_tree(), "the camp's Training Field portal (and its sign and frame) goes with the camp: nothing of the camp shows later")
	# The first combat chunk.
	var ch: Dictionary = m.next_chunk
	check.call(not ch.is_empty() and ch.index == 1, "Pathway #0 leads to the first combat chunk")
	var only_own: bool = ch.tiles.keys().all(func(k): return ch.tiles[k].visible == (k == Vector2i.ZERO))
	put(c, ch.centre + Vector3(0, 0, World.HALF - 1.5))
	steps(c, 0.1)
	await tree.physics_frame
	var entering: bool = c.rules.phase == "entering" and m.chunk == ch
	var ramp_vis: float = m.visibility_at(p.global_position, c.rules)
	var ey: float = maxf(m.height_at(Vector2(ch.centre.x + 20, ch.centre.z)), m.height_at(Vector2(ch.centre.x + 29.5, ch.centre.z))) + 3.0
	var east: Dictionary = c.world_ray(Vector3(ch.centre.x + 20, ey, ch.centre.z), Vector3(ch.centre.x + 40, ey, ch.centre.z))
	var up0: float = minf(flattest_up(m.pathways[0].node), flattest_up(ch.border))
	check.call(up0 > 0.25, "no ground hangs as a wall at a pathway's or a field's edge: the steepest ground face's normal.y is %.2f (pathway %.2f, border %.2f)" % [up0, flattest_up(m.pathways[0].node), flattest_up(ch.border)] + " tri %s" % str((m.pathways[0].node.get_meta("steepest_tri", []) as Array).map(func(v): var pr: Dictionary = World.path_project(m.pathways[0].pts, v); return "(along %.2f, out %.2f, y %.2f)" % [float(pr.along), float(pr.gap), v.y])))
	var g1: int = bamboo_gaps(m, ch)
	check.call(g1 == 0, "the bamboo round the first field has no gaps, the entrance joining it (%d gaps)" % g1)
	check.call(only_own and is_instance_valid(ch.border) and not east.is_empty() and String(east.collider.name).begins_with("field_edge_e") and ramp_vis > Rules.VIS.pathway and ramp_vis < Rules.VIS.peace, "the first chunk is a closed field: its own tile only, walled in bamboo (%s); 1.5 m in, visibility is opening out (%.0f m)" % [east.collider.name if not east.is_empty() else "open", ramp_vis])
	var seam_gap := 0.0
	for lat in [-3.0, -1.5, 0.0, 1.5, 3.0]: # where Pathway #0 meets the field: one surface
		var pe: Vector3 = World.path_point(m.pathways[0].pts, float(m.pathways[0].length) - 0.3) + Vector3(lat, 0, 0)
		var hit: Dictionary = c.world_ray(pe + Vector3(0, 6, 0), pe - Vector3(0, 6, 0))
		seam_gap = maxf(seam_gap, absf(float(hit.position.y) - World.field_world(ch, pe)) if not hit.is_empty() else 99.0)
	check.call(seam_gap < 0.08, "Pathway #0's floor blends into the field: no step where they meet (%.3f m)" % seam_gap)
	put(c, ch.centre + Vector3(0, 0, World.HALF - 4.0))
	steps(c, 0.1)
	check.call(entering and c.rules.phase == "starting" and is_equal_approx(Rules.VIS.peace, 60.0), "3 m in, at 60 m visibility, the fight's blackout begins")
	steps(c, Rules.swap_s() - 0.3)
	var still_closed: bool = c.rules.phase == "starting" and not m.pathways.is_empty() and not ch.wrap
	steps(c, 0.4)
	await tree.physics_frame
	check.call(still_closed and c.rules.phase == "combat" and c.rules.objective.kind == "page" and m.pathways.is_empty() and not is_instance_valid(ch.border) and ch.wrap and ch.tiles.size() == 9 and ch.tiles.values().all(func(t): return t.visible), "in the 5 m blackout the border and the pathway behind go, the field wraps round (3 x 3 tiles); the first fight wants a page")
	steps(c, float(Rules.T.fade_up_s) + 0.2)
	check.call(absf(m.visibility_at(p.global_position, c.rules) - Rules.VIS.combat) < 0.01, "then a fight's 30 m visibility")
	check.call(c.mission_hud.text.begins_with("Find a page"), "the objectives line shows the objective ('%s')" % c.mission_hud.text.get_slice("\n", 0))
	# The field's collider is the surface height_at reads (navigation, spawns, drops).
	var off_ground := 0.0
	var g := RandomNumberGenerator.new()
	g.seed = 5
	for i in 60:
		var q: Vector3 = ch.centre + Vector3(g.randf_range(-85, 85), 0, g.randf_range(-85, 85))
		var hit: Dictionary = c.world_ray(q + Vector3(0, 20, 0), q - Vector3(0, 20, 0))
		if hit.is_empty() or not String(hit.collider.name) == "floor": continue
		off_ground = maxf(off_ground, absf(float(hit.position.y) - m.height_at(Vector2(q.x, q.z))))
	check.call(off_ground < 0.02, "over the 3 x 3 tiles the ground's collider and height_at are the same triangles (largest gap %.4f m)" % off_ground)
	var grass_n := 0
	for k in ch.grass: grass_n += (ch.grass[k] as MultiMesh).instance_count
	check.call(grass_n >= int(World.CHUNK * World.CHUNK * World.FIELD_GRASS * 0.9), "BinbunGrass covers the field: %d cards per tile, shared by the 9 tiles" % grass_n)
	# Spawns: 32-40 m out, at most 5, still 32 m+ after wrapping (the diagonals), fading in.
	for e in live(c): c._to_reserve(e) # the pathway's encounter, if any: only fresh spawns count here
	var ring_ok := true
	var wrap_ok := true
	var faded := true
	var most := 0
	var pc: Vector3 = ch.centre
	for i in int(30.0 / DT):
		put(c, pc)
		p.health.reset() # the fights below must not end the run
		c.session.step(DT)
		var lv := live(c)
		most = maxi(most, lv.size())
		for e in lv:
			if not e.has_meta("m1_seen"):
				e.set_meta("m1_seen", true)
				var d: float = flat(e.global_position).distance_to(flat(pc))
				if d < 31.0 or d > 41.0: ring_ok = false
				var dd: Vector3 = e.global_position - pc
				var near := Vector2(fposmod(dd.x + World.HALF, World.CHUNK) - World.HALF, fposmod(dd.z + World.HALF, World.CHUNK) - World.HALF)
				if near.length() < 31.5: wrap_ok = false
				var geo: Array = e.find_children("*", "GeometryInstance3D", true, false)
				if geo.is_empty() or (geo[0] as GeometryInstance3D).transparency < 0.5: faded = false
	check.call(most > 0 and most <= 5 and ring_ok, "enemies spawn 32-40 m out, just past the fog (at most %d alive)" % most)
	check.call(wrap_ok, "every spawn is still 32 m+ away at its nearest image after wrapping (the diagonals)")
	check.call(faded, "a spawn starts faded out and fades in from the mist")
	var fade_done := true
	for e in live(c): if e.has_meta("m1_fade") or ((e.find_children("*", "GeometryInstance3D", true, false)[0] as GeometryInstance3D).transparency > 0.01 and not e.has_meta("m1_fade")): fade_done = false
	check.call(fade_done, "after %.1f s it is solid" % c.M1_FADE_S)
	# The wrap: walking off an edge, the tiles follow; enemies are re-centred.
	var t0: Vector2i = ch.tile
	put(c, pc + Vector3(World.HALF + 2.0, 0, 0))
	c.session.step(DT)
	await tree.physics_frame
	var e1: CharacterBody3D = live(c)[0] if not live(c).is_empty() else null
	check.call(ch.tile == t0 + Vector2i(1, 0) and ch.tiles[Vector2i(0, 0)].position.x > pc.x + 50.0, "off the east edge, the field goes on: the tiles move round the player")
	if e1:
		e1.global_position = p.global_position + Vector3(38.0, 0, 3.0)
		c.session.step(DT)
		var dd: Vector3 = e1.global_position - p.global_position
		check.call(absf(dd.x - (38.0 - World.CHUNK)) < 0.6 and absf(dd.z - 3.0) < 0.6, "an enemy 38 m east is at its nearest image, 22 m west (%.1f, %.1f)" % [dd.x, dd.z])
	# Enemies reach the player across the edge (on foot, through the wrap).
	for e in live(c): c._to_reserve(e)
	var anchor: Vector3 = ch.centre + Vector3(ch.tile.x * World.CHUNK, 0, ch.tile.y * World.CHUNK)
	put(c, anchor + Vector3(-World.HALF + 3.0, 0, 0)) # just inside the tile's west edge
	steps(c, 0.1)
	p.health.reset()
	var spr: CharacterBody3D = c._m1_place("sprite", p.global_position + Vector3(-14.0, 0, 0)) # across the edge, in the next tile
	var start_d: float = flat(spr.global_position).distance_to(flat(p.global_position))
	var reached := false
	c.rules.objective.met = true # no more spawns while it walks
	for i in int(10.0 / DT):
		c.session.step(DT)
		if flat(spr.global_position).distance_to(flat(p.global_position)) < 2.2: reached = true
	check.call(reached, "an enemy across the edge paths over it and reaches the player (from %.0f m)" % start_d)
	# On the hills: a diagonal crossing, a run up and down, a drop on a slope, a
	# fireball grazing a crest, Pounce and Charge across slopes.
	for e in live(c): c._to_reserve(e)
	c.rules.objective.met = false # (the cross-edge check above set it to hold spawns)
	c.spawning = false # no spawns while these run (combat itself goes on)
	var corner: Vector3 = ch.centre + Vector3(ch.tile.x * World.CHUNK + World.HALF - 1.0, 0, ch.tile.y * World.CHUNK + World.HALF - 1.0)
	put(c, corner)
	var t_before: Vector2i = ch.tile
	var grounded := true
	for i in int(0.6 / DT):
		p.velocity = Vector3(6.0, p.velocity.y, 6.0) # diagonally over the corner
		c.session.step(DT)
		if p.global_position.y < m.height_at(Vector2(p.global_position.x, p.global_position.z)) - 0.3: grounded = false
	check.call(ch.tile == t_before + Vector2i(1, 1) and grounded, "a diagonal crossing over a tile corner: both axes wrap, the player stays on the ground")
	var climb := true
	var hi: Vector3 = ch.centre
	var best_h := -INF
	for k in 40: # the highest point on a line through the middle: run over the crest
		var q: Vector3 = ch.centre + Vector3(-20.0 + k, 0, 0)
		var hq: float = m.height_at(Vector2(q.x, q.z))
		if hq > best_h:
			best_h = hq
			hi = q
	put(c, hi + Vector3(-8, 0, 0))
	for i in int(1.4 / DT):
		p.velocity = Vector3(12.0, p.velocity.y, 0.0) # a dash-speed run up and over the crest
		c.session.step(DT)
		if p.global_position.y < m.height_at(Vector2(p.global_position.x, p.global_position.z)) - 0.3: climb = false
	check.call(climb and p.global_position.x > hi.x + 4.0, "a dash-speed run up and over a crest: never under the ground (%.1f m past it)" % (p.global_position.x - hi.x))
	var slope_at: Vector3 = hi + Vector3(5, 0, 3)
	var slope_pid: String = c.drop_page(slope_at)
	var pg_y: float = c.page_pickups[slope_pid].global_position.y - 0.6 if slope_pid != "" else -999.0
	check.call(slope_pid != "" and absf(pg_y - m.height_at(Vector2(slope_at.x, slope_at.z))) < 0.05, "a page dropped on a slope lies on the ground")
	if slope_pid != "":
		c.page_pickups[slope_pid].set_meta("dropped", false)
		c._sync_page_pickups()
	var low: Vector3 = hi + Vector3(-14, 0, 0)
	var from: Vector3 = low + Vector3(0, m.height_at(Vector2(low.x, low.z)) - low.y + 0.7, 0)
	var crest: Vector3 = hi + Vector3(0, best_h - hi.y, 0)
	var det0: int = c.projectiles.detonations.size()
	c.projectiles.launch("basic", from, ((crest + Vector3(0, 0.5, 0)) - from).normalized(), {"damage": 1.0}) # just over the crest
	for i in int(1.0 / DT): c.session.step(DT)
	var over_ok := true
	for k in range(det0, c.projectiles.detonations.size()):
		if (c.projectiles.detonations[k].at as Vector3).x < crest.x: over_ok = false
	var det1: int = c.projectiles.detonations.size()
	c.projectiles.launch("basic", from, ((crest - Vector3(0, 0.6, 0)) - from).normalized(), {"damage": 1.0}) # into the slope below it
	for i in int(1.5 / DT): c.session.step(DT)
	var landed: bool = c.projectiles.detonations.size() > det1
	var det_at: Vector3 = c.projectiles.detonations[c.projectiles.detonations.size() - 1].at if landed else Vector3.INF
	check.call(over_ok and landed and absf(det_at.y - m.height_at(Vector2(det_at.x, det_at.z))) < 0.6 and det_at.x <= crest.x + 0.5, "a fireball skims over a crest (no burst short of it); one aimed into the slope bursts on the ground there")
	put(c, hi)
	p.health.reset()
	var spr2: CharacterBody3D = c._m1_place("sprite", hi + Vector3(-13.0, 0, 0)) # 13 m down the slope
	var dove := false
	var under := false
	for i in int(4.0 / DT):
		put(c, hi)
		c.session.step(DT)
		if spr2.state == spr2.State.DIVE: dove = true
		if spr2.global_position.y < m.height_at(Vector2(spr2.global_position.x, spr2.global_position.z)) - 0.4: under = true
	check.call(dove and spr2.pounces >= 1 and not under, "a Sprite pounces up a slope (pounces %d) and never sinks into the hill" % spr2.pounces)
	c._to_reserve(spr2)
	p.health.reset()
	var mor: CharacterBody3D = c._m1_place("mortus", hi + Vector3(0, 0, 18.0)) # 18 m across the hills
	var charged := false
	var m_under := false
	for i in int(6.0 / DT):
		put(c, hi)
		c.session.step(DT)
		if mor.state == mor.State.CHARGE or mor.charges > 0: charged = true
		if mor.global_position.y < m.height_at(Vector2(mor.global_position.x, mor.global_position.z)) - 0.4: m_under = true
	check.call(charged and not m_under, "Kostas Mortus charges across the hills and stays on the ground")
	c._to_reserve(mor)
	c.spawning = true
	# The objective: kill until a page drops.
	c.rules.objective.met = false
	for e in live(c): c._to_reserve(e)
	var serial := 77000
	var dropped := ""
	for i in 60:
		var e2: CharacterBody3D = c._m1_place(["sprite", "ghoul", "mortus"][i % 3], p.global_position + Vector3(4, 0, 4))
		serial += 1
		kill(c, e2, serial)
		for pid in c.page_pickups:
			if c.page_pickups[pid].visible: dropped = pid
		if dropped != "": break
	var drop_at: Vector3 = c.page_pickups[dropped].global_position if dropped != "" else Vector3.ZERO
	check.call(dropped != "" and c.rules.objective.met and flat(drop_at).distance_to(flat(p.global_position + Vector3(4, 0, 4))) < 1.0, "a kill drops a page where the enemy died (%s); the objective is met" % dropped)
	var spawned_after := 0
	for i in int(9.0 / DT):
		p.health.reset()
		var before: int = live(c).size()
		c.session.step(DT)
		if live(c).size() > before: spawned_after += 1
	check.call(spawned_after == 0, "spawning stops at the objective")
	var lv2: Array = live(c)
	var phase_with_alive: String = c.rules.phase
	for e in lv2:
		serial += 1
		kill(c, e, serial)
	c.session.step(DT)
	check.call((lv2.is_empty() and c.rules.phase in ["ending", "cooldown"]) or (phase_with_alive == "combat" and c.rules.phase == "ending"), "the fight ends only once the field is clear; its blackout begins (phase %s, %d alive)" % [c.rules.phase, c.alive_count()])
	var away := p.global_position
	steps(c, Rules.swap_s() + 0.1)
	await tree.physics_frame
	var tc: Vector3 = ch.centre + Vector3(ch.tile.x * World.CHUNK, 0, ch.tile.y * World.CHUNK)
	var exits_n: int = c.rules.exits
	check.call(c.rules.phase == "cooldown" and exits_n in [1, 2] and flat(p.global_position).distance_to(flat(tc)) < 0.5 and not ch.wrap and is_instance_valid(ch.border) and ch.tiles.keys().all(func(k): return ch.tiles[k].visible == (k == Vector2i.ZERO)), "in the blackout the player is moved to the middle of the field (from %.0f m off), which closes in bamboo round its own tile; %d exit(s)" % [flat(away).distance_to(flat(tc)), exits_n])
	var exits: Array = m.pathways.filter(func(q): return q.get("exit", false))
	var edge_ok: bool = exits.size() == exits_n
	var over := 0
	for q in exits:
		var d: Vector2i = q.dir
		var o: Vector3 = q.pts[0]
		if absf((o - tc).dot(Vector3(d.x, 0, d.y)) - World.HALF) > 0.05: edge_ok = false
		for a in range(1, int(q.length), 2):
			var pt := World.path_point(q.pts, float(a))
			if absf(pt.x - tc.x) < World.HALF - 0.05 and absf(pt.z - tc.z) < World.HALF - 0.05: over += 1
	if exits.size() == 2:
		for a in range(0, int(exits[0].length), 3):
			var p0 := World.path_point(exits[0].pts, float(a))
			for b in range(0, int(exits[1].length), 3):
				if flat(p0).distance_to(flat(World.path_point(exits[1].pts, float(b)))) < 2.0 * World.WALL_OFF: over += 1
	var g2: int = bamboo_gaps(m, ch)
	check.call(g2 == 0, "the bamboo round the closed field has no gaps where its exits join it (%d gaps)" % g2)
	check.call(edge_ok and over == 0, "each exit's pathway starts on an edge of the field and runs outside it (and clear of the other): %d points too close" % over)
	steps(c, float(Rules.T.hold_s) * 0.5 + float(Rules.T.fade_up_s) + 0.1)
	check.call(absf(m.visibility_at(p.global_position, c.rules) - Rules.VIS.peace) < 0.01 and c.rules.hud_line(0) == "Choose a path" and (c.NEXT_WAVE_NOTICE % "2:00") in c.notices_shown, "the next wave's 2:00 shows as a notice when the fight ends; then the closed field's 60 m visibility, on cooldown")
	# Touch the page (it was moved into the closed field).
	var pg_at: Vector3 = c.page_pickups[dropped].global_position
	check.call(absf(pg_at.x - tc.x) < World.HALF and absf(pg_at.z - tc.z) < World.HALF, "a page still on the ground is inside the closed field")
	put(c, pg_at - Vector3(0, 0.6, 0))
	c.session.step(DT)
	check.call(c.try_interact(true) == "page" and s.grimoire.is_found(dropped), "a dropped page is picked up by touching it (F)")
	c.try_interact(false)
	# Take an exit; no combat in the pathway, even past the cooldown.
	var pw: Dictionary = exits[0]
	put(c, World.path_point(pw.pts, 1.5))
	c.session.step(DT)
	await tree.physics_frame
	var closed_other := true
	if exits.size() == 2:
		var o: Dictionary = exits[1]
		var hit_o: Dictionary = c.world_ray(World.path_point(o.pts, 3.0) + Vector3(0, 1.2, 0), (o.pts[0] as Vector3) - (World.path_point(o.pts, 3.0) - (o.pts[0] as Vector3)) + Vector3(0, 1.2, 0))
		closed_other = not hit_o.is_empty() and String(hit_o.collider.name) == "exit_closed"
	check.call(m.chunk.is_empty() and not m.old_chunk.is_empty() and not m.next_chunk.is_empty() and c.rules.phase == "pathway" and closed_other, "an exit leads into a pathway toward a new combat chunk; the field stays loaded behind, any other exit is walled off")
	put(c, World.path_point(pw.pts, 10.0))
	steps(c, 0.1)
	var kept: bool = not m.old_chunk.is_empty() and is_equal_approx(m.visibility_at(p.global_position, c.rules), Rules.VIS.pathway)
	put(c, World.path_point(pw.pts, World.UNLOAD_M + 1.0))
	steps(c, 0.1)
	await tree.physics_frame
	var seal: Dictionary = c.world_ray(World.path_point(pw.pts, 3.0) + Vector3(0, 1.2, 0), World.path_point(pw.pts, 1.0) + Vector3(0, 1.2, 0)) # across the wall at 2 m
	check.call(kept and m.old_chunk.is_empty() and ch.tiles.is_empty() and m.pathways.size() == 1 and not seal.is_empty() and String(seal.collider.name) == "seal_wall", "%.0f m in (past the 20 m visibility) the field and any other exit unload, a thicket and a wall closing the way back (kept %s, old %s, tiles %d, pathways %d, hit %s)" % [World.UNLOAD_M, kept, m.old_chunk.is_empty(), ch.tiles.size(), m.pathways.size(), seal.collider.name if not seal.is_empty() else "nothing"])
	var stays := true
	for i in int(130.0 / DT / 10):
		put(c, World.path_point(pw.pts, World.UNLOAD_M + 1.0))
		for k in 10: c.session.step(DT)
		if c.rules.phase != "pathway": stays = false
	check.call(stays and c.rules.phase == "pathway", "in a pathway combat never triggers, even 130 s on")
	# Death: back to the camp, the found page kept.
	p.health.apply(DamagePacket.new(99001, "x", "infected", 1.0e7, "blast"), s.run.time)
	s.restart()
	await tree.physics_frame
	check.call(m.camp_loaded and flat(p.global_position).distance_to(flat(World.SPAWN.at)) < 0.5 and s.grimoire.is_found(dropped) and c.rules.phase == "camp" and m.pathways.size() == 1, "death: back at the camp, the corridor rebuilt from the start, the found page kept")
	check.call(c.training.forest_portal.visible and c.training.forest_open, "the Training Field portal is back at the camp")
	c.fixed_map_seed = -1
