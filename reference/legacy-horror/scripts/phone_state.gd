extends RefCounted
# The player's phone (career-long). Tools unlock and stay unlocked:
#   map     always: room outlines, rooms visited tonight, terminals, the van.
#   journal always: clues read from notes and terminals (unique entries).
#   intel   from hacking the Lab 2 admin terminal: loot and Shambler markers.
#   hints   from the grading-script note in the lab, or the van shop.

signal changed

const TOOLS := ["map", "journal", "intel", "hints"]

var unlocked := {"map": true, "journal": true, "intel": false, "hints": false}
var journal: Array[Dictionary] = [] # {id, title, text}
var visited := {}                   # room id -> true (tonight; cleared each night)

func unlock(tool: String) -> bool:
	if not tool in TOOLS or unlocked.get(tool, false): return false
	unlocked[tool] = true
	changed.emit()
	return true

func has(tool: String) -> bool:
	return unlocked.get(tool, false)

# Adds a clue once; returns true if it was new.
func add_entry(id: String, title: String, text: String) -> bool:
	for e in journal:
		if e.id == id: return false
	journal.append({"id": id, "title": title, "text": text})
	changed.emit()
	return true

func entry(id: String) -> Dictionary:
	for e in journal:
		if e.id == id: return e
	return {}

func visit(room: String) -> void:
	if room != "" and not visited.has(room):
		visited[room] = true
		changed.emit()

func new_night() -> void:
	visited.clear()
