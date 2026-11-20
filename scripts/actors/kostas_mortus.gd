extends "res://scripts/actors/blighted_sprite.gd"
# Kostas Mortus [Elite] [Sir, 2026-11-15; docs/plan-dark-forest-roster.md]:
#   melee; 3000 HP, 80 damage, attack speed 0.5/s, 3 m/s, detection 30 m with
#   line of sight, attack range 1.5 m [Sir 2026-11-15b]; normal melee between charges. Takes 50%
#   less damage from the front.
#   Charge: with the player 15-30 m away (in sight, off its 15 s cooldown) it
#   winds up 1.5 s, then charges at 20 m/s in a straight line toward where it
#   saw the player, up to 30 m or until it hits them: 100 damage, knocked back
#   10 m, Concussed 3 s. A tree or rock stops the charge and stuns it 1.5 s.
#   Every debuff and effect on it is halved (duration, stat reduction, damage)
#   and it ignores pulls, knockback and launches (resist / displace_immune).
#   One per clearing that holds a page, guarding it.
# Model: the Sprite's body x1.6, darker emissive skin, DarkMagicFX void aura.
# Anim: Walk slowed, Crouch_Idle for the wind-up, Sprint for the charge.

const MORTUS := {"hp": 3000.0, "damage": 80.0, "attack_speed": 0.5, "speed": 3.0, "detect": 30.0, "range": 1.5, "deaggro": 50.0,
	"charge_min": 15.0, "charge_max": 30.0, "windup_s": 1.5, "charge_speed": 20.0, "charge_len": 30.0,
	"charge_damage": 100.0, "knockback": 10.0, "concuss_s": 3.0, "stun_s": 1.5, "charge_cd": 15.0,
	"front_mult": 0.5, "front_deg": 90.0, "resist": 0.5, "kill_exp": 200, "scale": 1.6}
const MORTUS_SKIN := Color(0.16, 0.1, 0.2)

var charge_ready := 0.0         # sim time the next charge may start
var charge_dir := Vector3.ZERO
var charge_left := 0.0
var charges := 0                # charges started (tests)
var charge_hits := 0            # charges that hit the player
var stuns := 0                  # charges stopped by a tree or rock
var knock_player: Callable      # (dir, metres): main pushes the player back
var _player_pos := Vector3.ZERO # the player as last seen (front check)

func _init() -> void:
	kind = "mortus"
	eye_color = Color(1.0, 0.25, 0.15) # ember red
	hp_max = MORTUS.hp
	move_speed = MORTUS.speed
	aggro_r = MORTUS.detect
	deaggro_r = MORTUS.deaggro # [Sir 2026-11-15b]
	can_climb = false # [Sir 2026-11-15b]
	windup_r = MORTUS.range
	strike_reach = MORTUS.range + 0.5
	damage = MORTUS.damage
	attack_interval = 1.0 / MORTUS.attack_speed
	kill_exp = MORTUS.kill_exp
	resist = MORTUS.resist
	displace_immune = true

func setup(id: String, at: Vector3, yaw_deg: float) -> void:
	super.setup(id, at, yaw_deg)
	health.incoming_mult = front_mult
	var col: CollisionShape3D = $Shape
	var cap: CapsuleShape3D = (col.shape as CapsuleShape3D).duplicate()
	cap.radius = RADIUS * 1.6
	cap.height = HEIGHT * 1.6
	col.shape = cap
	col.position.y = cap.height * 0.5
	hp_bar.position.y = HEIGHT * 1.6 + 0.35

func _build_model() -> void:
	super._build_model()
	model.scale = Vector3.ONE * float(MORTUS.scale)
	if _skin:
		_skin.albedo_color = Look.palette_tint(MORTUS_SKIN, 0.3)
		_skin.emission = Color(0.4, 0.05, 0.5)
		_skin.emission_energy_multiplier = 0.6
		_skin_emission = _skin.emission
		_skin_energy = _skin.emission_energy_multiplier
	var aura: Node3D = Vfx.make_loop("addiction") # DarkMagicFX void aura, purple
	if aura:
		aura.name = "VoidAura"
		aura.scale *= 1.4
		add_child(aura)
		Vfx.set_loop(aura, true)

# 50% less damage from the front: the attacker (the player) inside its front 180 degrees.
func front_mult(_packet: RefCounted) -> float:
	var to := Vector3(_player_pos.x - global_position.x, 0, _player_pos.z - global_position.z)
	if to.length() < 0.05: return float(MORTUS.front_mult)
	return float(MORTUS.front_mult) if rad_to_deg(facing.angle_to(to.normalized())) <= float(MORTUS.front_deg) else 1.0

func reset_to(at: Vector3, yaw_deg: float, heard := -1) -> void:
	super.reset_to(at, yaw_deg, heard)
	charge_ready = 0.0
	charge_left = 0.0
	charges = 0
	charge_hits = 0
	stuns = 0

func can_pounce(_d: float, _now: float) -> bool:
	return false # the charge replaces the Sprite's pounce

func think(delta: float, now: float, ctx: Dictionary) -> void:
	var p: CharacterBody3D = ctx.player
	_player_pos = p.global_position
	var alive: bool = not ctx.player_health.dead
	var d := distance_to_player(p)
	match state:
		State.CHASE:
			if alive and d >= float(MORTUS.charge_min) and d <= float(MORTUS.charge_max) and now + 1e-6 >= charge_ready and ctx.los.call(eye(), p.eye_position()):
				velocity.x = 0; velocity.z = 0
				_go(State.CHARGE) # the 1.5 s wind-up
				return
			super.think(delta, now, ctx)
		State.CHARGE:
			velocity.x = 0; velocity.z = 0
			_turn_toward(p.global_position, delta)
			if timer + 1e-6 >= float(MORTUS.windup_s):
				var to := Vector3(p.global_position.x - global_position.x, 0, p.global_position.z - global_position.z)
				charge_dir = to.normalized() if to.length() > 0.01 else facing # where it saw the player
				facing = charge_dir
				charge_left = float(MORTUS.charge_len)
				charges += 1
				charge_ready = now + float(MORTUS.charge_cd)
				_strike_serial += 1
				dive_hit = false
				_go(State.DIVE)
				if hit_fx.is_valid(): hit_fx.call(global_position) # dust bursts from its feet
		State.DIVE: # the charge
			var spd := float(MORTUS.charge_speed) * speed_mult
			var step := spd * delta
			velocity.x = charge_dir.x * spd
			velocity.z = charge_dir.z * spd
			charge_left -= step
			var ax := capsule_axis(p)
			var centre := global_position + Vector3(0, HEIGHT * 0.8, 0)
			if not dive_hit and alive and _axis_distance(centre, ax[0], ax[1]) <= RADIUS * 1.6 + 0.6 + step:
				dive_hit = true
				var r: String = ctx.player_health.apply(DamagePacket.new(_strike_serial, enemy_id, "infected", float(MORTUS.charge_damage), "melee"), now)
				if r == "applied" or r == "lethal":
					charge_hits += 1
					if knock_player.is_valid(): knock_player.call(charge_dir, float(MORTUS.knockback))
					if ctx.has("concuss"): ctx.concuss.call(now + float(MORTUS.concuss_s), CONCUSS_MULT)
					if hit_fx.is_valid(): hit_fx.call(p.global_position + Vector3(0, 1.0, 0))
				velocity.x = 0; velocity.z = 0
				_go(State.CHASE)
			elif get_slide_collision_count() > 0 and timer > delta * 1.5 and is_on_wall(): # a tree or rock
				stuns += 1
				velocity.x = 0; velocity.z = 0
				_go(State.STUN)
				if hit_fx.is_valid(): hit_fx.call(global_position + charge_dir * 0.8 + Vector3(0, 1.2, 0))
			elif charge_left <= 0.0:
				velocity.x = 0; velocity.z = 0
				_go(State.CHASE if alive else State.DISENGAGE)
		State.STUN:
			velocity.x = 0; velocity.z = 0
			if timer + 1e-6 >= float(MORTUS.stun_s): _go(State.CHASE if alive else State.DISENGAGE)
		_:
			super.think(delta, now, ctx)

func _animate() -> void:
	if anim == null: return
	var want := "idle"
	var sc := 1.0
	var speed := Vector2(velocity.x, velocity.z).length()
	if state == State.DEAD: want = "death"
	elif state == State.CHARGE: want = "charge"           # Crouch_Idle wind-up
	elif state == State.DIVE: want = "run"                # Sprint charge
	elif state == State.STUN: want = "idle"
	elif state in [State.WINDUP, State.STRIKE]:
		want = "strike"
		sc = STRIKE_AT / maxf(windup_time(), 0.05)
	elif speed > 0.1:
		want = "stride"
		sc = 0.6 # a slowed Walk: a heavy, deliberate gait
	if state == State.DIVE: sc = 1.4
	if anim.current_animation != want and anim.has_animation(want): anim.play(want, 0.2)
	anim.speed_scale = clampf(sc, 0.3, 3.0)
