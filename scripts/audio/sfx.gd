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
}
# NoiseService kinds -> recipe (gameplay noises that also make a sound)
const NOISE_SOUNDS := {"footsteps": "footstep", "door": "door", "scan": "scan", "alarm": "alarm",
	"blast": "blast", "fire": "fire", "throw": "throw"}

var streams := {}       # recipe -> AudioStreamWAV
var players: Array[AudioStreamPlayer3D] = []
var next_player := 0
var played: Array = []  # [{recipe, pos}] recent plays (tests, debugging)
var muted := false

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
	return w

# Peak absolute sample of a rendered recipe (tests: not silent, not clipped flat).
func peak(recipe: String) -> float:
	var d: PackedByteArray = streams[recipe].data
	var m := 0
	for i in range(0, d.size(), 2): m = maxi(m, absi(d.decode_s16(i)))
	return m / 32767.0
