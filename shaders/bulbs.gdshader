// Festoon bulbs: each instance's colour, glowing at night (world.night_glows sets `emission`)
shader_type spatial;

uniform float emission = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb * 0.7;
	ROUGHNESS = 0.25;
	EMISSION = COLOR.rgb * emission;
}
