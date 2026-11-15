shader_type spatial;
render_mode cull_disabled;
// Browser version of water.gdshader: the same swell, sine ripples instead of noise, and no
// depth-texture shore tint or foam (quick to compile and cheap in WebGL).

uniform vec3 deep_color : source_color = vec3(0.04, 0.24, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.52, 0.55);
uniform float swell = 0.35;
uniform float choppy = 0.0;

varying vec3 wpos;

float wave(vec2 p, vec2 dir, float len, float speed) {
	return sin(dot(p, dir) * 6.2831 / len + TIME * speed);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = wave(wpos.xz, normalize(vec2(0.3, 1.0)), 38.0, 0.9) * 0.6
			+ wave(wpos.xz, normalize(vec2(-0.6, 1.0)), 23.0, 1.3) * 0.3
			+ wave(wpos.xz, normalize(vec2(1.0, 0.2)), 61.0, 0.6) * 0.4;
	VERTEX.y += h * swell * (1.0 + choppy);
	wpos.y += h * swell * (1.0 + choppy);
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 g = vec2(cos(p.x * 0.9 + t * 1.1) + cos((p.x + p.y) * 1.7 - t * 0.8) * 0.5,
			cos(p.y * 0.8 - t * 0.9) + cos((p.x - p.y) * 1.5 + t * 1.3) * 0.5) * (0.08 + choppy * 0.1);
	vec3 wn = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = mix(deep_color, shallow_color, 0.35);
	ROUGHNESS = 0.06 + choppy * 0.08;
	SPECULAR = 0.6;
	ALPHA = 0.9;
}
