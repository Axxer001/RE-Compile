extends Node3D
# The player's spellcaster (Grimoire MVP P2, docs/pivot-grimoire-plan.md).
# The equipped attack page ("Scorch and Burn" until the PageDatabase lands)
# drives the mouse buttons:
#   LMB held: basic fireball every 1 / Atk Spd seconds (no cooldown, no MP) [GDD §2]
#   RMB:      special fireball at the crosshair point (up to 40 m [S7]); its
#             cooldown is reduced by Spell Mastery [spec §1.2]
# MP is a pool sized by Max MP; spells spend it. The hands cast: the right
# palm pushes forward on a basic cast, both hands on a special, and both palms
# plant on a ledge or wall while mantling or climbing (no casting then).
# P4 loadout (GDD §3.1.3): attack, skill_1 (E), skill_2 (Q), spell_1..3 (1-3),
# passive. Skills cost no MP and ignore Spell Mastery; spells cost MP and their
# cooldowns take Mastery; a page needs its rank to be equipped and to be used.
#   Cultivate (skill): 10 s of Pow x1.10, Mastery +20%, Atk Spd x1.15; 20 s cooldown
#   Quick Step (skill): 5 m teleport along the held move (forward if none), never into a wall; 10 s
#   Ring of Fire (spell, rank D): 6 orbs at 3 m for 10 s, 15% Pow per hit + Scorched Slow [R12]; 30 MP; 15 s x Mastery
#   Sage Arts (passive, rank D): +3% max HP/s and +5% max MP/s while out of combat [S4]

const CombatController = preload("res://scripts/combat/combat_controller.gd")
const ArmsRig = preload("res://scripts/combat/arms_rig.gd")
const PlayerBody = preload("res://scripts/player/player_body.gd")
const AbilityPage = preload("res://scripts/core/ability_page.gd")
const PageLibrary = preload("res://scripts/core/page_library.gd")

const SLOTS := ["attack", "skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "passive"]
const SLOT_KIND := {"attack": AbilityPage.Kind.ATTACK, "skill_1": AbilityPage.Kind.SKILL, "skill_2": AbilityPage.Kind.SKILL,
	"spell_1": AbilityPage.Kind.SPELL, "spell_2": AbilityPage.Kind.SPELL, "spell_3": AbilityPage.Kind.SPELL, "passive": AbilityPage.Kind.PASSIVE}
const CULTIVATE := {"magic_pow": [1.10, 0.0], "spell_mastery": [1.0, 0.20], "atk_spd": [1.15, 0.0]} # [mul, flat] [GDD page 2]
const QUICK_STEP_M := 5.0        # [GDD page 4]
const SAGE_HP := 0.03            # of max HP per second [S4]
const SAGE_MP := 0.05            # of max MP per second [S4]

const HAND_FORWARD := Vector3(0.0, -0.02, -0.3) # cast push of a palm, rig-local (m) [design]
const CAST_POSE_S := 0.12  # basic: the palm stays out this long [design]
const SPECIAL_POSE_S := 0.3
const AIM_RANGE := 100.0   # crosshair ray for the basic fireball's convergence point

var world: Node3D          # main (session, player, enemies, projectiles, effects)
var combat: CombatController
var arms: Node3D           # ArmsRig on the camera
var planted := false       # hands planted on a ledge or wall (mantle / climb)
var page: Resource         # equipped attack page (AbilityPage) = loadout.attack
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
var pose_until := -INF     # cast pose shown until (presentation)
var pose_kind := ""
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
	arms = ArmsRig.new()
	arms.name = "Arms"
	p.camera.add_child(arms)
	var body := PlayerBody.new() # the full first-person body; the arms re-bind onto it
	body.name = "Body"
	p.add_child(body)
	body.setup(p, arms)
	aura = OmniLight3D.new()
	aura.name = "CultivateAura"
	aura.light_color = Color(0.55, 0.85, 1.0)
	aura.light_energy = 1.2
	aura.omni_range = 1.2
	aura.position = Vector3(0, -0.25, -0.35)
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
	loadout.attack = g.page("scorch_and_burn") if g else scorch_and_burn()
	loadout.skill_1 = g.page("cultivate") if g else PageLibrary.make("cultivate")
	page = loadout.attack

# Equip rules: only unlocked pages, slot kind must match, the rank must allow
# it, no page twice. Returns "ok", "unknown_slot", "locked", "wrong_kind",
# "rank" or "duplicate"; null empties the slot.
func equip(slot: String, pg: Resource) -> String:
	if not slot in SLOTS: return "unknown_slot"
	if pg == null:
		loadout[slot] = null
		if slot == "attack": page = null
		return "ok"
	if not world.session.grimoire.is_unlocked(String(pg.id)): return "locked"
	if pg.kind != SLOT_KIND[slot]: return "wrong_kind"
	if not pg.rank_ok(rank()): return "rank"
	for other in SLOTS:
		if other != slot and loadout[other] != null and loadout[other].id == pg.id: return "duplicate"
	loadout[slot] = pg
	if slot == "attack": page = pg
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
	if planted and arms != null:
		for side in ["r", "l"]: arms.release_hand(side)
	planted = false
	mp = max_mp()
	next_basic = -INF
	special_ready = 0.0
	_special_full = 0.0
	basic_casts = 0
	special_casts = 0
	pose_until = -INF
	pose_kind = ""
	_special_was = false
	ready_at.clear()
	_full_cd.clear()
	casts.clear()
	_slot_was.clear()
	cultivate_until = -INF
	rise_kills = 0
	if aura: aura.visible = false
	_default_loadout()
	if arms != null:
		for side in ["r", "l"]: arms.set_target(side, null)

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

# Hands free for a cast (not dead, not mantling or climbing).
func hands_free() -> bool:
	var p: CharacterBody3D = world.player
	return not p.health.dead and p.state != p.Move.MANTLE and p.state != p.Move.WALLCLIMB

# LMB / RMB need an attack page: an empty attack slot casts nothing [R12].
func can_cast() -> bool:
	return page != null and hands_free() and spell_busy() == "" and not addicted()

# Gambling Addiction (Let it Ride): every other attack, skill, spell and passive is off.
func addicted() -> bool:
	return world.get("gambler") != null and world.gambler.addicted

# Dragon's Breath or Explosion running: no other attack, skill or spell.
func spell_busy() -> String:
	return world.spells.busy() if world.get("spells") != null else ""

func simulate(intent: Dictionary, delta: float, now: float) -> void:
	var t0 := Time.get_ticks_usec() if prof != null else 0
	if spell_busy() != "":
		pose_kind = "special"
		pose_until = now + 0.1 # both palms out for the whole breath / charge
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
	for slot in ["skill_1", "skill_2", "spell_1", "spell_2", "spell_3"]:
		var down: bool = intent.get(slot, false)
		var edge: bool = down and not _slot_was.get(slot, false)
		_slot_was[slot] = down
		if edge and hands_free(): _notify(use_slot(slot, intent.get("move", Vector2.ZERO), now), slot)
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
	if String(pg.id) == "let_it_ride" and world.gambler.rolling(): return "rolling" # the die is still tumbling
	if not pg.rank_ok(rank()): return "rank"
	if remaining(slot, now) > 0.0: return "cooldown"
	if world.get("spells") != null:
		var why: String = world.spells.precheck(String(pg.id), now) # before anything is spent
		if why != "": return why
	if pg.kind == AbilityPage.Kind.SPELL and not spend_mp(pg.mp_cost): return "mp"
	match String(pg.id):
		"cultivate": _cultivate(pg, now)
		"quick_step": quick_step(move)
		"ring_of_fire": _ring_of_fire(pg, now)
		"dragons_breath": world.spells.start_breath(pg, slot, now)
		"firefly":
			world.spells.start_firefly(pg, now)
			_pose("special", now)
		"flight_of_the_phoenix": world.spells.start_flight(pg, slot, now)
		"call_of_the_phoenix": world.spells.start_call(pg, slot, now)
		"all_in": world.gambler.start_all_in(now)
		"let_it_ride":
			var r: Dictionary = world.gambler.roll(now)
			var cd: float = world.gambler.cooldown_after(r) # 5 s; 3 s after a low roll; none in Addiction
			ready_at[slot] = now + cd
			_full_cd[slot] = cd
			_pose("basic", now)
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

# The casting hand: in front of the right shoulder, below the eye.
func hand_origin() -> Vector3:
	var cam: Camera3D = world.player.camera
	var b := cam.global_transform.basis
	var eye: Vector3 = cam.global_position
	var at := eye + b.x * 0.18 - b.y * 0.16 - b.z * 0.35
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
	_pose("basic", now)
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
	_pose("special", now)
	if coin: # Tails: the giant coin
		return world.gambler.throw("tails", origin, dir, _pow(now) * page.special_damage_pct, _pow(now), aim.point, now)
	return world.projectiles.launch("special", origin, dir, {"damage": _pow(now) * page.special_damage_pct,
		"effect": page.effect_id, "effect_s": page.special_effect_s, "pow": _pow(now), "target_point": aim.point})

func _pose(kind: String, now: float) -> void:
	pose_kind = kind
	pose_until = now + (SPECIAL_POSE_S if kind == "special" else CAST_POSE_S)

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
	for slot in ["skill_1", "skill_2", "spell_1", "spell_2", "spell_3", "passive"]:
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

# Action bar (GDD §4; E before Q per S1): key, page, and its state.
func action_bar_text(now: float) -> String:
	var parts := []
	for pair in [["E", "skill_1"], ["Q", "skill_2"], ["1", "spell_1"], ["2", "spell_2"], ["3", "spell_3"], ["P", "passive"]]:
		var pg: Resource = loadout.get(pair[1])
		var state := "-"
		if pg != null:
			state = pg.title
			if not pg.rank_ok(rank()): state += " (rank %s)" % pg.rank_req
			elif remaining(pair[1], now) > 0.0: state += " %.0fs" % ceilf(remaining(pair[1], now))
			elif pg.kind == AbilityPage.Kind.SPELL and mp < pg.mp_cost: state += " (MP)"
		parts.append("[%s] %s" % [pair[0], state])
	return "   ".join(parts)

# Hands (presentation): planted on a ledge/wall while mantling or climbing;
# pushed forward, palm open, while a cast pose runs; free otherwise.
func _sync_arms() -> void:
	if arms == null or arms.skeleton == null: return
	var contact: Dictionary = world.player.hand_contact()
	if not contact.is_empty():
		for side in ["r", "l"]: arms.plant_hand(side, contact.point, contact.normal)
		planted = true
		return
	if planted:
		planted = false
		for side in ["r", "l"]: arms.release_hand(side)
	var now: float = world.session.run.time
	if aura:
		aura.visible = now < cultivate_until
		if aura_embers is GPUParticles3D:
			var ae := aura_embers as GPUParticles3D
			if ae.emitting != aura.visible: ae.emitting = aura.visible
		elif aura_embers: world.vfx.set_loop(aura_embers, aura.visible)
	if sage_fx: world.vfx.set_loop(sage_fx, sage_active(now))
	for side in ["r", "l"]:
		var casting: bool = now < pose_until and (side == "r" or pose_kind == "special")
		if casting:
			arms.set_grip(side, "open")
			arms.set_weight(side, 1.0)
			arms.set_target(side, Transform3D(arms.rests[side].basis, arms.rests[side].origin + HAND_FORWARD))
		elif arms.manual[side]:
			arms.set_target(side, null)
			arms.set_grip(side, "relaxed")

func publish() -> void:
	_sync_arms()
