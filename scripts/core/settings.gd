extends RefCounted
# Player settings: mouse sensitivity (hip + ADS), invert Y and
# keybinds. Pure data; owned by GameSession like TimeService. Saved to
# user://settings.cfg (ConfigFile). Defaults are captured from the project
# InputMap the first time this is constructed, so project.godot stays the
# source of truth. See docs/settings-menu-plan.md.

signal changed

const PATH := "user://settings.cfg"
const SLOTS := 2 # primary + secondary binding per action
const LAYOUT := 3 # key layout version: 1 = shooter, 2 = Grimoire (docs/pivot-grimoire-plan.md §3), 3 = + Effects tab on T [R14]; older saved bindings are dropped
# Rebindable actions in menu order; pause/confirm stay fixed (Esc/Enter).
const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "jump", "crouch", "dash",
	"attack", "special", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "interact", "grimoire", "effects_tab"]
const LABELS := {"move_forward": "Forward", "move_back": "Back", "move_left": "Left", "move_right": "Right",
	"jump": "Jump / Double jump", "crouch": "Crouch / Slide", "dash": "Dash", "attack": "Basic attack", "special": "Special attack",
	"skill_1": "Skill 1", "skill_2": "Skill 2", "spell_1": "Spell 1", "spell_2": "Spell 2", "spell_3": "Spell 3",
	"interact": "Interact", "grimoire": "Grimoire", "effects_tab": "Effects"}

const DEFAULT_HIP := 0.12 # degrees per pixel (the old fps_controller constant)
const DEFAULT_ADS := 0.8

var hip := DEFAULT_HIP
var ads_mult := DEFAULT_ADS
var ads_fov_scale := true # also scale ADS by tan(ads_fov/2)/tan(fov/2), Apex-style
var invert_y := false
var damage_numbers := true # floating damage numbers [R14]
var infinite_mana := false # debug [Sir, 2026-11-14]: "Infinite Mana + No Cooldown": MP never spent or required, every cooldown 0
const DEFAULT_GRASS := 25.0
var grass_distance := DEFAULT_GRASS # metres of grass round the player [Sir, 2026-11-13]
const DEFAULT_VOLUMES := {"master": 1.0, "music": 0.8, "ambience": 0.8, "sfx": 1.0, "ui": 1.0} # per bus, 0..1 [Sir R7]
var volumes := DEFAULT_VOLUMES.duplicate()
var path := PATH         # where save()/load_from() go by default; "" = not persisted (GameSession under tests)
var bindings := {}       # action -> Array of event dicts (len SLOTS; {} = empty)
var defaults := {}       # same shape, from the project InputMap

# Pristine defaults, shared by every instance. They come from project.godot
# (ProjectSettings "input/<action>"), not the live InputMap: an earlier rebind
# in the same process changes the InputMap, and capturing from it made
# "defaults" (and reset) inherit that rebind. Actions not in project.godot fall
# back to the InputMap as first seen by any Settings.
static var _pristine: Dictionary = {}

static func _project_events(action: String) -> Array:
	var key := "input/" + action
	if ProjectSettings.has_setting(key):
		var entry = ProjectSettings.get_setting(key)
		if entry is Dictionary and entry.has("events"): return entry.events
	return InputMap.action_get_events(action) if InputMap.has_action(action) else []

func _init() -> void:
	if _pristine.is_empty():
		for action in ACTIONS:
			var row := []
			for e in _project_events(action):
				var d := encode(e)
				if not d.is_empty() and row.size() < SLOTS: row.append(d)
			while row.size() < SLOTS: row.append({})
			_pristine[action] = row
	defaults = _pristine.duplicate(true)
	bindings = defaults.duplicate(true)

# --- events <-> dicts -------------------------------------------------------

static func encode(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return {"type": "key", "code": code} if code != 0 else {}
	if e is InputEventMouseButton:
		return {"type": "mouse", "button": e.button_index}
	return {}

static func decode(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.code)
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.button)
			return m
	return null

static func describe(d: Dictionary) -> String:
	match d.get("type", ""):
		"key":
			var code := int(d.code)
			# Show the key printed on this layout; headless has no layout.
			if DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_keycode_from_physical(code)
			return OS.get_keycode_string(code)
		"mouse":
			var names := {1: "Mouse 1", 2: "Mouse 2", 3: "Mouse 3", 4: "Wheel Up", 5: "Wheel Down", 6: "Wheel Left", 7: "Wheel Right", 8: "Mouse 4", 9: "Mouse 5"}
			# Buttons past 9 (gaming mice): numbered on from Mouse 5.
			return names.get(int(d.button), "Mouse %d" % (int(d.button) - 4))
	return "—"

static func same(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and a == b

# --- sensitivity -------------------------------------------------------------

# Degrees per pixel for a look delta. aim_t: 0 hip .. 1 fully aimed (blends).
func sensitivity(aim_t := 0.0, fov := 90.0, ads_fov := 65.0) -> float:
	var ads := hip * ads_mult
	if ads_fov_scale and fov > 0.0:
		ads *= tan(deg_to_rad(ads_fov) * 0.5) / tan(deg_to_rad(fov) * 0.5)
	return lerpf(hip, ads, clampf(aim_t, 0.0, 1.0))

# Look delta in degrees (x right, y down) for a mouse motion in pixels.
func look_degrees(relative: Vector2, aim_t := 0.0, fov := 90.0, ads_fov := 65.0) -> Vector2:
	var d := relative * sensitivity(aim_t, fov, ads_fov)
	if invert_y: d.y = -d.y
	return d

func set_value(key: String, value: Variant) -> void:
	match key:
		"hip": hip = clampf(float(value), 0.01, 1.0)
		"ads_mult": ads_mult = clampf(float(value), 0.1, 2.0)
		"ads_fov_scale": ads_fov_scale = bool(value)
		"invert_y": invert_y = bool(value)
		"damage_numbers": damage_numbers = bool(value)
		"infinite_mana": infinite_mana = bool(value)
		"grass_distance": grass_distance = clampf(float(value), 20.0, 120.0)
		_:
			if key.begins_with("vol_") and DEFAULT_VOLUMES.has(key.trim_prefix("vol_")):
				volumes[key.trim_prefix("vol_")] = clampf(float(value), 0.0, 1.0)
	changed.emit()

# --- bindings ----------------------------------------------------------------

# Action already using this event (other than action/slot), or "".
func conflict(event: Dictionary, action: String, slot: int) -> String:
	for other in bindings:
		for i in SLOTS:
			if other == action and i == slot: continue
			if same(bindings[other][i], event): return other
	return ""

# Bind; on conflict with swap=true the other action gets this slot's old event.
# Returns the conflicting action ("" if none). Without swap a conflict binds
# nothing, so the caller can ask the player first.
func rebind(action: String, slot: int, event: Dictionary, swap := false) -> String:
	if not action in bindings or slot < 0 or slot >= SLOTS: return ""
	var other := conflict(event, action, slot)
	if other != "" and not swap: return other
	if other != "":
		for i in SLOTS:
			if same(bindings[other][i], event):
				bindings[other][i] = bindings[action][slot].duplicate()
	bindings[action][slot] = event.duplicate()
	apply_bindings()
	changed.emit()
	return other

func clear(action: String, slot: int) -> void:
	if action in bindings and slot >= 0 and slot < SLOTS:
		bindings[action][slot] = {}
		apply_bindings()
		changed.emit()

func reset() -> void:
	bindings = defaults.duplicate(true)
	hip = DEFAULT_HIP
	ads_mult = DEFAULT_ADS
	ads_fov_scale = true
	invert_y = false
	damage_numbers = true
	infinite_mana = false
	grass_distance = DEFAULT_GRASS
	volumes = DEFAULT_VOLUMES.duplicate()
	apply_bindings()
	changed.emit()

# Writes bindings into the live InputMap (an InputRouter must re-read it).
func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for d in bindings[action]:
			var e := decode(d)
			if e: InputMap.action_add_event(action, e)

# --- persistence ---------------------------------------------------------------

func save(to := "") -> int:
	var path_now: String = to if to != "" else path
	if path_now == "": return OK # not persisted (tests)
	var cf := ConfigFile.new()
	cf.set_value("mouse", "hip", hip)
	cf.set_value("mouse", "ads_mult", ads_mult)
	cf.set_value("mouse", "ads_fov_scale", ads_fov_scale)
	cf.set_value("mouse", "invert_y", invert_y)
	cf.set_value("display", "damage_numbers", damage_numbers)
	cf.set_value("debug", "infinite_mana", infinite_mana)
	cf.set_value("display", "grass_distance", grass_distance)
	for k in volumes: cf.set_value("audio", k, volumes[k])
	cf.set_value("meta", "layout", LAYOUT)
	for action in bindings: cf.set_value("bindings", action, bindings[action])
	return cf.save(path_now)

# Missing or corrupt file: keep defaults (and rewrite them). Returns true if loaded.
func load_from(from := "") -> bool:
	var path_now: String = from if from != "" else path
	if path_now == "": return false
	var cf := ConfigFile.new()
	if cf.load(path_now) != OK:
		save(path_now)
		apply_bindings()
		return false
	set_value("hip", cf.get_value("mouse", "hip", DEFAULT_HIP))
	set_value("ads_mult", cf.get_value("mouse", "ads_mult", DEFAULT_ADS))
	ads_fov_scale = bool(cf.get_value("mouse", "ads_fov_scale", true))
	invert_y = bool(cf.get_value("mouse", "invert_y", false))
	damage_numbers = bool(cf.get_value("display", "damage_numbers", true))
	infinite_mana = bool(cf.get_value("debug", "infinite_mana", false))
	set_value("grass_distance", cf.get_value("display", "grass_distance", DEFAULT_GRASS))
	for k in DEFAULT_VOLUMES: volumes[k] = clampf(float(cf.get_value("audio", k, DEFAULT_VOLUMES[k])), 0.0, 1.0)
	# A file from an older key layout keeps its mouse settings but not its binds
	# (shooter binds like interact on E would collide with the new defaults).
	var same_layout: bool = int(cf.get_value("meta", "layout", 1)) == LAYOUT
	for action in ACTIONS:
		if not same_layout or not cf.has_section_key("bindings", action): continue
		var row = cf.get_value("bindings", action)
		if row is Array and row.size() == SLOTS and row.all(func(d): return d is Dictionary):
			bindings[action] = row.duplicate(true)
	if not same_layout: save(path_now) # rewrite in the new layout
	apply_bindings()
	changed.emit()
	return true
