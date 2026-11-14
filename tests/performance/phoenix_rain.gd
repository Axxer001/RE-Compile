extends Node
# Call of the Phoenix rain cost [2026-11-14]: the forest at the dense seed, 20
# Sprites chasing an immune player at the camp clearing, with or without
# Call of the Phoenix raining on three areas round the player non-stop.
#   godot --path . res://tests/performance/phoenix_rain.tscn -- --rain=1 --out=<dir>
#   --burn=1 (no rain, every Sprite kept burning) splits Burn's cost from the rain's;
#   --far=2.5 moves the areas out. Measured 2026-11-14: rain p50 4.8 ms, Burn alone
#   4.6, neither 3.4 - the cost is the burning crowd, not the rain itself.
# Frame times on the real clock; 3 s warm-up, 20 s sample; compared with the
# 7.7 ms p95 budget. Validity: frames, live enemies, rain actually falling.
const Forest = preload("res://scripts/world/dark_forest.gd")
const WARM_S := 3.0
const SAMPLE_S := 20.0
const BUDGET := 7.7
var main: Node3D
var rain_on := false
var burn_only := false # --burn=1: no rain, but every Sprite kept burning (splits Burn's cost from the rain's)
var gamble := false # --gamble=1: the Gambler set instead: Heads at 5/s and Tails every 2 s into the crowd, all 20 with Pocket Change and Heavy Pockets
var _gt := 0.0
var nonum := false # --nonum: damage numbers off (cost split)
var far := 1.0 # --far=2.5 puts the areas 2.5x further out (overdraw check)
var out_dir := "res://"
var frames: Array = []
var elapsed := 0.0
var last_us := 0
var drops := 0
var max_shots := 0
var steps: Array = [] # CPU time of each simulation step (ms), to split sim from render

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rain="): rain_on = a.trim_prefix("--rain=") == "1"
		elif a.begins_with("--burn="): burn_only = a.trim_prefix("--burn=") == "1"
		elif a == "--nonum": nonum = true
		elif a.begins_with("--gamble="): gamble = a.trim_prefix("--gamble=") == "1"
		elif a.begins_with("--far="): far = float(a.trim_prefix("--far="))
		elif a.begins_with("--out="): out_dir = a.trim_prefix("--out=").trim_suffix("/") + "/"
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = Forest.densest_seed()
	add_child(main)
	await get_tree().physics_frame
	main.spawning = false
	if nonum: main.damage_numbers.enabled = false
	var i := 0
	for id in main.enemies:
		var e: CharacterBody3D = main.enemies[id]
		e.reset_to(Vector3(66.0 + (i % 5) * 4.0, 0, 112.0 + (i / 5) * 3.0), 180.0)
		e.health.max_hp = 1.0e9
		e.health.reset()
		e._go(e.State.CHASE)
		i += 1
	main.player.health.grant_immunity(INF, ["*"])

func _physics_process(delta: float) -> void:
	if main == null or main.player == null: return
	if rain_on and main.spells.rain.is_empty() and main.spells.calling.is_empty():
		var sp = main.spells
		var pg: Resource = main.session.grimoire.page("call_of_the_phoenix")
		var at: Vector3 = main.player.global_position
		sp.start_call(pg, "spell_2", main.session.run.time)
		for off in [Vector3(10, 0, 0), Vector3(-6, 0, 9), Vector3(-6, 0, -9)]:
			sp.calling.areas.append(at + off * far)
			sp.calling.rings.append(main.vfx.ring(at + off * far, sp.CALL.area_r, Color(1.0, 0.35, 0.1)))
		sp._end_call(main.session.run.time)
	var t0 := Time.get_ticks_usec()
	if gamble:
		var gt: float = main.session.run.time
		var gb = main.gambler
		var eye: Vector3 = main.player.camera.global_position
		var foes: Array = main.combat_targets()
		for tg in foes:
			if not main.effects.has(tg.id, "Pocket Change", gt): main.effects.apply(String(tg.id), "Pocket Change", 10.0, gt, "player", 100.0)
			if not main.effects.has(tg.id, "Heavy Pockets", gt): main.effects.apply(String(tg.id), "Heavy Pockets", 10.0, gt, "player", 100.0)
		_gt += delta
		if _gt >= 0.2 and not foes.is_empty():
			_gt = 0.0
			var tg: Dictionary = foes[int(gt * 5.0) % foes.size()]
			gb.throw("heads", eye, (tg.pos - eye).normalized(), 1.0, 100.0, null, gt)
			if int(gt * 5.0) % 10 == 0: gb.throw("tails", eye, (tg.pos - eye).normalized(), 1.0, 100.0, tg.pos, gt)
	if burn_only:
		for id in main.enemies:
			if not main.effects.has(id, "Burn", main.session.run.time): main.effects.apply(String(id), "Burn", 5.0, main.session.run.time, "player", 100.0)
	main.session.step(delta)
	if elapsed > WARM_S: steps.append((Time.get_ticks_usec() - t0) / 1000.0)
	if elapsed > WARM_S: max_shots = maxi(max_shots, main.projectiles.shots.size())

func _process(_d: float) -> void:
	if main == null: return
	var now := Time.get_ticks_usec()
	if last_us == 0:
		last_us = now
		return
	var ms := (now - last_us) / 1000.0
	last_us = now
	elapsed += ms / 1000.0
	if elapsed > WARM_S: frames.append(ms)
	if elapsed >= WARM_S + SAMPLE_S:
		set_process(false)
		set_physics_process(false)
		var drops_n: int = main.spells.log.filter(func(h): return h.get("spell", "") == "call_drop").size()
		var sorted := frames.duplicate()
		sorted.sort()
		var n := sorted.size()
		var p95: float = sorted[int(n * 0.95)]
		var ok: bool = n > 300 and main.alive_count() == 20 and (not rain_on or drops_n > 300) and (not gamble or main.gambler.hits.size() > 100)
		steps.sort()
		var m := {"step_p50_ms": steps[int(steps.size() * 0.5)], "step_p95_ms": steps[int(steps.size() * 0.95)], "rain": rain_on, "frames": n, "p50_ms": sorted[int(n * 0.5)], "p95_ms": p95, "p99_ms": sorted[mini(n - 1, int(n * 0.99))],
			"within_budget": p95 <= BUDGET, "drops": drops_n, "max_shots": max_shots, "gamble": gamble, "coin_hits": main.gambler.hits.size(), "alive": main.alive_count()}
		var f := FileAccess.open(out_dir + "metrics.json", FileAccess.WRITE)
		if f: f.store_string(JSON.stringify(m, "  "))
		print("RESULT ", JSON.stringify({"status": "PASS" if ok else "FAIL", "metrics": m}))
		get_tree().quit(0 if ok else 1)
