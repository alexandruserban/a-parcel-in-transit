// Renaissance picture tiles for house fronts: a majolica panel (tin-glazed tiles painted in cobalt, ochre,
// yellow, green and manganese) with an ornamental border. Each motif is drawn with signed distance shapes in
// panel space, then split into glossy 15 cm tiles with grout lines and a fine craquelure.
// motif 0 Madonna and Child, 1 profile portrait, 2 coat of arms in a laurel wreath, 3 caravel at sea,
// 4 grotesque candelabrum, 5 Tuscan landscape with a hill town.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

uniform int motif = 0;
uniform float aspect = 0.75;          // panel width / height
uniform vec2 size_m = vec2(0.9, 1.2); // panel size in metres (for the tile grid)
uniform float tile_m = 0.15;
uniform bool has_normal = true;       // tells the batch to generate tangents (the tile bevels use NORMAL_MAP)

const vec3 WHITE = vec3(0.95, 0.93, 0.86);
const vec3 BLUE = vec3(0.12, 0.24, 0.58);
const vec3 LBLUE = vec3(0.48, 0.64, 0.86);
const vec3 YELLOW = vec3(0.96, 0.78, 0.26);
const vec3 OCHRE = vec3(0.84, 0.5, 0.16);
const vec3 GREEN = vec3(0.3, 0.54, 0.24);
const vec3 DGREEN = vec3(0.16, 0.34, 0.16);
const vec3 INK = vec3(0.2, 0.14, 0.24);
const vec3 RED = vec3(0.72, 0.22, 0.15);
const vec3 SKIN = vec3(0.97, 0.83, 0.69);
const vec3 BROWN = vec3(0.48, 0.28, 0.13);

float fill(float d, float aa) { return 1.0 - smoothstep(-aa, aa, d); }
vec3 lay(vec3 col, vec3 c, float d, float aa) { return mix(col, c, fill(d, aa)); }
vec3 inked(vec3 col, vec3 c, float d, float aa, float w) {
	col = mix(col, c, fill(d, aa));
	return mix(col, INK, fill(abs(d) - w, aa));
}
float sd_circle(vec2 p, float r) { return length(p) - r; }
float sd_box(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }
float sd_ellipse(vec2 p, vec2 ab) { return (length(p / ab) - 1.0) * min(ab.x, ab.y); }
float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a, ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
float sd_tri(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
	vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
	vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
	vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
	vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
	float s = sign(e0.x * e2.y - e0.y * e2.x);
	vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
		vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
		vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
	return -sqrt(d.x) * sign(d.y);
}
float sd_trap(vec2 p, float r1, float r2, float he) {   // bottom half width r1, top r2, half height he
	vec2 k1 = vec2(r2, he);
	vec2 k2 = vec2(r2 - r1, 2.0 * he);
	p.x = abs(p.x);
	vec2 ca = vec2(p.x - min(p.x, (p.y < 0.0) ? r1 : r2), abs(p.y) - he);
	vec2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
	float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
	return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}
vec2 rot(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x + s * p.y, -s * p.x + c * p.y); }

vec3 sky(vec2 q) { return mix(WHITE, LBLUE, smoothstep(-0.15, 0.5, q.y)); }

vec3 hills(vec3 col, vec2 q, float aa) {
	col = lay(col, mix(LBLUE, WHITE, 0.25), q.y - (0.0 + 0.06 * sin(q.x * 6.0 + 1.0) + 0.025 * sin(q.x * 17.0)), aa);
	col = inked(col, mix(GREEN, YELLOW, 0.35), q.y - (-0.12 + 0.05 * sin(q.x * 4.0 + 2.0)), aa, 0.003);
	col = inked(col, GREEN, q.y - (-0.28 + 0.035 * sin(q.x * 7.0)), aa, 0.003);
	return col;
}

vec3 cypress(vec3 col, vec2 q, vec2 at, float h, float aa) {
	col = lay(col, BROWN, sd_box(q - at - vec2(0.0, 0.01), vec2(0.006, 0.02)), aa);
	return inked(col, DGREEN, sd_ellipse(q - at - vec2(0.0, h * 0.5 + 0.02), vec2(h * 0.16, h * 0.5)), aa, 0.003);
}

// 0 Madonna and Child under a golden halo
vec3 m_madonna(vec2 q, float aa, float ia) {
	vec3 col = sky(q);
	col = hills(col, q, aa);
	if (ia > 0.9) {
		col = cypress(col, q, vec2(-0.36, -0.3), 0.32, aa);
		col = cypress(col, q, vec2(0.38, -0.32), 0.28, aa);
	}
	col = inked(col, YELLOW, sd_circle(q - vec2(0.0, 0.22), 0.155), aa, 0.004);
	col = mix(col, OCHRE, fill(abs(sd_circle(q - vec2(0.0, 0.22), 0.13)) - 0.004, aa));
	float mantle = min(sd_tri(q, vec2(0.0, 0.3), vec2(-0.3, -0.5), vec2(0.3, -0.5)), sd_circle(q - vec2(0.0, 0.2), 0.1));
	col = inked(col, BLUE, mantle, aa, 0.005);
	col = inked(col, RED, sd_tri(q, vec2(0.0, 0.1), vec2(-0.13, -0.5), vec2(0.13, -0.5)), aa, 0.004);
	col = inked(col, SKIN, sd_ellipse(q - vec2(0.0, 0.2), vec2(0.058, 0.075)), aa, 0.003);
	col = lay(col, INK, min(sd_circle(q - vec2(-0.022, 0.21), 0.008), sd_circle(q - vec2(0.022, 0.21), 0.008)), aa);
	col = lay(col, RED, sd_seg(q, vec2(-0.012, 0.165), vec2(0.012, 0.165)) - 0.004, aa);
	// the Child in white swaddling, his own halo
	col = inked(col, YELLOW, sd_circle(q - vec2(-0.1, 0.065), 0.072), aa, 0.003);
	col = inked(col, WHITE, sd_ellipse(rot(q - vec2(-0.05, -0.04), 0.5), vec2(0.085, 0.05)), aa, 0.003);
	col = inked(col, SKIN, sd_circle(q - vec2(-0.1, 0.055), 0.042), aa, 0.003);
	col = inked(col, SKIN, sd_circle(q - vec2(0.05, -0.02), 0.022), aa, 0.002);   // her hand
	return col;
}

// 1 Profile portrait in a red cap, over a landscape and a marble ledge
vec3 m_portrait(vec2 q, float aa, float ia) {
	vec3 col = sky(q);
	col = hills(col, q, aa);
	col = inked(col, RED, sd_ellipse(q - vec2(0.0, -0.44), vec2(0.3, 0.2)), aa, 0.005);
	col = inked(col, OCHRE, sd_ellipse(q - vec2(0.0, -0.26), vec2(0.13, 0.045)), aa, 0.003);
	col = inked(col, SKIN, sd_box(q - vec2(0.015, -0.17), vec2(0.045, 0.07)), aa, 0.003);
	float head = min(sd_ellipse(q - vec2(0.0, 0.02), vec2(0.11, 0.14)), sd_tri(q, vec2(0.095, 0.05), vec2(0.15, -0.012), vec2(0.095, -0.025)));
	col = inked(col, SKIN, head, aa, 0.004);
	col = inked(col, BROWN, max(sd_ellipse(q - vec2(-0.035, 0.02), vec2(0.095, 0.135)), q.x - 0.0), aa, 0.003);
	col = inked(col, RED, max(sd_ellipse(q - vec2(-0.005, 0.13), vec2(0.13, 0.07)), -(q.y - 0.1)), aa, 0.004);
	col = lay(col, INK, sd_circle(q - vec2(0.065, 0.05), 0.011), aa);
	col = lay(col, INK, sd_seg(q, vec2(0.045, 0.078), vec2(0.09, 0.074)) - 0.004, aa);
	col = lay(col, RED, sd_seg(q, vec2(0.1, -0.05), vec2(0.13, -0.05)) - 0.005, aa);
	col = inked(col, mix(WHITE, OCHRE, 0.3), sd_box(q - vec2(0.0, -0.47), vec2(ia * 0.5, 0.035)), aa, 0.003);
	return col;
}

// 2 Coat of arms in a laurel wreath with lemons; festoons on wide panels
vec3 m_arms(vec2 q, float aa, float ia) {
	vec3 col = BLUE;
	col = mix(col, LBLUE, 0.25 * step(0.5, fract((q.x + q.y) * 18.0)));   // faint diaper ground
	float R = 0.34;
	float a = atan(q.y, q.x);
	float sector = 6.2831853 / 26.0;
	float ai = (floor(a / sector) + 0.5) * sector;
	vec2 c = vec2(cos(ai), sin(ai)) * R;
	vec2 lq = rot(q - c, ai + 1.5708 + 0.5);
	col = inked(col, mod(floor(a / sector), 2.0) < 1.0 ? GREEN : DGREEN, sd_ellipse(lq, vec2(0.055, 0.024)), aa, 0.003);
	vec2 c2 = vec2(cos(ai), sin(ai)) * (R + 0.055);
	if (mod(floor(a / sector), 3.0) < 1.0) col = inked(col, YELLOW, sd_circle(q - c2, 0.02), aa, 0.003);
	col = inked(col, WHITE, sd_circle(q, R - 0.045), aa, 0.004);
	float shield = min(sd_box(q - vec2(0.0, 0.06), vec2(0.15, 0.1)), max(sd_circle(q - vec2(0.0, -0.02), 0.15), q.y - 0.06));
	float quarter = mod(step(0.0, q.x) + step(0.03, q.y), 2.0);
	col = inked(col, quarter > 0.5 ? YELLOW : RED, shield, aa, 0.006);
	col = inked(col, WHITE, sd_circle(q - vec2(0.0, 0.03), 0.04), aa, 0.003);
	// ribbons
	for (float s = -1.0; s < 2.0; s += 2.0) {
		col = inked(col, WHITE, sd_tri(q, vec2(s * 0.05, -0.33), vec2(s * 0.24, -0.47), vec2(s * 0.2, -0.36)), aa, 0.003);
	}
	if (ia > 1.2) {   // festoons swinging out to the corners
		float x = abs(q.x);
		float t = clamp((x - 0.38) / (ia * 0.5 - 0.42), 0.0, 1.0);
		float yf = 0.32 - 0.26 * sin(3.14159 * t);
		float band = abs(q.y - yf) - 0.04 * (1.0 - 0.4 * abs(t - 0.5));
		if (x > 0.38 && x < ia * 0.5 - 0.02) {
			col = inked(col, mix(GREEN, DGREEN, step(0.5, fract(x * 30.0))), band, aa, 0.003);
			if (fract(t * 4.0) < 0.15) col = inked(col, OCHRE, sd_circle(vec2(fract(t * 4.0) * 0.1, q.y - yf + 0.02), 0.02), aa, 0.002);
		}
	}
	return col;
}

// 3 Caravel under sail on a choppy sea
vec3 m_ship(vec2 q, float aa, float ia) {
	vec3 col = sky(q);
	col = inked(col, YELLOW, sd_circle(q - vec2(ia * 0.5 - 0.12, 0.34), 0.06), aa, 0.003);
	col = lay(col, WHITE, sd_ellipse(q - vec2(-ia * 0.25, 0.36), vec2(0.12, 0.03)), aa);
	float sea = q.y - (-0.16 + 0.012 * sin(q.x * 40.0));
	col = lay(col, BLUE, sea, aa);
	if (sea < 0.0) col = mix(col, LBLUE, 0.6 * step(fract((q.y + 0.012 * sin(q.x * 35.0 + q.y * 9.0)) * 22.0), 0.18));
	float hull = sd_trap(q - vec2(0.0, -0.16), 0.19, 0.3, 0.065);
	col = inked(col, BROWN, min(hull, sd_box(q - vec2(-0.24, -0.06), vec2(0.075, 0.04))), aa, 0.004);
	col = lay(col, YELLOW, max(sd_box(q - vec2(0.0, -0.135), vec2(0.4, 0.008)), hull), aa);
	for (float m = 0.0; m < 3.0; m += 1.0) {
		float x = -0.12 + m * 0.14;
		float top = m == 1.0 ? 0.4 : 0.3;
		col = lay(col, INK, sd_seg(q, vec2(x, -0.1), vec2(x, top)) - 0.007, aa);
		col = inked(col, RED, sd_tri(q, vec2(x, top), vec2(x, top - 0.04), vec2(x + 0.07, top - 0.02)), aa, 0.002);
	}
	col = inked(col, WHITE, sd_box(q - vec2(0.02, 0.14), vec2(0.105, 0.11)) - 0.01, aa, 0.004);
	col = lay(col, RED, min(sd_box(q - vec2(0.02, 0.14), vec2(0.012, 0.08)), sd_box(q - vec2(0.02, 0.15), vec2(0.07, 0.012))), aa);
	col = inked(col, WHITE, sd_box(q - vec2(0.16, 0.08), vec2(0.065, 0.075)) - 0.008, aa, 0.004);
	col = inked(col, WHITE, sd_tri(q, vec2(-0.12, 0.28), vec2(-0.12, -0.03), vec2(-0.26, -0.03)), aa, 0.004);
	return col;
}

// 4 Grotesque: a candelabrum vase with scrolls, leaves and fruit, mirrored about the middle
vec3 m_grotesque(vec2 q, float aa, float ia) {
	vec3 col = BLUE;
	vec2 m = vec2(abs(q.x), q.y);
	// scrolls
	for (float k = 0.0; k < 2.0; k += 1.0) {
		vec2 c = k < 1.0 ? vec2(0.2, -0.06) : vec2(0.16, 0.2);
		float r = k < 1.0 ? 0.075 : 0.055;
		col = lay(col, YELLOW, max(abs(sd_circle(m - c, r)) - 0.012, -(m.y - c.y + r * 0.6 * (1.0 - k * 2.0))), aa);
		col = inked(col, OCHRE, sd_circle(m - c - vec2(0.0, (k < 1.0 ? -1.0 : 1.0) * r * 0.45), 0.024), aa, 0.003);
		col = lay(col, YELLOW, sd_seg(m, vec2(0.06, c.y + (k < 1.0 ? -r : r)), vec2(c.x, c.y + (k < 1.0 ? -r : r))) - 0.012, aa);
	}
	// acanthus leaves at the foot and fruit at the top
	col = inked(col, GREEN, sd_ellipse(rot(m - vec2(0.13, -0.33), 0.7), vec2(0.09, 0.03)), aa, 0.003);
	col = inked(col, GREEN, sd_ellipse(rot(m - vec2(0.09, 0.32), -0.6), vec2(0.07, 0.025)), aa, 0.003);
	// vase
	col = inked(col, OCHRE, sd_trap(q - vec2(0.0, -0.39), 0.1, 0.04, 0.05), aa, 0.003);
	col = inked(col, YELLOW, sd_ellipse(q - vec2(0.0, -0.19), vec2(0.11, 0.13)), aa, 0.004);
	col = lay(col, OCHRE, max(abs(sd_ellipse(q - vec2(0.0, -0.19), vec2(0.075, 0.09))) - 0.008, q.y + 0.12), aa);
	col = inked(col, YELLOW, sd_box(q - vec2(0.0, -0.03), vec2(0.035, 0.04)), aa, 0.003);
	col = inked(col, WHITE, sd_ellipse(q - vec2(0.0, 0.02), vec2(0.09, 0.022)), aa, 0.003);
	col = inked(col, YELLOW, sd_box(q - vec2(0.0, 0.1), vec2(0.022, 0.07)), aa, 0.003);
	col = inked(col, OCHRE, sd_ellipse(q - vec2(0.0, 0.2), vec2(0.085, 0.045)), aa, 0.003);
	col = inked(col, RED, sd_circle(q - vec2(0.0, 0.29), 0.042), aa, 0.003);
	col = inked(col, GREEN, sd_circle(m - vec2(0.055, 0.265), 0.03), aa, 0.003);
	col = inked(col, YELLOW, sd_circle(q - vec2(0.0, 0.37), 0.02), aa, 0.002);
	// pearls along the sides
	vec2 pq = vec2(m.x - (ia * 0.5 - 0.04), fract(q.y * 12.0) / 12.0 - 0.0417);
	col = lay(col, WHITE, sd_circle(pq, 0.012), aa);
	return col;
}

// 5 Tuscan landscape: hill town with a dome and a campanile, cypresses, a winding road
vec3 m_landscape(vec2 q, float aa, float ia) {
	vec3 col = sky(q);
	col = lay(col, WHITE, min(sd_ellipse(q - vec2(-ia * 0.2, 0.33), vec2(0.13, 0.035)), sd_ellipse(q - vec2(ia * 0.25, 0.28), vec2(0.1, 0.028))), aa);
	col = hills(col, q, aa);
	// the town on the middle hill
	for (float i = 0.0; i < 5.0; i += 1.0) {
		float x = -0.16 + i * 0.075;
		float h = 0.05 + 0.03 * fract(sin(i * 12.9) * 43.7);
		float y0 = -0.1 + 0.05 * sin(x * 4.0 + 2.0);
		col = inked(col, mod(i, 2.0) < 1.0 ? WHITE : mix(WHITE, OCHRE, 0.4), sd_box(q - vec2(x, y0 + h * 0.5), vec2(0.034, h * 0.5)), aa, 0.0025);
		col = inked(col, RED, sd_tri(q, vec2(x - 0.04, y0 + h), vec2(x + 0.04, y0 + h), vec2(x, y0 + h + 0.035)), aa, 0.0025);
	}
	col = inked(col, RED, max(sd_circle(q - vec2(-0.04, -0.01), 0.055), -(q.y + 0.01)), aa, 0.003);
	col = inked(col, WHITE, sd_box(q - vec2(0.12, 0.05), vec2(0.022, 0.12)), aa, 0.003);
	col = inked(col, RED, sd_tri(q, vec2(0.095, 0.17), vec2(0.145, 0.17), vec2(0.12, 0.23)), aa, 0.003);
	col = lay(col, INK, sd_box(q - vec2(0.12, 0.13), vec2(0.008, 0.016)), aa);
	// road winding down to the foreground
	float rw = 0.012 + 0.05 * clamp(-(q.y + 0.2) * 2.0, 0.0, 1.0);
	if (q.y < -0.2) col = inked(col, mix(OCHRE, WHITE, 0.4), abs(q.x - 0.12 * sin(q.y * 9.0) + 0.05) - rw, aa, 0.002);
	col = cypress(col, q, vec2(-ia * 0.5 + 0.12, -0.36), 0.36, aa);
	col = cypress(col, q, vec2(-ia * 0.5 + 0.21, -0.33), 0.28, aa);
	col = cypress(col, q, vec2(ia * 0.5 - 0.12, -0.38), 0.34, aa);
	return col;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect, 0.5 - UV.y);
	float aa = max(fwidth(p.y), 1e-4);
	// border: cobalt band, yellow fillets, white beads; the picture inside
	float bw = 0.075;
	vec2 hb = vec2(aspect * 0.5, 0.5);
	float dbox = sd_box(p, hb - bw);
	vec3 col;
	if (dbox > 0.0) {
		col = BLUE;
		col = mix(col, YELLOW, fill(abs(sd_box(p, hb - bw * 0.22)) - 0.006, aa));
		col = mix(col, YELLOW, fill(abs(dbox) - 0.008, aa));
		// beads along the middle of the band
		vec2 e = abs(p) - (hb - bw * 0.55);
		float along = e.x > e.y ? p.y : p.x;
		float bead = sd_circle(vec2(min(abs(e.x), abs(e.y)), (fract(along * 14.0) - 0.5) / 14.0), 0.011);
		col = mix(col, WHITE, fill(bead, aa));
	} else {
		float s = 1.0 - 2.0 * bw;
		vec2 q = p / s;
		float ia = (aspect - 2.0 * bw) / s;
		float qa = aa / s;
		if (motif == 0) col = m_madonna(q, qa, ia);
		else if (motif == 1) col = m_portrait(q, qa, ia);
		else if (motif == 2) col = m_arms(q, qa, ia);
		else if (motif == 3) col = m_ship(q, qa, ia);
		else if (motif == 4) col = m_grotesque(q, qa, ia);
		else col = m_landscape(q, qa, ia);
	}
	// tiles: grout, each tile glazed a shade different, fine crazing and a little wear
	vec2 t = UV * size_m / tile_m;
	vec2 cell = floor(t);
	vec2 f = fract(t);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile_m;
	float gw = max(fwidth(t.x) * tile_m, 0.0008);
	float grout = 1.0 - smoothstep(0.0016, 0.0016 + gw, edge);
	grout *= smoothstep(10.0, 40.0, 1.0 / max(fwidth(t.x), 1e-4));   // fades out once a tile is only a few pixels wide
	col *= 0.95 + 0.08 * hash12(cell + 3.7);
	float craze = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(UV * size_m * 38.0) - 0.5));
	col *= 1.0 - 0.1 * craze;
	col = mix(col, col * 0.8 + vec3(0.06, 0.05, 0.03), smoothstep(0.62, 0.8, fbm(UV * size_m * 3.0)) * 0.45);
	col = mix(col, vec3(0.7, 0.67, 0.6), grout * 0.85);
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = mix(0.16 + 0.12 * craze, 0.95, grout);
	SPECULAR = 0.6;
	// a slight bevel at each tile's edge catches the light
	vec2 bev = (1.0 - smoothstep(0.0, 0.012, vec2(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile_m)) * sign(f - 0.5);
	NORMAL_MAP = normalize(vec3(bev * 0.35, 1.0)) * 0.5 + 0.5;
}
