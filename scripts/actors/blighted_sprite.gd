extends CharacterBody3D
# Blighted Sprite [Common] -- reworked to Sir's spec 2026-11-15 (docs/plan-dark-forest-roster.md):
#   melee, 500 HP, 30 damage, attack speed 1.00/s (+20% per hit landed on the
#   player, max +100% / 5 stacks, reset after 5 s without a hit), 9 m/s,
#   detection 50 m with line of sight, attack range 5 m; packs of 4.
#   Pounce: at 15-20 m with line of sight, a straight jump-dash at 20 m/s toward
#   where the player was (dodgeable; a tree or rock stops it): 60 damage +
#   Concuss 1.5 s (-80% Mov/Atk Spd); 10 s cooldown. NinjaJump clips.
# The base class of the Forest Ghoul and Kostas Mortus too: the per-actor
# values below (hp_max ... kill_exp) are what a subclass overrides.
# History: the MVP hostile (Tech Spec §4, plan P3). Built from the
# Shambler (reference/shooter/scripts/actors/shambler.gd): same body,
# navigation and clip handling, with the spec's state machine:
#   IDLE_ROAM -(player <= 16 m and in sight)-> CHASE -(<= 1.8 m)-> WINDUP -0.35 s-> STRIKE
#   STRIKE -> CHASE (one hit per 1.2 s cycle); CHASE -(player > 24 m)-> DISENGAGE
#   DISENGAGE -(back at its origin)-> IDLE_ROAM; any -> DEAD at 0 HP.
#   Pounce [Sir R8, R12]: CHASE -(<= 20 m, any facing, in sight, off cooldown)->
#   CHARGE (stands 0.5 s) -> DIVE: a ballistic leap (18 m/s across the ground,
#   up to 25 m) aimed in 3D at where the player was when it set off, high
#   ground and mid-air included; it lands where it lands. Touching the
#   player's capsule deals 20 and Concusses (-80% Mov Spd and Atk Spd for
#   1.5 s); dash i-frames dodge it; one action id per dive.
#   Reach is 3D [R12]: the telegraph and the strike need the player's capsule
#   within 1.8 / 2.2 m across the ground AND within 0.4 m vertically of the
#   Sprite's body, so a player on high ground is never hit from below.
#   Climbing [R12]: blocked by a ledge it can top (mantle <= 2.2 m, wall climb
#   up to 1.5 m more), it climbs it like the player; its nav grid treats such
#   ledges as passable (main's climb grid).
#   Scorched Slow [R12]: `speed_mult` (set by the world from its effects) scales its movement.
# All decisions happen in tick() on the session clock (pauses with the game).
#   [spec]   Tech Spec §4.1: 120 HP, 12 damage per 1.2 s, aggro 16 m,
#            de-aggro 24 m, 0.35 s telegraph, windup at 1.8 m
#   [Sir]    8 m/s fixed (R8 correction); Pounce 10 m, 0.5 s charge, 20 dmg, Concuss -80%
#   [proposed] dive 18 m/s / 12 m, 6 s cooldown, line of sight, Concuss 1.5 s (peer defaults, Sir to confirm)
#   [design] roam radius and pace, strike reach, turn rate

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Health = preload("res://scripts/combat/health_component.gd")
const HostileModels = preload("res://scripts/actors/hostile_models.gd")
# Glowing eyes [graphics direction 2026-11-20]: silhouettes read in the dense fog.
const EYE_COLOR := Color(0.85, 1.0, 0.35)
const EYE_ENERGY := 4.0
const EYE_R := 0.028
var eye_color := EYE_COLOR

enum State { IDLE_ROAM, CHASE, WINDUP, STRIKE, DISENGAGE, DEAD, CHARGE, DIVE, STUN } # STUN: Kostas Mortus after a charge into a tree or rock

const HP := 500.0             # [Sir 2026-11-15]
const SPEED := 9.0            # [Sir 2026-11-15] m/s
const POUNCE_MIN := 10.0      # [Map 1 spec §4, 2026-11-20: ranges scaled to the 30 m fog] no pounce this close (it just walks in to bite)
const POUNCE_R := 15.0        # [Map 1 spec §4] a pounce starts within this, in sight
const CHARGE_S := 2.0         # [Sir 2026-11-15b] the crouch before the dash
const DIVE_SPEED := 20.0      # [Sir 2026-11-15] straight jump-dash
const DIVE_MAX := 22.0        # [design] metres: to where the player was, plus a little
const POUNCE_DAMAGE := 60.0   # [Sir 2026-11-15]
const POUNCE_COOLDOWN_S := 15.0 # [Sir 2026-11-15b]
const DIVE_HIT_R := 0.9       # [design] centre distance that counts as touching the player
const CONCUSS_S := 1.5        # [Sir]
const CONCUSS_MULT := 0.2     # [Sir] -80% Mov Spd and Atk Spd
const AGGRO_R := 35.0         # [Map 1 spec §4] detection, with line of sight
const DEAGGRO_R := 45.0       # [Map 1 spec §4] loses track past this
const WINDUP_R := 1.5         # [Sir 2026-11-15b] attack range: starts the telegraph
const WINDUP_S := 0.35        # [spec]
const ATTACK_INTERVAL := 1.0  # [Sir 2026-11-15] attack speed 1.00 per second
const DAMAGE := 30.0          # [Sir 2026-11-15]
const STRIKE_REACH := 2.0     # [design] lands if still this close at the strike (stepping back dodges)
const FRENZY_STEP := 0.2      # [Sir 2026-11-15] +20% attack speed per hit landed on the player
const FRENZY_MAX := 5         # [Sir] +100% at most
const FRENZY_RESET_S := 5.0   # [Sir] stacks clear after this long without landing a hit
const KILL_EXP := 25          # [Sir 2026-11-15]
const STRIKE_ARC := 70.0      # [design] degrees either side of facing
const VREACH := 0.4           # [design R12] vertical gap between its body and the player's capsule that melee still reaches
const MANTLE_MAX := 2.2       # [R12] the player's mantle height
const CLIMB_MAX := MANTLE_MAX + 1.5 # [R12] mantle plus a wall climb
const MANTLE_SPEED := 6.0     # [design] m/s up a mantle-able face
const CLIMB_SPEED := 3.0      # [design] m/s up a taller face
const ROAM_R := 4.0           # [design] wanders within this of its origin
const ROAM_SPEED := 1.4       # [design]
const ROAM_PAUSE_S := 2.0     # [design] stands this long between roam legs
const HEIGHT := 1.75
const RADIUS := 0.3
const EYE := 1.6
const TURN_RATE := 8.0        # rad/s [design]
const ARRIVE := 0.6
const REPLAN_S := 0.3
const GRAVITY := 22.0

static var _strike_serial := 800000

var enemy_id := ""
var state := State.IDLE_ROAM
var origin := Vector3.ZERO
var origin_yaw := 0.0
var facing := Vector3.FORWARD
var roam_target := Vector3.ZERO
var path: Array[Vector3] = []
var timer := 0.0
var replan := 0.0
var strikes := 0               # committed strikes (for tests)
var hits := 0                  # strikes that landed
var struck := false            # this cycle's strike already committed
var aggroed := false           # chasing or attacking: the player is in combat (AggroTracker)
var inert := false             # tests: no AI (a target dummy, or parked out of play)
var reserve := false           # in the pool, not in play (the director spawns it)
var pounce_ready := 0.0        # sim time the next pounce may start
var dive_dir := Vector3.ZERO
var dive_left := 0.0
var dive_hit := false
var pounces := 0               # dives started (tests)
var pounce_hits := 0           # dives that landed
var rng := RandomNumberGenerator.new()
var speed_mult := 1.0          # Scorched Slow and the like (the world sets it each tick)
var atk_mult := 1.0            # Phoenix Concuss: attack speed (the strike cycle runs this much slower)
var climbing := false          # going up a ledge face
var climb_top := 0.0           # world y it climbs to
var climb_dir := Vector3.ZERO
var climbs := 0                # ledges climbed (tests)
var dive_vel := Vector3.ZERO   # the leap's launch velocity
var dive_hops := 0.0           # ground metres left on the leap
# Per-actor values (the Sprite's; the Forest Ghoul and Kostas Mortus override them).
var kind := "sprite"
var hp_max := HP
var move_speed := SPEED
var aggro_r := AGGRO_R
var deaggro_r := DEAGGRO_R
var windup_r := WINDUP_R
var strike_reach := STRIKE_REACH
var can_climb := true          # [Sir 2026-11-15b] Sprites climb; the Ghoul and Mortus do not (they path on main's ground grid)
var attack_interval := ATTACK_INTERVAL
var damage := DAMAGE
var kill_exp := KILL_EXP
var resist := 1.0             # effects on it: duration, stat reduction and damage x this (Mortus 0.5)
var displace_immune := false  # pulls, knockback and launches do nothing (Mortus)
var frenzy := 0               # stacks of +20% attack speed (hits landed on the player)
var frenzy_hit_at := -INF
var hit_fx: Callable          # presentation: hit_fx.call(at) on a landed hit (main sets it)
var health: Node
var model: Node3D
var anim: AnimationPlayer
var hp_bar: Node3D             # billboard over the head: shown once hurt, hidden at full HP [spec P3]
var hp_fill: Sprite3D
const BAR_W := 64              # px (texture); pixel_size makes it 0.9 m wide
const BAR_Y := HEIGHT + 0.35

func setup(id: String, at: Vector3, yaw_deg: float) -> void:
	enemy_id = id
	name = id
	origin = at
	origin_yaw = yaw_deg
	collision_layer = 0b1000 # enemy
	collision_mask = 0b11    # world + player
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	col.shape = cap
	col.position.y = HEIGHT * 0.5
	add_child(col)
	health = Health.new()
	health.name = "Health"
	health.max_hp = hp_max
	health.faction = "infected"
	add_child(health)
	health.died.connect(func(_p) -> void: _die())
	health.damaged.connect(func(_p, _a) -> void: _sync_bar())
	_build_model()
	_build_bar()
	reset_to(origin, origin_yaw)

func _build_model() -> void:
	# The approved Blighted Sprite [asset swap 2026-11-24]: one skinned GLB whose
	# claw scratch, all-fours anticipation and airborne clips replace the Quaternius
	# body and the UAL stand-ins. Gameplay and collision are untouched.
	var built: Dictionary = HostileModels.build(HostileModels.SPRITE_PATH, HostileModels.SPRITE_CLIPS, self)
	model = built.model
	anim = built.anim
	_use_skins(built.skins)
	_add_eyes()

var eye_mesh: MeshInstance3D   # the glowing eyes (tests)

# Glowing eyes: two small unshaded emissive spheres on the head bone, just proud
# of the face (the body's own eyeballs sit in shaded sockets and read as dark).
func _add_eyes() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = eye_color
	mat.emission_enabled = true
	mat.emission = eye_color
	mat.emission_energy_multiplier = EYE_ENERGY
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty(): return
	var skel := found[0] as Skeleton3D
	var bone := "Head"
	if skel.find_bone(bone) < 0: bone = "head"
	var bi := skel.find_bone(bone)
	if bi < 0: return
	var att := BoneAttachment3D.new()
	att.name = "Eyes"
	att.bone_name = bone
	skel.add_child(att)
	var head_g: Transform3D = skel.global_transform * skel.get_bone_global_rest(bi)
	var k: float = model.global_transform.basis.get_scale().x
	var fwd: Vector3 = -global_transform.basis.z.normalized()
	var right: Vector3 = global_transform.basis.x.normalized()
	var ball := SphereMesh.new()
	ball.radius = EYE_R
	ball.height = EYE_R * 2.0
	ball.radial_segments = 6
	ball.rings = 3
	for side in [-1.0, 1.0]:
		var w: Vector3 = head_g.origin + (Vector3.UP * 0.095 + fwd * 0.14 + right * side * 0.03) * k # just proud of the face
		var eye := MeshInstance3D.new()
		eye.name = "EyeL" if side < 0.0 else "EyeR"
		eye.mesh = ball
		eye.material_override = mat
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.position = head_g.affine_inverse() * w
		att.add_child(eye)
		eye_mesh = eye

static var _bar_tex := {}
static func _bar_texture(c: Color) -> ImageTexture:
	if _bar_tex.has(c): return _bar_tex[c]
	var img := Image.create(BAR_W, 6, false, Image.FORMAT_RGBA8)
	img.fill(c)
	_bar_tex[c] = ImageTexture.create_from_image(img)
	return _bar_tex[c]

func _build_bar() -> void:
	hp_bar = Node3D.new()
	hp_bar.name = "HpBar"
	hp_bar.position.y = BAR_Y
	add_child(hp_bar)
	for part in [["Back", Color(0.05, 0.02, 0.06, 0.85), 0], ["Fill", Color(0.85, 0.18, 0.2), 1]]:
		var sp := Sprite3D.new()
		sp.name = part[0]
		sp.texture = _bar_texture(part[1])
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = 0.9 / BAR_W
		sp.centered = false
		sp.offset = Vector2(-BAR_W * 0.5, -3)
		sp.region_enabled = true
		sp.region_rect = Rect2(0, 0, BAR_W, 6)
		sp.shaded = false
		sp.render_priority = part[2]
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hp_bar.add_child(sp)
		if part[0] == "Fill": hp_fill = sp
	_sync_bar()

# Fill = HP fraction; the bar shows only while hurt and alive.
func _sync_bar() -> void:
	if hp_bar == null or health == null: return
	var f := clampf(health.hp / maxf(health.max_hp, 1.0), 0.0, 1.0)
	hp_fill.region_rect = Rect2(0, 0, maxf(0.001, BAR_W * f), 6)
	hp_bar.visible = not health.dead and f < 0.999

# Effect icons under the HP bar [R12]: [{id, frac}] from the world each frame.
const StatusIcons = preload("res://scripts/ui/status_icons.gd")
const Vfx = preload("res://scripts/render/vfx.gd")
var slow_fx: Node3D # Scorched Slow: a Binbun fire area at the feet while it lasts
var status_row: Node3D
var status_ids: Array = []
func set_statuses(list: Array) -> void:
	var ids := list.map(func(x): return x.id)
	if ids == status_ids: return
	status_ids = ids
	var slowed: bool = "Scorched Slow" in ids
	if slow_fx == null and slowed:
		slow_fx = Vfx.make_loop("slow")
		if slow_fx: add_child(slow_fx)
	Vfx.set_loop(slow_fx, slowed)
	status_row = StatusIcons.update_row(self, status_row, ids, BAR_Y - 0.22) # just under the HP bar
	status_row.visible = not ids.is_empty() and not health.dead

# Burn visual [R14]: a few rising embers (at most 12 alive) and a faint
# orange glow on the body (30% strength or less), only while burning. Built
# once, then switched on and off; the silhouette and HP bar stay readable.
const BURN_EMBERS := 12
const BURN_GLOW := 0.3
var embers: Node3D # Burn: Binbun flames on the body (12 ember particles without Binbun)
var burning := false
var burn_full := true # presentation: the nearest burning Sprites wear the flames; the rest glow and flicker [2026-11-14]
var _skin: BaseMaterial3D
var _skins: Array = [] # every surface material (the swapped models are multi-surface)
var _skin_emission := Color.BLACK
var _skin_energy := 0.0

# The swap's models carry one material per surface: a burn or slow glows on all of
# them, and the first surface's look is what a restore returns to.
func _use_skins(list: Array) -> void:
	_skins = list
	if _skins.is_empty(): return
	_skin = _skins[0]
	_skin_emission = _skin.emission
	_skin_energy = _skin.emission_energy_multiplier

func _set_emission(color: Color, energy: float) -> void:
	for m in (_skins if not _skins.is_empty() else ([_skin] if _skin != null else [])):
		(m as BaseMaterial3D).emission = color
		(m as BaseMaterial3D).emission_energy_multiplier = energy
func set_burning(on: bool, full := true) -> void:
	if on and burning and full != burn_full: # still burning, moved in or out of the flames' nearest set
		burn_full = full
		_show_embers(full)
		if full and _skin != null: _set_emission(_skin.emission, BURN_GLOW)
		return
	if on == burning: return
	burning = on
	burn_full = full
	_show_embers(on and full)
	if _skin != null:
		_set_emission(Color(1.0, 0.45, 0.12) if on else _skin_emission, BURN_GLOW if on else _skin_energy)

# Without flames, the glow flickers (0.15-0.3) so a far burning Sprite still reads as burning.
func burn_flicker(now: float) -> void:
	if not burning or burn_full or _skin == null: return
	_set_emission(_skin.emission, BURN_GLOW * (0.75 + 0.25 * sin(now * 13.0 + float(get_instance_id() % 97))))

func _show_embers(on: bool) -> void:
	if embers == null and on:
		embers = Vfx.make_loop("burn")
		if embers:
			embers.position.y = HEIGHT * 0.45
			add_child(embers)
		else: _build_embers()
	if embers is GPUParticles3D: (embers as GPUParticles3D).emitting = on
	elif embers != null: Vfx.set_loop(embers, on)

func _build_embers() -> void:
	var ep := GPUParticles3D.new()
	embers = ep
	ep.name = "Embers"
	ep.amount = BURN_EMBERS
	ep.lifetime = 0.9
	ep.position.y = HEIGHT * 0.55
	ep.visibility_aabb = AABB(Vector3(-0.8, -1.0, -0.8), Vector3(1.6, 2.6, 1.6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.22, 0.7, 0.22)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	ep.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1.0, 0.55, 0.15)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.1)
	m.emission_energy_multiplier = 2.0
	q.material = m
	ep.draw_pass_1 = q
	ep.emitting = false
	add_child(ep)

func bar_fraction() -> float:
	return hp_fill.region_rect.size.x / BAR_W if hp_fill else 1.0

# Presentation-only randomness (idle start phase) has its own generator so it can
# never consume draws from the global sequence gameplay code uses.
static var _anim_rng := RandomNumberGenerator.new()

# Back to its origin, alive and roaming. `origin_at` moves the origin (tests, spawns).
var dormant := false
var _ground_position := Vector3.INF
var _ground_revision := -1

func set_dormant(on: bool) -> void:
	if dormant == on: return
	dormant = on
	if anim: anim.active = not on
	if on: velocity = Vector3.ZERO

func reset_to(at: Vector3, yaw_deg: float, _heard_before := -1) -> void:
	set_dormant(false)
	_ground_position = Vector3.INF
	origin = at
	origin_yaw = yaw_deg
	position = at
	velocity = Vector3.ZERO
	facing = Vector3(-sin(deg_to_rad(yaw_deg)), 0, -cos(deg_to_rad(yaw_deg)))
	rotation = Vector3(0, deg_to_rad(yaw_deg), 0)
	rng.seed = hash(enemy_id) ^ hash(at)
	path.clear()
	strikes = 0
	hits = 0
	pounces = 0
	pounce_hits = 0
	pounce_ready = 0.0
	frenzy = 0
	frenzy_hit_at = -INF
	climbing = false
	climbs = 0
	speed_mult = 1.0
	reserve = false
	health.reset()
	_sync_bar()
	set_statuses([])
	set_burning(false)
	$Shape.disabled = false
	visible = true
	inert = false
	model.position = Vector3.ZERO
	_go(State.IDLE_ROAM)
	roam_target = position
	timer = ROAM_PAUSE_S # first leg picks a point straight away
	if anim != null:
		anim.speed_scale = 1.0
		anim.play("idle")
		anim.seek(_anim_rng.randf() * anim.current_animation_length, true) # presentation: a crowd never moves in lockstep (own RNG: never shifts the gameplay sequence)

func eye() -> Vector3:
	return global_position + Vector3(0, EYE, 0)

func _die() -> void:
	_go(State.DEAD)
	_sync_bar()
	set_statuses([])
	set_burning(false)
	path.clear()
	velocity = Vector3.ZERO
	$Shape.set_deferred("disabled", true)
	if anim != null:
		anim.speed_scale = 1.0
		anim.play("death")

func _go(next: int) -> void:
	state = next
	timer = 0.0
	replan = 0.0
	struck = false
	aggroed = next in [State.CHASE, State.WINDUP, State.STRIKE, State.CHARGE, State.DIVE, State.STUN]

static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

func distance_to_player(p: Node3D) -> float:
	return _flat(global_position).distance_to(_flat(p.global_position))

# Vertical gap between this body (feet to HEIGHT) and the player's capsule
# (feet to its current height: crouch and slide included). 0 = they overlap.
func vertical_gap(p: Node3D) -> float:
	var pf: float = p.global_position.y
	var pt: float = pf + (p.height() if p.has_method("height") else 1.8)
	var sf := global_position.y
	return maxf(0.0, maxf(pf - (sf + HEIGHT), sf - pt))

# In melee reach in 3D: across the ground within `r` and vertically within VREACH.
func in_reach(p: Node3D, r: float) -> bool:
	return distance_to_player(p) <= r and vertical_gap(p) <= VREACH

# The player's capsule axis (bottom and top sphere centres) as it is now.
static func capsule_axis(p: Node3D) -> Array:
	var h: float = p.height() if p.has_method("height") else 1.8
	var r: float = p.RADIUS if "RADIUS" in p else 0.3
	return [p.global_position + Vector3(0, r, 0), p.global_position + Vector3(0, maxf(r, h - r), 0)]

static func _axis_distance(pt: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var u := clampf((pt - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return pt.distance_to(a + ab * u)

# ctx: {player, player_health, nav, los: Callable(from, to) -> bool, concuss, ray}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	timer += delta
	if state == State.DEAD or inert or reserve: return # the death clip plays out; an inert dummy only stands
	if frenzy > 0 and now - frenzy_hit_at >= FRENZY_RESET_S: frenzy = 0 # 5 s without landing a hit
	think(delta, now, ctx)
	_move(delta, ctx)

# Attack interval with the frenzy stacks and any slow (atk_mult) applied.
func current_interval() -> float:
	return attack_interval / (1.0 + FRENZY_STEP * frenzy) / maxf(atk_mult, 0.05)

# The telegraph: 0.35 s (slowed by atk_mult), never more than half the cycle.
func windup_time() -> float:
	return minf(WINDUP_S / maxf(atk_mult, 0.05), current_interval() * 0.5)

# The decision step (a subclass replaces it); movement and animation follow in _move.
func think(delta: float, now: float, ctx: Dictionary) -> void:
	var p: CharacterBody3D = ctx.player
	var alive: bool = not ctx.player_health.dead
	var d := distance_to_player(p)
	match state:
		State.IDLE_ROAM:
			if alive and d <= aggro_r and ctx.los.call(eye(), p.eye_position()): # range and line of sight
				_go(State.CHASE)
			else:
				_roam(delta, ctx.nav)
		State.CHASE:
			if not alive or d > deaggro_r:
				_go(State.DISENGAGE)
			elif in_reach(p, windup_r):
				velocity.x = 0; velocity.z = 0
				_go(State.WINDUP)
			elif can_pounce(d, now) and ctx.los.call(eye(), p.eye_position()):
				velocity.x = 0; velocity.z = 0
				_go(State.CHARGE)
			else:
				_walk_to(p.global_position, move_speed, delta, ctx.nav)
		State.CHARGE:
			velocity.x = 0; velocity.z = 0
			_turn_toward(p.global_position, delta)
			if timer + 1e-6 >= CHARGE_S: _start_dive(p, now)
		State.DIVE:
			_dive(p, alive, delta, now, ctx)
		State.WINDUP:
			velocity.x = 0; velocity.z = 0
			_turn_toward(p.global_position, delta)
			if timer + 1e-6 >= windup_time():
				_go(State.STRIKE)
				_strike(p, ctx.player_health, now, ctx.los)
		State.STRIKE:
			velocity.x = 0; velocity.z = 0
			# Recovery: the rest of the attack cycle, then chase (or strike again).
			if timer + 1e-6 >= current_interval() - windup_time():
				if alive and in_reach(p, windup_r): _go(State.WINDUP) # still in reach: the next cycle
				else: _go(State.CHASE if alive else State.DISENGAGE)
		State.DISENGAGE:
			if alive and d <= aggro_r and _flat(global_position).distance_to(_flat(origin)) <= ARRIVE and ctx.los.call(eye(), p.eye_position()):
				_go(State.CHASE) # home again and the player is still close
			elif _walk_to(origin, move_speed, delta, ctx.nav):
				_go(State.IDLE_ROAM)

# Pounce range [Map 1 spec §4]: 10-15 m, off cooldown, not climbing.
func can_pounce(d: float, now: float) -> bool:
	return d >= POUNCE_MIN and d <= POUNCE_R and now + 1e-6 >= pounce_ready and not climbing

# The straight jump-dash: toward where the player stands now, a little past it, 22 m at most.
func _start_dive(p: CharacterBody3D, now: float) -> void:
	var to := Vector3(p.global_position.x - global_position.x, 0, p.global_position.z - global_position.z)
	dive_dir = to.normalized() if to.length() > 0.01 else facing
	facing = dive_dir
	dive_left = minf(DIVE_MAX, to.length() + 2.0)
	dive_vel = Vector3.UP * 4.0 # a low hop: it reads as a jump, the line stays straight
	dive_hit = false
	pounces += 1
	pounce_ready = now + POUNCE_COOLDOWN_S
	_strike_serial += 1 # one action id for the whole dash
	_go(State.DIVE)

func _dive(p: CharacterBody3D, alive: bool, delta: float, now: float, ctx: Dictionary) -> void:
	var spd := DIVE_SPEED * speed_mult
	var step := spd * delta
	if timer <= delta + 1e-6: velocity.y = dive_vel.y
	if dive_left > 0.0:
		velocity.x = dive_dir.x * spd
		velocity.z = dive_dir.z * spd
		dive_left -= step
	else:
		velocity.x = 0; velocity.z = 0
	var ax := capsule_axis(p)
	var centre := global_position + Vector3(0, HEIGHT * 0.5, 0)
	if not dive_hit and alive and _axis_distance(centre, ax[0], ax[1]) <= DIVE_HIT_R + step:
		dive_hit = true
		var r: String = ctx.player_health.apply(DamagePacket.new(_strike_serial, enemy_id, "infected", POUNCE_DAMAGE, "bite"), now)
		if r == "applied" or r == "lethal":
			pounce_hits += 1
			if ctx.has("concuss"): ctx.concuss.call(now + CONCUSS_S, CONCUSS_MULT)
			if hit_fx.is_valid(): hit_fx.call(p.global_position + Vector3(0, 1.0, 0))
		dive_left = 0.0
	var landed := is_on_floor() and timer > 0.1 and velocity.y <= 0.0
	var blocked := get_slide_collision_count() > 0 and timer > delta * 1.5 and is_on_wall() # a tree or rock stops it
	if (dive_left <= 0.0 and landed) or blocked or timer > 3.0:
		velocity.x = 0; velocity.z = 0
		_go(State.CHASE if alive else State.DISENGAGE)

# Movement, gravity, climbing and animation after the decision.
func _move(delta: float, ctx: Dictionary) -> void:
	if climbing:
		velocity = climb_dir * 0.6 + Vector3.UP * (MANTLE_SPEED if climb_top - global_position.y <= MANTLE_MAX else CLIMB_SPEED)
	elif not is_on_floor() or state == State.DIVE: velocity.y -= GRAVITY * delta
	else: velocity.y = 0.0
	var want := Vector3(velocity.x, 0, velocity.z) # sliding along a wall eats this; climbing needs it
	# Static support can be reused only while neither this body nor the world changed.
	if not is_on_floor() or not velocity.is_zero_approx() or global_position != _ground_position or ctx.nav.revision != _ground_revision:
		move_and_slide()
		_ground_position = global_position
		_ground_revision = ctx.nav.revision
	if climbing:
		if global_position.y >= climb_top + 0.02:
			climbing = false # over the lip: step on
			climbs += 1
			global_position += climb_dir * 0.4
			velocity = Vector3.ZERO
	elif can_climb and state != State.DIVE and is_on_wall() and want.length() > 0.1 and ctx.has("ray"):
		_try_climb(ctx.ray, want)
	rotation.y = atan2(-facing.x, -facing.z)
	_animate()

func _roam(delta: float, nav: RefCounted) -> void:
	if _flat(global_position).distance_to(_flat(roam_target)) <= ARRIVE:
		velocity.x = 0; velocity.z = 0
		if timer >= ROAM_PAUSE_S:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * ROAM_R
			roam_target = origin + Vector3(cos(a) * r, 0, sin(a) * r)
			timer = 0.0
			path.clear()
		return
	if _walk_to(roam_target, ROAM_SPEED, delta, nav): timer = 0.0

# One strike at the end of the telegraph: lands only if the player is still in
# reach, in front and not behind a wall. Each strike has its own damage id.
func _strike(p: CharacterBody3D, ph: Node, now: float, los: Callable) -> void:
	strikes += 1
	var to := p.global_position - global_position
	to.y = 0.0
	if not in_reach(p, strike_reach): return # 3D: a player above (or below) its body is out of reach
	if to.length() > 0.05 and rad_to_deg(facing.angle_to(to.normalized())) > STRIKE_ARC: return
	if not los.call(eye(), p.eye_position()): return
	_strike_serial += 1
	var r: String = ph.apply(DamagePacket.new(_strike_serial, enemy_id, "infected", damage, "bite"), now)
	if r == "applied" or r == "lethal":
		hits += 1
		frenzy = mini(FRENZY_MAX, frenzy + 1) # +20% attack speed per hit landed, 5 stacks at most
		frenzy_hit_at = now
		if hit_fx.is_valid(): hit_fx.call(p.global_position + Vector3(0, 1.0, 0))

# Follows the grid path toward goal; true once within ARRIVE (or unreachable).
func _walk_to(goal: Vector3, speed: float, delta: float, nav: RefCounted) -> bool:
	if _flat(global_position).distance_to(_flat(goal)) <= ARRIVE:
		velocity.x = 0; velocity.z = 0
		return true
	replan -= delta
	if path.is_empty() or replan <= 0.0:
		var r: Dictionary = nav.find_path(global_position, goal)
		path.clear()
		if r.ok: path.assign(r.path)
		replan = REPLAN_S
		if not r.ok:
			velocity.x = 0; velocity.z = 0
			return true # unreachable: count it as arrived (roam picks again, disengage settles)
	while not path.is_empty() and _flat(global_position).distance_to(_flat(path[0])) < 0.15:
		path.pop_front()
	if path.is_empty(): return false
	var dir := Vector3(path[0].x - global_position.x, 0, path[0].z - global_position.z).normalized()
	_turn_toward(global_position + dir, delta)
	velocity.x = dir.x * speed * speed_mult
	velocity.z = dir.z * speed * speed_mult
	return false

# Blocked while walking: if the face ahead tops out within CLIMB_MAX of its
# feet, climb it (the player's mantle and wall-climb heights) [R12].
func _try_climb(ray: Callable, want: Vector3) -> void:
	var dir := want.normalized()
	var feet := global_position.y
	var probe := global_position + dir * (RADIUS + 0.35)
	var hit: Dictionary = ray.call(probe + Vector3(0, CLIMB_MAX + 0.3, 0), probe + Vector3(0, 0.05, 0))
	if hit.is_empty(): return
	var top: float = hit.position.y
	if top - feet < 0.35 or top - feet > CLIMB_MAX: return
	climbing = true
	climb_top = top
	climb_dir = dir

func _turn_toward(point: Vector3, delta: float) -> void:
	var to := Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	if to.length() < 0.01: return
	var want := to.normalized()
	var ang := facing.signed_angle_to(want, Vector3.UP)
	facing = facing.rotated(Vector3.UP, clampf(ang, -TURN_RATE * delta, TURN_RATE * delta)).normalized()

# Hurt by the player: give chase (unless dead or already fighting). A hit from
# past the de-aggro radius still turns it around; it gives up at 24 m as usual.
func alert_to(_pos: Vector3) -> void:
	if state in [State.DEAD, State.CHASE, State.WINDUP, State.STRIKE, State.CHARGE, State.DIVE, State.STUN]: return
	_go(State.CHASE)

const WALK_CLIP_SPEED := 1.4
const RUN_CLIP_SPEED := 6.5   # Sprint clip's ground speed at 1x [design, tuned by eye]
const ZOMBIE_WALK_CLIP_SPEED := 1.1 # Zombie_Walk_Fwd at 1x [design]
const STRIKE_AT := 0.35 # seconds into Punch_Jab where the arm is extended
func _animate() -> void:
	if anim == null: return
	var speed := Vector2(velocity.x, velocity.z).length()
	var want := "idle"
	var scale := 1.0
	if state == State.CHARGE:
		want = "pounce_start" # NinjaJump_Start before the dash
	elif state == State.DIVE:
		want = "air"
	elif state in [State.WINDUP, State.STRIKE]:
		want = "strike"
		scale = STRIKE_AT / maxf(windup_time(), 0.05)
	elif climbing:
		want = "climb"
	elif speed > 0.1:
		want = "run" if speed > 3.0 else "walk"
		scale = speed / (RUN_CLIP_SPEED if want == "run" else ZOMBIE_WALK_CLIP_SPEED)
	if anim.current_animation != want:
		anim.play(want, 0.2)
	anim.speed_scale = clampf(scale, 0.3, 3.0)

func state_name() -> String:
	return State.keys()[state]
