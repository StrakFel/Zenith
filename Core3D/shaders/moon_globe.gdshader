shader_type spatial;
render_mode cull_back;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.62, 0.61, 0.58);
varying vec3 opos;

void vertex() {
	opos = normalize(VERTEX);
}

void fragment() {
	vec3 p = opos;
	float maria = smoothstep(0.52, 0.62, fbm(p * 2.2 + vec3(3.0)));
	float craters = fbm(p * 9.0);
	float fine = vnoise(p * 40.0);
	vec3 col = base_col * mix(1.0, 0.55, maria) * (0.75 + 0.5 * craters) * (0.9 + 0.2 * fine);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
