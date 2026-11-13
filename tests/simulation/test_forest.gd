extends RefCounted
# P7 Dark Forest (handoff §7) with Sir's R11 map generation, on a main built
# as the game builds it: the fixed clearings, paths and camp; a seeded map
# (trees, rocks, ledges, page spots, spawn zones) that is identical for the
# same seed, new on every run and death, valid for 1,000 seeds, built within
# 200 ms, and walkable on the real navigation grid; the camp fire, night grade
# and fog; trees blocking sight; the boundary; a quiet start; a death sending
# the player back to camp.

const DT := 1.0 / 60.0
const Forest = preload("res://scripts/world/dark_forest.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const SEEDS := 50 # a sample here; the Content suite runs 1,000 [R11]

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	var p: CharacterBody3D = c.player
	check.call(c.world_kind == "forest" and c.level == Forest and c.find_child("DarkForest", false, false) != null and c.find_child("Greybox", false, false) == null, "the game builds the Dark Forest, not the arena")
	check.call(not "doors" in c and not "terminals" in c and not "objectives" in c, "no doors, terminals, notes or research files in the game [P7]")

	# ---- R11: generation -----------------------------------------------------------------
	check.call(Forest.generate(4242, 0).is_empty(), "exhausted generation rejects the map")
	var a1 := Forest.generate(4242)
	var a2 := Forest.generate(4242)
	var b := Forest.generate(4243)
	check.call(str(a1) == str(a2) and str(a1) != str(b) and a1.trees != b.trees and a1.pages != b.pages, "a fixed seed gives an identical map; the next seed a different one [R11]")
	var t0 := Time.get_ticks_usec()
	var bad := []
	var tree_n := [1000000, 0]
	for sd in SEEDS:
		var m := Forest.generate(sd)
		if m.is_empty():
			bad.append("seed %d: generation failed" % sd)
			continue
		var v: Array = Forest.rule_violations(m)
		if not v.is_empty() and bad.size() < 3: bad.append("seed %d: %s" % [sd, v[0]])
		tree_n[0] = mini(tree_n[0], m.trees.size())
		tree_n[1] = maxi(tree_n[1], m.trees.size())
	var per_ms := (Time.get_ticks_usec() - t0) / 1000.0 / SEEDS
	check.call(bad.is_empty(), "%d seeds (sample) all pass R11's rules (reachable; pages >= 25 m from the start, >= 20 m apart, >= 15 m from zones; nothing within 3 m of a path or in the camp) %s" % [SEEDS, str(bad)])
	check.call(tree_n[1] > tree_n[0] + 100 and tree_n[0] > 400, "tree density varies by seed (%d to %d trees)" % [tree_n[0], tree_n[1]])
	c.new_map(17)
	var build_ms: float = c.map_ms
	await tree.physics_frame
	check.call(build_ms <= 200.0 and per_ms <= 200.0, "a new map is generated and built in %.0f ms (generation alone %.1f ms) <= 200 ms [R11]" % [build_ms, per_ms])
	# A new seed and a new forest each run, deaths included.
	c.fixed_map_seed = -1
	s.restart()
	await tree.physics_frame
	var seed1: int = c.map_seed
	var qs1: Vector3 = c.page_spots.quick_step
	s.restart()
	await tree.physics_frame
	check.call(c.map_seed != seed1 and c.page_spots.quick_step != qs1 and c.page_pickups.quick_step.position.distance_to(c.page_spots.quick_step + Vector3(0, 0.6, 0)) < 0.01, "every run draws a new seed: new trees, page spots and zones; the pickups move with them")
	var trunks: MultiMeshInstance3D = c.find_child("Trunks", true, false)
	check.call(trunks != null and trunks.multimesh.instance_count == c.map.trees.size() and c.find_children("Scatter", "", true, false).size() == 1, "the run's trees are one MultiMesh; the old map is gone")
	# The real navigation grid agrees with the rules: every page and zone walkable from the camp.
	var unreachable := []
	for id in c.page_spots:
		if not c.nav.find_path(c.spawn.at, c.page_spots[id]).ok: unreachable.append(id)
	for z in c.zones:
		if not c.nav.find_path(c.spawn.at, z.at).ok: unreachable.append(z.id)
	check.call(unreachable.is_empty() and c.zones.size() == 6 and c.page_spots.size() == 3, "on the built map, all 3 pages and 6 spawn zones are walkable from the camp %s" % str(unreachable))
	var tops := []
	for l in c.map.ledges: tops.append(l[4])
	check.call(1.0 in tops and 2.0 in tops and 3.0 in tops and c.map.rocks.size() >= 6, "rocks for cover and 1 / 2 / 3 m ledges for mantle tech")

	# ---- Phase 3: Binbun grass, rock ledges, night sky -----------------------------------
	var gf: Node3D = c.find_child("GrassField", true, false)
	var gok := gf != null
	var near_path := 0
	var near_fire := 0
	var blades := 0
	if gok:
		gf.focus_fn = func() -> Vector3: return c.spawn.at
		for i in 40: gf.update(8)
		blades = gf.blade_count()
		for key in gf.chunks:
			var mm: MultiMesh = gf.chunks[key].multimesh
			for i in range(0, mm.instance_count, 7):
				var o: Vector3 = mm.get_instance_transform(i).origin
				var q := Vector2(o.x, o.z)
				if Forest.centreline_dist(q) < gf.PATH_CLEAR - 0.01: near_path += 1
				if q.distance_to(Vector2(Forest.CAMPFIRE.x, Forest.CAMPFIRE.z)) < gf.FIRE_CLEAR - 0.01: near_fire += 1
		var k0: Vector2i = gf.chunks.keys()[0]
		var again: MultiMeshInstance3D = gf._build(k0)
		gok = gok and again.multimesh.buffer == gf.chunks[k0].multimesh.buffer
		again.free()
		gf.focus_fn = Callable()
	check.call(gok and blades > 8000 and near_path == 0 and near_fire == 0, "Binbun grass round the player (%d blades), none on the paths or by the fire, the same blades every time [Phase 3]" % blades)
	var fade_ok: bool = gok and is_equal_approx(float(gf.material.get_shader_parameter("fade_end")), gf.fade_end) and String(gf.material.shader.resource_path).ends_with("grass_fade.gdshader")
	check.call(fade_ok and c.find_children("GroundCover", "", true, false).is_empty(), "grass grows in by distance (fades out by %.0f m), no Nature-kit ground cover" % (gf.fade_end if gf else 0.0))
	var ledge_bad := []
	for i in c.map.ledges.size():
		var lg: Array = c.map.ledges[i]
		var rock: MeshInstance3D = c.find_child("kit_ledge_%d" % i, true, false)
		var lbox: Node3D = c.find_child("ledge_%d" % i, true, false)
		if rock == null or lbox == null: ledge_bad.append("ledge %d missing" % i); continue
		var top: float = (rock.global_transform * rock.mesh.get_aabb()).end.y
		var shown := lbox.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.visible).size()
		var col := lbox.find_children("*", "CollisionShape3D", true, false).size()
		if absf(top - float(lg[4])) > 0.06 or shown > 0 or col == 0: ledge_bad.append("ledge %d top %.2f/%.1f shown %d col %d" % [i, top, lg[4], shown, col])
	check.call(ledge_bad.is_empty(), "every mantle ledge is a kit rock at its exact height; the box collider stays, unseen %s" % str(ledge_bad))
	var env0: Environment = (c.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var sky_ok: bool = env0.background_mode == Environment.BG_SKY and env0.sky and String((env0.sky.sky_material as ShaderMaterial).shader.resource_path).contains("BinbunSky") and float((env0.sky.sky_material as ShaderMaterial).get_shader_parameter("day_night_mix")) < 0.0
	var floor_m: MeshInstance3D = c.find_child("floor", true, false).find_children("*", "MeshInstance3D", true, false)[0]
	check.call(sky_ok and floor_m.material_override is ShaderMaterial and String(floor_m.material_override.shader.resource_path).ends_with("ground_lit.gdshader"), "Binbun night sky overhead; the floor wears the grass's ground colour")

	# ---- trees: no clipping, no low-poly snap [Sir, 2026-11-13] ------------------------
	var thin := []
	var cols: Node3D = c.find_child("TreeColliders", true, false)
	for ti in range(0, c.map.trees.size(), 17):
		var look: Dictionary = Forest.tree_look(c.map.trees[ti], ti, c.map_seed)
		var shape: CylinderShape3D = (cols.get_child(ti).get_child(0) as CollisionShape3D).shape
		if shape.radius + 0.3 < float(look.trunk) - 0.05 or float(look.trunk) > Forest.TRUNK_MAX + 1e-4: thin.append("tree %d trunk %.2f collider %.2f" % [ti, look.trunk, shape.radius])
	check.call(thin.is_empty(), "every tree's collider covers its drawn trunk (trunks capped at %.2f m) %s" % [Forest.TRUNK_MAX, str(thin.slice(0, 3))])
	var near_inst: GeometryInstance3D = c.find_child("KitTrees", true, false).get_child(0).get_child(0)
	check.call(Forest.NEAR_END >= 40.0 and is_equal_approx(near_inst.visibility_range_end, Forest.NEAR_END) and near_inst.visibility_range_end_margin >= 8.0, "real trees out to %.0f m, an %.0f m cross-fade to the impostors" % [Forest.NEAR_END, Forest.NEAR_FADE])
	# Grass distance is a setting, applied live.
	var gset: RefCounted = s.settings
	var gd0: float = gset.grass_distance
	gset.set_value("grass_distance", 90.0)
	var gf2: Node3D = c.find_child("GrassField", true, false)
	var far_ok: bool = gf2 != null and is_equal_approx(gf2.fade_end, 90.0) and is_equal_approx(float(gf2.material.get_shader_parameter("fade_end")), 90.0)
	gset.set_value("grass_distance", 500.0)
	var capped: bool = is_equal_approx(gset.grass_distance, 120.0)
	gset.set_value("grass_distance", gd0)
	check.call(far_ok and capped and is_equal_approx(gf2.fade_end, gd0), "Settings > Grass distance sets how far grass grows (90 m here; 20-120 m)")

	# ---- Phase 4: the camp and the pages from the Fantasy Props kit ----------------------
	var camp: Node3D = c.find_child("Camp", true, false)
	var benches: int = camp.find_children("bench_*", "", false, false).size()
	var logs_ok := true
	for i in 3:
		var lb: Node3D = camp.get_node_or_null("log_%d" % i)
		logs_ok = logs_ok and lb != null and lb.find_children("*", "CollisionShape3D", true, false).size() > 0 and lb.find_children("*", "MeshInstance3D", true, false).is_empty()
	var flames: Node3D = camp.get_node_or_null("CampFlames")
	var stones: int = camp.find_children("fire_stone_*", "", false, false).size()
	var supplies: int = camp.find_children("camp_*", "", false, false).filter(func(n): return not String(n.name).ends_with("_col")).size()
	check.call(benches == 3 and logs_ok and flames != null and flames.visible and camp.find_child("Embers", false, false) == null and stones == 9 and supplies >= 6, "the camp: 3 benches on the old log colliders, a Binbun fire in a ring of %d stones, %d props, no cone or boxes [Phase 4]" % [stones, supplies])
	var walk_out: bool = c.nav.find_path(c.spawn.at, c.spawn.at + Vector3(0, 0, -20)).ok
	var scrolls := 0
	for id in c.page_pickups:
		var pk: Node3D = c.page_pickups[id]
		var leaf: MeshInstance3D = pk.get_node_or_null("Leaf")
		if pk.has_node("Scroll") and leaf != null and not leaf.visible: scrolls += 1
	check.call(walk_out and scrolls == c.page_pickups.size(), "the walk out of camp stays clear; every lost page is a scroll (%d of %d)" % [scrolls, c.page_pickups.size()])

	# ---- the fixed part: camp, light, grade ---------------------------------------------
	var fire: OmniLight3D = c.find_child("CampFire", true, false)
	var env: Environment = (c.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var moon: DirectionalLight3D = c.find_child("Moon", true, false)
	check.call(fire != null and fire.light_color.r > fire.light_color.b * 2.0 and not fire.shadow_enabled and fire in c.lamps, "a lit, warm campfire at the camp (no shadow: perf trim 2)")
	check.call(moon != null and moon.light_color.b > moon.light_color.r and moon.light_energy < 0.5 and env.fog_enabled and env.fog_density >= 0.02 and env.background_color.v < 0.1, "cold moonlight, night sky and fog")
	check.call(Forest.SIZE == Vector2(150, 150) and Forest.CLEARINGS.size() >= 6 and Forest.PATHS.size() >= Forest.CLEARINGS.size() - 1, "150 x 150 m: %d clearings joined by %d paths" % [Forest.CLEARINGS.size(), Forest.PATHS.size()])
	check.call(flat(c.spawn.at).distance_to(flat(Forest.CAMPFIRE)) < 8.0 and Forest.clearing_at(c.spawn.at) == 0 and p.global_position.distance_to(c.spawn.at) < 0.05, "the player starts at the camp")
	# Trees block sight (aggro and blast line of sight use the same layer).
	var t: Array = c.map.trees[c.map.trees.size() / 2]
	var tp := Vector3(t[0], 1.6, t[1])
	check.call(not c.clear_line(tp + Vector3(-3, 0, 0), tp + Vector3(3, 0, 0)) and c.clear_line(c.spawn.at + Vector3(0, 1.6, 0), c.spawn.at + Vector3(0, 1.6, -8)), "a trunk blocks sight; the open camp does not")
	# A quiet start: six Sprites roam their zones, nobody is in combat.
	for i in 120: s.step(DT)
	check.call(c.alive_count() >= 6 and not c.director.in_combat and not p.health.dead and p.is_on_floor(), "2 s in: %d Sprites roam, the camp is quiet, the player stands on the ground" % c.alive_count())
	# The boundary: running at the west edge stops at it.
	p.global_position = Vector3(3, 0, 80)
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(90.0) # facing west (-X)
	p.apply_look()
	c.park_enemies()
	var keys := {KEY_W: true}
	var saved: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	for i in 120: s.step(DT)
	s.input.key_source = saved
	check.call(p.global_position.x > 0.0 and p.global_position.x < 6.0, "the forest edge holds the player in (x %.2f)" % p.global_position.x)
	# A death returns the player to the camp with full HP and MP, in a new forest.
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var seed_alive: int = c.map_seed
	p.global_position = Vector3(75, 0, 95)
	p.health.apply(DamagePacket.new(96001, "test", "infected", 500.0, "bite"), s.run.time)
	check.call(p.health.dead and c.death_panel.visible and c.death_panel.button.text == "Return to camp", "death: the panel offers 'Return to camp'")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(not p.health.dead and p.global_position.distance_to(c.spawn.at) < 0.05 and is_equal_approx(p.health.hp, p.health.max_hp) and is_equal_approx(c.pcombat.mp, c.pcombat.max_mp()) and c.map_seed != seed_alive, "back at the camp with full HP and MP, in a new forest [R5, R11]")
	# Dying with the Grimoire open and burning: the panel closes, nothing carries over.
	c.park_enemies()
	s.handle_action("grimoire")
	var was_open: bool = c.grimoire_panel.visible
	c.effects.apply("player", "Burn", 5.0, s.run.time, "test", 100.0)
	c.player.health.apply(DamagePacket.new(96002, "test", "infected", 9999.0, "bite"), s.run.time)
	var closed: bool = not c.grimoire_panel.visible and c.death_panel.visible and s.input.context == s.input.Context.DEATH
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	c.publish(DT)
	check.call(was_open and closed and c.effects.active.is_empty() and c.hud.status_ids().is_empty() and s.input.context == s.input.Context.GAMEPLAY and not c.banner.showing(), "death with the Grimoire open and Burn on: the panel closes; after the respawn no effect, icon or banner carries over")
	s.meta.reset()
	s.restart()
	await tree.physics_frame
