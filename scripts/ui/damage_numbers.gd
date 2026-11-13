extends Node3D
# Floating damage numbers [Sir R14]: on each applied hit a billboard number
# rises 0.8 m from the hit point and fades over 0.8 s with a little sideways
# drift. White for direct hits, orange for Burn ticks, larger for the special.
# Burn ticks on one enemy within 0.25 s merge into one number. A pool of 40
# labels: when all are in use the oldest is reused, so never more than 40 on
# screen. Presentation only; main feeds it from the health signals and ticks
# it from publish(). The settings toggle "Damage numbers" turns spawning off.

const POOL := 40
const LIFE_S := 0.8
const RISE_M := 0.8
const MERGE_S := 0.25
const COLORS := {"direct": Color(1, 1, 1), "burn": Color(1.0, 0.6, 0.2), "special": Color(1.0, 0.92, 0.6)}
const SIZES := {"direct": 44, "burn": 38, "special": 64}

var enabled := true
var _labels: Array = []     # Label3D pool
var _free: Array = []       # labels not on screen
var _live: Array = []       # {label, t, start, drift, amount, kind, target}
var _rng := RandomNumberGenerator.new()
var spawned := 0            # numbers spawned (tests; merges do not count)

func _ready() -> void:
	_rng.seed = 1412
	for i in POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.pixel_size = 0.006
		l.outline_size = 8
		l.outline_modulate = Color(0, 0, 0, 0.9)
		l.visible = false
		add_child(l)
		_labels.append(l)
		_free.append(l)

# One applied hit of `amount` at `at`. kind: direct | burn | special. A Burn
# tick on a target that showed one less than MERGE_S ago adds to that number.
func spawn(at: Vector3, amount: float, kind := "direct", target := "") -> void:
	if not enabled or amount <= 0.0: return
	if kind == "burn" and target != "":
		for n in _live:
			if n.kind == "burn" and n.target == target and n.t < MERGE_S:
				n.amount += amount
				n.label.text = _fmt(n.amount)
				return
	var n := {}
	if _free.is_empty():
		n = _live.pop_front() # all 40 in use: the oldest is reused
	else:
		n = {"label": _free.pop_back()}
	var l: Label3D = n.label
	n.t = 0.0
	n.start = at
	n.drift = Vector3(_rng.randf_range(-0.25, 0.25), 0, _rng.randf_range(-0.25, 0.25))
	n.amount = amount
	n.kind = kind
	n.target = target
	l.text = _fmt(amount)
	l.modulate = COLORS.get(kind, COLORS.direct)
	l.font_size = SIZES.get(kind, SIZES.direct)
	l.position = at
	l.visible = true
	_live.append(n)
	spawned += 1

static func _fmt(x: float) -> String:
	return str(roundi(x)) if x >= 1.0 else "%.1f" % x

func tick(delta: float) -> void:
	for n in _live.duplicate():
		n.t += delta
		var u: float = clampf(n.t / LIFE_S, 0.0, 1.0)
		var l: Label3D = n.label
		l.position = n.start + Vector3(0, RISE_M * u, 0) + n.drift * u
		l.modulate.a = 1.0 - u * u
		if n.t >= LIFE_S:
			l.visible = false
			_live.erase(n)
			_free.append(l)

func live_count() -> int:
	return _live.size()

func live_texts() -> Array:
	return _live.map(func(n): return n.label.text)

func clear() -> void:
	for n in _live:
		n.label.visible = false
		_free.append(n.label)
	_live.clear()
