// Pond water, ported from _makeWaterMaterial() in world.js: three octaves of wind ripples from a height
// texture, a Fresnel mix of a dark green-brown body and the live sky (the day cycle feeds the sky colours in),
// the wall shading the water at the edge, sun glints and a moon path at night.
shader_type spatial;
render_mode unshaded;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith : source_color = vec3(0.25, 0.47, 0.75);
uniform vec3 horizon : source_color = vec3(0.76, 0.84, 0.9);
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.2);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.87);
uniform float sun_glow = 1.0;
uniform float sun_vis = 1.0;
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float moon_vis = 0.0;
uniform float day = 1.0;
uniform vec2 wind_dir = vec2(0.958, 0.287);
uniform float wind = 0.25;
uniform vec2 center = vec2(0.0);
uniform vec2 axes = vec2(10.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hgt(vec2 p) {
	return texture(noise_tex, p).r;
}

// slope of the ripple field in world units (scale = texture tiles per metre)
vec2 slope(vec2 p, float scale) {
	vec2 q = p * scale;
	float e = 1.0 / 256.0;
	return vec2(hgt(q + vec2(e, 0.0)) - hgt(q - vec2(e, 0.0)), hgt(q + vec2(0.0, e)) - hgt(q - vec2(0.0, e))) / (2.0 * e) * scale;
}

// The web shader works in display (sRGB) values and writes them out untouched; do the same maths here
vec3 disp(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 sky_at(vec3 d) {
	float h = max(d.y, 0.0);
	vec3 c = mix(disp(horizon), disp(zenith), pow(smoothstep(0.0, 1.0, h), 0.5));
	float mu = max(dot(d, normalize(sun_dir)), 0.0);
	c += disp(sun_color) * sun_glow * (pow(mu, 6.0) * 0.18 + pow(mu, 2.0) * 0.12 * (1.0 - smoothstep(0.0, 0.45, h)));
	return c;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 w = wind_dir;
	vec2 wp = vec2(-w.y, w.x);
	float t = TIME;
	vec2 g = slope(p + w * t * 0.35, 0.035) * 0.9
		+ slope(p + wp * t * 0.22 - w * t * 0.5, 0.09) * 0.45
		+ slope(p + w * t * 0.9, 0.23) * 0.22;
	float amp = 0.035 + wind * 0.11;
	vec3 n = normalize(vec3(-g.x * amp, 1.0, -g.y * amp));

	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	vec3 R = reflect(-V, n);
	R.y = abs(R.y);
	float cos_t = clamp(dot(n, V), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - cos_t, 5.0);

	// dark green-brown body, lit by the sky
	vec3 body = mix(vec3(0.035, 0.07, 0.06), vec3(0.07, 0.13, 0.11), cos_t) * (0.12 + 0.88 * day);
	vec3 refl = sky_at(R);

	// the wall and coping are reflected in / shade the water right at the edge
	float e = length((p - center) / axes);
	float edge = smoothstep(0.93, 1.0, e);
	refl = mix(refl, vec3(0.32, 0.3, 0.27) * (0.15 + 0.85 * day), edge * 0.7);
	body *= 1.0 - edge * 0.35;

	vec3 col = mix(body, refl, clamp(fres, 0.0, 1.0));

	// sun glints: a tight sparkle plus a broader sheen
	vec3 L = normalize(sun_dir);
	vec3 H = normalize(V + L);
	float nh = max(dot(n, H), 0.0);
	col += disp(sun_color) * (pow(nh, 900.0) * 9.0 + pow(nh, 90.0) * 0.35) * sun_vis;
	// moon path at night
	vec3 Hm = normalize(V + normalize(moon_dir));
	col += vec3(0.75, 0.8, 0.9) * pow(max(dot(n, Hm), 0.0), 300.0) * 1.5 * moon_vis;
	ALBEDO = pow(max(col, vec3(0.0)), vec3(2.2));
}
