extends Node
# Sole owner of an actor's endurance. Everything that costs endurance goes
# through spend() (all-or-nothing, for actions) or drain() (continuous, for
# running); regeneration happens only in tick(). Time is the simulation clock.

@export var max_value := 100.0
@export var regen_per_s := 12.0
@export var run_drain_per_s := 20.0
@export var run_minimum := 2.0       # running needs more than this
@export var regen_delay_s := 1.0     # after an action spend (ARCHITECTURE: attacks/dodge)

var value := 100.0
var _regen_after := -1.0
var _drained_this_tick := false

func _ready() -> void:
	reset()

func reset() -> void:
	value = max_value
	_regen_after = -1.0
	_drained_this_tick = false

func can_afford(cost: float) -> bool:
	return cost <= value + 0.0001

func can_run() -> bool:
	return value > run_minimum

# Action cost: either the whole cost is paid or nothing changes.
func spend(cost: float, now: float) -> bool:
	if cost < 0.0 or not can_afford(cost):
		return false
	value = maxf(0.0, value - cost)
	_regen_after = now + regen_delay_s
	return true

# Running cost for this tick; clamps at zero.
func drain_running(delta: float) -> void:
	value = maxf(0.0, value - run_drain_per_s * delta)
	_drained_this_tick = true

# Once per simulation tick, after movement/actions.
func tick(delta: float, now: float) -> void:
	if not _drained_this_tick and now >= _regen_after:
		value = minf(max_value, value + regen_per_s * delta)
	_drained_this_tick = false
