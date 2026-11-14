shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;

uniform vec3 sun_dir = vec3(-0.55, 0.3, 0.78);
uniform vec3 atm_col : source_color = vec3(0.30, 0.58, 1.0);
uniform float strength = 1.6;

void fragment() {
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sl = dot(nw, normalize(sun_dir));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	float lit = smoothstep(-0.35, 0.45, sl);
	vec3 warm = mix(atm_col, vec3(1.0, 0.55, 0.25), smoothstep(0.35, -0.05, sl) * smoothstep(-0.4, 0.0, sl));
	ALBEDO = warm * rim * lit * strength;
}

