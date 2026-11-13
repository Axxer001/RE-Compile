extends Node
# Art direction (architecture-rehaul §11): L4D2-style night grading, fog and
# practical lights over the existing world. One call from main after the world
# is built:  ArtDirection.new().apply(self)
# Presentation only: never touches simulation state.

const POST := """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform float bt = 0.0; // bullet time: desaturate harder
uniform float grain = 0.05; // 0 for deterministic captures (render tests)
uniform vec2 low_res = vec2(640.0, 360.0); // the world view's pixel grid (lofi_view): dither per world pixel
uniform bool colour16 = true; // 16-bit colour (RGB 5-6-5) with a 4x4 ordered dither [Sir, 2026-11-13]
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// split tone: cold blue-green shadows, warm sodium highlights
	c *= mix(vec3(0.82, 0.98, 1.04), vec3(1.10, 0.96, 0.80), smoothstep(0.12, 0.65, l));
	c = mix(vec3(l), c, mix(0.85, 0.25, bt));
	c = (c - 0.5) * 1.1 + 0.5;
	c += (hash(SCREEN_UV * 931.0 + TIME) - 0.5) * grain; // film grain
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * 0.85; // vignette
	if (colour16) {
		ivec2 cell = ivec2(floor(SCREEN_UV * low_res)) % 4;
		float t = BAYER[cell.y * 4 + cell.x] / 16.0 - 0.5;
		vec3 levels = vec3(31.0, 63.0, 31.0);
		c = floor(clamp(c, 0.0, 1.0) * levels + 0.5 + t) / levels;
	}
	COLOR = vec4(c, 1.0);
}
"""

const MAX_LAMP_SHADOWS := 3 # §11 budget: ≤ 4 shadowed lights incl. the flashlight

var post: ShaderMaterial

func apply(world: Node) -> void:
	world.add_child(self)
	var we: WorldEnvironment = _find(world, "WorldEnvironment")
	if we and we.environment:
		_grade(we.environment)
	var sun: DirectionalLight3D = _find(world, "DirectionalLight3D")
	if sun:
		# Night: the sun becomes weak, cold moonlight.
		sun.light_color = Color(0.55, 0.65, 0.85)
		sun.light_energy = 0.35
	var shadows := 0
	for n in world.find_children("lamp_*", "OmniLight3D", true, false):
		var lamp := n as OmniLight3D
		lamp.light_color = Color(1.0, 0.62, 0.3) if lamp.get_index() % 2 == 0 else Color(0.78, 0.92, 1.0)
		lamp.light_energy = 3.0
		lamp.set_meta("base_energy", 3.0) # main's flicker and reset scale from this
		lamp.omni_range = 15.0
		lamp.shadow_enabled = shadows < MAX_LAMP_SHADOWS
		shadows += 1
	_add_post()

# Binbun's sky in a night setting [Phase 3]: stars and dim clouds above the
# forest. The shader treats the scene's main light as the sun (and puts its moon
# opposite), and ours is the moon, so the sky runs on its own night blend
# instead. Fog covers it only partly, so the canopy gaps show it.
const SKY_SHADER := "res://assets/BinbunSky/shader/main.gdshader"
const CLOUDS := "res://assets/BinbunSky/textures/clouds/clouds_%02d.tres"
func apply_night_sky(e: Environment) -> bool:
	if not ResourceLoader.exists(SKY_SHADER) or OS.has_environment("RC_NO_SKY"): return false
	var m := ShaderMaterial.new()
	m.shader = load(SKY_SHADER)
	m.set_shader_parameter("use_directional_light", false)
	m.set_shader_parameter("day_night_mix", -1.0)
	m.set_shader_parameter("sky_night", Color(0.025, 0.035, 0.06))
	m.set_shader_parameter("horizon_night", Color(0.05, 0.065, 0.085))
	m.set_shader_parameter("cloud_color", Color(0.17, 0.19, 0.25))
	m.set_shader_parameter("cloud_density", 0.45)
	m.set_shader_parameter("wind_speed", Vector2(0.15, 0.05))
	m.set_shader_parameter("cloud_tex_01", load(CLOUDS % 1))
	m.set_shader_parameter("cloud_tex_02", load(CLOUDS % 2))
	var stars := FastNoiseLite.new() # fine noise: small star points (the cloud noise draws streaks)
	stars.noise_type = FastNoiseLite.TYPE_SIMPLEX
	stars.frequency = 0.35
	stars.fractal_type = FastNoiseLite.FRACTAL_NONE
	var st := NoiseTexture2D.new()
	st.width = 1024
	st.height = 1024
	st.seamless = true
	st.noise = stars
	var ramp := Gradient.new() # only the noise's peaks become stars (the shader keeps values > 0.9)
	ramp.offsets = PackedFloat32Array([0.0, 0.8, 0.86])
	ramp.colors = PackedColorArray([Color.BLACK, Color.BLACK, Color.WHITE])
	st.color_ramp = ramp
	m.set_shader_parameter("night_noise_01", st)
	m.set_shader_parameter("night_noise_02", load(CLOUDS % 3))
	var sky := Sky.new()
	sky.sky_material = m
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR # the grade's ambient, not the sky's
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_sky_affect = 0.15
	return true

func _grade(e: Environment) -> void:
	e.background_color = Color(0.02, 0.025, 0.035)
	e.ambient_light_color = Color(0.2, 0.25, 0.28)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.13, 0.15)
	e.fog_density = 0.01
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		e.volumetric_fog_enabled = true
		e.volumetric_fog_density = 0.008
		e.volumetric_fog_albedo = Color(0.7, 0.75, 0.78)
	e.glow_enabled = true
	e.glow_bloom = 0.12
	e.adjustment_enabled = true
	e.adjustment_saturation = 0.9
	e.adjustment_contrast = 1.0

func _add_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0 # above the world view (lofi_view, layer -1), below the HUD (1) and panels (6, 10)
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = POST
	post = ShaderMaterial.new()
	post.shader = sh
	rect.material = post
	layer.add_child(rect)

# The world view's pixel grid, so the dither lands on whole world pixels.
func set_low_res(size: Vector2) -> void:
	if post: post.set_shader_parameter("low_res", size)

func set_colour16(on: bool) -> void:
	if post: post.set_shader_parameter("colour16", on)

func set_grain(amount: float) -> void:
	if post: post.set_shader_parameter("grain", maxf(amount, 0.0))

# 0 = normal, 1 = full bullet-time grade. Call from the bullet-time ability (R2).
func set_bullet_time(amount: float) -> void:
	if post: post.set_shader_parameter("bt", clampf(amount, 0.0, 1.0))

func _find(root: Node, type: String) -> Node:
	var found := root.find_children("*", type, true, false)
	return found[0] if found.size() else null
