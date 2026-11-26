// Sandstone slab pavements: staggered courses of rectangular slabs in world space.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform vec2 slab_size = vec2(0.75, 0.5);
uniform vec3 sand_a : source_color = vec3(0.71, 0.64, 0.53);
uniform vec3 sand_b : source_color = vec3(0.60, 0.53, 0.44);
uniform vec3 joint : source_color = vec3(0.30, 0.27, 0.23);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 col;
	float rough = 0.92;
	if (abs(wnorm.y) > 0.5) {
		vec2 p = wpos.xz / slab_size;
		float row = floor(p.y);
		p.x += 0.5 * mod(row, 2.0) + 0.23 * hash12(vec2(row, 7.0));
		vec2 cell = floor(p);
		vec2 f = fract(p);
		float e = min(min(f.x, 1.0 - f.x) * slab_size.x, min(f.y, 1.0 - f.y) * slab_size.y);
		float s = smoothstep(0.004, 0.014, e);
		float id = hash12(cell);
		col = mix(sand_a, sand_b, id) * (0.9 + 0.18 * vnoise(wpos.xz * 7.0)) * (0.88 + 0.22 * fbm(wpos.xz * 0.06));
		col = mix(joint, col, s);
		rough = mix(1.0, 0.88, s);
	} else {
		col = sand_b * 0.85;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
