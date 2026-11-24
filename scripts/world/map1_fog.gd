extends Node3D
## Map 1's fog, as close to Silent Hill 2's as the engine allows [Sir, 2026-11-20;
## docs/plan-map1-layout-pass.md §4]. Over the depth fog's opaque 30 m cutoff
## (the background is the fog's exact colour, art_direction.gd):
##   - rolling banks: a FogVolume round the player whose density is drifting 3D
##     noise (fog_banks.gdshader), the wind turning slowly;
##   - drifting sheets: soft quads at several angles, born upwind, carried by the
##     wind and recycled downwind (fog_sheet.gdshader);
##   - breathing visibility: the opaque distance drifts between BREATH_MIN and
##     BREATH_MAX over 20-40 s;
##   - a close haze: the depth fog starts at the eye (HAZE_BEGIN), so near
##     things soften too;
##   - the wand's cone lights the fog (volumetric light, set by main);
##   - per zone: thin at the camp (the town in view), thickest in combat, and
##     closing in while a pathway behind is sealing.
## Presentation only: never touches the simulation.

const ArtDirection = preload("res://scripts/render/art_direction.gd")
const BANKS_SHADER := "res://assets/shaders/map1/fog_banks.gdshader"
const SHEET_SHADER := "res://assets/shaders/map1/fog_sheet.gdshader"
const BREATH_LOW := 0.82        # the fog breathes between this share of the visibility and all of it (24.6-30 m at 30)
const HAZE_BEGIN := 0.0          # the depth fog starts at the eye: a faint haze within a few metres
const HAZE_CURVE := 0.9
const PEACE_BEGIN := 8.0         # a closed field (60 m visibility): the depth fog starts further out ...
const PEACE_CURVE := 2.2         # ... and gathers toward the far end, so the field reads open to its border
const BANK_SIZE := Vector3(64, 14, 64)
const BANK_DENSITY := {"camp": 0.012, "pathway": 0.1, "peace": 0.03, "chunk": 0.16} # "peace": a closed field's 60 m view
const SHEETS := 12 # [perf trim: sheet coverage]
const SHEET_RING := Vector2(5.0, 24.0)
const WIND_SPEED := Vector2(1.0, 2.2) # m/s
const SEAL_CLOSE := 6.0          # m the fog closes in while a pathway seals
const WAND_FOG := 2.5            # the wand light's volumetric energy (light shafts)

var time := 0.0
var wind_dir := Vector2(1, 0.3).normalized()
var wind_speed := 1.0
var drift := Vector3.ZERO
var banks: FogVolume
var banks_mat: ShaderMaterial
var sheets: Array = []           # {node, mat, life, age, span}
var rng := RandomNumberGenerator.new()
var zone := "camp"
var forest_mix := 0.0
var bank_density := 0.012
var visibility := ArtDirection.FOG_END
var _sheet_noise: Texture2D

func setup(seed_value: int) -> void:
	name = "Map1Fog"
	rng.seed = seed_value ^ 0x666f67
	banks = FogVolume.new()
	banks.name = "FogBanks"
	banks.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	banks.size = BANK_SIZE
	banks_mat = ShaderMaterial.new()
	banks_mat.shader = load(BANKS_SHADER)
	var n3 := NoiseTexture3D.new()
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.06
	fnl.fractal_octaves = 3
	fnl.seed = seed_value
	n3.noise = fnl
	n3.width = 64
	n3.height = 32
	n3.depth = 64
	n3.seamless = true
	banks_mat.set_shader_parameter("noise", n3)
	banks.material = banks_mat
	add_child(banks)
	var n2 := NoiseTexture2D.new()
	var f2 := FastNoiseLite.new()
	f2.frequency = 0.012
	f2.fractal_octaves = 3
	f2.seed = seed_value + 1
	n2.noise = f2
	n2.seamless = true
	n2.width = 256
	n2.height = 256
	_sheet_noise = n2
	for i in SHEETS: sheets.append(_new_sheet(i))

func _new_sheet(i: int) -> Dictionary:
	var m := MeshInstance3D.new()
	m.name = "fog_sheet_%d" % i
	var q := QuadMesh.new()
	q.size = Vector2(rng.randf_range(7.0, 13.0), rng.randf_range(2.6, 4.2))
	q.center_offset = Vector3(0, q.size.y * 0.5 - 0.3, 0)
	m.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load(SHEET_SHADER)
	mat.set_shader_parameter("noise", _sheet_noise)
	if RenderingServer.get_current_rendering_method() != "forward_plus": mat.set_shader_parameter("alpha", 0.5) # no volumetric banks there: the sheets carry the drift
	mat.set_shader_parameter("life", 0.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	return {"node": m, "mat": mat, "age": rng.randf_range(0.0, 20.0), "span": rng.randf_range(16.0, 30.0), "placed": false, "scroll": Vector2(rng.randf(), rng.randf())}

## The opaque distance now: the player's visibility (Map1World.visibility_at, the
## plan's 30 / 20 / 60 / 30 / 5 m) breathing a little under it, never past it.
func visibility_at(base_end: float, sealing: float) -> float:
	var breath := (sin(time * TAU / 27.0) * 0.6 + sin(time * TAU / 41.0 + 1.3) * 0.4) * 0.5 + 0.5 # 0..1
	return base_end * lerpf(BREATH_LOW, 1.0, breath) * (1.0 - 0.2 * clampf(sealing, 0.0, 1.0))

## One frame. `zone`: camp / pathway / chunk; `ground_y`: under the player;
## `base_end`: Map1World.visibility_at; `sealing`: unused now (0), kept for callers.
## Returns the opaque distance (main applies it to the environment and the far clip).
func update(delta: float, player_pos: Vector3, camera: Camera3D, zone_now: String, ground_y: float, base_end: float, sealing: float) -> float:
	time += delta
	zone = zone_now
	# The wind turns slowly and gusts a little.
	var turn := sin(time * 0.021) * 0.004 + sin(time * 0.007 + 2.0) * 0.003
	wind_dir = wind_dir.rotated(turn * delta * 60.0).normalized()
	wind_speed = lerpf(WIND_SPEED.x, WIND_SPEED.y, 0.5 + 0.5 * sin(time * 0.09))
	drift += Vector3(wind_dir.x, 0.02, wind_dir.y) * wind_speed * delta
	banks.global_position = Vector3(player_pos.x, ground_y + BANK_SIZE.y * 0.5 - 2.0, player_pos.z)
	banks_mat.set_shader_parameter("drift", drift)
	banks_mat.set_shader_parameter("ground_y", ground_y)
	bank_density = lerpf(bank_density, float(BANK_DENSITY.get(zone, 0.045)) * (1.0 + 0.6 * sealing), 1.0-exp(-delta*2.0))
	banks_mat.set_shader_parameter("density", bank_density)
	visibility = visibility_at(base_end, sealing)
	# Sheets: in the forest only; born upwind, carried downwind, recycled.
	forest_mix = move_toward(forest_mix, 0.0 if zone == "camp" else 1.0, delta * 0.7)
	var show := forest_mix > 0.0
	var w3 := Vector3(wind_dir.x, 0, wind_dir.y)
	for sh in sheets:
		var node: MeshInstance3D = sh.node
		if not show:
			node.visible = false
			sh.placed = false
			continue
		sh.age = float(sh.age) + delta
		var rel: Vector3 = node.global_position - player_pos
		var downwind: float = rel.dot(w3)
		if not sh.placed or float(sh.age) >= float(sh.span) or downwind > SHEET_RING.y or Vector2(rel.x, rel.z).length() > SHEET_RING.y + 6.0:
			_place(sh, player_pos, ground_y, w3)
		node.global_position += w3 * wind_speed * delta
		var life: float = smoothstep(0.0, 4.0, float(sh.age)) * (1.0 - smoothstep(float(sh.span) - 4.0, float(sh.span), float(sh.age)))
		sh.scroll = (sh.scroll as Vector2) + Vector2(wind_speed, 0.0) * delta * 0.01
		(sh.mat as ShaderMaterial).set_shader_parameter("life", life * forest_mix * (1.0-smoothstep(15.0, SHEET_RING.y, rel.length())))
		(sh.mat as ShaderMaterial).set_shader_parameter("scroll", sh.scroll)
		node.visible = true
	return visibility

## A sheet born upwind (or anywhere round the player the first time), at its own angle.
func _place(sh: Dictionary, player_pos: Vector3, ground_y: float, w3: Vector3) -> void:
	var node: MeshInstance3D = sh.node
	var r := rng.randf_range(SHEET_RING.x, SHEET_RING.y)
	var a := rng.randf_range(-1.4, 1.4)
	var up := -w3.rotated(Vector3.UP, a) if sh.placed else Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
	node.global_position = Vector3(player_pos.x, ground_y + rng.randf_range(-0.2, 0.8), player_pos.z) + up * r
	node.rotation = Vector3(0, rng.randf() * TAU, 0)
	sh.age = 0.0
	sh.span = rng.randf_range(16.0, 30.0)
	sh.placed = true

## Sheets showing now (tests, the performance metrics).
func sheets_live() -> int:
	return sheets.filter(func(sh): return (sh.node as MeshInstance3D).visible).size()
