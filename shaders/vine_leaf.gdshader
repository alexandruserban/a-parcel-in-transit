// Grapevine leaf card: a five-lobed, toothed vine leaf cut out of the quad, with its veins and a petiole.
// The leaf colour comes from the vertex colour (each leaf a slightly different green, a few turning yellow).
shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/wind_sway.gdshaderinc"

uniform float alpha_cut = 0.5;

varying vec3 tint;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = wind_sway(VERTEX, w, true, TIME);
	tint = pow(COLOR.rgb, vec3(2.2));   // the vertex colours are sRGB hex values
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.56 - UV.y);    // y up, origin where the veins meet
	float d = length(p);
	float phi = atan(p.x, p.y);                  // 0 = towards the tip
	float lobe = 0.5 + 0.5 * cos(5.0 * phi);     // five lobes: tip, two sides, two basal
	float R = 0.27 + 0.17 * pow(lobe, 1.6);
	R += 0.014 * cos(phi * 36.0);                // toothed edge
	R *= 1.0 - 0.8 * smoothstep(2.7, 3.1, abs(phi));   // the deep sinus where the stalk joins
	float stalk = step(abs(p.x), 0.014) * step(p.y, 0.0) * step(-0.5, p.y);
	float aa = fwidth(d) * 1.2;
	float a = max(1.0 - smoothstep(R - aa, R + aa, d), stalk);
	// veins along the lobe axes, paler; the blade a little darker towards its edge
	float off = abs(fract(phi * 5.0 / 6.2831853 + 0.5) - 0.5) * 6.2831853 / 5.0 * d;
	float vein = (1.0 - smoothstep(0.004, 0.011, off)) * step(d, R * 0.9);
	vec3 col = tint * mix(1.08, 0.82, d / max(R, 0.01));
	col = mix(col, tint * 1.45 + vec3(0.04, 0.05, 0.0), vein * 0.55);
	col = mix(col, tint * 0.7, stalk);
	ALBEDO = col;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.62;
	SPECULAR = 0.35;
	BACKLIGHT = col * 0.6;   // sunlight glowing through the leaves
}
