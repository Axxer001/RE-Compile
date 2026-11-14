extends RefCounted
# The Gambler set [Sir, 2026-11-14; docs/plan-gambler-set.md]. World-owned like
# SpellService: coins in flight outlive their cast, and the die, the buffs and
# the coin purse live here. Timing runs on the simulation clock.
#   Let it Ride (spell, rank D): 0 MP, 5 s cooldown; a d6 from its own RNG.
#     1-3: every buff on the player ends; the next cooldown is 3 s. Two low rolls
#     in a row: Gambling Addiction. 4-5: Gambler's High (20 s). 6: the Jackpot
#     (10 s). The same buff again refreshes it; High and Jackpot stack.
#     Addiction: every other attack, skill, spell and passive is off; Magic Pow
#     x0.1 (applied last), Mov Spd +50%; Let it Ride has no cooldown and its rolls
#     give nothing; it ends after 2 rolls above 3 (in all, not in a row).
#   Heads or Tails (attack, rank D): Heads, one coin at one enemy (30 m, 15 m/s,
#     80% Pow); Tails, a giant coin bursting 20 m (120% Pow) that leaves Pocket
#     Change 10 s. A Heads coin on an enemy with Pocket Change bounces on to
#     another within 10 m (3 bounces at most, never the same enemy twice),
#     +10% per bounce (110/120/130%).
#   Where are my Coins? (passive, rank D): +1 coin a kill (10 at most; none while
#     any enemy has Heavy Pockets). At 10 coins, any buff spends them: every enemy
#     within 30 m gets Heavy Pockets, -80% Mov Spd easing to 0 over 10 s.

const PS = preload("res://scripts/combat/projectile_service.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")
const EffectSystem = preload("res://scripts/core/effect_system.gd")

const LET := {"cd": 5.0, "cd_low": 3.0, "high_s": 20.0, "jackpot_s": 10.0, "addict_rolls": 2, "addict_pow": 0.1, "addict_mov": 1.5}
const HIGH := {"magic_pow": [2.0, 0.0], "atk_spd": [1.3, 0.0], "mov_spd": [1.3, 0.0], "spell_mastery": [1.0, 0.2]}     # [mul, flat]
const JACKPOT := {"magic_pow": [6.0, 0.0], "atk_spd": [2.0, 0.0], "mov_spd": [2.0, 0.0], "spell_mastery": [1.0, 1.0]}
const HIGH_ID := "gamblers_high"
const JACKPOT_ID := "jackpot"
const ADDICTION_ID := "addiction"
const ALL_IN_WIN_ID := "all_in"
const ALL_IN_BUST_ID := "all_in_bust"
const BUFF_SOURCES := ["cultivate", HIGH_ID, JACKPOT_ID, ALL_IN_WIN_ID] # every timed buff in the game (stat modifiers)
# All In [Sir, 2026-11-14] (spell, rank D, 1 min cooldown): 99% of current HP for 10 s of
# Invincibility; when it ends, any buff active -> the lost HP back and +200% Pow 10 s,
# else -70% Mov Spd and Atk Spd 5 s.
const ALL_IN := {"hp_cost": 0.99, "invuln_s": 10.0, "win_s": 10.0, "win_pow": 3.0, "bust_s": 5.0, "bust_mult": 0.3}
const COIN := {"speed": 15.0, "range": 30.0, "radius": 0.15, "bounce_r": 10.0, "bounces": 3, "bounce_step": 0.10}
const GIANT := {"speed": 15.0, "range": 30.0, "radius": 0.6, "aoe": 20.0}
const POCKET := {"id": "Pocket Change", "s": 10.0}
const PURSE := {"max": 10, "spill_r": 30.0, "heavy_s": 10.0, "slow": 0.8}
const HEAVY_ID := "Heavy Pockets"

var world: Node3D
var root: Node3D            # visuals parent (null = headless)
var rng := RandomNumberGenerator.new() # the die: its own seeded sequence
var streak_low := 0         # low rolls in a row (outside Addiction)
var addicted := false
var addict_highs := 0       # rolls above 3 since Addiction began
var rolls: Array = []       # {face, outcome, time} (tests, HUD)
var last_roll := {}         # the newest roll (the HUD die)
var jackpot_at := -INF      # the last 6 (the HUD's gold flash)
var coins: Array = []       # {id, kind (heads|tails), pos, vel, travelled, range, damage, pow, target_point, node}
var hits: Array = []        # {kind (heads|bounce|tails), id, amount, bounce, result, time}
var purse := 0
var spills := 0
var forced: Array = []      # test hook: faces the next rolls will show
var all_in := {}           # {start, until, lost} while the Invincibility runs
var all_in_log: Array = []  # {outcome (won|bust), lost, returned, time} (tests)
var _roll_n := 0            # every roll's serial (never reset: the HUD die tells rolls apart by it)
var _next := 0

func setup(main: Node3D) -> void:
	world = main
	rng.seed = 0xD1CE

func reset() -> void:
	for c in coins: _free_node(c)
	coins.clear()
	hits.clear()
	rolls.clear()
	last_roll = {}
	pending = {}
	jackpot_at = -INF
	streak_low = 0
	purse = 0
	spills = 0
	if addicted: _end_addiction()
	addicted = false
	all_in = {}
	all_in_log.clear()
	addict_highs = 0

func stats() -> RefCounted:
	return world.session.stats

# ---- Let it Ride ---------------------------------------------------------------------------------

# One roll [Sir, 2026-11-14: the die finishes rolling before anything happens].
# The face is decided now (its own RNG; `face` > 0 forces it for tests) and the
# HUD die starts tumbling; the result lands LAND_S later (tick -> land). Returns
# {face, outcome (what it will do), time, lands_at, n}; outcomes: low | addiction |
# high | jackpot | addicted (a roll inside Addiction) | recovered.
const LAND_S := 0.95 # = the die's tumble + settle (ui/dice_view.gd)
var pending := {}           # the roll still tumbling ({} = none)

func roll(now: float, face := 0) -> Dictionary:
	if not pending.is_empty(): land(now) # (only tests roll on top of a tumbling die)
	var f: int = face if face > 0 else (int(forced.pop_front()) if not forced.is_empty() else rng.randi_range(1, 6))
	_roll_n += 1
	last_roll = {"face": f, "outcome": _predict(f), "time": now, "lands_at": now + LAND_S, "n": _roll_n}
	pending = last_roll
	rolls.append(last_roll)
	var sfx = world.get("sfx")
	if sfx != null: sfx.play("dice_rattle", world.player.global_position)
	return last_roll

func rolling() -> bool:
	return not pending.is_empty()

# What a face will do from the state now (no effects).
func _predict(f: int) -> String:
	var low := f <= 3
	if addicted: return "recovered" if not low and addict_highs + 1 >= int(LET.addict_rolls) else "addicted"
	if low: return "addiction" if streak_low + 1 >= 2 else "low"
	return "jackpot" if f == 6 else "high"

# The die has landed: its result takes effect.
func land(now: float) -> Dictionary:
	if pending.is_empty(): return {}
	var r: Dictionary = pending
	pending = {}
	var f: int = int(r.face)
	var low := f <= 3
	var outcome := ""
	if addicted:
		outcome = "addicted"
		if not low:
			addict_highs += 1
			if addict_highs >= int(LET.addict_rolls):
				_end_addiction()
				outcome = "recovered"
	elif low:
		strip_buffs(now)
		streak_low += 1
		outcome = "low"
		if streak_low >= 2:
			_start_addiction(now)
			outcome = "addiction"
	else:
		streak_low = 0
		if f == 6:
			_buff(JACKPOT, JACKPOT_ID, now + float(LET.jackpot_s))
			jackpot_at = now
			outcome = "jackpot"
		else:
			_buff(HIGH, HIGH_ID, now + float(LET.high_s))
			outcome = "high"
	r.outcome = outcome
	r.landed = now
	_announce(outcome, f)
	return r

# Let it Ride's cooldown after a roll: 3 s after a low roll, none in Addiction.
func cooldown_after(r: Dictionary) -> float:
	match String(r.get("outcome", "")):
		"addiction", "addicted": return 0.0
		"low": return float(LET.cd_low)
	return float(LET.cd)

func _buff(table: Dictionary, id: String, until: float) -> void:
	for stat in table: stats().add_modifier(id, stat, table[stat][0], table[stat][1], until)

# Every buff on the player ends (all sources, Cultivate included).
func strip_buffs(_now: float) -> void:
	stats().remove_sources(BUFF_SOURCES)
	var pc = world.get("pcombat")
	if pc != null: pc.cultivate_until = -INF
	var per: Dictionary = world.effects.active.get("player", {}) if world.get("effects") != null else {}
	for eid in per.keys():
		if EffectSystem.kind_of(eid) == "buff": per.erase(eid)

# Any buff on the player right now (Where are my Coins? spends on this).
func has_buff(now: float) -> bool:
	for m in stats().modifiers:
		if m.id in BUFF_SOURCES and now < m.until: return true
	var pc = world.get("pcombat")
	if pc != null and now < pc.cultivate_until: return true
	if world.get("effects") != null:
		for eid in world.effects.active.get("player", {}):
			if EffectSystem.kind_of(eid) == "buff" and world.effects.has("player", eid, now): return true
	return false

func buff_left(id: String, now: float) -> float:
	for m in stats().modifiers:
		if m.id == id and m.stat == "magic_pow" and now < m.until: return m.until - now
	return 0.0

# On entry every buff ends; while it lasts no buff of any source lands [Sir, 2026-11-14].
func _start_addiction(now: float) -> void:
	addicted = true
	addict_highs = 0
	streak_low = 0
	strip_buffs(now)
	stats().add_modifier(ADDICTION_ID, "magic_pow", 1.0, 0.0, INF, float(LET.addict_pow))
	stats().add_modifier(ADDICTION_ID, "mov_spd", float(LET.addict_mov), 0.0, INF)
	_block(true)

func _block(on: bool) -> void:
	if world == null or world.session == null: return
	stats().buff_block = on
	if world.get("effects") != null:
		if on: world.effects.buff_blocked["player"] = true
		else: world.effects.buff_blocked.erase("player")

func _end_addiction() -> void:
	addicted = false
	addict_highs = 0
	streak_low = 0
	if world != null and world.session != null: stats().remove_sources([ADDICTION_ID])
	_block(false)

func addiction_label() -> String:
	return "%d/%d" % [addict_highs, int(LET.addict_rolls)]

func _announce(outcome: String, f: int) -> void:
	var at: Vector3 = world.player.global_position if world.get("player") != null else Vector3.ZERO
	var sfx = world.get("sfx")
	if sfx != null:
		match outcome:
			"jackpot": sfx.play("jackpot", at)
			"addiction": sfx.play("addiction_thud", at)
	if not world.has_method("show_notice"): return
	match outcome:
		"low": world.show_notice("Let it Ride: %d. Your buffs are gone." % f, 1.6)
		"addiction": world.show_notice("Let it Ride: %d. GAMBLING ADDICTION!" % f, 2.2)
		"high": world.show_notice("Let it Ride: %d. Gambler's High!" % f, 1.6)
		"jackpot": world.show_notice("I JUST HIT THE JACKPOT!", 2.2)
		"addicted": world.show_notice("Let it Ride: %d (%s to break free)" % [f, addiction_label()], 1.4)
		"recovered": world.show_notice("Let it Ride: %d. You walk away from the table." % f, 2.0)

# ---- All In -------------------------------------------------------------------------------------

func start_all_in(now: float) -> void:
	var h: Node = world.player.health
	var lost: float = h.hp * float(ALL_IN.hp_cost)
	h.hp -= lost
	h.grant_immunity(now + float(ALL_IN.invuln_s), ["*"], -INF, "all_in")
	all_in = {"start": now, "until": now + float(ALL_IN.invuln_s), "lost": lost}
	if world.get("sfx") != null: world.sfx.play("addiction_thud", world.player.global_position)
	if world.has_method("show_notice"): world.show_notice("All In: %d HP on the table" % roundi(lost), 1.6)

# The Invincibility ends: a buff active wins the bet, none busts it.
func resolve_all_in(now: float) -> String:
	var lost: float = float(all_in.get("lost", 0.0))
	all_in = {}
	var h: Node = world.player.health
	var outcome := "bust"
	var returned := 0.0
	if has_buff(now) and not h.dead:
		outcome = "won"
		var before: float = h.hp
		h.hp = minf(h.max_hp, h.hp + lost)
		returned = h.hp - before
		stats().add_modifier(ALL_IN_WIN_ID, "magic_pow", float(ALL_IN.win_pow), 0.0, now + float(ALL_IN.win_s))
		if world.get("sfx") != null: world.sfx.play("ka_ching", world.player.global_position)
		if world.has_method("show_notice"): world.show_notice("All In: won! HP back, +200% Magic Pow", 1.8)
	else:
		for stat in ["mov_spd", "atk_spd"]: stats().add_modifier(ALL_IN_BUST_ID, stat, float(ALL_IN.bust_mult), 0.0, now + float(ALL_IN.bust_s))
		if world.has_method("show_notice"): world.show_notice("All In: bust. -70% Mov Spd and Atk Spd", 1.8)
	all_in_log.append({"outcome": outcome, "lost": lost, "returned": returned, "time": now})
	return outcome

func modifier_left(id: String, stat: String, now: float) -> float:
	for m in stats().modifiers:
		if m.id == id and m.stat == stat and now < m.until: return m.until - now
	return 0.0

# ---- Heads or Tails ------------------------------------------------------------------------------

# A coin. kind heads: one enemy; tails: the giant coin, aimed at `target_point`.
func throw(kind: String, origin: Vector3, dir: Vector3, damage: float, magic: float, target_point, now: float) -> Dictionary:
	_next += 1
	var spec: Dictionary = COIN if kind == "heads" else GIANT
	var c := {"id": _next, "kind": kind, "pos": origin, "vel": dir.normalized() * float(spec.speed), "travelled": 0.0,
		"range": float(spec.range), "damage": damage, "pow": magic, "target_point": target_point, "node": null, "born": now}
	if target_point != null: c.range = minf(c.range, origin.distance_to(target_point))
	if world.get("vfx") != null and root != null: c.node = world.vfx.coin_visual(kind, origin)
	coins.append(c)
	return c

func tick(delta: float, now: float) -> void:
	if not pending.is_empty() and now + 1e-6 >= float(pending.lands_at): land(now)
	if not all_in.is_empty() and now >= float(all_in.until): resolve_all_in(now)
	if not coins.is_empty():
		var targets: Array = world.combat_targets()
		for c in coins.duplicate():
			_fly(c, delta, now, targets)
	_purse_tick(now)

func _fly(c: Dictionary, delta: float, now: float, targets: Array) -> void:
	var spec: Dictionary = COIN if c.kind == "heads" else GIANT
	var dist := minf(c.vel.length() * delta, c.range - c.travelled)
	var dir: Vector3 = c.vel.normalized()
	var from: Vector3 = c.pos
	var to: Vector3 = from + dir * dist
	var r: float = float(spec.radius)
	var best_t := INF
	var best_tg := {}
	if dist > 1e-6:
		var w: Dictionary = world.world_ray(from, to + dir * r)
		if not w.is_empty(): best_t = maxf(0.0, from.distance_to(w.position) - r)
		for tg in targets:
			if tg.health.dead or from.distance_squared_to(tg.pos) > pow(dist + r + 2.0, 2.0): continue
			var t := PS.target_along(from, dir, dist, tg, r)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_tg = tg
	if best_t < INF:
		var at := from + dir * best_t
		if c.kind == "heads":
			if not best_tg.is_empty(): heads_hit(best_tg, float(c.damage), now)
			elif world.get("vfx") != null: world.vfx.coin_hit(at, now) # it rings off a trunk or rock
		else: tails_blast(at, float(c.damage), float(c.pow), now)
		_remove(c)
		return
	c.pos = to
	c.travelled += dist
	if c.node: world.vfx.coin_move(c.node, to, dir, now)
	if c.travelled >= c.range - 1e-4:
		if c.kind == "tails": tails_blast(to, float(c.damage), float(c.pow), now) # the giant coin bursts at its point
		_remove(c)

func _remove(c: Dictionary) -> void:
	_free_node(c)
	coins.erase(c)

func _free_node(c: Dictionary) -> void:
	if c.get("node") != null and is_instance_valid(c.node) and world.get("vfx") != null: world.vfx.coin_release(c.node)
	c.node = null

func _apply(tg: Dictionary, amount: float, now: float) -> String:
	return tg.health.apply(DamagePacket.new(CombatController.next_id(), "player", "player", amount, "coin"), now)

# A Heads coin on one enemy; Pocket Change passes it on (3 bounces at most).
func heads_hit(tg: Dictionary, damage: float, now: float) -> void:
	var result := _apply(tg, damage, now)
	hits.append({"kind": "heads", "id": tg.id, "amount": damage, "bounce": 0, "result": result, "time": now})
	var vfx = world.get("vfx")
	if vfx != null: vfx.coin_hit(tg.pos, now)
	if world.get("sfx") != null: world.sfx.play("coin_clink", tg.pos)
	if world.get("effects") == null or not world.effects.has(String(tg.id), POCKET.id, now): return
	var done := [tg.id]
	var cur: Dictionary = tg
	for n in range(1, int(COIN.bounces) + 1):
		var nxt := {}
		var best := INF
		for o in world.combat_targets():
			if o.health.dead or o.id in done or not world.effects.has(String(o.id), POCKET.id, now): continue
			var d: float = (o.pos as Vector3).distance_to(cur.pos)
			if d <= float(COIN.bounce_r) and d < best:
				best = d
				nxt = o
		if nxt.is_empty(): break
		var amount := damage * (1.0 + float(COIN.bounce_step) * n)
		var res := _apply(nxt, amount, now)
		hits.append({"kind": "bounce", "id": nxt.id, "amount": amount, "bounce": n, "result": res, "time": now})
		if vfx != null:
			vfx.coin_arc(cur.pos, nxt.pos, now)
			vfx.coin_hit(nxt.pos, now)
		if world.get("sfx") != null: world.sfx.play("coin_clink", nxt.pos)
		done.append(nxt.id)
		cur = nxt

# The giant coin bursts: 120% Pow within 20 m (walls and trunks shield), Pocket Change 10 s.
func tails_blast(spot: Vector3, damage: float, magic: float, now: float) -> void:
	var packet := CombatController.next_id()
	var eye := spot + Vector3(0, 0.3, 0)
	for tg in world.combat_targets():
		if tg.health.dead or PS.gap_to(spot, tg) > float(GIANT.aoe): continue
		if not world.clear_line(eye, tg.pos): continue
		var result: String = tg.health.apply(DamagePacket.new(packet, "player", "player", damage, "blast"), now)
		hits.append({"kind": "tails", "id": tg.id, "amount": damage, "bounce": 0, "result": result, "time": now})
		if world.get("effects") != null and not tg.health.dead and result in ["applied", "duplicate"]:
			world.effects.apply(String(tg.id), POCKET.id, float(POCKET.s), now, "player", magic)
	if world.get("vfx") != null: world.vfx.tails_blast(spot, now)
	if world.get("sfx") != null:
		world.sfx.play("ka_ching", spot)
		world.sfx.play("blast", spot)
	if world.get("noise") != null: world.noise.emit_noise(spot, 30.0, "blast", "player", now)

# ---- Where are my Coins? -------------------------------------------------------------------------

func purse_equipped() -> bool:
	var pc = world.get("pcombat")
	if pc == null or addicted: return false # Addiction turns every passive off
	var pg: Resource = pc.loadout.get("passive")
	return pg != null and String(pg.id) == "where_are_my_coins" and pg.rank_ok(pc.rank())

func any_heavy(now: float) -> bool:
	for id in world.enemies:
		if world.effects.has(String(id), HEAVY_ID, now): return true
	return false

func on_kill(now: float) -> void:
	if not purse_equipped() or any_heavy(now): return
	purse = mini(int(PURSE.max), purse + 1)

func _purse_tick(now: float) -> void:
	if purse >= int(PURSE.max) and purse_equipped() and has_buff(now): spill(now)

# All 10 coins spill: every enemy within 30 m gets Heavy Pockets.
func spill(now: float) -> void:
	purse = 0
	spills += 1
	var at: Vector3 = world.player.global_position
	for tg in world.combat_targets():
		if tg.health.dead or not world.enemies.has(tg.id): continue
		if (tg.pos as Vector3).distance_to(at) > float(PURSE.spill_r): continue
		world.effects.apply(String(tg.id), HEAVY_ID, float(PURSE.heavy_s), now, "player")
	if world.get("sfx") != null: world.sfx.play("ka_ching", at)
	if world.has_method("show_notice"): world.show_notice("Where are my Coins? Your pockets spill!", 1.6)

# Heavy Pockets: -80% Mov Spd at first, easing to 0 over its 10 s.
func heavy_mult(id: String, now: float) -> float:
	if not world.effects.has(id, HEAVY_ID, now): return 1.0
	var left: float = world.effects.remaining(id, HEAVY_ID, now)
	return 1.0 - float(PURSE.slow) * clampf(left / float(PURSE.heavy_s), 0.0, 1.0)
