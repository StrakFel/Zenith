shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform float intensity = 1.0;
uniform vec3 core_col : source_color = vec3(1.0, 0.96, 0.82);
uniform vec3 edge_col : source_color = vec3(1.0, 0.42, 0.08);

void fragment() {
	float t = UV.y; // 0 at the nozzle -> 1 at the tip
	float flick = 0.5 + 0.5 * sin(t * 26.0 - TIME * 55.0 + UV.x * 18.0);
	float flick2 = 0.5 + 0.5 * sin(t * 11.0 - TIME * 33.0 - UV.x * 9.0);
	float fres = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	vec3 c = mix(core_col, edge_col, smoothstep(0.0, 0.75, t));
	ALBEDO = c * intensity * (1.5 - t * 0.9);
	ALPHA = clamp((1.0 - t) * (0.25 + 0.9 * fres) * (0.6 + 0.25 * flick + 0.15 * flick2) * intensity, 0.0, 1.0);
}
