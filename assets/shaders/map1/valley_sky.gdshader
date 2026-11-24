// The camp's valley sky: a dome over the town, faded by `amount` (Map 1 layout pass).
// Clouds and moon ported from Binbun's sky shader (assets/BinbunSky, CC0 1.0): two
// scrolling noise layers on a plane overhead, each pushed along the ray by its own
// height (parallax depth), and a moon that the clouds cover. Night colours only.
// Target: Forward+ and Mobile. Cost: 4 texture samples per sky pixel, camp only (the
// dome fades out with `amount` as the fog closes over Pathway #0).
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never, shadows_disabled;

uniform float amount = 1.0;

group_uniforms Sky;
uniform vec3 sky_night : source_color = vec3(0.035, 0.053, 0.078);
uniform vec3 horizon_night : source_color = vec3(0.076, 0.094, 0.13);
uniform float horizon_exponent = 2.0;

group_uniforms Clouds;
// project.godot forces nearest filtering: the samplers ask for linear, or the clouds turn blocky.
uniform sampler2D cloud_tex_01 : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex_02 : filter_linear_mipmap, repeat_enable;
uniform vec3 cloud_color : source_color = vec3(0.16, 0.18, 0.22);
uniform vec2 cloud_tiling = vec2(1.0);
uniform vec2 wind_speed = vec2(0.08, 0.03);
uniform float cloud_density : hint_range(0.0, 5.0, 0.1) = 0.7;
uniform float cloud_depth = 2.0;
uniform float cloud_shape_exponent = 2.0;
uniform float cloud_occlude_exponent = 1.0;

group_uniforms Moon;
uniform vec3 moon_dir = vec3(-0.19, 0.23, 0.96);
uniform float moon_scale = 0.012;
uniform float moon_strength = 1.0;
uniform vec3 moon_color : source_color = vec3(0.62, 0.67, 0.70);

varying vec3 dir;

float get_cloud_height(sampler2D tex, vec2 uv) {
	float height = texture(tex, uv).r;
	height = clamp((height - (1.0 - cloud_density)) / cloud_density, 0.0, 1.0);
	return pow(height, cloud_shape_exponent);
}

void vertex() {
	dir = VERTEX;
}

void fragment() {
	vec3 ray = normalize(dir);
	// The cloud plane one unit overhead (t = distance to it along the ray). Rays at or
	// below the horizon get no clouds from the smoothstep below, so there is no branch.
	float t = 1.0 / max(ray.y, 0.001);
	vec3 wind = vec3(wind_speed.x, 0.0, wind_speed.y) * TIME * 0.1;
	vec3 tiling = vec3(cloud_tiling.x, 1.0, cloud_tiling.y) * 0.2;
	vec3 p1 = ray * t * tiling + wind;
	vec3 p2 = ray * t * tiling + wind * 0.5; // the second layer drifts at half speed: depth
	float h1 = get_cloud_height(cloud_tex_01, p1.xz);
	float h2 = get_cloud_height(cloud_tex_02, p2.xz);
	// Parallax: push each sample along the ray by its own height, then sample again.
	p1 += ray * h1 * cloud_depth * 0.1;
	p2 += ray * h2 * cloud_depth * 0.1;
	h1 = get_cloud_height(cloud_tex_01, p1.xz);
	h2 = get_cloud_height(cloud_tex_02, p2.xz);
	float cloud_value = min(h1, h1 * h2) * smoothstep(0.0, 0.2, ray.y);
	vec3 sky = mix(sky_night, horizon_night, pow(1.0 - abs(ray.y), horizon_exponent));
	sky = mix(sky, cloud_color, pow(cloud_value, 0.8));
	float moon_distance = clamp(1.0 - distance(ray, normalize(moon_dir)) - pow(cloud_value, cloud_occlude_exponent * 2.0), 0.0, 1.0);
	float moon_disc = smoothstep(1.0 - moon_scale, 1.0 - moon_scale * 0.9, moon_distance);
	float moon_glow = pow(moon_distance, 8.0) * 0.07;
	sky += moon_color * moon_strength * max(moon_disc, moon_glow);
	ALBEDO = sky;
	ALPHA = amount * smoothstep(-.18, .25, ray.z) * smoothstep(-.18, .04, ray.y);
}
