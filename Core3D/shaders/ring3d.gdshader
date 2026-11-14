shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 col : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform float progress = 0.0;
uniform float pulse = 0.0;
uniform float thickness = 0.035;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = exp(-pow((r - 0.9) / thickness, 2.0));
	float soft = exp(-pow((r - 0.9) / (thickness * 4.0), 2.0)) * 0.25;
	float ang = atan(p.x, -p.y) / 6.2831853 + 0.5;
	float arc_band = exp(-pow((r - 0.74) / (thickness * 1.6), 2.0));
	float arc = arc_band * step(ang, progress) * step(0.001, progress);
	float k = (ring + soft) * (0.65 + 0.35 * pulse) + arc * 1.8;
	ALBEDO = col.rgb * k * 1.6;
	ALPHA = clamp(k, 0.0, 1.0);
}
