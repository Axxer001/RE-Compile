extends SceneTree
const Packet = preload("res://scripts/combat/damage_packet.gd")
var failures := []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = true
	c.world_kind = "arena"
	root.add_child(c)
	await physics_frame
	await physics_frame
	c.park_enemies()
	var s = c.session
	var gp = c.grimoire_panel
	var serial := 880000
	for foe_kind in ["sprite", "ghoul", "mortus"]:
		var foes: Array = c.enemies.values().filter(func(e): return e.kind == foe_kind)
		check(not foes.is_empty(), "roster contains " + foe_kind)
		if foes.is_empty(): continue
		for mode in ["browse", "player_id", "assembly", "chant"]:
			s.restart()
			c.park_enemies()
			s.grimoire.find("quick_step")
			s.handle_action("grimoire")
			if mode == "player_id": gp.show_tab("player_id")
			elif mode == "assembly": gp.start_assembly("quick_step")
			elif mode == "chant": gp.start_chant("magic_pow")
			var unlocked: Array = s.meta.unlocked.duplicate()
			var points: Dictionary = s.stats.chant_points.duplicate()
			serial += 1
			var result: String = c.player.health.apply(Packet.new(serial, foes[0].enemy_id, "infected", 5.0, "bullet" if foe_kind == "ghoul" else "melee"), s.run.time)
			check(result == "applied" and not gp.visible and s.input.context == s.InputRouter.Context.GAMEPLAY, foe_kind + " damage closes " + mode)
			check(gp.attempt.is_empty() and gp.problem.is_empty() and s.meta.unlocked == unlocked and s.stats.chant_points == points, "interruption clears attempt without rewards: " + foe_kind + "/" + mode)
			if gp.visible: s.handle_action("grimoire")
			s.handle_action("grimoire")
			check(gp.visible and gp.mode == "browse" and gp.attempt.is_empty() and gp.problem.is_empty(), "Tab reopens cleanly: " + foe_kind + "/" + mode)
			s.handle_action("grimoire")
	# Exercise actual melee, projectile and charge emitters as well as the mode matrix.
	var row := 0.0
	for z in [76.0,74.0,56.0,54.0,48.0,44.0,36.0,34.0,20.0,16.0,6.0,4.0]:
		if c.clear_line(Vector3(4,1.6,z),Vector3(56,1.6,z)):
			row = z
			break
	check(row > 0.0, "open lane for real hostile attacks")
	for kind in ["sprite", "ghoul", "mortus"]:
		s.restart()
		c.park_enemies()
		var foe = c.enemies.values().filter(func(e): return e.kind == kind)[0]
		foe.reset_to(Vector3(6,0,row),-90.0)
		c.player.position = Vector3(12 if kind == "ghoul" else 7,0,row)
		c.player.velocity = Vector3.ZERO
		await physics_frame
		s.grimoire.find("quick_step")
		s.handle_action("grimoire")
		gp.start_assembly("quick_step")
		var hp: float = c.player.health.hp
		if kind == "sprite": foe._strike(c.player,c.player.health,0.0,c.clear_line)
		elif kind == "ghoul":
			foe._shoot(c.player,0.0)
			for i in 180:
				c.arrows.tick(1.0/60.0,i/60.0,{"player":c.player,"player_health":c.player.health,"ray":c.world_ray})
				if c.player.health.hp < hp: break
		else:
			foe._go(foe.State.CHARGE)
			foe.timer = 2.0
			var ctx := {"player":c.player,"player_health":c.player.health,"los":c.clear_line}
			foe.think(1.0/60.0,2.0,ctx)
			foe.think(1.0/60.0,2.1,ctx)
		check(c.player.health.hp < hp and not gp.visible and s.input.context == s.InputRouter.Context.GAMEPLAY, "actual " + kind + " attack interrupts assembly")
		if gp.visible: s.handle_action("grimoire")
	c.player.health.reset()
	s.handle_action("grimoire")
	gp.start_assembly("quick_step")
	c.player.health.grant_immunity(1.0,["*"],0.0)
	check(c.player.health.apply(Packet.new(990001,"test","infected",5.0,"melee"),0.0) == "immune" and gp.visible and gp.mode == "assembly", "immune hit preserves the open attempt")
	c.player.health.reset()
	c.player.health.apply(Packet.new(990002,"test","infected",100000.0,"melee"),0.0)
	check(not gp.visible and s.input.context == s.InputRouter.Context.DEATH, "lethal hit closes grimoire and enters death context")
	c.free()
	print("RESULT ",JSON.stringify({"checks":checks,"failures":failures,"status":"PASS" if failures.is_empty() else "FAIL"}))
	quit(0 if failures.is_empty() else 1)
