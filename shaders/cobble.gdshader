// Granite setts for the old-town streets and squares: cellular stones in world space with rounded tops and dark joints.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform float scale = 6.5;            // stones per metre
uniform float jitter = 0.5;
uniform vec3 stone_a : source_color = vec3(0.42, 0.41, 0.39);
uniform vec3 stone_b : source_color = vec3(0.29, 0.28, 0.27);
uniform vec3 joint : source_color = vec3(0.15, 0.14, 0.13);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec2 p = (abs(wnorm.y) > 0.5 ? wpos.xz : wpos.xy + wpos.zy) * scale;
	vec2 c;
	float id;
	vec2 f = voronoi(p, jitter, c, id);
	float edge = f.y - f.x;
	float stone = smoothstep(0.05, 0.16, edge);
	vec3 col = mix(stone_a, stone_b, id);
	col *= 0.86 + 0.26 * vnoise(wpos.xz * 11.0);
	col *= 0.82 + 0.3 * fbm(wpos.xz * 0.045);
	col = mix(joint, col, stone);
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.76, stone);
	AO = mix(0.55, 1.0, stone);
	AO_LIGHT_AFFECT = 0.35;
	if (abs(wnorm.y) > 0.5) {
		// Rounded stone tops: tilt the normal away from each stone's centre
		vec3 wn = normalize(vec3(-c.x * 0.55 * stone, 1.0, -c.y * 0.55 * stone));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
}
