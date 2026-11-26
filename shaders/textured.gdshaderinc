// Surface material for the textures exported from the web game (assets/textures, tools/export_textures.py).
// UVs are in metres; `tile` is the size of one texture repeat in metres, as in the web version.
// macro_mode adds the web version's low-frequency world-space tints: 1 = applyStoneMacro (paving),
// 2 = applyGroundMacro (the lawn).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 tile = vec2(1.0);
uniform vec3 tint : source_color = vec3(1.0);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform float normal_depth = 1.0;
uniform bool has_normal = false;
uniform bool has_rough = false;
uniform int macro_mode = 0;
uniform float emission = 0.0;
uniform vec3 emission_tint : source_color = vec3(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV / tile;
	vec3 c = texture(albedo_tex, uv).rgb * tint;
	if (macro_mode == 1) {
		vec4 m = texture(macro_tex, wpos.xz / 45.0);
		c *= mix(0.82, 1.12, m.r);
		c = mix(c, c * vec3(1.08, 1.0, 0.88), smoothstep(0.55, 0.85, m.g) * 0.6);
	} else if (macro_mode == 2) {
		vec4 m = texture(macro_tex, wpos.xz / 600.0 + vec2(0.5));
		c *= mix(0.72, 1.18, m.r);
		c = mix(c, c * vec3(1.25, 1.08, 0.62), smoothstep(0.62, 0.9, m.g) * 0.7);
	}
	ALBEDO = c;
	ROUGHNESS = has_rough ? texture(rough_tex, uv).g * roughness : roughness;
	METALLIC = metallic;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	EMISSION = c * emission_tint * emission;
}
