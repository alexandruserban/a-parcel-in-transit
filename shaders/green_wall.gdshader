// Vine-covered wall: a sheet of overlapping grape leaves drawn on a quad laid over the wall face. UVs are in
// metres (x along the wall, -y up). Every 17 cm cell holds one leaf (some cells empty on the sparser front
// layer) at a random offset, size and tilt; the leaf with the highest random "order" among the neighbours is on
// top, the ones behind are darker. The cover thins out towards an uneven top edge and leaves a few bare patches.
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/noise.gdshaderinc"

uniform float density = 1.0;     // share of cells that hold a leaf
uniform float layer_seed = 0.0;
uniform float shade = 1.0;
uniform float top_y = 8.55;      // height of the wall top above the ground

float leaf_sdf(vec2 p) {
	vec2 q = p - vec2(0.0, 0.06);
	float d = length(q);
	float phi = atan(q.x, q.y);
	float lobe = 0.5 + 0.5 * cos(5.0 * phi);
	float R = 0.27 + 0.17 * pow(lobe, 1.6) + 0.014 * cos(phi * 36.0);
	R *= 1.0 - 0.8 * smoothstep(2.7, 3.1, abs(phi));
	return d - R;
}

vec2 rot2(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x + s * p.y, -s * p.x + c * p.y); }

void fragment() {
	vec2 p = vec2(UV.x, -UV.y);
	float cell = 0.17;
	vec2 gi = floor(p / cell);
	float best = -1.0;
	float bd = 0.0;
	vec2 blp = vec2(0.0);
	vec2 bc = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = gi + vec2(float(x), float(y));
			if (hash12(c * 1.7 + layer_seed * 13.1 + 3.1) > density) continue;
			vec2 h = hash22(c + layer_seed * 17.0);
			vec2 centre = (c + 0.15 + 0.7 * h) * cell;
			float ang = (hash12(c + 9.1 + layer_seed) - 0.5) * 2.2;
			float size = cell * (1.3 + 0.7 * hash12(c + 5.3));
			vec2 lp = rot2(p - centre, ang) / size;
			float d = leaf_sdf(lp);
			float order = hash12(c + 7.7 + layer_seed * 3.0);
			if (d < 0.0 && order > best) {
				best = order;
				bd = d;
				blp = lp;
				bc = c;
			}
		}
	}
	// cover: thick at the foot, an uneven top edge, a few bare patches higher up
	float edge = top_y - 0.1 - 1.6 * pow(vnoise(vec2(p.x * 0.3 + layer_seed * 5.0, 1.0)), 2.0) - 0.5 * vnoise(vec2(p.x * 1.3, 7.0));
	float bare = fbm(p * 0.35 + vec2(layer_seed * 7.0, 2.0));
	bool keep = best >= 0.0 && p.y < edge && bare > 0.3 + 0.12 * smoothstep(2.0, 7.0, p.y);
	vec3 dark = vec3(0.035, 0.09, 0.02);
	vec3 mid = vec3(0.09, 0.2, 0.035);
	vec3 light = vec3(0.17, 0.3, 0.06);
	float hc = hash12(bc + 2.2);
	vec3 col = hc < 0.5 ? mix(dark, mid, hc * 2.0) : mix(mid, light, hc * 2.0 - 1.0);
	if (hash12(bc + 4.4) < 0.06) col = vec3(0.32, 0.3, 0.06);     // a leaf turning yellow
	col *= mix(0.55, 1.05, best);                                   // leaves further back are in shade
	col *= 0.78 + 0.22 * smoothstep(0.0, -0.12, bd);               // darker at the rim
	float phi = atan(blp.x, blp.y - 0.06);
	float off = abs(fract(phi * 5.0 / 6.2831853 + 0.5) - 0.5) * 6.2831853 / 5.0 * length(blp - vec2(0.0, 0.06));
	col = mix(col, col * 1.5 + vec3(0.02, 0.03, 0.0), (1.0 - smoothstep(0.006, 0.016, off)) * 0.5);
	col *= mix(0.85, 1.0, smoothstep(0.0, 1.5, p.y));               // damp shade at the foot
	ALBEDO = col * shade;
	ALPHA = keep ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.65;
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.35;
}
