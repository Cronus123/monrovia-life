shader_type sky;
// Browser version of sky.gdshader (no noise clouds: quick to compile in WebGL).
// Tropical sky: gradient set by the world clock, sun disc and glow (warm at sunrise and
// sunset), moon disc and stars at night, and two drifting cloud layers that thicken and
// darken with rain. Clouds are skipped in the radiance pass (cheap ambient light).

uniform vec3 top_color : source_color = vec3(0.18, 0.44, 0.7);
uniform vec3 horizon_color : source_color = vec3(0.66, 0.8, 0.88);
uniform vec3 ground_color : source_color = vec3(0.11, 0.37, 0.53);
uniform float night = 0.0;
uniform float rain = 0.0;
uniform float sunset = 0.0;          // 0 midday .. 1 sun on the horizon
uniform float cloud_time = 0.0;


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
		float st = step(0.9965, fract(sin(dot(floor(sp), vec2(12.9898, 78.233))) * 43758.5453)) * smoothstep(0.0, 0.25, h);
		col += vec3(st) * night * (1.0 - rain) * 1.6;
	}
	COLOR = col;
}
