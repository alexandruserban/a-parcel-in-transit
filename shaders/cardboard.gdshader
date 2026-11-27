// Parcels (MultiMesh, tint per instance) with the web game's cardboard texture once on every face,
// like the per-face UVs of a three.js BoxGeometry.
shader_type spatial;

uniform sampler2D card_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 box_size = vec3(1.0);

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	vec3 q = lpos / box_size + vec3(0.5);
	vec3 n = abs(lnorm);
	// read every side face from outside: flip u on the faces that look down -x and +z
	vec2 uv;
	if (n.y > 0.5) uv = q.xz;
	else if (n.x > 0.5) uv = vec2(lnorm.x > 0.0 ? 1.0 - q.z : q.z, 1.0 - q.y);
	else uv = vec2(lnorm.z > 0.0 ? q.x : 1.0 - q.x, 1.0 - q.y);
	ALBEDO = texture(card_tex, uv).rgb * COLOR.rgb;
	ROUGHNESS = 0.85;
}
