extends RefCounted
# The Training Field [Sir, 2026-11-14]: a separate 200 x 200 m daytime field with
# no trees, reached only by the player through the portal beside the camp, sealed
# in combat; undying dummies that take no damage but show it; target boards at
# 10-80 m; rock formations and the movement drills; back to the forest at night.

const DT := 1.0 / 60.0
const TF = preload("res://scripts/world/training_field.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var t: Node3D = c.training
	var p: CharacterBody3D = c.player
	check.call(t != null and not t.active and not t.field.visible, "the Training Field exists, hidden while the player is in the forest")
	var f: Node3D = t.field
	var trees := f.find_children("*", "MultiMeshInstance3D", true, false).size() + f.find_children("Trunks", "", true, false).size()
	var ground: Node3D = f.get_node("ground")
	var gsize: Vector3 = ((ground.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
	check.call(trees == 0 and gsize.x >= 200.0 and gsize.z >= 200.0 and TF.ORIGIN.x - 150.0 > 500.0, "a 200 x 200 m field, no trees, far from the forest")
	check.call(t.dummies.size() >= 15 and t.boards.size() == 15 and t.ROCKS.size() >= 15 and f.find_child("slide_gap_0", true, false) != null and f.find_child("drop_tower", true, false) != null, "%d dummies, 15 target boards (10/20/30/50/80 m), %d rocks and the movement drills" % [t.dummies.size(), t.ROCKS.size()])

	# An enemy at the portal is never taken through; only the player is.
	var foe: CharacterBody3D = c.enemies.values()[0]
	foe.reset_to(TF.FOREST_PORTAL, 0.0)
	foe.inert = true
	steps(c, 0.2)
	check.call(not t.active and foe.global_position.distance_to(TF.FOREST_PORTAL) < 0.5, "an enemy standing in the portal stays in the forest")
	c.park_enemies()
	# Sealed in combat.
	var sh: CharacterBody3D = c.enemies.values()[1]
	sh.reset_to(c.spawn.at + Vector3(0, 0, -30), 0.0)
	sh.aggroed = true
	steps(c, 0.1)
	p.global_position = TF.FOREST_PORTAL
	p.velocity = Vector3.ZERO
	var r_locked: String = t.check_portals(s.run.time)
	var tint: Color = t.forest_portal.get_node("Portal").primary_color
	check.call(c.director.in_combat and r_locked == "locked" and not t.active and tint == TF.LOCKED_COLOR, "in combat the portal is sealed (red): the player stays in the forest")
	c.park_enemies()
	sh.aggroed = false
	p.global_position = c.spawn.at # step away while combat ends
	steps(c, 4.0) # out of combat after the grace
	# Through: day, the forest hidden.
	var env: Environment = (c.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	var night_fog: float = env.fog_density
	p.global_position = TF.FOREST_PORTAL
	p.velocity = Vector3.ZERO
	steps(c, 2.0 * DT)
	var sky: ShaderMaterial = env.sky.sky_material if env.sky else null
	var day: bool = t.sun.visible and not c.find_child("Moon", true, false).visible and env.fog_density < night_fog and (sky == null or float(sky.get_shader_parameter("day_night_mix")) > 0.5)
	check.call(t.active and p.global_position.distance_to(TF.ORIGIN + TF.ARRIVE) < 1.0 and t.field.visible and not c._forest_node.visible and day, "walking into the portal: the player arrives in the field, in daylight (sun on, moon off, light fog); the forest is hidden %s" % str([t.active, p.global_position, t.field.visible, c._forest_node.visible, t.sun.visible, c.find_child("Moon", true, false).visible, env.fog_density, night_fog, sky.get_shader_parameter("day_night_mix") if sky else null]))

	# Dummies: hits show, no damage, never die; Burn ticks too. Records are untouched.
	var d: Dictionary = t.dummies[0]
	var best0: float = float(s.meta.records.best_hit)
	var n0: int = c.damage_numbers.spawned
	var hp0: float = d.health.hp
	var tg: Array = c.combat_targets().filter(func(x): return x.id == d.id)
	d.health.apply(DamagePacket.new(990101, "player", "player", 123.0, "blast"), s.run.time)
	d.health.apply(DamagePacket.new(990102, "player", "player", 1.0e9, "blast"), s.run.time)
	c.effects.apply(d.id, "Burn", 2.0, s.run.time, "player", 100.0)
	steps(c, 1.2)
	check.call(not tg.is_empty() and not d.health.dead and is_equal_approx(d.health.hp, hp0) and c.damage_numbers.spawned >= n0 + 3 and d.total >= 1.0e9 + 123.0 and d.label.text != "", "a dummy hit for 123 and 1e9, then burning: every number shows, its total counts, and it takes no damage and never dies")
	check.call(is_equal_approx(float(s.meta.records.best_hit), best0), "training hits do not count toward the records")
	# A real fireball at a dummy from the arrival pad.
	var near: Dictionary = t.dummies[16] # [85, 175]
	p.global_position = TF.ORIGIN + Vector3(85, 0, 182)
	p.yaw = 0.0
	p.pitch = deg_to_rad(-4.0)
	p.apply_look()
	var h0: int = near.hits
	c.pcombat.cast_basic(s.run.time)
	steps(c, 1.0)
	check.call(near.hits > h0, "a cast basic fireball hits a dummy (%d hits)" % near.hits)
	steps(c, 5.0 + TF.TOTAL_RESET_S + 0.5) # its Burn (5 s) ends, then the total clears
	check.call(near.total == 0.0 and near.label.text == "", "a dummy's running total clears %d s after its last hit %s" % [int(TF.TOTAL_RESET_S), str([near.total, near.label.text, t.active])])
	# The AoE cluster [Sir, 2026-11-14]: 13 dummies packed 2 m apart; blasts catch many at once.
	var cl: Array = t.dummies.filter(func(x): return x.get("cluster", false))
	var min_gap := INF
	var max_r := 0.0
	for i in cl.size():
		max_r = maxf(max_r, Vector2(cl[i].base.x - TF.CLUSTER_AT.x, cl[i].base.z - TF.CLUSTER_AT.z).length())
		for j in range(i + 1, cl.size()): min_gap = minf(min_gap, (cl[i].base as Vector3).distance_to(cl[j].base))
	check.call(cl.size() == 13 and min_gap > 1.9 and max_r < 4.1, "the AoE cluster: %d dummies, %.1f m apart at least, all within %.1f m of its centre" % [cl.size(), min_gap, max_r])
	var centre: Vector3 = TF.ORIGIN + TF.CLUSTER_AT
	var hits0: Array = cl.map(func(x): return int(x.hits))
	c.gambler.tails_blast(centre + Vector3(0, 0.5, 0), 10.0, 100.0, s.run.time)
	var caught_t: int = 0
	for i in cl.size(): if int(cl[i].hits) > int(hits0[i]): caught_t += 1
	hits0 = cl.map(func(x): return int(x.hits))
	c.projectiles.launch("basic", centre + Vector3(0, 6, 0.1), Vector3(0, -1, 0), {"damage": 5.0, "pow": 100.0, "target_point": centre + Vector3(0, 0.5, 0)})
	steps(c, 1.0)
	var caught_b: int = 0
	for i in cl.size(): if int(cl[i].hits) > int(hits0[i]): caught_b += 1
	check.call(caught_t == 13 and caught_b >= 7 and caught_b < 13, "AoE on the cluster: Tails' 20 m burst catches all %d; a basic fireball's 3.5 m blast at the centre catches %d" % [caught_t, caught_b])
	# Boards: a hit flashes and counts.
	var b: Dictionary = t.boards[0]
	b.health.apply(DamagePacket.new(990103, "player", "player", 10.0, "blast"), s.run.time)
	check.call(b.hits == 1 and b.flash > 0.5 and not b.health.dead, "a target board hit flashes and counts")
	var dists := {}
	for bb in t.boards: dists[bb.dist] = true
	check.call(dists.keys().size() == 5 and t.boards.all(func(bb): return absf((TF.RANGE_LINE_Z - (bb.body.position.z)) - float(bb.dist)) < 0.01), "boards stand at 10, 20, 30, 50 and 80 m from the firing line")
	# Strafing dummies move.
	var mover: Dictionary = t.dummies.filter(func(x): return float(x.strafe) > 0.0)[0]
	var xs := [] # sampled over 2 s: a single 0.5 s window can straddle a turning point
	for k in 8:
		steps(c, 0.25)
		xs.append(float(mover.body.position.x))
	check.call(xs.max() - xs.min() > 0.5, "strafing dummies move side to side (%.1f m)" % (xs.max() - xs.min()))
	# Back through the return portal: the forest at night.
	p.global_position = TF.ORIGIN + TF.RETURN_PORTAL
	p.velocity = Vector3.ZERO
	steps(c, 2.0 * DT)
	check.call(not t.active and p.global_position.distance_to(TF.FOREST_ARRIVE) < 1.0 and c._forest_node.visible and not t.field.visible and not t.sun.visible and c.find_child("Moon", true, false).visible and is_equal_approx(env.fog_density, night_fog), "the return portal: back beside the camp, at night (moon, fog), the field hidden")
	# A restart in the field returns to the camp at night.
	steps(c, 1.2)
	p.global_position = TF.FOREST_PORTAL
	steps(c, 2.0 * DT)
	var was_in: bool = t.active
	s.restart()
	await tree.physics_frame
	check.call(was_in and not t.active and p.global_position.distance_to(c.spawn.at) < 0.1 and c.find_child("Moon", true, false).visible and is_equal_approx(env.fog_density, night_fog), "a restart from the field: back at the camp, at night")
	s.meta.reset()
	s.restart()
	await tree.physics_frame
