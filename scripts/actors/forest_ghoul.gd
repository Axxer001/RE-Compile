extends "res://scripts/actors/blighted_sprite.gd"
# Forest Ghoul [Common] [Sir, 2026-11-15; docs/plan-dark-forest-roster.md]:
#   ranged; 250 HP, 70 damage an arrow, attack speed 1.5/s, 5 m/s, detection
#   35 m with line of sight, range 22 m, arrows 10 m/s (enemy_arrows.gd).
#   [Sir 2026-11-15b] renamed from Forest Ranger; gives up past 100 m; cannot climb.
#   Keeps 12-22 m from the player and backs off inside 10 m.
#   Burst: on its first attack, then every 20 s: attack speed +100% and its
#   next 3 shots are homing arrows of 35 damage (5 -> 20 m/s as they close).
# Model: the approved Ashveil Retro archer [asset swap 2026-11-24]: one skinned
# GLB with its own bow, quiver, 29-bone rig and bow clips, replacing the Quaternius
# body and the longbow that used to be built in code. The right hand holds the Bow
# bone, the left pulls the Nock and the shaft points down local +Z; EnemyArrows
# still fires exactly one gameplay projectile per release (unchanged).

const HostileModelsR = preload("res://scripts/actors/hostile_models.gd")
const GHOUL := {"hp": 250.0, "damage": 70.0, "attack_speed": 1.5, "speed": 5.0, "detect": 35.0, "range": 22.0, "deaggro": 45.0, # [Map 1 spec §4: scaled to the 30 m fog]
	"keep_min": 12.0, "back_off": 10.0, "burst_every": 20.0, "burst_arrows": 3, "burst_damage": 35.0, 	"burst_speed_mult": 2.0, "kill_exp": 35}


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
	var built: Dictionary = HostileModelsR.build(HostileModelsR.GHOUL_PATH, HostileModelsR.GHOUL_CLIPS, self)
	model = built.model
	anim = built.anim
	_use_skins(built.skins)
	_add_eyes()

# The longbow, its limbs and its string are part of the approved model: nothing is
# built in code any more (the old _attach_bow is gone with the body it hung on).

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

# Away from the player, keeping 12-22 m.
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
