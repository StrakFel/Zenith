shader_type sky;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform float atmo : hint_range(0.0, 1.0) = 1.0;
uniform vec3 zenith_col : source_color = vec3(0.10, 0.28, 0.70);
uniform vec3 horizon_col : source_color = vec3(0.62, 0.78, 0.95);
uniform vec3 sun_dir = vec3(-0.55, 0.3, 0.78);
uniform vec3 sun_col : source_color = vec3(1.0, 0.85, 0.65);
uniform float star_gain = 1.0;

float stars(vec3 d, float scale, float thresh) {
	vec3 q = d * scale;
	vec3 id = floor(q);
	vec3 fp = fract(q);
	float r = h13(id);
	vec3 off = vec3(h13(id + 1.7), h13(id + 5.3), h13(id + 9.1));
	float dist = length(fp - off * 0.8 - 0.1);
	return step(thresh, r) * smoothstep(0.16, 0.0, dist) * (0.4 + 0.6 * h13(id + 3.3));
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 sd3 = normalize(sun_dir);
	float sd = max(dot(d, sd3), 0.0);
	// --- atmosphere
	vec3 atm = mix(horizon_col, zenith_col, pow(clamp(up, 0.0, 1.0), 0.42));
	atm = mix(atm, horizon_col * 0.75, smoothstep(0.0, -0.35, up));
	atm += sun_col * (pow(sd, 500.0) * 7.0 + pow(sd, 7.0) * 0.30 + pow(sd, 26.0) * 0.30);
	// --- deep space
	float s = stars(d, 140.0, 0.93) + stars(d, 320.0, 0.965) * 0.8 + stars(d, 60.0, 0.985) * 1.4;
	float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.9, 0.2))) * 3.0, 2.0));
	float neb = fbm(d * 3.5 + vec3(3.1));
	vec3 space = vec3(0.004, 0.006, 0.014);
	space += band * neb * vec3(0.10, 0.12, 0.24) * 0.9 + band * vec3(0.016, 0.015, 0.024);
	space += s * vec3(0.85, 0.92, 1.0) * star_gain * (0.6 + band * 0.8);
	space += sun_col * (pow(sd, 2500.0) * 40.0 + pow(sd, 70.0) * 0.45);
	vec3 col = mix(space, atm, atmo);
	col += s * vec3(0.8, 0.9, 1.0) * star_gain * 0.5 * atmo * smoothstep(0.9, 0.2, atmo);
	COLOR = col;
}
