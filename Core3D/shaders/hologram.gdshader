shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec3 holo_col : source_color = vec3(0.2, 0.65, 1.0);
uniform float pulse = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.6);
	float scan = 0.5 + 0.5 * sin(UV.y * 70.0 - TIME * 3.0);
	ALBEDO = holo_col * (0.9 + 1.4 * fres) * (0.7 + 0.3 * scan) * (0.8 + 0.5 * pulse);
	ALPHA = (0.22 + 0.5 * fres) * (0.8 + 0.4 * scan);
}

