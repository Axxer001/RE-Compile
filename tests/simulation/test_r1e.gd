extends RefCounted
# R1e: the remaining Apex General Tech (docs/r1e-remaining-movement.md).
# Kept by D1 in the Grimoire build, values rescaled to the spec's pace
# (movement_tuning.gd). Ground rules (step height, constant acceleration,
# damage slow), slides (quick slide, edge slide), fall stun and its cancels
# (edge, corner, climb, mantle, wallhop), the mantle phases (hang, cancel,
# hop, boost, slide surf, auto/insta mantle, no-ma climb, clamber), the climb
# space (zones, mini-bounce, wallbounce, wall push, wallrun, end boost,
# reattach, U-bounce baseline), and slopes (surf, trimp, geo jump).
# Driven through the session with synthetic keys, like play.

const DT := 1.0 / 60.0
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Greybox = preload("res://scripts/world/greybox.gd")

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement()

static func air_at(c: Node3D, tree: SceneTree, at: Vector3, yaw_deg: float, v: Vector3) -> void:
	var p: CharacterBody3D = c.player
	place(c, at, yaw_deg)
	await tree.physics_frame
	c.session.step(DT)
	# Clear the stale "on floor" left by the teleport (and with it the ground snap).
	p.global_position = at
	p.velocity = Vector3(0, 0.01, 0)
	p.move_and_slide()
	p.global_position = at
	p.velocity = v
	p.state = p.Move.AIR
	p.since_floor = 1.0
	p.lurch_t = INF
	p.land_t = 5.0

static func tap(c: Node3D, keys: Dictionary, k: int) -> void:
	keys[k] = true; c.session.step(DT); keys.erase(k)

static func land(c: Node3D) -> void:
	for i in 240:
		c.session.step(DT)
		if c.player.is_on_floor() and c.player.state == c.player.Move.GROUND: break
	steps(c, 3)

static func heading(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, -v.z))

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var p: CharacterBody3D = c.player
	var T: Resource = p.tuning
	check.call(T.step_height == 0.5588 and T.ground_accel == 45.0 and T.bhop_penalty == 3.85 and T.climb_space_h == 3.7338 and T.mini_zone_h == 0.4826 and T.green_zone_h == 1.1938 and T.jump_drop == 6.5024 and T.detach_drop == 3.2512 and T.stun_min_drop == 7.62 and T.stun_max_drop == 20.32, "Apex tuning: 22 hu step, accel 45 [spec], bhop penalty 100 hu/s x1.514, 147/19/47 hu zones, 128/256 hu drops, 300-800 hu stun")

	# ---- ground -------------------------------------------------------------------
	# Constant acceleration: crouch and run gain speed alike from a standstill.
	var early := {}
	for mode in ["crouch", "run"]:
		place(c, Vector3(60, 0, 60), 0.0)
		await tree.physics_frame
		steps(c, 2)
		if mode == "crouch": keys[KEY_CTRL] = true
		steps(c, 2)
		keys[KEY_W] = true
		steps(c, 3)
		early[mode] = p.horizontal_speed()
		keys.erase(KEY_W); keys.erase(KEY_CTRL)
		steps(c, 30)
	check.call(absf(early.crouch - early.run) < 0.01 and absf(early.run - 45.0 * 3.0 * DT) < 0.01, "constant acceleration: 3 ticks in, crouch %.2f = run %.2f m/s [spec]" % [early.crouch, early.run])
	# Quick slide: from a crouch walk, uncrouch + crouch slides as soon as the run passes 0.7 x run speed.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	keys[KEY_CTRL] = true
	keys[KEY_W] = true
	steps(c, 6)
	var t0: float = s.run.time
	keys.erase(KEY_CTRL)
	var slid := false
	for i in 40:
		if p.horizontal_speed() > T.slide_min_ratio * p.run_top() and not keys.has(KEY_CTRL): keys[KEY_CTRL] = true
		s.step(DT)
		if p.state == p.Move.SLIDE:
			slid = true
			break
	keys.erase(KEY_CTRL); keys.erase(KEY_W)
	check.call(slid and s.run.time - t0 < 0.35, "quick slide: crouch walk -> uncrouch, crouch: sliding after %.2f s" % (s.run.time - t0))
	steps(c, 40)
	# Edge slide: slide off the 1 m ledge with Ctrl held: no friction in the air, the slide resumes on landing.
	place(c, Vector3(86, 1.0, 42.5), 0.0)
	await tree.physics_frame
	s.step(DT)
	p.velocity = Vector3(0, 0, -9.0)
	keys[KEY_CTRL] = true
	s.step(DT)
	var entry_at: float = p.slide_entry_at
	var left_edge := 0.0
	var resumed := false
	for i in 90:
		s.step(DT)
		if p.state == p.Move.AIR and p.air_slide and left_edge == 0.0: left_edge = p.horizontal_speed()
		if left_edge > 0.0 and p.state == p.Move.SLIDE and p.is_on_floor():
			resumed = true
			break
	keys.erase(KEY_CTRL)
	check.call(resumed and p.slide_entry_at == entry_at and p.horizontal_speed() > left_edge - 0.5, "edge slide: airborne mid-slide, then the slide resumes on landing (no new entry; %.2f -> %.2f m/s)" % [left_edge, p.horizontal_speed()])
	steps(c, 40)
	# Damage slow: on the ground, damage drops speed to 189 hu/s; not again within 3 s; not in the air.
	place(c, Vector3(60, 0, 74), 0.0)
	await tree.physics_frame
	keys[KEY_W] = true
	steps(c, 40)
	p.health.apply(DamagePacket.new(991001, "test", "infected", 1.0, "bite"), s.run.time)
	s.step(DT)
	var slowed: float = p.horizontal_speed()
	steps(c, 30)
	p.health.apply(DamagePacket.new(991002, "test", "infected", 1.0, "bite"), s.run.time)
	s.step(DT)
	keys.erase(KEY_W)
	check.call(p.damage_slows == 1 and slowed < T.damage_slow_speed + T.ground_accel * DT + 0.05 and p.horizontal_speed() > T.damage_slow_speed + 1.0, "damage slow: hit on the ground at run speed -> %.2f m/s; a second hit 0.5 s later is not slowed (%d slow)" % [slowed, p.damage_slows])
	p.health.reset()
	steps(c, 30)
	# ---- fall stun ----------------------------------------------------------------
	var v20 := sqrt(2.0 * T.gravity * 20.0)
	check.call(p.stun_strength(sqrt(2.0 * T.gravity * 7.0)) == 0.0 and p.stun_strength(sqrt(2.0 * T.gravity * 21.0)) == 1.0 and p.stun_strength(sqrt(2.0 * T.gravity * 14.0)) > 0.0, "stun strength: none from 7 m, full from 21 m [study 300-800 hu]")
	# Flat landing from 20 m: stunned, slowed.
	await air_at(c, tree, Vector3(60, 0.6, 60), 0.0, Vector3(0, -v20, -5.0))
	land(c)
	check.call(p.stuns == 1 and p.stun_q > 0.8 and p.horizontal_speed() < 1.5, "20 m fall onto flat ground: fall stun (strength %.2f), speed cut to %.2f" % [p.stun_q, p.horizontal_speed()])
	steps(c, 70)
	# 6 m: no stun.
	await air_at(c, tree, Vector3(60, 0.6, 60), 0.0, Vector3(0, -sqrt(2.0 * T.gravity * 6.0), 0))
	land(c)
	check.call(p.stuns == 0, "6 m fall: no stun")
	# Corner: landing while touching a wall cancels it.
	await air_at(c, tree, Vector3(119.5, 0.6, 40), -90.0, Vector3(1.0, -v20, 0))
	land(c)
	check.call(p.stuns == 0 and p.stun_cancels == 1, "corner stun-cancel: a 20 m fall landing against the wall is not stunned")
	# Edge: landing on the edge of the 1 m ledge (tilted contact) cancels it.
	await air_at(c, tree, Vector3(86, 1.4, 37.0 - 0.26), 0.0, Vector3(0, -v20, 0))
	land(c)
	check.call(p.stuns == 0, "edge stun-cancel: a 20 m fall onto the ledge's edge is not stunned (landed y %.2f, stuns %d, q %.2f, cancels %d)" % [p.global_position.y, p.stuns, p.stun_q, p.stun_cancels])
	# Climb: falling with W into the tower face slows the fall (no stun); without W, stunned.
	for climb in [true, false]:
		await air_at(c, tree, Vector3(5, 6.0, 43.65), 180.0, Vector3(0, -v20, 0))
		p.baseline_y = 6.0
		if climb: keys[KEY_W] = true
		land(c)
		keys.erase(KEY_W)
		if climb: check.call(p.stuns == 0 and p.climbs >= 1, "climb stun-cancel: attaching to the tower while falling at %.1f m/s slows it (no stun)" % v20)
		else: check.call(p.stuns == 1, "the same fall without climbing: stunned")
		steps(c, 70)
	# Mantle: falling past a ledge with W mantles it, no stun.
	await air_at(c, tree, Vector3(98, 3.4, 43.6), 0.0, Vector3(0, -12.0, 0))
	keys[KEY_W] = true
	land(c)
	keys.erase(KEY_W)
	check.call(p.mantles >= 1 and p.stuns == 0 and absf(p.global_position.y - 3.0) < 0.05, "mantle stun-cancel: falling past the 3 m ledge with W mantles onto it")
	steps(c, 20)
	# Wallhop: meeting a wall at ~35 deg clears an active fall stun.
	place(c, Vector3(110, 0, 0.62), 0.0) # friction 12 stops a coast within about 0.35 m
	await tree.physics_frame
	steps(c, 2)
	p.stun_q = 0.5
	p.stun_left = 0.9
	p.velocity = Vector3(5.7, 0, -4.0) # 35 deg into the north wall
	for i in 20:
		s.step(DT)
		if p.wallhops > 0: break
	check.call(p.wallhops == 1 and p.stun_left == 0.0, "wallhop: meeting a wall at 35 deg clears the fall stun")
	steps(c, 30)

	# ---- mantle phases ------------------------------------------------------------
	# Hang: reaching the 2 m ledge in the air with no input grabs and hangs; W pulls up.
	await air_at(c, tree, Vector3(92, 0.6, 43.45), 0.0, Vector3(0, 6.0, -0.6))
	for i in 45: s.step(DT)
	var hung: bool = p.state == p.Move.MANTLE and String(p.mantle.get("phase", "")) == "hang" and p.hangs == 1
	keys[KEY_W] = true
	for i in 40: s.step(DT)
	keys.erase(KEY_W)
	check.call(hung and absf(p.global_position.y - 2.0) < 0.05, "mantle hang: no input -> hang; W -> pull onto the 2 m ledge")
	steps(c, 10)
	# Cancel from the hang (S) and mantle hop (jump).
	for act in ["cancel", "hop"]:
		await air_at(c, tree, Vector3(92, 0.6, 43.45), 0.0, Vector3(0, 6.0, -0.6))
		for i in 45: s.step(DT)
		if act == "cancel": tap(c, keys, KEY_S)
		else: tap(c, keys, KEY_SPACE)
		if act == "cancel":
			check.call(p.mantle_cancels == 0 and p.state == p.Move.MANTLE and String(p.mantle.get("phase", "")) == "hang", "S in the hang does nothing: still hanging [R13]")
			tap(c, keys, KEY_SPACE) # off the ledge for the next case
		else: check.call(p.mantle_hops == 1 and p.velocity.z > 1.0 and p.velocity.y > 0.0, "mantle hop: jump in the hang pushes off the edge")
		land(c)
	# Mantle boost: crouch in the pull's last 0.15 s (1 m ledge, a pull-only mantle).
	place(c, Vector3(86, 0, 43.4), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	var gw := 0
	while (p.state != p.Move.MANTLE or String(p.mantle.get("phase", "")) != "pull") and gw < 60:
		s.step(DT)
		gw += 1
	steps(c, 11)
	var boost_t: float = s.run.time
	tap(c, keys, KEY_CTRL)
	keys.erase(KEY_W)
	check.call(p.mantle_boosts == 1 and absf(p.horizontal_speed() - T.mantle_boost_speed) < 0.3 and p.slide_entry_at < boost_t - 1.0, "mantle boost: crouch late in the pull -> %.2f m/s over the ledge; no cooldown (the spec slide has none)" % p.horizontal_speed())
	# Slide surf: landing in a slide out of the boost does not count as an entry.
	keys[KEY_CTRL] = true
	var surfed := false
	for i in 60:
		s.step(DT)
		if p.state == p.Move.SLIDE:
			surfed = true
			break
	keys.erase(KEY_CTRL)
	check.call(surfed, "slide surf: Ctrl held out of a mantle boost slides on landing")
	land(c)
	# Auto mantle: holding jump on the ground at the 1 m ledge.
	place(c, Vector3(86, 0, 43.4), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	keys[KEY_SPACE] = true
	for i in 50: s.step(DT)
	keys.erase(KEY_SPACE); keys.erase(KEY_W)
	check.call(p.auto_mantles == 1 and absf(p.global_position.y - 1.0) < 0.05, "auto mantle: holding jump at the 1 m ledge mantles it")
	# Insta-mantle: standing still holding jump at the 0.4 m curb (overwalkable: below the 0.56 m step).
	place(c, Vector3(72.0, 0, Greybox.CURB.z[1] + 0.35), 0.0)
	await tree.physics_frame
	steps(c, 3)
	keys[KEY_SPACE] = true
	for i in 30: s.step(DT)
	keys.erase(KEY_SPACE)
	check.call(p.insta_mantles == 1 and p.global_position.y > 0.25, "insta-mantle: below 1 hu/s, holding jump mantles a step-height obstacle")
	steps(c, 10)
	# No-ma climb: W+D with the view turned 10 deg right: the input is 55 deg off the wall -> a climb, no mantle.
	place(c, Vector3(92, 0, 43.4), -10.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true; keys[KEY_D] = true
	tap(c, keys, KEY_SPACE)
	for i in 20: s.step(DT)
	var noma: bool = p.climbs >= 1 and p.mantles == 0
	keys.erase(KEY_W); keys.erase(KEY_D)
	check.call(noma, "no-ma climb: input 55 deg off the 2 m ledge's face -> a climb (%d), no mantle (%d)" % [p.climbs, p.mantles])
	land(c)
	# Clamber: one jump at the two-tier block chains a second pull to its 3.6 m top.
	place(c, Vector3(106, 0, 42.4), 0.0)
	await tree.physics_frame
	steps(c, 2)
	keys[KEY_W] = true
	tap(c, keys, KEY_SPACE)
	for i in 120:
		s.step(DT)
		if p.state == p.Move.GROUND and p.global_position.y > 3.0: break
	keys.erase(KEY_W)
	check.call(p.clambers == 1 and absf(p.global_position.y - 3.6) < 0.05, "clamber: the 2 m tier's pull chains onto the 3.6 m tier (y %.2f)" % p.global_position.y)
	steps(c, 10)

	# ---- climb space ----------------------------------------------------------------
	check.call(p.climb_zone(0.2) == "mini" and p.climb_zone(0.4826) == "mini" and p.climb_zone(0.49) == "green" and p.climb_zone(1.19) == "green" and p.climb_zone(1.2) == "neutral" and p.climb_zone(3.8) == "above" and p.climb_zone(-0.1) == "below", "climb zones: mini to 19 hu, green to 47 hu, neutral to the 147 hu cutoff [study]")
	# Jumps off the east wall by zone: [height above baseline, expected counter].
	var ups := {}
	for zc in [[0.2, "mini_bounces"], [0.55, "bounces"], [1.1, "bounces"], [2.0, "wall_pushes"]]:
		await air_at(c, tree, Vector3(119.45, float(zc[0]), 40), -90.0, Vector3.ZERO)
		p.baseline_y = 0.0
		keys[KEY_W] = true
		s.step(DT)
		s.step(DT)
		var on_wall: bool = p.state == p.Move.WALLCLIMB
		var b0: float = p.baseline_y
		tap(c, keys, KEY_SPACE)
		keys.erase(KEY_W)
		ups[zc[0]] = p.velocity.y
		var out: float = -p.velocity.x
		var expect_out: float = T.mini_bounce_out if zc[1] == "mini_bounces" else T.bounce_out
		var expect_drop: float = T.detach_drop if zc[1] == "mini_bounces" else T.jump_drop
		check.call(on_wall and int(p.get(zc[1])) == 1 and absf(out - expect_out) < 0.3 and absf((b0 - p.baseline_y) - expect_drop) < 0.01, "climb jump at %.2f m above the baseline: %s, %.2f m/s off the wall, climb space down %.2f m" % [zc[0], zc[1], out, b0 - p.baseline_y])
		land(c)
	check.call(ups[0.55] > ups[1.1] + 1.0 and absf(ups[2.0]) < 0.5 and ups[0.2] > 0.0, "zone heights: green low %.2f > green high %.2f; wall push %.2f (none); mini-bounce %.2f" % [ups[0.55], ups[1.1], ups[2.0], ups[0.2]])
	# Reattach: right after a green jump the climb space is below you: no attach.
	await air_at(c, tree, Vector3(119.45, 0.7, 40), -90.0, Vector3.ZERO)
	p.baseline_y = 0.0
	keys[KEY_W] = true
	steps(c, 2)
	tap(c, keys, KEY_SPACE)
	check.call(not p.can_attach(Vector3.LEFT), "after a wallbounce the climb space has dropped 6.5 m: no reattach up here")
	keys.erase(KEY_W)
	land(c)
	# U-bounce mechanism: falling below the baseline drags it down with you.
	await air_at(c, tree, Vector3(60, 5.0, 60), 0.0, Vector3.ZERO)
	p.baseline_y = 8.0
	s.step(DT)
	check.call(p.baseline_y <= p.global_position.y + 0.01, "below the baseline it follows you down (U-bounce)")
	land(c)
	# Wallrun: D along the run wall with the view 10 deg off it: sideways climb up to 258 hu/s x1.514, about 1 s.
	await air_at(c, tree, Vector3(40.55, 2.0, 12), 100.0, Vector3.ZERO)
	p.baseline_y = 1.0
	keys[KEY_D] = true
	var peak := 0.0
	var run_t := 0
	for i in 90:
		s.step(DT)
		if p.state == p.Move.WALLCLIMB:
			peak = maxf(peak, p.horizontal_speed())
			run_t += 1
	keys.erase(KEY_D)
	check.call(p.wallruns >= 1 and peak > T.wallrun_speed - 0.3 and run_t * DT <= 1.2 and run_t * DT > 0.6, "wallrun: %.2f m/s along the wall for %.2f s" % [peak, run_t * DT])
	land(c)

	# ---- slopes -----------------------------------------------------------------------
	# Surf: along the 60 deg wedge at 10 m/s holding D into it stays up longer than without.
	var sz: float = Greybox.SIZE.y - (2.5 / tan(deg_to_rad(Greybox.SURF.angle))) + 0.35
	var surf_y := {}
	for hold in [true, false]:
		await air_at(c, tree, Vector3(74, 2.5, sz), -90.0, Vector3(10.0, 0, 0))
		if hold: keys[KEY_D] = true
		for i in 45: s.step(DT)
		surf_y[hold] = p.global_position.y
		var surf_v: float = p.horizontal_speed()
		keys.erase(KEY_D)
		if hold: check.call(surf_v > 9.0, "surf: still at %.2f m/s along the slope after 0.75 s (no friction)" % surf_v)
		land(c)
	check.call(surf_y[true] > surf_y[false] + 0.3, "surf: holding D into the slope keeps you up (y %.2f vs %.2f)" % [surf_y[true], surf_y[false]])
	# Trimp: airborne at 12 m/s into the 55 deg ramp turns speed upward; a jump right after is a geo jump.
	for geo in [false, true]:
		await air_at(c, tree, Vector3(19, 0.15, 51.0), 0.0, Vector3(0, 0, -12.0))
		var vy_peak := -INF
		for i in 20:
			s.step(DT)
			vy_peak = maxf(vy_peak, p.velocity.y)
			if p.since_surface == 0.0 and geo:
				tap(c, keys, KEY_SPACE)
				vy_peak = maxf(vy_peak, p.velocity.y)
				break
		if geo: check.call(p.geo_jumps == 1 and vy_peak > T.jump_speed + 1.0, "geo jump: jumping off the trimp adds the jump on top (vy %.2f)" % vy_peak)
		else: check.call(vy_peak > 3.0, "trimp: 12 m/s into the 55 deg ramp turns into %.2f m/s upward" % vy_peak)
		land(c)

	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
