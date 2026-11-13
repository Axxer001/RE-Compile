extends RefCounted
# P6 Spell Chanting (GDD §3.4.4, Tech Spec §3.3, handoff §6, Sir R2-R5): tiers
# and the guardrail, per-stat difficulty, fresh topic-bound problems, the answer
# check, the reward (+1 point's worth, no level), Reset stats, hits, and the
# chant tier surviving a death.

const DT := 1.0 / 60.0
const Chant = preload("res://scripts/core/chant_engine.gd")
const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func fill(pr: Dictionary, answers: Array) -> Array:
	var out := []
	for l in pr.lines:
		var t: String = l
		for i in answers.size(): t = t.replace("[?%d]" % (i + 1), answers[i])
		out.append(t)
	return out

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var all5 := ["scorch_and_burn", "cultivate", "ring_of_fire", "quick_step", "sage_arts"]

	# ---- tiers, guardrail, banks ---------------------------------------------------------
	var enough := true
	for t in [1, 2, 3, 4]:
		if Chant.candidates(t).size() < 6: enough = false
	check.call(enough, "every tier has at least 6 fill-in templates on its page's topic [R2]")
	var d := [Chant.difficulty(0, all5), Chant.difficulty(1, all5), Chant.difficulty(2, all5), Chant.difficulty(6, all5), Chant.difficulty(9, all5)]
	check.call(d[0].tier == 1 and d[0].blanks == 1 and d[1].tier == 1 and d[1].blanks == 2 and d[2].tier == 2 and d[3].tier == 4 and not d[3].plateau and d[4].tier == 4 and d[4].plateau, "difficulty: tier = 1 + level/2, blanks = 1 + level%2; past tier 4 it plateaus")
	var over := 0
	for i in 200:
		var pr: Dictionary = Chant.draw(rng.randi_range(0, 12), ["scorch_and_burn"], rng)
		if pr.tier >= 2: over += 1
	check.call(over == 0, "guardrail: with only page 1 unlocked, 200 draws never go past tier 1")
	var over2 := 0
	var plateau_seen := false
	for i in 200:
		var pr: Dictionary = Chant.draw(rng.randi_range(0, 12), ["scorch_and_burn", "cultivate", "quick_step"], rng)
		if pr.tier >= 3: over2 += 1
		if pr.plateau: plateau_seen = true
	check.call(over2 == 0 and plateau_seen, "pages 1, 2 and 4 (no Ring of Fire): never tier 3+, and the plateau hint shows")
	var off_tier := 0
	var off_topic := 0
	var not_source := 0
	var repeats := 0
	var last := ""
	for i in 300:
		var lv := rng.randi_range(0, 9)
		var pr: Dictionary = Chant.draw(lv, all5, rng, last)
		if pr.key == last: repeats += 1
		last = pr.key
		if not pr.page in {1: ["scorch_and_burn", "cultivate"], 2: ["ring_of_fire"], 3: ["quick_step"], 4: ["sage_arts"]}[pr.tier]: off_topic += 1 # written out: not read back from the engine
		var line_toks := []
		for l in CodeAssembly.variants(pr.page)[pr.variant].lines: for tk in Chant.tokens(l, pr.tier): line_toks.append(tk.text)
		for a in pr.answers:
			if not a in line_toks: off_tier += 1
		if fill(pr, pr.answers) != CodeAssembly.variants(pr.page)[pr.variant].lines: not_source += 1
	check.call(off_tier == 0 and off_topic == 0, "300 draws: every blank is of the chant's tier, from that tier's page [R2]")
	check.call(repeats == 0, "never the same problem twice in a row")
	check.call(not_source == 0, "filled in, every problem is its bank code exactly (g++-checked C++)")

	var lit := '  cout << "main; return {x} // << endl";'
	check.call(Chant.tokens(lit, 1).is_empty() and Chant.tokens(lit, 4).is_empty() and Chant.tokens(lit, 2).map(func(t): return t.text) == [";"] and Chant.tokens(lit, 3).map(func(t): return t.text) == ["cout", "<<"], "nothing inside a string literal is ever blanked (C++ tokens outside it are)")
	# Tier 1 draws Cultivate's code only once Cultivate is unlocked.
	var only1 := 0
	for i in 100:
		var pr1: Dictionary = Chant.draw(0, ["scorch_and_burn"], rng)
		if pr1.page != "scorch_and_burn": only1 += 1
	check.call(only1 == 0, "with only Scorch and Burn unlocked, tier-1 chants use only its code")

	# ---- the answer check -------------------------------------------------------------------
	var p1 := {"answers": ["*", "0.10", "add_multiplier", "\"Burn\""]}
	check.call(Chant.check(p1, ["  *  ", "0.1", "add_multiplier", "\"Burn\""]).ok, "whitespace, an equal number (0.1 = 0.10) and quotes are accepted")
	check.call(Chant.check({"answers": ["Burn"]}, ["'Burn'"]).ok and not Chant.check({"answers": ["for"]}, ["For"]).ok and Chant.check({"answers": ["for", "in"]}, ["for", "on"]).wrong == [1], "surrounding quotes are stripped; code is case-sensitive; wrong blanks are named")

	# ---- the chant through the Player ID panel ---------------------------------------------
	var gp: CanvasLayer = c.grimoire_panel
	var st: RefCounted = s.stats
	var pr: RefCounted = s.progression
	s.handle_action("grimoire")
	gp.show_tab("player_id")
	st.unspent = 1
	check.call(gp.start_chant("magic_pow").is_empty() and gp.mode != "chant", "a chant needs 0 unspent points [GDD]")
	check.call(gp.allocate("magic_pow") and st.points.magic_pow == 1 and gp.mode != "chant", "[+] with a point spends it")
	st.points.magic_pow = 0
	var spent_none: bool = gp.allocate("magic_pow")
	var prob: Dictionary = gp.problem
	check.call(not spent_none and not prob.is_empty() and prob.tier == 1 and prob.blanks == 1 and gp.mode == "chant", "[+] with 0 points starts a Spell Chant for that stat: tier 1, one blank [R9]")
	pr.chant_streak = 3
	var bad := []
	for a in prob.answers: bad.append("nope")
	var r1: Dictionary = gp.submit_chant(bad)
	check.call(not r1.ok and pr.chant_streak == 0 and gp.problem.key == prob.key and st.points.magic_pow == 0 and gp.mode == "chant", "wrong: fizzle, the streak resets, the same problem stays")
	var lvl0: int = pr.level
	var exp0: int = pr.exp
	var r2: Dictionary = gp.submit_chant(prob.answers)
	check.call(r2.ok and st.points.magic_pow == 0 and st.chant_points.magic_pow == 1 and absf(st.value("magic_pow", s.run.time) - 105.0) < 0.01 and pr.level == lvl0 and pr.exp == exp0 and st.unspent == 0, "right (tier 1): Magic Pow +5, no EXP, no level, no stat point [R9/R10]")
	check.call(int(s.meta.chant_tier.magic_pow) == 1 and gp.mode == "browse", "the stat's chant tier rises (kept in the profile)")
	var nxt: Dictionary = gp.start_chant("magic_pow")
	check.call(nxt.blanks == 2 and nxt.tier == 1, "the next Magic Pow chant is harder: 2 blanks")
	gp.cancel_chant()
	var hp_c: Dictionary = gp.start_chant("max_hp")
	check.call(hp_c.blanks == 1 and hp_c.tier == 1, "difficulty is per stat: Max HP is still at 1 blank")
	# A hit mid-chant restarts it with a fresh problem [R1].
	var k0: String = gp.problem.key
	c.player.health.apply(DamagePacket.new(98001, "test", "infected", 5.0, "bite"), s.run.time)
	check.call(gp.visible and gp.mode == "chant" and gp.problem.key != k0 and gp.problem.tier == 1, "a hit during a chant restarts it with a fresh problem, same tier, panel open")
	var hp_ok: Dictionary = gp.submit_chant(gp.problem.answers)
	check.call(hp_ok.ok and absf(st.value("max_hp", s.run.time) - 105.0) < 0.01, "a Max HP chant: +5 HP")
	# A tier-4 chant pays x1.5 [R10]: all pages unlocked, Atk Spd chanted 6 times before.
	for id in all5: s.meta.unlock(id)
	s.meta.chant_tier["atk_spd"] = 6
	var t4: Dictionary = gp.start_chant("atk_spd")
	var atk0: float = st.value("atk_spd", s.run.time)
	gp.submit_chant(t4.answers)
	check.call(t4.tier == 4 and absf(st.value("atk_spd", s.run.time) - atk0 - 0.25 * 1.5) < 0.001, "a tier-%d chant on Atk Spd pays 0.25 x 1.5 = +0.375/s [R10]" % t4.tier)

	# ---- Reset stats [R4] -----------------------------------------------------------------
	# A capped stat refuses before the chant starts.
	st.points.mov_spd = 48
	check.call(gp.start_chant("mov_spd").is_empty() and gp.mode != "chant", "a stat at its cap refuses the chant before it starts [R9]")
	st.points.mov_spd = 0
	st.unspent = 2
	gp.allocate("mov_spd"); gp.allocate("max_mp")
	var armed: int = gp.reset_stats()
	var still: bool = st.points.mov_spd == 1
	var refund: int = gp.reset_stats()
	check.call(armed == -1 and still and refund == 5 and st.unspent == 5 and absf(st.value("magic_pow", s.run.time) - 100.0) < 0.01 and absf(st.value("atk_spd", s.run.time) - 5.0) < 0.01 and absf(st.value("mov_spd", s.run.time) - 10.0) < 0.01, "Reset stats (pressed twice): every stat at base, 2 allocated + 3 chants back as 5 points (1 per chant, whatever its tier)")
	check.call(int(s.meta.chant_tier.magic_pow) == 1, "a reset keeps the chant difficulty")
	s.handle_action("grimoire")

	# ---- death [R5] ---------------------------------------------------------------------------
	st.unspent = 0
	s.restart()
	await tree.physics_frame
	check.call(int(s.meta.chant_tier.get("magic_pow", 0)) == 1 and int(s.meta.chant_tier.get("max_hp", 0)) == 1 and s.stats.points.magic_pow == 0 and s.stats.unspent == 0, "after a death: chant gains are gone, each stat's chant tier is kept")
	s.meta.reset()
	s.restart()
	await tree.physics_frame
