shader_type spatial;
// One shader for the generated 1:1 city tiles. Base colours come from the tile's vertex
// colours (painted walls, roofs, asphalt, laterite, sand...); `kind` adds the detail,
// all procedural (no texture files), with surface relief as normal perturbation:
// 0 ground (lumpy laterite/grass), 1 road (worn asphalt, patches, potholes, puddles when
// wet), 2 paving (slab joints), 3 wall (rough plaster, framed recessed windows, lit at
// night), 4 roof (corrugated sheet, rust), 5 plain (props, low-detail tiles).
#include "res://proto3d/noise.gdshaderinc"

uniform int kind = 0;
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;
uniform float night_windows = 0.0;   // 0 by day, ~1.5 at night (set by the world clock)
uniform float wetness = 0.0;         // 0 dry .. 1 soaked (rain; set by the world clock)

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

// gradient of a value-noise height field (central differences)
vec2 grad(vec2 p, float e) {
	return vec2(vnoise(p + vec2(e, 0.0)) - vnoise(p - vec2(e, 0.0)),
			vnoise(p + vec2(0.0, e)) - vnoise(p - vec2(0.0, e))) / (2.0 * e);
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));     // tile colours are authored in sRGB
	vec2 p = world_pos.xz;
	vec3 col = base;
	vec3 wn = world_normal;
	float rough = 0.9;
	float spec = 0.3;
	float up = step(0.5, world_normal.y);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(40.0, 90.0, dist);       // relief fades out with distance
	if (kind == 0) {
		col *= 0.88 + fbm(p * 0.12) * 0.26;
		vec2 g = grad(p * 1.7, 0.08) * 0.12 + grad(p * 0.35, 0.2) * 0.12;
		wn = normalize(wn - vec3(g.x, 0.0, g.y) * up * near);
		float puddle = smoothstep(0.62, 0.7, fbm(p * 0.09 + 4.0)) * wetness;
		col *= 1.0 - wetness * 0.3 - puddle * 0.25;
		rough = mix(0.95, 0.08, puddle) - wetness * 0.25;
		wn = normalize(mix(wn, world_normal, puddle));
	} else if (kind == 1) {
		float patches = fbm(p * 0.08);
		col *= (0.82 + patches * 0.32) * (0.94 + hash12(floor(p * 18.0)) * 0.12);
		// repair patches: darker rectangles of fresher asphalt
		vec2 cell = floor(p / 7.0);
		float hp = hash12(cell + 9.1);
		vec2 f = abs(fract(p / 7.0) - 0.5);
		float patch = step(0.78, hp) * step(max(f.x, f.y), 0.18 + hp * 0.15);
		col = mix(col, col * 0.62, patch);
		// potholes: a few deep, rough holes, worse on poor roads (lighter vertex colour)
		float hole_n = vnoise(p * 0.45 + 31.0);
		float hole = smoothstep(0.86, 0.9, hole_n) * near;
		col = mix(col, vec3(0.05, 0.045, 0.04), hole * 0.8);
		vec2 hg = grad(p * 0.45 + 31.0, 0.05) * 0.45;
		vec2 g = grad(p * 3.0, 0.05) * 0.06;                 // fine aggregate
		wn = normalize(wn + vec3(hg.x, 0.0, hg.y) * hole * 3.0 * up - vec3(g.x, 0.0, g.y) * near * up);
		// rain: darker, glossy road; puddles collect in the dips and the potholes
		float puddle = max(smoothstep(0.6, 0.68, fbm(p * 0.11 + 2.0)), smoothstep(0.84, 0.88, hole_n)) * wetness;
		rough = mix(0.85 - patches * 0.2, 0.32, wetness * 0.7);
		rough = mix(rough, 0.03, puddle);
		col *= 1.0 - wetness * 0.35;
		col = mix(col, col * 0.55, puddle);
		spec = mix(0.3, 0.6, wetness);
		wn = normalize(mix(wn, world_normal, puddle));
	} else if (kind == 2) {
		vec2 g = abs(fract(p / 1.5) - 0.5);
		float joint = step(0.47, max(g.x, g.y)) * up;
		col *= (0.9 + hash12(floor(p / 1.5)) * 0.14);
		col = mix(col, col * 0.62, joint);
		// slabs slightly tilted, joints sunk
		vec2 tilt = (vec2(hash12(floor(p / 1.5) + 1.7), hash12(floor(p / 1.5) + 5.3)) - 0.5) * 0.08;
		vec2 jg = sign(fract(p / 1.5) - 0.5) * step(0.44, g) * 0.4;
		wn = normalize(wn + vec3(tilt.x + jg.x, 0.0, tilt.y + jg.y) * up * near);
		rough = mix(0.85, 0.3, wetness);
		col *= 1.0 - wetness * 0.25;
	} else if (kind == 3) {
		float wall = 1.0 - step(0.5, abs(world_normal.y));
		bool xn = abs(world_normal.x) > abs(world_normal.z);
		float along = xn ? world_pos.z : world_pos.x;
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
		spec = mix(0.3, 0.75, win);
		// rough plaster relief, and the frame edges catching light
		vec3 t = normalize(cross(vec3(0.0, 1.0, 0.0), world_normal + vec3(0.0001)));
		vec2 g = grad(vec2(along, world_pos.y) * 2.5, 0.06) * 0.08 * near * (1.0 - win);
		wn = normalize(wn - t * g.x * wall - vec3(0.0, 1.0, 0.0) * g.y * wall);
		wn = normalize(wn + vec3(0.0, -0.5, 0.0) * (frame - win) * near * step(0.7, fy));   // sill top faces up
	} else if (kind == 4) {
		float ridge = 0.5 + 0.5 * sin(p.x * 9.0);
		float r = smoothstep(0.45, 0.85, fbm(vec2(p.x * 0.7, p.y * 0.15)));
		col = mix(col, vec3(0.45, 0.22, 0.1), r * 0.5) * (0.85 + ridge * 0.2);
		rough = mix(0.45, 0.9, r) - wetness * 0.25;
		spec = 0.45;
		// corrugations as relief
		wn = normalize(wn + vec3(cos(p.x * 9.0) * 0.35 * near, 0.0, 0.0));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = spec;
}
