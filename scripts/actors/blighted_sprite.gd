extends CharacterBody3D
# Blighted Sprite, the MVP hostile (Tech Spec §4, plan P3). Built from the
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
const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")
const BODY := "res://assets/quaternius/base_characters/Superhero_Male_FullBody.gltf"
const ANIMS := "res://assets/quaternius/animations/UAL1_Standard.glb"
const BodyModel = preload("res://scripts/actors/body_model.gd")
const SKIN_TINT := Color(0.32, 0.22, 0.42) # blighted violet

enum State { IDLE_ROAM, CHASE, WINDUP, STRIKE, DISENGAGE, DEAD, CHARGE, DIVE }

const HP := 120.0             # [spec]
const SPEED := 8.0            # [Sir R8] fixed (not the player's Mov Spd); the spec had 5.5
const POUNCE_R := 20.0        # [Sir R12] starts a pounce at or inside this (was 10)
const CHARGE_S := 0.5         # [Sir] stands still, telegraphing
const DIVE_SPEED := 18.0      # [proposed]
const DIVE_MAX := 25.0        # [proposed R12] metres across the ground (was 12)
const POUNCE_DAMAGE := 20.0   # [Sir]
const POUNCE_COOLDOWN_S := 6.0 # [proposed] per Sprite, from the dive's start
const DIVE_HIT_R := 0.9       # [design] centre distance that counts as touching the player
const CONCUSS_S := 1.5        # [proposed]
const CONCUSS_MULT := 0.2     # [Sir] -80% Mov Spd and Atk Spd
const AGGRO_R := 16.0         # [spec]
const DEAGGRO_R := 24.0       # [spec]
const WINDUP_R := 1.8         # [spec] starts the telegraph
const WINDUP_S := 0.35        # [spec]
const ATTACK_INTERVAL := 1.2  # [spec] windup + recovery: one hit per 1.2 s in contact
const DAMAGE := 12.0          # [spec]
const STRIKE_REACH := 2.2     # [design] lands if still this close at the strike (stepping back dodges)
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
var climbing := false          # going up a ledge face
var climb_top := 0.0           # world y it climbs to
var climb_dir := Vector3.ZERO
var climbs := 0                # ledges climbed (tests)
var dive_vel := Vector3.ZERO   # the leap's launch velocity
var dive_hops := 0.0           # ground metres left on the leap
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
	health.max_hp = HP
	health.faction = "infected"
	add_child(health)
	health.died.connect(func(_p) -> void: _die())
	health.damaged.connect(func(_p, _a) -> void: _sync_bar())
	_build_model()
	_build_bar()
	reset_to(origin, origin_yaw)

func _build_model() -> void:
	# The Quaternius base body (CC0), bare and tinted: a blighted forest creature.
	model = (load(BODY) as PackedScene).instantiate()
	model.name = "Model"
	model.rotation.y = PI # Quaternius bodies face +Z; this body faces -Z
	add_child(model)
	var body := OutfitBuilder.body_mesh(model)
	var skin: BaseMaterial3D = body.mesh.surface_get_material(0).duplicate()
	skin.albedo_color = SKIN_TINT
	skin.emission_enabled = true
	skin.emission = Color(0.35, 0.1, 0.45)
	skin.emission_energy_multiplier = 0.25
	body.set_surface_override_material(0, skin)
	_skin = skin
	_skin_emission = skin.emission
	_skin_energy = skin.emission_energy_multiplier
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", _library())

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
	if status_row == null:
		status_row = Node3D.new()
		status_row.name = "StatusRow"
		status_row.position.y = BAR_Y - 0.17 # just under the HP bar
		add_child(status_row)
	for ch in status_row.get_children():
		status_row.remove_child(ch)
		ch.queue_free()
	for i in ids.size():
		var def := StatusIcons.icon(ids[i])
		var tx := StatusIcons.texture(ids[i])
		var x := (i - (ids.size() - 1) * 0.5) * 0.2 # 0.18 m icons, side by side
		if tx:
			var sp := Sprite3D.new()
			sp.texture = tx
			sp.pixel_size = 0.18 / float(tx.get_width())
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.shaded = false
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sp.offset = Vector2(x / sp.pixel_size, 0)
			sp.set_meta("status", ids[i])
			status_row.add_child(sp)
			continue
		var l := Label3D.new()
		l.text = def.glyph
		l.modulate = def.color
		l.outline_modulate = Color(0, 0, 0)
		l.outline_size = 6
		l.font_size = 40
		l.pixel_size = 0.004
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = false
		l.offset = Vector2(x / l.pixel_size, 0)
		l.set_meta("status", ids[i])
		status_row.add_child(l)
	status_row.visible = not ids.is_empty() and not health.dead

# Burn visual [R14]: a few rising embers (at most 12 alive) and a faint
# orange glow on the body (30% strength or less), only while burning. Built
# once, then switched on and off; the silhouette and HP bar stay readable.
const BURN_EMBERS := 12
const BURN_GLOW := 0.3
var embers: Node3D # Burn: Binbun flames on the body (12 ember particles without Binbun)
var burning := false
var _skin: BaseMaterial3D
var _skin_emission := Color.BLACK
var _skin_energy := 0.0
func set_burning(on: bool) -> void:
	if on == burning: return
	burning = on
	if embers == null and on:
		embers = Vfx.make_loop("burn")
		if embers:
			embers.position.y = HEIGHT * 0.45
			add_child(embers)
		else: _build_embers()
	if embers is GPUParticles3D: (embers as GPUParticles3D).emitting = on
	elif embers != null: Vfx.set_loop(embers, on)
	if _skin != null:
		_skin.emission = Color(1.0, 0.45, 0.12) if on else _skin_emission
		_skin.emission_energy_multiplier = BURN_GLOW if on else _skin_energy

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

static var _lib: AnimationLibrary
# Presentation-only randomness (idle start phase) has its own generator so it can
# never consume draws from the global sequence gameplay code uses.
static var _anim_rng := RandomNumberGenerator.new()
# Movement clips [Sir: rig + movement animation; attacks later]. Built from the
# shared UAL1+UAL2 library (BodyModel.library): roam = zombie idle/shamble,
# chase = sprint, pounce charge = crouch, dive = airborne, climb = ClimbUp.
# "strike" stays Punch_Jab until attack animations are done.
const SPRITE_CLIPS := {"idle": "zombie_idle", "walk": "zombie_walk", "run": "run", "strike": "bite",
	"death": "death", "charge": "crouch", "air": "jump_air", "climb": "climb", "land": "land"}
static func _library() -> AnimationLibrary:
	if _lib != null: return _lib
	_lib = AnimationLibrary.new()
	var shared: AnimationLibrary = BodyModel.library()
	for key in SPRITE_CLIPS:
		var src: String = SPRITE_CLIPS[key]
		if not shared.has_animation(src): src = "walk" if key in ["idle", "walk"] else "idle"
		var a: Animation = shared.get_animation(src).duplicate()
		if key == "climb": a.loop_mode = Animation.LOOP_LINEAR # held while scaling a face
		_lib.add_animation(key, a)
	return _lib

# Back to its origin, alive and roaming. `origin_at` moves the origin (tests, spawns).
func reset_to(at: Vector3, yaw_deg: float, _heard_before := -1) -> void:
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
	aggroed = next in [State.CHASE, State.WINDUP, State.STRIKE, State.CHARGE, State.DIVE]

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

# ctx: {player, player_health, nav, los: Callable(from, to) -> bool}
func tick(delta: float, now: float, ctx: Dictionary) -> void:
	timer += delta
	if state == State.DEAD or inert or reserve: return # the death clip plays out; an inert dummy only stands
	var p: CharacterBody3D = ctx.player
	var alive: bool = not ctx.player_health.dead
	var d := distance_to_player(p)
	match state:
		State.IDLE_ROAM:
			if alive and d <= AGGRO_R and ctx.los.call(eye(), p.eye_position()): # [spec] range and line of sight
				_go(State.CHASE)
			else:
				_roam(delta, ctx.nav)
		State.CHASE:
			if not alive:
				_go(State.DISENGAGE)
			elif d > DEAGGRO_R:
				_go(State.DISENGAGE)
			elif in_reach(p, WINDUP_R):
				velocity.x = 0; velocity.z = 0
				_go(State.WINDUP)
			elif d <= POUNCE_R and d > WINDUP_R * 0.5 and now + 1e-6 >= pounce_ready and not climbing and ctx.los.call(eye(), p.eye_position()):
				velocity.x = 0; velocity.z = 0
				_go(State.CHARGE)
			else:
				_walk_to(p.global_position, SPEED, delta, ctx.nav)
		State.CHARGE:
			velocity.x = 0; velocity.z = 0
			_turn_toward(p.global_position, delta)
			if timer + 1e-6 >= CHARGE_S:
				# A ballistic leap at the player's centre as it is now (3D: high ground and mid-air too).
				var ax := capsule_axis(p)
				var aim: Vector3 = (ax[0] + ax[1]) * 0.5
				var from := global_position + Vector3(0, HEIGHT * 0.5, 0)
				var to := Vector3(aim.x - from.x, 0, aim.z - from.z)
				dive_dir = to.normalized() if to.length() > 0.01 else facing
				var ground := minf(DIVE_MAX, to.length())
				var t_fly := maxf(ground, 0.5) / DIVE_SPEED
				var rise := aim.y - from.y if to.length() <= DIVE_MAX else 0.0
				dive_vel = dive_dir * DIVE_SPEED + Vector3.UP * ((rise + 0.5 * GRAVITY * t_fly * t_fly) / t_fly)
				dive_left = ground + 0.5 # a little past the aim point, at most 25 m
				dive_hit = false
				pounces += 1
				pounce_ready = now + POUNCE_COOLDOWN_S
				_strike_serial += 1 # one action id for the whole dive
				_go(State.DIVE)
		State.DIVE:
			var spd := DIVE_SPEED * speed_mult
			var step := spd * delta
			if timer <= delta + 1e-6: velocity.y = dive_vel.y # the leap's launch
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
				dive_left = 0.0
			var landed := is_on_floor() and timer > 0.1 and velocity.y <= 0.0
			if (dive_left <= 0.0 and landed) or (landed and dive_hit) or timer > 3.0 or (get_slide_collision_count() > 0 and timer > delta * 1.5 and is_on_wall()):
				velocity.x = 0; velocity.z = 0
				_go(State.CHASE if alive else State.DISENGAGE)
		State.WINDUP:
			velocity.x = 0; velocity.z = 0
			_turn_toward(p.global_position, delta)
			if timer + 1e-6 >= WINDUP_S:
				_go(State.STRIKE)
				_strike(p, ctx.player_health, now, ctx.los)
		State.STRIKE:
			velocity.x = 0; velocity.z = 0
			# Recovery: the rest of the 1.2 s cycle, then chase (or strike again).
			if timer + 1e-6 >= ATTACK_INTERVAL - WINDUP_S:
				if alive and in_reach(p, WINDUP_R): _go(State.WINDUP) # still in contact: the next 1.2 s cycle
				else: _go(State.CHASE if alive else State.DISENGAGE)
		State.DISENGAGE:
			if alive and d <= AGGRO_R and _flat(global_position).distance_to(_flat(origin)) <= ARRIVE and ctx.los.call(eye(), p.eye_position()):
				_go(State.CHASE) # home again and the player is still close
			elif _walk_to(origin, SPEED, delta, ctx.nav):
				_go(State.IDLE_ROAM)
	if climbing:
		velocity = climb_dir * 0.6 + Vector3.UP * (MANTLE_SPEED if climb_top - global_position.y <= MANTLE_MAX else CLIMB_SPEED)
	elif state == State.DIVE: velocity.y -= GRAVITY * delta
	elif not is_on_floor(): velocity.y -= GRAVITY * delta
	else: velocity.y = 0.0
	var want := Vector3(velocity.x, 0, velocity.z) # sliding along a wall eats this; climbing needs it
	move_and_slide()
	if climbing:
		if global_position.y >= climb_top + 0.02:
			climbing = false # over the lip: step on
			climbs += 1
			global_position += climb_dir * 0.4
			velocity = Vector3.ZERO
	elif state != State.DIVE and is_on_wall() and want.length() > 0.1 and ctx.has("ray"):
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
	if not in_reach(p, STRIKE_REACH): return # 3D: a player above (or below) its body is out of reach
	if to.length() > 0.05 and rad_to_deg(facing.angle_to(to.normalized())) > STRIKE_ARC: return
	if not los.call(eye(), p.eye_position()): return
	_strike_serial += 1
	var r: String = ph.apply(DamagePacket.new(_strike_serial, enemy_id, "infected", DAMAGE, "bite"), now)
	if r == "applied" or r == "lethal": hits += 1

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
	if state in [State.DEAD, State.CHASE, State.WINDUP, State.STRIKE, State.CHARGE, State.DIVE]: return
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
		want = "charge" # crouched wind-up before the pounce
	elif state == State.DIVE:
		want = "air"
	elif state in [State.WINDUP, State.STRIKE]:
		want = "strike"
		scale = STRIKE_AT / WINDUP_S
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
