shader_type spatial;
// Concrete paving: 1.5 m slabs with dark joints, stains and slight tone changes.
#include "res://proto3d/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.66, 0.64, 0.6, 1.0);
uniform float slab = 1.5;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 g = abs(fract(p / slab) - 0.5);
	float joint = step(0.47, max(g.x, g.y)) * step(0.5, world_normal.y);
	float cell = hash12(floor(p / slab));
	float stain = smoothstep(0.55, 0.85, fbm(p * 0.6));
	vec3 col = base_color.rgb * (0.9 + cell * 0.14) * (1.0 - stain * 0.25);
	col = mix(col, col * 0.62, joint);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
