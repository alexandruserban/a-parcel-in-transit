// Parcels (MultiMesh, tint per instance): brown cardboard with a strip of packing tape over the top.
shader_type spatial;

varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

void fragment() {
	vec3 base = vec3(0.60, 0.44, 0.27) * COLOR.rgb;
	float tape = (1.0 - step(0.045, abs(lpos.x))) * step(0.5, abs(lnorm.y) + abs(lnorm.z));
	ALBEDO = mix(base, vec3(0.76, 0.64, 0.44) * COLOR.rgb, tape * 0.85);
	ROUGHNESS = mix(0.88, 0.35, tape);
}
