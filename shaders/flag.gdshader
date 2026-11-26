// The castle banner: the town arms on a strip that ripples from the pole outward (castle.js updateCastle,
// moved into a vertex shader: z = sin(t * (3 + 4w) - 1.6x) * 0.18 * x * (0.5 + w))
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float wind = 0.25;

void vertex() {
	float x = VERTEX.x;
	VERTEX.z = sin(TIME * (3.0 + wind * 4.0) - x * 1.6) * 0.18 * x * (0.5 + wind);
	float dz = cos(TIME * (3.0 + wind * 4.0) - x * 1.6) * -1.6 * 0.18 * x * (0.5 + wind) + sin(TIME * (3.0 + wind * 4.0) - x * 1.6) * 0.18 * (0.5 + wind);
	NORMAL = normalize(vec3(-dz, 0.0, 1.0));
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = 0.8;
}
