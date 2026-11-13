extends Node
# Music and ambience [Sir R7]: "Music only in combat, quiet forest ambience".
#   Exploring: forest ambience only (wind, leaves, distant birds and insects,
#   an occasional creak), no music.
#   In combat (CombatDirector.in_combat): music fades in over 1.5 s and the
#   ambience ducks under it; once out of combat (after the 3 s grace [R12]) the
#   music fades out over 3 s.
# Buses Master / Music / Ambience / SFX / UI, volumes from the settings.
# Both loops are synthesised in code (nothing to download or license), once
# per process. Presentation only: gameplay never reads it.

const BUSES := ["Music", "Ambience", "SFX", "UI"] # Master always exists
const BUS_OF := {"master": "Master", "music": "Music", "ambience": "Ambience", "sfx": "SFX", "ui": "UI"}
const RATE := 22050
const AMBIENCE_S := 16.0
const MUSIC_S := 8.0          # 4 bars at 120 bpm
const FADE_IN_S := 1.5        # [Sir R7]
const FADE_OUT_S := 3.0       # [Sir R7]
const DUCK := 0.6             # ambience drops by this share at full music [design]

var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var level := 0.0              # music 0..1 (the fade)

static var _streams := {}

static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

# Volumes 0..1 per bus ("master", "music", "ambience", "sfx", "ui").
static func apply_volumes(v: Dictionary) -> void:
	ensure_buses()
	for key in v:
		var i := AudioServer.get_bus_index(String(BUS_OF.get(key, "")))
		if i >= 0: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(v[key]), 0.0001)))

func _ready() -> void:
	ensure_buses()
	ambience = AudioStreamPlayer.new()
	ambience.name = "Ambience"
	ambience.bus = "Ambience"
	ambience.stream = stream("ambience")
	add_child(ambience)
	music = AudioStreamPlayer.new()
	music.name = "Music"
	music.bus = "Music"
	music.stream = stream("music")
	music.volume_db = linear_to_db(0.0001)
	add_child(music)
	ambience.play()

# Shutdown / world teardown: stop the players and drop the static stream cache,
# which otherwise outlives the scene tree and is reported as leaked at exit
# (AudioStreamWAV + its playing AudioStreamPlaybackWAV) [2026-11-14].
func _exit_tree() -> void:
	if ambience: ambience.stop()
	if music: music.stop()
	_streams.clear()

func reset() -> void:
	level = 0.0
	music.stop()
	_apply()

# Per tick (presentation clock): fade toward the combat state.
func tick(delta: float, in_combat: bool) -> void:
	var target := 1.0 if in_combat else 0.0
	if level < target: level = minf(target, level + delta / FADE_IN_S)
	elif level > target: level = maxf(target, level - delta / FADE_OUT_S)
	if level > 0.0 and not music.playing: music.play()
	elif level <= 0.0 and music.playing: music.stop()
	_apply()

func _apply() -> void:
	music.volume_db = linear_to_db(maxf(level, 0.0001))
	ambience.volume_db = linear_to_db(1.0 - DUCK * level)

func ambience_gain() -> float:
	return 1.0 - DUCK * level

static func stream(which: String) -> AudioStreamWAV:
	if not _streams.has(which): _streams[which] = _render_ambience() if which == "ambience" else _render_music()
	return _streams[which]

static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = data.size() / 2
	return w

# Quiet forest: wind (low-passed noise breathing slowly), leaf rustles, a few
# distant bird chirps, a faint insect shimmer and one creak per loop.
static func _render_ambience() -> AudioStreamWAV:
	var n := int(AMBIENCE_S * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF0E57
	var rustles := []
	var t := 0.6
	while t < AMBIENCE_S - 1.0:
		rustles.append(t)
		t += rng.randf_range(1.5, 3.5)
	var chirps := []
	for i in 7: chirps.append(rng.randf_range(0.5, AMBIENCE_S - 0.5))
	var creak_at := rng.randf_range(4.0, AMBIENCE_S - 4.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	var wind := 0.0
	var wind2 := 0.0
	var leaf := 0.0
	var ph_bird := 0.0
	var ph_ins := 0.0
	var ph_creak := 0.0
	for i in n:
		var ts := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		wind += (noise - wind) * 0.02
		wind2 += (wind - wind2) * 0.05
		var breath := 0.55 + 0.45 * sin(TAU * ts / AMBIENCE_S * 2.0) * sin(TAU * ts / AMBIENCE_S * 3.0 + 1.0)
		var v := wind2 * 2.2 * breath
		for r in rustles:
			var u: float = (ts - r) / 0.7
			if u > 0.0 and u < 1.0:
				leaf += (noise - leaf) * 0.35
				v += leaf * 0.09 * sin(PI * u) * (0.6 + 0.4 * sin(ts * 70.0))
		for c in chirps:
			var u: float = (ts - c) / 0.09
			if u > 0.0 and u < 1.0:
				ph_bird += TAU * (2600.0 + 1200.0 * u) / RATE
				v += sin(ph_bird) * 0.035 * sin(PI * u)
		ph_ins += TAU * 4300.0 / RATE
		v += sin(ph_ins) * 0.006 * (0.5 + 0.5 * sin(TAU * 31.0 * ts))
		var cu := (ts - creak_at) / 0.6
		if cu > 0.0 and cu < 1.0:
			ph_creak += TAU * (85.0 + 25.0 * sin(cu * 9.0)) / RATE
			v += (fmod(ph_creak, TAU) / TAU - 0.5) * 0.05 * sin(PI * cu)
		# Seamless loop: fade the last and first 50 ms toward each other.
		var edge := minf(ts, AMBIENCE_S - ts)
		if edge < 0.05: v *= edge / 0.05
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(data)

# Combat loop: 120 bpm, A minor. Kick on the beat, hats on the off-beats, a
# driving bass ostinato and a low pad.
static func _render_music() -> AudioStreamWAV:
	var n := int(MUSIC_S * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0BA7
	var beat := 0.5
	var bass_notes := [55.0, 55.0, 65.41, 49.0] # A1 A1 C2 G1, one per bar
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph_b := 0.0
	var ph_p := 0.0
	var ph_k := 0.0
	var lp := 0.0
	for i in n:
		var ts := float(i) / RATE
		var bt := fmod(ts, beat)
		var bar := int(ts / (beat * 4.0)) % 4
		var noise := rng.randf_range(-1.0, 1.0)
		var kick_env := exp(-bt * 18.0)
		ph_k += TAU * (45.0 + 90.0 * exp(-bt * 30.0)) / RATE
		var v := sin(ph_k) * kick_env * 0.55
		var ht := fmod(ts + beat * 0.5, beat)
		v += noise * exp(-ht * 60.0) * 0.08
		var eighth := fmod(ts, beat * 0.5)
		var f: float = bass_notes[bar] * (2.0 if int(ts / (beat * 0.5)) % 4 == 3 else 1.0)
		ph_b += TAU * f / RATE
		var saw := fmod(ph_b, TAU) / TAU * 2.0 - 1.0
		lp += (saw - lp) * 0.08
		v += lp * 0.32 * exp(-eighth * 6.0)
		ph_p += TAU * (f * 2.0) / RATE
		v += (sin(ph_p) + 0.5 * sin(ph_p * 1.5)) * 0.05
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(data)

# Peak of a rendered loop (tests: not silent, not clipped flat).
static func peak(which: String) -> float:
	var d: PackedByteArray = stream(which).data
	var m := 0
	for i in range(0, d.size(), 8): m = maxi(m, absi(d.decode_s16(i)))
	return m / 32767.0
