// Tree crowns (MultiMesh, colour per instance) that sway in the wind.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform float sway = 0.05;

varying vec3 lpos;

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float w = sin(TIME * 1.2 + o.x * 0.13 + o.z * 0.11) + 0.4 * sin(TIME * 2.7 + o.x * 0.31 + o.z * 0.2);
	float h = max(VERTEX.y + 1.0, 0.0);
	VERTEX.x += w * sway * h;
	VERTEX.z += w * 0.5 * sway * h;
	lpos = VERTEX;
}

void fragment() {
	float clumps = vnoise(lpos.xz * 3.5 + vec2(lpos.y * 2.0));
	float leaves = vnoise(lpos.xy * 14.0 + lpos.zx * 9.0);
	vec3 col = COLOR.rgb * (0.62 + 0.38 * clumps) * (0.85 + 0.25 * leaves);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.5;
}
