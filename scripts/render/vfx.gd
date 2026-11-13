extends Node3D
# Spell VFX (handoff P2/P4), presentation only and pooled: every node is
# built once and reused, nothing is allocated per shot, and every count is
# capped (the perf budget has little headroom).
#   explosion(at, kind, now): a particle burst (8 basic / 16 special) and a
#     scorch mark on the ground that fades over SCORCH_S (the light flash
#     itself stays the projectile service's 0.15 s burst light).
#   step_flash(from, to, now): Quick Step's flash at both ends (a light and
#     a small burst at each).
#   trail_for(node, kind): a fireball's glowing streak, added once to a pooled
#     fireball visual (hidden on Ring of Fire's orbs, which glow instead).
#   aura_particles(): the Cultivate hand embers (the aura light's child).
# Times run on the simulation clock passed in (tick(now)), so pauses hold them.

const BURST_POOL := 6        # per kind; the oldest is reused when all are busy
const DECAL_POOL := 6
const FLASH_POOL := 4
const SCORCH_S := 4.0
const FLASH_S := 0.15
const BURST := {"basic": {"amount": 6, "speed": 4.0, "size": 0.12, "life": 0.45, "color": Color(1.0, 0.55, 0.15)},
	"special": {"amount": 12, "speed": 8.0, "size": 0.22, "life": 0.6, "color": Color(1.0, 0.4, 0.08)},
	"step": {"amount": 10, "speed": 2.5, "size": 0.08, "life": 0.35, "color": Color(0.55, 0.85, 1.0)}}
const TRAIL_LEN := 0.9           # metres of streak behind a basic fireball
# BinbunVFX Vol.2 (CC0) one-shot scenes per burst kind [Sir: Binbun effects,
# stepped at 12 FPS via pixel_fx.gdshaderinc]. Missing scenes fall back to the
# built-in GPU bursts. Their own lights are turned off: the pooled flashes light
# the scene (the perf budget has ~0.2 ms of headroom).
const BB := "res://assets/BinbunVFX_Vol2/"
# Blasts [Sir, 2026-11-13]: ExplosionFX, a different explosion per attack, each
# scaled so its impact ring matches the attack's damage radius (KINDS.aoe):
# the air explosion's ring is 5 m across (radius 2.5), the nuke's 10 m (5).
const ProjectileService = preload("res://scripts/combat/projectile_service.gd")
const BLAST_NATIVE_R := {"basic": 2.5, "special": 5.0}
static func blast_scale(kind: String) -> float:
	return float(ProjectileService.KINDS[kind].aoe) / float(BLAST_NATIVE_R[kind])
const BINBUN := {"basic": {"scene": BB + "ExplosionFX/effects/air/vfx_air_explosion_01.tscn", "scale": -1.0, "color": Color(1.0, 0.55, 0.15)},
	"special": {"scene": BB + "ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn", "scale": -1.0, "color": Color(1.0, 0.42, 0.08)},
	"step": {"scene": BB + "StylizedHitFX/effects/hit/vfx_hit_01.tscn", "scale": 0.7, "color": Color(0.55, 0.85, 1.0)},
	# New spells [2026-11-14]: Firefly's missile impacts, Explosion's 50 m eruption (nuke ring r 5 m x 5 = 25 m).
	"missile_hit": {"scene": BB + "StylizedHitFX/effects/impact/vfx_impact_01.tscn", "scale": 0.5, "color": Color(1.0, 0.55, 0.15)},
	"cataclysm": {"scene": BB + "ExplosionFX/effects/nuke/vfx_nuke_explosion_01.tscn", "scale": 5.0, "color": Color(1.0, 0.4, 0.06)}}
# Fireballs [Sir, 2026-11-13]: DarkMagicFX. The basic attack is the evil
# projectile (its own fire-orange palette), the special the bigger evil ball,
# Ring of Fire's orbs small evil balls. Binbun projectiles fly along their +X
# axis; our shot visuals face their flight along -Z, so the projectile turns 90°.
const BASIC_PROJECTILE := BB + "DarkMagicFX/effects/projectile/vfx_evil_projectile_01.tscn"
const SPECIAL_PROJECTILE := BB + "DarkMagicFX/effects/ball/vfx_ball_evil_01.tscn"
const ORB_SCENE := SPECIAL_PROJECTILE
const FIRE_ORANGE := Color(1.0, 0.37, 0.0)
const FIRE_RED := Color(1.0, 0.08, 0.0)
const ORB_SCALE := 0.4
# Phase 2 [Sir, 2026-11-13]: every ability and status wears a Binbun effect.
# A basic fireball (up to 64 in flight) wears a lite cut of the fire projectile:
# its flame and tail meshes only, no spark particles and no own light (the shot
# light cap in projectile_service handles lighting). The special keeps it whole.
const LITE_STRIP := ["VFXOmniLightBB", "AudioStreamPlayer3D"]
const BASIC_STRIP := ["Flares2", "Glow"] # a basic shot (64 in flight at worst) keeps its core, trail and main flare
const SHOT_SCALE := {"basic": 0.8, "special": 1.3, "missile": 0.3} # differing sizes: the special's ball is ~1.4 m across; Firefly's missiles are tiny
# Looping effects that follow an actor while a state lasts (set_loop on/off).
const LOOPS := {
	"burn": {"scene": BB + "FlameFX/effects/fire/vfx_basic_fire_01.tscn", "scale": 0.45, "color": Color(1.0, 0.5, 0.12)},
	# Buffs [Sir, 2026-11-13]: StatusFX's status aura (its free edition's one effect):
	# cyan round the hands for Cultivate, green round the body for Sage Arts.
	# Seen from inside (first person), the aura's camera-facing streak quad (2 x
	# 2.5 m) covered the screen [Sir, 2026-11-13]: both drop it and keep a few
	# soft, dimmer rising motes; Cultivate's sit low and out by the hands.
	"cultivate": {"scene": BB + "StatusFX/effects/status/vfx_status_shatter.tscn", "scale": 0.2, "color": Color(0.55, 0.85, 1.0),
		"hide": ["MeshInstance3D"], "emission": 0.7, "amount": 10, "offset": Vector3(0, 0.15, -0.1)},
	"sage": {"scene": BB + "StatusFX/effects/status/vfx_status_shatter.tscn", "scale": 0.6, "color": Color(0.45, 1.0, 0.5),
		"hide": ["MeshInstance3D"], "emission": 0.6, "amount": 14},
	"slow": {"scene": BB + "ElementalMagicFX/effects/area/vfx_fire_area_01.tscn", "scale": 0.45, "color": Color(1.0, 0.35, 0.1)},
	"campfire": {"scene": BB + "FlameFX/effects/fire/vfx_basic_fire_01.tscn", "scale": 1.0, "color": Color(1.0, 0.55, 0.18)},
	"marker": {"scene": BB + "ElementalMagicFX/effects/area/vfx_fire_area_01.tscn", "scale": 3.0, "color": Color(1.0, 0.3, 0.05)}, # Explosion's locked point while it charges
}
# Binbun scenes are far heavier than the built-in bursts (measured: blasts +3.9 ms
# p95, the projectile core +14.7 ms when the whole pool wore it). Pools stay small
# and only ONE special fireball wears the core at a time (the special's 15 s
# cooldown means one in flight in real play; the rest keep the cheap streak).
const BINBUN_POOL := {"basic": 4, "special": 2, "step": 2, "missile_hit": 4, "cataclysm": 1} # basic hits are constant: they keep the cheap built-in burst (Binbun basic cost +3.7 ms p95)
const CORE_MAX := 1
var _cores: Array = []
var _bb := {"basic": [], "special": [], "step": [], "missile_hit": [], "cataclysm": []}
var _next_bb := {"basic": 0, "special": 0, "step": 0, "missile_hit": 0, "cataclysm": 0}
const AURA_AMOUNT := 8

var enabled := true
var _bursts := {"basic": [], "special": [], "step": []}
var _next_burst := {"basic": 0, "special": 0, "step": 0}
var _decals: Array = []       # [Decal, born, radius]
var _next_decal := 0
var _flashes: Array = []      # [OmniLight3D, until]
var _next_flash := 0
var _burst_mats := {}
var _scorch_tex: Texture2D
var _ember_tex: Texture2D
var _dot_tex: Texture2D
var counts := {"bursts": 0, "decals": 0, "flashes": 0, "trails": 0, "skipped": 0} # what was shown (tests)
# Per-tick caps: a storm of blasts (64 fireballs at once) shows a few bursts
# and one scorch a tick, and no scorch on top of a live one.
const BURSTS_PER_TICK := 2
const DECALS_PER_TICK := 1
const DECAL_SPACING := 1.0
var _tick_bursts := 0
var _tick_decals := 0
var _tick_at := -INF

func _ready() -> void:
	name = "Vfx"
	for kind in BURST:
		for i in BURST_POOL if kind != "step" else 4:
			var p := _make_burst(kind)
			p.visible = false
			add_child(p)
			_bursts[kind].append(p)
	for kind in BINBUN:
		if OS.has_environment("RC_NO_BINBUN") or not ResourceLoader.exists(BINBUN[kind].scene): continue
		var ps: PackedScene = load(BINBUN[kind].scene)
		if kind == "basic" and OS.has_environment("RC_NO_BBBLAST"): continue # diagnosis: the basic blast's Binbun explosion off
		for i in int(BINBUN_POOL[kind]):
			var fx: Node3D = ps.instantiate()
			if "autoplay" in fx: fx.autoplay = false
			_make_one_shot(fx)
			var bs: float = float(BINBUN[kind].scale)
			fx.scale = Vector3.ONE * (blast_scale(kind) if bs < 0.0 else bs)
			fx.visible = false
			add_child(fx)
			_tint(fx, BINBUN[kind].color)
			_bb[kind].append(fx)
	_scorch_tex = _make_scorch_texture()
	_ember_tex = _make_ember_texture()
	for i in DECAL_POOL:
		var d := Decal.new()
		d.texture_albedo = _scorch_tex
		d.texture_emission = _ember_tex # a dim ember ring: a scorch still reads at night
		d.emission_energy = 0.0
		d.cull_mask = 1
		d.visible = false
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		add_child(d)
		_decals.append([d, -INF, 1.0])
	for i in FLASH_POOL:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		add_child(l)
		_flashes.append([l, -INF])

static func _make_ember_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.62, Color(1.0, 0.42, 0.1, 1.0))
	g.add_point(0.45, Color(0, 0, 0, 0))
	g.add_point(0.8, Color(0, 0, 0, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

# A soft round dot for every particle (no square quads).
func _dot() -> Texture2D:
	if _dot_tex: return _dot_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	_dot_tex = t
	return t

static func _make_scorch_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.03, 0.02, 0.75))
	g.set_color(1, Color(0.05, 0.03, 0.02, 0.0))
	g.add_point(0.55, Color(0.08, 0.05, 0.03, 0.5))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t

func _particle_mat(color: Color, size: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), size]
	if _burst_mats.has(key): return _burst_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = _dot()
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_burst_mats[key] = m
	return m

func _quad(color: Color, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_mat(color, size)
	return q

func _make_burst(kind: String) -> GPUParticles3D:
	var b: Dictionary = BURST[kind]
	var p := GPUParticles3D.new()
	p.name = "Burst_" + kind
	p.amount = b.amount
	p.lifetime = b.life
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = b.speed * 0.5
	pm.initial_velocity_max = b.speed
	pm.gravity = Vector3(0, -4.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	p.draw_pass_1 = _quad(b.color, b.size)
	return p

# Recolours a Binbun effect and switches off its own lights.
# DarkMagic's ball is purple by default: recoloured to the fireball's orange and red.
static func _fire_tint(fx: Node) -> void:
	if "primary_color" in fx: fx.primary_color = FIRE_ORANGE
	if "secondary_color" in fx: fx.secondary_color = FIRE_RED
	if "light_color" in fx: fx.light_color = FIRE_ORANGE
	for l in fx.find_children("*", "Light3D", true, false): (l as Light3D).visible = false

# Ring of Fire: a pooled basic visual wears a small fire ball instead of the
# streaking projectile while it orbits (made once per visual, kept with it).
func orb_on(node: Node3D, on: bool) -> void:
	if node == null: return
	var core := node.get_node_or_null("BinbunCore")
	if core: core.visible = not on
	var orb := node.get_node_or_null("BinbunOrb")
	if orb == null and on and ResourceLoader.exists(ORB_SCENE) and not OS.has_environment("RC_NO_BINBUN"):
		orb = (load(ORB_SCENE) as PackedScene).instantiate()
		orb.name = "BinbunOrb"
		for nm in LITE_STRIP:
			var ch := orb.get_node_or_null(nm)
			if ch:
				orb.remove_child(ch)
				ch.free()
		orb.scale = Vector3.ONE * ORB_SCALE
		_fire_tint(orb)
		node.add_child(orb)
	if orb: orb.visible = on

# A node's scale reaches its particles only when they simulate in local
# coordinates; Binbun's scenes use world coordinates, so a blast scaled to its
# damage radius drew its particles at native size. Pooled effects stand still
# while they play, so local coordinates change nothing else [2026-11-14].
static func _scale_particles(fx: Node) -> void:
	if OS.has_environment("RC_NO_PSCALE"): return # diagnosis: particles at native size
	for gp in fx.find_children("*", "GPUParticles3D", true, false): (gp as GPUParticles3D).local_coords = true

static func _tint(fx: Node, color: Color) -> void:
	if "primary_color" in fx: fx.primary_color = color
	if "secondary_color" in fx: fx.secondary_color = color.lerp(Color.WHITE, 0.35)
	if "use_stepped_shading" in fx: fx.use_stepped_shading = true
	for l in fx.find_children("*", "Light3D", true, false): (l as Light3D).visible = false

# Binbun's demo scenes replay forever (controller one_shot = false; the
# explosion's "main" animation also loops): one play per blast here, and the
# effect hides itself when its animation ends.
func _make_one_shot(fx: Node3D) -> void:
	if "one_shot" in fx: fx.one_shot = true
	_scale_particles(fx)
	for ap in fx.find_children("*", "AnimationPlayer", true, false):
		for an in (ap as AnimationPlayer).get_animation_list():
			(ap as AnimationPlayer).get_animation(an).loop_mode = Animation.LOOP_NONE
	if fx.has_signal("finished"): fx.finished.connect(_bb_finished.bind(fx))

func _bb_finished(fx: Node3D) -> void:
	if is_instance_valid(fx): fx.visible = false

func binbun_ready(kind: String) -> bool:
	return not _bb.get(kind, []).is_empty()

# One burst of a kind at `at` (the pooled emitters take turns).
func _play_burst(kind: String, at: Vector3) -> void:
	if binbun_ready(kind):
		var pool_b: Array = _bb[kind]
		var fx: Node3D = pool_b[_next_bb[kind] % pool_b.size()]
		_next_bb[kind] += 1
		fx.global_position = at
		fx.visible = true
		if fx.has_method("play"): fx.play()
		counts.bursts += 1
		return
	if not _bursts.has(kind): return # Binbun-only kinds (missile_hit, cataclysm) have no built-in fallback
	var pool: Array = _bursts[kind]
	var p: GPUParticles3D = pool[_next_burst[kind] % pool.size()]
	_next_burst[kind] += 1
	p.global_position = at
	p.visible = true
	p.restart()
	counts.bursts += 1

func _flash(at: Vector3, color: Color, energy: float, rng: float, now: float) -> void:
	var f: Array = _flashes[_next_flash % _flashes.size()]
	_next_flash += 1
	var l: OmniLight3D = f[0]
	l.global_position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.visible = true
	f[1] = now + FLASH_S
	counts.flashes += 1

# A blast: particles, and a scorch on the ground under it that fades.
func explosion(at: Vector3, kind: String, now: float, ground_y := NAN) -> void:
	if not enabled or not is_inside_tree(): return
	if now != _tick_at:
		_tick_at = now
		_tick_bursts = 0
		_tick_decals = 0
	var special := kind == "special"
	if special or _tick_bursts < BURSTS_PER_TICK: # a special always shows
		var gy0: float = at.y - 1.0 if is_nan(ground_y) else ground_y
		_play_burst("special" if special else "basic", Vector3(at.x, maxf(gy0, 0.0), at.z) if special else at) # the nuke rises from the ground
		_tick_bursts += 1
	else: counts.skipped += 1
	if not special and _tick_decals >= DECALS_PER_TICK: return
	for e2 in _decals: # never a scorch on top of a live one
		if e2[0].visible and Vector2(e2[0].global_position.x - at.x, e2[0].global_position.z - at.z).length() < DECAL_SPACING and not special: return
	_tick_decals += 1
	var r: float = float(ProjectileService.KINDS["special" if special else "basic"].aoe) * 0.5 # the burnt core: half the damage radius
	var e: Array = _decals[_next_decal % _decals.size()]
	_next_decal += 1
	var d: Decal = e[0]
	var gy: float = at.y - 1.0 if is_nan(ground_y) else ground_y
	d.global_position = Vector3(at.x, gy + 0.5, at.z)
	d.size = Vector3(r * 2.0, 2.0, r * 2.0)
	d.modulate = Color(1, 1, 1, 1)
	d.emission_energy = 0.8 if kind == "special" else 0.55
	d.visible = true
	e[1] = now
	e[2] = r
	counts.decals += 1

# Quick Step: a flash and a puff at the start and at the end.
func step_flash(from: Vector3, to: Vector3, now: float) -> void:
	if not enabled or not is_inside_tree(): return
	for at in [from, to]:
		_play_burst("step", at + Vector3(0, 1.0, 0))
	_flash(from + Vector3(0, 1.0, 0), Color(0.55, 0.85, 1.0), 2.0, 3.0, now)
	_flash(to + Vector3(0, 1.0, 0), Color(0.55, 0.85, 1.0), 2.0, 3.0, now)

# A fireball's trail: a tapered glowing streak behind it (one shared mesh and
# material per kind, no particle system: 64 particle emitters cost ~1.6 ms a
# frame in the perf scene), added once to a pooled visual and reused with it.
# The projectile service turns the visual along its flight each tick.
var _streaks := {}
func _streak_mesh(kind: String) -> Mesh:
	if _streaks.has(kind): return _streaks[kind]
	var b: Dictionary = BURST["special" if kind == "special" else "basic"]
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.16 if kind != "special" else 0.38
	m.height = TRAIL_LEN if kind != "special" else TRAIL_LEN * 1.6
	m.radial_segments = 6
	m.rings = 1
	m.cap_top = false
	m.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(b.color, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material = mat
	_streaks[kind] = m
	return m

func trail_for(node: Node3D, kind: String) -> void:
	if node == null or node.has_node("Trail") or node.has_node("BinbunCore"): return
	var scene: String = SPECIAL_PROJECTILE if kind == "special" else BASIC_PROJECTILE
	if not OS.has_environment("RC_NO_BINBUN") and not OS.has_environment("RC_NO_BBCORE") and ResourceLoader.exists(scene):
		# The fireball IS the Binbun projectile: the old sphere is hidden, and the
		# projectile's own tail is the trail (no streak cone).
		var core: Node3D = (load(scene) as PackedScene).instantiate()
		core.name = "BinbunCore"
		for nm in LITE_STRIP + (BASIC_STRIP if kind != "special" else []): # no own light (the shot light cap lights it), no audio
			var ch := core.get_node_or_null(nm)
			if ch:
				core.remove_child(ch)
				ch.free()
		core.scale = Vector3.ONE * float(SHOT_SCALE.get(kind, 0.8))
		core.rotation.y = PI * 0.5 # +X (the projectile's flight) onto -Z (the visual's)
		if kind == "special": _fire_tint(core)
		for m in node.get_children():
			if m is MeshInstance3D: (m as MeshInstance3D).visible = false
		node.add_child(core)
		_cores.append(core)
		counts.trails += 1
		return
	var t := MeshInstance3D.new()
	t.name = "Trail"
	t.mesh = _streak_mesh(kind)
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var h: float = (t.mesh as CylinderMesh).height
	t.rotation.x = -PI * 0.5 # the cone's axis along +Z: behind a visual that faces its flight (-Z)
	t.position = Vector3(0, 0, h * 0.5)
	node.add_child(t)
	counts.trails += 1

# A looping Binbun effect for an actor's state (Burn, Scorched Slow, Cultivate):
# made once per owner, hidden and quiet until set_loop(fx, true). Static so
# actors can build their own without a reference to the world's Vfx.
static func make_loop(kind: String) -> Node3D:
	var spec: Dictionary = LOOPS[kind]
	if OS.has_environment("RC_NO_BINBUN") or not ResourceLoader.exists(spec.scene): return null
	var fx: Node3D = (load(spec.scene) as PackedScene).instantiate()
	fx.name = "Loop_" + kind
	if "autoplay" in fx: fx.autoplay = false
	if "one_shot" in fx: fx.one_shot = true # the controller never re-queues itself; set_loop drives it
	for ap in fx.find_children("*", "AnimationPlayer", true, false): (ap as AnimationPlayer).autoplay = ""
	fx.scale = Vector3.ONE * float(spec.scale)
	_tint(fx, spec.color)
	if kind == "marker": _scale_particles(fx) # sized to Explosion's area (the buff auras were tuned at native particle size)
	for nm in spec.get("hide", []): # parts that cannot work from the first-person eye
		var part := fx.get_node_or_null(nm)
		if part:
			fx.remove_child(part)
			part.free()
	if spec.has("emission") and "emission" in fx: fx.emission = float(spec.emission)
	if spec.has("amount"):
		for gp in fx.find_children("*", "GPUParticles3D", true, false): (gp as GPUParticles3D).amount = int(spec.amount)
	if spec.has("offset"): fx.position = spec.offset
	fx.visible = false
	for gp in fx.find_children("*", "GPUParticles3D", true, false): (gp as GPUParticles3D).emitting = false
	return fx

static func set_loop(fx: Node3D, on: bool) -> void:
	if fx == null or fx.visible == on: return
	fx.visible = on
	for gp in fx.find_children("*", "GPUParticles3D", true, false):
		(gp as GPUParticles3D).emitting = on
		if on: (gp as GPUParticles3D).restart()
	for ap in fx.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		if not on:
			a.stop()
			continue
		var clip := "open" if a.has_animation("open") else "main"
		if clip == "main" and a.has_animation("main"): a.get_animation("main").loop_mode = Animation.LOOP_LINEAR
		if a.has_animation(clip):
			a.play(clip)
			if clip == "open": a.seek(a.current_animation_length, true) # straight to the open state (its emitters on)

static func loop_on(fx: Node3D) -> bool:
	return fx != null and fx.visible

# ---- new spells [2026-11-14] -------------------------------------------------------------

func missile_hit(at: Vector3, _now: float) -> void:
	if enabled and is_inside_tree(): _play_burst("missile_hit", at)

func cataclysm(at: Vector3, _now: float) -> void:
	if enabled and is_inside_tree():
		_play_burst("cataclysm", at)

# Dragon's Breath [Sir, 2026-11-14]: a cone of fire built from DarkMagicFX's own
# parts (the pack has no cone or stream effect): its fire-ball flame particles,
# i.e. that scene's void_particles shader and 0.6 x 1.4 m flame quad, re-emitted
# from the mouth down the aim. They spread 7.1 deg (2.5 m over 20 m) and grow
# as they travel, so the flames fill the 20 m x 5 m damage cone; a finer ember
# layer rides inside. World-space particles: the cone trails a turning head.
# Child of the camera; set_breath() starts and stops the emitters.
const BREATH_LEN := 20.0
const BREATH_END_R := 2.5
func breath_cone() -> Node3D:
	if OS.has_environment("RC_NO_BINBUN") or not ResourceLoader.exists(SPECIAL_PROJECTILE): return null
	var ball: Node3D = (load(SPECIAL_PROJECTILE) as PackedScene).instantiate() # DarkMagicFX vfx_ball_evil_01
	var src: GPUParticles3D = ball.get_node_or_null("Particles")
	if src == null:
		ball.free()
		return null
	var root := Node3D.new()
	root.name = "DragonsBreath"
	root.position = Vector3(0, -0.5, -0.9) # the mouth: low and a little ahead, so the stream rises into view without covering it
	var spread := rad_to_deg(atan2(BREATH_END_R, BREATH_LEN))
	root.add_child(_cone_layer("Flames", src, 140, 0.95, 20.0, spread, Vector2(0.7, 3.4), Color(1.0, 0.42, 0.04), Color(1.0, 0.08, 0.0)))
	root.add_child(_cone_layer("Embers", src, 48, 0.8, 24.0, spread * 0.7, Vector2(0.12, 0.9), Color(1.0, 0.75, 0.2), Color(1.0, 0.3, 0.0)))
	ball.free()
	root.visible = false
	return root

# One emitter of the cone: the pack's flame material and quad, our cone motion.
# scale = [at the mouth, at the far end] in units of the 1.4 m flame quad.
func _cone_layer(nm: String, src: GPUParticles3D, amount: int, life: float, speed: float, spread_deg: float,
		scale: Vector2, primary: Color, secondary: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY # flames stretch along their flight
	p.visibility_aabb = AABB(Vector3(-4, -4, -BREATH_LEN - 2.0), Vector3(8, 8, BREATH_LEN + 4.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := (src.material_override as ShaderMaterial).duplicate() if src.material_override is ShaderMaterial else null
	if mat:
		mat.set_shader_parameter("primary_color", primary)
		mat.set_shader_parameter("secondary_color", secondary)
		p.material_override = mat
	p.draw_pass_1 = src.draw_pass_1
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = spread_deg
	pm.initial_velocity_min = speed * 0.9
	pm.initial_velocity_max = speed * 1.1
	pm.gravity = Vector3(0, 1.2, 0) # flames lift a little
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, scale.x / scale.y))
	grow.add_point(Vector2(1.0, 1.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_min = scale.y
	pm.scale_max = scale.y
	pm.scale_curve = gt
	var srcpm := src.process_material as ParticleProcessMaterial
	var fade := Curve.new() # in at once, out over the last third (the pack's curve fades in too slowly near the mouth)
	fade.add_point(Vector2(0.0, 0.6))
	fade.add_point(Vector2(0.08, 1.0))
	fade.add_point(Vector2(0.65, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var ft := CurveTexture.new()
	ft.curve = fade
	pm.alpha_curve = ft
	if srcpm and srcpm.color_initial_ramp: pm.color_initial_ramp = srcpm.color_initial_ramp
	p.process_material = pm
	return p

func set_breath(b: Node3D, on: bool) -> void:
	if b == null: return
	b.visible = on
	for gp in b.find_children("*", "GPUParticles3D", true, false):
		(gp as GPUParticles3D).emitting = on
		if on: (gp as GPUParticles3D).restart()

# Cultivate's hand embers, made once for the aura light (fallback without Binbun).
func aura_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "AuraEmbers"
	p.amount = AURA_AMOUNT
	p.lifetime = 0.8
	p.local_coords = true
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.18
	pm.direction = Vector3.UP
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0, 0.3, 0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	p.draw_pass_1 = _quad(Color(0.55, 0.85, 1.0), 0.03)
	return p

# Fades the scorches and ends the flashes (simulation time).
func tick(now: float) -> void:
	for e in _decals:
		var d: Decal = e[0]
		if not d.visible: continue
		var u := (now - float(e[1])) / SCORCH_S
		if u >= 1.0: d.visible = false
		else:
			d.modulate.a = 1.0 - u * u
			d.emission_energy = maxf(0.0, 1.0 - u * 2.0) * (0.8 if float(e[2]) > 2.0 else 0.55) # the embers cool first
	for f in _flashes:
		if f[0].visible and now >= float(f[1]): f[0].visible = false

func reset() -> void:
	for kind in _bb:
		for fx in _bb[kind]:
			# Not fx.stop(): some Binbun scenes have no "stop" animation and it logs an engine error.
			for gp in fx.find_children("*", "GPUParticles3D", true, false): (gp as GPUParticles3D).emitting = false
			fx.visible = false
	for e in _decals: e[0].visible = false
	for f in _flashes: f[0].visible = false
	for kind in _bursts:
		for p in _bursts[kind]:
			p.emitting = false
			p.visible = false

func live_decals() -> int:
	return _decals.filter(func(e): return e[0].visible).size()

func pooled_nodes() -> int:
	var n := _decals.size() + _flashes.size()
	for k in _bursts: n += _bursts[k].size()
	for k in _bb: n += _bb[k].size()
	return n
