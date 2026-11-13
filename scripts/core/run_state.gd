extends RefCounted
# Run identity and the single simulation clock (ADR-002 §1). Owns nothing else:
# HP, inventory, quest progress stay with their components. A restart creates
# a new RunState instead of clearing scattered flags.

enum Lifecycle { RUNNING, COMPLETE }

static var _issued := 0

var run_id: int
var seed: int
var tick := 0
var time := 0.0
var lifecycle := Lifecycle.RUNNING
var _instance_serial := 0

# Stable, unique-per-run ids for owned item/weapon instances ("wpn_1", "stk_2").
func next_instance_id(prefix: String) -> String:
	_instance_serial += 1
	return "%s_%d" % [prefix, _instance_serial]

func _init(seed_value := -1) -> void:
	_issued += 1
	run_id = _issued
	seed = seed_value if seed_value >= 0 else randi()

func advance(delta: float) -> void:
	tick += 1
	time += delta
