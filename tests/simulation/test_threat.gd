extends RefCounted
# Threat checks (P3: the Blighted Sprite, Tech Spec §4): navigation grid,
# footsteps, idle roam, aggro at 16 m, chase at 5.5 m/s, the 0.35 s telegraph
# at 1.8 m and its dodge, 12 damage per 1.2 s, disengage past 24 m back to its
# origin, the AggroTracker's 3 s out-of-combat countdown [R12], kill EXP and the
# 20-kill Rank D mission, respawns, player death and restart, pause, overlay
# closing on damage. The Shambler version is reference/shooter/.

const DT := 1.0 / 60.0
const Sprite = preload("res://scripts/actors/blighted_sprite.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put_player(c: Node3D, at: Vector3, yaw_deg := 0.0) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()

static func put_enemy(sh: CharacterBody3D, at: Vector3, yaw_deg: float) -> void:
	sh.reset_to(at, yaw_deg)

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	var keys := {}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	var nav: RefCounted = c.nav
	var sprites: Array = c.enemies.values()
	var live: Array = sprites.filter(func(e): return not e.reserve)
	check.call(sprites.size() == c.MAX_ALIVE and c.MAX_ALIVE == 20 and live.size() == 6 and live.all(func(e): return e is Sprite and e.state == Sprite.State.IDLE_ROAM and e.health.hp == 120.0), "a pool of 20 Sprites (the R6 cap): six start roaming at their zones with 120 HP, 14 in reserve")
	check.call(live.all(func(e): return flat(e.global_position).distance_to(flat(c.spawn.at)) > Sprite.AGGRO_R + 10.0) and not c.director.in_combat, "none starts inside aggro range of the player spawn; out of combat")
	check.call(Sprite.SPEED == 8.0 and Sprite.AGGRO_R == 16.0 and Sprite.DEAGGRO_R == 24.0 and Sprite.WINDUP_R == 1.8 and Sprite.WINDUP_S == 0.35 and Sprite.DAMAGE == 12.0 and Sprite.ATTACK_INTERVAL == 1.2, "Sprite tuning: 8 m/s [Sir R8], aggro 16 / de-aggro 24 m, 0.35 s windup at 1.8 m, 12 per 1.2 s [spec]")

	# The spawner keeps 8 in play [design], one every 4 s, far from the player; never over 20.
	var most := 0
	var near_spawn := false
	for i in int(round(9.0 / DT)):
		s.step(DT)
		most = maxi(most, c.alive_count())
		for e in c.enemies.values():
			if not e.reserve and e.visible and flat(e.global_position).distance_to(flat(c.player.global_position)) <= Sprite.AGGRO_R: near_spawn = true
	check.call(c.alive_count() == c.TARGET_ALIVE and most == c.TARGET_ALIVE and not near_spawn and c.TARGET_ALIVE <= c.MAX_ALIVE, "after 9 s: %d in play (6 + one every 4 s up to %d), none inside aggro range" % [c.alive_count(), c.TARGET_ALIVE])
	var killed := []
	for e in c.enemies.values():
		if not e.reserve:
			killed.append(e)
			e.health.apply(DamagePacket.new(95000 + e.get_index(), "player", "player", 500.0, "blast"), s.run.time)
	s.step(DT)
	var all_dead: int = c.alive_count()
	for i in int(round(4.2 / DT)): s.step(DT)
	var refilling: int = c.alive_count()
	for i in int(round(8.2 / DT)): s.step(DT)
	var recycled: bool = killed.all(func(e): return e.reserve or (not e.health.dead and e.visible))
	check.call(all_dead == 0 and refilling >= 1 and recycled and c.alive_count() <= c.TARGET_ALIVE and s.progression.kills == c.TARGET_ALIVE, "killing all 8: the spawner refills from the pool (%d after 4 s, %d after 12 s) and the dead return to it after 12 s: 20 kills stay reachable" % [refilling, c.alive_count()])
	# A new Sprite never comes out at a zone inside the player's reach: stand on each zone in turn.
	var bad_zone := 0
	for z in c.Greybox.ENEMIES:
		c.player.global_position = z.at
		for k in 40:
			var fz: Dictionary = c._free_zone()
			if not fz.is_empty() and flat(fz.at).distance_to(flat(z.at)) <= Sprite.AGGRO_R + 4.0: bad_zone += 1
	check.call(bad_zone == 0, "spawn zones inside 20 m of the player are never used (%d bad picks)" % bad_zone)
	s.restart()
	await tree.physics_frame

	# Navigation: a pillar, the slide gap.
	var west := Vector3(76, 0, 28)
	var east := Vector3(84, 0, 28)
	var r: Dictionary = nav.find_path(west, east)
	var clear := true
	for wp in r.path:
		if nav.blocked(nav.cell_of(wp)): clear = false
	check.call(nav.blocked(nav.cell_of(Vector3(80, 0, 28))) and r.ok and clear, "a pillar is blocked for walkers; the route goes round it, never through solids")
	var around: Dictionary = nav.find_path(Vector3(60, 0, 32), Vector3(60, 0, 28))
	var under := false
	for wp in around.path:
		if absf(wp.z - 30.0) < 0.3 and wp.x > 52.0 and wp.x < 68.0: under = true
	check.call(nav.blocked(nav.cell_of(Vector3(60, 0, 30))) and around.ok and not under, "slide gap blocks standing walkers: the route goes round the wall")

	# One live Sprite for the behaviour checks; the rest out of play.
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	c.park_enemies(["sprite_1"])
	sh.inert = false

	# Idle roam: wanders, but stays within 4 m of its origin.
	put_player(c, Vector3(110, 0, 10))
	put_enemy(sh, Vector3(40, 0, 60), 0.0)
	await tree.physics_frame
	var far_out := 0.0
	var moved := 0.0
	var last: Vector3 = sh.global_position
	for i in int(round(12.0 / DT)):
		s.step(DT)
		far_out = maxf(far_out, flat(sh.global_position).distance_to(flat(sh.origin)))
		moved += flat(sh.global_position).distance_to(flat(last))
		last = sh.global_position
	check.call(sh.state == Sprite.State.IDLE_ROAM and moved > 3.0 and far_out <= Sprite.ROAM_R + 0.3, "idle roam: walks %.1f m in 12 s, never more than %.1f m from its origin (%.2f)" % [moved, Sprite.ROAM_R, far_out])

	# Footsteps: crouching is silent, running is heard at 6 m.
	for mode in [["crouch", [KEY_W, KEY_CTRL]], ["walk", [KEY_W]]]:
		put_player(c, Vector3(75, 0, 55))
		await tree.physics_frame
		var first_id: int = c.noise.events.back().id if not c.noise.events.is_empty() else 0
		for k in mode[1]: keys[k] = true
		steps(c, 1.0)
		for k in mode[1]: keys.erase(k)
		var radii := []
		for e in c.noise.events:
			if e.id > first_id and e.kind == "footsteps": radii.append(e.radius)
		match mode[0]:
			"crouch": check.call(radii.is_empty(), "crouch-walking makes no footstep noise")
			"walk": check.call(radii.size() >= 2 and radii.all(func(x): return x == 6.0), "running: footsteps heard at 6 m (%d)" % radii.size())
		steps(c, 0.3)

	# Aggro by distance (any facing, no sight cone): 16.5 m no, 15.5 m yes.
	put_enemy(sh, Vector3(60, 0, 70), 0.0)
	put_player(c, Vector3(60, 0, 53.5)) # 16.5 m
	await tree.physics_frame
	s.step(DT)
	var calm: bool = sh.state == Sprite.State.IDLE_ROAM and not c.director.in_combat
	put_enemy(sh, Vector3(60, 0, 70), 180.0) # facing away
	put_player(c, Vector3(60, 0, 54.5)) # 15.5 m, behind its back
	await tree.physics_frame
	s.step(DT)
	check.call(calm and sh.state == Sprite.State.CHASE and sh.aggroed and c.director.in_combat, "aggro at 16 m whatever its facing; the player is in combat")
	var a: Vector3 = sh.global_position
	sh.pounce_ready = s.run.time + 10.0 # pounce on cooldown: this is the plain chase
	steps(c, 0.5)
	var chased := flat(sh.global_position).distance_to(flat(a))
	check.call(chased > 3.5 and chased <= Sprite.SPEED * 0.5 + 0.05 and sh.state == Sprite.State.CHASE, "chases at 8 m/s, below the player's 10 (%.2f m in 0.5 s)" % chased)

	# Pounce [Sir R8, R12]: at 20 m or closer, in sight, it stands 0.5 s, then leaps (18 m/s):
	# 20 damage and Concuss (-80% Mov Spd and Atk Spd for 1.5 s).
	check.call(Sprite.POUNCE_R == 20.0 and Sprite.DIVE_MAX == 25.0 and Sprite.CHARGE_S == 0.5 and Sprite.POUNCE_COOLDOWN_S == 6.0, "pounce tuning [R12]: from 20 m, leaps up to 25 m; 0.5 s charge, 6 s cooldown")
	c.player.health.reset()
	s.stats.modifiers.clear()
	put_enemy(sh, Vector3(60, 0, 65.5), 0.0)
	put_player(c, Vector3(60, 0, 45)) # 20.5 m (aggro first: it is hunting)
	await tree.physics_frame
	sh.alert_to(c.player.global_position)
	s.step(DT); s.step(DT)
	var no_charge_far: bool = sh.state == Sprite.State.CHASE and sh.pounces == 0
	put_enemy(sh, Vector3(60, 0, 64.5), 0.0)
	put_player(c, Vector3(60, 0, 45)) # 19.5 m
	await tree.physics_frame
	sh.alert_to(c.player.global_position)
	s.step(DT); s.step(DT)
	var c0: Vector3 = sh.global_position
	var charging: bool = sh.state == Sprite.State.CHARGE
	for i in int(round(0.45 / DT)): s.step(DT)
	var still_charging: bool = sh.state == Sprite.State.CHARGE and flat(sh.global_position).distance_to(flat(c0)) < 0.01 and c.player.health.hp == 100.0
	var hit_t := -1.0
	for i in 120:
		s.step(DT)
		if c.player.health.hp < 100.0:
			hit_t = s.run.time
			break
	check.call(no_charge_far and charging and still_charging, "pounce: none at 20.5 m; at 19.5 m it stands still for the 0.5 s charge, no damage yet")
	check.call(hit_t > 0.0 and c.player.health.hp == 80.0 and sh.pounces == 1 and sh.pounce_hits == 1, "the dive lands: exactly 20 damage (hp %.0f)" % c.player.health.hp)
	var run_c: float = c.player.run_top()
	var atk_c: float = s.stats.attack_interval(s.run.time)
	check.call(absf(run_c - 2.0) < 0.01 and absf(atk_c - 1.0) < 0.01, "Concuss: run %.2f m/s, one attack per %.2f s (-80%%)" % [run_c, atk_c])
	put_player(c, Vector3(20, 0, 20)) # far away while it wears off
	await tree.physics_frame
	while s.run.time - hit_t < 1.55: s.step(DT)
	check.call(absf(c.player.run_top() - 10.0) < 0.01 and absf(s.stats.attack_interval(s.run.time) - 0.2) < 0.01, "Concuss ends after 1.5 s: run 10, attack every 0.2 s")
	# Cooldown: no second pounce within 6 s of the first dive.
	put_enemy(sh, Vector3(60, 0, 69.5), 0.0)
	sh.pounce_ready = s.run.time + 3.0 # as if it dived 3 s ago
	c.player.health.reset()
	put_player(c, Vector3(60, 0, 62)) # 7.5 m
	await tree.physics_frame
	s.step(DT); s.step(DT)
	check.call(sh.state == Sprite.State.CHASE and sh.pounces == 0, "on its 6 s cooldown it chases instead of pouncing")
	# Dash i-frames dodge the dive.
	put_enemy(sh, Vector3(60, 0, 69.5), 0.0)
	c.player.health.reset()
	s.stats.modifiers.clear()
	put_player(c, Vector3(60, 0, 60))
	await tree.physics_frame
	for i in int(round(0.55 / DT)): s.step(DT)
	c.player.health.grant_immunity(s.run.time + 1.0, ["*"], s.run.time)
	for i in 60: s.step(DT)
	check.call(sh.pounces == 1 and sh.pounce_hits == 0 and c.player.health.hp == 100.0 and absf(c.player.run_top() - 10.0) < 0.01, "dash i-frames dodge the pounce: no damage, no Concuss")
	c.player.health.grant_immunity(-1.0, [], -INF)
	# Line of sight: a Sprite already hunting (hit, say) chases a player behind a wall, never pounces.
	put_enemy(sh, Vector3(47, 0, 12), 90.0)
	put_player(c, Vector3(42, 0, 12)) # 5 m, the 6 m run wall at x 44 between
	await tree.physics_frame
	sh.alert_to(c.player.global_position)
	var ever_charged := false
	for i in 60:
		s.step(DT)
		if sh.state == Sprite.State.CHARGE: ever_charged = true
	check.call(not ever_charged and sh.pounces == 0, "no pounce without line of sight")

	# The strike: windup at 1.8 m, lands after 0.35 s, one hit per 1.2 s in contact.
	c.player.health.reset()
	put_enemy(sh, Vector3(60, 0, 62), 0.0)
	put_player(c, Vector3(60, 0, 60.5)) # 1.5 m ahead
	await tree.physics_frame
	s.step(DT) # roam -> aggro
	s.step(DT) # inside 1.8 m: the telegraph starts
	var winding: bool = sh.state == Sprite.State.WINDUP and c.player.health.hp == 100.0
	steps(c, 0.3) # 0.32 s into the windup
	var before_hit: float = c.player.health.hp
	steps(c, 0.05)
	check.call(winding and before_hit == 100.0 and c.player.health.hp == 88.0, "1.5 m away: a 0.35 s telegraph, then 12 damage (hp %.0f)" % c.player.health.hp)
	steps(c, 3.6 - 0.35 - DT * 2.0)
	check.call(sh.hits == 3 and is_equal_approx(c.player.health.hp, 64.0), "in contact: one strike every 1.2 s (%d hits in 3.6 s, hp %.0f)" % [sh.hits, c.player.health.hp])
	# Stepping back during the telegraph dodges it.
	c.player.health.reset()
	put_enemy(sh, Vector3(60, 0, 62), 0.0)
	put_player(c, Vector3(60, 0, 60.5))
	await tree.physics_frame
	steps(c, 0.2)
	put_player(c, Vector3(60, 0, 58.5)) # 3.5 m: out of reach
	await tree.physics_frame
	steps(c, 0.25)
	check.call(sh.strikes == 1 and sh.hits == 0 and c.player.health.hp == 100.0, "stepping back during the telegraph dodges the strike")

	# Disengage: past 24 m it walks home and roams; the combat countdown then runs 3 s [R12].
	put_enemy(sh, Vector3(60, 0, 70), 0.0)
	put_player(c, Vector3(60, 0, 57)) # 13 m: chasing (pounce on cooldown)
	await tree.physics_frame
	sh.pounce_ready = s.run.time + 10.0
	steps(c, 0.2)
	var hunting: bool = sh.state == Sprite.State.CHASE
	put_player(c, Vector3(60, 0, 30)) # ~35 m
	await tree.physics_frame
	s.step(DT)
	var t_drop: float = s.run.time
	check.call(hunting and sh.state == Sprite.State.DISENGAGE and not sh.aggroed, "past 24 m it disengages")
	var home_t := -1.0
	for i in int(round(6.0 / DT)):
		s.step(DT)
		if sh.state == Sprite.State.IDLE_ROAM:
			home_t = s.run.time
			break
	check.call(home_t > 0.0 and flat(sh.global_position).distance_to(flat(sh.origin)) <= 0.7, "back at its origin, roaming again (%.2f m off)" % flat(sh.global_position).distance_to(flat(sh.origin)))
	var t_back: float = s.run.time
	put_enemy(sh, Vector3(60, 0, 70), 0.0) # aggro again, then drop it: time the grace
	put_player(c, Vector3(60, 0, 57))
	await tree.physics_frame
	sh.pounce_ready = s.run.time + 10.0
	steps(c, 0.2)
	put_player(c, Vector3(60, 0, 30))
	await tree.physics_frame
	s.step(DT)
	t_drop = s.run.time
	var in_c: bool = c.director.in_combat
	while s.run.time - t_drop < 2.9: s.step(DT)
	var still: bool = c.director.in_combat
	steps(c, 0.2)
	check.call(t_back > 0.0 and in_c and still and not c.director.in_combat and c.director.OUT_OF_COMBAT_S == 3.0, "in combat until 3 s after the last aggro drops, then out [R12]")
	# A hit from past 24 m turns it toward the player, then it gives up again.
	put_enemy(sh, Vector3(60, 0, 70), 0.0)
	put_player(c, Vector3(60, 0, 40)) # 30 m
	await tree.physics_frame
	sh.health.apply(DamagePacket.new(96010, "player", "player", 1.0, "blast"), s.run.time)
	var provoked: bool = sh.state == Sprite.State.CHASE
	s.step(DT)
	check.call(provoked and sh.state == Sprite.State.DISENGAGE, "hurt from 30 m: it turns to chase, then disengages at once (past 24 m)")

	# Kills: EXP straight from the kill [Sir: no orbs]; respawn after 12 s, away from the player.
	var pr: RefCounted = s.progression
	var k0: int = pr.kills
	var exp0: int = pr.exp + 0
	put_enemy(sh, Vector3(60, 0, 70), 0.0)
	put_player(c, Vector3(60, 0, 40))
	await tree.physics_frame
	sh.health.apply(DamagePacket.new(96011, "player", "player", 500.0, "blast"), s.run.time)
	s.step(DT)
	await tree.physics_frame
	check.call(sh.state == Sprite.State.DEAD and sh.get_node("Shape").disabled and pr.kills == k0 + 1 and pr.exp == exp0 + 25, "a kill: dead, no collision, +1 kill and +25 EXP straight away")
	steps(c, 11.5)
	var waiting: bool = sh.state == Sprite.State.DEAD and not sh.reserve
	steps(c, 0.7)
	check.call(waiting and sh.reserve and not sh.visible, "a dead Sprite returns to the pool after 12 s")

	# Mission: 20 kills promote E -> D (+5 stat points, +300 EXP) [spec].
	var unspent0: int = s.stats.unspent
	var level0: int = pr.level
	for i in 19:
		if pr.kills >= 20: break
		put_enemy(sh, Vector3(60, 0, 70), 0.0)
		sh.inert = false
		sh.health.apply(DamagePacket.new(96100 + i, "player", "player", 500.0, "blast"), s.run.time)
		s.step(DT)
	var m: Dictionary = pr.mission()
	check.call(pr.kills == 20 and pr.rank == "D" and m.is_empty() and s.stats.unspent >= unspent0 + 5 and pr.level > level0, "20 kills: Rank D, +5 stat points, levels from the EXP (level %d, %d unspent)" % [pr.level, s.stats.unspent])
	check.call(c.notice.begins_with("RANK UP: D") or c.mission_hud.text.begins_with("Rank D"), "the rank-up is announced (%s)" % c.notice)
	s.restart()
	await tree.physics_frame
	s.step(DT) # the HUD refreshes on publish
	check.call(s.progression.kills == 0 and s.progression.level == 1 and s.progression.rank == "D" and s.meta.rank == "D" and c.mission_hud.text.begins_with("Rank D"), "restart (death model): kills and level reset, the earned Rank D is kept (%s) [R5]" % c.mission_hud.text)
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	s.step(DT)
	check.call(s.progression.rank == "E" and c.mission_hud.text.begins_with("Mission: Defeat 20 enemies (0/20)"), "a fresh profile: rank E, 0/20 on the mission tracker")
	sh = c.enemies["sprite_1"]
	c.park_enemies(["sprite_1"])
	sh.inert = false

	# Damage closes an overlay (the Grimoire, P5).
	put_enemy(sh, Vector3(60, 0, 62), 0.0)
	put_player(c, Vector3(60, 0, 60.5))
	await tree.physics_frame
	s.input.open_overlay("grimoire")
	steps(c, 0.5)
	check.call(s.input.context == InputRouter.Context.GAMEPLAY and c.player.health.hp < 100.0, "a strike closes the overlay")

	# Pause freezes the Sprite.
	var esc := InputEventKey.new(); esc.physical_keycode = KEY_ESCAPE; esc.keycode = KEY_ESCAPE; esc.pressed = true
	put_enemy(sh, Vector3(60, 0, 70), 0.0)
	put_player(c, Vector3(60, 0, 60))
	await tree.physics_frame
	steps(c, 0.3)
	s.handle_event(esc)
	a = sh.global_position
	var hp_paused: float = c.player.health.hp
	steps(c, 1.0)
	check.call(sh.global_position == a and c.player.health.hp == hp_paused, "paused: Sprite frozen")
	s.handle_event(esc)

	# Player death: panel; the Sprite stands down; restart resets the level.
	put_enemy(sh, Vector3(60, 0, 62), 0.0)
	put_player(c, Vector3(60, 0, 60.5))
	await tree.physics_frame
	c.player.health.reset()
	c.player.health.hp = 12.0
	steps(c, 0.5)
	check.call(c.player.health.dead and c.death_panel.visible and s.input.context == InputRouter.Context.DEATH, "lethal strike: death panel takes focus")
	check.call(c.death_panel.title.text == "YOU DIED" and c.death_panel.button.text == "Return to camp" and c.death_panel.detail.text.contains("Kept: unlocked pages"), "death panel: YOU DIED, what is lost and kept [R5], Return to camp")
	steps(c, 1.5)
	check.call(sh.hits == 1 and sh.state in [Sprite.State.DISENGAGE, Sprite.State.IDLE_ROAM], "the Sprite stops striking a dead player and goes home")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(not c.death_panel.visible and not c.player.health.dead and s.input.context == InputRouter.Context.GAMEPLAY, "'Return to camp': panel closed, alive")
	check.call(flat(sh.global_position).distance_to(Vector2(35, 60)) < 0.01 and sh.state == Sprite.State.IDLE_ROAM and sh.visible and not sh.inert and not sh.reserve and c.alive_count() == 6, "restart: six Sprites back at their zones, live")
	s.input.key_source = saved_k
	s.restart()
	await tree.physics_frame

	# Line of sight [spec P3]: in range behind a pillar it stays calm; step out and it aggroes.
	c.park_enemies([sh.enemy_id])
	put_enemy(sh, Vector3(80, 0, 36), 180.0) # the pillar at (80, 28) between them
	put_player(c, Vector3(80, 0, 21)) # 15 m
	await tree.physics_frame
	s.step(DT)
	var hidden_calm: bool = sh.state == Sprite.State.IDLE_ROAM and not sh.aggroed
	put_player(c, Vector3(84, 0, 23)) # 13.6 m, past the pillar's edge
	await tree.physics_frame
	s.step(DT)
	check.call(hidden_calm and sh.state == Sprite.State.CHASE, "aggro needs line of sight: behind a pillar at 15 m it stays calm, in the open it chases [spec P3]")
	# HP bar [spec P3]: hidden at full HP, shown and scaled once hurt, gone on death.
	put_enemy(sh, Vector3(80, 0, 36), 180.0)
	sh.inert = true
	var full_hidden: bool = not sh.hp_bar.visible
	sh.health.apply(DamagePacket.new(97001, "test", "player", 30.0, "blast"), s.run.time)
	var shown: bool = sh.hp_bar.visible and absf(sh.bar_fraction() - 0.75) < 0.02
	sh.health.apply(DamagePacket.new(97002, "test", "player", 500.0, "blast"), s.run.time)
	var gone: bool = not sh.hp_bar.visible
	put_enemy(sh, Vector3(80, 0, 36), 180.0)
	check.call(full_hidden and shown and gone and not sh.hp_bar.visible, "enemy HP bar: hidden at full HP, 75% after 30 damage, hidden on death and after a respawn")
	s.restart()
	await tree.physics_frame
