shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.102, 0.122, 0.110);
uniform float soft_distance : hint_range(0.1, 6.0) = 2.2;
uniform vec2 wind = vec2(0.018, 0.006);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth * 2.0 - 1.0;
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = VERTEX.z - scene.z / scene.w;
	vec2 p = vec2(dot(world_pos.xz, vec2(0.81,0.59)), world_pos.y) * vec2(0.075,0.11);
	float cloud = texture(noise_tex, p - wind * TIME).r;
	cloud = mix(cloud, texture(noise_tex, p * 2.4 - wind * TIME * 0.7).r, 0.22);
	vec2 edge = min(UV, 1.0 - UV);
	float feather = smoothstep(0.0,0.18,edge.x) * smoothstep(0.0,0.23,edge.y);
	ALBEDO = tint;
	ALPHA = cover * feather * mix(0.4,1.0,smoothstep(0.24,0.68,cloud))
		* smoothstep(0.0,soft_distance,gap) * smoothstep(0.8,4.0,length(VERTEX));
}
