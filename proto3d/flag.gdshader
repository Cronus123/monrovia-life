shader_type spatial;
render_mode cull_disabled;
// Flag waving in the sea breeze. Left edge (UV.x = 0) is fixed to the pole.
uniform sampler2D flag : source_color, filter_linear_mipmap;

void vertex() {
	float t = UV.x;
	VERTEX.z += sin(TIME * 4.0 - VERTEX.x * 2.5) * 0.14 * t;
	VERTEX.y += sin(TIME * 2.6 - VERTEX.x * 1.7) * 0.05 * t;
}

void fragment() {
	ALBEDO = texture(flag, UV).rgb;
	ROUGHNESS = 0.9;
}
