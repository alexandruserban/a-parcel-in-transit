// Wind sway for merged world-space tree geometry, as applyWindSway() in world.js: vertices bend downwind by
// (height / ref_h)^2, with a slow sway travelling across the town as gust waves, plus leaf flutter.

uniform vec2 wind_dir = vec2(0.958, 0.287);
uniform float wind = 0.25;
uniform float ref_h = 8.0;
uniform float sway_amp = 0.32;

vec3 wind_sway(vec3 v, vec3 w, bool flutter, float t) {
	float k = max(w.y, 0.0) / ref_h;
	k *= k;
	float ph = w.x * 0.045 + w.z * 0.03;
	float wave = 0.6 * sin(t * 1.1 - ph * 3.0) + 0.4 * sin(t * 2.7 - ph * 5.1);
	float bend = sway_amp * k * ((0.12 + wind * 0.9) * wave + wind * 0.8);
	v.xz += wind_dir * bend;
	if (flutter) {
		v += vec3(sin(t * 7.0 + w.x * 2.1 + w.y * 1.3), sin(t * 6.1 + w.z * 1.9) * 0.6, cos(t * 7.7 + w.z * 2.3))
			* 0.025 * (0.3 + wind) * min(k * 4.0, 1.0);
	}
	return v;
}
