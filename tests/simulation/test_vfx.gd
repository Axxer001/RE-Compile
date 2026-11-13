extends RefCounted
# MVP close-out VFX (handoff P2/P4): fireball trails, blast bursts and fading
# scorch marks, a larger special blast, Quick Step's flash at both ends,
# Cultivate's hand embers, Ring of Fire's glowing orbs. Everything is pooled:
# after the pools fill, more shots and blasts add no nodes.

const DT := 1.0 / 60.0

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func nodes_under(n: Node) -> int:
	return n.get_child_count() + n.get_children().reduce(func(a, ch): return a + nodes_under(ch), 0)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var vfx: Node3D = c.vfx
	var ps: RefCounted = c.projectiles
	check.call(vfx != null and ps.vfx == vfx and vfx.pooled_nodes() == vfx.BURST_POOL * 2 + 4 + vfx.DECAL_POOL + vfx.FLASH_POOL + vfx.BINBUN_POOL.values().reduce(func(x, y): return x + y, 0) and vfx.binbun_ready("special") and vfx.binbun_ready("step"), "the VFX pools are built up front, BinbunVFX scenes included (%d nodes)" % vfx.pooled_nodes())

	# Binbun effects play once [Sir's bug, 2026-11-13]: no looping animation, and
	# each hides itself when it finishes (the demo scenes replayed forever).
	var looping := []
	for kind in vfx._bb:
		for fx in vfx._bb[kind]:
			if "one_shot" in fx and not fx.one_shot: looping.append("%s one_shot" % kind)
			for ap in fx.find_children("*", "AnimationPlayer", true, false):
				for an in ap.get_animation_list():
					if ap.get_animation(an).loop_mode != Animation.LOOP_NONE: looping.append("%s %s" % [kind, an])
	var sfx_node: Node3D = vfx._bb.special[0]
	vfx._play_burst("special", Vector3(60, 1, 50))
	var shown: bool = sfx_node.visible
	sfx_node.finished.emit()
	check.call(looping.is_empty() and shown and not sfx_node.visible, "Binbun blasts play once and hide when they finish %s" % str(looping))
	vfx.reset()

	# Blasts: a burst and a scorch each; the special's is bigger; scorches fade.
	var b0: int = vfx.counts.bursts
	var d0: int = vfx.counts.decals
	ps._burst(Vector3(60, 1, 50), "basic", s.run.time)
	var small: float = vfx._decals[(vfx._next_decal - 1) % vfx.DECAL_POOL][2]
	ps._burst(Vector3(62, 1, 50), "special", s.run.time)
	var big: float = vfx._decals[(vfx._next_decal - 1) % vfx.DECAL_POOL][2]
	var sb: GPUParticles3D = vfx._bursts.special[0]
	var bb: GPUParticles3D = vfx._bursts.basic[0]
	check.call(vfx.counts.bursts == b0 + 2 and vfx.counts.decals == d0 + 2 and big > small and sb.amount > bb.amount and sb.amount <= 12 and bb.amount <= 6, "a blast: a particle burst and a scorch; the special's is bigger (scorch %.1f vs %.1f m, %d vs %d particles)" % [big, small, sb.amount, bb.amount])
	var live0: int = vfx.live_decals()
	steps(c, vfx.SCORCH_S + 0.2)
	check.call(live0 >= 2 and vfx.live_decals() == 0, "scorch marks fade out after %.0f s" % vfx.SCORCH_S)

	# Pooled: after a warm-up pass, another 100 blasts and 200 fireballs at play pace add no nodes.
	var clock: Array = [s.run.time] # a lambda captures locals by value: the clock lives in an array
	var pass_fn := func() -> void:
		for i in 100:
			clock[0] += 0.2 # a blast every 0.2 s: each light flash ends before long
			ps._burst(Vector3(60 + i % 5, 1, 50), "basic" if i % 3 else "special", clock[0])
			ps.tick(0.0, clock[0], {"targets": []})
			vfx.tick(clock[0])
		for i in 200:
			ps.launch("basic", Vector3(60, 1, 50), Vector3(0, 0, -1), {"damage": 0.0})
			if i % 4 == 3: ps.reset()
		ps.reset()
	pass_fn.call()
	await tree.process_frame
	var before: int = nodes_under(vfx) + nodes_under(ps.root)
	pass_fn.call()
	await tree.process_frame
	var after: int = nodes_under(vfx) + nodes_under(ps.root)
	check.call(after == before and vfx.live_decals() <= vfx.DECAL_POOL, "pooled: another 100 blasts and 200 fireballs add no nodes (%d -> %d)" % [before, after])

	# Trails: one per pooled fireball visual, never a second on reuse.
	var shot: Dictionary = ps.launch("basic", Vector3(60, 1, 50), Vector3(1, 0, 0), {"damage": 0.0})
	var trails: int = shot.node.find_children("BinbunCore", "", false, false).size()
	var core: Node3D = shot.node.get_node_or_null("BinbunCore")
	var lite: bool = core != null and vfx.LITE_STRIP.all(func(nm): return core.get_node_or_null(nm) == null) and core.find_children("*", "Light3D", true, false).is_empty()
	var sphere_hidden: bool = shot.node.get_children().filter(func(ch): return ch is MeshInstance3D and ch.visible).is_empty()
	ps.reset()
	var again: Dictionary = ps.launch("basic", Vector3(60, 1, 50), Vector3(1, 0, 0), {"damage": 0.0})
	ps.tick(DT, s.run.time, {"targets": []})
	var fwd: Vector3 = -again.node.global_transform.basis.z
	check.call(trails == 1 and again.node.find_children("BinbunCore", "", false, false).size() == 1 and not again.node.has_node("Trail") and fwd.dot(Vector3(1, 0, 0)) > 0.99, "each fireball is one Binbun fire projectile, kept with its pooled visual, facing its flight")
	check.call(lite and sphere_hidden, "a basic fireball wears the lite projectile (no sparks, no own light); the old sphere is hidden [Phase 2]")
	var sp: Dictionary = ps.launch("special", Vector3(60, 1, 50), Vector3(1, 0, 0), {"damage": 0.0})
	var sp_core: Node3D = sp.node.get_node_or_null("BinbunCore")
	var ball: bool = sp_core != null and sp_core.scene_file_path == vfx.SPECIAL_PROJECTILE and core.scene_file_path == vfx.BASIC_PROJECTILE
	var bigger: bool = sp_core != null and sp_core.scale.x > core.scale.x * 1.4
	ps.reset()
	check.call(ball and bigger, "fireballs are DarkMagicFX: the basic the evil projectile, the special the evil ball, %.1fx its size [Sir, 2026-11-13]" % (sp_core.scale.x / core.scale.x if sp_core else 0.0))
	# Not sideways: the projectile's own flight axis (+X) points where the shot flies.
	var aim := Vector3(0.6, 0.0, -0.8).normalized()
	var fly: Dictionary = ps.launch("basic", Vector3(60, 1, 50), aim, {"damage": 0.0})
	ps.tick(DT, s.run.time, {"targets": []})
	var axis: Vector3 = fly.node.get_node("BinbunCore").global_transform.basis.x.normalized()
	ps.reset()
	check.call(axis.dot(aim) > 0.99, "a fireball flies nose first, not sideways (axis . aim = %.2f)" % axis.dot(aim))
	# Blasts: a different explosion per attack, each the size of its damage radius.
	var bb_b: Node3D = vfx._bb.basic[0]
	var bb_s: Node3D = vfx._bb.special[0]
	var r_b: float = bb_b.scale.x * vfx.BLAST_NATIVE_R.basic
	var r_s: float = bb_s.scale.x * vfx.BLAST_NATIVE_R.special
	check.call(bb_b.scene_file_path != bb_s.scene_file_path and bb_b.scene_file_path.contains("ExplosionFX") and bb_s.scene_file_path.contains("ExplosionFX") and is_equal_approx(r_b, ps.KINDS.basic.aoe) and is_equal_approx(r_s, ps.KINDS.special.aoe), "ExplosionFX blasts: air for the basic (%.1f m), nuke for the special (%.1f m), each its damage radius" % [r_b, r_s])
	ps.reset()

	# Quick Step: a flash at both ends.
	var pc: Node3D = c.pcombat
	c.player.global_position = Vector3(60, 0, 40)
	await tree.physics_frame
	var f0: int = vfx.counts.flashes
	var sb0: int = vfx.counts.bursts
	pc.quick_step(Vector2.ZERO)
	var lit: int = vfx._flashes.filter(func(f): return f[0].visible).size()
	check.call(vfx.counts.flashes == f0 + 2 and vfx.counts.bursts == sb0 + 2 and lit == 2, "Quick Step flashes at its start and its end")
	steps(c, 0.3)
	check.call(vfx._flashes.all(func(f): return not f[0].visible), "the flashes end after 0.15 s")

	# Cultivate: embers on the hands while it lasts.
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, s.run.time)
	c.publish(DT)
	var on: bool = pc.aura_embers != null and vfx.loop_on(pc.aura_embers) and pc.aura_embers.name == "Loop_cultivate"
	pc.cultivate_until = s.run.time
	c.publish(DT)
	check.call(on and not vfx.loop_on(pc.aura_embers) and pc.aura_embers.scene_file_path.contains("StatusFX") and pc.aura_embers.get_node_or_null("MeshInstance3D") == null and pc.aura_embers.find_children("*", "GPUParticles3D", true, false).all(func(g): return g.amount <= 12), "Cultivate wears StatusFX's aura (cyan) on the hands while it lasts: soft motes only, no screen-filling streaks")
	# Sage Arts rests at full HP and MP, restores (green aura on) when either is down.
	var sage_pg: Resource = s.grimoire.page("sage_arts")
	var had: Resource = pc.loadout.get("passive")
	var rank_was: String = s.progression.rank
	s.progression.rank = "D"
	pc.loadout.passive = sage_pg
	var h: Node = c.player.health
	h.hp = h.max_hp
	pc.mp = pc.max_mp(s.run.time)
	c.park_enemies()
	steps(c, 0.1)
	var rests: bool = not pc.sage_active(s.run.time) and not vfx.loop_on(pc.sage_fx) and not c.player_statuses(s.run.time).any(func(x): return x.id == "Sage Arts")
	h.hp = h.max_hp * 0.5
	steps(c, 0.1)
	var works: bool = pc.sage_active(s.run.time) and vfx.loop_on(pc.sage_fx) and h.hp > h.max_hp * 0.5 and c.player_statuses(s.run.time).any(func(x): return x.id == "Sage Arts")
	pc.loadout.passive = had
	s.progression.rank = rank_was
	h.hp = h.max_hp
	steps(c, 0.05)
	check.call(rests and works and pc.sage_fx.scene_file_path.contains("StatusFX"), "Sage Arts rests at full HP and MP (no aura, no icon) and restores with StatusFX's green aura when hurt [Sir, 2026-11-13]")

	# Ring of Fire: glowing orbs from the pool, back to it when the ring ends.
	var ring: Dictionary = ps.summon_ring(func() -> Vector3: return c.player.global_position, s.run.time, 0.5, 0.0)
	var glow: bool = ring.nodes.all(func(n): return is_equal_approx(n.find_children("*", "OmniLight3D", false, false)[0].light_energy, ps.ORB_GLOW))
	var with_trail: bool = ring.nodes.all(func(n): return n.has_node("BinbunOrb") and n.get_node("BinbunOrb").visible and not n.get_node("BinbunCore").visible and not n.has_node("Trail")) # each orb a small evil fire ball
	var pooled_before: int = ps._free_nodes.basic.size()
	steps(c, 0.7)
	check.call(glow and with_trail and ps.rings.is_empty() and ps._free_nodes.basic.size() >= pooled_before + int(ps.ORBIT.count), "Ring of Fire's orbs glow brighter, trail, and go back to the pool when it ends (glow %s trail %s ended %s pool %d -> %d)" % [glow, with_trail, ps.rings.is_empty(), pooled_before, ps._free_nodes.basic.size()])

	# Scorched Slow: a Binbun fire area at a Sprite's feet while it lasts.
	var sl: CharacterBody3D = c.enemies.values()[0]
	sl.set_statuses([{"id": "Scorched Slow"}])
	var slow_on: bool = vfx.loop_on(sl.slow_fx)
	sl.set_statuses([])
	check.call(slow_on and not vfx.loop_on(sl.slow_fx), "Scorched Slow shows a Binbun fire area under the Sprite, gone when it ends [Phase 2]")

	# Small blasts are Binbun impacts too (pooled, own lights off).
	var bb_basic: bool = vfx.binbun_ready("basic") and vfx._bb.basic.all(func(fx): return fx.find_children("*", "Light3D", true, false).all(func(l): return not l.visible))
	check.call(bb_basic, "basic blasts are Binbun impacts from a pool of %d, their own lights off" % vfx.BINBUN_POOL.basic)

	# Perf option A: only the 8 shots nearest the camera carry a light; ring orbs always do.
	ps.reset()
	var eye: Vector3 = c.player.camera.global_position
	for i in 20: ps.launch("basic", eye + Vector3(0, 0, -3.0 - 2.0 * i), Vector3(1, 0, 0), {"damage": 0.0})
	ps.tick(DT, s.run.time, {"targets": []})
	var lit_ids: Array = ps.lit_shots().map(func(sh): return sh.id)
	var by_dist: Array = ps.shots.duplicate()
	by_dist.sort_custom(func(a, b): return eye.distance_squared_to(a.pos) < eye.distance_squared_to(b.pos))
	var nearest: Array = by_dist.slice(0, ps.LIT_MAX).map(func(sh): return sh.id)
	lit_ids.sort(); nearest.sort()
	var orbs: Dictionary = ps.summon_ring(func() -> Vector3: return c.player.global_position, s.run.time, 5.0, 0.0)
	ps.tick(DT, s.run.time, {"targets": []})
	var orbs_lit: bool = orbs.nodes.all(func(n): return n.find_children("*", "OmniLight3D", false, false)[0].visible)
	check.call(ps.shots.size() == 20 and lit_ids == nearest and orbs_lit and ps.lit_shots().size() == ps.LIT_MAX, "of 20 fireballs only the %d nearest the camera are lit; Ring of Fire's orbs stay lit [perf A]" % ps.LIT_MAX)
	ps.reset()
	s.restart()
	await tree.physics_frame
