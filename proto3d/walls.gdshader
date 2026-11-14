shader_type spatial;
// Painted concrete walls with a grid of windows (the pattern build_city.py uses in
// Blender; glTF can't carry that node setup), plus faded paint per building, rain
// streaks, and darkening near the ground in place of ambient occlusion (the
// Compatibility renderer has no SSAO).
#include "res://proto3d/noise.gdshaderinc"

uniform vec4 wall_color : source_color = vec4(0.85, 0.8, 0.7, 1.0);
uniform vec4 window_color : source_color = vec4(0.11, 0.15, 0.2, 1.0);
uniform vec4 frame_color : source_color = vec4(0.92, 0.9, 0.85, 1.0);
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;
uniform float ground_floor = 1.2;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float band(float v, float period, float lo, float hi) {
	float f = fract(v / period);
	return step(lo, f) * step(f, hi);
}

void fragment() {
	float wall = 1.0 - step(0.5, abs(world_normal.y));          // vertical faces only
	float along = abs(world_normal.x) > abs(world_normal.z) ? world_pos.z : world_pos.x;
	float above = step(ground_floor, world_pos.y);
	float win = band(world_pos.y, floor_height, 0.38, 0.78) * band(along, bay_width, 0.25, 0.75) * above * wall;
	float frame = band(world_pos.y, floor_height, 0.33, 0.83) * band(along, bay_width, 0.2, 0.8) * above * wall * (1.0 - win);
	// per-building tint (roughly one cell per block) and weathering
	float cell = hash12(floor(world_pos.xz / 9.0));
	vec3 paint = wall_color.rgb * (0.86 + cell * 0.22);
	float streak = smoothstep(0.55, 0.9, vnoise(vec2(along * 1.3, world_pos.y * 0.12))) * wall;
	paint *= 1.0 - streak * 0.18;
	// contact shadow near the ground
	float ao = mix(0.55, 1.0, smoothstep(0.1, 2.2, world_pos.y));
	vec3 col = mix(paint, frame_color.rgb, frame * 0.8);
	col = mix(col, window_color.rgb, win);
	ALBEDO = col * mix(1.0, ao, wall);
	ROUGHNESS = mix(0.88, 0.2, win);
	SPECULAR = mix(0.3, 0.7, win);
}
