// Map 1's rolling fog [Sir, 2026-11-20; layout pass §4]: volumetric density from
// two octaves of seamless 3D noise drifting on the wind, thinning with height,
// so banks visibly thicken and thin as they pass (Silent Hill 2's streets).
shader_type fog;
uniform sampler3D noise : repeat_enable, filter_linear_mipmap;
uniform vec3 drift = vec3(0.0);      // accumulated wind offset (m), set by map1_fog.gd
uniform float density = 0.05;
uniform float ground_y = 0.0;
uniform float height = 9.0;          // banks thin out over this height
uniform vec3 tint : source_color = vec3(0.30, 0.35, 0.32);
void fog() {
	vec3 p = (WORLD_POSITION - drift) * 0.06;
	float n = texture(noise, p).r * 0.68 + texture(noise, p * 2.7 + vec3(0.37, 0.11, 0.73)).r * 0.32;
	float bank = smoothstep(0.42, 0.7, n);
	float h = clamp(1.0 - (WORLD_POSITION.y - ground_y) / height, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.72, 1.0, max(max(abs(UVW.x*2.0-1.0), abs(UVW.z*2.0-1.0)), abs(UVW.y*2.0-1.0)));
	DENSITY = density * bank * h * h * edge;
	ALBEDO = tint;
}
