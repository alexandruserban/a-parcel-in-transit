// Tree bark (getBarkMaterial in world.js): the bark texture, swaying with the leaves.
shader_type spatial;
#include "res://shaders/wind_sway.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 tile = vec2(1.0, 3.0);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = wind_sway(VERTEX, w, false, TIME);
}

void fragment() {
	vec2 uv = UV / tile;
	ALBEDO = texture(albedo_tex, uv).rgb;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = 0.95;
}
