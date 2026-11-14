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
# Immunity windows, one per source [2026-11-14]: a dash's i-frames or the end of
# Flight no longer cut short All In's 10 s Invincibility. A new grant from the
# same source replaces that source's window; immune while any window covers it.
var _immunity := {}        # source -> [from, until, kinds]
# (packet) -> bool: asked before a lethal hit lands; true = the actor does not die
# (Rise of the Phoenix revives the player in place). The guard restores HP itself.
var death_guard: Callable

func _ready() -> void:
	reset()

func reset() -> void:
	hp = max_hp
	dead = false
	_seen.clear()
	_immunity.clear()

# Grants immunity to the listed damage kinds for simulation times in [from, until).
func grant_immunity(until: float, kinds: Array, from := -INF, source := "") -> void:
	_immunity[source] = [from, until, kinds.duplicate()]

func immune_to(kind: String, now: float) -> bool:
	for w in _immunity.values():
		if now >= float(w[0]) and now < float(w[1]) and (kind in w[2] or "*" in w[2]): return true # "*" = every kind
	return false

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
	if packet.amount >= hp and death_guard.is_valid() and death_guard.call(packet):
		damaged.emit(packet, minf(packet.amount, max_hp))
		return "revived"
	var applied: float = minf(packet.amount, hp)
	hp -= applied
	damaged.emit(packet, applied)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit(packet)
		return "lethal"
	return "applied"
