extends CanvasLayer
# The lo-fi look (design brief §8): the 3D world is drawn into a SubViewport at
# 1/`shrink` of the window size and scaled up with nearest-neighbour filtering
# (crunchy pixels), with film grain and a vignette on top. The SubViewport
# shares the main World3D, and a camera here mirrors the player camera each
# frame; the root viewport stops drawing 3D. The HUD lives on a higher
# CanvasLayer at full resolution, so text stays sharp. Presentation only.

const GRAIN_SHADER := """
shader_type canvas_item;
uniform float grain = 0.06;
uniform float vignette = 0.45;
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	float n = hash(floor(FRAGCOORD.xy / 2.0) + floor(TIME * 24.0)) - 0.5;
	vec2 c = UV - 0.5;
	float v = smoothstep(0.85, 0.2, length(c) * 1.25);
	COLOR = vec4(vec3(0.0), clamp((1.0 - v) * vignette, 0.0, 1.0));
	COLOR.rgb += n * grain * 4.0;
	COLOR.a = max(COLOR.a, abs(n) * grain);
}
"""

var shrink := 3
var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var grain: ColorRect
var source: Camera3D   # the player camera being mirrored
# View-only kick (radians: pitch up, roll) from damage and hard landings. Applied
# to the display camera only, so the player's aim never moves. Decays to zero.
var kick := Vector2.ZERO
const KICK_DECAY := 9.0   # per second (exponential)
const KICK_MAX := 0.12    # radians
var kicks_enabled := true

func setup(source_camera: Camera3D, world: World3D, shrink_factor := 3) -> void:
	layer = -1
	source = source_camera
	shrink = shrink_factor
	container = SubViewportContainer.new()
	container.name = "LoFi"
	container.stretch = true
	container.stretch_shrink = shrink
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.world_3d = world
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.handle_input_locally = false
	container.add_child(viewport)
	camera = Camera3D.new()
	camera.name = "LoFiCamera"
	viewport.add_child(camera)
	camera.current = true
	grain = ColorRect.new()
	grain.name = "Grain"
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GRAIN_SHADER
	mat.shader = sh
	grain.material = mat
	add_child(grain)
	sync()

# Mirror the player camera (call every frame and after teleports).
func sync() -> void:
	if source == null or camera == null: return
	camera.global_transform = source.global_transform
	if kicks_enabled and kick.length_squared() > 1e-8:
		camera.rotate_object_local(Vector3.RIGHT, kick.x)
		camera.rotate_object_local(Vector3.FORWARD, kick.y)
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far

func add_kick(pitch: float, roll: float) -> void:
	kick = (kick + Vector2(pitch, roll)).limit_length(KICK_MAX)

func _process(delta: float) -> void:
	kick *= exp(-KICK_DECAY * delta)
	if kick.length() < 1e-4: kick = Vector2.ZERO
	sync()
