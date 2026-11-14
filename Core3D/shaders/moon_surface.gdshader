shader_type spatial;
render_mode cull_back, diffuse_burley;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform vec3 base_col : source_color = vec3(0.50, 0.49, 0.47);
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 p = lpos;
	float broad = fbm(vec3(p.x * 0.012, 0.0, p.z * 0.012) + vec3(4.0));
	float mid = fbm(vec3(p.x * 0.09, 0.0, p.z * 0.09));
	float fine = vnoise(vec3(p.x * 1.3, p.y * 1.3, p.z * 1.3));
	float grain = vnoise(vec3(p.x * 6.0, p.y * 6.0, p.z * 6.0));
	vec3 col = base_col * (0.55 + 0.75 * broad) * (0.8 + 0.4 * mid) * (0.88 + 0.22 * fine) * (0.93 + 0.12 * grain);
	// slightly warmer, brighter regolith on gentle slopes; dark where steep
	float slope = 1.0 - clamp(dot(normalize(NORMAL), normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.0, 1.0);
	col *= 1.0 - 0.35 * smoothstep(0.15, 0.6, slope);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.08;
}
