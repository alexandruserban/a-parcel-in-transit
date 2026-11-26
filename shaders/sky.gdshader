// Gradient sky dome with sun glow, moon, stars and drifting clouds. Port of the SkySystem shader in js/sky.js:
// the day cycle (sky_cycle.gd) blends the colours between keyframes by sun elevation and weather.
shader_type sky;
#include "res://shaders/noise.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.25, 0.47, 0.75);
uniform vec3 horizon : source_color = vec3(0.76, 0.84, 0.9);
uniform vec3 ground_col : source_color = vec3(0.3, 0.32, 0.27);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.87);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float sun_glow = 1.0;
uniform float sun_disc = 1.0;
uniform float moon_vis = 0.0;
uniform float stars = 0.0;
uniform float cloud_cover = 0.4;
uniform float cloud_time = 0.0;
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.65, 0.72);

// The web moon's own hash and value noise (sky.js), so the face comes out the same
float m_hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float m_vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(m_hash2(i), m_hash2(i + vec2(1.0, 0.0)), f.x), mix(m_hash2(i + vec2(0.0, 1.0)), m_hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}
// Crater: dark floor, bright raised rim, faint ejecta halo. q = disc coords, c = centre, r = radius
float crater(vec2 q, vec2 c, float r) {
	float d = length(q - c) / r;
	return -0.16 * (1.0 - smoothstep(0.55, 0.95, d)) + 0.22 * smoothstep(0.7, 0.95, d) * (1.0 - smoothstep(0.95, 1.2, d))
		+ 0.05 * (1.0 - smoothstep(1.0, 2.2, d));
}
// Moon face: maria (dark seas), highlands, craters, ray systems, limb darkening. Albedo in rgb, coverage in a
vec4 moon_face(vec3 d, vec3 md) {
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 q = vec2(dot(d, right), dot(d, up)) / 0.0205;
	float r = length(q);
	if (r > 1.03) return vec4(0.0);
	float z = sqrt(max(0.0, 1.0 - r * r));
	vec2 sp = q / (0.6 + 0.4 * z);   // fake sphere wrap: features squeeze towards the limb
	float n = m_vnoise(sp * 2.6 + 4.0) * 0.55 + m_vnoise(sp * 5.5 + 9.0) * 0.3 + m_vnoise(sp * 12.0 + 2.0) * 0.15;
	float bias = 0.34 * exp(-dot(sp - vec2(-0.2, 0.25), sp - vec2(-0.2, 0.25)) * 3.0)
		+ 0.22 * exp(-dot(sp - vec2(0.35, 0.2), sp - vec2(0.35, 0.2)) * 9.0)
		+ 0.2 * exp(-dot(sp - vec2(0.0, -0.25), sp - vec2(0.0, -0.25)) * 8.0)
		+ 0.18 * exp(-dot(sp - vec2(-0.6, -0.1), sp - vec2(-0.6, -0.1)) * 10.0) - 0.12 * smoothstep(0.3, 0.9, -sp.y);
	float m = n + bias;
	float seas = smoothstep(0.64, 0.76, m);
	float alb = 0.92 - 0.3 * seas - 0.08 * smoothstep(0.78, 0.95, m)
		+ (m_vnoise(sp * 20.0) - 0.5) * 0.1 * (1.0 - seas * 0.6) + (m_vnoise(sp * 45.0) - 0.5) * 0.06;
	alb += 0.8 * crater(sp, vec2(0.12, -0.62), 0.07);   // a bright young crater in the southern highlands
	alb += 0.5 * crater(sp, vec2(-0.48, 0.05), 0.06);
	alb += 0.5 * crater(sp, vec2(0.55, -0.25), 0.05);
	alb += 0.4 * crater(sp, vec2(-0.2, -0.5), 0.05);
	alb += 0.4 * crater(sp, vec2(0.62, 0.45), 0.04);
	alb += 0.6 * crater(sp, vec2(-0.32, 0.38), 0.035);  // a bright crater inside the seas
	alb += 0.4 * crater(sp, vec2(0.35, -0.55), 0.035);
	alb += 0.4 * crater(sp, vec2(-0.7, 0.4), 0.04);
	// Bright rays from the young crater
	vec2 rv = sp - vec2(0.12, -0.62);
	float ang = atan(rv.y, rv.x);
	alb += 0.09 * pow(m_vnoise(vec2(ang * 7.0, 1.0)), 5.0) * (1.0 - smoothstep(0.08, 1.1, length(rv)));
	// Small pocks everywhere
	vec2 cell = floor(sp * 16.0), f = fract(sp * 16.0) - 0.5;
	float h = m_hash2(cell);
	float pd = length(f - (vec2(m_hash2(cell + 3.1), m_hash2(cell + 7.7)) - 0.5) * 0.5) / (0.12 + 0.2 * h);
	alb += step(0.78, h) * (1.0 - seas * 0.7) * (-0.05 * (1.0 - smoothstep(0.5, 0.9, pd)) + 0.035 * smoothstep(0.75, 0.95, pd) * (1.0 - smoothstep(0.95, 1.15, pd)));
	alb *= 0.62 + 0.38 * pow(z, 0.45);   // limb darkening
	return vec4(vec3(0.9, 0.9, 0.88) * alb, 1.0 - smoothstep(0.97, 1.03, r));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) col = mix(horizon, zenith, pow(smoothstep(0.0, 1.0, h), 0.5));
	else col = mix(horizon, ground_col, smoothstep(0.0, 0.08, -h));

	// Scattering glow round the sun, spreading along the horizon at dawn and dusk
	float mu = max(dot(d, normalize(sun_dir)), 0.0);
	float band = 1.0 - smoothstep(0.0, 0.45, abs(h));
	col += sun_color * sun_glow * (pow(mu, 6.0) * 0.18 + pow(mu, 48.0) * 0.35 + pow(mu, 2.0) * 0.14 * band);

	// Stars
	if (stars > 0.0 && h > 0.0) {
		vec3 cell = floor(d * 380.0);
		float s = hash13(cell);
		float tw = hash13(cell + vec3(7.0));
		col += vec3(0.85, 0.9, 1.0) * step(0.9975, s) * (0.35 + 0.65 * tw) * stars * smoothstep(0.02, 0.25, h);
	}

	// Moon disc
	vec3 md = normalize(moon_dir);
	float mm = max(dot(d, md), 0.0);
	if (mm > 0.999 && moon_vis > 0.0) {
		vec4 mf = moon_face(d, md);
		col = mix(col, pow(mf.rgb, vec3(2.2)) * 0.85, mf.a * moon_vis);   // the web writes the face in display space, untonemapped
	}
	col += vec3(0.25, 0.3, 0.45) * pow(mm, 60.0) * 0.25 * moon_vis;

	// Sun disc (HDR so it blooms)
	col = mix(col, sun_color * 8.0, smoothstep(0.99965, 0.99985, mu) * sun_disc * step(-0.01, h));

	// Clouds: a noise layer projected on a flat sky plane, drifting with the wind
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.9 + vec2(cloud_time * 0.004, cloud_time * 0.0013);
		float n = fbm(uv * 1.4) * 0.65 + fbm(uv * 4.1 + vec2(3.0)) * 0.35;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n) * smoothstep(0.0, 0.12, h);
		float lit = clamp(0.55 + (n - 0.5) * 1.4 + pow(mu, 4.0) * 0.4, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		col = mix(col, cc, c * 0.92);
	}
	COLOR = col;
}
