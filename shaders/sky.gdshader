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

vec3 moon_face(vec3 d, vec3 md) {
	vec3 right = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(right, md);
	vec2 q = vec2(dot(d, right), dot(d, up)) / 0.0205;
	float r = length(q);
	float z = sqrt(max(0.0, 1.0 - r * r));
	vec2 sp = q / (0.6 + 0.4 * z);
	float m = vnoise(sp * 2.6 + vec2(4.0)) * 0.55 + vnoise(sp * 5.5 + vec2(9.0)) * 0.3 + vnoise(sp * 12.0) * 0.15;
	m += 0.3 * exp(-dot(sp - vec2(-0.2, 0.25), sp - vec2(-0.2, 0.25)) * 3.0);
	float seas = smoothstep(0.62, 0.75, m);
	float alb = 0.92 - 0.3 * seas + (vnoise(sp * 22.0) - 0.5) * 0.12;
	alb *= 0.62 + 0.38 * pow(z, 0.45);
	return vec3(0.9, 0.9, 0.88) * alb;
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
	if (mm > 0.9997 && moon_vis > 0.0) {
		float a = smoothstep(0.99975, 0.99979, mm);
		col = mix(col, moon_face(d, md) * 1.6, a * moon_vis);
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
