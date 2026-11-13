extends RefCounted
# Simulation time scales (rehaul §4.2). The world (enemies, projectiles,
# hazards) and the player each get their own scaled delta; Engine.time_scale is
# never touched, so the physics tick, input and UI run at full rate. Bullet
# time (R2) sets the targets; scales ease toward them over EASE_S.
# Owned by GameSession (not an autoload) so headless tests get a fresh one per
# session and runs stay deterministic.

const EASE_S := 0.15

var world_scale := 1.0
var player_scale := 1.0
var world_target := 1.0
var player_target := 1.0

func set_targets(world: float, player: float) -> void:
	world_target = clampf(world, 0.0, 1.0)
	player_target = clampf(player, 0.0, 1.0)

# Once per tick with the real delta, before anything uses the scales.
func tick(delta: float) -> void:
	var k := 1.0 if EASE_S <= 0.0 else clampf(delta / EASE_S, 0.0, 1.0)
	world_scale = lerpf(world_scale, world_target, k)
	player_scale = lerpf(player_scale, player_target, k)
	if absf(world_scale - world_target) < 1e-4: world_scale = world_target
	if absf(player_scale - player_target) < 1e-4: player_scale = player_target

func world_dt(delta: float) -> float:
	return delta * world_scale

func player_dt(delta: float) -> float:
	return delta * player_scale

func reset() -> void:
	world_scale = 1.0
	player_scale = 1.0
	world_target = 1.0
	player_target = 1.0
