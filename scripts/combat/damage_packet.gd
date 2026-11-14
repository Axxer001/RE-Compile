extends RefCounted
# One damage event. `action_id` identifies the attack/shot/blast/fire tick that
# produced it; a target accepts each action_id at most once, so overlapping
# hurtbox contacts from one swing or pellet cannot stack.

const KINDS := ["melee", "bullet", "blast", "fire", "bite", "test", "coin"] # coin: Heads or Tails [2026-11-14]

var action_id: int
var source_id: String
var source_faction: String
var amount: float
var kind: String

func _init(action: int, source: String, faction: String, damage: float, damage_kind := "melee") -> void:
	action_id = action
	source_id = source
	source_faction = faction
	amount = damage
	kind = damage_kind

func valid() -> bool:
	return action_id > 0 and amount > 0.0 and is_finite(amount) and source_faction != "" and kind in KINDS
