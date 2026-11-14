shader_type spatial;
// Painted concrete walls with a grid of dark windows, worked out from world position
// (the same pattern build_city.py uses in Blender; glTF can't carry that node setup).

uniform vec4 wall_color : source_color = vec4(0.85, 0.8, 0.7, 1.0);
uniform vec4 window_color : source_color = vec4(0.11, 0.15, 0.2, 1.0);
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
	float win = band(world_pos.y, floor_height, 0.38, 0.78) * band(along, bay_width, 0.25, 0.75)
		* step(ground_floor, world_pos.y) * wall;
	ALBEDO = mix(wall_color.rgb, window_color.rgb, win);
	ROUGHNESS = mix(0.85, 0.25, win);
	SPECULAR = mix(0.3, 0.6, win);
}
