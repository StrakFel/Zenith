shader_type spatial;
render_mode blend_mix, cull_back;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform float radius = 2400.0;
varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 p = lpos;
	float n1 = fbm(p * 0.004);
	float n2 = fbm(p * 0.05);
	float n3 = vnoise(p * 0.8);
	vec3 grass = mix(vec3(0.07, 0.20, 0.07), vec3(0.18, 0.30, 0.10), n1);
	vec3 sand = mix(vec3(0.38, 0.32, 0.22), vec3(0.50, 0.43, 0.30), n2);
	vec3 col = mix(grass, sand, smoothstep(0.55, 0.72, fbm(p * 0.0025 + vec3(5.0))));
	col *= 0.82 + 0.3 * n2 + 0.1 * n3;
	float r = length(p.xz);
	float pad_zone = smoothstep(180.0, 70.0, r);
	col = mix(col, vec3(0.34, 0.33, 0.31) * (0.9 + 0.2 * n3), pad_zone * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	ALPHA = 1.0 - smoothstep(radius * 0.72, radius, r);
}

