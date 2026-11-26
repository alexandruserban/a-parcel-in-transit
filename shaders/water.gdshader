// Pond water: dark body with wind ripples; the sky, sun and moon come from the environment reflections.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 deep : source_color = vec3(0.04, 0.10, 0.11);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 g = vec2(cos(p.x * 1.3 + t * 1.1), cos(p.y * 1.1 + t * 0.9)) * 0.04;
	g += vec2(cos(p.x * 3.1 - p.y * 2.3 + t * 2.0), cos(p.y * 2.7 + p.x * 1.9 + t * 1.7)) * 0.02;
	g += (vec2(vnoise(p * 2.2 + vec2(t * 0.3)), vnoise(p * 2.2 - vec2(t * 0.27) + vec2(9.0))) - vec2(0.5)) * 0.1;
	vec3 wn = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = deep;
	METALLIC = 0.0;
	ROUGHNESS = 0.03;
	SPECULAR = 0.65;
}
