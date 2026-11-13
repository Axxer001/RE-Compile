extends RefCounted
# Composition and tick order (ported from the 2D build, ADR-002). Holds the
# RunState, InputRouter and the player stats, advances the one simulation
# clock, and restarts by creating a new run. Gameplay rules stay in the world;
# this only orders calls. Optional world hooks are called only if present, so
# systems can arrive milestone by milestone.

const RunState = preload("res://scripts/core/run_state.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")
const Stats = preload("res://scripts/core/stat_container.gd")
const TimeService = preload("res://scripts/core/time_service.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Progression = preload("res://scripts/core/progression.gd")
const MetaProfile = preload("res://scripts/core/meta_profile.gd")
const Grimoire = preload("res://scripts/core/grimoire.gd")

# world: simulate(intent, delta), publish(delta), reset_run(), on_pause_changed(bool), complete
# optional: actors_step(delta, now), effects_step(delta), show_*/hide_* panels
var world: Object
var run: RunState
var input := InputRouter.new()
var stats := Stats.new() # the six player stats (Tech Spec §1.1); Mov Spd drives the run speed
var progression := Progression.new(stats) # level, EXP, rank, kills (points land in stats)
# Death model [Sir, R5]: `meta` outlives every run (pages, rank, chant tiers);
# the run's stats, progression and grimoire are rebuilt on each restart.
var meta := MetaProfile.new()
var grimoire := Grimoire.new(meta)
var time := TimeService.new() # world/player time scales (bullet time, R2)
# Player settings (docs/settings-menu-plan.md). Defaults only: the world loads
# user://settings.cfg when it runs as the game, never under a test runner.
var settings := Settings.new()

func _init(world_value: Object) -> void:
	world = world_value
	run = RunState.new()
	settings.path = "" # nothing is saved unless the world (the real game) turns it on
	settings.changed.connect(_on_settings_changed) # a method, not a lambda: no session <-> settings cycle
	_new_run_state()

# A fresh run on top of the kept meta: rank carried over, unlocked pages known.
func _new_run_state() -> void:
	stats = Stats.new()
	progression = Progression.new(stats)
	progression.rank = meta.rank
	progression.ranked.connect(_on_ranked)
	progression.leveled.connect(_on_leveled) # a method, not a lambda: no session <-> progression cycle
	grimoire = Grimoire.new(meta)

func _on_leveled(l: int, _points: int) -> void:
	meta.note_level(l)

func _on_ranked(r: String, _points: int) -> void:
	meta.set_rank(r) # a rank once earned is kept [R5]

func _on_settings_changed() -> void:
	input.refresh() # rebinds reach the router
	_call("apply_settings")

func paused() -> bool:
	return input.context == InputRouter.Context.PAUSE

func _call(method: String, args := []) -> void:
	if world.has_method(method): world.callv(method, args)

# One fixed simulation tick. Paused ticks do not advance the clock or the world.
# Order: input -> player (movement, interaction) -> actors -> effects -> publish.
func step(delta: float) -> void:
	if paused():
		input.sample() # keep release tracking current
		return
	run.advance(delta)
	time.tick(delta)
	world.simulate(input.sample(), time.player_dt(delta))
	_call("actors_step", [time.world_dt(delta), run.time])
	_call("effects_step", [time.world_dt(delta)])
	world.publish(delta)
	if world.complete and run.lifecycle != RunState.Lifecycle.COMPLETE:
		run.lifecycle = RunState.Lifecycle.COMPLETE
		input.set_context(InputRouter.Context.EXTRACTION)
		_call("show_complete_panel")

func handle_event(event: InputEvent) -> void:
	handle_action(input.action_for_event(event))

func handle_action(action: String) -> void:
	# The Grimoire overlay opens only once the world has one (P5).
	if action == "grimoire" and input.context == InputRouter.Context.GAMEPLAY and not world.has_method("show_grimoire"): return
	var outcome := input.press(action)
	match outcome:
		"paused", "resumed":
			world.on_pause_changed(paused())
		"grimoire_opened":
			_call("show_grimoire")
		"effects_opened":
			_call("show_effects")
		"overlay_closed":
			_call("hide_overlays")

# A hit with an overlay open [Sir R1]: the world may keep it open (a page
# unlock restarts instead); otherwise the overlay closes.
func on_player_damaged() -> void:
	if input.context == InputRouter.Context.OVERLAY:
		if world.has_method("overlay_hit") and world.overlay_hit(): return
		input.close_overlay()
		_call("hide_overlays")

func on_player_died() -> void:
	meta.note_death(run.time)
	meta.save()
	input.set_context(InputRouter.Context.DEATH)
	_call("hide_overlays")
	_call("show_death_panel")

func restart() -> void:
	run = RunState.new()
	_new_run_state()
	time.reset()
	input.set_context(InputRouter.Context.GAMEPLAY)
	input.flush()
	_call("hide_overlays")
	world.reset_run()
	world.on_pause_changed(false)
