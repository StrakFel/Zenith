shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 col : source_color = vec4(0.3, 1.0, 0.7, 1.0);
uniform float intensity = 1.0;
uniform float height = 330.0;

varying float t;   // 0 at the wide (far) end -> 1 at the apex (docking port)

void vertex() {
	t = VERTEX.y / height + 0.5;
}

void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.3);
	float stripes = 0.72 + 0.28 * sin(t * 120.0 - TIME * 2.0);
	float a = (0.03 + 0.42 * edge) * (0.12 + 0.88 * t) * stripes * intensity;
	ALBEDO = col.rgb * 1.5;
	ALPHA = clamp(a, 0.0, 0.6);
}
