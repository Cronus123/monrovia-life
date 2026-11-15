shader_type sky;
// Tropical sky: gradient set by the world clock, sun disc and glow (warm at sunrise and
// sunset), moon disc and stars at night, and two drifting cloud layers that thicken and
// darken with rain. Clouds are skipped in the radiance pass (cheap ambient light).
#include "res://proto3d/noise.gdshaderinc"

uniform vec3 top_color : source_color = vec3(0.18, 0.44, 0.7);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.8, 0.88);
uniform vec3 ground_color : source_color = vec3(0.11, 0.37, 0.53);
uniform float night = 0.0;
uniform float rain = 0.0;
uniform float sunset = 0.0;          // 0 midday .. 1 sun on the horizon
uniform float cloud_time = 0.0;

float clouds(vec2 p, float cover) {
	float n = fbm(p) * 0.65 + fbm(p * 2.3 + 5.0) * 0.35;
	return smoothstep(1.0 - cover, 1.0 - cover + 0.32, n);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.55));
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	vec3 L = LIGHT0_DIRECTION;
	float cosang = dot(d, L);
	float above = smoothstep(-0.05, 0.02, L.y);
	// sun (by day) / moon (night: the key light is moonlight)
	vec3 sun_col = mix(vec3(1.0, 0.92, 0.75), vec3(1.0, 0.5, 0.22), sunset);
	float disc = smoothstep(0.9995, 0.99975, cosang) * above;
	float halo = pow(max(cosang, 0.0), 12.0) * 0.35 + pow(max(cosang, 0.0), 160.0) * 0.6;
	vec3 sky_sun = sun_col * (disc * 18.0 + halo * (1.0 + sunset * 1.5)) * (1.0 - rain * 0.85);
	vec3 moon = vec3(0.85, 0.9, 1.0) * (smoothstep(0.99955, 0.9997, cosang) * 2.5 + pow(max(cosang, 0.0), 300.0) * 0.3) * above;
	col += mix(sky_sun, moon, night);
	// sunset band along the horizon toward the sun
	col += vec3(1.0, 0.42, 0.15) * sunset * (1.0 - night) * pow(1.0 - abs(h), 6.0) * (0.4 + 0.6 * max(dot(normalize(d.xz + 0.0001), normalize(L.xz + 0.0001)), 0.0)) * 0.7;
	// stars
	if (h > 0.0 && night > 0.01) {
		vec2 sp = d.xz / (h + 0.3) * 160.0;
		float st = step(0.9965, hash12(floor(sp))) * smoothstep(0.0, 0.25, h);
		col += vec3(st) * night * (1.0 - rain) * 1.6;
	}
	if (!AT_CUBEMAP_PASS && h > 0.0) {
		vec2 cp = d.xz / (h + 0.12);
		float cover = mix(0.42, 0.85, rain);
		float c1 = clouds(cp * 1.2 + vec2(cloud_time * 0.012, cloud_time * 0.004), cover);
		float c2 = clouds(cp * 0.55 + vec2(cloud_time * 0.006, -cloud_time * 0.002) + 11.0, cover * 0.85) * 0.7;
		float c = max(c1, c2) * smoothstep(0.0, 0.18, h);
		float lit = clamp(0.55 + 0.45 * max(cosang, 0.0), 0.0, 1.0);
		vec3 cday = mix(vec3(1.0, 0.98, 0.95), vec3(0.52, 0.55, 0.58), rain) * lit;
		cday = mix(cday, vec3(1.0, 0.55, 0.32) * lit, sunset * 0.7);
		vec3 cnight = vec3(0.07, 0.09, 0.14) + moon * 0.1;
		vec3 ccol = mix(cday, cnight, night);
		col = mix(col, ccol, c * 0.92);
	}
	COLOR = col;
}
