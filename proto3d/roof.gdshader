shader_type spatial;
// Corrugated zinc roofs with rust streaks (rust = 1.0 for the old red-brown sheets).
#include "res://proto3d/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.6, 0.63, 0.66, 1.0);
uniform float rust = 0.0;
uniform float metal = 0.5;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float ridge = 0.5 + 0.5 * sin(p.x * 9.0);
	float r = smoothstep(0.35, 0.8, fbm(vec2(p.x * 0.7, p.y * 0.15)) + rust * 0.35);
	vec3 col = mix(base_color.rgb, vec3(0.45, 0.22, 0.1), r * (0.55 + rust * 0.4));
	ALBEDO = col * (0.85 + ridge * 0.2);
	METALLIC = metal * (1.0 - r);
	ROUGHNESS = mix(0.4, 0.9, r);
}
