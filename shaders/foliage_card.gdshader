// Alpha-cut leaf / needle cards (foliageCardMaterial in world.js). Normals point out of the crown, so the
// foliage shades as a soft volume; shadows use the same alpha cut, so they show the leaf shapes.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/wind_sway.gdshaderinc"

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.35;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = wind_sway(VERTEX, w, true, TIME);
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.85;
}
