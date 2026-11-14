shader_type spatial;
// Worn asphalt: patchy tone, fine grit, darker oil stains down the lane centres.
#include "res://proto3d/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.25, 0.26, 0.28, 1.0);
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float patches = fbm(p * 0.08);
	float grit = hash12(floor(p * 18.0));
	vec3 col = base_color.rgb * (0.82 + patches * 0.32) * (0.94 + grit * 0.12);
	col = mix(col, vec3(0.12, 0.12, 0.13), smoothstep(0.62, 0.8, fbm(p * 0.35 + 5.0)) * 0.35);
	ALBEDO = col;
	ROUGHNESS = 0.85 - patches * 0.2;
	SPECULAR = 0.35;
}
