extends Node3D
# Sound effects, synthesised in code (no audio assets, nothing to license):
# short noise bursts, tones and envelopes rendered once into AudioStreamWAV
# buffers and played through a pool of AudioStreamPlayer3D at the source.
# Gameplay never depends on audio (the AI hears NoiseService events, not
# sound), so muting changes nothing but the mood.

const RATE := 22050
const AudioMix = preload("res://scripts/audio/audio_mix.gd")
const POOL := 16

# recipe -> {seconds, volume_db, max_distance}
const RECIPES := {
	"footstep": [0.07, -14.0, 12.0], "swing": [0.22, -8.0, 10.0], "pistol": [0.3, 0.0, 40.0],
	"shotgun": [0.45, 3.0, 50.0], "rifle": [0.14, -2.0, 40.0], "reload": [0.25, -10.0, 8.0],
	"door": [0.45, -8.0, 14.0], "scan": [0.22, -10.0, 10.0], "alarm": [0.9, 0.0, 30.0],
	"blast": [1.0, 6.0, 60.0], "fire": [0.8, -4.0, 18.0], "throw": [0.2, -10.0, 10.0],
	"scrape": [1.2, -4.0, 14.0], "hit": [0.09, -6.0, 14.0], "bite": [0.35, -4.0, 16.0],
	"pickup": [0.08, -12.0, 6.0], "van": [0.3, -8.0, 10.0], "click": [0.05, -10.0, 6.0],
	"chime": [1.4, -6.0, 40.0], # level / rank up [R15]: two bell notes
	# The three Rank E spells [Sir, 2026-11-14]:
	"breath_loop": [2.0, -5.0, 30.0],    # Dragon's Breath: a flame roar, looped for the whole channel
	"firefly_launch": [0.7, -3.0, 30.0], # the 30-missile volley's whoosh
	"firefly_pop": [0.12, -12.0, 18.0],  # one missile's hit (capped: see play_capped)
	"charge_hum": [2.0, -9.0, 40.0],     # Explosion's charge, looped; it rises in pitch and volume to the blast
	"nuke": [3.6, 0.0, 0.0],             # the eruption: its own long-range player (boom())
	# The Phoenix set [2026-11-14]
	"phoenix_climb": [2.0, -6.0, 30.0],  # Flight's rising whoosh, looped through the climb and hover
	"phoenix_dive": [2.6, -2.0, 40.0],   # the dive: a falling roar (the boom lands at impact)
	"rain_loop": [2.0, -7.0, 40.0],      # Call's storm of fire, looped while it rains
	"rebirth": [1.6, -2.0, 40.0],        # Rise of the Phoenix: a rush of flame and a bright chord
	# The Gambler set [2026-11-14]
	"dice_rattle": [0.6, -6.0, 12.0],    # Let it Ride: the die clatters and lands
	"coin_clink": [0.25, -9.0, 20.0],    # Heads: a coin strikes (each bounce too)
	"ka_ching": [0.7, -4.0, 30.0],       # Tails' blast and the pockets spilling
	"jackpot": [1.8, -2.0, 30.0],        # a 6: the jackpot fanfare
	"addiction_thud": [1.0, -2.0, 20.0], # Gambling Addiction sets in: a low, heavy thud
}
const LOOPED := ["breath_loop", "charge_hum", "phoenix_climb", "rain_loop"]
# The boom carries across the 150 m forest: inverse-distance falloff with a
# wide unit size (gain = unit / distance: -11.5 dB at 150 m), capped at 0 dB up
# close; the recipe peaks at 0.8, so it never clips the master bus.
const BOOM := {"unit_size": 40.0, "max_db": 0.0, "volume_db": 0.0, "max_distance": 400.0}
const POP_CAP := 4          # missile pops at most this many per POP_WINDOW s: 30 hits never stack into clipping
const POP_WINDOW := 0.1
const FADE_IN_S := 0.25
const FADE_OUT_S := 0.35
# NoiseService kinds -> recipe (gameplay noises that also make a sound)
const NOISE_SOUNDS := {"footsteps": "footstep", "door": "door", "scan": "scan", "alarm": "alarm",
	"blast": "blast", "fire": "fire", "throw": "throw"}

var streams := {}       # recipe -> AudioStreamWAV
var players: Array[AudioStreamPlayer3D] = []
var next_player := 0
var played: Array = []  # [{recipe, pos}] recent plays (tests, debugging)
var muted := false
var loops := {}         # name -> {player: AudioStreamPlayer, target_db, gain (0..1 fade), stopping}
var boom_player: AudioStreamPlayer3D
var _pop_times: Array = []
var pops_dropped := 0

func _ready() -> void:
	AudioMix.ensure_buses()
	for key in RECIPES: streams[key] = _render(key)
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice%d" % i
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 3.0
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	boom_player = AudioStreamPlayer3D.new()
	boom_player.name = "Boom"
	boom_player.bus = "SFX"
	boom_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	boom_player.unit_size = BOOM.unit_size
	boom_player.max_db = BOOM.max_db
	boom_player.volume_db = BOOM.volume_db
	boom_player.max_distance = BOOM.max_distance
	boom_player.stream = streams["nuke"]
	add_child(boom_player)

func play(recipe: String, at: Vector3) -> void:
	if not streams.has(recipe): return
	played.append({"recipe": recipe, "pos": at})
	if played.size() > 64: played.pop_front()
	if muted: return
	var p: AudioStreamPlayer3D = players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = streams[recipe]
	p.volume_db = RECIPES[recipe][1]
	p.max_distance = RECIPES[recipe][2]
	p.global_position = at
	p.play()

# A short sound that may come in bursts (Firefly's 30 hits): at most POP_CAP
# per POP_WINDOW seconds of the given clock; the rest are dropped (counted).
func play_capped(recipe: String, at: Vector3, now: float) -> bool:
	_pop_times = _pop_times.filter(func(t): return now - float(t) < POP_WINDOW)
	if _pop_times.size() >= POP_CAP:
		pops_dropped += 1
		return false
	_pop_times.append(now)
	play(recipe, at)
	return true

# A looping sound owned by a spell (the player's own, so not positional): it
# fades in when started and out when stopped (fade_s = 0: cut at once).
func start_loop(name: String, recipe: String) -> void:
	var e: Dictionary = loops.get(name, {})
	if e.is_empty():
		var p := AudioStreamPlayer.new()
		p.name = "Loop_" + name
		p.bus = "SFX"
		p.stream = streams[recipe]
		add_child(p)
		e = {"player": p, "target_db": float(RECIPES[recipe][1]), "gain": 0.0, "stopping": false, "fade_out": FADE_OUT_S, "recipe": recipe}
		loops[name] = e
	e.stopping = false
	e.player.pitch_scale = 1.0
	if not e.player.playing and not muted: e.player.play()
	played.append({"recipe": recipe, "pos": Vector3.ZERO, "loop": name})

func stop_loop(name: String, fade_s := FADE_OUT_S) -> void:
	if not loops.has(name): return
	var e: Dictionary = loops[name]
	e.stopping = true
	e.fade_out = fade_s
	if fade_s <= 0.0:
		e.gain = 0.0
		e.player.stop()

func loop_playing(name: String) -> bool:
	return loops.has(name) and not loops[name].stopping and (loops[name].player.playing or muted)

# Explosion's charge builds to the blast: pitch and volume rise with the charge (0..1).
func set_loop_build(name: String, frac: float) -> void:
	if not loops.has(name): return
	var e: Dictionary = loops[name]
	e.player.pitch_scale = lerpf(0.6, 1.6, clampf(frac, 0.0, 1.0))
	e.build = clampf(frac, 0.0, 1.0)

func _process(delta: float) -> void:
	for name in loops:
		var e: Dictionary = loops[name]
		if e.stopping:
			e.gain = maxf(0.0, e.gain - delta / maxf(e.fade_out, 0.001))
			if e.gain <= 0.0 and e.player.playing: e.player.stop()
		else:
			e.gain = minf(1.0, e.gain + delta / FADE_IN_S)
		var build: float = e.get("build", 1.0)
		var db: float = e.target_db + linear_to_db(maxf(e.gain * lerpf(0.45, 1.0, build), 0.0001))
		e.player.volume_db = db

# The eruption, heard across the forest from the blast point.
func boom(at: Vector3) -> void:
	played.append({"recipe": "nuke", "pos": at})
	boom_player.global_position = at
	if not muted: boom_player.play()

# Linear gain the boom reaches at a distance (the player's inverse-distance model).
func boom_gain(distance: float) -> float:
	return minf(db_to_linear(BOOM.max_db), BOOM.unit_size / maxf(distance, 0.001)) * db_to_linear(BOOM.volume_db)

func stop_all_loops() -> void:
	for name in loops: stop_loop(name, 0.0)

func on_noise(event: Dictionary) -> void:
	if NOISE_SOUNDS.has(event.kind): play(NOISE_SOUNDS[event.kind], event.origin)

func count(recipe: String) -> int:
	return played.filter(func(e): return e.recipe == recipe).size()

# ---- synthesis -----------------------------------------------------------------

static func _render(recipe: String) -> AudioStreamWAV:
	var seconds: float = RECIPES[recipe][0]
	var n := int(seconds * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(recipe)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / seconds
		var noise := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		match recipe:
			"footstep":
				lp += (noise - lp) * 0.25
				v = lp * exp(-t * 60.0)
			"swing":
				lp += (noise - lp) * (0.15 + 0.5 * u)
				v = lp * sin(PI * u) * 0.8
			"pistol", "rifle", "shotgun":
				var k := 30.0 if recipe == "pistol" else (45.0 if recipe == "rifle" else 14.0)
				phase += TAU * (90.0 - 50.0 * u) / RATE
				v = noise * exp(-t * k) + 0.7 * sin(phase) * exp(-t * 12.0)
			"reload":
				v = noise * (exp(-t * 80.0) + exp(-maxf(0.0, t - 0.15) * 80.0) * float(t > 0.15)) * 0.7
			"door":
				phase += TAU * (150.0 - 50.0 * u) / RATE
				v = sign(sin(phase)) * 0.25 * (0.6 + 0.4 * sin(t * 40.0)) * sin(PI * u)
			"scan":
				phase += TAU * 1200.0 / RATE
				v = sin(phase) * 0.4 * float(fmod(t, 0.11) < 0.06)
			"alarm":
				phase += TAU * (900.0 if fmod(t, 0.3) < 0.15 else 700.0) / RATE
				v = sign(sin(phase)) * 0.35
			"blast":
				lp += (noise - lp) * 0.08
				phase += TAU * 40.0 / RATE
				v = (lp * 1.6 + 0.8 * sin(phase)) * exp(-t * 3.5)
			"fire":
				v = noise * 0.6 * float(rng.randf() < 0.02) + noise * 0.05
				v *= sin(PI * u)
			"throw":
				lp += (noise - lp) * 0.3
				v = lp * sin(PI * u) * 0.6
			"scrape":
				lp += (noise - lp) * 0.12
				v = lp * (0.5 + 0.5 * sin(t * 23.0)) * sin(PI * u) * 1.2
			"hit":
				phase += TAU * 110.0 / RATE
				v = (sin(phase) * 0.8 + noise * 0.4) * exp(-t * 40.0)
			"bite":
				phase += TAU * (120.0 + 15.0 * sin(t * 30.0)) / RATE
				v = (fmod(phase, TAU) / TAU - 0.5) * 0.8 * sin(PI * u) + noise * 0.1 * sin(PI * u)
			"pickup", "click":
				phase += TAU * (1600.0 if recipe == "pickup" else 900.0) / RATE
				v = sin(phase) * exp(-t * 50.0) * 0.6
			"van":
				phase += TAU * (660.0 if u < 0.5 else 990.0) / RATE
				v = sin(phase) * 0.4
			"breath_loop": # roaring flame: low-passed noise with a slow surge; seamless loop (sin of whole cycles)
				lp += (noise - lp) * 0.18
				phase += TAU * 55.0 / RATE
				v = (lp * 1.5 + 0.18 * sin(phase)) * (0.75 + 0.25 * sin(TAU * 2.0 * u)) * 0.7
			"firefly_launch": # a rising whoosh
				lp += (noise - lp) * (0.05 + 0.35 * u)
				v = lp * sin(PI * u) * 0.8
			"firefly_pop":
				phase += TAU * (700.0 - 400.0 * u) / RATE
				v = (sin(phase) * 0.5 + noise * 0.3) * exp(-t * 35.0)
			"charge_hum": # a tense rising hum: two detuned tones and a rumble, looping cleanly
				phase += TAU * 110.0 / RATE
				v = (sin(phase) * 0.35 + sin(phase * 1.5 + 0.3) * 0.2 + sin(phase * 0.5) * 0.25) * (0.8 + 0.2 * sin(TAU * 4.0 * u))
			"nuke": # a long, deep eruption: crack, rumble and roll-off, peaking at 0.8
				lp += (noise - lp) * (0.05 + 0.25 * exp(-t * 6.0))
				phase += TAU * (48.0 - 18.0 * u) / RATE
				var env := (1.0 - exp(-t * 80.0)) * exp(-t * 1.1)
				v = (lp * 1.9 + sin(phase) * 0.9 + noise * 0.6 * exp(-t * 12.0)) * env * 0.3
			"phoenix_climb": # wind rushing past: band-limited noise with a slow swell (loops cleanly)
				lp += (noise - lp) * 0.3
				v = lp * (0.6 + 0.4 * sin(TAU * u)) * 0.8
			"phoenix_dive": # a falling roar: noise that darkens and grows as it drops
				lp += (noise - lp) * (0.5 - 0.4 * u)
				v = lp * (0.3 + 0.7 * u) * 0.9
			"rain_loop": # crackling fire: noise bursts on a low bed
				lp += (noise - lp) * 0.12
				v = lp * 0.5 + noise * 0.35 * float(rng.randf() < 0.03)
			"rebirth": # a rush of flame, then a rising major chord
				lp += (noise - lp) * 0.25
				phase += TAU * (330.0 + 220.0 * u) / RATE
				v = lp * exp(-t * 2.5) * 0.6 + (sin(phase) + 0.5 * sin(phase * 1.25) + 0.4 * sin(phase * 1.5)) * minf(1.0, t * 4.0) * exp(-t * 1.6) * 0.22
			"dice_rattle": # five clacks that slow and soften, then the die settles
				var clack := 0.0
				for k in 5:
					var at := 0.07 * k + 0.012 * k * k
					if t >= at: clack += exp(-(t - at) * 90.0) * (1.0 - 0.13 * k)
				lp += (noise - lp) * 0.6
				v = lp * clack * 0.7
			"coin_clink": # a bright metallic ping: inharmonic partials
				phase += TAU * 2637.0 / RATE
				v = (sin(phase) + 0.6 * sin(phase * 1.52) + 0.35 * sin(phase * 2.31)) * exp(-t * 18.0) * 0.32 + noise * exp(-t * 200.0) * 0.3
			"ka_ching": # the drawer clunk, then the bell
				phase += TAU * (1975.5 if t > 0.12 else 140.0) / RATE
				if t < 0.12: v = (noise * 0.5 + sin(phase) * 0.6) * exp(-t * 35.0)
				else: v = (sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 2.76)) * exp(-(t - 0.12) * 4.0) * 0.34
			"jackpot": # a rising major arpeggio over a shimmer
				var notes := [523.25, 659.25, 783.99, 1046.5]
				var ni := mini(int(t / 0.18), 3)
				phase += TAU * float(notes[ni]) / RATE
				var tt := t - 0.18 * ni
				v = (sign(sin(phase)) * 0.18 + sin(phase * 2.0) * 0.12) * exp(-tt * (2.0 if ni == 3 else 6.0)) + noise * 0.05 * sin(PI * u)
			"addiction_thud": # a deep falling thump with a dull ring
				phase += TAU * (70.0 - 35.0 * u) / RATE
				lp += (noise - lp) * 0.05
				v = sin(phase) * exp(-t * 4.0) * 0.8 + lp * exp(-t * 10.0) * 0.4
			"chime":
				var f := 880.0 if t < 0.18 else 1318.5
				var tt := t if t < 0.18 else t - 0.18
				phase += TAU * f / RATE
				v = (sin(phase) + 0.35 * sin(phase * 2.0) + 0.15 * sin(phase * 3.01)) * exp(-tt * 3.5) * 0.35
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if recipe in LOOPED:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w

# Peak absolute sample of a rendered recipe (tests: not silent, not clipped flat).
func peak(recipe: String) -> float:
	var d: PackedByteArray = streams[recipe].data
	var m := 0
	for i in range(0, d.size(), 2): m = maxi(m, absi(d.decode_s16(i)))
	return m / 32767.0
