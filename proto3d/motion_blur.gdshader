shader_type canvas_item;
// Radial blur toward the screen edges, used as subtle motion blur when driving fast.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5, 0.55);
	float edge = smoothstep(0.12, 0.6, length(dir));
	vec3 c = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		c += textureLod(screen_tex, uv - dir * amount * edge * float(i), 0.0).rgb;
	}
	COLOR = vec4(c / 8.0, 1.0);
}
