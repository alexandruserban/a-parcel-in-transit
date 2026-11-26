// Clay (or slate) roof tiles. UVs are in metres: u along the eave, v up the slope.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.62, 0.30, 0.20);
uniform vec2 tile = vec2(0.24, 0.3);
uniform float variation = 0.22;

void fragment() {
	vec2 p = UV / tile;
	float row = floor(p.y);
	p.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float id = hash12(cell);
	vec3 col = albedo * (1.0 - variation * 0.5 + variation * id);
	col *= 0.85 + 0.25 * fbm(UV * 0.35 + vec2(id * 0.1));          // weathering patches
	float lip = smoothstep(0.0, 0.28, 1.0 - f.y);                  // shadow under the tile above
	float gap = smoothstep(0.0, 0.06, min(f.x, 1.0 - f.x));
	col *= mix(0.55, 1.0, lip) * mix(0.7, 1.0, gap);
	if (!FRONT_FACING) col *= 0.45;                                // underside of the eaves
	ALBEDO = col;
	ROUGHNESS = 0.82;
}
