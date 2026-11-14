extends RefCounted
# Buffs and debuffs together [Sir, 2026-11-14]: every enemy debuff shows a marker
# (an icon over the Sprite or training dummy, drawn through grass); with every
# debuff on one enemy and many buffs on the player, nothing fights: each effect
# keeps its own icon and look, the slows take the strongest (never stack or
# cancel), stat buffs multiply, one source's immunity never cuts another's
# short, and clearing one effect leaves the rest intact.

const DT := 1.0 / 60.0
const GS = preload("res://scripts/combat/gambler_service.gd")
const EffectSystem = preload("res://scripts/core/effect_system.gd")
const StatusIcons = preload("res://scripts/ui/status_icons.gd")
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
	s.progression.rank = "D"
	var pc: Node3D = c.pcombat
	var p: CharacterBody3D = c.player
	var g: RefCounted = c.gambler
	p.global_position = Vector3(60, 0, 50)
	steps(c, 0.2)
	var now: float = s.run.time

	# Every enemy debuff has its own icon file.
	var debuffs: Array = EffectSystem.DEFS.keys().filter(func(k): return EffectSystem.kind_of(k) == "debuff" and k != "Gambling Addiction" and k != "All In: Bust" and k != "Concuss")
	var files := {}
	for k in debuffs: files[k] = String(StatusIcons.icon(k).get("file", ""))
	check.call(debuffs.all(func(k): return files[k] != "" and StatusIcons.texture(k) != null), "every enemy debuff has an icon: %s" % str(files))

	# One Sprite with every debuff at once.
	var e: CharacterBody3D = c.enemies.values()[0]
	e.reset_to(p.global_position + Vector3(0, 0, -8), 0.0)
	e.inert = true
	e.health.max_hp = 1.0e6
	e.health.reset()
	var all_ids := ["Burn", "Scorched Slow", "Phoenix Concuss", "Pocket Change", "Heavy Pockets"]
	for k in all_ids: c.effects.apply(e.enemy_id, k, 10.0, now, "player", 100.0)
	steps(c, 2.0 * DT)
	c.publish(DT)
	var icons: Array = e.status_row.get_children()
	var xs: Array = icons.map(func(n): return (n.offset.x * n.pixel_size) if n is Sprite3D else (n.offset.x * n.pixel_size))
	var apart := true
	for i in range(1, xs.size()):
		if float(xs[i]) - float(xs[i - 1]) < StatusIcons.ICON_M - 0.001: apart = false
	var through: bool = icons.all(func(n): return n.no_depth_test)
	check.call(e.status_ids.size() == 5 and all_ids.all(func(k): return k in e.status_ids) and icons.size() == 5 and apart and through and e.status_row.visible, "a Sprite with all 5 debuffs shows 5 icons side by side, never overlapping, seen through grass")
	var slow_m: float = minf(c.projectiles.SCORCHED_SLOW.mult, minf(c.spells.FLIGHT.concuss_mult, g.heavy_mult(e.enemy_id, s.run.time)))
	check.call(is_equal_approx(e.speed_mult, slow_m) and is_equal_approx(e.atk_mult, c.spells.FLIGHT.concuss_mult), "the slows don't stack or cancel: the strongest one sets the speed (x%.2f); Concuss sets the attack speed" % e.speed_mult)
	var looks: bool = e.slow_fx != null and e.slow_fx.visible and e.burning and e.has_meta("gfx_pocket_change") and e.get_meta("gfx_pocket_change").visible and e.has_meta("gfx_pile") and e.get_meta("gfx_pile").visible
	var pocket_y: float = e.get_meta("gfx_pocket_change").position.y if e.has_meta("gfx_pocket_change") else 0.0
	check.call(looks and pocket_y > e.BAR_Y + 0.3, "every debuff's look shows at once (fire area, Burn, Pocket Change above the HP bar at %.2f m, the coin pile)" % pocket_y)
	c.effects.active[e.enemy_id].erase("Scorched Slow")
	steps(c, 2.0 * DT)
	c.publish(DT)
	check.call(e.status_ids.size() == 4 and not "Scorched Slow" in e.status_ids and not e.slow_fx.visible and e.burning and e.get_meta("gfx_pocket_change").visible and is_equal_approx(e.speed_mult, minf(0.2, g.heavy_mult(e.enemy_id, s.run.time))), "clearing one debuff removes only its icon and look; the rest stay")
	c.effects.clear_target(e.enemy_id)
	steps(c, 2.0 * DT)
	c.publish(DT)
	check.call(e.status_ids.is_empty() and not e.status_row.visible and not e.burning and not e.get_meta("gfx_pocket_change").visible and is_equal_approx(e.speed_mult, 1.0), "all cleared: no icons, no looks, full speed")

	# Many buffs on the player, and a debuff.
	g.reset()
	now = s.run.time
	var pow0: float = pc._pow(now)
	pc._cultivate(s.grimoire.page("cultivate"), now)
	g.roll(now, 5)
	g.land(now)
	g.roll(now, 6)
	g.land(now)
	s.stats.add_modifier(GS.ALL_IN_WIN_ID, "magic_pow", 3.0, 0.0, now + 10.0)
	c.concuss(now + 2.0, 0.2)
	steps(c, DT)
	var t: float = s.run.time
	var want: float = pow0 * pc.CULTIVATE.magic_pow[0] * 2.0 * 6.0 * 3.0
	var ids: Array = c.player_statuses(t).map(func(x): return x.id)
	var uniq := {}
	for i in ids: uniq[i] = true
	check.call(absf(pc._pow(t) - want) < 0.01 and uniq.size() == ids.size() and ["Cultivate", "Gambler's High", "Jackpot", "All In: Won", "Concuss"].all(func(k): return k in ids), "buffs together multiply (Pow x%.1f) and each shows once beside the debuff: %s" % [pc._pow(t) / pow0, str(ids)])
	c.publish(DT)
	var auras: Array = ["gamblers_high", "jackpot", "all_in_won"].filter(func(k): return c._gfx.has(k) and c._gfx[k].visible)
	var scenes := {}
	for k in auras: scenes[String(c.vfx.LOOPS[k].scene)] = true
	check.call(auras.size() == 3 and scenes.size() == 3 and c.vfx.LOOPS.gamblers_high.scene != c.vfx.LOOPS.sage.scene, "each buff keeps its own aura (3 rings, none shared with Sage Arts' motes)")
	g.strip_buffs(t)
	check.call(not g.has_buff(t) and c.player_statuses(t).any(func(x): return x.id == "Concuss") and is_equal_approx(s.stats.value("mov_spd", t), s.stats.base_value("mov_spd") * 0.2), "stripping the buffs leaves the debuff in place")
	s.stats.remove_sources(["concuss"])

	# Immunity from one source never cuts another short.
	var h: Node = p.health
	h.grant_immunity(t + 10.0, ["*"], -INF, "all_in")
	h.grant_immunity(t + 0.2, ["*"], t, "dash") # a dash's i-frames
	h.grant_immunity(t + 0.1, ["*"], -INF, "flight") # Flight ending
	steps(c, 1.0)
	var hit: String = h.apply(DamagePacket.new(995001, "sprite_x", "infected", 5.0, "bite"), s.run.time)
	check.call(hit == "immune", "All In's 10 s Invincibility survives a dash and Flight's end (each source has its own window)")
	h.reset()
	g.reset()
	pc.reset()

# The Training Field lives in the forest world (the arena run has none).
static func run_dummies(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	# Training dummies show their debuffs too.
	var tf: Node3D = c.training
	tf.enter()
	await tree.physics_frame
	var d: Dictionary = tf.dummies[0]
	for k in ["Burn", "Pocket Change", "Heavy Pockets"]: c.effects.apply(String(d.id), k, 10.0, s.run.time, "player", 100.0)
	c.publish(DT)
	var drow: Node3D = d.get("status_row")
	check.call(drow != null and drow.visible and drow.get_child_count() == 3 and d.body.has_meta("gfx_pocket_change") and d.body.get_meta("gfx_pocket_change").visible, "a training dummy shows its debuff icons and marks too")
	c.effects.clear_target(String(d.id))
	c.publish(DT)
	check.call(not drow.visible and not d.body.get_meta("gfx_pocket_change").visible, "and they clear with the debuffs")
	tf.leave()
	await tree.physics_frame
	c.effects.clear_target(String(d.id))

