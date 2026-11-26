// Lawn over the valley floor: world-space colour variation so the ground never shows a tiling pattern.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 grass_dark : source_color = vec3(0.23, 0.36, 0.13);
uniform vec3 grass_light : source_color = vec3(0.40, 0.52, 0.20);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.53, 0.30);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float macro = fbm(p * 0.018);
	float mid = fbm(p * 0.22 + vec2(5.0, 3.0));
	float fine = vnoise(p * 7.0);
	float blades = vnoise(p * vec2(38.0, 31.0));
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.25, 0.75, macro));
	col = mix(col, grass_dry, smoothstep(0.55, 0.85, mid) * 0.45);
	col *= 0.82 + 0.22 * fine + 0.14 * blades;
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.3;
}
