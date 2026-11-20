extends "res://scripts/actors/blighted_sprite.gd"
# Forest Ghoul [Common] [Sir, 2026-11-15; docs/plan-dark-forest-roster.md]:
#   ranged; 250 HP, 70 damage an arrow, attack speed 1.5/s, 5 m/s, detection
#   50 m with line of sight, range 30 m, arrows 10 m/s (enemy_arrows.gd).
#   [Sir 2026-11-15b] renamed from Forest Ranger; gives up past 100 m; cannot climb.
#   Keeps 15-30 m from the player and backs off inside 10 m.
#   Burst: on its first attack, then every 20 s: attack speed +100% and its
#   next 3 shots are homing arrows of 35 damage (5 -> 20 m/s as they close).
# Model: the Quaternius base body in a ghoul's outfit, with a bow built in code
# (no bow mesh is installed). UAL1/UAL2 have no bow clips, so the aim pose is
# Pistol_Aim_Neutral and the release Pistol_Shoot (checked 2026-11-15).

const BodyModelR = preload("res://scripts/actors/body_model.gd")
const OutfitBuilderR = preload("res://scripts/actors/outfit_builder.gd")
const GHOUL := {"hp": 250.0, "damage": 70.0, "attack_speed": 1.5, "speed": 5.0, "detect": 50.0, "range": 30.0, "deaggro": 100.0,
	"keep_min": 15.0, "back_off": 10.0, "burst_every": 20.0, "burst_arrows": 3, "burst_damage": 35.0, "burst_speed_mult": 2.0, "kill_exp": 35}
const GHOUL_SKIN := Color(0.78, 0.6, 0.45)

var arrows: RefCounted          # EnemyArrows (main sets it)
var next_shot := 0.0            # sim time the next arrow may leave
var burst_ready := 0.0          # the first attack is a Burst [Sir]
var burst_left := 0             # homing arrows left in the running Burst
var shots := 0                  # arrows loosed (tests)
var bursts := 0                 # Bursts started (tests)
var aiming := false             # presentation: the bow is up
var shot_at := -INF             # presentation: the release clip

func _init() -> void:
	kind = "ghoul"
	eye_color = Color(0.75, 0.88, 1.0) # pale
	hp_max = GHOUL.hp
	move_speed = GHOUL.speed
	aggro_r = GHOUL.detect
	deaggro_r = GHOUL.deaggro
	can_climb = false
	damage = GHOUL.damage
	attack_interval = 1.0 / GHOUL.attack_speed
	windup_r = 0.0 # never melee
	kill_exp = GHOUL.kill_exp

func _build_model() -> void:
	var outfit := {"polo": OutfitBuilderR.fabric(Color(0.2, 0.32, 0.18), Color(0.12, 0.1, 0.06), 0.0, 3),
		"trousers": OutfitBuilderR.fabric(Color(0.3, 0.22, 0.14), Color(0.15, 0.1, 0.06), 0.0, 4),
		"shoes": OutfitBuilderR.fabric(Color(0.18, 0.12, 0.08), Color(0.08, 0.06, 0.04), 0.0, 5)}
	var built: Dictionary = BodyModelR.build(self, false, GHOUL_SKIN, outfit)
	model = built.model
	anim = built.anim # the shared UAL library: idle, walk, jog, death, climb, aim, shoot
	var body := OutfitBuilderR.body_mesh(model)
	_skin = body.get_surface_override_material(0) as BaseMaterial3D
	if _skin:
		_skin_emission = _skin.emission
		_skin_energy = _skin.emission_energy_multiplier
	_attach_bow()
	_add_eyes()

# A longbow in the left hand: two curved limbs and a string, built in code.
func _attach_bow() -> void:
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if skel == null or skel.find_bone("hand_l") < 0: return
	var att := BoneAttachment3D.new()
	att.name = "BowHand"
	att.bone_name = "hand_l"
	skel.add_child(att)
	var bow := Node3D.new()
	bow.name = "Bow"
	att.add_child(bow)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.22, 0.1)
	wood.roughness = 0.8
	for side in [-1.0, 1.0]: # upper and lower limbs, bent back at the tips
		for k in 3:
			var seg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.012 - k * 0.002
			cyl.bottom_radius = 0.016 - k * 0.002
			cyl.height = 0.24
			seg.mesh = cyl
			seg.material_override = wood
			var y: float = side * (0.12 + k * 0.22)
			seg.position = Vector3(0, y, -0.03 * k * k * 0.5)
			seg.rotation.x = side * 0.18 * k
			bow.add_child(seg)
	var string := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.002
	sc.bottom_radius = 0.002
	sc.height = 1.28
	string.mesh = sc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.85, 0.82, 0.7)
	string.material_override = sm
	string.position = Vector3(0, 0, -0.1)
	bow.add_child(string)
	bow.rotation = Vector3(0, 0, PI * 0.5)

func reset_to(at: Vector3, yaw_deg: float, heard := -1) -> void:
	super.reset_to(at, yaw_deg, heard)
	next_shot = 0.0
	burst_ready = 0.0
	burst_left = 0
	shots = 0
	bursts = 0
	aiming = false

# Never pounces.
func can_pounce(_d: float, _now: float) -> bool:
	return false

func think(delta: float, now: float, ctx: Dictionary) -> void:
	var p: CharacterBody3D = ctx.player
	var alive: bool = not ctx.player_health.dead
	var d := distance_to_player(p)
	aiming = false
	_clock = now
	match state:
		State.IDLE_ROAM:
			if alive and d <= aggro_r and ctx.los.call(eye(), p.eye_position()):
				_go(State.CHASE)
				next_shot = maxf(next_shot, now + 0.4) # draws the bow first
			else:
				_roam(delta, ctx.nav)
		State.CHASE:
			if not alive or d > deaggro_r:
				_go(State.DISENGAGE)
				return
			var sees: bool = ctx.los.call(eye(), p.eye_position())
			if d < float(GHOUL.back_off):
				_back_off(p, delta, ctx.nav) # too close: give ground
			elif d > float(GHOUL.range) or not sees:
				_walk_to(p.global_position, move_speed, delta, ctx.nav) # out of range or out of sight: close in
			else:
				velocity.x = 0; velocity.z = 0
				_turn_toward(p.global_position, delta)
				aiming = true
				if now + 1e-6 >= next_shot: _shoot(p, now)
		_:
			super.think(delta, now, ctx)

# Away from the player, keeping 15-30 m.
func _back_off(p: CharacterBody3D, delta: float, nav: RefCounted) -> void:
	var away := Vector3(global_position.x - p.global_position.x, 0, global_position.z - p.global_position.z)
	away = away.normalized() if away.length() > 0.01 else -facing
	var goal: Vector3 = global_position + away * (float(GHOUL.keep_min) - distance_to_player(p) + 2.0)
	_walk_to(goal, move_speed, delta, nav)
	_turn_toward(p.global_position, delta) # it keeps its eyes on the player while it backs off

func _shoot(p: CharacterBody3D, now: float) -> void:
	_clock = now
	if arrows == null: return
	var from := global_position + Vector3(0, 1.45, 0) + facing * 0.5
	var aim := p.global_position + Vector3(0, 1.1, 0)
	var homing := false
	var dmg := damage
	if burst_left <= 0 and now + 1e-6 >= burst_ready: # first attack, then every 20 s
		burst_left = int(GHOUL.burst_arrows)
		burst_ready = now + float(GHOUL.burst_every)
		bursts += 1
	if burst_left > 0:
		homing = true
		dmg = float(GHOUL.burst_damage)
		burst_left -= 1
	arrows.fire(from, aim, dmg, homing, enemy_id, now)
	shots += 1
	shot_at = now
	var iv := current_interval() / (float(GHOUL.burst_speed_mult) if homing else 1.0)
	next_shot = now + iv

var _clock := 0.0
func now_shot() -> bool:
	return _clock - shot_at < 0.25

func _animate() -> void:
	if anim == null: return
	var speed := Vector2(velocity.x, velocity.z).length()
	var want := "idle"
	var sc := 1.0
	if state == State.DEAD:
		want = "death"
	elif aiming:
		want = "shoot" if now_shot() else "aim"
	elif climbing:
		want = "climb"
	elif speed > 0.1:
		want = "jog" if speed > 3.0 else "walk"
		sc = speed / (4.0 if want == "jog" else 1.4)
	if anim.current_animation != want and anim.has_animation(want): anim.play(want, 0.2)
	anim.speed_scale = clampf(sc, 0.3, 3.0)
