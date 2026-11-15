shader_type spatial;
// One shader for the generated 1:1 city tiles. Base colours come from the tile's vertex
// colours (painted walls, roofs, asphalt, laterite, sand...); `kind` adds the detail:
// 0 ground, 1 road, 2 paving (sidewalk), 3 wall (windows, weathering, contact shading),
// 4 roof (corrugation, rust), 5 plain (props, low-detail tiles).
#include "res://proto3d/noise.gdshaderinc"

uniform int kind = 0;
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;
uniform float night_windows = 0.0;   // 0 by day, ~1.5 at night (set by the world clock)

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
	vec3 base = pow(COLOR.rgb, vec3(2.2));     // tile colours are authored in sRGB
	vec2 p = world_pos.xz;
	vec3 col = base;
	float rough = 0.9;
	float spec = 0.3;
	if (kind == 0) {
		col *= 0.88 + fbm(p * 0.12) * 0.26;
	} else if (kind == 1) {
		float patches = fbm(p * 0.08);
		col *= (0.82 + patches * 0.32) * (0.94 + hash12(floor(p * 18.0)) * 0.12);
		rough = 0.85 - patches * 0.2;
	} else if (kind == 2) {
		vec2 g = abs(fract(p / 1.5) - 0.5);
		float joint = step(0.47, max(g.x, g.y)) * step(0.5, world_normal.y);
		col *= (0.9 + hash12(floor(p / 1.5)) * 0.14);
		col = mix(col, col * 0.62, joint);
	} else if (kind == 3) {
		float wall = 1.0 - step(0.5, abs(world_normal.y));
		float along = abs(world_normal.x) > abs(world_normal.z) ? world_pos.z : world_pos.x;
		// windows start one storey above the local ground: use height within the building
		float hgt = world_pos.y - floor(world_pos.y / 400.0) * 400.0;
		// window = frame (painted surround) + recessed glass: the top of the recess is in
		// the lintel's shadow and the glass shows louvre / burglar-bar lines
		float fy = fract(hgt / floor_height);
		float fx = fract(along / bay_width);
		float frame = band(hgt, floor_height, 0.34, 0.82) * band(along, bay_width, 0.21, 0.79) * wall;
		float win = band(hgt, floor_height, 0.38, 0.78) * band(along, bay_width, 0.25, 0.75) * wall;
		float lintel = smoothstep(0.78, 0.66, fy);
		float side = smoothstep(0.25, 0.3, fx) * smoothstep(0.75, 0.7, fx);
		float bars = step(0.9, fract(along * 8.0)) * 0.6;
		float lit = step(0.72, hash12(floor(vec2(along / bay_width, world_pos.y / floor_height)) + 3.1));
		float streak = smoothstep(0.55, 0.9, vnoise(vec2(along * 1.3, world_pos.y * 0.12))) * wall;
		col *= 1.0 - streak * 0.18;
		col = mix(col, col * 1.18 + 0.03, frame - win);
		vec3 glass = vec3(0.1, 0.13, 0.17) * (0.45 + 0.55 * lintel * side);
		glass = mix(glass, glass * 0.4, bars);
		col = mix(col, glass, win);
		EMISSION = vec3(1.0, 0.78, 0.45) * win * lit * (1.0 - bars) * night_windows * lintel;
		rough = mix(0.88, 0.15, win);
		spec = mix(0.3, 0.75, win);	} else if (kind == 4) {
		float ridge = 0.5 + 0.5 * sin(p.x * 9.0);
		float r = smoothstep(0.45, 0.85, fbm(vec2(p.x * 0.7, p.y * 0.15)));
		col = mix(col, vec3(0.45, 0.22, 0.1), r * 0.5) * (0.85 + ridge * 0.2);
		rough = mix(0.45, 0.9, r);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
