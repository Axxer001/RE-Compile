// Map 1's hollow mist [from GAME ASSETS/Dark Forest Layouts/Mist.gdshader; layout
// pass §4]: low, slow-moving, faded at every edge and near the camera.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
varying vec3 w;
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float wave = sin(w.x * 0.25 + w.z * 0.11 + TIME * 0.33) + 0.48 * sin(w.x * 0.57 - w.z * 0.31 + TIME * 0.54);
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.3, e.x) * smoothstep(0.0, 0.5, e.y);
	ALBEDO = vec3(0.19, 0.22, 0.215);
	ALPHA = 0.14 * smoothstep(-1.4, 0.7, wave) * edge * smoothstep(0.0, 4.0, length(w.xz - CAMERA_POSITION_WORLD.xz));
}
