extends StaticBody3D
# A hackable computer in the world (interactable layer). Holds the per-night
# puzzle state: attempts, lockout and whether it was solved. The puzzle answer
# comes from hack_puzzles.gd and the career seed. The world opens the terminal
# overlay on E and calls submit() with what the player entered.

const Puzzles = preload("res://scripts/world/hack_puzzles.gd")

var terminal_id := ""
var kind := ""          # "password" | "choice"
var puzzle := {}        # choice puzzles only
var password := ""      # password puzzles only
var attempts := 0       # wrong answers since the last lockout
var locked_until := -1.0
var solved := false

func setup(id: String, at: Vector3, seed: int) -> void:
	terminal_id = id
	name = id
	position = at
	kind = Puzzles.TERMINALS[id].kind
	collision_layer = 0b100 # interactable only: rays find it, bodies ignore it
	collision_mask = 0
	set_meta("terminal", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 0.6, 0.4)
	col.shape = box
	col.position.y = 0.3
	add_child(col)
	var glow := OmniLight3D.new() # the screen lights the desk a little
	glow.light_color = Color(0.4, 0.8, 1.0)
	glow.light_energy = 0.4
	glow.omni_range = 1.6
	glow.position = Vector3(0, 0.4, 0.3)
	add_child(glow)
	reset_for_night(seed)

func reset_for_night(seed: int) -> void:
	attempts = 0
	locked_until = -1.0
	solved = false
	if kind == "password": password = Puzzles.lab_password(seed)
	else: puzzle = Puzzles.office_puzzle(seed)

func label() -> String:
	return Puzzles.TERMINALS[terminal_id].label

func locked(now: float) -> bool:
	return now < locked_until

# {result: "solved" | "wrong" | "lockout" | "locked" | "already", attempts_left}
# answer: the typed password, or the chosen option index (0-2) as a String.
func submit(answer: String, now: float) -> Dictionary:
	if solved: return {"result": "already", "attempts_left": 0}
	if locked(now): return {"result": "locked", "attempts_left": 0}
	var right := false
	if kind == "password":
		right = answer.strip_edges().to_upper() == password
	else:
		right = answer.is_valid_int() and int(answer) == int(puzzle.answer)
	if right:
		solved = true
		return {"result": "solved", "attempts_left": Puzzles.MAX_ATTEMPTS - attempts}
	attempts += 1
	if attempts >= Puzzles.MAX_ATTEMPTS:
		attempts = 0
		locked_until = now + Puzzles.LOCKOUT_S
		return {"result": "lockout", "attempts_left": 0}
	return {"result": "wrong", "attempts_left": Puzzles.MAX_ATTEMPTS - attempts}
