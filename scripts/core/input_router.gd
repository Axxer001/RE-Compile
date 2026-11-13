extends RefCounted
# Named actions and focus arbitration (ported from the 2D campus build).
# Exactly one context is active. Only GAMEPLAY yields movement/interaction.
# OVERLAY (grimoire/terminal) blocks input but keeps the world live;
# PAUSE freezes the simulation. Any context change flushes held input: a key
# already down stays ignored until it is released, so returning from typing or
# a menu cannot leak a buffered move or shot. Bindings come from the project
# InputMap (project.godot [input]). Mouse look is not an action: the player
# controller consumes mouse motion only while `look_enabled()`.

enum Context { GAMEPLAY, OVERLAY, PAUSE, DEATH, EXTRACTION }

const ACTIONS := ["move_forward", "move_left", "move_back", "move_right", "dash", "crouch", "jump",
	"attack", "special", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "interact", "grimoire", "effects_tab", "pause", "confirm"]
# Held/edge intents sampled every tick (everything else is a discrete press).
const HELD := ["dash", "crouch", "jump", "attack", "special", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "interact"]

var keys := {}    # action -> first physical keycode bound
var buttons := {} # action -> first mouse button bound
var binds := {}   # action -> every binding (both settings slots): [{"key": code} or {"mouse": index}]

func _init() -> void:
	refresh()

# Re-read the InputMap (after a rebind in the settings menu).
func refresh() -> void:
	keys.clear(); buttons.clear(); binds.clear()
	for action in ACTIONS:
		if not InputMap.has_action(action): continue
		var row := []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
				row.append({"key": code})
				if not keys.has(action): keys[action] = code
			elif event is InputEventMouseButton:
				row.append({"mouse": event.button_index})
				if not buttons.has(action): buttons[action] = event.button_index
		binds[action] = row

var context := Context.GAMEPLAY
var overlay := ""
# Physical key state; tests may replace it with a synthetic source.
var key_source: Callable = func(key: int) -> bool: return Input.is_physical_key_pressed(key)
var mouse_source: Callable = func(button: int) -> bool: return Input.is_mouse_button_pressed(button)
var _suppressed := {}
# Mouse-wheel notches (and tilt) are events, never "held": each notch is a
# one-tick press of every action bound to it (one notch = one jump, or one
# forward tap for a tap strafe, as in Apex). Cleared by sample().
const PULSE_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
var _pulse := {}

# Feed raw input events; returns true if the event was a wheel pulse.
func note_event(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton and event.pressed and event.button_index in PULSE_BUTTONS): return false
	var hit := false
	for action in binds:
		for b in binds[action]:
			if b.get("mouse", -1) == event.button_index:
				_pulse[action] = true
				hit = true
	return hit

func down(action: String) -> bool:
	if _pulse.has(action): return true
	for b in binds.get(action, []):
		if b.has("key") and key_source.call(b.key): return true
		if b.has("mouse") and mouse_source.call(b.mouse): return true
	return false

func held(action: String) -> bool:
	if not down(action):
		_suppressed.erase(action)
		return false
	return not _suppressed.has(action)

func flush() -> void:
	for action in binds:
		if down(action):
			_suppressed[action] = true

func set_context(next: Context, overlay_name := "") -> void:
	if next == context and overlay_name == overlay:
		return
	context = next
	overlay = overlay_name
	flush()

func open_overlay(overlay_name: String) -> void:
	set_context(Context.OVERLAY, overlay_name)

func close_overlay() -> void:
	if context == Context.OVERLAY:
		set_context(Context.GAMEPLAY)

func look_enabled() -> bool:
	return context == Context.GAMEPLAY

# Continuous intent for this tick. held() is evaluated in every context so
# releases clear suppression even while blocked.
# move: x = strafe right (+) / left (-), y = forward (+) / back (-).
func sample() -> Dictionary:
	var move := Vector2(
		float(held("move_right")) - float(held("move_left")),
		float(held("move_forward")) - float(held("move_back")))
	var out := {"move": move}
	for action in HELD: out[action] = held(action)
	if context != Context.GAMEPLAY:
		out.move = Vector2.ZERO
		for action in HELD: out[action] = false
	_pulse.clear() # each wheel notch counts for exactly one tick
	return out

func action_for_event(event: InputEvent) -> String:
	var want := {}
	if event is InputEventKey and event.pressed and not event.echo:
		want = {"key": event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode}
	elif event is InputEventMouseButton and event.pressed:
		want = {"mouse": event.button_index}
	if want.is_empty(): return ""
	for action in binds:
		for b in binds[action]:
			if b == want: return action
	return ""

# Discrete actions. Escape closes an overlay first; a later Escape pauses.
# Tab toggles the Grimoire overlay.
func press(action: String) -> String:
	match action:
		"grimoire":
			if context == Context.GAMEPLAY:
				open_overlay("grimoire")
				return "grimoire_opened"
			if context == Context.OVERLAY and overlay == "grimoire":
				close_overlay()
				return "overlay_closed"
			return ""
		"effects_tab": # T toggles the Effects overlay [R14]
			if context == Context.GAMEPLAY:
				open_overlay("effects")
				return "effects_opened"
			if context == Context.OVERLAY and overlay == "effects":
				close_overlay()
				return "overlay_closed"
			return ""
		"pause":
			if context in [Context.DEATH, Context.EXTRACTION]:
				return "" # the end panel owns focus; nothing to pause
			if context == Context.OVERLAY:
				close_overlay()
				return "overlay_closed"
			if context == Context.PAUSE:
				set_context(Context.GAMEPLAY)
				return "resumed"
			set_context(Context.PAUSE)
			return "paused"
	return ""
