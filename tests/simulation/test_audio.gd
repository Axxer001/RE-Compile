extends RefCounted
# R7 audio [Sir: "Music only in combat, should have quiet forest ambience"]:
# the buses, the synthesised loops, the combat fade in (1.5 s) and out (3 s,
# after the 3 s grace [R12]), the ambience duck, and per-bus volumes from settings.

const DT := 1.0 / 60.0
const AudioMix = preload("res://scripts/audio/audio_mix.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	c.park_enemies(["sprite_1"])
	var foe: CharacterBody3D = c.enemies["sprite_1"]
	var mix: Node = c.audio
	var buses := ["Master", "Music", "Ambience", "SFX", "UI"]
	check.call(buses.all(func(b): return AudioServer.get_bus_index(b) >= 0) and c.sfx.players.all(func(p): return p.bus == "SFX") and mix.music.bus == "Music" and mix.ambience.bus == "Ambience", "buses Master, Music, Ambience, SFX and UI; effects, music and ambience on their own")
	var amb: AudioStreamWAV = AudioMix.stream("ambience")
	var mus: AudioStreamWAV = AudioMix.stream("music")
	check.call(amb.loop_mode == AudioStreamWAV.LOOP_FORWARD and mus.loop_mode == AudioStreamWAV.LOOP_FORWARD and absf(amb.data.size() / 2.0 / amb.mix_rate - 16.0) < 0.01 and absf(mus.data.size() / 2.0 / mus.mix_rate - 8.0) < 0.01, "a 16 s forest loop and an 8 s combat loop, both looping (synthesised: nothing to license)")
	var pa: float = AudioMix.peak("ambience")
	var pm: float = AudioMix.peak("music")
	check.call(pa > 0.05 and pa < 0.6 and pm > 0.3 and pm < 0.99, "the ambience is quiet (peak %.2f), the music louder (peak %.2f), neither clipped" % [pa, pm])

	# Exploring: ambience only.
	steps(c, 0.5)
	check.call(not c.director.in_combat and mix.level == 0.0 and not mix.music.playing and is_equal_approx(mix.ambience_gain(), 1.0), "exploring: no music, full ambience")
	# Combat starts: music in over 1.5 s, ambience ducks.
	foe.aggroed = true
	steps(c, 0.75 + DT)
	var half_in: float = mix.level
	steps(c, 0.8)
	check.call(absf(half_in - 0.5) < 0.03 and is_equal_approx(mix.level, 1.0) and mix.music.playing and absf(mix.ambience_gain() - 0.4) < 0.01 and absf(mix.ambience.volume_db - linear_to_db(0.4)) < 0.05 and absf(mix.music.volume_db) < 0.05, "in combat: music fades in over 1.5 s (%.2f at 0.75 s), the ambience ducks to 40%%" % half_in)
	# The last aggro drops: music holds through the 3 s grace [R12], then fades out over 3 s.
	foe.aggroed = false
	steps(c, 2.8)
	var held: float = mix.level
	steps(c, 0.2 + 1.5 + DT)
	var half_out: float = mix.level
	steps(c, 1.7)
	check.call(is_equal_approx(held, 1.0) and absf(half_out - 0.5) < 0.04 and mix.level == 0.0 and not mix.music.playing and is_equal_approx(mix.ambience_gain(), 1.0), "out of combat: the music holds the 3 s grace (%.2f), fades out over 3 s (%.2f half-way), ambience back" % [held, half_out])

	# Volumes per bus from the settings.
	var st: RefCounted = s.settings
	st.set_value("vol_music", 0.5)
	st.set_value("vol_ambience", 0.25)
	var mdb: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var adb: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ambience"))
	check.call(absf(mdb - linear_to_db(0.5)) < 0.01 and absf(adb - linear_to_db(0.25)) < 0.01, "volume sliders set the bus levels (music %.1f dB, ambience %.1f dB)" % [mdb, adb])
	check.call(st.save("user://test_audio_settings.cfg") == OK, "audio settings save")
	var t: RefCounted = st.get_script().new()
	t.load_from("user://test_audio_settings.cfg")
	check.call(is_equal_approx(t.volumes.music, 0.5) and is_equal_approx(t.volumes.ambience, 0.25), "volumes round-trip through the settings file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_audio_settings.cfg"))
	st.reset()
	t.reset()
	check.call(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(st.DEFAULT_VOLUMES.music)), "reset restores the default volumes")
	s.restart()
	await tree.physics_frame
	check.call(mix.level == 0.0 and not mix.music.playing, "restart: no music")

	# ---- the three Rank E spells' sounds [Sir, 2026-11-14] ----------------------------------------
	var fx: Node3D = c.sfx
	var spell_sounds := ["breath_loop", "firefly_launch", "firefly_pop", "charge_hum", "nuke"]
	var peaks := {}
	for r in spell_sounds: peaks[r] = fx.peak(r)
	var loud_ok: bool = peaks.values().all(func(v): return v > 0.08 and v < 0.95)
	check.call(loud_ok and fx.streams.breath_loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and fx.streams.charge_hum.loop_mode == AudioStreamWAV.LOOP_FORWARD and fx.streams.nuke.loop_mode == AudioStreamWAV.LOOP_DISABLED, "spell sounds render, none clipped (peaks %s); the breath roar and the charge hum loop, the boom does not" % str(peaks.values().map(func(v): return snappedf(v, 0.01))))
	var g150: float = fx.boom_gain(150.0)
	check.call(fx.boom_player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE and fx.boom_gain(5.0) <= 1.0 + 1e-6 and g150 > 0.2 and g150 < 0.4 and fx.boom_player.max_distance >= 300.0 and peaks.nuke <= 0.85, "the Explosion boom is positional with distance falloff: full at 5 m (capped at 0 dB, recipe peak %.2f), %.1f dB at 150 m: heard across the forest" % [peaks.nuke, linear_to_db(g150)])
	var dropped0: int = fx.pops_dropped
	var let := 0
	for i in 30:
		if fx.play_capped("firefly_pop", Vector3.ZERO, 100.0): let += 1 # 30 missiles landing at once
	check.call(let == fx.POP_CAP and fx.pops_dropped == dropped0 + 30 - fx.POP_CAP, "30 Firefly hits at once: %d pops play, the rest are dropped (no clipping pile-up)" % let)
	# The loops follow the spells: breath for its channel; the charge builds, then is cut off.
	var pc: Node3D = c.pcombat
	c.park_enemies()
	pc.mp = pc.max_mp(s.run.time)
	c.spells.start_breath(s.grimoire.page("dragons_breath"), "spell_1", s.run.time)
	var breath_on: bool = fx.loop_playing("breath")
	c.spells.end_breath()
	var breath_off: bool = not fx.loop_playing("breath") and fx.loops.breath.stopping
	c.spells.start_explosion(s.grimoire.page("explosion"), "spell_3", s.run.time)
	var hum_on: bool = fx.loop_playing("charge")
	steps(c, 10.0)
	var pitch_mid: float = fx.loops.charge.player.pitch_scale
	c.player.health.apply(c.DamagePacket.new(98001, "test", "infected", 1.0, "bite"), s.run.time) # breaks the charge
	var hum_cut: bool = not fx.loop_playing("charge") and not fx.loops.charge.player.playing
	check.call(breath_on and breath_off and hum_on and pitch_mid > 1.0 and pitch_mid < 1.25 and hum_cut, "the breath roar plays while breathing and fades out after; the charge hum rises (pitch %.2f at half charge) and cuts off when a hit breaks it" % pitch_mid)
	var booms0: int = fx.count("nuke")
	c.spells.reset()
	pc.ready_at.erase("spell_3")
	pc.mp = pc.max_mp(s.run.time)
	c.spells.start_explosion(s.grimoire.page("explosion"), "spell_3", s.run.time)
	var bp := Vector3(70, 0, 20)
	c.spells.charge.point = bp
	steps(c, 20.2)
	var boomed: bool = fx.count("nuke") == booms0 + 1 and fx.boom_player.global_position.distance_to(bp) < 0.01 and not fx.loop_playing("charge")
	check.call(boomed, "a full charge: the hum stops and the boom sounds at the blast point")
	c.spells.reset()
	s.restart()
	await tree.physics_frame
