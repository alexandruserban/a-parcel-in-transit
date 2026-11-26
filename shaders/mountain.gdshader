// Mountain ranges round the valley: meadow and forest low down, rock on steep faces, snow on the peaks.
shader_type spatial;
#include "res://shaders/noise.gdshaderinc"

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float h = wpos.y;
	float slope = 1.0 - normalize(wnorm).y;
	float n = fbm(wpos.xz * 0.008);
	vec3 meadow = vec3(0.26, 0.36, 0.16);
	vec3 forest = vec3(0.11, 0.19, 0.10);
	vec3 rock = vec3(0.40, 0.38, 0.36);
	vec3 snow = vec3(0.93, 0.95, 0.98);
	vec3 col = mix(meadow, forest, smoothstep(4.0, 26.0, h + n * 25.0));
	col = mix(col, rock, smoothstep(0.32, 0.55, slope + (h - 140.0) / 420.0 + n * 0.2));
	col = mix(col, snow, smoothstep(250.0, 330.0, h + n * 90.0 - slope * 140.0));
	col *= 0.85 + 0.3 * vnoise(wpos.xz * 0.06);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
