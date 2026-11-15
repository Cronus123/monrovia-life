shader_type spatial;
// Browser version of city_surfaces.gdshader: same uniforms (the world clock sets them the
// same way), same tile colours and window grid, but no procedural noise or surface
// relief. Browsers (WebGL through ANGLE on Windows) take many seconds to compile the full
// shader for each light setup the first time a page loads; this one compiles quickly.
// 0 ground, 1 road, 2 paving, 3 wall, 4 roof, 5 plain.

uniform int kind = 0;
uniform float floor_height = 3.2;
uniform float bay_width = 2.6;
uniform float night_windows = 0.0;
uniform float wetness = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = pow(COLOR.rgb, vec3(2.2));      // tile colours are authored in sRGB
	float rough = 0.9;
	if (kind == 1) {
		// asphalt: darker and shinier when wet
		col *= 1.0 - wetness * 0.35;
		rough = mix(0.85, 0.32, wetness * 0.7);
	} else if (kind == 2) {
		// paving: slab joints
		vec2 g = fract(world_pos.xz / 1.2);
		float joint = 1.0 - step(0.04, g.x) * step(0.04, g.y);
		col *= 1.0 - joint * 0.18 - wetness * 0.25;
		rough = mix(0.85, 0.3, wetness);
	} else if (kind == 3) {
		// walls: a window per bay and floor, lit at night
		float wall = 1.0 - step(0.5, abs(world_normal.y));
		float along = abs(world_normal.x) > abs(world_normal.z) ? world_pos.z : world_pos.x;
		float fy = fract(world_pos.y / floor_height);
		float fx = fract(along / bay_width);
		float win = step(0.38, fy) * step(fy, 0.78) * step(0.28, fx) * step(fx, 0.72) * wall
			* step(1.2, world_pos.y - floor(world_pos.y / 400.0));
		col = mix(col, vec3(0.05, 0.06, 0.07), win * 0.85);
		rough = mix(0.9, 0.2, win);
		EMISSION = vec3(1.0, 0.78, 0.45) * win * night_windows * 0.8;
	} else if (kind == 4) {
		// roofs: corrugation stripes
		float s = sin(dot(world_pos.xz, vec2(0.7, 0.7)) * 9.0) * 0.5 + 0.5;
		col *= 0.92 + s * 0.08;
		rough = 0.6 - wetness * 0.25;
	}
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
}
