extends Node3D
# The player's spellcaster (Grimoire MVP P2, docs/pivot-grimoire-plan.md).
# The equipped attack page ("Scorch and Burn" until the PageDatabase lands)
# drives the mouse buttons:
#   LMB held: basic fireball every 1 / Atk Spd seconds (no cooldown, no MP) [GDD §2]
#   RMB:      special fireball at the crosshair point (up to 40 m [S7]); its
#             cooldown is reduced by Spell Mastery [spec §1.2]
# MP is a pool sized by Max MP; spells spend it. The player holds the grimoire
# and the Ember Wand (held_rig.gd) [Sir, 2026-11-20]: every cast leaves from the
# wand's tip; no casting while mantling or climbing.
# Loadout: spell_1..4 (keys 1-4 turn the held book to them) and the
# passive. Skills cost no MP and ignore Spell Mastery; spells cost MP and their
# cooldowns take Mastery; a page needs its rank to be equipped and to be used.
#   Cultivate (skill): 10 s of Pow x1.10, Mastery +20%, Atk Spd x1.15; 20 s cooldown
#   Quick Step (skill): 5 m teleport along the held move (forward if none), never into a wall; 10 s
#   Ring of Fire (spell, rank D): 6 orbs at 3 m for 10 s, 15% Pow per hit + Scorched Slow [R12]; 30 MP; 15 s x Mastery
#   Sage Arts (passive, rank D): +3% max HP/s and +5% max MP/s while out of combat [S4]

const CombatController = preload("res://scripts/combat/combat_controller.gd")
const HeldRig = preload("res://scripts/player/held_rig.gd")
const AbilityPage = preload("res://scripts/core/ability_page.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")

# The held grimoire [Sir, 2026-11-20; docs/plan-held-grimoire.md]: 4 spell slots
# (any attack, skill or spell page) and 1 passive. Keys 1-4 turn the book to a
# spell page, 5 to the status page; LMB casts the open page, RMB its special.
const SPELL_SLOTS := ["spell_1", "spell_2", "spell_3", "spell_4"]
const SLOTS := ["spell_1", "spell_2", "spell_3", "spell_4", "passive"]
const STATUS_PAGE := 4         # page index of the status page (key 5)
const TURN_S := 0.5            # seconds per leaf crossed
# Old slot names (before 2026-11-20) in fill order: the attack page first, then
# skills and spells in their old order (migrate_loadout).
const OLD_ORDER := ["attack", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3"]
const CULTIVATE := {"magic_pow": [1.10, 0.0], "spell_mastery": [1.0, 0.20], "atk_spd": [1.15, 0.0]} # [mul, flat] [GDD page 2]
const QUICK_STEP_M := 5.0        # [GDD page 4]
const SAGE_HP := 0.03            # of max HP per second [S4]
const SAGE_MP := 0.05            # of max MP per second [S4]

const CAST_POSE_S := 0.15  # the tip glows this long after any cast [design]
const AIM_RANGE := 100.0   # crosshair ray for the basic fireball's convergence point

var world: Node3D          # main (session, player, enemies, projectiles, effects)
var combat: CombatController
var rig: Node3D            # HeldRig on the camera: the book and the Ember Wand
var wand: Node3D           # rig.wand
var page: Resource         # the open page when it is an attack page (LMB basic, RMB special), else null
var active := 0            # open page: 0-3 the spell slots, STATUS_PAGE the status page
var book_closed := false
var last_spell_slot := 0
var queued_page := -1
var turn_from := 0         # the running turn (the held book reads it too)
var turn_to := 0
var turn_start := -INF
var turns := 0             # turns finished (tests)
var _page_was := {}
var loadout := {}          # slot -> AbilityPage or null
var ready_at := {}         # slot -> sim time it is off cooldown
var casts := {}            # page id -> casts (tests)
var cultivate_until := -INF
var aura: OmniLight3D      # Cultivate glow on the hands (presentation)
var aura_embers: Node3D # its Binbun status aura on the hands (embers without Binbun; made once)
var sage_fx: Node3D     # Sage Arts' green status aura round the body while it restores
var _slot_was := {}
var mp := 100.0
var next_basic := -INF     # sim time the next basic cast is allowed
var special_ready := 0.0   # sim time the special is off cooldown
var basic_casts := 0
# Opt-in profiler (tests/performance/baseline.gd sets it to {}): per substage
# {calls, total_us, max_us}. Null in play: one null check per section.
var prof = null
func _prof(key: String, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	var e: Dictionary = prof.get(key, {"calls": 0, "total_us": 0, "max_us": 0})
	e.calls += 1
	e.total_us += dt
	e.max_us = maxi(e.max_us, dt)
	prof[key] = e
var special_casts := 0
var pose_until := -INF     # the wand's tip glows until (presentation)
var _special_was := false

static func scorch_and_burn() -> Resource:
	return PageLibrary.make("scorch_and_burn") # the PageDatabase supplies the real page in P5

func setup(main: Node3D) -> void:
	world = main
	var p: CharacterBody3D = world.player
	combat = CombatController.new(p.health, p.endurance)
	combat.origin_fn = func() -> Vector3: return p.eye_position()
	combat.targets_fn = world.combat_targets
	combat.los_fn = world.clear_line
	p.health.died.connect(func(_pk) -> void: combat.on_death())
	rig = HeldRig.new()
	rig.pc = self
	rig.book_right = _book_right()
	p.camera.add_child(rig)
	wand = rig.wand
	p.health.damaged.connect(func(_pk, applied: float) -> void:
		if applied > 0.0 and rig != null: rig.damage(applied >= 100.0))
	p.health.died.connect(func(_pk) -> void:
		if rig != null: rig.equip(false)) # dead: book and wand stowed
	var st = world.session.settings if world.session != null else null
	if st != null: st.changed.connect(_apply_hand)
	aura = OmniLight3D.new()
	aura.name = "CultivateAura"
	aura.light_color = Color(0.55, 0.85, 1.0)
	aura.light_energy = 1.2
	aura.omni_range = 1.2
	_place_aura()
	aura.visible = false
	p.camera.add_child(aura)
	if world.get("vfx") != null:
		aura_embers = world.vfx.make_loop("cultivate")
		if aura_embers == null: aura_embers = world.vfx.aura_particles()
		aura.add_child(aura_embers)
		sage_fx = world.vfx.make_loop("sage")
		if sage_fx: p.add_child(sage_fx) # at the feet, round the body
	_default_loadout()

func rank() -> String:
	return String(world.session.progression.rank)

# Start loadout of every run [handoff §5, R5]: Scorch and Burn and Cultivate.
# Other unlocked pages are equipped from the Grimoire (the loadout is lost on death).
func _default_loadout() -> void:
	for slot in SLOTS: loadout[slot] = null
	var g: RefCounted = world.session.grimoire if world != null and world.session != null else null
	loadout.spell_1 = g.page("scorch_and_burn") if g else scorch_and_burn()
	loadout.spell_2 = g.page("cultivate") if g else PageLibrary.make("cultivate")
	active = 0
	book_closed = false
	last_spell_slot = 0
	queued_page = -1
	turn_from = 0
	turn_to = 0
	turn_start = -INF
	_sync_page()

# A pre-2026-11-20 loadout {attack, skill_1, skill_2, spell_1..3, passive} as the
# held grimoire's: the attack page to slot 1, then skills and spells in their old
# order; past 4 they are left out (still unlocked); the passive is kept.
static func migrate_loadout(old: Dictionary) -> Dictionary:
	var out := {}
	for slot in SLOTS: out[slot] = null
	var i := 0
	for key in OLD_ORDER:
		var pg = old.get(key)
		if pg == null: continue
		if i < SPELL_SLOTS.size(): out[SPELL_SLOTS[i]] = pg
		i += 1
	out.passive = old.get("passive")
	return out

# Which slots a page fits: any non-passive page goes in a spell slot.
static func fits(slot: String, pg: Resource) -> bool:
	if slot == "passive": return pg.kind == AbilityPage.Kind.PASSIVE
	return slot in SPELL_SLOTS and pg.kind != AbilityPage.Kind.PASSIVE

func open_slot() -> String:
	return SPELL_SLOTS[active] if active < SPELL_SLOTS.size() else ""

# `page` follows the open page: an attack page there drives LMB/RMB.
func _sync_page() -> void:
	var pg: Resource = loadout.get(open_slot()) if open_slot() != "" else null
	page = pg if pg != null and pg.kind == AbilityPage.Kind.ATTACK else null

# The active spell changes after the turn completes. Redirect at a leaf boundary.
func turning(now: float) -> bool:
	return now < turn_start + TURN_S * flips()

func flips() -> int:
	return absi(turn_to - turn_from)

func turn_to_page(i: int, now: float) -> bool:
	if book_closed or i < 0 or i > STATUS_PAGE: return false
	_advance_turn(now)
	if turning(now):
		var dir := signi(turn_to - turn_from)
		var landed := floori((now - turn_start) / TURN_S)
		turn_to = turn_from + dir * (landed + 1)
		queued_page = i if i != turn_to else -1
		return true
	if i == active: return false
	turn_from = active
	turn_to = i
	turn_start = now
	return true

func _advance_turn(now: float) -> void:
	while turn_start > -INF and not turning(now):
		var end_time := turn_start + TURN_S * flips()
		active = turn_to
		if active < STATUS_PAGE: last_spell_slot = active
		turns += 1
		_sync_page()
		if queued_page < 0:
			turn_start = -INF
		else:
			turn_from = active
			turn_to = queued_page
			queued_page = -1
			turn_start = end_time

func toggle_book(now: float) -> void:
	_advance_turn(now)
	book_closed = not book_closed
	if book_closed:
		# An unfinished selection never replaces the equipped spell.
		active = last_spell_slot
		turn_from = active
		turn_to = active
		turn_start = -INF
		queued_page = -1
		_sync_page()

# Equip rules: only unlocked pages, slot kind must match, the rank must allow
# it, no page twice. Returns "ok", "unknown_slot", "locked", "wrong_kind",
# "rank" or "duplicate"; null empties the slot.
func equip(slot: String, pg: Resource) -> String:
	if not slot in SLOTS: return "unknown_slot"
	if pg == null:
		loadout[slot] = null
		_sync_page()
		return "ok"
	if not world.session.grimoire.is_unlocked(String(pg.id)): return "locked"
	if not fits(slot, pg): return "wrong_kind"
	if not pg.rank_ok(rank()): return "rank"
	for other in SLOTS:
		if other != slot and loadout[other] != null and loadout[other].id == pg.id: return "duplicate"
	loadout[slot] = pg
	_sync_page()
	return "ok"

func remaining(slot: String, now: float) -> float:
	if free_casting(): return 0.0
	return maxf(0.0, float(ready_at.get(slot, 0.0)) - now)

# Cooldown left as a fraction of the slot's last full cooldown (HUD overlays).
func fraction(slot: String, now: float) -> float:
	var full: float = float(_full_cd.get(slot, 0.0))
	return 0.0 if full <= 0.0 else clampf(remaining(slot, now) / full, 0.0, 1.0)
var _full_cd := {}

func stats() -> RefCounted:
	return world.session.stats

func max_mp(now := 0.0) -> float:
	return float(stats().value("max_mp", now))

func reset() -> void:
	combat.reset()
	mp = max_mp()
	next_basic = -INF
	special_ready = 0.0
	_special_full = 0.0
	basic_casts = 0
	special_casts = 0
	pose_until = -INF
	_special_was = false
	ready_at.clear()
	_full_cd.clear()
	casts.clear()
	_slot_was.clear()
	cultivate_until = -INF
	control_until = -INF
	rise_kills = 0
	if aura: aura.visible = false
	_default_loadout()
	if rig != null:
		rig.clear_tuck()
		rig.equip(true) # a new run: book and wand back out
	turns = 0
	_page_was.clear()

func aim_dir() -> Vector3:
	return -world.player.camera.global_transform.basis.z

# Spend MP if there is enough (spells, P4). Returns false and spends nothing otherwise.
# Settings > "Infinite Mana + No Cooldown" (testing): MP is never spent or
# required and every skill, spell and special cooldown is 0. The basic attack
# keeps its Atk Spd rate (a fire rate, not a cooldown).
func free_casting() -> bool:
	var ss = world.get("session")
	return ss != null and ss.settings != null and bool(ss.settings.infinite_mana)

func spend_mp(amount: float) -> bool:
	if free_casting(): return true
	if amount > mp + 1e-6: return false
	mp -= amount
	return true

func special_remaining(now: float) -> float:
	if free_casting(): return 0.0
	return maxf(0.0, special_ready - now)

# Free to cast (not dead, not mantling, hanging or climbing).
func hands_free() -> bool:
	var p: CharacterBody3D = world.player
	return not p.health.dead and p.state != p.Move.MANTLE and p.state != p.Move.WALLCLIMB

# LMB / RMB need an attack page: an empty attack slot casts nothing [R12].
func can_cast() -> bool:
	return page != null and hands_free() and spell_busy() == "" and not addicted() and not controlled()

# Knockback, stun or another control effect [Sir, 2026-11-15]: no casting until it
# ends (Concuss only slows; it never blocks casting).
var control_until := -INF
func controlled() -> bool:
	return world.session.run.time < control_until

# Gambling Addiction (Let it Ride): every other attack, skill, spell and passive is off.
func addicted() -> bool:
	return world.get("gambler") != null and world.gambler.addicted

# Dragon's Breath or Explosion running: no other attack, skill or spell.
func spell_busy() -> String:
	return world.spells.busy() if world.get("spells") != null else ""

func simulate(intent: Dictionary, delta: float, now: float) -> void:
	var t0 := Time.get_ticks_usec() if prof != null else 0
	if spell_busy() != "":
		pose_until = now + 0.1 # the tip stays lit for the whole breath / charge
	combat.advance(delta, now)
	if prof != null:
		_prof("advance", t0)
		t0 = Time.get_ticks_usec()
	var h: Node = world.player.health
	h.max_hp = float(stats().value("max_hp", now)) # Max HP stat sizes the player's pool
	h.hp = minf(h.hp, h.max_hp)
	mp = minf(mp, max_mp(now))
	_sage_arts(delta, now)
	if prof != null:
		_prof("resources", t0)
		t0 = Time.get_ticks_usec()
	var q_down: bool = intent.get("toggle_book", false)
	if q_down and not _page_was.get("toggle_book", false): toggle_book(now)
	_page_was["toggle_book"] = q_down
	for i in STATUS_PAGE + 1: # keys 1-5: turn the held book
		var key := "page_%d" % (i + 1)
		var pdown: bool = intent.get(key, false)
		if pdown and not _page_was.get(key, false): turn_to_page(i, now)
		_page_was[key] = pdown
	_advance_turn(now)
	var attack_down: bool = intent.get("attack", false)
	var attack_edge: bool = attack_down and not _slot_was.get("attack", false)
	_slot_was["attack"] = attack_down
	if turning(now) or active == STATUS_PAGE: # mid-turn, or on the status page: nothing casts
		_special_was = intent.get("special", false)
		next_basic = maxf(next_basic, now)
		if prof != null: _prof("slots", t0)
		return
	var open: Resource = loadout.get(open_slot())
	if open != null and open.kind != AbilityPage.Kind.ATTACK: # a skill or spell page: LMB casts it; RMB nothing
		_special_was = intent.get("special", false)
		if attack_edge and hands_free(): _notify(use_slot(open_slot(), intent.get("move", Vector2.ZERO), now), open_slot())
		if prof != null: _prof("slots", t0)
		return
	if prof != null:
		_prof("slots", t0)
		t0 = Time.get_ticks_usec()
	var special_down: bool = intent.get("special", false)
	var special_edge := special_down and not _special_was
	_special_was = special_down
	if not can_cast():
		next_basic = maxf(next_basic, now) # no banked casts while the hands are busy
		return
	# Basic: held LMB fires on the Atk Spd interval; the schedule carries the
	# fraction over (a 5.2/s rate is not rounded to whole ticks), but an idle
	# button never banks casts.
	if intent.get("attack", false):
		if next_basic < now - delta: next_basic = now
		if now + 1e-6 >= next_basic:
			cast_basic(now)
			next_basic += stats().attack_interval(now)
	if special_edge and (free_casting() or now + 1e-6 >= special_ready):
		cast_special(now)
	if prof != null: _prof("schedule_and_casts", t0)

# One slot press. Returns "ok", "empty", "cooldown", "rank" or "mp".
func use_slot(slot: String, move: Vector2, now: float) -> String:
	var pg: Resource = loadout.get(slot)
	if pg == null: return "empty"
	if spell_busy() != "": return "busy"
	if addicted() and String(pg.id) != "let_it_ride": return "addicted"
	if controlled(): return "controlled"
	if String(pg.id) == "let_it_ride" and world.gambler.rolling(): return "rolling" # the die is still tumbling
	if not pg.rank_ok(rank()): return "rank"
	if remaining(slot, now) > 0.0: return "cooldown"
	if world.get("spells") != null:
		var why: String = world.spells.precheck(String(pg.id), now) # before anything is spent
		if why != "": return why
	if pg.kind == AbilityPage.Kind.SPELL and not spend_mp(pg.mp_cost): return "mp"
	_pose(now) # the one generic cast kick, whatever the page
	match String(pg.id):
		"cultivate": _cultivate(pg, now)
		"quick_step": quick_step(move)
		"ring_of_fire": _ring_of_fire(pg, now)
		"dragons_breath": world.spells.start_breath(pg, slot, now)
		"firefly":
			world.spells.start_firefly(pg, now)
		"flight_of_the_phoenix": world.spells.start_flight(pg, slot, now)
		"call_of_the_phoenix": world.spells.start_call(pg, slot, now)
		"all_in": world.gambler.start_all_in(now)
		"let_it_ride":
			var r: Dictionary = world.gambler.roll(now)
			var cd: float = world.gambler.cooldown_after(r) # 5 s; 3 s after a low roll; none in Addiction
			ready_at[slot] = now + cd
			_full_cd[slot] = cd
			casts[String(pg.id)] = int(casts.get(String(pg.id), 0)) + 1
			return "ok"
		"explosion":
			world.spells.start_explosion(pg, slot, now)
			ready_at[slot] = INF # its cooldown starts when the charge ends (complete or broken)
			_full_cd[slot] = 0.0
			casts[String(pg.id)] = int(casts.get(String(pg.id), 0)) + 1
			return "ok"
	start_cooldown(slot, pg, now)
	casts[String(pg.id)] = int(casts.get(String(pg.id), 0)) + 1
	return "ok"

func start_cooldown(slot: String, pg: Resource, now: float) -> void:
	var cd: float = stats().cooldown(pg.cooldown_s, pg.kind == AbilityPage.Kind.SPELL and pg.mastery_applies, now)
	ready_at[slot] = now + cd
	_full_cd[slot] = cd

func _cultivate(pg: Resource, now: float) -> void:
	if stats().buff_block: return # Gambling Addiction: no buff lands
	for stat in CULTIVATE:
		stats().add_modifier("cultivate", stat, CULTIVATE[stat][0], CULTIVATE[stat][1], now + pg.duration_s)
	cultivate_until = now + pg.duration_s

# Teleport QUICK_STEP_M along the held move (normalised: diagonals too), forward
# when none is held; a capsule shape-cast stops it short of any wall. Returns the distance moved.
func quick_step(move: Vector2) -> float:
	var p: CharacterBody3D = world.player
	var dir: Vector3 = p.wish_dir(move) if move != Vector2.ZERO else p._flat_forward()
	if dir == Vector3.ZERO: dir = p._flat_forward()
	var shape_node: CollisionShape3D = p.get_node("Shape")
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape_node.shape
	q.transform = shape_node.global_transform.translated(Vector3(0, 0.05, 0)) # just off the floor
	q.motion = dir * QUICK_STEP_M
	q.collision_mask = 1 | 0b1000 # world and enemies
	q.exclude = [p.get_rid()]
	var frac: PackedFloat32Array = p.get_world_3d().direct_space_state.cast_motion(q)
	var safe: float = frac[0] if frac.size() > 0 else 1.0
	var dist := maxf(0.0, QUICK_STEP_M * safe - (0.02 if safe < 1.0 else 0.0))
	var from := p.global_position
	p.global_position += dir * dist
	if world.get("vfx") != null: world.vfx.step_flash(from, p.global_position, world.session.run.time) # pooled
	return dist

func _ring_of_fire(pg: Resource, now: float) -> void:
	var p: CharacterBody3D = world.player
	world.projectiles.summon_ring(func() -> Vector3: return p.global_position, now, pg.duration_s, _pow(now) * pg.damage_pct)

# Sage Arts: out of combat only (the AggroTracker's 3 s grace included [R12]) [GDD page 5].
# Active only while it has something to restore [Sir, 2026-11-13]: equipped,
# out of combat, alive, and HP or MP below full; at full HP and MP it rests.
func sage_active(now: float) -> bool:
	if spell_busy() == "flight" or addicted(): return false # Flight of the Phoenix and Gambling Addiction hold every passive
	var pg: Resource = loadout.get("passive")
	if pg == null or String(pg.id) != "sage_arts" or not pg.rank_ok(rank()): return false
	if world.director.in_combat: return false
	var h: Node = world.player.health
	if h.dead: return false
	return h.hp < h.max_hp - 0.001 or mp < max_mp(now) - 0.001

# ---- Rise of the Phoenix [Sir, 2026-11-14] -----------------------------------------------------
# Killing a burning enemy: +2% max HP and +2% max MP. Rebirth arms after 20 kills
# this run (the counter clears when used). Armed, a lethal hit revives the player
# in place at full HP (MP unchanged), 2 s invulnerable, with a 200% Magic Pow
# blast + Burn that knocks everything within 20 m out to 20 m.
const RISE := {"heal": 0.02, "arm_kills": 20, "invuln_s": 2.0, "blast_r": 20.0, "burn_s": 5.0}
var rise_kills := 0
var rise_revives := 0

func rise_equipped() -> bool:
	if addicted(): return false
	var pg: Resource = loadout.get("passive")
	return pg != null and String(pg.id) == "rise_of_the_phoenix" and pg.rank_ok(rank())

func rise_armed() -> bool:
	return rise_equipped() and rise_kills >= int(RISE.arm_kills)

func on_enemy_killed(was_burning: bool, now: float) -> void:
	if not rise_equipped(): return
	if rise_kills < int(RISE.arm_kills): rise_kills += 1
	if was_burning and spell_busy() != "flight":
		var h: Node = world.player.health
		if not h.dead: h.hp = minf(h.max_hp, h.hp + h.max_hp * float(RISE.heal))
		mp = minf(max_mp(now), mp + max_mp(now) * float(RISE.heal))

# Health.death_guard: armed, the lethal hit becomes a rebirth.
func rise_guard(_packet: RefCounted) -> bool:
	if not rise_armed(): return false
	var now: float = world.session.run.time
	var h: Node = world.player.health
	h.hp = h.max_hp
	h.grant_immunity(now + float(RISE.invuln_s), ["*"], -INF, "rise")
	rise_kills = 0
	rise_revives += 1
	var pg: Resource = loadout.get("passive")
	if world.get("spells") != null:
		world.spells.blast(world.player.global_position, float(RISE.blast_r), _pow(now) * pg.damage_pct, pg.effect_id, float(RISE.burn_s), float(RISE.blast_r), now, "rise")
	if world.get("sfx") != null: world.sfx.play("rebirth", world.player.global_position)
	if world.has_method("show_notice"): world.show_notice("Rise of the Phoenix: reborn!", 2.0)
	return true

func rise_label() -> String:
	return "Armed" if rise_armed() else "%d/%d" % [rise_kills, int(RISE.arm_kills)]

func _sage_arts(delta: float, now: float) -> void:
	if not sage_active(now): return
	var h: Node = world.player.health
	h.hp = minf(h.max_hp, h.hp + h.max_hp * SAGE_HP * delta)
	mp = minf(max_mp(now), mp + max_mp(now) * SAGE_MP * delta)

func _pow(now: float) -> float:
	return float(stats().value("magic_pow", now))

# Book hand from Settings [Sir, 2026-11-20]: right by default, the wand in the other.
func _book_right() -> bool:
	var st = world.session.settings if world != null and world.session != null else null
	return st != null and String(st.book_hand) == "right"

func _apply_hand() -> void:
	if rig != null and rig.book_right != _book_right(): rig.set_book_right(_book_right())
	_place_aura()

func _place_aura() -> void:
	if aura == null or wand == null: return
	aura.position = wand.position + Vector3(0, 0, -0.2) # by the wand

# Where spells leave from: the wand's tip at its rest pose (lower right of the
# view), so the sway and bob never move a shot.
func hand_origin() -> Vector3:
	var cam: Camera3D = world.player.camera
	var eye: Vector3 = cam.global_position
	var at: Vector3 = wand.tip_rest_global() if wand != null else eye
	return at if world.clear_line(eye, at) else eye # never from inside a wall

# Where the crosshair points: the first world surface or enemy, else AIM_RANGE out.
func crosshair_point(reach: float) -> Dictionary:
	var eye: Vector3 = world.player.camera.global_position
	var dir := aim_dir()
	var to := eye + dir * reach
	var best := reach
	var w: Dictionary = world.world_ray(eye, to)
	if not w.is_empty(): best = eye.distance_to(w.position)
	var on_enemy := false
	for t in world.combat_targets():
		var d: float = world.projectiles.target_along(eye, dir, best, t)
		if d >= 0.0 and d < best:
			best = d
			on_enemy = true
	return {"point": eye + dir * best, "hit": best < reach - 1e-3, "enemy": on_enemy}

func cast_basic(now: float) -> Dictionary:
	var t0 := Time.get_ticks_usec() if prof != null else 0
	var origin := hand_origin()
	if prof != null:
		_prof("cast.hand_origin", t0)
		t0 = Time.get_ticks_usec()
	var aim := crosshair_point(AIM_RANGE)
	if prof != null:
		_prof("cast.crosshair", t0)
		t0 = Time.get_ticks_usec()
	var dir: Vector3 = (aim.point - origin)
	dir = dir.normalized() if dir.length() > 0.5 else aim_dir()
	basic_casts += 1
	_pose(now, false, true)
	if String(page.id) == "heads_or_tails": # Heads: one coin at one enemy
		return world.gambler.throw("heads", origin, dir, _pow(now) * page.damage_pct, _pow(now), null, now)
	var shot: Dictionary = world.projectiles.launch("basic", origin, dir, {"damage": _pow(now) * page.damage_pct,
		"effect": page.effect_id, "effect_s": page.effect_s, "pow": _pow(now)})
	if prof != null: _prof("cast.launch", t0)
	return shot

func cast_special(now: float) -> Dictionary:
	var origin := hand_origin()
	var coin := String(page.id) == "heads_or_tails"
	var aim := crosshair_point(world.gambler.GIANT.range if coin else world.projectiles.KINDS.special.range)
	var dir: Vector3 = (aim.point - origin)
	dir = dir.normalized() if dir.length() > 0.5 else aim_dir()
	special_casts += 1
	special_ready = now + stats().cooldown(page.special_cooldown_s, page.mastery_applies, now)
	_special_full = special_ready - now
	_pose(now, true, true)
	if coin: # Tails: the giant coin
		return world.gambler.throw("tails", origin, dir, _pow(now) * page.special_damage_pct, _pow(now), aim.point, now)
	return world.projectiles.launch("special", origin, dir, {"damage": _pow(now) * page.special_damage_pct,
		"effect": page.effect_id, "effect_s": page.special_effect_s, "pow": _pow(now), "target_point": aim.point})

# A cast was accepted: the wand's kick (Attack for an attack page's basic,
# Cast otherwise) and the book's snap; the tip stays lit CAST_POSE_S.
func _pose(now: float, special := false, attack := false) -> void:
	pose_until = now + CAST_POSE_S
	if rig != null: rig.cast(special, attack)

var _special_full := 0.0

# A refused key press is announced [handoff §7 notifications].
func _notify(result: String, slot: String) -> void:
	if not world.has_method("show_notice"): return
	match result:
		"mp": world.show_notice("Not enough MP", 1.0)
		"cooldown": world.show_notice("%s is on cooldown" % loadout[slot].title, 1.0)
		"rank": world.show_notice("%s needs rank %s" % [loadout[slot].title, loadout[slot].rank_req], 1.5)
		"no_target": world.show_notice("No enemy in sight to lock on to", 1.2)
		"mp_full": world.show_notice("%s needs full MP" % loadout[slot].title, 1.2)
		"airborne": world.show_notice("%s must be cast from the ground" % loadout[slot].title, 1.2)
		"addicted": world.show_notice("Gambling Addiction: only Let it Ride", 1.2)
		"rolling": world.show_notice("The die is still rolling", 0.8)

# Special cooldown left as a fraction (0 = ready), for the crosshair ring.
func special_fraction(now: float) -> float:
	return 0.0 if _special_full <= 0.0 else clampf(special_remaining(now) / _special_full, 0.0, 1.0)

# The HUD's view of each action-bar slot: {id, title, rank_req, state, cd_frac, cd_s};
# state is empty, ready, cooldown, locked (rank) or mp (too little MP). "basic"
# and "special" are the attack page's two casts (LMB, RMB) [R12].
func slot_view(now: float) -> Dictionary:
	var out := {}
	if page == null:
		out.basic = {"state": "empty"}
		out.special = {"state": "empty"}
	else:
		var iv: float = stats().attack_interval(now)
		var b_left := maxf(0.0, next_basic - now)
		out.basic = {"id": String(page.id), "title": "Basic", "state": "cooldown" if b_left > 0.0 else "ready", "cd_frac": clampf(b_left / maxf(iv, 1e-6), 0.0, 1.0), "cd_s": b_left}
		out.special = {"id": String(page.id), "title": "Special", "state": "cooldown" if special_remaining(now) > 0.0 else "ready", "cd_frac": special_fraction(now), "cd_s": special_remaining(now)}
		if addicted():
			out.basic.state = "addicted"
			out.special.state = "addicted"
	for slot in SLOTS:
		var pg: Resource = loadout.get(slot)
		if pg == null:
			out[slot] = {"state": "empty"}
			continue
		var st := "ready"
		if addicted() and String(pg.id) != "let_it_ride": st = "addicted"
		elif not pg.rank_ok(rank()): st = "locked"
		elif remaining(slot, now) > 0.0 and remaining(slot, now) < INF: st = "cooldown"
		elif remaining(slot, now) == INF: st = "channel" # Explosion charging
		elif pg.kind == AbilityPage.Kind.SPELL and mp < pg.mp_cost and not free_casting(): st = "mp"
		elif String(pg.id) == "explosion" and mp < max_mp(now) - 0.001 and not free_casting(): st = "mp"
		out[slot] = {"id": String(pg.id), "title": pg.title, "rank_req": pg.rank_req, "state": st, "cd_frac": fraction(slot, now), "cd_s": remaining(slot, now)}
	return out

func hud_text(now: float) -> String:
	var sp := "ready" if special_remaining(now) <= 0.0 else "%.1f s" % special_remaining(now)
	return "MP %d/%d     RMB special: %s" % [roundi(mp), roundi(max_mp(now)), sp]

# The loadout as text (debug): key, page, and its state.
func action_bar_text(now: float) -> String:
	var parts := []
	for pair in [["1", "spell_1"], ["2", "spell_2"], ["3", "spell_3"], ["4", "spell_4"], ["P", "passive"]]:
		var pg: Resource = loadout.get(pair[1])
		var state := "-"
		if pg != null:
			state = pg.title
			if not pg.rank_ok(rank()): state += " (rank %s)" % pg.rank_req
			elif remaining(pair[1], now) > 0.0: state += " %.0fs" % ceilf(remaining(pair[1], now))
			elif pg.kind == AbilityPage.Kind.SPELL and mp < pg.mp_cost: state += " (MP)"
		parts.append("[%s] %s" % [pair[0], state])
	return "   ".join(parts)

# Presentation: the wand's tip glow, the Cultivate and Sage Arts auras.
func _sync_wand() -> void:
	var now: float = world.session.run.time
	if wand != null:
		var busy := spell_busy() != ""
		if busy and not wand.channeling: wand.trigger(&"Channel") # Dragon's Breath, Explosion: the tip held lit
		elif not busy and wand.channeling: wand.end_channel()
	if aura:
		aura.visible = now < cultivate_until
		if aura_embers is GPUParticles3D:
			var ae := aura_embers as GPUParticles3D
			if ae.emitting != aura.visible: ae.emitting = aura.visible
		elif aura_embers: world.vfx.set_loop(aura_embers, aura.visible)
	if sage_fx: world.vfx.set_loop(sage_fx, sage_active(now))

func publish() -> void:
	_sync_wand()
