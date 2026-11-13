extends Node3D
# Composition root for the first-person build. Owns the session (tick order),
# the world geometry, the player body, world pickups, the level objectives
# and the minimal HUD. All gameplay state changes happen inside
# simulate(); publish() only updates presentation.

const GameSession = preload("res://scripts/core/game_session.gd")
const Objectives = preload("res://scripts/core/objectives.gd")
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
const Sfx = preload("res://scripts/audio/sfx.gd")
const InventoryPanel = preload("res://scripts/ui/inventory_panel.gd")
const PlayerCombat = preload("res://scripts/combat/player_combat.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const LOFI_SHRINK := 1        # §11 retired the low-res look: full resolution (the view still carries camera kicks)
const ArtDirection = preload("res://scripts/render/art_direction.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")

const STEP_INTERVAL := 0.45   # s between footstep noises while moving
const WALK_NOISE := 6.0       # metres heard while running (crouching makes none)
const SPRINT_NOISE := 10.0     # dashing or sliding

const DROP_DISTANCE := 0.8

var session: GameSession
var objectives := Objectives.new()
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
var drop_was := false
var notice := ""
var notice_time := 0.0
var hud: CanvasLayer
var prompt: Label
var status: Label
var pause_label: Label
var world_items: Node3D
var lofi: CanvasLayer
var art: Node                 # ArtDirection (§11): night grade, practical lights, post layer
var pause_menu: CanvasLayer   # Esc: Resume / Settings / Restart / Quit
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
var interactables := {}        # id -> Interactable3D (notes)
var terminal_panel: CanvasLayer
var open_terminal_id := ""
var terminal_status := ""
var pcombat: Node3D            # PlayerCombat: weapons, reload, dodge, throws
var died_at_run := -1         # run id of the last death (for the panel)
var hazards := Hazards.new()   # throws in flight, frag blasts, molotov fires
var sfx: Node3D                # synthesised sound effects
var inventory_panel: CanvasLayer
var muzzle: OmniLight3D        # muzzle flash (presentation)
var muzzle_until := -1.0
var was_on_floor := true
var fall_speed := 0.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.44, 0.47) # open grey sky over the movement arena
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.56, 0.58)
	e.ambient_light_energy = 0.6
	e.fog_enabled = true # light haze: the far wall (120 m) stays readable
	e.fog_light_color = Color(0.42, 0.44, 0.47)
	e.fog_density = 0.004
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.85
	e.adjustment_contrast = 1.05
	e.adjustment_brightness = 1.0
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
	for l in lamps: l.set_meta("room", Greybox.room_at(l.position))
	pcombat = PlayerCombat.new()
	pcombat.name = "PlayerCombat"
	add_child(pcombat)
	pcombat.setup(self)
	_build_interactables()
	death_panel = DeathPanel.new()
	add_child(death_panel)
	death_panel.next_night_requested.connect(func() -> void: session.restart())
	terminal_panel = TerminalPanel.new()
	add_child(terminal_panel)
	terminal_panel.submitted.connect(on_terminal_submit)
	terminal_panel.close_requested.connect(func() -> void: session.handle_action("pause"))
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
	lofi.grain.visible = false # the art-direction post layer owns grain now
	get_viewport().disable_3d = true # the view's SubViewport draws the world
	art = ArtDirection.new()
	art.apply(self)
	player.settings = session.settings
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.setup(session.settings)
	pause_menu.resume_requested.connect(func() -> void:
		if session.paused(): session.handle_action("pause"))
	pause_menu.restart_requested.connect(func() -> void:
		if session.paused(): session.handle_action("pause")
		session.restart())
	pause_menu.quit_requested.connect(func() -> void: get_tree().quit())
	_load_user_settings.call_deferred()
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

# The real game only: a test runner never has main as its current scene, so a
# player's saved bindings cannot change what the suites press.
func _load_user_settings() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		session.settings.path = session.Settings.PATH
		session.settings.load_from()

# Settings that are not bindings (the router refreshes itself).
func apply_settings() -> void:
	player.tuning.sprint_toggle = session.settings.sprint_toggle

func _unhandled_key_input(event: InputEvent) -> void:
	if pause_menu != null and pause_menu.visible:
		if pause_menu.is_capturing(): return # the settings panel is reading a key
		if session.input.action_for_event(event) == "pause":
			pause_menu.back() # leave settings first, then resume
			get_viewport().set_input_as_handled()
			return
	session.handle_event(event)

# Discrete actions rebound to mouse buttons (a wheel or side button).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (pause_menu == null or not pause_menu.visible):
		session.input.note_event(event) # wheel notches: one-tick presses of held actions (jump, forward...)
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
	pause_label.visible = false # the pause menu replaces the old label
	if pause_menu != null:
		if is_paused: pause_menu.open()
		else: pause_menu.close()
	if not external_driver:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_paused else Input.MOUSE_MODE_CAPTURED

# One unpaused tick of world rules.
func simulate(intent: Dictionary, delta: float) -> void:
	if player.health.dead: return
	player.carry_factor = pcombat.combat.movement_factor() # no weight penalty (rehaul)
	var held: Resource = pcombat.weapon() if pcombat != null else null
	player.ads_time = held.ads_s if held != null and held.is_ranged() else player.tuning.ads_s
	player.ads_move = held.ads_move_scale if held != null else player.tuning.ads_speed_factor
	player.holstered = held == null or not held.is_ranged() # no gun in hand: Apex holster speed
	player.simulate(intent, delta, session.run.time)
	_landing_kick()
	pcombat.simulate(intent, delta, session.run.time)
	footsteps(delta)
	try_flashlight(intent.get("flashlight", false))
	try_interact(intent.get("interact", false))
	check_exit()
	try_drop(intent.get("drop", false))
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

func in_extraction(point: Vector3) -> bool:
	return extraction.grow(0.001).has_point(point + Vector3(0, 0.5, 0))

# Walking into the exit with every research file completes the level (the
# session then shows the complete panel).
func check_exit() -> void:
	if complete or not in_extraction(player.global_position): return
	if objectives.has_all():
		objectives.level_complete = true
		complete = true
		sfx.play("van", player.global_position)

func show_complete_panel() -> void:
	hide_overlays()
	death_panel.show_panel("All %d research files recovered in %.0f s." % [objectives.total(), session.run.time], "LEVEL COMPLETE", "Restart level")

func show_death_panel() -> void:
	death_panel.show_panel("Research recovered: %d/%d." % [objectives.count(), objectives.total()], "YOU DIED", "Restart level")

# ---- terminals and notes -----------------------------------------------------

func _build_interactables() -> void:
	var root := Node3D.new()
	root.name = "Interactables"
	add_child(root)
	for id in Greybox.TERMINAL_SPOTS:
		var t: StaticBody3D = Terminal3D.new()
		root.add_child(t)
		t.setup(id, Greybox.TERMINAL_SPOTS[id], objectives.seed)
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

func open_terminal(t: Node3D) -> String:
	open_terminal_id = t.terminal_id
	terminal_status = "Locked out." if t.locked(session.run.time) else ""
	session.input.open_overlay("terminal")
	terminal_panel.open(terminal_view(t))
	return "terminal"

func terminal_view(t: Node3D) -> Dictionary:
	var hint := ""
	if objectives.hints and not t.solved:
		hint = t.puzzle.hint if t.kind == "choice" else "The password is on the lab whiteboard."
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

# Hacking retrieves the file at once (+1 objective).
func award(t: Node3D) -> void:
	var spec: Dictionary = Puzzles.TERMINALS[t.terminal_id]
	if objectives.retrieve(spec.research):
		show_notice("FILE RECOVERED  (%d/%d)" % [objectives.count(), objectives.total()], 2.5)

func read_note(id: String) -> String:
	var spec: Dictionary = Puzzles.NOTES[id]
	var text := Puzzles.note_text(id, objectives.seed)
	if spec.unlock == "hints": objectives.hints = true
	show_notice(text.replace("\n", "  "), 4.0)
	return "note"

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
	for p in [terminal_panel, inventory_panel]:
		if p != null: p.close()

# Footstep noise: running and dashing/sliding are heard, crouching is silent.
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
			var head: bool = hit.position.y - enemies[id].global_position.y >= enemies[id].HEIGHT - enemies[id].HEAD_ZONE
			return {"target": {"id": id, "pos": hit.position, "radius": 0.0, "health": enemies[id].health}, "distance": d, "head": head}
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


func _reseed_terminals() -> void:
	for id in terminals: terminals[id].reset_for_night(objectives.seed)

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
			var base: float = lamp.get_meta("base_energy", 0.7)
			lamp.light_energy = base * 0.2 if k > 1.6 else base

func publish(_delta: float) -> void:
	muzzle.visible = session.run.time < muzzle_until
	if muzzle.visible:
		var at = pcombat.view.muzzle_global() # the gun model's Muzzle marker, when it has one
		if at != null: muzzle.global_position = at
	if lofi: lofi.sync()
	pcombat.publish()
	var inv: RefCounted = session.inventory
	status.text = weapon_hud() + "\n" + objectives.current_text() + "   |   Bag %d/%d" % [inv.entries.size(), inv.capacity]
	if notice_time > 0.0:
		prompt.text = notice
		return
	var t := target_in_view()
	match t.kind:
		"door": prompt.text = "E  %s door" % ("Close" if t.target.is_open else "Open")
		"pickup": prompt.text = "E  Take %s" % t.target.label()
		"terminal": prompt.text = "E  Use %s%s" % [t.target.label(), "  (hacked)" if t.target.solved else ""]
		"note": prompt.text = "E  Read"
		_:
			if in_extraction(player.global_position) and not objectives.has_all():
				prompt.text = "EXIT - recover every research file first (%d/%d)" % [objectives.count(), objectives.total()]
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
	player.reset_movement()
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
	drop_was = false
	notice_time = 0.0
	complete = false
	pcombat.reset()
	hazards.reset()
	muzzle_until = -1.0 # the run clock restarts at 0: a stale flash time would linger
	if sfx: sfx.played.clear()
	fall_speed = 0.0
	was_on_floor = true
	for l in lamps: l.light_energy = l.get_meta("base_energy", 0.7)
	objectives.reset()
	for id in doors: doors[id].locked = false
	_reseed_terminals()
	open_terminal_id = ""
	terminal_status = ""
	if prompt: prompt.text = ""
