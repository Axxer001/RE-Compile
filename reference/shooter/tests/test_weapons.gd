extends RefCounted
# M5a weapons: melee reach/arc/walls, gun rays, magazines and reload, shotgun
# pellets, automatic fire rate, frag blast falloff and wall shielding,
# molotov fire ticks, throw cancel, no swap mid-action. Driven through the
# session with synthetic input, like play.

const DT := 1.0 / 60.0
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")
const ItemStack = preload("res://scripts/items/item_stack.gd")
const Greybox = preload("res://scripts/world/greybox.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const Shambler = preload("res://scripts/actors/shambler.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

# Equip and wait out its draw time (plus a tick to notice the change).
static func arm(c: Node3D, item: String) -> RefCounted:
	var w: RefCounted = WeaponInstance.create(item, c.session.run).weapon
	c.session.inventory.upgrade_bag(12)
	c.session.inventory.try_add(w)
	c.session.inventory.equip(w.instance_id)
	steps(c, w.definition.draw_s + 2.0 * DT)
	return w

# Aim (RMB) at a body height for `seconds` (default: fully aimed for this weapon).
static func aim_at(c: Node3D, keys: Dictionary, d: float, height: float) -> void:
	c.player.pitch = -atan2(c.player.eye_position().y - height, d)
	c.player.apply_look()
	keys[MOUSE_BUTTON_RIGHT] = true

static func give(c: Node3D, item: String, n: int) -> void:
	c.session.inventory.upgrade_bag(12)
	c.session.inventory.try_add(ItemStack.create(item, n, c.session.run).stack)

# Fresh night; player at `at` facing east (+X), level eyes; Shambler east of
# the player at distance `d`, facing away (east) so it does not start the fight.
static func setup(c: Node3D, tree: SceneTree, at: Vector3, d: float) -> CharacterBody3D:
	c.session.restart()
	await tree.physics_frame
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.yaw = deg_to_rad(-90.0)
	p.pitch = 0.0
	p.apply_look()
	var sh: CharacterBody3D = c.enemies["shambler_1"]
	sh.reset_to(at + Vector3(d, 0, 0), -90.0, c.noise.last_id())
	await tree.physics_frame
	return sh

static func click(c: Node3D, keys: Dictionary, button: int) -> void:
	keys[button] = true; c.session.step(DT)
	keys.erase(button); c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)

	# The level holds every MVP weapon and both throwables.
	var placed := {}
	for spec in Greybox.LOOT: placed[spec.item] = true
	for id in ["knife", "baseball_bat", "katana", "pistol", "shotgun", "assault_rifle", "molotov", "frag", "ammo_9mm", "ammo_shells", "ammo_556"]:
		check.call(placed.has(id), "%s is placed in the level" % id)

	# Melee: each weapon hits once at its reach edge, misses just beyond it.
	for id in ["knife", "baseball_bat", "katana"]:
		var def: Resource = load("res://data/weapons/%s.tres" % id)
		var sh := await setup(c, tree, Vector3(65, 0, 55), def.reach_tiles + Shambler.RADIUS - 0.1)
		arm(c, id)
		click(c, keys, MOUSE_BUTTON_LEFT)
		steps(c, def.total_s() + 0.1)
		check.call(sh.health.hp == Shambler.HP - def.damage_hp, "%s hits once at its reach edge (%.0f HP left)" % [id, sh.health.hp])
		check.call(sh.state == Shambler.State.CHASE or sh.state == Shambler.State.ATTACK, "%s: a hit Shambler turns on the player" % id)
		# Beyond reach by more than it can close during the active window (the swing noise draws it in).
		sh = await setup(c, tree, Vector3(65, 0, 55), def.reach_tiles + Shambler.RADIUS + 0.35)
		arm(c, id)
		click(c, keys, MOUSE_BUTTON_LEFT)
		steps(c, def.total_s() + 0.1)
		check.call(sh.health.hp == Shambler.HP, "%s misses just beyond reach (hp %.0f, gap %.2f m)" % [id, sh.health.hp, Vector2(sh.global_position.x - c.player.global_position.x, sh.global_position.z - c.player.global_position.z).length()])
	# A wall between player and target blocks the swing (bat through the lab's east wall).
	var walled := await setup(c, tree, Vector3(25.5, 0, 11), 1.2) # Shambler at x 26.7, outside the lab
	arm(c, "baseball_bat")
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 1.1)
	check.call(walled.health.hp == Shambler.HP, "the lab wall blocks a bat swing")

	# Pistol: one round, 35 damage along the ray (aimed at the chest); walls stop it.
	var sh2 := await setup(c, tree, Vector3(64, 0, 55), 5.0)
	var pistol := arm(c, "pistol")
	aim_at(c, keys, 5.0, 1.0)
	steps(c, pistol.definition.ads_s + 0.05)
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 0.4)
	keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(pistol.magazine == 14 and sh2.health.hp == Shambler.HP - 35.0, "pistol: one round, 35 HP at 5 m (aimed, chest)")
	var sh3 := await setup(c, tree, Vector3(24.5, 0, 11), 3.0) # target outside the lab, wall between
	pistol = arm(c, "pistol")
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 0.4)
	check.call(pistol.magazine == 14 and sh3.health.hp == Shambler.HP, "the wall stops the bullet; the round is still spent")
	pistol.magazine = 0
	click(c, keys, MOUSE_BUTTON_LEFT)
	check.call(pistol.magazine == 0 and not c.pcombat.combat.busy() and "Empty" in c.notice, "empty magazine: click, nothing fired")
	give(c, "ammo_9mm", 40)
	var empty_commit: float = pistol.definition.reload_empty_s * pistol.definition.RELOAD_COMMIT
	click(c, keys, KEY_R)
	steps(c, empty_commit - 0.1)
	check.call(pistol.magazine == 0, "reload from empty: no rounds before the %.2f s commit (empty reload %.1f s)" % [empty_commit, pistol.definition.reload_empty_s])
	steps(c, 0.2)
	check.call(pistol.magazine == 15 and s.inventory.count("ammo_9mm") == 25, "reload commit moves exactly 15 rounds")
	steps(c, 1.0)
	# A tactical reload (rounds left) is quicker than one from empty.
	pistol.magazine = 5
	var tac_commit: float = pistol.definition.reload_s * pistol.definition.RELOAD_COMMIT
	click(c, keys, KEY_R)
	steps(c, tac_commit + 0.05)
	check.call(pistol.magazine == 15 and tac_commit < empty_commit, "tactical reload commits at %.2f s, before the empty one (%.2f)" % [tac_commit, empty_commit])
	steps(c, 1.0)

	# Shotgun: six pellets for one shell; at 1.2 m all six land (108 HP) and kill.
	var sh4 := await setup(c, tree, Vector3(64, 0, 55), 1.2)
	var gun := arm(c, "shotgun")
	c.player.pitch = -atan2(c.player.eye_position().y - 1.0, 1.2) # aim at the chest
	c.player.apply_look()
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 0.2)
	check.call(gun.magazine == 5 and sh4.health.dead, "shotgun: one shell, six pellets kill at 1.2 m (%.0f HP)" % sh4.health.hp)

	# Rifle: holding LMB fires every 0.1 s (10 rounds in 0.95 s).
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	var rifle := arm(c, "assault_rifle")
	keys[MOUSE_BUTTON_LEFT] = true
	steps(c, 0.95)
	keys.erase(MOUSE_BUTTON_LEFT)
	steps(c, 0.3)
	check.call(30 - rifle.magazine == 10, "rifle held 0.95 s: 10 rounds (%d)" % (30 - rifle.magazine))

	# ---- handling (2026-11-10) ---------------------------------------------------
	# Draw: no shot until the draw time is over.
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	var rf: RefCounted = WeaponInstance.create("assault_rifle", s.run).weapon
	s.inventory.upgrade_bag(12)
	s.inventory.try_add(rf)
	s.inventory.equip(rf.instance_id)
	s.step(DT)
	click(c, keys, MOUSE_BUTTON_LEFT)
	check.call(rf.magazine == 30 and c.pcombat.drawing(s.run.time), "drawing the rifle: a click right away fires nothing")
	steps(c, rf.definition.draw_s)
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 0.05)
	check.call(rf.magazine == 29, "after its %.2f s draw the rifle fires" % rf.definition.draw_s)
	# Headshot: the pistol at the head does x headshot_mult.
	var shh := await setup(c, tree, Vector3(64, 0, 55), 5.0)
	var ph := arm(c, "pistol")
	aim_at(c, keys, 5.0, 1.62)
	steps(c, ph.definition.ads_s + 0.05)
	var hs0: int = c.pcombat.combat.headshots
	click(c, keys, MOUSE_BUTTON_LEFT)
	steps(c, 0.3)
	keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(c.pcombat.combat.headshots == hs0 + 1 and is_equal_approx(shh.health.hp, Shambler.HP - 35.0 * ph.definition.headshot_mult), "pistol headshot: %.1f HP (x%.1f)" % [Shambler.HP - shh.health.hp, ph.definition.headshot_mult])
	# Spread: hip shots scatter inside the cone; fully aimed they stay on it.
	var spread_def: Resource = rf.definition
	var hip_dev := []
	var ads_max := 0.0
	for i in 30:
		var dh := CombatController.cone_dir(Vector3.FORWARD, spread_def.spread_at(0.0), 7000 + i)
		hip_dev.append(rad_to_deg(dh.angle_to(Vector3.FORWARD)))
		ads_max = maxf(ads_max, rad_to_deg(CombatController.cone_dir(Vector3.FORWARD, spread_def.spread_at(1.0), 7000 + i).angle_to(Vector3.FORWARD)))
	var distinct_dev := {}
	for x in hip_dev: distinct_dev[snappedf(x, 0.01)] = true
	check.call(hip_dev.max() <= spread_def.spread_hip_deg + 0.01 and hip_dev.max() > spread_def.spread_hip_deg * 0.6 and distinct_dev.size() > 20, "rifle hip spread: 30 shots inside %.1f deg, scattered (max %.2f)" % [spread_def.spread_hip_deg, hip_dev.max()])
	check.call(ads_max <= spread_def.spread_ads_deg + 0.01, "rifle fully aimed: on the crosshair (max %.2f deg)" % ads_max)
	check.call(CombatController.cone_dir(Vector3.FORWARD, 2.5, 42) == CombatController.cone_dir(Vector3.FORWARD, 2.5, 42), "spread is seeded: the same shot id lands the same way")
	# The shot uses the player's aim progress.
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	var rf2 := arm(c, "assault_rifle")
	check.call(is_equal_approx(c.pcombat.attack_action().cone, rf2.definition.spread_hip_deg), "hip: the shot carries the hip cone")
	keys[MOUSE_BUTTON_RIGHT] = true
	steps(c, rf2.definition.ads_s * 0.5)
	var mid: float = c.pcombat.attack_action().cone
	steps(c, rf2.definition.ads_s * 0.5 + 0.05)
	var full: float = c.pcombat.attack_action().cone
	keys.erase(MOUSE_BUTTON_RIGHT)
	check.call(mid > full and mid < rf2.definition.spread_hip_deg and is_equal_approx(full, rf2.definition.spread_ads_deg), "aiming in narrows the cone (%.2f mid-way, %.2f aimed)" % [mid, full])
	# In play: a hip-fire burst at 15 m scatters off a body; the same burst aimed all lands.
	var landed := {}
	for aimed in [false, true]:
		var tgt := await setup(c, tree, Vector3(64, 0, 55), 15.0)
		tgt.health.max_hp = 100000.0
		tgt.health.hp = 100000.0
		var rb := arm(c, "assault_rifle")
		c.player.pitch = -atan2(c.player.eye_position().y - 1.0, 15.0)
		c.player.apply_look()
		if aimed:
			keys[MOUSE_BUTTON_RIGHT] = true
			steps(c, rb.definition.ads_s + 0.05)
		var hp0: float = tgt.health.hp
		keys[MOUSE_BUTTON_LEFT] = true
		steps(c, 0.95)
		keys.erase(MOUSE_BUTTON_LEFT); keys.erase(MOUSE_BUTTON_RIGHT)
		steps(c, 0.2)
		landed[aimed] = int(round((hp0 - tgt.health.hp) / rb.definition.damage_hp))
		tgt.health.max_hp = Shambler.HP # leave the Shambler as later tests expect
		tgt.health.hp = Shambler.HP
	check.call(landed[true] == 10 and landed[false] < 10, "rifle at 15 m: %d of 10 hip shots land, %d of 10 aimed" % [landed[false], landed[true]])
	# Per-weapon aim-in time and aimed move speed.
	var ads_ticks := {}
	var ads_speed := {}
	for wid in ["pistol", "assault_rifle"]:
		await setup(c, tree, Vector3(64, 0, 40), 30.0)
		var wi := arm(c, wid)
		c.player.pitch = 0.0; c.player.apply_look()
		c.player.yaw = 0.0; c.player.apply_look()
		keys[MOUSE_BUTTON_RIGHT] = true
		var n := 0
		while c.player.aim_t < 1.0 and n < 120:
			s.step(DT)
			n += 1
		ads_ticks[wid] = n
		keys[KEY_W] = true
		steps(c, 1.0)
		ads_speed[wid] = c.player.horizontal_speed()
		keys.erase(KEY_W); keys.erase(MOUSE_BUTTON_RIGHT)
		steps(c, 0.5)
		check.call(absf(n * DT - wi.definition.ads_s) <= DT + 0.001 and absf(ads_speed[wid] - c.player.tuning.run_speed * wi.definition.ads_move_scale) < 0.05, "%s: aims in over %.2f s (%d ticks), aimed walk %.2f m/s (x%.2f)" % [wid, wi.definition.ads_s, n, ads_speed[wid], wi.definition.ads_move_scale])
	check.call(ads_ticks.pistol < ads_ticks.assault_rifle and ads_speed.pistol > ads_speed.assault_rifle, "the pistol aims faster and moves faster aimed than the rifle")

	# No weapon swap mid-action.
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	var bat := arm(c, "baseball_bat")
	var knife: RefCounted = WeaponInstance.create("knife", s.run).weapon
	s.inventory.try_add(knife)
	click(c, keys, MOUSE_BUTTON_LEFT)
	c.equip_slot(2)
	check.call(s.inventory.equipped_id == bat.instance_id, "cannot switch weapons mid-swing")
	steps(c, 1.2)
	c.equip_slot(2)
	check.call(s.inventory.equipped_id == knife.instance_id, "switching works once the swing is over")

	# (The Alt dodge was replaced by the movement dash in R1; see test_movement.gd.)

	# Frag: aim (marker), release, 0.44 s to leave the hand, 2 s fuse, one blast.
	var sh5 := await setup(c, tree, Vector3(64, 0, 55), 4.5)
	give(c, "frag", 2)
	keys[KEY_G] = true; s.step(DT)
	check.call(c.pcombat.aiming_throw and c.pcombat.marker.visible, "holding G aims with a landing marker")
	keys.erase(KEY_G); s.step(DT)
	steps(c, 0.5)
	check.call(s.inventory.count("frag") == 1 and c.hazards.throws.size() == 1, "the frag leaves the hand: one used")
	check.call(c.hazards.explosions.is_empty(), "no blast before the fuse")
	steps(c, 2.0)
	check.call(c.hazards.explosions.size() == 1, "one explosion")
	var hit := {}
	if not c.hazards.explosions.is_empty():
		for h in c.hazards.explosions[0].hits: hit[h.id] = h.amount
	check.call(hit.has("shambler_1") and hit.shambler_1 > 30.0 and hit.shambler_1 < 120.0 and not hit.has("player"), "blast falls off with distance; the thrower at range is unharmed (%s)" % [hit])
	steps(c, 3.0)
	check.call(c.hazards.explosions.size() == 1, "the fuse fires once only")
	# Wall shielding: a blast inside the lab does not reach outside it.
	var behind := await setup(c, tree, Vector3(24, 0, 11), 3.0) # Shambler at x 27, outside the lab
	var blast: Dictionary = c.hazards.explode(Vector3(25.6, 0.1, 11), s.run.time, {"targets": c.hazard_targets(), "los": c.clear_line, "noise": c.noise})
	check.call(blast.hits.all(func(h): return h.id != "shambler_1") and behind.health.hp == Shambler.HP, "the lab wall shields the outside from a blast inside")
	check.call(Hazards.falloff(0.0, 4.0, 0.25) == 1.0 and is_equal_approx(Hazards.falloff(4.0, 4.0, 0.25), 0.25) and Hazards.falloff(4.1, 4.0, 0.25) == 0.0, "blast falloff: full at the centre, 25% at 4 m, none beyond")

	# Molotov fire, on a stationary dummy: 8 HP per 0.5 s while inside, nothing
	# once outside, burns out after 6 s. (A real Shambler walks out of it.)
	var hz := Hazards.new()
	var dummy: Node = preload("res://scripts/combat/health_component.gd").new()
	dummy.max_hp = 200.0
	dummy.faction = "infected"
	c.add_child(dummy)
	var body := {"id": "dummy", "pos": Vector3(5, 1, 5), "radius": 0.3, "health": dummy}
	var ctx := {"targets": [body]}
	hz._ignite(Vector3(5, 0, 5.5), 0.0, ctx)
	var tt := 0.0
	for i in 117: # 1.95 s at 60 Hz
		tt += DT
		hz.tick(DT, tt, ctx)
	check.call(hz.fire_ticks.size() == 4 and is_equal_approx(dummy.hp, 200.0 - 32.0), "fire: 4 ticks of 8 HP in 1.95 s (%d)" % hz.fire_ticks.size())
	body.pos = Vector3(9, 1, 5) # step out of the fire
	for i in 60:
		tt += DT
		hz.tick(DT, tt, ctx)
	check.call(hz.fire_ticks.size() == 4, "outside the fire: no more ticks")
	for i in 300:
		tt += DT
		hz.tick(DT, tt, ctx)
	check.call(hz.fires.is_empty(), "the fire burns out after 6 s")
	dummy.free()
	# A molotov thrown in play does ignite where it lands.
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	give(c, "molotov", 1)
	c.player.pitch = deg_to_rad(-20.0)
	c.player.apply_look()
	keys[KEY_G] = true; s.step(DT); keys.erase(KEY_G); s.step(DT)
	steps(c, 1.2)
	check.call(s.inventory.count("molotov") == 0 and c.hazards.fires.size() == 1, "a thrown molotov lands and starts one fire")

	# Cancel: RMB while aiming keeps the item.
	await setup(c, tree, Vector3(64, 0, 55), 9.0)
	give(c, "molotov", 1)
	keys[KEY_G] = true; s.step(DT)
	keys[MOUSE_BUTTON_RIGHT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_RIGHT)
	keys.erase(KEY_G); steps(c, 1.0)
	check.call(s.inventory.count("molotov") == 1 and c.hazards.throws.is_empty() and c.hazards.fires.is_empty(), "RMB cancels the throw; nothing used")

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
