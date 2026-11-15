shader_type spatial;
render_mode cull_disabled, depth_draw_always;
// Ocean, lagoon and river surface: gentle swell in the vertices, small scrolling ripples
// in the normals, deep/shallow colour from the depth behind the water, white foam where
// it meets the shore, and a glossy surface for sky and screen-space reflections.
#include "res://proto3d/noise.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.52, 0.55);
uniform float swell = 0.35;
uniform float choppy = 0.0;          // rain / wind (set by the world clock)
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;

float wave(vec2 p, vec2 dir, float len, float speed) {
	return sin(dot(p, dir) * 6.2831 / len + TIME * speed);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = wave(wpos.xz, normalize(vec2(0.3, 1.0)), 38.0, 0.9) * 0.6
			+ wave(wpos.xz, normalize(vec2(-0.6, 1.0)), 23.0, 1.3) * 0.3
			+ wave(wpos.xz, normalize(vec2(1.0, 0.2)), 61.0, 0.6) * 0.4;
	VERTEX.y += h * swell * (1.0 + choppy);
	wpos.y += h * swell * (1.0 + choppy);
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	// ripple normals: two scrolling noise layers
	float e = 0.15;
	vec2 a = p * 0.55 + vec2(t * 0.16, t * 0.05);
	vec2 b = p * 1.3 + vec2(-t * 0.1, t * 0.17);
	vec2 g = vec2(vnoise(a + vec2(e, 0.0)) - vnoise(a - vec2(e, 0.0)), vnoise(a + vec2(0.0, e)) - vnoise(a - vec2(0.0, e)))
			+ vec2(vnoise(b + vec2(e, 0.0)) - vnoise(b - vec2(e, 0.0)), vnoise(b + vec2(0.0, e)) - vnoise(b - vec2(0.0, e))) * 0.6;
	g *= (1.2 + choppy * 2.0) / (2.0 * e);
	vec3 wn = normalize(vec3(-g.x * 0.12, 1.0, -g.y * 0.12));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	// how much water is behind this pixel (shore = shallow)
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -view.z / view.w;
	float water_z = -VERTEX.z;
	float depth = clamp(scene_z - water_z, 0.0, 50.0);
	float shallow = 1.0 - smoothstep(0.0, 6.0, depth);
	vec3 col = mix(deep_color, shallow_color, shallow);
	float foam_n = vnoise(p * 1.6 + vec2(t * 0.4, 0.0));
	float foam = (1.0 - smoothstep(0.0, 1.4 + foam_n, depth)) * step(0.0001, depth);
	foam = max(foam, smoothstep(0.75, 0.95, foam_n * (0.6 + choppy)) * 0.3);
	col = mix(col, vec3(0.9, 0.93, 0.92), foam * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.6, foam) + choppy * 0.08;
	METALLIC = 0.0;
	ALPHA = mix(0.72, 0.97, smoothstep(0.0, 3.0, depth)) + foam * 0.3;
	SPECULAR = 0.6;
	// a little light passing through the wave crests
	BACKLIGHT = vec3(0.05, 0.25, 0.22);
}
