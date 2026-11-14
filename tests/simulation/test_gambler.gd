extends RefCounted
# The Gambler set [Sir, 2026-11-14; docs/plan-gambler-set.md]: Let it Ride (seeded
# rolls, the low-roll strip and 3 s cooldown, High / Jackpot stacking and refresh,
# the streak into Gambling Addiction, Addiction's gating, Pow x0.1 last, Mov +50%,
# no cooldown, no stats, the way out), Heads or Tails (Heads: one enemy, 80%, 30 m
# at 15 m/s; Tails: 20 m, 120%, Pocket Change and its refresh; the bounce chain),
# Where are my Coins? (+1 a kill to 10, no coins under Heavy Pockets, the spill on
# a buff, the 10 s decay, off in Addiction), and the HUD (die, coins, tint).

const DT := 1.0 / 60.0
const GS = preload("res://scripts/combat/gambler_service.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func put(c: Node3D, id: String, at: Vector3) -> CharacterBody3D:
	var e: CharacterBody3D = c.enemies[id]
	e.reset_to(at, 0.0)
	e.inert = true
	e.health.max_hp = 1.0e6
	e.health.reset()
	return e

static func hits(c: Node3D, kind: String) -> Array:
	return c.gambler.hits.filter(func(h): return h.kind == kind)

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
	var ids: Array = c.enemies.keys()
	var home := Vector3(60, 0, 50)
	var reset_player := func() -> void:
		p.global_position = home
		p.velocity = Vector3.ZERO
		p.yaw = deg_to_rad(-90.0)
		p.pitch = 0.0
		p.apply_look()
	reset_player.call()
	steps(c, 0.2)
	var pages := ["heads_or_tails", "where_are_my_coins", "let_it_ride", "all_in"]
	check.call(pages.all(func(id): return s.grimoire.is_unlocked(id) and s.grimoire.page(id).rank_req == "D"), "the Gambler pages are unlocked from the start, all rank D")
	var now := func() -> float: return s.run.time

	# ---- Let it Ride ---------------------------------------------------------------------------------
	var lr: Resource = s.grimoire.page("let_it_ride")
	check.call(pc.equip("spell_1", lr) == "ok" and lr.mp_cost == 0.0, "Let it Ride equips in a spell slot and costs no MP")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 0xD1CE
	b.seed = 0xD1CE
	var seq_a := []
	var seq_b := []
	for i in 12:
		seq_a.append(a.randi_range(1, 6))
		seq_b.append(b.randi_range(1, 6))
	var first_rolls := []
	for i in 12: first_rolls.append(g.roll(now.call()).face)
	check.call(seq_a == seq_b and first_rolls == seq_a and first_rolls.all(func(f): return f >= 1 and f <= 6), "the die has its own seeded sequence: %s" % str(first_rolls))
	g.reset()
	s.stats.remove_sources(GS.BUFF_SOURCES) # the 12 rolls' buffs
	var pow0: float = pc._pow(now.call())
	var atk0: float = s.stats.value("atk_spd", now.call())
	var mov0: float = s.stats.value("mov_spd", now.call())
	var mas0: float = s.stats.value("spell_mastery", now.call())
	g.forced = [4]
	var r1: String = pc.use_slot("spell_1", Vector2.ZERO, now.call())
	g.land(now.call()) # the die lands (its effects wait for it)
	var t: float = now.call()
	var high_ok: bool = is_equal_approx(pc._pow(t), pow0 * 2.0) and is_equal_approx(s.stats.value("atk_spd", t), minf(atk0 * 1.3, 12.0)) and is_equal_approx(s.stats.value("mov_spd", t), minf(mov0 * 1.3, 22.0)) and is_equal_approx(s.stats.value("spell_mastery", t), mas0 + 0.2)
	check.call(r1 == "ok" and g.last_roll.outcome == "high" and high_ok and absf(g.buff_left(GS.HIGH_ID, t) - 20.0) < 0.01, "a 4: Gambler's High for 20 s (+100%% Pow, +30%% Atk Spd and Mov Spd, +20%% Mastery) %s" % str([r1, g.last_roll, pc._pow(t) / pow0, s.stats.value("atk_spd", t) / atk0, s.stats.value("mov_spd", t) / mov0, s.stats.value("spell_mastery", t) - mas0, g.buff_left(GS.HIGH_ID, t)]))
	check.call(absf(pc.remaining("spell_1", t) - 5.0) < 0.01, "Let it Ride's cooldown: 5 s")
	# [Sir, 2026-11-14] The die finishes rolling before the result takes effect.
	s.stats.remove_sources(GS.BUFF_SOURCES)
	pc.ready_at.erase("spell_1")
	g.forced = [5]
	pc.use_slot("spell_1", Vector2.ZERO, now.call())
	var early: bool = g.rolling() and g.buff_left(GS.HIGH_ID, now.call()) == 0.0 and is_equal_approx(pc._pow(now.call()), pow0)
	pc.ready_at.erase("spell_1")
	var again: String = pc.use_slot("spell_1", Vector2.ZERO, now.call())
	steps(c, 0.5)
	var mid: bool = g.rolling() and g.buff_left(GS.HIGH_ID, now.call()) == 0.0
	steps(c, 0.5)
	check.call(early and again == "rolling" and mid and not g.rolling() and g.buff_left(GS.HIGH_ID, now.call()) > 19.0 and is_equal_approx(pc._pow(now.call()), pow0 * 2.0), "the die rolls first: nothing changes for %.2f s (a second cast waits), then the High lands" % GS.LAND_S)
	steps(c, 1.0)
	g.roll(now.call(), 6)
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	check.call(g.last_roll.outcome == "jackpot" and is_equal_approx(pc._pow(t), pow0 * 2.0 * 6.0) and absf(g.buff_left(GS.JACKPOT_ID, t) - 10.0) < 0.01 and g.buff_left(GS.HIGH_ID, t) > 18.0, "a 6: I JUST HIT THE JACKPOT! for 10 s (+500%% Pow), stacking with the High: Pow x%.1f" % (pc._pow(t) / pow0))
	steps(c, 2.0)
	g.roll(now.call(), 5)
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	var high_mods: int = s.stats.modifiers.filter(func(m): return m.id == GS.HIGH_ID and m.stat == "magic_pow").size()
	check.call(absf(g.buff_left(GS.HIGH_ID, t) - 20.0) < 0.01 and high_mods == 1, "the High again refreshes it to 20 s (one copy, no stacking with itself)")
	# A low roll strips every buff, Cultivate included; the next cooldown is 3 s.
	var cu: Resource = s.grimoire.page("cultivate")
	pc.equip("skill_1", cu)
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, now.call())
	pc.ready_at.erase("spell_1")
	g.forced = [2]
	pc.use_slot("spell_1", Vector2.ZERO, now.call())
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	var stripped: bool = not g.has_buff(t) and t >= pc.cultivate_until and is_equal_approx(pc._pow(t), pow0)
	check.call(g.last_roll.outcome == "low" and stripped and absf(pc.remaining("spell_1", t) - 3.0) < 0.01 and not g.addicted, "a 2: every buff ends (Cultivate too); the next cooldown is 3 s")
	# The streak: low, high, low is no Addiction; two lows in a row is.
	g.roll(now.call(), 5)
	g.land(now.call()) # the die lands (its effects wait for it)
	g.roll(now.call(), 1)
	g.land(now.call()) # the die lands (its effects wait for it)
	check.call(not g.addicted and g.streak_low == 1, "low, high, low: the high roll broke the streak")
	g.roll(now.call(), 3)
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	check.call(g.addicted and g.last_roll.outcome == "addiction", "two low rolls in a row: Gambling Addiction")
	# [Sir, 2026-11-14] Entry removes every existing buff, whatever its source.
	g._end_addiction()
	s.stats.add_modifier("cultivate", "magic_pow", 1.1, 0.0, now.call() + 10.0)
	pc.cultivate_until = now.call() + 10.0
	g._buff(GS.HIGH, GS.HIGH_ID, now.call() + 20.0)
	g._buff(GS.JACKPOT, GS.JACKPOT_ID, now.call() + 10.0)
	c.effects.apply("player", "Sage Arts", 5.0, now.call(), "test")
	var had_buffs: bool = g.has_buff(now.call())
	g._start_addiction(now.call())
	t = now.call()
	check.call(had_buffs and g.addicted and not g.has_buff(t) and not c.effects.has("player", "Sage Arts", t) and t >= pc.cultivate_until, "Addiction's entry removes every existing buff (Cultivate, High, Jackpot, buff effects)")
	# While it lasts, no buff lands from any source.
	var refused0: int = s.stats.buffs_refused
	var mod_ok: bool = s.stats.add_modifier("cultivate", "atk_spd", 1.15, 0.0, t + 10.0)
	pc._cultivate(cu, t)
	var fx_r: String = c.effects.apply("player", "Sage Arts", 5.0, t, "test")
	var chant_ok: bool = s.progression.on_chant_success("magic_pow", 1)
	g._buff(GS.HIGH, GS.HIGH_ID, t + 20.0)
	var debuff_ok: bool = s.stats.add_modifier("concuss", "mov_spd", 0.2, 0.0, t + 0.5) # a debuff still lands
	t = now.call()
	check.call(not mod_ok and t >= pc.cultivate_until and fx_r == "blocked" and not chant_ok and not s.stats.can_rise("magic_pow") and g.buff_left(GS.HIGH_ID, t) == 0.0 and not g.has_buff(t) and s.stats.buffs_refused > refused0, "in Addiction no buff lands: stat buffs, Cultivate, buff effects and chant gains are all refused")
	check.call(debuff_ok and is_equal_approx(pc._pow(t), pow0 * 0.1), "debuffs still land, and Addiction's own Pow x0.1 holds")
	s.stats.remove_sources(["concuss"])
	var pow_add: float = pc._pow(t)
	check.call(is_equal_approx(pow_add, pow0 * 0.1) and is_equal_approx(s.stats.value("mov_spd", t), minf(mov0 * 1.5, 22.0)), "Addiction: Magic Pow x0.1 (%.1f of %.1f), Mov Spd +50%%" % [pow_add, pow0])
	# Pow x0.1 is applied last: after a flat bonus too.
	s.stats.buff_block = false # the probe is itself a buff: let it in just for this check
	s.stats.add_modifier("probe", "magic_pow", 1.0, 50.0, t + 1.0)
	s.stats.buff_block = true
	check.call(is_equal_approx(pc._pow(t), (pow0 + 50.0) * 0.1), "Addiction's x0.1 is applied last (after flat bonuses)")
	s.stats.remove_sources(["probe"])
	var gated: bool = pc.use_slot("skill_1", Vector2.ZERO, t) == "addicted" and not pc.can_cast() and not pc.rise_equipped() and not pc.sage_active(t)
	var view: Dictionary = pc.slot_view(t)
	check.call(gated and view.skill_1.state == "addicted" and view.basic.state == "addicted" and view.spell_1.state != "addicted", "Addiction: every other skill, attack and passive is off (Let it Ride stays)")
	pc.ready_at.erase("spell_1")
	g.forced = [6]
	pc.use_slot("spell_1", Vector2.ZERO, now.call())
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	check.call(g.last_roll.outcome == "addicted" and g.buff_left(GS.JACKPOT_ID, t) == 0.0 and pc.remaining("spell_1", t) == 0.0 and g.addict_highs == 1, "in Addiction a 6 gives nothing, and Let it Ride has no cooldown")
	g.forced = [1]
	pc.use_slot("spell_1", Vector2.ZERO, now.call())
	g.land(now.call()) # the die lands (its effects wait for it)
	check.call(g.addicted and g.addict_highs == 1 and pc.remaining("spell_1", now.call()) == 0.0, "a low roll in Addiction does nothing extra")
	g.forced = [4]
	pc.use_slot("spell_1", Vector2.ZERO, now.call())
	g.land(now.call()) # the die lands (its effects wait for it)
	t = now.call()
	check.call(not g.addicted and g.last_roll.outcome == "recovered" and is_equal_approx(pc._pow(t), pow0) and pc.can_cast() and g.buff_left(GS.HIGH_ID, t) == 0.0, "two rolls above 3 in all (not in a row) end Addiction; Pow is back and that roll gives no buff")
	check.call(absf(pc.remaining("spell_1", t) - 5.0) < 0.01, "after Addiction the cooldown is 5 s again")
	var back_ok: bool = s.stats.add_modifier("probe2", "magic_pow", 1.2, 0.0, t + 1.0) and c.effects.apply("player", "Sage Arts", 1.0, t, "test") != "blocked" and s.stats.can_rise("magic_pow")
	s.stats.remove_sources(["probe2"])
	c.effects.clear_target("player")
	check.call(back_ok, "once Addiction ends, buffs land again")

	# ---- Heads or Tails ------------------------------------------------------------------------------
	g.reset()
	c.park_enemies()
	reset_player.call()
	steps(c, 0.3)
	var ht: Resource = s.grimoire.page("heads_or_tails")
	check.call(pc.equip("attack", ht) == "ok" and ht.kind == 0, "Heads or Tails takes the attack slot (in place of Scorch and Burn)")
	var fwd: Vector3 = pc.aim_dir()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var e1 := put(c, ids[0], home + fwd * 10.0)
	var e1b := put(c, ids[1], home + fwd * 10.0 + side * 1.5) # right beside it: a single-target coin never touches it
	await tree.physics_frame
	var pow1: float = pc._pow(now.call())
	var hp_e1: float = e1.health.hp
	var coin: Dictionary = pc.cast_basic(now.call())
	steps(c, 0.3)
	var flown: float = float(coin.get("travelled", 0.0))
	steps(c, 0.7)
	var hh := hits(c, "heads")
	check.call(not hh.is_empty() and hh[0].result == "applied" and absf((hp_e1 - e1.health.hp) - pow1 * 0.8) < 0.01, "Heads really hurts: the enemy loses %.1f HP (%s)" % [hp_e1 - e1.health.hp, hh[0].result if not hh.is_empty() else "-"])
	check.call(not hh.is_empty() and hh[0].id == e1.enemy_id and absf(hh[0].amount - pow1 * 0.8) < 0.01 and hits(c, "heads").filter(func(h): return h.id == e1b.enemy_id).is_empty(), "Heads: one coin, one enemy, %.1f damage (80%% of Magic Pow)" % (hh[0].amount if not hh.is_empty() else 0.0))
	check.call(absf(flown - 15.0 * 0.3) < 0.4, "the coin flies at 15 m/s (%.2f m in 0.3 s)" % flown)
	c.park_enemies()
	var e_far := put(c, ids[2], home + fwd * 34.0)
	await tree.physics_frame
	var n0: int = g.hits.size()
	pc.cast_basic(now.call())
	steps(c, 2.6)
	check.call(g.hits.size() == n0 and g.coins.is_empty(), "Heads reaches 30 m: an enemy at 34 m is out of reach (the coin is gone)")
	# Tails: a 20 m burst, 120%, Pocket Change 10 s.
	c.park_enemies()
	var t_in := put(c, ids[0], home + fwd * 12.0)
	var t_in2 := put(c, ids[1], home + fwd * 12.0 + side * -15.0) # (+15 m stands inside the camp's crate)
	var t_out := put(c, ids[2], home + fwd * 12.0 + side * 26.0)
	await tree.physics_frame
	pc.special_ready = 0.0
	var pow2: float = pc._pow(now.call())
	pc.cast_special(now.call())
	var cd_t: float = pc.special_remaining(now.call())
	steps(c, 1.2)
	var th := hits(c, "tails")
	t = now.call()
	var in_ok: bool = th.any(func(h): return h.id == t_in.enemy_id and absf(h.amount - pow2 * 1.2) < 0.01 and h.result == "applied") and absf((1.0e6 - t_in.health.hp) - pow2 * 1.2) < 0.01 and th.any(func(h): return h.id == t_in2.enemy_id)
	var pc_ok: bool = c.effects.has(t_in.enemy_id, "Pocket Change", t) and c.effects.has(t_in2.enemy_id, "Pocket Change", t) and not c.effects.has(t_out.enemy_id, "Pocket Change", t)
	check.call(in_ok and pc_ok and th.filter(func(h): return h.id == t_out.enemy_id).is_empty(), "Tails: the giant coin bursts 20 m: 120%% Pow and Pocket Change; the enemy 26 m off is untouched %s" % str([th.map(func(h): return [h.id, snappedf(h.amount, 0.1)]), pow2 * 1.2]))
	check.call(absf(cd_t - s.stats.cooldown(20.0, true, now.call())) < 0.05, "Tails' cooldown: 20 s x Spell Mastery (%.1f s)" % cd_t)
	var left0: float = c.effects.remaining(t_in.enemy_id, "Pocket Change", now.call())
	steps(c, 3.0)
	g.tails_blast(t_in.global_position + Vector3(0, 1, 0), 1.0, pow2, now.call())
	var left1: float = c.effects.remaining(t_in.enemy_id, "Pocket Change", now.call())
	check.call(left0 > 9.0 and absf(left1 - 10.0) < 0.05, "a new Tails hit refreshes Pocket Change to 10 s (%.1f -> %.1f)" % [left0 - 3.0, left1])
	# The bounce chain: five enemies with Pocket Change 6 m apart; three bounces, never back.
	c.park_enemies()
	c.effects = c.effects.get_script().new()
	c.projectiles.effects = c.effects
	g.hits.clear()
	var chain := []
	for i in 5:
		var e := put(c, ids[i], home + fwd * 10.0 + side * (6.0 * i))
		c.effects.apply(e.enemy_id, "Pocket Change", 10.0, now.call(), "player", 100.0)
		chain.append(e)
	var lone := put(c, ids[5], home + fwd * 10.0 + side * -11.0) # Pocket Change too, but 11 m from the first
	c.effects.apply(lone.enemy_id, "Pocket Change", 10.0, now.call(), "player", 100.0)
	await tree.physics_frame
	var tg0: Dictionary = c.combat_targets().filter(func(x): return x.id == chain[0].enemy_id)[0]
	g.heads_hit(tg0, 100.0, now.call())
	var bh := hits(c, "bounce")
	var order: Array = bh.map(func(h): return h.id)
	var amounts: Array = bh.map(func(h): return snappedf(h.amount, 0.01))
	var expect_ids := [chain[1].enemy_id, chain[2].enemy_id, chain[3].enemy_id]
	check.call(bh.all(func(h): return h.result == "applied") and absf((1.0e6 - chain[1].health.hp) - 110.0) < 0.01, "each bounce really lands (HP lost: %.1f)" % (1.0e6 - chain[1].health.hp))
	check.call(order == expect_ids and amounts == [110.0, 120.0, 130.0], "Pocket Change: the coin bounces 3 times, 10 m at most, +10%% each (110/120/130%%): %s %s" % [str(order), str(amounts)])
	check.call(not order.has(chain[4].enemy_id) and not order.has(chain[0].enemy_id) and not order.has(lone.enemy_id), "never a 4th bounce, never the same enemy twice, nothing past 10 m")
	g.hits.clear()
	var tg_plain: Dictionary = c.combat_targets().filter(func(x): return x.id == chain[0].enemy_id)[0]
	c.effects.clear_target(chain[0].enemy_id)
	g.heads_hit(tg_plain, 100.0, now.call())
	check.call(hits(c, "bounce").is_empty(), "without Pocket Change on the struck enemy, no bounce")

	# ---- All In ---------------------------------------------------------------------------------------
	g.reset()
	c.park_enemies()
	reset_player.call()
	steps(c, 0.2)
	var ai: Resource = s.grimoire.page("all_in")
	check.call(pc.equip("spell_2", ai) == "ok" and ai.kind == 2 and ai.rank_req == "D" and ai.cooldown_s == 60.0, "All In: a rank D spell, 1 min cooldown")
	p.health.hp = p.health.max_hp
	var hp_full: float = p.health.hp
	var r_ai: String = pc.use_slot("spell_2", Vector2.ZERO, now.call())
	t = now.call()
	var hit_ai: String = p.health.apply(preload("res://scripts/combat/damage_packet.gd").new(990001, "sprite_x", "infected", 50.0, "bite"), t)
	check.call(r_ai == "ok" and absf(p.health.hp - hp_full * 0.01) < 0.01 and hit_ai == "immune" and absf(pc.remaining("spell_2", t) - 60.0) < 0.05, "All In: 99%% of current HP gone (%.1f left), Invincible, 60 s cooldown" % p.health.hp)
	c.publish(DT)
	var aura_in: bool = c._gfx.has("all_in") and c._gfx["all_in"].visible
	steps(c, 10.1)
	t = now.call()
	var bust: bool = not g.all_in_log.is_empty() and g.all_in_log[-1].outcome == "bust"
	check.call(bust and absf(s.stats.value("mov_spd", t) - mov0 * 0.3) < 0.01 and absf(s.stats.value("atk_spd", t) - atk0 * 0.3) < 0.01 and absf(p.health.hp - hp_full * 0.01) < 0.01, "no buff when the Invincibility ends: bust, -70% Mov Spd and Atk Spd, the HP stays lost")
	steps(c, 5.1)
	check.call(is_equal_approx(s.stats.value("mov_spd", now.call()), mov0), "the bust lasts 5 s")
	pc.ready_at.erase("spell_2")
	p.health.hp = p.health.max_hp
	pc.use_slot("spell_2", Vector2.ZERO, now.call())
	steps(c, 4.0)
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, now.call()) # Cultivate: still active when the 10 s end
	steps(c, 6.2)
	t = now.call()
	var won: bool = g.all_in_log[-1].outcome == "won"
	check.call(won and absf(p.health.hp - hp_full) < 0.01 and absf(pc._pow(t) - pow0 * pc.CULTIVATE.magic_pow[0] * 3.0) < 0.01, "a buff active when it ends: every lost HP back (%.0f) and +200%% Magic Pow" % p.health.hp)
	c.publish(DT)
	var aura_won: bool = c._gfx.has("all_in_won") and c._gfx["all_in_won"].visible and not c._gfx["all_in"].visible
	check.call(aura_in and aura_won, "All In wears a silver ring while Invincible and a crimson ring once won")
	steps(c, 10.1)
	check.call(is_equal_approx(pc._pow(now.call()), pow0), "the win's +200% Pow lasts 10 s")
	var kinds := ["gamblers_high", "jackpot", "all_in", "all_in_won"]
	var scenes: Array = kinds.map(func(k): return String(c.vfx.LOOPS[k].scene) + str(c.vfx.LOOPS[k].color))
	var low: bool = kinds.all(func(k): return float(c.vfx.LOOPS[k].get("offset", Vector3.ZERO).y) < 0.5)
	check.call(scenes.size() == 4 and Array(scenes).filter(func(x): return scenes.count(x) == 1).size() == 4 and low, "each Gambler buff has its own aura, all low round the body")

	# ---- Where are my Coins? -------------------------------------------------------------------------
	g.reset()
	c.park_enemies()
	c.effects = c.effects.get_script().new()
	c.projectiles.effects = c.effects
	reset_player.call()
	steps(c, 0.2)
	var wc: Resource = s.grimoire.page("where_are_my_coins")
	check.call(pc.equip("passive", wc) == "ok" and g.purse_equipped(), "Where are my Coins? takes the passive slot")
	for i in 12: g.on_kill(now.call())
	check.call(g.purse == 10, "a coin a kill, 10 at most (12 kills: %d)" % g.purse)
	var near1 := put(c, ids[0], home + fwd * 8.0)
	var near2 := put(c, ids[1], home + side * 25.0)
	var far1 := put(c, ids[2], home + side * -40.0)
	await tree.physics_frame
	steps(c, 0.2)
	check.call(g.purse == 10 and g.spills == 0, "10 coins and no buff: they stay in the pocket")
	pc.ready_at.erase("skill_1")
	pc.use_slot("skill_1", Vector2.ZERO, now.call()) # Cultivate: a buff
	steps(c, 2.0 * DT)
	t = now.call()
	var heavy_ok: bool = c.effects.has(near1.enemy_id, GS.HEAVY_ID, t) and c.effects.has(near2.enemy_id, GS.HEAVY_ID, t) and not c.effects.has(far1.enemy_id, GS.HEAVY_ID, t)
	check.call(g.purse == 0 and g.spills == 1 and heavy_ok, "a buff at 10 coins: all 10 spill; enemies within 30 m get Heavy Pockets (the one at 40 m does not)")
	var m0: float = g.heavy_mult(near1.enemy_id, t)
	check.call(absf(m0 - 0.2) < 0.02 and near1.speed_mult <= 0.21, "Heavy Pockets: -80%% Mov Spd at first (x%.2f)" % m0)
	g.on_kill(t)
	check.call(g.purse == 0, "no coins while any enemy has Heavy Pockets")
	steps(c, 5.0)
	var m5: float = g.heavy_mult(near1.enemy_id, now.call())
	steps(c, 5.1)
	var m10: float = g.heavy_mult(near1.enemy_id, now.call())
	check.call(absf(m5 - 0.6) < 0.03 and is_equal_approx(m10, 1.0), "the slow eases off linearly over 10 s (x%.2f at 5 s, x%.2f at 10 s)" % [m5, m10])
	g.on_kill(now.call())
	check.call(g.purse == 1, "Heavy Pockets gone: coins come again")
	g.roll(now.call(), 1)
	g.land(now.call()) # the die lands (its effects wait for it)
	g.roll(now.call(), 2)
	g.land(now.call()) # the die lands (its effects wait for it)
	var off_in_addiction: bool = g.addicted and not g.purse_equipped()
	g.on_kill(now.call())
	check.call(off_in_addiction and g.purse == 1, "Gambling Addiction turns Where are my Coins? off (no coins gained)")

	# ---- HUD -----------------------------------------------------------------------------------------
	c.publish(DT)
	var hud: CanvasLayer = c.hud
	check.call(hud.addict_tint.visible and hud.die.visible and hud.die.face == 2, "the HUD: the die shows the roll; Addiction tints the view purple")
	g.roll(now.call(), 4)
	g.land(now.call()) # the die lands (its effects wait for it)
	g.roll(now.call(), 5)
	g.land(now.call()) # the die lands (its effects wait for it)
	c.publish(DT)
	check.call(not hud.addict_tint.visible and hud.coin_label.visible and hud.coin_label.text == "Coins 1/10", "out of Addiction: no tint; the coin counter beside the bars: '%s'" % hud.coin_label.text)
	var die_basis_ok := true
	for f in range(1, 7):
		var n: Vector3 = hud.die.FACES[f]
		if not (hud.die.show_basis(f) * n).is_equal_approx(Vector3(0, 0, 1)): die_basis_ok = false
	check.call(die_basis_ok, "the die settles with the rolled face toward the camera (all six faces)")
	var gp: CanvasLayer = c.grimoire_panel
	var rows_ok: bool = pages.all(func(id): return gp.page_stats(id).size() >= 3)
	var heads_row: Array = gp.page_stats("heads_or_tails")[0]
	check.call(rows_ok and String(heads_row[1]).contains("80%"), "the Grimoire lists each Gambler page's stats: '%s'" % str(heads_row))
	g.reset()
	c.park_enemies()
	pc.reset()
