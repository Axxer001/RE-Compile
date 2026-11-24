// Map 1's drifting fog sheets [layout pass §4]: soft at every edge, broken up by
// moving noise, fading when seen edge-on or from close, so they read as wisps.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec3 colour : source_color = vec3(0.19, 0.22, 0.205);
uniform float alpha = 0.3;
uniform float life = 1.0;            // 0..1, set per sheet: born and recycled faded
uniform vec2 scroll = vec2(0.0);
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.35, e.x) * smoothstep(0.0, 0.45, e.y);
	float n = texture(noise, UV * vec2(1.6, 0.8) + scroll).r * 0.6 + texture(noise, UV * vec2(3.1, 1.7) - scroll * 1.7).r * 0.4;
	vec3 to_cam = CAMERA_POSITION_WORLD - wpos;
	float facing = abs(dot(normalize(to_cam), wnrm));
	float near = smoothstep(1.5, 5.0, length(to_cam));
	ALBEDO = colour;
	ALPHA = alpha * life * edge * smoothstep(0.25, 0.75, n) * smoothstep(0.15, 0.55, facing) * near;
}
