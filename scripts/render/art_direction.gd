extends Node
# Art direction: Silent Hill 2-style night [Sir, 2026-11-20; docs/plan-graphics-
# direction.md]: dense dark grey-green fog, opaque at FOG_END, the background
# the fog's exact colour (no sky, no band), a weak cool moon over the pack's cool
# ambient fill, linear tonemapping; the post layer adds grain, desaturation and a
# vignette. Practical lights over the existing world. One call from main after the world
# is built:  ArtDirection.new().apply(self)
# Presentation only: never touches simulation state.

# Post [graphics direction 2026-11-20]: film grain, ~30% desaturation and the
# vignette, nothing else (the pixel view and the 16-bit dither are gone).
const POST := """
shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear;
uniform float bt = 0.0; // bullet time: desaturate harder
uniform float grain = 0.06; // 0 for deterministic captures (render tests)
uniform float saturation = 0.7; // ~30% desaturated
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, mix(saturation, 0.25, bt));
	c += (hash(SCREEN_UV * 931.0 + TIME) - 0.5) * grain; // film grain
	vec2 d = SCREEN_UV - 0.5;
	c *= 1.0 - dot(d, d) * 0.85; // vignette
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
		# Night: the sun becomes weak, cool moonlight.
		sun.light_color = Color(0.62, 0.7, 0.86)
		sun.light_energy = 0.22
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

const FOG := Color(0.102, 0.122, 0.110)  # #1a1f1c
const FOG_BEGIN := 3.0                   # m: clear air round the player
const FOG_END := 30.0                    # m: fully opaque here
const FAR_CLIP := 40.0                   # m: the camera draws no further (the fog hides the edge)
const AMBIENT := Color(0.64, 0.66, 0.70) # the pack's cool fill (ForestLight), scaled to night
const AMBIENT_ENERGY := 0.3
const EXPOSURE := 1.15

func _grade(e: Environment) -> void:
	e.background_mode = Environment.BG_COLOR
	e.background_color = FOG # matched exactly: fully fogged geometry and the void are one colour
	e.sky = null
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT
	e.ambient_light_energy = AMBIENT_ENERGY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = EXPOSURE
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = FOG
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.0
	e.fog_density = 1.0
	e.fog_depth_begin = FOG_BEGIN
	e.fog_depth_end = FOG_END
	e.fog_depth_curve = 0.8
	e.fog_sky_affect = 1.0
	e.fog_aerial_perspective = 0.0
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		e.volumetric_fog_enabled = true # the drift: cheap settings
		e.volumetric_fog_density = 0.012
		e.volumetric_fog_albedo = Color(0.32, 0.38, 0.34)
		e.volumetric_fog_length = 24.0
		e.volumetric_fog_detail_spread = 2.0
		e.volumetric_fog_gi_inject = 0.0
		e.volumetric_fog_ambient_inject = 0.2
	e.glow_enabled = true # the saturated accents (fire, the wand) bloom a little
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 0.9
	e.adjustment_enabled = false # the post layer desaturates

func _add_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0 # above the world view (lofi_view, layer -1, native resolution), below the HUD (1) and panels (6, 10)
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

func set_grain(amount: float) -> void:
	if post: post.set_shader_parameter("grain", maxf(amount, 0.0))

# 0 = normal, 1 = full bullet-time grade. Call from the bullet-time ability (R2).
func set_bullet_time(amount: float) -> void:
	if post: post.set_shader_parameter("bt", clampf(amount, 0.0, 1.0))

func _find(root: Node, type: String) -> Node:
	var found := root.find_children("*", type, true, false)
	return found[0] if found.size() else null
