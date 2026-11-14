extends SceneTree
# Playthrough suite (handoff §7, §9): a bot plays a fresh run of the 50% MVP
# in the Dark Forest end to end, through the real game loop (main runs its own
# physics ticks; run with --fixed-fps 60 so it goes as fast as the CPU allows)
# and the real input path (keys and mouse buttons through the InputRouter,
# mouse look through the player's yaw/pitch, panels through their own
# methods), with the Blighted Sprites live, on a fixed seed: a New game from
# the pause menu; find and unlock Quick Step; kill 20 Sprites for rank D (the
# rank banner); find and unlock Ring of Fire and Sage Arts, equip them; one
# Spell Chant (the stat rises, no EXP); Reset stats refunds exactly; cast the
# Ring; then die, and check the death model (pages, rank, chant tier kept;
# level, points, loadout lost), the camp respawn at full HP/MP, and a new
# forest. Every step is asserted.
#   godot --headless --fixed-fps 60 --path . -s res://tests/playthrough/run_playthrough.gd
# Emits one `RESULT {json}` line.

const SUITE := "playthrough"
const NavigationGrid = preload("res://scripts/world/navigation_grid.gd")
const Forest = preload("res://scripts/world/dark_forest.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const SIM_LIMIT_S := 900.0
const FIGHT_R := 22.0      # the bot shoots from here (the basic fireball reaches 30 m)
const KEEP_AWAY := 10.0    # and backs off when a Sprite gets this close

var checks := 0
var failures: Array[String] = []
var fixture := ""
var c: Node3D
var keys := {}
var nav := NavigationGrid.new()
var log: Array[String] = []
var frames := 0
var deaths := 0
var lowest_hp := INF
var banners: Array = []
var hit_log: Array = []
var rng_seed := 20261112
var dodges := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="): fixture = arg.trim_prefix("--fixture=")
		if arg.begins_with("--seed="): rng_seed = int(arg.trim_prefix("--seed="))
	c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = false # the game drives itself; the bot only presses keys
	root.add_child(c)
	run.call_deferred()

func step() -> void:
	await physics_frame
	frames += 1
	if p().health.hp < lowest_hp: lowest_hp = p().health.hp

func steps(n: int) -> void:
	for i in n: await step()

func tap(k: int) -> void:
	keys[k] = true
	await step()
	keys.erase(k)
	await step()

func p() -> CharacterBody3D:
	return c.player

func out_of_time() -> bool:
	return frames / 60.0 > SIM_LIMIT_S

func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# Mouse look: turn the view to a world point.
func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = p().eye_position()
	var to := target - eye
	p().yaw = atan2(-to.x, -to.z)
	p().pitch = atan2(to.y, Vector2(to.x, to.z).length())
	p().apply_look()

func release_all() -> void:
	for k in [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SHIFT, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]: keys.erase(k)

# The Sprite the bot should deal with: hunting it, or the nearest one in play.
func threat() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := INF
	for id in c.enemies:
		var e: CharacterBody3D = c.enemies[id]
		if e.health.dead or e.reserve or not e.visible: continue
		var d := flat(e.global_position).distance_to(flat(p().global_position))
		if e.aggroed: d -= 100.0 # anything already on the player comes first
		if d < best_d:
			best_d = d
			best = e
	return best

func hunting_me() -> CharacterBody3D:
	var t := threat()
	if t != null and (t.aggroed or flat(t.global_position).distance_to(flat(p().global_position)) < 12.0): return t
	return null

# One tick of walking toward `target` along the bot's nav path.
var _path: Array = []
var _path_goal := Vector3.INF
var _replan := 0
func walk_toward(target: Vector3) -> bool:
	var pos := p().global_position
	_replan -= 1
	if _path.is_empty() or _replan <= 0 or _path_goal.distance_to(target) > 1.0:
		var r: Dictionary = nav.find_path(pos, target)
		if not r.ok: return false
		_path = r.path
		_path_goal = target
		_replan = 30
	while not _path.is_empty() and flat(_path[0]).distance_to(flat(pos)) < 0.3: _path.pop_front()
	var next: Vector3 = _path[0] if not _path.is_empty() else target
	var to := next - pos
	p().yaw = atan2(-to.x, -to.z)
	p().pitch = 0.0
	keys.erase(KEY_S)
	keys[KEY_W] = true
	return true

# A Sprite at the end of its pounce charge (0.5 s, telegraphed): the bot
# dodges it the way a player does, a sideways dash (i-frames, then out of the
# dive line).
func about_to_dive() -> CharacterBody3D:
	if p().dash_charges <= 0: return null
	for id in c.enemies:
		var e: CharacterBody3D = c.enemies[id]
		if e.state == e.State.CHARGE and e.timer + 0.12 >= e.CHARGE_S and flat(e.global_position).distance_to(flat(p().global_position)) < e.DIVE_MAX + 1.0:
			return e
	return null

var _dodge_left := true
func dodge(diver: CharacterBody3D) -> void:
	release_all()
	look_at_point(diver.global_position + Vector3(0, 1.0, 0))
	var side := KEY_A if _dodge_left else KEY_D
	_dodge_left = not _dodge_left
	dodges += 1
	keys[side] = true
	keys[KEY_SHIFT] = true
	await step()
	keys.erase(KEY_SHIFT)
	await steps(10)
	keys.erase(side)

func others_on_me(foe: CharacterBody3D) -> int:
	var n := 0
	for id in c.enemies:
		var e: CharacterBody3D = c.enemies[id]
		if e != foe and e.aggroed and not e.health.dead and flat(e.global_position).distance_to(flat(p().global_position)) < 20.0: n += 1
	return n

# Fight one Sprite to the death: close in along the paths, shoot from range
# (special when ready, Cultivate when ready), back off when it gets close.
func fight(foe: CharacterBody3D) -> bool:
	var since := 0
	var last_hp: float = foe.health.hp
	var no_hit := 0          # ticks of shooting without the Sprite losing HP
	var close_in := 0        # ticks left of stepping in (shots blocked by cover)
	while not foe.health.dead and not foe.reserve:
		if out_of_time() or p().health.dead: return false
		since += 1
		if since > 60 * 60:
			check(false, "a fight ran over a minute (%s at %s)" % [foe.enemy_id, foe.global_position])
			return false
		var diver := about_to_dive()
		if diver != null:
			await dodge(diver)
			continue
		var aim: Vector3 = foe.global_position + Vector3(0, 1.0, 0)
		var d := flat(foe.global_position).distance_to(flat(p().global_position))
		var seen: bool = c.clear_line(p().eye_position(), aim)
		if foe.health.hp < last_hp:
			last_hp = foe.health.hp
			no_hit = 0
		elif no_hit > 120 and others_on_me(foe) == 0: # 2 s of shots on cover, and alone with it: step round
			no_hit = 0
			close_in = 60
		if close_in > 0: close_in -= 1
		if d > FIGHT_R or not seen or (close_in > 0 and d > 3.0):
			keys.erase(MOUSE_BUTTON_LEFT)
			if not walk_toward(foe.global_position):
				keys.erase(KEY_W)
		else:
			look_at_point(aim)
			keys.erase(KEY_W)
			if d < KEEP_AWAY: keys[KEY_S] = true
			else: keys.erase(KEY_S)
			keys[MOUSE_BUTTON_LEFT] = true
			no_hit += 1
			if c.pcombat.special_remaining(c.session.run.time) <= 0.0 and d > 4.0: keys[MOUSE_BUTTON_RIGHT] = true
			else: keys.erase(MOUSE_BUTTON_RIGHT)
			if c.pcombat.remaining("skill_1", c.session.run.time) <= 0.0: keys[KEY_E] = true
			else: keys.erase(KEY_E)
		await step()
	release_all()
	keys.erase(KEY_E)
	await step()
	return true

# Walk to `target`, fighting anything that comes for the bot on the way.
func goto(target: Vector3, label: String) -> bool:
	var best := INF
	var since_progress := 0
	_path.clear()
	while true:
		if out_of_time():
			check(false, "%s: out of time" % label)
			return false
		if p().health.dead:
			check(false, "%s: died" % label)
			return false
		var foe := hunting_me()
		if foe != null:
			if not await fight(foe): return false
			_path.clear()
			best = INF
			continue
		var pos := p().global_position
		var left := flat(target).distance_to(flat(pos))
		if left < 0.5:
			release_all()
			await steps(2)
			return true
		if left < best - 0.05:
			best = left
			since_progress = 0
		else:
			since_progress += 1
			if since_progress > 360:
				check(false, "%s: stuck at %s (%.2f m left)" % [label, pos, left])
				return false
		if not walk_toward(target):
			check(false, "%s: no route from %s" % [label, pos])
			return false
		await step()
	return false

# Spend any stat points on Magic Pow, through the Player ID panel's [+].
func spend_points() -> void:
	var gp: CanvasLayer = c.grimoire_panel
	while c.session.stats.unspent > 0:
		if not gp.allocate("magic_pow"): break

# Walk up to a page lying in the world, look at it, press F.
func pick_up(id: String) -> bool:
	var spot: Vector3 = c.page_spots[id]
	if not await goto(spot + Vector3(0, 0, 1.6), "to the %s page" % id): return false
	look_at_point(spot + Vector3(0, 0.9, 0))
	await step()
	var kind: String = c.target_in_view().kind
	await tap(KEY_F)
	check(kind == "page" and c.session.grimoire.is_found(id) and c.notice.begins_with("New page"), "picked up the %s page (%s)" % [id, kind])
	return c.session.grimoire.is_found(id)

# Tab, then solve the page's Code Assembly by clicking lines into place.
func unlock(id: String) -> bool:
	while hunting_me() != null:
		if not await fight(hunting_me()): return false
	var gp: CanvasLayer = c.grimoire_panel
	c.session.handle_event(_key(KEY_TAB))
	await step()
	var opened: bool = gp.visible
	gp.select_page(id)
	var a: Dictionary = gp.start_assembly(id)
	for k in gp.attempt.order.size():
		var at: int = gp.attempt.order.find(k)
		if at != k:
			gp.pick(k)
			gp.pick(at)
	var r: Dictionary = gp.submit()
	check(opened and not a.is_empty() and r.ok and c.session.grimoire.is_unlocked(id), "Tab, Code Assembly solved: %s unlocked" % id)
	c.session.handle_event(_key(KEY_TAB))
	await step()
	return c.session.grimoire.is_unlocked(id)

func run() -> void:
	if fixture == "hang": return
	seed(rng_seed)
	c.fixed_map_seed = rng_seed # one fixed forest; the spawner's draws are seeded from it (main.spawn_rng)
	await step()
	await step()
	var s = c.session
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	# 0. A New game from the pause menu (two clicks), as a player starts from zero.
	s.meta.unlock("quick_step") # a profile with something to wipe
	s.meta.set_rank("D")
	var pm: CanvasLayer = c.pause_menu
	s.handle_action("pause")
	pm.buttons.new_game.pressed.emit()
	pm.buttons.new_game.pressed.emit()
	await step()
	check(s.meta.rank == "E" and s.meta.unlocked == s.meta.START_PAGES and not s.paused(), "New game (wipe progress): rank E, only the start pages, playing")
	c.banner.shown.connect(func(it) -> void: banners.append(it.kind))
	nav.setup(Forest.BOUNDS[0], Forest.BOUNDS[1])
	nav.rebuild(c.static_solids)
	p().health.died.connect(func(_pk) -> void:
		deaths += 1
		var on := 0
		for id in c.enemies: if c.enemies[id].aggroed: on += 1
		log.append("died at %.0f s: %d Sprites on the player, hits %s" % [frames / 60.0, on, str(hit_log.slice(-8))]))
	p().health.damaged.connect(func(pk, applied: float) -> void:
		if applied > 0.0: hit_log.append("%s %.0f" % [pk.kind, applied]))
	check(c.world_kind == "forest" and p().global_position.distance_to(c.spawn.at) < 0.1 and s.progression.rank == "E" and s.progression.level == 1, "a fresh run at the camp: level 1, rank E")
	check(c.alive_count() >= 6, "the forest is live: %d Sprites roaming" % c.alive_count())

	# 1. Quick Step, by the camp: pick it up, unlock it, equip it on Q.
	if not await pick_up("quick_step"): return finish()
	if not await unlock("quick_step"): return finish()
	check(c.grimoire_panel.equip_selected("skill_2") == "ok" and String(c.pcombat.loadout.skill_2.id) == "quick_step", "equipped Quick Step on [Q]")
	spend_points()

	# 2. The rank mission: 20 kills, fighting through the real loop.
	var hunts := 0
	while s.progression.rank == "E":
		if out_of_time() or p().health.dead: break
		var foe := threat()
		if foe == null:
			await steps(30) # the spawner brings the next one out
			continue
		hunts += 1
		if not await fight(foe): break
		spend_points()
	check(not p().health.dead and s.progression.kills >= 20 and s.progression.rank == "D" and s.meta.rank == "D", "20 Sprites killed in one life: rank D (%d kills, level %d)" % [s.progression.kills, s.progression.level])
	await steps(10)
	check("rank" in banners, "the rank-up gets its banner (%s)" % str(banners))
	log.append("rank D after %.0f s, level %d, lowest HP %.0f" % [frames / 60.0, s.progression.level, lowest_hp])
	if s.progression.rank != "D": return finish()

	# 3. Deeper in: Ring of Fire (north-west glade), Sage Arts (north-east glade).
	if not await pick_up("ring_of_fire"): return finish()
	if not await pick_up("sage_arts"): return finish()
	if not await unlock("ring_of_fire"): return finish()
	if not await unlock("sage_arts"): return finish()
	var gp: CanvasLayer = c.grimoire_panel
	gp.select_page("ring_of_fire")
	var e1: String = gp.equip_selected("spell_1")
	gp.select_page("sage_arts")
	var e2: String = gp.equip_selected("passive")
	check(e1 == "ok" and e2 == "ok" and String(c.pcombat.loadout.spell_1.id) == "ring_of_fire" and String(c.pcombat.loadout.passive.id) == "sage_arts", "at rank D: Ring of Fire on [1], Sage Arts on [P] (%s, %s)" % [e1, e2])

	# 4. One Spell Chant: with no points left, [+] on Magic Pow starts it.
	while hunting_me() != null:
		if not await fight(hunting_me()): return finish()
	spend_points()
	s.handle_event(_key(KEY_TAB))
	await step()
	gp.show_tab("player_id")
	var pow0: float = s.stats.value("magic_pow", s.run.time)
	var exp0: int = s.progression.exp
	var lvl0: int = s.progression.level
	var started: bool = not gp.allocate("magic_pow") and gp.mode == "chant"
	var r: Dictionary = gp.submit_chant(gp.problem.answers) if started else {"ok": false}
	var chant_open: bool = gp.visible
	check(chant_open and started and r.ok and s.stats.value("magic_pow", s.run.time) > pow0 and int(s.meta.chant_tier.get("magic_pow", 0)) == 1, "a Spell Chant on Magic Pow: right answer, +%.0f Pow" % (s.stats.value("magic_pow", s.run.time) - pow0))
	check(s.progression.exp == exp0 and s.progression.level == lvl0, "the chant gives no EXP and no level [R9]")
	# Reset stats: every allocated point and every chant comes back as a point.
	var st: RefCounted = s.stats
	var owed: int = st.unspent
	for k in st.points: owed += int(st.points[k])
	for k in st.chant_points: owed += int(st.chant_points[k])
	gp.reset_stats()
	var refunded: int = gp.reset_stats()
	var all_base: bool = st.points.values().all(func(v): return int(v) == 0) and st.chant_points.values().all(func(v): return int(v) == 0) and is_equal_approx(st.base_value("magic_pow"), 100.0) # base: a live Cultivate buff is not a stat
	check(st.unspent == owed and all_base and refunded >= 1, "Reset stats: every stat back to base, %d points back (allocated + chants)" % owed)
	spend_points()
	s.handle_event(_key(KEY_TAB))
	await step()

	# 5. Cast the Ring of Fire from [1].
	var casts0: int = int(c.pcombat.casts.get("ring_of_fire", 0))
	var mp0: float = c.pcombat.mp
	await tap(KEY_1)
	check(int(c.pcombat.casts.get("ring_of_fire", 0)) == casts0 + 1 and c.projectiles.rings.size() >= 1 and c.pcombat.mp < mp0, "[1] casts the Ring of Fire: orbs round the player, MP spent")
	check(not p().health.dead and deaths == 0 and not out_of_time(), "the whole loop in one life, %.0f s of game time (lowest HP %.0f)" % [frames / 60.0, lowest_hp])
	log.append("hunts %d, kills %d, level %d, frames %d" % [hunts, s.progression.kills, s.progression.level, frames])
	release_all()

	# 6. Death [R5]: what was learned is kept, the run is lost; back at camp in a new forest.
	var lvl_dead: int = s.progression.level
	var seed_dead: int = c.map_seed
	c.fixed_map_seed = -1 # the respawn draws a new forest, as in the game
	var trees_dead: Array = c.map.trees.slice(0, 5)
	p().health.apply(DamagePacket.new(990001, "test", "infected", 9999.0, "bite"), s.run.time)
	await step()
	check(p().health.dead and c.death_panel.visible and c.death_panel.button.text == "Return to camp" and c.death_panel.detail.text.contains("Kept"), "death: the panel says what is lost and kept, and offers Return to camp")
	c.death_panel.button.pressed.emit()
	await step()
	await step()
	var kept: bool = s.meta.rank == "D" and s.meta.unlocked.size() == 15 and int(s.meta.chant_tier.get("magic_pow", 0)) == 1
	var lost: bool = s.progression.level == 1 and s.progression.kills == 0 and s.stats.unspent == 0 and c.pcombat.loadout.spell_1 == null and c.pcombat.loadout.passive == null and c.pcombat.loadout.skill_2 == null
	check(kept, "after death, kept: rank D, all 15 pages unlocked, the Magic Pow chant tier [R5]")
	check(lost and lvl_dead > 1, "after death, lost: level %d -> 1, kills, stat points and the loadout [R5]" % lvl_dead)
	check(not p().health.dead and p().global_position.distance_to(c.spawn.at) < 0.1 and is_equal_approx(p().health.hp, p().health.max_hp) and is_equal_approx(c.pcombat.mp, c.pcombat.max_mp()), "respawned at the camp with full HP and MP")
	check(c.map_seed != seed_dead and c.map.trees.slice(0, 5) != trees_dead and Forest.rule_violations(c.map).is_empty(), "a new seed, a new forest (still a valid map)")
	check(s.grimoire.page("ring_of_fire").rank_ok(s.progression.rank) and c.grimoire_panel.equip_selected("spell_1") != "rank", "rank D is kept: Ring of Fire can be equipped again in the new run")
	finish()

func _key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k; e.keycode = k; e.pressed = true
	return e

func finish() -> void:
	if fixture == "fail": check(false, "injected fixture failure")
	if fixture == "missing-pass":
		quit(0)
		return
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"suite": SUITE, "status": status, "checks": checks, "failures": failures, "metrics": {"game_seconds": snappedf(frames / 60.0, 0.1), "deaths": deaths, "seed": rng_seed, "map_seed": c.map_seed, "dodges": dodges, "log": log}}))
	quit(0 if failures.is_empty() else 1)
