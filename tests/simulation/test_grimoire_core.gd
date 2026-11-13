extends RefCounted
# Grimoire MVP core systems against the Tech Spec numbers: StatContainer,
# Progression, EffectSystem, AbilityPage rank gate. Headless, no scene needed.

const Stats = preload("res://scripts/core/stat_container.gd")
const Progression = preload("res://scripts/core/progression.gd")
const Effects = preload("res://scripts/core/effect_system.gd")
const AbilityPage = preload("res://scripts/core/ability_page.gd")

static func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

static func run(check: Callable, _c = null) -> void:
	# --- Stats -----------------------------------------------------------------
	var s := Stats.new()
	check.call(s.value("max_hp") == 100.0 and s.value("max_mp") == 100.0 and s.value("magic_pow") == 100.0
		and s.value("mov_spd") == 10.0 and s.value("atk_spd") == 5.0 and s.value("spell_mastery") == 0.0, "beginner stats match GDD §3.2")
	check.call(not s.allocate("max_hp"), "allocate needs an unspent point")
	s.unspent = 6
	for stat in Stats.STATS: s.allocate(stat)
	check.call(near(s.value("max_hp"), 105) and near(s.value("max_mp"), 105) and near(s.value("magic_pow"), 105)
		and near(s.value("mov_spd"), 10.25) and near(s.value("atk_spd"), 5.2) and near(s.value("spell_mastery"), 0.015), "one point per stat: flat +5 HP/MP/Pow [Sir R3], Tech Spec §1.1 for the rest")
	check.call(s.unspent == 0, "allocation spends points")

	var caps := Stats.new()
	caps.points["mov_spd"] = 48
	check.call(near(caps.value("mov_spd"), 22.0), "Mov Spd reaches its 22 m/s cap at 48 points")
	caps.unspent = 1
	check.call(not caps.allocate("mov_spd") and caps.unspent == 1, "no allocation past a hard cap")
	caps.points["atk_spd"] = 100
	check.call(near(caps.value("atk_spd"), 12.0), "Atk Spd hard cap 12")
	caps.points["spell_mastery"] = 30
	check.call(near(caps.value("spell_mastery"), 0.45), "30 points reach the 45% Mastery soft cap")
	caps.points["spell_mastery"] = 31
	check.call(near(caps.value("spell_mastery"), 0.4575), "past 45% a point gives half (+0.75%)")
	caps.points["spell_mastery"] = 500
	check.call(near(caps.value("spell_mastery"), 0.65), "Mastery hard cap 65%")

	var m := Stats.new()
	m.points["spell_mastery"] = 0
	m.add_modifier("probe", "spell_mastery", 1.0, 0.20, 100.0)
	check.call(near(m.cooldown(15.0, true, 0.0), 12.0), "15 s cooldown at 20% Mastery is 12 s (Tech Spec §1.2)")
	check.call(near(m.cooldown(20.0, false, 0.0), 20.0), "skills ignore Mastery")
	check.call(near(m.attack_interval(), 0.2), "Atk Spd 5 = one basic attack every 0.2 s")

	# Cultivate buff (Page 2): Pow x1.10, Mastery +0.20, AtkSpd x1.15 for 10 s.
	var b := Stats.new()
	b.add_modifier("cultivate", "magic_pow", 1.10, 0.0, 10.0)
	b.add_modifier("cultivate", "spell_mastery", 1.0, 0.20, 10.0)
	b.add_modifier("cultivate", "atk_spd", 1.15, 0.0, 10.0)
	check.call(near(b.value("magic_pow", 5.0), 110.0) and near(b.value("spell_mastery", 5.0), 0.20) and near(b.value("atk_spd", 5.0), 5.75), "Cultivate buffs apply during the 10 s")
	check.call(near(b.value("magic_pow", 10.0), 100.0) and near(b.value("atk_spd", 10.5), 5.0), "Cultivate buffs end at 10 s")
	b.add_modifier("cultivate", "magic_pow", 1.10, 0.0, 30.0)
	check.call(near(b.value("magic_pow", 20.0), 110.0), "re-casting refreshes, does not stack (still x1.10)")

	# --- Progression -----------------------------------------------------------
	check.call(Progression.exp_required(1) == 100 and Progression.exp_required(2) == 263 and Progression.exp_required(5) == 951
		and Progression.exp_required(10) == 2511 and Progression.exp_required(20) == 6628, "EXP curve floor(100 L^1.4) matches the spec table")
	check.call(Progression.points_for_level(9) == 1 and Progression.points_for_level(10) == 2 and Progression.points_for_level(20) == 3, "level-up points scale per 10 levels")
	check.call(Progression.points_for_rank("D") == 5 and Progression.points_for_rank("C") == 10, "rank-up points 5 x rank")

	var ps := Stats.new()
	var p := Progression.new(ps)
	p.on_page_unlocked()
	check.call(ps.unspent == 3 + 1 and p.level == 2 and p.exp == 50, "page unlock: +3 points, +150 EXP (levels to 2 with 50 over, +1 point)")
	var ranked := []
	p.ranked.connect(func(r, pts): ranked.append([r, pts]))
	for i in 19: p.on_kill()
	check.call(p.rank == "E" and p.mission().progress == 19, "19 kills: still rank E, mission 19/20")
	var pts_before := ps.unspent
	p.on_kill()
	check.call(p.rank == "D" and ranked == [["D", 5]], "20th kill promotes E -> D with 5 points")
	check.call(ps.unspent >= pts_before + 5 and p.mission().is_empty(), "rank points granted; no further MVP mission")

	var cs := Stats.new()
	var cp := Progression.new(cs)
	var lvl := cp.level
	check.call(cp.on_chant_success("magic_pow") and cs.points.magic_pow == 0 and cs.chant_points.magic_pow == 1 and near(cs.value("magic_pow"), 105.0) and cp.level == lvl and cp.exp == 0 and cs.unspent == 0, "a tier-1 chant: Magic Pow +5, no EXP, no level, no stat point [Sir R9/R10]")
	var base_gain := {"max_hp": 5.0, "max_mp": 5.0, "magic_pow": 5.0, "mov_spd": 0.4, "atk_spd": 0.25, "spell_mastery": 0.015}
	var gains_ok := true
	for stat in Stats.STATS:
		for tier in [1, 4]:
			var g := Stats.new()
			var before: float = g.value(stat)
			g.grant_point(stat, tier)
			if not near(g.value(stat) - before, base_gain[stat] * (1.0 if tier == 1 else 1.5)): gains_ok = false
	check.call(gains_ok, "chant gains x tier: HP/MP/Pow +5, Mov Spd +0.4, Atk Spd +0.25, Mastery +1.5% at tier 1; x1.5 at tier 4 [R10]")
	var tiers := Stats.new()
	tiers.grant_point("max_hp", 2); tiers.grant_point("max_hp", 3)
	check.call(near(tiers.value("max_hp"), 100.0 + 5.0 * 1.15 + 5.0 * 1.3), "each chant keeps the gain of its own tier (x1.15 then x1.3)")
	var cap := Stats.new()
	var n_ch := 0
	while cap.grant_point("mov_spd") and n_ch < 100: n_ch += 1
	check.call(n_ch == 30 and near(cap.value("mov_spd"), 22.0) and not cap.can_rise("mov_spd"), "Mov Spd needs 30 tier-1 chants from base to reach its 22 m/s cap; then chants are refused (%d)" % n_ch)
	cp.on_chant_success("magic_pow")
	check.call(cp.chant_streak == 2 and cp.exp == 0, "the streak counts on, still no EXP")
	cp.on_chant_fail()
	check.call(cp.chant_streak == 0, "a failed chant resets the streak")
	# Reset stats [Sir R4]: back to base; allocated points refunded, each chant = 1 point.
	cs.unspent = 2
	cs.allocate("max_hp"); cs.allocate("mov_spd")
	var refund: int = cs.reset_stats()
	check.call(refund == 4 and cs.unspent == 4 and near(cs.value("max_hp"), 100.0) and near(cs.value("magic_pow"), 100.0) and near(cs.value("mov_spd"), 10.0) and cs.chant_points.magic_pow == 0, "reset stats: 2 allocated + 2 chants refunded as 4 points, every stat at base")

	# --- Effects ---------------------------------------------------------------
	var fx := Effects.new()
	check.call(fx.apply("sprite_1", "Burn", 5.0, 0.0, "player", 100.0) == "applied", "Burn applies")
	var ticks: Array = fx.tick(3.0)
	check.call(ticks.size() == 3 and near(ticks[0].amount, 2.0), "Burn ticks 2% of Magic Pow per second")
	check.call(fx.apply("sprite_1", "Burn", 5.0, 3.0, "player", 500.0) == "refreshed" and near(fx.remaining("sprite_1", "Burn", 3.0), 5.0), "re-applying Burn refreshes to full duration")
	var t2: Array = fx.tick(4.0)
	check.call(t2.size() == 1 and near(t2[0].amount, 2.0), "refresh keeps potency (does not take the new Pow) and does not stack")
	fx.apply("sprite_1", "Slow", 2.0, 4.0)
	check.call(fx.has("sprite_1", "Burn", 4.0) and fx.has("sprite_1", "Slow", 4.0), "different effects coexist")
	fx.tick(6.5)
	check.call(not fx.has("sprite_1", "Slow", 6.5) and fx.has("sprite_1", "Burn", 6.5), "each effect keeps its own timer")
	var rest: Array = fx.tick(20.0)
	check.call(not fx.has("sprite_1", "Burn", 20.0) and rest.size() == 2, "Burn ends at its refreshed time (ticks to t=8)")
	var ids := {}
	for e in ticks + t2 + rest: ids[e.action_id] = true
	check.call(ids.size() == (ticks + t2 + rest).size(), "every tick has a unique action id")

	var fx2 := Effects.new()
	fx2.apply("s2", "Burn", 10.0, 0.0, "player", 100.0)
	check.call(fx2.tick(10.0).size() == 10, "special Burn: 10 s = 10 ticks")

	# --- Rank gate ---------------------------------------------------------------
	var page := AbilityPage.new()
	page.rank_req = "D"
	check.call(not page.rank_ok("E") and page.rank_ok("D") and page.rank_ok("S"), "rank-locked pages gate on Adventurer Rank")
