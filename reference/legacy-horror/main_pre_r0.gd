extends Node3D
# Composition root for the first-person build. Owns the session (tick order),
# the world geometry, the player body, world pickups, the career (money that
# outlives a run) and the minimal HUD. All gameplay state changes happen inside
# simulate(); publish() only updates presentation.

const GameSession = preload("res://scripts/core/game_session.gd")
const Career = preload("res://scripts/core/career.gd")
const Greybox = preload("res://scripts/world/greybox.gd")
const Pickup3D = preload("res://scripts/world/pickup3d.gd")
const NoiseService = preload("res://scripts/world/noise_service.gd")
const ItemDefinition = preload("res://scripts/items/item_definition.gd")
const ItemStack = preload("res://scripts/items/item_stack.gd")
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")
const Inventory = preload("res://scripts/items/inventory.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const NavigationGrid = preload("res://scripts/world/navigation_grid.gd")
const Shambler = preload("res://scripts/actors/shambler.gd")
const DeathPanel = preload("res://scripts/ui/death_panel.gd")
const LoFiView = preload("res://scripts/render/lofi_view.gd")
const Terminal3D = preload("res://scripts/world/terminal3d.gd")
const Interactable3D = preload("res://scripts/world/interactable3d.gd")
const Puzzles = preload("res://scripts/world/hack_puzzles.gd")
const TerminalPanel = preload("res://scripts/ui/terminal_panel.gd")
const PhonePanel = preload("res://scripts/ui/phone_panel.gd")
const VanPanel = preload("res://scripts/ui/van_panel.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const PlayerCombat = preload("res://scripts/combat/player_combat.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const Tracer = preload("res://scripts/actors/tracer.gd")
const Proctor = preload("res://scripts/actors/proctor.gd")
const Blackout = preload("res://scripts/actors/blackout.gd")
const NIGHT_START_MIN := 22 * 60  # the clock reads 22:00 when the night begins
const BLACKOUT_AT := 540.0        # seconds into the night (9 real minutes; 23:30 on the HUD clock)
const BLACKOUT_STEP := 15.0       # one room goes dark every 15 s
const BLACKOUT_ORDER := ["east_corridor", "computer_lab", "faculty_office", "classroom_104"]
const LIT_REACH := 4.5            # metres from a powered lamp counts as lit
const BEAM_HALF_ANGLE := 20.0     # degrees: the flashlight "catches" within this cone
const BEAM_RANGE := 14.0
const LOFI_SHRINK := 3        # 3D drawn at 1/3 resolution, nearest-neighbour upscale

const STEP_INTERVAL := 0.45   # s between footstep noises while moving
const WALK_NOISE := 4.0       # metres heard (crouching makes none)
const SPRINT_NOISE := 9.0

const SCAN_RADIUS := 12.0     # metres; pings through walls
const SCAN_COOLDOWN := 2.0    # seconds
const SCAN_NOISE := 4.0       # metres heard
const SCAN_SHOW_S := 3.0
const EXTRACT_HOLD_S := 1.0   # hold E in the bay to load the van
const DROP_DISTANCE := 0.8

var session: GameSession
var career := Career.new()
var noise := NoiseService.new()
var player: CharacterBody3D
var doors := {}            # id -> door
var pickups := {}          # pickup_id -> Pickup3D (the run's floor state)
var spawn := {}
var extraction := AABB()
var complete := false
# Set by test runners before entering the tree; they then call game_step().
var external_driver := false
var interact_was := false
var flashlight_was := false
var scan_was := false
var drop_was := false
var scan_ready_at := 0.0
var scan_until := 0.0
var last_scan: Array = []     # [{pickup_id, label, value, distance}]
var extract_progress := 0.0
var last_death := {}          # {fine, lost_value}
var notice := ""
var notice_time := 0.0
var hud: CanvasLayer
var prompt: Label
var status: Label
var pause_label: Label
var world_items: Node3D
var lofi: CanvasLayer
var lamps: Array = []
var flicker_t := 0.0
var nav := NavigationGrid.new()
var static_solids: Array = []  # level boxes (doors are added live)
var nav_dirty := false
var enemies := {}              # id -> Shambler
var footstep_timer := 0.0
var death_panel: CanvasLayer
var died_at := -1.0
var terminals := {}            # id -> Terminal3D
var interactables := {}        # id -> Interactable3D (notes, van terminal)
var run_research: Array = []   # research ids copied tonight, not yet delivered
var terminal_panel: CanvasLayer
var phone_panel: CanvasLayer
var van_panel: CanvasLayer
var open_terminal_id := ""
var terminal_status := ""
var van_message := ""
var last_night := {}           # summary of the last night that ended
var after_panel := "restart"   # what the end panel's button does: restart | new_career
var pcombat: Node3D            # PlayerCombat: weapons, reload, dodge, throws
var hazards := Hazards.new()   # throws in flight, frag blasts, molotov fires
var sfx: Node3D                # synthesised sound effects
var inventory_panel: CanvasLayer
var muzzle: OmniLight3D        # muzzle flash (presentation)
var muzzle_until := -1.0
var was_on_floor := true
var fall_speed := 0.0
var tracer: CharacterBody3D
var proctor: CharacterBody3D
var blackout: CharacterBody3D
var staff_nav := NavigationGrid.new() # ignores doors: the Proctor has keys
var dark_rooms := {}           # room id -> true once its lights failed tonight

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.025)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.25, 0.27, 0.25)
	e.ambient_light_energy = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.09, 0.08)
	e.fog_density = 0.04
	# Grade toward a sickly, low-saturation institutional green.
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.72
	e.adjustment_contrast = 1.12
	e.adjustment_brightness = 0.95
	env.environment = e
	add_child(env)
	var built := Greybox.build(self)
	lamps = built.lamps
	doors = built.doors
	spawn = built.spawn
	extraction = built.extraction
	static_solids = built.solids
	nav.setup(built.bounds[0], built.bounds[1])
	for id in doors:
		doors[id].toggled.connect(func(_d, _open) -> void: nav_dirty = true)
	world_items = Node3D.new()
	world_items.name = "WorldItems"
	add_child(world_items)
	session = GameSession.new(self)
	player = PlayerScene.instantiate()
	add_child(player)
	player.look_enabled_fn = func() -> bool: return session.input.look_enabled()
	player.health.died.connect(func(_p) -> void:
		died_at = session.run.time
		apply_death_penalty()
		session.on_player_died())
	player.health.damaged.connect(func(_p, applied: float) -> void:
		if applied > 0.0: session.on_player_damaged())
	var enemy_root := Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)
	for spec in Greybox.ENEMIES:
		var foe: CharacterBody3D = Shambler.new()
		enemy_root.add_child(foe)
		foe.setup(spec.id, spec.at, spec.yaw)
		enemies[spec.id] = foe
		foe.health.damaged.connect(func(_pk, applied: float) -> void:
			if applied > 0.0: foe.alert_to(player.global_position))
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	noise.noise_emitted.connect(sfx.on_noise)
	player.health.damaged.connect(func(pk, applied: float) -> void:
		if applied <= 0.0: return
		sfx.play("bite" if pk.kind in ["bite", "melee"] else "hit", player.eye_position())
		if lofi: lofi.add_kick(clampf(applied * 0.004, 0.02, 0.1), randf_range(-0.03, 0.03)))
	muzzle = OmniLight3D.new()
	muzzle.light_color = Color(1.0, 0.85, 0.55)
	muzzle.light_energy = 4.0
	muzzle.omni_range = 7.0
	muzzle.position = Vector3(0.15, -0.1, -0.7)
	muzzle.visible = false
	player.camera.add_child(muzzle)
	var hazard_root := Node3D.new()
	hazard_root.name = "Hazards"
	add_child(hazard_root)
	hazards.root = hazard_root
	staff_nav.setup(built.bounds[0], built.bounds[1])
	staff_nav.rebuild(static_solids)
	for l in lamps: l.set_meta("room", Greybox.room_at(l.position))
	tracer = Tracer.new()
	enemy_root.add_child(tracer)
	tracer.setup()
	tracer.warned.connect(func() -> void:
		show_notice("Something scrapes in the ceiling above you.", 2.5)
		sfx.play("scrape", player.global_position + Vector3(0, 2.8, 0)))
	tracer.health.damaged.connect(func(_pk, _a: float) -> void: pass)
	proctor = Proctor.new()
	enemy_root.add_child(proctor)
	proctor.setup()
	proctor.locked_door.connect(func(_d) -> void: show_notice("A key turns. The door is locked.", 2.0))
	blackout = Blackout.new()
	enemy_root.add_child(blackout)
	blackout.setup()
	pcombat = PlayerCombat.new()
	pcombat.name = "PlayerCombat"
	add_child(pcombat)
	pcombat.setup(self)
	_build_interactables()
	death_panel = DeathPanel.new()
	add_child(death_panel)
	death_panel.next_night_requested.connect(on_end_panel_button)
	terminal_panel = TerminalPanel.new()
	add_child(terminal_panel)
	terminal_panel.submitted.connect(on_terminal_submit)
	terminal_panel.close_requested.connect(func() -> void: session.handle_action("pause"))
	phone_panel = PhonePanel.new()
	add_child(phone_panel)
	phone_panel.close_requested.connect(func() -> void: session.handle_action("phone"))
	van_panel = VanPanel.new()
	add_child(van_panel)
	van_panel.buy_requested.connect(on_buy)
	van_panel.end_night_requested.connect(end_night_in_van)
	van_panel.close_requested.connect(func() -> void: session.handle_action("pause"))
	inventory_panel = InventoryPanel.new()
	add_child(inventory_panel)
	inventory_panel.equip_requested.connect(func(id: String) -> void:
		if not pcombat.combat.busy(): session.inventory.equip(id)
		else: show_notice("Can't switch weapons now.")
		inventory_panel.refresh(inventory_snapshot()))
	inventory_panel.drop_requested.connect(func(id: String) -> void:
		drop_item(id)
		inventory_panel.refresh(inventory_snapshot()))
	inventory_panel.close_requested.connect(func() -> void: session.handle_action("inventory"))
	_make_hud()
	lofi = LoFiView.new()
	add_child(lofi)
	lofi.setup(player.camera, get_viewport().world_3d, LOFI_SHRINK)
	get_viewport().disable_3d = true # the lo-fi SubViewport draws the world
	reset_run()
	if not external_driver:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _make_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.add_theme_font_size_override("font_size", 22)
	hud.add_child(cross)
	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position += Vector2(-260, -120)
	prompt.custom_minimum_size = Vector2(520, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt)
	status = Label.new()
	status.position = Vector2(24, 20)
	status.add_theme_font_size_override("font_size", 18)
	hud.add_child(status)
	pause_label = Label.new()
	pause_label.text = "PAUSED  -  ESC to resume"
	pause_label.set_anchors_preset(Control.PRESET_CENTER)
	pause_label.position += Vector2(-120, -60)
	pause_label.visible = false
	hud.add_child(pause_label)

func _unhandled_key_input(event: InputEvent) -> void:
	session.handle_event(event)

func _physics_process(delta: float) -> void:
	if external_driver: return
	game_step(delta)

func game_step(delta: float) -> void:
	session.step(delta)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null:
		session.input.flush()

func on_pause_changed(is_paused: bool) -> void:
	pause_label.visible = is_paused
	if not external_driver:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED

# Speed multiplier from carried kg: free up to 5 kg, -2% per kg after, floor 50%.
static func carry_factor(kg: float) -> float:
	return clampf(1.0 - 0.02 * maxf(0.0, kg - 5.0), 0.5, 1.0)

# One unpaused tick of world rules.
func simulate(intent: Dictionary, delta: float) -> void:
	if player.health.dead: return
	player.carry_factor = carry_factor(session.inventory.carried_weight()) * pcombat.combat.movement_factor()
	player.simulate(intent, delta, session.run.time)
	_landing_kick()
	pcombat.simulate(intent, delta, session.run.time)
	footsteps(delta)
	try_flashlight(intent.get("flashlight", false))
	var acted := try_interact(intent.get("interact", false))
	try_extract(intent.get("interact", false) and acted == "", delta)
	try_scan(intent.get("scan", false))
	try_drop(intent.get("drop", false))
	career.phone.visit(Greybox.room_at(player.global_position))
	noise.prune(session.run.time)
	if notice_time > 0.0: notice_time -= delta

func try_flashlight(down: bool) -> void:
	if down and not flashlight_was:
		player.flashlight.visible = not player.flashlight.visible
	flashlight_was = down

# What the crosshair is on: {kind: "pickup"|"door"|"", target}.
func target_in_view() -> Dictionary:
	var hit: Dictionary = player.look_target()
	if hit.is_empty(): return {"kind": "", "target": null}
	var col: Object = hit.collider
	if col != null and col.has_meta("pickup"): return {"kind": "pickup", "target": col.get_meta("pickup")}
	if col != null and col.has_meta("door"): return {"kind": "door", "target": col.get_meta("door")}
	if col != null and col.has_meta("terminal"): return {"kind": "terminal", "target": col.get_meta("terminal")}
	if col != null and col.has_meta("interact"):
		var it: Node3D = col.get_meta("interact")
		return {"kind": it.kind, "target": it}
	return {"kind": "", "target": null}

func door_in_view() -> Node3D:
	var t := target_in_view()
	return t.target if t.kind == "door" else null

# Rising edge of E acts on what the crosshair is on (one press, one action).
# Returns what happened ("" = nothing under the crosshair).
func try_interact(down: bool) -> String:
	var pressed := down and not interact_was
	interact_was = down
	if not pressed: return ""
	var t := target_in_view()
	match t.kind:
		"pickup": return take_pickup(t.target)
		"door":
			var door: Node3D = t.target
			if door.locked:
				show_notice("It's locked.")
				return "locked"
			if door.toggle(get_world_3d().direct_space_state):
				show_notice("Door opened." if door.is_open else "Door closed.")
				noise.emit_noise(door.global_position, 5.0, "door", "player", session.run.time)
				return "door"
			show_notice("Something is in the doorway.")
			return "blocked"
		"terminal": return open_terminal(t.target)
		"note": return read_note(t.target.target_id)
		"van": return open_van()
	return ""

# Full bag: the item stays where it is (partially, for stacks).
func take_pickup(p: Node3D) -> String:
	var inv: RefCounted = session.inventory
	if p.bag_id != "":
		if not inv.upgrade_bag(Inventory.BAG_TIERS[p.bag_id]):
			show_notice("Your bag is already bigger.")
			return "rejected:bag"
		remove_pickup(p)
		show_notice("%s: %d slots." % [p.label(), inv.capacity])
		return "bag"
	var label: String = p.label()
	var result: Dictionary = inv.try_add(p.entry)
	if result.remaining == 0:
		remove_pickup(p)
		show_notice("Picked up %s." % label)
		sfx.play("pickup", p.global_position)
		return "taken"
	show_notice("Bag full." if result.moved == 0 else "Took %d; bag full." % result.moved)
	return "partial" if result.moved > 0 else "rejected:full"

func remove_pickup(p: Node3D) -> void:
	pickups.erase(p.pickup_id)
	p.queue_free()
	p.collision_layer = 0 # gone for rays this tick, not only after the free

func place_pickup(entry: RefCounted, at: Vector3, bag := "") -> Node3D:
	var p: StaticBody3D = Pickup3D.new()
	p.setup(session.run.next_instance_id("pck"), at, entry, bag)
	world_items.add_child(p)
	pickups[p.pickup_id] = p
	return p

# X drops the most recently added entry in front of the player (never through
# a wall: the spot is pulled back from the first solid hit). Spawn first, then
# remove from the bag (inventory.drop rolls back if the spawn fails).
func try_drop(down: bool) -> String:
	var pressed := down and not drop_was
	drop_was = down
	if not pressed: return ""
	var inv: RefCounted = session.inventory
	if inv.entries.is_empty():
		show_notice("Nothing to drop.")
		return "rejected:empty"
	var e: RefCounted = inv.entries.back()
	var label: String = Inventory.definition_of(e).label
	if inv.drop(e.instance_id, func(entry: RefCounted) -> bool: return place_pickup(entry, drop_spot()) != null):
		show_notice("Dropped %s." % label)
		return "dropped"
	return "rejected"

func drop_spot() -> Vector3:
	var fwd := -player.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var from := player.global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * (DROP_DISTANCE + 0.3), 1, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var dist := DROP_DISTANCE
	if not hit.is_empty(): dist = maxf(0.0, from.distance_to(hit.position) - 0.3)
	return player.global_position + fwd * dist

# C pings loot within range (through walls), with a cooldown and a little noise.
func try_scan(down: bool) -> Array:
	var pressed := down and not scan_was
	scan_was = down
	if not pressed: return []
	var now: float = session.run.time
	if now < scan_ready_at - 1e-6:
		show_notice("Scanner recharging.")
		return []
	scan_ready_at = now + SCAN_COOLDOWN
	scan_until = now + SCAN_SHOW_S
	noise.emit_noise(player.global_position, SCAN_NOISE, "scan", "player", now)
	last_scan = []
	for id in pickups:
		var p: Node3D = pickups[id]
		var d := player.global_position.distance_to(p.global_position)
		if d <= SCAN_RADIUS and p.value() > 0:
			last_scan.append({"pickup_id": id, "label": p.label(), "value": p.value(), "distance": d})
	last_scan.sort_custom(func(a, b): return a.distance < b.distance)
	var total := 0
	for s in last_scan: total += s.value
	show_notice("Scan: %d items, PHP %d nearby." % [last_scan.size(), total])
	return last_scan

func in_extraction(point: Vector3) -> bool:
	return extraction.grow(0.001).has_point(point + Vector3(0, 0.5, 0))

# Holding E (with nothing under the crosshair) in the loading bay for 1 s banks
# all loot in the bag. Releasing or stepping out resets the progress.
func try_extract(holding: bool, delta: float) -> int:
	var has_cargo: bool = not session.inventory.loot_entries().is_empty() or not run_research.is_empty()
	if not holding or not in_extraction(player.global_position) or not has_cargo:
		extract_progress = 0.0
		return 0
	extract_progress += delta
	if extract_progress + 1e-6 < EXTRACT_HOLD_S: return 0
	extract_progress = 0.0
	var delivered := deliver_cargo()
	sfx.play("van", player.global_position)
	show_notice("Loaded the van: PHP %d banked%s." % [delivered.amount, ", %d research file(s) delivered" % delivered.research.size() if not delivered.research.is_empty() else ""])
	return delivered.amount

# Everything carried goes into the van: loot is banked, research is recorded.
func deliver_cargo() -> Dictionary:
	var amount := career.bank(session.inventory.unload_loot())
	var fresh := career.bank_research(run_research)
	run_research.clear()
	return {"amount": amount, "research": fresh}

# ---- terminals, notes, phone, van --------------------------------------------

func _build_interactables() -> void:
	var root := Node3D.new()
	root.name = "Interactables"
	add_child(root)
	for id in Greybox.TERMINAL_SPOTS:
		var t: StaticBody3D = Terminal3D.new()
		root.add_child(t)
		t.setup(id, Greybox.TERMINAL_SPOTS[id], career.seed)
		terminals[id] = t
	for id in Greybox.NOTE_SPOTS:
		var n: StaticBody3D = Interactable3D.new()
		root.add_child(n)
		n.setup("note", id, Greybox.NOTE_SPOTS[id][0], Greybox.NOTE_SPOTS[id][1])
		if id in ["note_bulletin", "note_memo", "note_lablog"]: # a sheet of paper / a pinned notice
			var paper := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.03, 0.55, 0.75) if id == "note_bulletin" else Vector3(0.21, 0.004, 0.29)
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.92, 0.9, 0.82)
			pm.material = pmat
			paper.mesh = pm
			paper.position.y = Greybox.NOTE_SPOTS[id][1].y * 0.5
			n.add_child(paper)
		if id == "note_grading": # a yellow sticky note on the desk
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, 0.004, 0.12)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.95, 0.88, 0.3)
			bm.material = mat
			m.mesh = bm
			m.position.y = 0.003
			n.add_child(m)
		interactables[id] = n
	var van: StaticBody3D = Interactable3D.new()
	root.add_child(van)
	van.setup("van", "van_terminal", Greybox.VAN_TERMINAL[0], Greybox.VAN_TERMINAL[1])
	var crate := Greybox.prop(van, "cardboardBoxClosed", Vector2.ZERO, 0.0, 0.0, Vector3(1.4, 1.6, 1.4), false, "crate")
	crate.position = Vector3.ZERO
	var lap := Greybox.prop(van, "laptop", Vector2.ZERO, 0.0, 180.0, Vector3.ONE, false, "laptop")
	lap.position = Vector3(0, Greybox.VAN_TERMINAL[1].y - 0.02, 0)
	interactables["van_terminal"] = van

func open_terminal(t: Node3D) -> String:
	open_terminal_id = t.terminal_id
	terminal_status = "Locked out." if t.locked(session.run.time) else ""
	session.input.open_overlay("terminal")
	terminal_panel.open(terminal_view(t))
	return "terminal"

func terminal_view(t: Node3D) -> Dictionary:
	var hint := ""
	if career.phone.has("hints") and not t.solved:
		hint = t.puzzle.hint if t.kind == "choice" else "The password was written up in Classroom 104."
	var v := {"label": t.label(), "kind": t.kind, "hint": hint, "status": terminal_status, "solved": t.solved, "locked": t.locked(session.run.time)}
	if t.kind == "choice":
		v.title = t.puzzle.title
		v.lines = t.puzzle.lines
		v.options = t.puzzle.options
	return v

# The panel's answer: the terminal decides; a lockout sounds an alarm.
func on_terminal_submit(answer: String) -> void:
	var t: Node3D = terminals.get(open_terminal_id)
	if t == null: return
	var res: Dictionary = t.submit(answer, session.run.time)
	match res.result:
		"solved":
			award(t)
			terminal_status = "Access granted."
		"wrong": terminal_status = "Access denied. %d attempt(s) left." % res.attempts_left
		"lockout":
			terminal_status = "LOCKED OUT. Alarm triggered."
			noise.emit_noise(t.global_position, Puzzles.ALARM_RADIUS, "alarm", "terminal", session.run.time)
		"locked": terminal_status = "Locked out. Try again later."
	terminal_panel.refresh(terminal_view(t))

func award(t: Node3D) -> void:
	var spec: Dictionary = Puzzles.TERMINALS[t.terminal_id]
	if not spec.research in run_research and not career.research.has(spec.research):
		run_research.append(spec.research)
	if spec.unlock != "": career.phone.unlock(spec.unlock)
	career.phone.add_entry(spec.journal[0], spec.journal[1], spec.journal[2])

func read_note(id: String) -> String:
	var spec: Dictionary = Puzzles.NOTES[id]
	var text := Puzzles.note_text(id, career.seed)
	career.phone.add_entry(id, spec.title, text)
	if spec.unlock != "": career.phone.unlock(spec.unlock)
	show_notice(text.replace("\n", "  "), 4.0)
	return "note"

func phone_snapshot() -> Dictionary:
	var loot: Array = []
	for id in pickups: loot.append(pickups[id].global_position)
	var foes: Array = []
	for id in enemies:
		if enemies[id].state != enemies[id].State.DEAD: foes.append(enemies[id].global_position)
	foes.append(proctor.global_position)
	if tracer.is_down(): foes.append(tracer.global_position)
	if blackout.active(): foes.append(blackout.global_position)
	var hints: Array = []
	if career.phone.has("hints"):
		hints.append("LAB 2 ADMIN: the password was written up in Classroom 104.")
		hints.append("FACULTY PC: " + terminals["terminal_office"].puzzle.hint)
	var tpos: Array = []
	for id in terminals: tpos.append(terminals[id].global_position)
	return {"rooms": Greybox.ROOMS, "bounds": Greybox.BOUNDS, "visited": career.phone.visited, "player": player.global_position,
		"yaw": player.yaw, "terminals": tpos, "van": interactables["van_terminal"].global_position,
		"intel": career.phone.has("intel"), "loot": loot, "enemies": foes, "journal": career.phone.journal,
		"hints_unlocked": career.phone.has("hints"), "hints": hints}

func show_phone() -> void:
	phone_panel.open(phone_snapshot())

func open_van() -> String:
	van_message = ""
	session.input.open_overlay("van")
	van_panel.open(van_view())
	return "van"

func van_view() -> Dictionary:
	var shop: Array = []
	for id in Career.SHOP:
		var spec: Dictionary = Career.SHOP[id]
		shop.append({"id": id, "label": spec.label, "price": spec.price, "owned": career.owned.has(id),
			"affordable": career.banked >= spec.price, "allowed": not spec.has("bag") or spec.bag > career.start_bag})
	return {"night": career.night_in_cycle, "nights_per_cycle": Career.NIGHTS_PER_CYCLE, "cycle": career.cycle,
		"quota": career.quota, "delivered": career.banked_cycle, "banked": career.banked,
		"research": career.research.size(), "research_total": Career.RESEARCH_IDS.size(),
		"carrying_value": session.inventory.loot_value(), "carrying_research": run_research.size(),
		"shop": shop, "message": van_message}

func on_buy(item: String) -> void:
	var r: Dictionary = career.buy(item)
	van_message = "Bought: %s." % Career.SHOP[item].label if r.ok else "Can't buy: %s." % r.reason
	van_panel.refresh(van_view())

# Tab: the inventory screen (the world stays live, as with every overlay).
func show_inventory() -> void:
	inventory_panel.open(inventory_snapshot())

func inventory_snapshot() -> Dictionary:
	var inv: RefCounted = session.inventory
	var out: Array = []
	for e in inv.entries:
		var w: bool = inv.is_weapon(e)
		var d: Resource = Inventory.definition_of(e)
		var row := {"id": e.instance_id, "label": d.label, "quantity": 1 if w else e.quantity, "weapon": w}
		if w and e.uses_ammo():
			row.magazine = e.magazine
			row.magazine_size = e.definition.magazine_size
			row.reserve = inv.count(e.definition.ammo_type)
		out.append(row)
	return {"capacity": inv.capacity, "equipped_id": inv.equipped_id, "entries": out}

# Drop one item by id in front of the player (spawn first, then remove).
func drop_item(id: String) -> bool:
	var ok: bool = session.inventory.drop(id, func(entry: RefCounted) -> bool: return place_pickup(entry, drop_spot()) != null)
	if ok: sfx.play("click", player.global_position)
	return ok

func hide_overlays() -> void:
	open_terminal_id = ""
	for p in [terminal_panel, phone_panel, van_panel, inventory_panel]:
		if p != null: p.close()

# Leave in the van: deliver what you carry, close the night, show the result.
func end_night_in_van() -> Dictionary:
	var delivered := deliver_cargo()
	var first_chapter := career.has_all_research() and not career.chapter_complete
	if first_chapter: career.chapter_complete = true
	var r := career.end_night()
	last_night = r.merged({"delivered_tonight": delivered.amount, "research_tonight": delivered.research, "chapter": first_chapter, "died": false})
	session.input.set_context(session.input.Context.EXTRACTION)
	hide_overlays()
	_show_night_result()
	return last_night

func _show_night_result() -> void:
	var r: Dictionary = last_night
	var head := "NIGHT OVER"
	var body := ""
	after_panel = "restart"
	if r.died:
		head = "YOU DIED"
		body = "Bitten in the dark. The van left without your PHP %d of loot%s, and the company docked PHP %d.\n" % [r.lost_value, " and research" if r.lost_research > 0 else "", r.fine]
	else:
		body = "Delivered tonight: PHP %d%s.\n" % [r.delivered_tonight, ", research: %d file(s)" % r.research_tonight.size() if not r.research_tonight.is_empty() else ""]
	match r.result:
		"next_night": body += "Quota: PHP %d / %d with %d night(s) left." % [career.banked_cycle, career.quota, career.nights_left_in_cycle()]
		"next_cycle": body += "QUOTA MET (PHP %d / %d). The new quota is PHP %d." % [r.delivered, r.quota, career.quota]
		"fired":
			head = "FIRED"
			body += "You delivered PHP %d of a PHP %d quota. The contractor let you go." % [r.delivered, r.quota]
			after_panel = "new_career"
	if r.get("chapter", false):
		head = "CHAPTER 01 COMPLETE"
		body = "Both research files reached the van. Someone has to read them.\n" + body
	death_panel.show_panel(body.replace("\n", "\n"), head, "Start a new career" if after_panel == "new_career" else "Start the next night")

# Footstep noise: walking and sprinting are heard, crouching is silent.
func footsteps(delta: float) -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	footstep_timer -= delta
	if speed < 0.5 or not player.is_on_floor() or player.crouching:
		return
	if footstep_timer <= 0.0:
		noise.emit_noise(player.global_position, SPRINT_NOISE if player.sprinting else WALK_NOISE, "footsteps", "player", session.run.time)
		footstep_timer = STEP_INTERVAL

func level_solids() -> Array:
	var out := static_solids.duplicate()
	for id in doors: out.append(doors[id].panel_aabb())
	return out

# Line of sight for enemies: nothing on the world layer between the points.
func clear_line(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# A hard landing kicks the view down a little (presentation only).
func _landing_kick() -> void:
	var on := player.is_on_floor()
	if not on: fall_speed = maxf(fall_speed, -player.velocity.y)
	elif not was_on_floor and fall_speed > 3.5:
		lofi.add_kick(-clampf((fall_speed - 3.5) * 0.02, 0.01, 0.06), 0.0)
		sfx.play("footstep", player.global_position)
	if on: fall_speed = 0.0
	was_on_floor = on

func muzzle_flash() -> void:
	muzzle_until = session.run.time + 0.06

# Melee/blast targets: living enemies (chest height) and, for hazards, the player.
func combat_targets() -> Array:
	var out: Array = []
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		if not e.health.dead:
			out.append({"id": id, "pos": e.global_position + Vector3(0, 1.0, 0), "radius": e.RADIUS, "health": e.health, "body": e})
	if tracer.is_down() and not tracer.health.dead:
		out.append({"id": "tracer", "pos": tracer.global_position + Vector3(0, 0.6, 0), "radius": tracer.RADIUS, "health": tracer.health, "body": tracer})
	if blackout.active() and not blackout.health.dead:
		out.append({"id": "blackout", "pos": blackout.global_position + Vector3(0, 1.0, 0), "radius": blackout.RADIUS, "health": blackout.health, "body": blackout})
	return out

func hazard_targets() -> Array:
	var out := combat_targets()
	out.append({"id": "player", "pos": player.global_position + Vector3(0, 0.9, 0), "radius": player.RADIUS, "health": player.health})
	return out

# Weapon ray: the first wall or enemy along the line; walls stop the shot.
func weapon_ray(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 0b1001, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return {"target": null, "distance": INF}
	var d: float = from.distance_to(hit.position)
	for id in enemies:
		if hit.collider == enemies[id] and not enemies[id].health.dead:
			return {"target": {"id": id, "pos": hit.position, "radius": 0.0, "health": enemies[id].health}, "distance": d}
	for e in [tracer, blackout]:
		if hit.collider == e and not e.health.dead:
			return {"target": {"id": e.enemy_id, "pos": hit.position, "radius": 0.0, "health": e.health}, "distance": d}
	return {"target": null, "distance": d}

# Session hook: thrown items, fires and blasts after the actors move.
func effects_step(delta: float) -> void:
	hazards.tick(delta, session.run.time, {"targets": hazard_targets(), "los": clear_line, "noise": noise})

func equip_slot(n: int) -> void:
	if not pcombat.equip_slot(n): show_notice("Can't switch weapons now." if pcombat.combat.busy() else "No weapon in slot %d." % n)

func cycle_throwable() -> void:
	pcombat.cycle_throwable()

func weapon_hud() -> String:
	var inv: RefCounted = session.inventory
	var w: RefCounted = inv.equipped_weapon()
	var s := "Unarmed"
	if w != null:
		s = w.item.label
		if w.uses_ammo(): s += "  %d/%d (+%d)" % [w.magazine, w.definition.magazine_size, inv.count(w.definition.ammo_type)]
	var throwables: Array[String] = pcombat.available_throwables()
	if not throwables.is_empty():
		var t: String = pcombat.throw_item if pcombat.throw_item in throwables else throwables[0]
		s += "   |   G: %s x%d" % [ItemDefinition.lookup(t).label, inv.count(t)]
	return s

# Session hook: enemies think and move after the player each tick.
func actors_step(delta: float, now: float) -> void:
	if nav_dirty:
		nav.rebuild(level_solids())
		nav_dirty = false
	var ctx := {"player": player, "player_health": player.health, "noise": noise.events, "nav": nav, "los": clear_line}
	for id in enemies: enemies[id].tick(delta, now, ctx)
	_update_blackout(now)
	tracer.tick(delta, now, {"player": player, "player_health": player.health, "lit": lit_at, "nav": nav, "los": clear_line})
	proctor.tick(delta, now, {"player": player, "carrying": carrying_research(), "doors": doors, "staff_nav": staff_nav,
		"los": clear_line, "lock": lock_door, "unlock": unlock_door, "opened": func(_d) -> void: nav_dirty = true})
	blackout.tick(delta, now, {"player": player, "player_health": player.health, "nav": nav, "los": clear_line, "dark": is_dark, "in_beam": in_beam})

# ---- lights, darkness and the night clock -------------------------------------

func clock_text() -> String:
	var minutes := NIGHT_START_MIN + int(session.run.time / 60.0 * 6.0) # 10 real seconds = 1 night minute
	return "%02d:%02d" % [(minutes / 60) % 24, minutes % 60]

func lamp_powered(l: OmniLight3D) -> bool:
	return not dark_rooms.has(l.get_meta("room", ""))

# A point is lit when a powered lamp in the same room is within reach.
func lit_at(pos: Vector3) -> bool:
	var room := Greybox.room_at(pos)
	for l in lamps:
		if l.get_meta("room", "") != room or not lamp_powered(l): continue
		if Vector2(l.position.x - pos.x, l.position.z - pos.z).length() <= LIT_REACH: return true
	return false

func is_dark(pos: Vector3) -> bool:
	return not lit_at(pos)

# The flashlight "catches" a point inside its cone, in range, with a clear line.
func in_beam(pos: Vector3) -> bool:
	if not player.flashlight.visible: return false
	var eye: Vector3 = player.eye_position()
	var to: Vector3 = pos - eye
	if to.length() > BEAM_RANGE: return false
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to.normalized())) > BEAM_HALF_ANGLE: return false
	return clear_line(eye, pos)

func _update_blackout(now: float) -> void:
	for i in BLACKOUT_ORDER.size():
		var room: String = BLACKOUT_ORDER[i]
		if dark_rooms.has(room) or now + 1e-6 < BLACKOUT_AT + i * BLACKOUT_STEP: continue
		dark_rooms[room] = true
		for l in lamps:
			if l.get_meta("room", "") == room: l.light_energy = 0.0
		if i == 0:
			show_notice("The lights are failing.", 2.5)
			blackout.activate(Vector3(9.5, 0, 1.8))

func carrying_research() -> bool:
	return not run_research.is_empty() or session.inventory.count("research_drive") > 0

# The Proctor's keys: shut and lock (refused if someone stands in the doorway).
func lock_door(door: Node3D) -> bool:
	if door.locked: return false
	if door.is_open:
		if door.occupied(get_world_3d().direct_space_state): return false
		door.set_open(false)
	door.locked = true
	nav_dirty = true
	return true

func unlock_door(door: Node3D) -> void:
	door.locked = false

# Death ends the night too: loot and undelivered research are lost, a fine is
# taken, and the night counts toward the quota cycle.
func show_death_panel() -> void:
	var r := career.end_night()
	last_night = r.merged({"died": true, "fine": last_death.fine, "lost_value": last_death.lost_value, "lost_research": last_death.lost_research})
	_show_night_result()

# End panel button: next night (career kept) or, when fired, a new career.
func on_end_panel_button() -> void:
	if after_panel == "new_career":
		career = Career.new()
		_reseed_terminals()
	session.restart()

func _reseed_terminals() -> void:
	for id in terminals: terminals[id].reset_for_night(career.seed)

# Death: the carried loot is lost with the run, and a fine is taken.
func apply_death_penalty() -> void:
	var lost: int = session.inventory.loot_value()
	var fine := career.fine_for_death()
	last_death = {"fine": fine, "lost_value": lost, "lost_research": run_research.size()}

func show_notice(text: String, seconds := 1.5) -> void:
	notice = text
	notice_time = seconds

# Presentation: flickering fluorescent tubes (not simulation state).
func _process(delta: float) -> void:
	flicker_t += delta
	for i in lamps.size():
		var lamp: OmniLight3D = lamps[i]
		if lamp.get_meta("flicker", false):
			var k := sin(flicker_t * 23.0 + i * 3.1) + sin(flicker_t * 7.3 + i)
			lamp.light_energy = 0.15 if k > 1.6 else 0.7
		if not lamp_powered(lamp): lamp.light_energy = 0.0

func publish(_delta: float) -> void:
	muzzle.visible = session.run.time < muzzle_until
	if lofi: lofi.sync()
	pcombat.publish()
	var inv: RefCounted = session.inventory
	status.text = weapon_hud() + "\n" + clock_text() + "   |   Night %d/%d   |   Quota PHP %d/%d   |   Bank PHP %d   |   Carrying %.1f kg, loot PHP %d, research %d   |   Bag %d/%d" % [career.night_in_cycle, Career.NIGHTS_PER_CYCLE, career.banked_cycle, career.quota, career.banked, inv.carried_weight(), inv.loot_value(), run_research.size(), inv.entries.size(), inv.capacity]
	var show_scan := session.run.time < scan_until
	for id in pickups:
		var tag: Label3D = pickups[id].get_node_or_null("ScanTag")
		var pinged := show_scan and last_scan.any(func(s): return s.pickup_id == id)
		if pinged and tag == null:
			tag = Label3D.new()
			tag.name = "ScanTag"
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.position.y = 0.7
			tag.pixel_size = 0.003
			tag.modulate = Color(0.6, 1.0, 0.7)
			tag.text = "%s\nPHP %d" % [pickups[id].label(), pickups[id].value()]
			pickups[id].add_child(tag)
		elif not pinged and tag != null:
			tag.queue_free()
	if notice_time > 0.0:
		prompt.text = notice
		return
	if extract_progress > 0.0:
		prompt.text = "Loading the van...  %d%%" % int(extract_progress / EXTRACT_HOLD_S * 100.0)
		return
	var t := target_in_view()
	match t.kind:
		"door": prompt.text = "E  %s door" % ("Close" if t.target.is_open else "Open")
		"pickup": prompt.text = "E  Take %s" % t.target.label()
		"terminal": prompt.text = "E  Use %s%s" % [t.target.label(), "  (hacked)" if t.target.solved else ""]
		"note": prompt.text = "E  Read"
		"van": prompt.text = "E  Van terminal: shop, quota, end the night"
		_:
			if in_extraction(player.global_position) and (not inv.loot_entries().is_empty() or not run_research.is_empty()):
				prompt.text = "Hold E  Load PHP %d%s into the van" % [inv.loot_value(), " + research" if not run_research.is_empty() else ""]
			else:
				prompt.text = ""

func seed_pickups() -> void:
	for id in pickups:
		pickups[id].collision_layer = 0
		pickups[id].queue_free()
	pickups.clear()
	for spec in Greybox.LOOT:
		var item_id: String = spec.item
		if Inventory.BAG_TIERS.has(item_id):
			place_pickup(null, spec.at, item_id)
			continue
		var made: Dictionary = WeaponInstance.create(item_id, session.run)
		if not made.ok: made = ItemStack.create(item_id, int(spec.get("quantity", 1)), session.run)
		if not made.ok:
			push_error("pickup %s: %s" % [spec.id, made.error])
			continue
		place_pickup(made.get("weapon", made.get("stack")), spec.at)

func reset_run() -> void:
	player.global_position = spawn.at
	player.velocity = Vector3.ZERO
	player.yaw = deg_to_rad(spawn.yaw)
	player.pitch = 0.0
	player.crouching = false
	player._apply_height(player.STAND_HEIGHT)
	player.apply_look()
	player.health.reset()
	player.endurance.reset()
	player.flashlight.visible = false
	player.carry_factor = 1.0
	for id in doors: doors[id].set_open(false)
	nav.rebuild(level_solids())
	nav_dirty = false
	for spec in Greybox.ENEMIES:
		enemies[spec.id].reset_to(spec.at, spec.yaw, noise.last_id())
	if death_panel: death_panel.hide_panel()
	died_at = -1.0
	footstep_timer = 0.0
	seed_pickups()
	noise.reset()
	interact_was = false
	flashlight_was = false
	scan_was = false
	drop_was = false
	scan_ready_at = 0.0
	scan_until = 0.0
	last_scan = []
	extract_progress = 0.0
	notice_time = 0.0
	complete = false
	run_research.clear()
	pcombat.reset()
	hazards.reset()
	muzzle_until = -1.0 # the run clock restarts at 0: a stale flash time would linger
	if sfx: sfx.played.clear()
	fall_speed = 0.0
	was_on_floor = true
	dark_rooms.clear()
	for l in lamps: l.light_energy = 0.7
	for id in doors: doors[id].locked = false
	tracer.reset()
	proctor.reset()
	blackout.reset()
	career.phone.new_night()
	_reseed_terminals()
	if career.start_bag > session.inventory.capacity: session.inventory.upgrade_bag(career.start_bag)
	open_terminal_id = ""
	terminal_status = ""
	if prompt: prompt.text = ""
