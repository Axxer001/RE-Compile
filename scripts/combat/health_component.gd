extends Node
# Sole owner of an actor's hit points. Damage arrives only as DamagePackets and
# is resolved here: each action applies once per target, same-faction damage is
# refused, declared immunity windows block listed kinds, HP clamps at zero and
# death latches once. A dead actor rejects further damage and actions.
# Time is the simulation clock passed in by the caller (RunState.time), never
# a node timer, so pause freezes immunity windows too.

signal damaged(packet: RefCounted, applied: float)
signal died(packet: RefCounted)

@export var max_hp := 100.0
@export var faction := "player"

var hp := 100.0
var dead := false
var _seen := {}            # action_id -> true
var _immune_until := -1.0
var _immune_from := -INF
var _immune_kinds: Array = []

func _ready() -> void:
	reset()

func reset() -> void:
	hp = max_hp
	dead = false
	_seen.clear()
	_immune_until = -1.0
	_immune_from = -INF
	_immune_kinds = []

# Grants immunity to the listed damage kinds for simulation times in [from, until).
func grant_immunity(until: float, kinds: Array, from := -INF) -> void:
	_immune_from = from
	_immune_until = until
	_immune_kinds = kinds.duplicate()

func immune_to(kind: String, now: float) -> bool:
	return now >= _immune_from and now < _immune_until and (kind in _immune_kinds or "*" in _immune_kinds) # "*" = every kind

func accepts_actions() -> bool:
	return not dead

# Returns "applied", "lethal", "invalid", "friendly", "duplicate", "immune" or "dead".
# Only "applied"/"lethal" change state; a refused packet is not remembered, so the
# same action can still land once the reason clears (e.g. immunity ends).
func apply(packet: RefCounted, now: float) -> String:
	if not packet.valid(): return "invalid"
	if dead: return "dead"
	if packet.source_faction == faction: return "friendly"
	if _seen.has(packet.action_id): return "duplicate"
	if immune_to(packet.kind, now): return "immune"
	_seen[packet.action_id] = true
	var applied: float = minf(packet.amount, hp)
	hp -= applied
	damaged.emit(packet, applied)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit(packet)
		return "lethal"
	return "applied"
