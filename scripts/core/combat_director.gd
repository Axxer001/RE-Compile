extends RefCounted
# AggroTracker (Tech Spec §5, plan §4.7): the player is in combat while any
# enemy is aggroed; after the last one drops (de-aggro or death), a 10 s
# cooldown runs, then the player is out of combat (what Sage Arts, P4, waits
# for). Mission progress lives in Progression.

const OUT_OF_COMBAT_S := 3.0 # [Sir R12] the Sage Arts countdown (was 10 s [spec])

var in_combat := false
var last_aggro := -INF   # sim time an enemy was last aggroed

func reset() -> void:
	in_combat = false
	last_aggro = -INF

func update(now: float, any_aggroed: bool) -> void:
	if any_aggroed:
		in_combat = true
		last_aggro = now
	elif in_combat and now - last_aggro + 1e-6 >= OUT_OF_COMBAT_S:
		in_combat = false

# Seconds left on the out-of-combat countdown (0 when out of combat or still fighting).
func countdown(now: float) -> float:
	if not in_combat: return 0.0
	return maxf(0.0, OUT_OF_COMBAT_S - (now - last_aggro))
