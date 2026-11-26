// House and town walls. mode 0: lime plaster with mottling and grime at the foot.
// mode 1: ashlar (dressed stone courses), used for Gothic houses, the church and the city wall.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.9, 0.86, 0.78);
uniform int mode = 0;
uniform vec2 block = vec2(0.9, 0.42);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(wnorm);
	vec2 q = abs(n.x) > abs(n.z) ? wpos.zy : wpos.xy;
	if (abs(n.y) > 0.6) q = wpos.xz;
	vec3 col = albedo * (0.9 + 0.16 * fbm(q * 1.1));
	col *= 0.94 + 0.08 * vnoise(q * 16.0);
	col *= mix(0.74, 1.0, smoothstep(0.0, 1.1, wpos.y));      // splash grime at the foot of the wall
	float rough = 0.94;
	if (mode == 1) {
		vec2 b = q / block;
		float row = floor(b.y);
		b.x += 0.5 * mod(row, 2.0) + 0.3 * hash12(vec2(row, 1.0));
		vec2 f = fract(b);
		vec2 cell = floor(b);
		float e = min(min(f.x, 1.0 - f.x) * block.x, min(f.y, 1.0 - f.y) * block.y);
		float s = smoothstep(0.006, 0.022, e);
		col *= 0.84 + 0.26 * hash12(cell + vec2(3.0, 5.0));
		col = mix(col * 0.55, col, s);
		rough = 0.9;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
