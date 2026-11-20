extends RefCounted
const PageLibrary = preload("res://scripts/core/page_library.gd")
# Sir's R12 playtest fixes (handoff §10), in the arena:
#   3D melee (no hit on a player 3 m up; the hitbox follows crouch), the 3D
#   pounce (a leap that reaches a player in mid-air or on high ground),
#   Sprites climbing ledges, Scorched Slow on movement, unequip on every slot
#   (an empty attack slot casts nothing), status icons for the player and the
#   Sprites, and the pause menu's New game (wipe progress).

const DT := 1.0 / 60.0
const Sprite = preload("res://scripts/actors/blighted_sprite.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put_player(c: Node3D, at: Vector3, yaw_deg := 0.0) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()
	p.reset_movement()

static func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# Hold the player still (in the air, say) for `seconds`, the world running.
static func hold(c: Node3D, at: Vector3, seconds: float, until_hit := false) -> float:
	var top := -INF
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	for i in int(round(seconds / DT)):
		c.player.global_position = at
		c.player.velocity = Vector3.ZERO
		c.session.step(DT)
		top = maxf(top, sh.global_position.y)
		if until_hit and c.player.health.hp < c.player.health.max_hp: break
	return top

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"])
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	var p: CharacterBody3D = c.player
	var h: Node = p.health

	# ---- 3D melee [R12 bug 1] ----------------------------------------------------------------
	# The 3 m ledge (x 96-100, z 37-43): the player on top at its south edge, the Sprite on the ground below.
	sh.reset_to(Vector3(98, 0, 43.6), 0.0)
	sh.inert = true
	put_player(c, Vector3(98, 3.0, 42.6), 180.0)
	await tree.physics_frame
	s.step(DT)
	var flat_d: float = sh.distance_to_player(p)
	sh._strike(p, h, s.run.time, c.clear_line)
	check.call(flat_d < Sprite.STRIKE_REACH and is_equal_approx(h.hp, 1000.0) and not sh.in_reach(p, Sprite.WINDUP_R), "a player 3 m up (%.1f m across) is out of melee reach: no hit from below [R12]" % flat_d)
	sh.reset_to(Vector3(60, 0, 61.0), 0.0)
	sh.inert = true
	put_player(c, Vector3(60, 0, 60.0))
	await tree.physics_frame
	s.step(DT)
	sh._strike(p, h, s.run.time, c.clear_line)
	check.call(is_equal_approx(h.hp, 970.0), "on the same level, 1 m away: the strike lands (hp %.0f)" % h.hp)
	h.reset()
	# The hitbox follows the controller's capsule: crouched, the top drops to 0.9 m.
	p.crouching = true
	p._apply_height(p.CROUCH_HEIGHT)
	var ax: Array = Sprite.capsule_axis(p)
	var tg: Dictionary = c.hazard_targets().filter(func(t): return t.id == "player")[0]
	var crouch_ok: bool = absf((ax[1] as Vector3).y - p.global_position.y - 0.6) < 0.01 and absf(tg.b.y - p.global_position.y - 0.6) < 0.01
	p.crouching = false
	p._apply_height(p.STAND_HEIGHT)
	tg = c.hazard_targets().filter(func(t): return t.id == "player")[0]
	check.call(crouch_ok and absf(tg.b.y - p.global_position.y - 1.5) < 0.01 and (p.find_child("*", false, false) != null), "the hit capsule is the controller's: its top at 0.6 m crouched, 1.5 m standing")
	# A player standing on a 1 m crate is still in reach of a Sprite beside it (its body overlaps).
	put_player(c, Vector3(60, 1.0, 60.0))
	check.call(sh.vertical_gap(p) == 0.0 and sh.in_reach(p, Sprite.WINDUP_R), "a player 1 m up still overlaps a Sprite's body: in reach")

	# ---- the pounce's straight jump-dash [Sir, 2026-11-15] -------------------------------------
	# A low hop along the ground at 20 m/s (no longer a ballistic leap aimed in 3D).
	h.reset()
	s.stats.modifiers.clear()
	sh.reset_to(Vector3(60, 0, 59), 180.0) # facing away: any facing
	put_player(c, Vector3(60, 0.5, 50)) # 9 m away, half a metre up (a small jump)
	await tree.physics_frame
	sh.alert_to(p.global_position)
	var top: float = hold(c, Vector3(60, 0.5, 50), 3.0, true) # the 2 s crouch, then the dash
	check.call(sh.pounces == 1 and sh.pounce_hits == 1 and is_equal_approx(h.hp, 940.0) and top < 1.0, "a player half a metre up: the low dash (Sprite up to %.2f m) still lands the pounce (hp %.0f)" % [top, h.hp])
	# High ground: the player on the 3 m ledge, the Sprite 9 m out on the ground: the dash stays low.
	h.reset()
	s.stats.modifiers.clear()
	sh.reset_to(Vector3(98, 0, 49.5), 0.0)
	put_player(c, Vector3(98, 3.0, 40.5))
	await tree.physics_frame
	sh.alert_to(p.global_position)
	top = -INF # the dash itself (afterwards it may climb up the ledge like any walker)
	for i in int(round(3.0 / DT)):
		p.global_position = Vector3(98, 3.0, 40.5)
		p.velocity = Vector3.ZERO
		s.step(DT)
		if sh.state == Sprite.State.DIVE: top = maxf(top, sh.global_position.y)
		if sh.pounces >= 1 and sh.state != Sprite.State.DIVE and sh.state != Sprite.State.CHARGE: break
	check.call(sh.pounces >= 1 and sh.pounce_hits == 0 and is_equal_approx(h.hp, 1000.0) and top < 2.0, "a player on a 3 m ledge: the straight dash cannot reach him up there (Sprite up to %.2f m)" % top)
	# Still dodgeable: a sidestep after the launch makes it miss and stop where its line ends.
	h.reset()
	sh.reset_to(Vector3(60, 0, 59), 180.0)
	put_player(c, Vector3(60, 0, 50))
	await tree.physics_frame
	sh.alert_to(p.global_position)
	hold(c, Vector3(60, 0, 50), 2.05)
	var dove: bool = sh.state == Sprite.State.DIVE
	hold(c, Vector3(63, 0, 50), 1.2)
	check.call(dove and sh.pounces == 1 and sh.pounce_hits == 0 and h.hp >= 970.0 and sh.state != Sprite.State.DIVE, "a sidestep after the launch: the dash misses and ends (a melee strike may follow, hp %.0f)" % h.hp)

	# ---- climbing [R12] -------------------------------------------------------------------------
	# The 2 m ledge (x 90-94, z 37-43): the Sprite walks to its face and climbs up to the player.
	h.reset()
	sh.reset_to(Vector3(92, 0, 48), 180.0)
	put_player(c, Vector3(92, 2.0, 37.6)) # the ledge's far edge: out of reach from below
	await tree.physics_frame
	sh.alert_to(p.global_position)
	sh.pounce_ready = s.run.time + 30.0 # walking only
	var up_t := -1.0
	for i in int(round(6.0 / DT)):
		p.global_position = Vector3(92, 2.0, 37.6)
		p.velocity = Vector3.ZERO
		s.step(DT)
		if up_t < 0.0 and sh.global_position.y > 1.9 and sh.is_on_floor(): up_t = s.run.time
		if h.hp < 1000.0: break
	check.call(sh.climbs >= 1 and up_t > 0.0 and h.hp < 1000.0, "a Sprite climbs the 2 m ledge and strikes the player up there (climbs %d, hp %.0f)" % [sh.climbs, h.hp])
	check.call(not c.nav.find_path(Vector3(92, 0, 48), Vector3(92, 0, 40)).path.any(func(w): return w.z > 37.5 and w.z < 42.5) and c.nav_climb.find_path(Vector3(92, 0, 48), Vector3(92, 0, 40)).ok, "walkers route round the ledge; the Sprites' grid climbs over it")
	var tall_blocked: bool = c.nav_climb.blocked(c.nav_climb.cell_of(Vector3(40, 0, 12)))
	check.call(tall_blocked, "a 6 m wall is too tall to climb (blocked on the Sprites' grid)")

	# ---- Scorched Slow on movement [R12] ------------------------------------------------------
	h.reset()
	sh.reset_to(Vector3(69, 0, 70), 0.0) # a diagonal chase: both ground axes slowed
	put_player(c, Vector3(60, 0, 58))
	await tree.physics_frame
	sh.alert_to(p.global_position)
	sh.pounce_ready = s.run.time + 30.0
	c.effects.apply(sh.enemy_id, "Scorched Slow", 2.0, s.run.time, "player")
	s.step(DT)
	var a0: Vector3 = sh.global_position
	for i in 30:
		put_player(c, Vector3(60, 0, 58))
		s.step(DT)
	var slow_d := flat(sh.global_position).distance_to(flat(a0))
	check.call(slow_d < Sprite.SPEED * 0.5 * 0.1 + 0.05 and slow_d > 0.1, "Scorched Slow: it chases at 10%% speed (%.2f m in 0.5 s)" % slow_d)

	# ---- status icons [R12] ---------------------------------------------------------------------
	c.publish(DT)
	await tree.process_frame
	var enemy_icons: Array = sh.status_ids
	check.call(enemy_icons == ["Scorched Slow"] and sh.status_row.visible, "the Sprite shows its effect icons under its HP bar (%s)" % str(enemy_icons))
	c.effects.apply(sh.enemy_id, "Burn", 5.0, s.run.time, "player")
	c.publish(DT)
	check.call(sh.status_ids == ["Scorched Slow", "Burn"], "two effects: two icons (%s)" % str(sh.status_ids))
	var SI = preload("res://scripts/ui/status_icons.gd")
	var all_tex: bool = SI.ICONS.keys().all(func(k): return SI.texture(k) != null and SI.texture(k).get_width() == 128)
	var row_tex: bool = sh.status_row.get_children().all(func(n): return n is Sprite3D and n.texture != null)
	check.call(all_tex and row_tex, "every status has its Akami icon (CC0, 128 px); the Sprite's row draws them")
	c.effects.clear_target(sh.enemy_id)
	c.publish(DT)
	check.call(sh.status_ids.is_empty() and not sh.status_row.visible, "effects gone: no icons")
	var pc: Node3D = c.pcombat
	pc.ready_at.erase("spell_2")
	pc.use_slot("spell_2", Vector2.ZERO, s.run.time) # Cultivate
	c.concuss(s.run.time + 1.5, 0.2)
	c.publish(DT)
	var ids: Array = c.hud.status_ids()
	steps(c, 0.75)
	c.publish(DT)
	var tile: Control = c.hud.status_row.get_child(ids.find("Concuss"))
	var tile_icon: bool = (tile.get_node("Icon") as TextureRect).texture == SI.texture("Concuss") and (tile.get_node("Glyph") as Label).text == ""
	var gone: float = tile.get_meta("gone", 0.0)
	check.call(tile_icon and "Cultivate" in ids and "Concuss" in ids and absf(gone - 0.5) < 0.05, "player buffs and debuffs under the bars %s, each with a time sweep (Concuss %.2f gone half-way)" % [str(ids), gone])
	s.stats.modifiers.clear()

	# ---- unequip [R12 bug 2] --------------------------------------------------------------------
	var gp: CanvasLayer = c.grimoire_panel
	s.handle_action("grimoire")
	gp.show_tab("grimoire")
	var has_buttons: bool = gp.page_control("unequip_spell_1") != null and gp.page_control("unequip_spell_2") != null
	var r1: String = gp.unequip("spell_1")
	var r2: String = gp.unequip("spell_2")
	check.call(has_buttons and r1 == "ok" and r2 == "ok" and pc.loadout.spell_1 == null and pc.loadout.spell_2 == null and pc.page == null and gp.page_control("unequip_spell_1") == null, "every equipped slot has an Unequip button; pages 1 and 2 empty")
	s.handle_action("grimoire")
	var b0: int = pc.basic_casts
	var s0: int = pc.special_casts
	var keys := {MOUSE_BUTTON_LEFT: true, MOUSE_BUTTON_RIGHT: true}
	var saved_m: Callable = s.input.mouse_source
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	steps(c, 0.5)
	s.input.mouse_source = saved_m
	check.call(pc.basic_casts == b0 and pc.special_casts == s0 and c.projectiles.shots.is_empty(), "an empty attack slot: LMB and RMB cast nothing")
	pc.equip("spell_3", s.grimoire.page("cultivate"))
	pc.ready_at.erase("spell_3")
	var n_cult: int = int(pc.casts.get("cultivate", 0))
	var kq := {KEY_3: true}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return kq.get(k, false)
	s.step(DT)
	kq.clear()
	steps(c, 1.05) # two leaves to page 3
	var lm := {MOUSE_BUTTON_LEFT: true}
	s.input.mouse_source = func(b: int) -> bool: return lm.get(b, false)
	s.step(DT)
	s.input.mouse_source = saved_m
	s.input.key_source = saved_k
	s.step(DT)
	check.call(int(pc.casts.get("cultivate", 0)) == n_cult + 1, "page 3 + LMB still casts a skill with no attack page equipped")

	# ---- New game (wipe progress) [R12] ------------------------------------------------------------
	s.restart()
	await tree.physics_frame
	for id in PageLibrary.IDS: s.meta.unlock(id)
	s.meta.set_rank("D")
	s.meta.chant_tier["magic_pow"] = 3
	var pm: CanvasLayer = c.pause_menu
	s.handle_action("pause")
	pm.buttons.restart.pressed.emit()
	await tree.physics_frame
	var kept: bool = s.meta.rank == "D" and s.meta.unlocked.size() == PageLibrary.IDS.size() and s.progression.rank == "D"
	s.handle_action("pause")
	pm.buttons.new_game.pressed.emit()
	var armed: bool = pm.wipe_armed and pm.visible and s.meta.rank == "D" and pm.buttons.new_game.text.begins_with("Confirm")
	pm.buttons.new_game.pressed.emit()
	await tree.physics_frame
	check.call(kept, "Restart run keeps the profile (rank D, every page)")
	check.call(armed and s.meta.rank == "E" and s.meta.unlocked == s.meta.START_PAGES and s.meta.chant_tier.is_empty() and s.progression.rank == "E" and s.progression.level == 1 and not s.paused() and not pm.visible, "New game: the first click arms it, the second wipes pages, rank and chant tiers and starts from zero")
	s.handle_action("pause")
	pm.buttons.new_game.pressed.emit()
	pm.buttons.resume.pressed.emit()
	s.handle_action("pause")
	check.call(not pm.wipe_armed and pm.buttons.new_game.text == pm.WIPE_TEXT, "any other choice (or reopening) disarms it")
	pm.buttons.resume.pressed.emit()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
