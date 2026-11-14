extends Node3D
# Composition root for the first-person build. Owns the session (tick order),
# the world geometry (the Dark Forest, or the movement arena for the rule
# tests), the player body, the enemies, the spells and the HUD. All gameplay state changes happen inside
# simulate(); publish() only updates presentation.

const GameSession = preload("res://scripts/core/game_session.gd")
const Greybox = preload("res://scripts/world/greybox.gd")       # the movement arena (tests)
const DarkForest = preload("res://scripts/world/dark_forest.gd") # the game world [P7]
const GrassFieldScript = preload("res://scripts/world/grass_field.gd")
const SpellService = preload("res://scripts/combat/spell_service.gd")
const TrainingField = preload("res://scripts/world/training_field.gd")
const NoiseService = preload("res://scripts/world/noise_service.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const NavigationGrid = preload("res://scripts/world/navigation_grid.gd")
const BlightedSprite = preload("res://scripts/actors/blighted_sprite.gd")
const CombatDirector = preload("res://scripts/core/combat_director.gd")
const DeathPanel = preload("res://scripts/ui/death_panel.gd")
const LoFiView = preload("res://scripts/render/lofi_view.gd")
const Interactable3D = preload("res://scripts/world/interactable3d.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const EffectsPanel = preload("res://scripts/ui/effects_panel.gd")
const DamageNumbers = preload("res://scripts/ui/damage_numbers.gd")
const Banner = preload("res://scripts/ui/banner.gd")
const Vfx = preload("res://scripts/render/vfx.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")
const Sfx = preload("res://scripts/audio/sfx.gd")
const PlayerCombat = preload("res://scripts/combat/player_combat.gd")
const Hazards = preload("res://scripts/combat/hazards.gd")
const ProjectileService = preload("res://scripts/combat/projectile_service.gd")
const EffectSystem = preload("res://scripts/core/effect_system.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const CombatController = preload("res://scripts/combat/combat_controller.gd")
const GROUND_MAT := "res://assets/BinbunGrass/src/materials/grass_01/grass_ground_01.tres"
const GROUND_SHADER := "res://assets/BinbunGrass/src/shader/ground_lit.gdshader"
const LOFI_SHRINK := 3        # pixel look [Sir, 2026-11-13]: the world at 1/3 size (640 x 360 of 1080p), nearest-neighbour up; the HUD stays sharp
const ArtDirection = preload("res://scripts/render/art_direction.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const GrimoirePanel = preload("res://scripts/ui/grimoire_panel.gd")
const AudioMix = preload("res://scripts/audio/audio_mix.gd")

const STEP_INTERVAL := 0.45   # s between footstep noises while moving
const WALK_NOISE := 6.0       # metres heard while running (crouching makes none)
const DASH_NOISE := 10.0      # dashing or sliding

var session: GameSession
var noise := NoiseService.new()
var player: CharacterBody3D
# Which world to build, set before entering the tree: "forest" (the game) or
# "arena" (the movement sandbox the rule tests run in).
var world_kind := "forest"
var level: Script            # DarkForest or Greybox
var spawn := {}
# The map [Sir R11]: in the forest every run draws a new seed (trees, rocks,
# ledges, page spots, spawn zones); the arena's are fixed. `fixed_map_seed`
# >= 0 pins the seed (tests, the perf suite); -1 draws a new one each run.
var fixed_map_seed := -1
var map := {}                # DarkForest.generate() output (forest only)
var map_seed := -1
var spawn_rng := RandomNumberGenerator.new() # spawn jitter and zone picks: seeded by the map, so a fixed seed replays
var fx_rng := RandomNumberGenerator.new()    # presentation only (camera kick); never touches gameplay draws
var map_ms := 0.0            # last generate + build time (budget 200 ms [R11])
var zones: Array = []        # Sprite spawn zones [{id, at, yaw}]
var page_spots := {}         # page id -> Vector3
var _fixed_solids: Array = []
var _forest_node: Node3D
var _map_fresh := false      # the map built in _ready serves the first run
var complete := false        # the session's level-complete hook (the MVP has no exit)
# Set by test runners before entering the tree; they then call game_step().
var external_driver := false
var interact_was := false
var notice := ""             # the newest notification
var notice_time := 0.0
var notices: Array = []      # [[text, seconds left]] shown stacked (newest last)
const MAX_NOTICES := 4
var hud: CanvasLayer         # Hud (P7)
var prompt: Label
var status: Label
var pause_label: Label
var lofi: CanvasLayer
var art: Node                 # ArtDirection (§11): night grade, practical lights, post layer
var pause_menu: CanvasLayer   # Esc: Resume / Settings / Restart / Quit
var lamps: Array = []
var flicker_t := 0.0
var nav := NavigationGrid.new()
var nav_climb := NavigationGrid.new() # the Sprites' grid: ledges they can climb are passable [R12]
var static_solids: Array = []  # level solids (navigation)
var nav_dirty := false
var enemies := {}              # id -> BlightedSprite
var director := CombatDirector.new() # in/out of combat (AggroTracker)
var dead_at := {}              # enemy id -> sim time it died (respawn clock)
const RESPAWN_S := 12.0        # [design] a dead Sprite returns to the pool after this
# Enemy pool [Sir R6]: never more than 20 alive at once. The six spawn zones
# (`zones`) start occupied; the spawner keeps TARGET_ALIVE in play from
# the pool, one every SPAWN_EVERY_S, always outside the player's aggro range,
# so the 20-kill mission stays reachable.
const MAX_ALIVE := 20          # [Sir R6]
const TARGET_ALIVE := 8        # [design] how many the spawner keeps in play
const SPAWN_EVERY_S := 4.0     # [design]
var next_spawn := 0.0
var spawning := true           # off while tests park the enemies
var mission_hud: Label         # top-right mission tracker
var footstep_timer := 0.0
var death_panel: CanvasLayer
var died_at := -1.0
var page_pickups := {}         # page id -> Interactable3D (a page lying in the world)
var grimoire_panel: CanvasLayer # Tab: Grimoire + Player ID (P5)
var effects_panel: CanvasLayer  # T: the player's effects [R14]
var damage_numbers: Node3D      # floating numbers on enemy hits [R14]
var banner: CanvasLayer         # level / rank-up announcements [R15]
var vfx: Node3D                 # pooled spell effects (trails, bursts, scorches, flashes)
var _burn_ticking := false      # set while effect ticks land (their numbers are orange)
var _grim_fx_t := 0.0
var audio: Node                # music in combat, forest ambience [Sir R7]
var pcombat: Node3D            # PlayerCombat: the casting layer (action clock, arms)
var died_at_run := -1         # run id of the last death (for the panel)
var hazards := Hazards.new()   # blasts and fire zones (the base for fireball AOE and Burn)
var projectiles := ProjectileService.new() # fireballs in flight and their detonations (P2)
var spells := SpellService.new() # Dragon's Breath, Firefly, Explosion [2026-11-14]
var training: Node3D # the Training Field, through the portal beside the camp [2026-11-14]
var effects := EffectSystem.new() # timed effects on actors (Burn)
var effect_packets := {}       # effect tick action string -> DamagePacket id (each tick lands once)
var sfx: Node3D                # synthesised sound effects
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
	level = DarkForest if world_kind == "forest" else Greybox
	var built: Dictionary = level.build(self)
	lamps = built.lamps
	spawn = built.spawn
	nav.setup(built.bounds[0], built.bounds[1])
	nav_climb.setup(built.bounds[0], built.bounds[1])
	if world_kind == "forest":
		_forest_node = built.node
		_fixed_solids = built.solids
		training = TrainingField.new()
		add_child(training)
		training.build(self)
		_fixed_solids = _fixed_solids + training.forest_solids() # its portal frame: enemies path round it
		if not new_map():
			get_tree().quit(1)
			return
		_map_fresh = true
	else:
		static_solids = built.solids
		zones = Greybox.ENEMIES
		page_spots = Greybox.PAGE_SPOTS
	session = GameSession.new(self)
	session.meta.save_failed.connect(func(_error: int): show_notice("Progress could not be saved. Check disk space and permissions.", 8.0))
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
	for i in MAX_ALIVE:
		var spec: Dictionary = zones[i % zones.size()]
		var id := "sprite_%d" % (i + 1)
		var foe: CharacterBody3D = BlightedSprite.new()
		enemy_root.add_child(foe)
		foe.setup(id, spec.at, spec.yaw)
		enemies[id] = foe
		foe.health.damaged.connect(func(_pk, applied: float) -> void:
			if applied > 0.0: foe.alert_to(player.global_position))
		foe.health.damaged.connect(func(_pk, applied: float) -> void: _number_for(foe, applied))
		foe.health.damaged.connect(func(pk, applied: float) -> void:
			if applied > 0.0 and pk.source_faction == "player": session.meta.note_hit(applied))
		foe.health.died.connect(func(_pk) -> void: on_enemy_died(id))
	audio = AudioMix.new()
	audio.name = "AudioMix"
	add_child(audio)
	AudioMix.apply_volumes(session.settings.volumes)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	noise.noise_emitted.connect(sfx.on_noise)
	player.health.damaged.connect(func(pk, applied: float) -> void:
		if applied <= 0.0: return
		sfx.play("bite" if pk.kind in ["bite", "melee"] else "hit", player.eye_position())
		if lofi: lofi.add_kick(clampf(applied * 0.004, 0.02, 0.1), fx_rng.randf_range(-0.03, 0.03)))
	var hazard_root := Node3D.new()
	hazard_root.name = "Hazards"
	add_child(hazard_root)
	hazards.root = hazard_root
	var spell_root := Node3D.new()
	spell_root.name = "Spells"
	add_child(spell_root)
	projectiles.root = spell_root
	vfx = Vfx.new()
	add_child(vfx)
	projectiles.vfx = vfx
	projectiles.effects = effects
	pcombat = PlayerCombat.new()
	pcombat.name = "PlayerCombat"
	add_child(pcombat)
	pcombat.setup(self)
	spells.root = spell_root
	spells.setup(self)
	player.health.damaged.connect(func(_pk, applied: float) -> void: spells.on_player_hurt(applied, session.run.time)) # a hit breaks Explosion's charge
	_build_interactables()
	death_panel = DeathPanel.new()
	add_child(death_panel)
	death_panel.next_night_requested.connect(func() -> void: session.restart())
	grimoire_panel = GrimoirePanel.new()
	add_child(grimoire_panel)
	grimoire_panel.setup(self)
	grimoire_panel.close_requested.connect(func() -> void: session.handle_action("grimoire"))
	banner = Banner.new()
	banner.name = "Banner"
	add_child(banner)
	banner.shown.connect(func(_it) -> void: if sfx: sfx.play("chime", player.global_position))
	damage_numbers = DamageNumbers.new()
	damage_numbers.name = "DamageNumbers"
	add_child(damage_numbers)
	effects_panel = EffectsPanel.new()
	effects_panel.name = "EffectsPanel"
	add_child(effects_panel)
	effects_panel.close_requested.connect(func() -> void: session.handle_action("effects_tab"))
	_make_hud()
	lofi = LoFiView.new()
	add_child(lofi)
	lofi.setup(player.camera, get_viewport().world_3d, LOFI_SHRINK)
	lofi.grain.visible = false # the art-direction post layer owns grain now
	get_viewport().disable_3d = true # the view's SubViewport draws the world
	art = ArtDirection.new()
	art.apply(self)
	art.set_colour16(true)
	_sync_pixel_grid()
	get_viewport().size_changed.connect(_sync_pixel_grid)
	if world_kind == "forest": # thicker night fog between the trees [handoff §7]
		e.fog_density = 0.022
		e.fog_light_color = Color(0.06, 0.08, 0.11)
		art.apply_night_sky(e) # Binbun night sky [Phase 3]
		var floor_mesh: MeshInstance3D = find_child("floor", true, false).find_children("*", "MeshInstance3D", true, false)[0] if find_child("floor", true, false) else null
		if floor_mesh and ResourceLoader.exists(GROUND_MAT) and ResourceLoader.exists(GROUND_SHADER):
			var gm: ShaderMaterial = (load(GROUND_MAT) as ShaderMaterial).duplicate() # the grass's ground colour
			gm.shader = load(GROUND_SHADER)
			gm.set_shader_parameter("color_gradient", load("res://scripts/world/grass_field.gd").night_palette())
			floor_mesh.material_override = gm
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
	pause_menu.new_game_requested.connect(new_game)
	_load_user_settings.call_deferred()
	reset_run()
	if not external_driver:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _make_hud() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	prompt = hud.prompt
	status = hud.status
	mission_hud = hud.mission
	pause_label = hud.pause_label

# The real game only: a test runner never has main as its current scene, so a
# player's saved bindings cannot change what the suites press.
func _load_user_settings() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		session.settings.path = session.Settings.PATH
		session.settings.load_from()
		session.meta.path = session.MetaProfile.PATH # the kept profile (pages, rank, chant tiers)
		session.meta.load_from()
		session.restart() # rebuild the run on the loaded profile

# "New game (wipe progress)" [Sir R12]: the meta profile back to nothing
# (pages, rank, chant tiers; saved so in the real game), then a fresh run with
# only the start pages. Settings are untouched.
func new_game() -> void:
	if session.paused(): session.handle_action("pause")
	session.meta.reset()
	session.meta.save() # path "" under tests: nothing written
	session.restart()
	show_notice("New game: progress wiped", 2.5)

# A damage number for an applied hit on an enemy [R14]: orange for Burn ticks
# (merged per enemy), larger for the special's blast, white otherwise.
func _number_for(foe: CharacterBody3D, applied: float) -> void:
	if applied <= 0.0 or damage_numbers == null: return
	var kind := "burn" if _burn_ticking else ("special" if projectiles.detonating == "special" else "direct")
	damage_numbers.spawn(foe.global_position + Vector3(0, foe.HEIGHT + 0.15, 0), applied, kind, foe.enemy_id)

# Settings that are not bindings (the router refreshes itself).
func apply_settings() -> void:
	AudioMix.apply_volumes(session.settings.volumes)
	if damage_numbers != null: damage_numbers.enabled = session.settings.damage_numbers
	GrassFieldScript.view_distance = session.settings.grass_distance
	var gf: Node = find_child("GrassField", true, false)
	if gf: gf.set_distance(session.settings.grass_distance)
	apply_graphics()

# Settings > Graphics [Sir, 2026-11-14], applied live. Window, VSync and the frame
# cap are left alone when a test or benchmark drives the world (external_driver).
func apply_graphics() -> void:
	var g: Dictionary = session.settings.gfx
	if lofi and lofi.container and lofi.container.stretch_shrink != int(g.pixel_scale):
		lofi.container.stretch_shrink = int(g.pixel_scale)
		lofi.shrink = int(g.pixel_scale)
		_sync_pixel_grid.call_deferred()
	if player and player.get("tuning") != null: player.tuning.fov = float(g.fov)
	if art:
		art.set_colour16(bool(g.colour16))
		art.set_grain([0.0, 0.025, 0.05][int(g.film_grain)])
	if lofi: lofi.kicks_enabled = bool(g.camera_shake)
	var we: Array = find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty() and RenderingServer.get_current_rendering_method() == "forward_plus":
		(we[0] as WorldEnvironment).environment.volumetric_fog_enabled = bool(g.volumetric_fog)
	var sh := int(g.shadows)
	for l in find_children("*", "DirectionalLight3D", true, false):
		var dl := l as DirectionalLight3D
		dl.shadow_enabled = sh > 0
		dl.directional_shadow_max_distance = 25.0 if sh == 1 else (70.0 if dl.name == "Sun" else 50.0)
	RenderingServer.directional_shadow_atlas_set_size(2048 if sh <= 1 else 4096, true)
	if world_kind == "forest": DarkForest.set_tree_distance(_forest_node, float(g.tree_distance))
	if vfx: vfx.set_quality(int(g.effects), self)
	if external_driver or DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(g.vsync) else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(g.fps_cap)
	var want_mode: int = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][int(g.window_mode)]
	if DisplayServer.window_get_mode() != want_mode: DisplayServer.window_set_mode(want_mode)
	if want_mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var sz: Vector2i = session.settings.WINDOW_SIZES[int(g.window_size)]
		if DisplayServer.window_get_size() != sz:
			DisplayServer.window_set_size(sz)
			var scr := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(scr.position + (scr.size - sz) / 2)

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
	if what == NOTIFICATION_WM_CLOSE_REQUEST and session != null:
		session.meta.save() # the records (best hit, kills...) since the last save

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
	player.carry_factor = pcombat.combat.movement_factor()
	player.stats = session.stats # Mov Spd drives the run speed
	intent = frozen_intent(intent)
	player.simulate(intent, delta, session.run.time)
	hold_for_charge()
	if training: training.check_portals(session.run.time)
	_landing_kick()
	pcombat.simulate(intent, delta, session.run.time)
	footsteps(delta)
	try_interact(intent.get("interact", false))
	noise.prune(session.run.time)
	if notice_time > 0.0: notice_time -= delta
	for n in notices: n[1] -= delta
	notices = notices.filter(func(n): return n[1] > 0.0)

# Explosion's charge: no movement, look or action, held where it began (in the air too).
func frozen_intent(intent: Dictionary) -> Dictionary:
	if not spells.frozen(): return intent
	player._look_queue = Vector2.ZERO
	return {"move": Vector2.ZERO}

func hold_for_charge() -> void:
	if not spells.frozen(): return
	player.global_position = spells.hold_position()
	player.velocity = Vector3.ZERO

# What the crosshair is on: {kind: "page"|"", target}.
func target_in_view() -> Dictionary:
	var hit: Dictionary = player.look_target()
	if hit.is_empty(): return {"kind": "", "target": null}
	var col: Object = hit.collider
	if col != null and col.has_meta("interact"):
		var it: Node3D = col.get_meta("interact")
		return {"kind": it.kind, "target": it}
	return {"kind": "", "target": null}

# Rising edge of F (interact) acts on what the crosshair is on (one press, one action).
# Returns what happened ("" = nothing under the crosshair).
func try_interact(down: bool) -> String:
	var pressed := down and not interact_was
	interact_was = down
	if not pressed: return ""
	var t := target_in_view()
	if t.kind == "page": return pick_up_page(t.target.target_id)
	return ""

# A page in the world: found (listed, locked) until its Code Assembly is solved.
func pick_up_page(id: String) -> String:
	if not session.grimoire.find(id): return ""
	_sync_page_pickups()
	show_notice("New page: %s  -  open the Grimoire (Tab) to unlock" % session.grimoire.page(id).title, 4.0)
	sfx.play("pickup", player.global_position)
	return "page"

# A pickup shows only while its page is not yet found this run (unlocked pages are known for good).
func _sync_page_pickups() -> void:
	for id in page_pickups:
		var on: bool = not session.grimoire.is_found(id)
		page_pickups[id].visible = on
		for ch in page_pickups[id].get_children():
			if ch is CollisionShape3D: ch.disabled = not on

# Death [Sir R5]: the run is lost, what was learned is kept.
func show_death_panel() -> void:
	var pr: RefCounted = session.progression
	death_panel.show_panel("Fell at level %d with %d kills.\nLost: level, EXP, stats, chant gains, loadout and mission kills.\nKept: unlocked pages, rank %s and every stat's chant tier." % [pr.level, pr.kills, pr.rank], "YOU DIED", "Return to camp")

# ---- pages in the world -----------------------------------------------------

func _build_interactables() -> void:
	var root := Node3D.new()
	root.name = "Interactables"
	add_child(root)
	for id in page_spots:
		var pg: StaticBody3D = Interactable3D.new()
		root.add_child(pg)
		pg.setup("page", id, page_spots[id] + Vector3(0, 0.6, 0), Vector3(0.6, 0.6, 0.6))
		if DarkForest.prop_available("Scroll_1"): # Phase 4: a lost page is a scroll
			var scroll: Node3D = DarkForest.prop("Scroll_1", 0.5)
			scroll.name = "Scroll"
			scroll.position.y = 0.15
			scroll.rotation_degrees = Vector3(0, 25, -20)
			pg.add_child(scroll)
		var leaf := MeshInstance3D.new()
		leaf.visible = not DarkForest.prop_available("Scroll_1")
		var lm := BoxMesh.new()
		lm.size = Vector3(0.32, 0.42, 0.02)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(1.0, 0.86, 0.45)
		lmat.emission_enabled = true
		lmat.emission = Color(1.0, 0.75, 0.3)
		lmat.emission_energy_multiplier = 2.0
		lm.material = lmat
		leaf.mesh = lm
		leaf.name = "Leaf"
		leaf.position.y = 0.3
		leaf.rotation_degrees = Vector3(-15, 25, 0)
		pg.add_child(leaf)
		var glow := OmniLight3D.new()
		glow.light_color = Color(1.0, 0.8, 0.4)
		glow.light_energy = 1.5
		glow.omni_range = 3.0
		glow.position.y = 0.3
		pg.add_child(glow)
		page_pickups[id] = pg
func hide_overlays() -> void:
	if grimoire_panel != null: grimoire_panel.close()
	if effects_panel != null: effects_panel.close()
	if not external_driver and not session.paused(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Tab (the router opened the "grimoire" overlay): the world keeps running [Sir].
func show_grimoire() -> void:
	grimoire_panel.open("grimoire")
	if not external_driver: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# Where the player is, for the Player ID card: the clearing's name in the forest.
const CLEARING_NAMES := ["Camp Ember", "The Crossing", "West Hollow", "East Hollow", "The Stones", "North-west Glade", "North-east Glade"]
func location_name() -> String:
	if world_kind != "forest": return "Training Arena"
	var i: int = DarkForest.clearing_at(player.global_position)
	return "Dark Forest, " + (CLEARING_NAMES[i] if i >= 0 and i < CLEARING_NAMES.size() else "deep in the trees")

# The MVP has one region at world level 1 (later regions raise it).
func world_level() -> int:
	return 1

# T (the router opened the "effects" overlay) [R14]: the world keeps running.
func show_effects() -> void:
	effects_panel.open()
	effects_panel.refresh(effect_rows(session.run.time))
	if not external_driver: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

static func _num(x: float) -> String:
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x

# The Effects tab's rows [R14]: each status on the player with its plain-words
# description (live numbers), buff or debuff, and the time left.
func effect_rows(now: float) -> Array:
	var out := []
	for st in player_statuses(now):
		var id: String = st.id
		var vals := {}
		var until_text := ""
		match id:
			"Cultivate":
				vals = {"pow": _num((pcombat.CULTIVATE.magic_pow[0] - 1.0) * 100.0), "mastery": _num(pcombat.CULTIVATE.spell_mastery[1] * 100.0), "atk": _num((pcombat.CULTIVATE.atk_spd[0] - 1.0) * 100.0)}
			"Concuss":
				vals = {"pct": _num((1.0 - BlightedSprite.CONCUSS_MULT) * 100.0)}
			"Sage Arts":
				vals = {"hp": _num(pcombat.SAGE_HP * 100.0), "mp": _num(pcombat.SAGE_MP * 100.0)}
				until_text = "while out of combat"
			"Burn":
				var e: Dictionary = effects.active.get("player", {}).get("Burn", {})
				vals = {"dps": _num(float(e.get("pow", 100.0)) * float(EffectSystem.DEFS.Burn.dps_pct))}
			"Scorched Slow":
				vals = {"slow": _num((1.0 - projectiles.SCORCHED_SLOW.mult) * 100.0)}
		out.append({"id": id, "name": EffectSystem.display_name(id), "kind": EffectSystem.kind_of(id), "text": EffectSystem.describe(id, vals), "s": st.s, "until_text": until_text})
	return out

# Session hook: a hit while an overlay is open [Sir R1]. True = handled here
# (a page unlock restarts with a fresh question and stays open).
func overlay_hit() -> bool:
	return grimoire_panel != null and grimoire_panel.on_hit()

# Footstep noise: running and dashing/sliding are heard, crouching is silent.
func footsteps(delta: float) -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	footstep_timer -= delta
	if speed < 0.5 or not player.is_on_floor() or player.crouching:
		return
	if footstep_timer <= 0.0:
		noise.emit_noise(player.global_position, DASH_NOISE if player.sprinting else WALK_NOISE, "footsteps", "player", session.run.time)
		footstep_timer = STEP_INTERVAL

func level_solids() -> Array:
	return static_solids.duplicate()

# Walkers' grid (every solid) and the Sprites' climb grid: a solid whose top a
# Sprite can climb to (<= CLIMB_MAX) is passable there [R12].
func _rebuild_navs() -> void:
	var all := level_solids()
	nav.rebuild(all)
	nav_climb.rebuild(all.filter(func(b: AABB) -> bool: return b.end.y > BlightedSprite.CLIMB_MAX + 0.01))

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

# Blast targets: living enemies (chest height) and, for hazards, the player.
func combat_targets() -> Array:
	var out: Array = []
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		if not e.health.dead and e.visible:
			out.append({"id": id, "pos": e.global_position + Vector3(0, 1.0, 0), "radius": e.RADIUS, "health": e.health, "body": e,
				"a": e.global_position + Vector3(0, e.RADIUS, 0), "b": e.global_position + Vector3(0, e.HEIGHT - e.RADIUS, 0)}) # a-b: the capsule axis
	if training: out.append_array(training.targets()) # dummies and boards, while the player is in the field
	return out

func hazard_targets() -> Array:
	var out := combat_targets()
	var ax: Array = BlightedSprite.capsule_axis(player) # the controller's capsule as it is now (crouch and slide too) [R12]
	out.append({"id": "player", "pos": (ax[0] + ax[1]) * 0.5, "radius": player.RADIUS, "health": player.health, "a": ax[0], "b": ax[1]})
	return out

# Session hook: fires and blasts after the actors move.
func effects_step(delta: float) -> void:
	hazards.tick(delta, session.run.time, {"targets": hazard_targets(), "los": clear_line, "noise": noise})
	projectiles.tick(delta, session.run.time, {"targets": combat_targets(), "ray": world_ray, "los": clear_line, "noise": noise})
	spells.tick(delta, session.run.time)
	if training: training.tick(delta, session.run.time)
	vfx.tick(session.run.time)
	_effect_ticks(session.run.time)

# Effect damage (Burn) becomes DamagePackets: one packet id per tick, so a
# tick lands once however often it is offered.
func _effect_ticks(now: float) -> void:
	for ev in effects.tick(now):
		var h: Node = enemies[ev.target].health if enemies.has(ev.target) else (player.health if ev.target == "player" else (training.health_of(String(ev.target)) if training else null))
		if h == null or h.dead: continue
		if not effect_packets.has(ev.action_id): effect_packets[ev.action_id] = CombatController.next_id()
		_burn_ticking = true
		h.apply(DamagePacket.new(effect_packets[ev.action_id], String(ev.source), "player", ev.amount, "fire"), now)
		_burn_ticking = false
	if effect_packets.size() > 512: effect_packets.clear() # ids only matter within a tick's offer

# The first world surface between two points (layer 1: the level): {position, normal} or {}.
func world_ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_world_3d().direct_space_state.intersect_ray(q)

# Session hook: enemies think and move after the player each tick.
func actors_step(delta: float, now: float) -> void:
	if nav_dirty:
		_rebuild_navs()
		nav_dirty = false
	var ctx := {"player": player, "player_health": player.health, "noise": noise.events, "nav": nav_climb, "los": clear_line, "concuss": concuss, "ray": world_ray}
	var any_aggro := false
	for id in enemies:
		enemies[id].speed_mult = projectiles.SCORCHED_SLOW.mult if effects.has(id, projectiles.SCORCHED_SLOW.id, now) else 1.0
		enemies[id].tick(delta, now, ctx)
		if enemies[id].aggroed: any_aggro = true
	_respawn(now)
	director.update(now, any_aggro)

# Concuss [Sir R8]: Mov Spd and Atk Spd x0.2 until `until`; re-applying refreshes (same id).
func concuss(until: float, mult: float) -> void:
	for stat in ["mov_spd", "atk_spd"]: session.stats.add_modifier("concuss", stat, mult, 0.0, until)
	show_notice("CONCUSSED", 1.0)

# A kill: EXP and the kill count go straight to Progression [Sir: no orbs]; the
# Sprite's effects end; its respawn clock starts.
func on_enemy_died(id: String) -> void:
	effects.clear_target(id)
	dead_at[id] = session.run.time
	session.progression.on_kill()
	session.meta.note_kill(session.progression.kills)

# The spawner: a dead Sprite goes back to the pool after RESPAWN_S; while fewer
# than TARGET_ALIVE are in play (and never more than MAX_ALIVE), one comes out
# every SPAWN_EVERY_S at a zone outside the player's aggro range (no pop-in attacks).
func _respawn(now: float) -> void:
	for id in dead_at.keys():
		if now - dead_at[id] < RESPAWN_S or enemies[id].inert: continue
		_to_reserve(enemies[id])
		dead_at.erase(id)
	if not spawning or now < next_spawn: return
	if alive_count() >= mini(TARGET_ALIVE, MAX_ALIVE): return
	var spot := _free_zone()
	if spot.is_empty(): return
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		if e.reserve:
			var j := Vector3(spawn_rng.randf_range(-2.0, 2.0), 0, spawn_rng.randf_range(-2.0, 2.0))
			e.reset_to(spot.at + j, spot.yaw)
			next_spawn = now + SPAWN_EVERY_S
			return

func alive_count() -> int:
	var n := 0
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		if not e.reserve and not e.health.dead and e.visible: n += 1
	return n

func _free_zone() -> Dictionary:
	var ok: Array = zones.filter(func(z): return Vector2(z.at.x - player.global_position.x, z.at.z - player.global_position.z).length() > BlightedSprite.AGGRO_R + 4.0)
	return ok[spawn_rng.randi() % ok.size()] if not ok.is_empty() else {}

func _to_reserve(e: CharacterBody3D) -> void:
	e.reserve = true
	e.visible = false
	e.get_node("Shape").disabled = true
	e.velocity = Vector3.ZERO
	e.aggroed = false

# Tests: every enemy out of play (hidden, no collision, no AI) until the next
# reset; the ids in `keep` stay as inert target dummies (visible, hittable, no AI).
func park_enemies(keep := []) -> void:
	spawning = false
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		e.inert = true
		e.aggroed = false
		e.velocity = Vector3.ZERO
		if id in keep: continue
		e.visible = false
		e.get_node("Shape").disabled = true
	director.reset()

# Rank and level-ups get the top-centre banner [R15], not a small notice.
# The 16-bit dither follows the world view's pixel grid (it changes with the window).
func _sync_pixel_grid() -> void:
	if art and lofi and lofi.viewport: art.set_low_res(Vector2(lofi.viewport.size))

func _on_ranked(rank: String, points: int) -> void:
	var AP = PageLibrary.AbilityPage
	var from: String = AP.RANKS[maxi(0, AP.rank_index(rank) - 1)]
	var lines := ["+%d stat points" % points, "+%d EXP" % session.progression.EXP.rank_up]
	var pages := []
	for id in PageLibrary.IDS:
		var pg: Resource = session.grimoire.page(id)
		if pg != null and String(pg.rank_req) == rank: pages.append(pg.title)
	if not pages.is_empty(): lines.append("Now equippable: " + ", ".join(pages))
	banner.push_rank(from, rank, lines)

func _on_leveled(level: int, points: int) -> void:
	banner.push_level(level - 1, level, points)

# A notification (level up, rank up, page found or unlocked, not enough MP, on
# cooldown...): newest last; the same text again only refreshes its timer.
func show_notice(text: String, seconds := 1.5) -> void:
	notice = text
	notice_time = seconds
	for n in notices:
		if n[0] == text:
			n[1] = seconds
			return
	notices.append([text, seconds])
	while notices.size() > MAX_NOTICES: notices.pop_front()

# Presentation: the campfire breathes, old tubes flicker (not simulation state).
func _process(delta: float) -> void:
	flicker_t += delta
	for i in lamps.size():
		var lamp: OmniLight3D = lamps[i]
		if lamp.get_meta("flicker", false) is String:
			lamp.light_energy = float(lamp.get_meta("base_energy", 3.5)) * (0.86 + 0.08 * sin(flicker_t * 9.0) + 0.06 * sin(flicker_t * 23.0 + 1.3))
		elif lamp.get_meta("flicker", false):
			var k := sin(flicker_t * 23.0 + i * 3.1) + sin(flicker_t * 7.3 + i)
			var base: float = lamp.get_meta("base_energy", 0.7)
			lamp.light_energy = base * 0.2 if k > 1.6 else base

func publish(_delta: float) -> void:
	if lofi: lofi.sync()
	pcombat.publish()
	var now := session.run.time
	var pr: RefCounted = session.progression
	var m: Dictionary = pr.mission()
	var mission := ("Mission: %s (%d/%d)" % [m.text, m.progress, m.target]) if not m.is_empty() else "Rank %s" % pr.rank
	if director.in_combat: mission += "\nIN COMBAT" + ("" if director.countdown(now) >= director.OUT_OF_COMBAT_S - 0.01 else "  (%.0f s)" % director.countdown(now))
	if audio: audio.tick(_delta, director.in_combat)
	var lines := []
	for n in notices: lines.append(n[0])
	var t := target_in_view()
	hud.refresh({"level": pr.level, "rank": pr.rank, "hp": player.health.hp, "max_hp": player.health.max_hp,
		"mp": pcombat.mp, "max_mp": pcombat.max_mp(now), "mission": mission, "slots": pcombat.slot_view(now),
		"statuses": player_statuses(now), "prompt": "F  Pick up page" if t.kind == "page" else "", "notices": lines, "channel": channel_view(now)})
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		if e.visible: e.set_statuses(effect_statuses(id, now))
	if effects_panel.visible: effects_panel.refresh(effect_rows(now))
	grimoire_panel.tick() # the chant hint's countdown
	if grimoire_panel.visible and grimoire_panel.tab == "effects": # live countdown, 4 times a second
		_grim_fx_t += _delta
		if _grim_fx_t >= 0.25:
			_grim_fx_t = 0.0
			grimoire_panel.refresh()
	for id in enemies:
		var e: CharacterBody3D = enemies[id]
		e.set_burning(e.visible and not e.health.dead and effects.has(id, "Burn", now))
	damage_numbers.tick(_delta)
	banner.tick(_delta)

var _effect_full := {} # presentation: each effect instance's full length, for the sweep
# Timed effects on a target as status icons: [{id, frac (time left / full), s}] [R12].
func effect_statuses(target: String, now: float) -> Array:
	var out := []
	for eid in effects.active.get(target, {}):
		if not effects.has(target, eid, now): continue
		var e: Dictionary = effects.active[target][eid]
		var key := "%s|%s|%d" % [target, eid, e.serial]
		var left: float = e.until - now
		if left > float(_effect_full.get(key, 0.0)): _effect_full[key] = left # first seen, or refreshed: the full length
		out.append({"id": eid, "frac": left / maxf(float(_effect_full[key]), 0.001), "s": left})
	return out

# The player's buffs and debuffs: Cultivate, Concuss, Sage Arts at work, and any effect on them.
# The HUD's cast bar: {label, frac} while Dragon's Breath or Explosion runs, else {}.
func channel_view(now: float) -> Dictionary:
	if not spells.charge.is_empty(): return {"label": "Explosion  charging", "frac": spells.charge_fraction(now)}
	if not spells.breath.is_empty(): return {"label": "Dragon's Breath", "frac": clampf((float(spells.breath.until) - now) / float(spells.BREATH.s), 0.0, 1.0)}
	return {}

func player_statuses(now: float) -> Array:
	var out := []
	if now < pcombat.cultivate_until:
		var full: float = pcombat.loadout.skill_1.duration_s if pcombat.loadout.get("skill_1") != null and String(pcombat.loadout.skill_1.id) == "cultivate" else 10.0
		out.append({"id": "Cultivate", "frac": (pcombat.cultivate_until - now) / maxf(full, 0.001), "s": pcombat.cultivate_until - now})
	for m in session.stats.modifiers:
		if m.id == "concuss" and m.stat == "mov_spd" and now < m.until:
			out.append({"id": "Concuss", "frac": (m.until - now) / BlightedSprite.CONCUSS_S, "s": m.until - now})
	if pcombat.sage_active(now): # only while it restores (it rests at full HP and MP)
		out.append({"id": "Sage Arts", "frac": 1.0, "s": 0.0})
	out.append_array(effect_statuses("player", now))
	return out

# A new forest [Sir R11]: draw (or take the pinned) seed, generate, build the
# trees, rocks and ledges, and take the map's page spots and spawn zones.
func new_map(seed := -1) -> bool:
	var t0 := Time.get_ticks_usec()
	var candidate_seed: int = seed if seed >= 0 else (fixed_map_seed if fixed_map_seed >= 0 else randi())
	var candidate := DarkForest.generate(candidate_seed)
	if candidate.is_empty(): return false
	map_seed = candidate_seed
	map = candidate
	spawn_rng.seed = map_seed ^ 0x5bd1
	static_solids = _fixed_solids + DarkForest.scatter(_forest_node, map)
	zones = map.zones
	page_spots = map.pages
	for id in page_pickups:
		if page_spots.has(id): page_pickups[id].position = page_spots[id] + Vector3(0, 0.6, 0)
	map_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return true

func reset_run() -> void:
	if training: training.reset() # a restart or death always returns to the forest, at night
	if world_kind == "forest":
		if _map_fresh: _map_fresh = false
		elif not new_map():
			show_notice("Map generation failed. Reusing the previous forest.", 8.0)
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
	player.stats = session.stats
	player.carry_factor = 1.0
	player.reset_movement()
	_rebuild_navs()
	nav_dirty = false
	var n := 0
	for id in enemies: # the six zones start occupied; the rest wait in the pool
		var spec: Dictionary = zones[n % zones.size()]
		enemies[id].reset_to(spec.at, spec.yaw, noise.last_id())
		if n >= zones.size(): _to_reserve(enemies[id])
		n += 1
	dead_at.clear()
	spawning = true
	next_spawn = SPAWN_EVERY_S
	director.reset()
	_sync_page_pickups()
	if not session.progression.ranked.is_connected(_on_ranked): session.progression.ranked.connect(_on_ranked)
	if not session.progression.leveled.is_connected(_on_leveled): session.progression.leveled.connect(_on_leveled)
	if death_panel: death_panel.hide_panel()
	died_at = -1.0
	footstep_timer = 0.0
	noise.reset()
	interact_was = false
	notice_time = 0.0
	notices.clear()
	complete = false
	pcombat.reset()
	hazards.reset()
	projectiles.reset()
	spells.reset()
	if vfx: vfx.reset()
	if audio: audio.reset()
	effects = EffectSystem.new()
	projectiles.effects = effects
	effect_packets.clear()
	_effect_full.clear()
	if damage_numbers: damage_numbers.clear()
	if banner: banner.clear()
	if sfx: sfx.played.clear()
	fall_speed = 0.0
	was_on_floor = true
	for l in lamps: l.light_energy = l.get_meta("base_energy", 0.7)
	if prompt: prompt.text = ""
