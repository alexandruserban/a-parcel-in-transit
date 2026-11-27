// Surface material for the textures exported from the web game (assets/textures, tools/export_textures.py).
// UVs are in metres; `tile` is the size of one texture repeat in metres, as in the web version.
// macro_mode adds the web version's low-frequency world-space tints: 1 = applyStoneMacro (paving),
// 2 = applyGroundMacro (the lawn).
// age > 0 weathers old masonry (the city wall): patchy stains, rain streaks, rising damp, moss and lichen.

#include "res://shaders/noise.gdshaderinc"

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
uniform float age = 0.0;

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
	float rough = has_rough ? texture(rough_tex, uv).g * roughness : roughness;
	if (age > 0.0) {
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float top = smoothstep(0.6, 0.9, nw.y);
		vec2 q = top > 0.5 ? wpos.xz : (abs(nw.x) > abs(nw.z) ? wpos.zy : wpos.xy);
		// broad blotches of grime and warm iron stains
		c *= mix(1.0, mix(0.6, 1.08, fbm(q * 0.12)), age);
		c = mix(c, c * vec3(1.12, 0.94, 0.74), smoothstep(0.55, 0.75, fbm(q * 0.31 + 7.3)) * 0.5 * age);
		// worn stone: darker joints and pits
		c = mix(c, c * c * 1.5, 0.35 * age);
		// rain streaks running down the face
		float streak = vnoise(vec2(q.x * 2.3, q.y * 0.08 + 3.1)) * vnoise(vec2(q.x * 7.0, q.y * 0.25));
		c *= 1.0 - smoothstep(0.22, 0.55, streak) * 0.4 * age * (1.0 - top);
		// rising damp at the foot
		float foot = 1.0 - smoothstep(0.0, 1.6 + 0.9 * vnoise(q * 0.9), wpos.y);
		c *= 1.0 - foot * 0.32 * age;
		// moss at the foot, on the tops and in damp patches; pale lichen rosettes
		float mm = fbm(q * 0.55 + 2.0) + foot * 0.32 + top * 0.3;
		float moss = smoothstep(0.6, 0.76, mm) * age;
		c = mix(c, vec3(0.19, 0.25, 0.09) * (0.65 + 0.7 * vnoise(q * 9.0)), moss * 0.85);
		float lich = smoothstep(0.7, 0.9, vnoise(q * 3.0 + 11.0)) * smoothstep(0.45, 0.65, fbm(q * 0.4 + 5.0));
		c = mix(c, c * 0.6 + vec3(0.2, 0.2, 0.14), lich * 0.45 * age * (1.0 - moss));
		rough = mix(rough, 1.0, max(moss, 0.4 * age));
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metallic;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	EMISSION = c * emission_tint * emission;
}
