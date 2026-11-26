// Tree crowns (MultiMesh, colour per instance) that sway in the wind.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform float sway = 0.05;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

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
	// The web game's foliage texture for the leaf detail, the instance colour for the tree's tint
	vec3 t = texture(leaf_tex, vec2(lpos.x + lpos.z, lpos.y) * 0.55).rgb;
	float lum = dot(t, vec3(0.3, 0.59, 0.11));
	float clumps = vnoise(lpos.xz * 3.5 + vec2(lpos.y * 2.0));
	vec3 col = COLOR.rgb * lum * 2.6 * (0.75 + 0.35 * clumps);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
	BACKLIGHT = col * 0.5;
}
