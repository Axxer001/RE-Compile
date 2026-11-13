// Derived from BinbunGrass/src/shader/ground.gdshader (CC0, Binbun): coloured lights.
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha;

group_uniforms Colors;
uniform sampler2D noise_texture;
uniform sampler2D color_gradient;

varying flat int id;
varying vec3 world_pos;

#include "util/dither.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float noise_value = texture(noise_texture, world_pos.xz * 0.1).r;
	vec4 color = texture(color_gradient, vec2(noise_value, 0.0));

	ALBEDO = color.rgb;
}

void light(){
	// RE:Compile: coloured lights (campfire, blasts) tint it, as on every other surface.
	float ndotl = max(dot(LIGHT, NORMAL), 0.0) * ATTENUATION;
	DIFFUSE_LIGHT += ndotl * LIGHT_COLOR / PI;
}
