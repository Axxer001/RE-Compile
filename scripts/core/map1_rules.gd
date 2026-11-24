extends RefCounted
## Map 1, the Dark Forest [Sir, 2026-11-20; docs/spec-map1-dark-forest.md]: the
## rules, as pure seeded data (no nodes). The world (map1_world.gd, main.gd)
## tells it where the player is and what died; it answers with events.
##
## Phases: "camp" -> "pathway" -> "entering" (in a closed combat chunk) ->
## "starting" (the 5 m blackout: the border goes, the field wraps) -> "combat" ->
## "ending" (the blackout again: the border and the exits load) -> "cooldown"
## (2 min, exits open) -> "pathway" (an exit taken) ... or, if the cooldown runs out
## in the chunk, "starting" again. No combat ever starts in a pathway.
## Visibility drives it [Sir, 2026-11-22; docs/plan-map1-visibility.md]: a combat
## chunk's fight starts once the player is RAMP_M inside (at full 60 m visibility).

# ---- tuning (spec §2-§4) -------------------------------------------------------------
const T := {
	"fade_down_s": 3.0,         # a blackout: visibility fades to VIS.blackout ...
	"hold_s": 0.5,              # ... holds while the world loads and unloads (the swap is at its middle) ...
	"fade_up_s": 1.5,           # ... and opens out again
	"spawn_every_s": 3.0,       # one roll each
	"spawn_chance": 0.7,        # [proposed] the roll spawns an enemy
	"max_alive": 5,
	"kills_goal": 20,
	"cooldown_s": 120.0,
	"two_exits": 0.3,           # chance of a second pathway out
	"pathway_m": Vector2(30, 90),
}
# Visibility, the fog's opaque distance in m [Sir, 2026-11-22; the pathway's 20 m is the plan's].
const VIS := {"camp": 30.0, "pathway": 20.0, "peace": 60.0, "combat": 30.0, "blackout": 5.0}
const RAMP_M := 3.0             # entering a pathway or a chunk: visibility moves to the new zone's over these metres
const MIX := [["sprite", 0.4], ["ghoul", 0.4], ["mortus", 0.2]]  # spawn mix
const DROP := {"sprite": 0.2, "ghoul": 0.2, "mortus": 0.5}        # page drop per kill

var rng := RandomNumberGenerator.new()
var phase := "camp"
var chunks := 0                 # combat chunks reached this run
var chunk_fights := 0           # combats started in the current chunk
var objective := {}             # {kind: "page"|"kills", kills, goal, met}
var phase_t := 0.0              # seconds in the current phase (the blackouts' clock)
var resume := ""                # a cancelled "starting" goes back to this phase
var spawn_s := 0.0
var cooldown_left := 0.0
var exits := 0                  # pathway entrances open (cooldown)

func reset(seed_value: int) -> void:
	rng.seed = seed_value
	phase = "camp"
	chunks = 0
	chunk_fights = 0
	objective = {}
	phase_t = 0.0
	resume = ""
	spawn_s = 0.0
	cooldown_left = 0.0
	exits = 0

func _go(next: String) -> void:
	phase = next
	phase_t = 0.0

# ---- draws ------------------------------------------------------------------------------

## Which enemy (spawn mix).
func pick_kind() -> String:
	var r := rng.randf()
	for e in MIX:
		r -= float(e[1])
		if r < 0.0: return e[0]
	return MIX[MIX.size() - 1][0]

func pathway_length() -> float:
	return rng.randf_range(T.pathway_m.x, T.pathway_m.y)

# ---- the player's whereabouts (the world calls these) ----------------------------------

## The player stepped into a pathway (Pathway #0 from the camp, or an exit).
func enter_pathway() -> void:
	_go("pathway")
	objective = {}
	exits = 0

## The player reached a new combat chunk at the end of a pathway.
func enter_chunk() -> void:
	_go("entering")
	chunks += 1
	chunk_fights = 0

func _start_combat(pages_missing: bool) -> Dictionary:
	_go("combat")
	var first := chunk_fights == 0
	chunk_fights += 1
	objective = {"kind": "page" if first and pages_missing else "kills", "kills": 0, "goal": int(T.kills_goal), "met": false}
	spawn_s = 0.0
	return {"event": "combat_start", "objective": objective.kind}

## The swap moment of a blackout: the fade down plus half the hold.
static func swap_s() -> float:
	return float(T.fade_down_s) + float(T.hold_s) * 0.5

## One frame. `settled`: the player is inside the combat chunk, at least RAMP_M past
## its entrance (full visibility); `alive`: enemies alive now; `pages_missing`: an
## available page is not found yet. Returns events: {event: combat_starting |
## start_cancelled | combat_start | spawn | combat_end | exits_open | exits_close, ...}.
## combat_start and exits_open fire at a blackout's swap moment (the world swaps then).
func step(dt: float, settled: bool, alive: int, pages_missing: bool) -> Array:
	var out := []
	phase_t += dt
	match phase:
		"entering":
			if settled:
				resume = "entering"
				_go("starting")
				out.append({"event": "combat_starting"})
		"starting":
			if not settled: # stepped back out before the swap: the fog lifts again
				_go(resume)
				out.append({"event": "start_cancelled"})
			elif phase_t + 1e-6 >= swap_s():
				if resume == "cooldown": out.append({"event": "exits_close"})
				exits = 0
				out.append(_start_combat(pages_missing))
		"combat":
			if not objective.met:
				spawn_s += dt
				while spawn_s + 1e-6 >= float(T.spawn_every_s):
					spawn_s -= float(T.spawn_every_s)
					if alive < int(T.max_alive) and rng.randf() < float(T.spawn_chance):
						out.append({"event": "spawn", "kind": pick_kind()})
						alive += 1
			elif alive <= 0:
				_go("ending")
				out.append({"event": "combat_end"})
		"ending":
			if phase_t + 1e-6 >= swap_s():
				_go("cooldown")
				cooldown_left = float(T.cooldown_s)
				exits = 2 if rng.randf() < float(T.two_exits) else 1
				out.append({"event": "exits_open", "count": exits})
		"cooldown":
			cooldown_left = maxf(cooldown_left - dt, 0.0)
			if cooldown_left <= 0.0 and settled: # the cooldown ran out in the chunk: fight again
				resume = "cooldown"
				_go("starting")
				out.append({"event": "combat_starting"})
	return out

## The blackouts' visibility (m), or -1 outside them (the world sets it by place).
func timed_visibility() -> float:
	var down := float(T.fade_down_s)
	var half := float(T.hold_s) * 0.5
	var up := float(T.fade_up_s)
	match phase:
		"starting": return lerpf(float(VIS.peace), float(VIS.blackout), smoothstep(0.0, down, phase_t))
		"ending": return lerpf(float(VIS.combat), float(VIS.blackout), smoothstep(0.0, down, phase_t))
		"combat":
			if phase_t < half + up: return lerpf(float(VIS.blackout), float(VIS.combat), smoothstep(half, half + up, phase_t))
			return float(VIS.combat)
		"cooldown":
			if phase_t < half + up: return lerpf(float(VIS.blackout), float(VIS.peace), smoothstep(half, half + up, phase_t))
			return float(VIS.peace)
	return -1.0

## An enemy died in combat. Returns true when it drops a page (only on a page
## objective, until one drops). A kill objective counts the kill.
func on_kill(kind: String) -> bool:
	if phase != "combat" or objective.is_empty(): return false
	objective.kills = int(objective.kills) + 1
	if objective.met: return false
	if objective.kind == "page":
		if rng.randf() < float(DROP.get(kind, 0.0)):
			objective.met = true
			return true
		return false
	if int(objective.kills) >= int(objective.goal): objective.met = true
	return false

## The objectives line (spec §5): "Find a page", "Defeat 20 · 12/20",
## "Clear the field · 3 left", "Choose a path", "Pathway".
func hud_line(alive: int) -> String:
	match phase:
		"camp": return "Camp · enter the forest"
		"pathway": return "Pathway"
		"entering": return "Combat chunk"
		"starting": return "The fog closes in"
		"ending": return "The field is clear"
		"combat":
			if objective.met: return "Clear the field · %d left" % alive
			if objective.kind == "page": return "Find a page"
			return "Defeat %d · %d/%d" % [int(objective.goal), int(objective.kills), int(objective.goal)]
		"cooldown": return "Choose a path" if cooldown_left > 0.0 else "The fog stirs" # the 2 min is a notice when the fight ends [Sir, 2026-11-22]
	return ""
