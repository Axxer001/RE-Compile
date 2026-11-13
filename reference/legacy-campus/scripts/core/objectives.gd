extends RefCounted
# Level objectives (rehaul §4.7, replaces the retired career/quota). One level
# run: recover every research file by hacking its terminal, then reach the
# exit. Hacking counts the file at once (nothing to carry). `seed` fixes the
# puzzle answers for this run.

const Puzzles = preload("res://scripts/world/hack_puzzles.gd")

var seed := 0
var retrieved := {}         # research id -> true
var hints := false          # hacking hints unlocked (grading note)
var level_complete := false

func _init(seed_value := -1) -> void:
	seed = seed_value if seed_value >= 0 else randi()

static func research_ids() -> Array:
	var out := []
	for id in Puzzles.TERMINALS: out.append(Puzzles.TERMINALS[id].research)
	return out

func total() -> int:
	return research_ids().size()

func count() -> int:
	return retrieved.size()

# Returns true when the file is new.
func retrieve(research_id: String) -> bool:
	if not research_id in research_ids() or retrieved.has(research_id): return false
	retrieved[research_id] = true
	return true

func has_all() -> bool:
	return count() == total()

func current_text() -> String:
	if level_complete: return "Level complete"
	if not has_all(): return "Recover research files %d/%d" % [count(), total()]
	return "Reach the exit"

# A new run of the level: files and hints reset, the seed is kept.
func reset() -> void:
	retrieved.clear()
	hints = false
	level_complete = false
