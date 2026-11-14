shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, fog_disabled;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.55, 0.3, 0.78);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float time_s = 0.0;

varying vec3 opos;

void vertex() {
	opos = normalize(VERTEX);
}

void fragment() {
	vec3 p = opos;
	vec3 w = vec3(time_s * 0.00002, 0.0, 0.0);
	float macro = fbm(p * 5.0 + w + vec3(8.0));
	float micro = fbm(p * 220.0 + w * 40.0);
	float fine = fbm(p * 1800.0);
	float c = smoothstep(0.50, 0.72, macro) * (0.45 + 0.75 * micro) + 0.12 * fine * smoothstep(0.4, 0.7, macro);
	c = clamp(c, 0.0, 1.0);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sl = dot(nw, normalize(sun_dir));
	float light = 0.10 + 0.92 * smoothstep(-0.12, 0.5, sl);
	vec3 col = mix(vec3(0.62, 0.70, 0.85), vec3(1.0, 0.98, 0.95), clamp(0.4 + micro, 0.0, 1.0)) * light;
	ALBEDO = col;
	ALPHA = c * opacity;
}

