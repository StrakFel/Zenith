shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
#include "res://Core3D/shaders/noise.gdshaderinc"

// Engine exhaust. UV.y: 0 at the nozzle -> 1 at the tip. The soft radial falloff comes from the view angle, so the
// cone never shows a hard silhouette. `vac` 0 = dense air (turbulent, orange), 1 = vacuum (clean, blue-white, shock diamonds).
uniform float intensity = 1.0;
uniform float vac : hint_range(0.0, 1.0) = 0.0;
uniform vec3 core_col : source_color = vec3(1.0, 0.97, 0.88);
uniform vec3 edge_col : source_color = vec3(1.0, 0.42, 0.08);

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float fres = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float radial = pow(fres, mix(1.7, 2.6, vac));            // bright axis, soft edge
	float turb = fbm(vec3(UV.x * 7.0, t * 3.5 - TIME * 7.0, TIME * 0.6));
	float turb_amt = mix(0.55, 0.12, vac);
	float body = (1.0 - turb_amt) + turb_amt * 2.0 * turb;
	// longitudinal fade with a soft start at the nozzle lip
	float along = pow(1.0 - t, mix(1.35, 0.9, vac)) * smoothstep(0.0, 0.05, t);
	// shock diamonds in vacuum
	float diamonds = 1.0 + vac * 0.55 * (0.5 + 0.5 * sin(t * 34.0 - TIME * 2.0)) * (1.0 - t);
	// colour ramp: white-hot core -> yellow -> orange -> deep red (air) / pale blue (vacuum)
	vec3 hot = core_col;
	vec3 mid = mix(vec3(1.0, 0.78, 0.30), vec3(0.75, 0.88, 1.0), vac);
	vec3 cool = mix(edge_col, vec3(0.30, 0.45, 1.0), vac);
	vec3 c = mix(hot, mid, smoothstep(0.0, 0.28, t + (1.0 - radial) * 0.35));
	c = mix(c, cool, smoothstep(0.22, 0.85, t + (1.0 - radial) * 0.45));
	float a = radial * along * body * diamonds;
	ALBEDO = c * intensity * (1.6 - t * 0.7);
	ALPHA = clamp(a * intensity * 1.15, 0.0, 1.0);
}
