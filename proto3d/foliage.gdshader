shader_type spatial;
render_mode cull_disabled;
// Palm fronds, bushes, tree canopies and grass tufts. Vertex colour = leaf colour (sRGB),
// vertex alpha = how much that vertex moves in the wind (0 at the stem, 1 at the tip).
// Meshes are in world space (tiles aren't moved), grass is instanced.
#include "res://proto3d/noise.gdshaderinc"

uniform float wind = 1.0;            // set by the world clock (stronger in rain)
uniform vec2 wind_dir = vec2(0.8, 0.6);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = COLOR.a;
	float gust = 0.6 + 0.8 * vnoise(wp.xz * 0.02 + vec2(TIME * 0.15, 0.0));
	float sway = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.21) * 0.6 + sin(TIME * 3.1 + wp.x * 0.9) * 0.25;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * (sway + 0.6) * gust * wind * w * 0.22;
	off.y -= abs(sway) * w * 0.05 * wind;
	// back into the instance/mesh space
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c * (0.85 + 0.3 * COLOR.a);
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.6;      // sunlight through the leaves
}
