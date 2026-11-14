shader_type spatial;
render_mode cull_back, fog_disabled;
#include "res://Core3D/shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.55, 0.3, 0.78);
uniform float ground_detail : hint_range(0.0, 1.0) = 0.0;
uniform vec3 atm_col : source_color = vec3(0.25, 0.55, 1.0);
uniform float haze = 0.0;
uniform vec3 haze_col : source_color = vec3(0.62, 0.78, 0.95);

varying vec3 opos;

void vertex() {
	opos = normalize(VERTEX);
}

void fragment() {
	vec3 p = opos;
	float cont = fbm(p * 2.6 + vec3(1.7)) + 0.22 * fbm(p * 8.0);
	float land = smoothstep(0.54, 0.575, cont);
	float lat = abs(p.z);
	float dry = smoothstep(0.58, 0.86, fbm(p * 5.5 + vec3(3.0)));
	float elev = smoothstep(0.575, 0.78, cont);
	vec3 forest = vec3(0.045, 0.20, 0.075);
	vec3 savanna = vec3(0.33, 0.32, 0.15);
	vec3 desert = vec3(0.64, 0.50, 0.30);
	vec3 rock = vec3(0.34, 0.31, 0.29);
	vec3 land_col = mix(forest, savanna, smoothstep(0.30, 0.62, dry));
	land_col = mix(land_col, desert, smoothstep(0.62, 0.92, dry) * (1.0 - smoothstep(0.55, 0.9, lat)));
	land_col = mix(land_col, rock, elev * 0.75);
	land_col *= 0.82 + 0.36 * fbm(p * 34.0);                    // relief / texture variation
	land_col = mix(land_col, vec3(0.92, 0.94, 0.97), smoothstep(0.80, 0.93, lat + 0.06 * fbm(p * 20.0)));
	// deep ocean -> coastal shallows (turquoise) near the shore
	vec3 ocean = mix(vec3(0.03, 0.22, 0.42), vec3(0.008, 0.05, 0.18), smoothstep(0.28, 0.52, cont));
	float shore = smoothstep(0.47, 0.545, cont) * (1.0 - land);
	ocean = mix(ocean, vec3(0.06, 0.45, 0.52), shore * 0.85);
	vec3 alb = mix(ocean, land_col, land);
	// fine detail that only matters when flying low
	float d1 = fbm(p * 900.0);
	float d2 = fbm(p * 6000.0);
	alb *= mix(1.0, 0.72 + 0.5 * d1 + 0.25 * d2, ground_detail * land);
	alb = mix(alb, alb * (0.8 + 0.4 * d1), ground_detail * (1.0 - land));
	float hz = 1.0 - exp(-length(VERTEX) * haze);
	ALBEDO = mix(alb, haze_col * 0.6, hz * 0.85);
	ROUGHNESS = mix(0.10, 0.88, land);
	SPECULAR = mix(0.85, 0.15, land);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sl = dot(nw, normalize(sun_dir));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 em = atm_col * fres * 0.85 * smoothstep(-0.25, 0.35, sl);
	// city lights on the night side
	float night = smoothstep(0.08, -0.22, sl);
	float city = smoothstep(0.80, 0.9, vnoise(p * 120.0)) * smoothstep(0.5, 0.62, land) * (0.5 + 0.5 * fbm(p * 14.0));
	em += vec3(1.0, 0.72, 0.38) * city * night * 1.4;
	EMISSION = em * (1.0 - hz) + haze_col * hz * 0.55;
}



