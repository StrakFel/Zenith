class_name SpaceStage
extends Node3D
## Reusable 3D world: procedural sky (atmosphere -> stars), sun, a huge procedural Earth
## with clouds + atmosphere glow, cinematic post-processing. The Earth is a real sphere
## (scaled game radius); `set_flight(h, theta)` moves it so the camera stays near the origin.

const R := 1_600_000.0

var sun: DirectionalLight3D
var fill: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var planet_pivot: Node3D
var ground_anchor: Node3D        # child of the pivot at the top of the globe (pad goes here)
var planet: MeshInstance3D
var planet_mat: ShaderMaterial
var clouds: MeshInstance3D
var cloud_mat: ShaderMaterial
var atmo: MeshInstance3D
var atmo_mat: ShaderMaterial

var sun_to := Vector3(-0.55, 0.30, 0.78).normalized()
var base_zenith := Color(0.10, 0.28, 0.68)
var base_horizon := Color(0.62, 0.78, 0.95)
var sun_color := Color(1.0, 0.86, 0.68)
var haze := 1.0
var altitude := 0.0
var spin := 0.0                  # rad/s, slow planet rotation for orbit scenes
var _time := 0.0
var _blend_dawn := false


func _ready() -> void:
	_build()
	apply_look()


func _build() -> void:
	# ---- environment + sky
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://Core3D/shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.8
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssao_radius = 2.5
	env.fog_enabled = true
	env.fog_density = 0.0004
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.5
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# ---- lights
	sun = DirectionalLight3D.new()
	sun.light_energy = 2.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 600.0
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 0.6
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)
	# ---- planet
	planet_pivot = Node3D.new()
	add_child(planet_pivot)
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = R
	sm.height = R * 2.0
	sm.radial_segments = 256
	sm.rings = 128
	planet.mesh = sm
	planet_mat = ShaderMaterial.new()
	planet_mat.shader = load("res://Core3D/shaders/planet.gdshader")
	planet.material_override = planet_mat
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_pivot.add_child(planet)
	clouds = MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = R + 3800.0
	cm.height = (R + 3800.0) * 2.0
	cm.radial_segments = 256
	cm.rings = 128
	clouds.mesh = cm
	cloud_mat = ShaderMaterial.new()
	cloud_mat.shader = load("res://Core3D/shaders/clouds.gdshader")
	clouds.material_override = cloud_mat
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_pivot.add_child(clouds)
	atmo = MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = R + 75000.0
	am.height = (R + 75000.0) * 2.0
	am.radial_segments = 192
	am.rings = 96
	atmo.mesh = am
	atmo_mat = ShaderMaterial.new()
	atmo_mat.shader = load("res://Core3D/shaders/atmosphere.gdshader")
	atmo.material_override = atmo_mat
	atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet_pivot.add_child(atmo)
	ground_anchor = Node3D.new()
	ground_anchor.position = Vector3(0, R, 0)
	planet_pivot.add_child(ground_anchor)
	set_flight(0.0, 0.0)


func _process(delta: float) -> void:
	_time += delta
	if cloud_mat != null:
		cloud_mat.set_shader_parameter("time_s", _time)
	if spin != 0.0:
		planet_pivot.rotation.z += spin * delta


## Look presets: "day", "dawn", "dusk", "space".
func set_look(kind: String) -> void:
	_blend_dawn = (kind == "dawn")
	match kind:
		"dawn":
			base_zenith = Color(0.07, 0.15, 0.40)
			base_horizon = Color(1.0, 0.60, 0.34)
			sun_color = Color(1.0, 0.62, 0.38)
			sun_to = Vector3(-0.62, 0.12, 0.78).normalized()
			haze = 1.6
		"dusk":
			base_zenith = Color(0.05, 0.10, 0.30)
			base_horizon = Color(0.95, 0.45, 0.30)
			sun_color = Color(1.0, 0.5, 0.3)
			sun_to = Vector3(0.62, 0.10, 0.78).normalized()
			haze = 1.5
		"space":
			sun_color = Color(1.0, 0.94, 0.85)
			sun_to = Vector3(-0.7, 0.35, 0.62).normalized()
			haze = 0.0
		_:
			base_zenith = Color(0.10, 0.28, 0.68)
			base_horizon = Color(0.62, 0.78, 0.95)
			sun_color = Color(1.0, 0.88, 0.72)
			sun_to = Vector3(-0.55, 0.30, 0.78).normalized()
			haze = 1.0
	apply_look()


func apply_look() -> void:
	if sun == null:
		return
	_push_sun()
	_apply_altitude(altitude)


func _push_sun() -> void:
	sun.light_color = sun_color
	sun.global_transform = Transform3D(Basis.looking_at(-sun_to, Vector3.UP), Vector3.ZERO)
	fill.global_transform = Transform3D(Basis.looking_at(sun_to * Vector3(1, -0.3, -1), Vector3.UP), Vector3.ZERO)
	for m in [sky_mat, planet_mat, cloud_mat, atmo_mat]:
		(m as ShaderMaterial).set_shader_parameter("sun_dir", sun_to)
	sky_mat.set_shader_parameter("sun_col", sun_color)


func set_flight(h: float, theta: float) -> void:
	altitude = h
	planet_pivot.position = Vector3(0, -(R + h), 0)
	planet_pivot.rotation.z = theta
	_apply_altitude(h)


## Orbit-scene layout: puts the globe at `dist` from the camera so its limb sits
## `limb_deg` degrees below the horizon line (what the player sees at the bottom).
func place_planet_view(dist: float, limb_deg: float, x_off: float = 0.0) -> void:
	var rho := asin(clampf(R / dist, 0.0, 0.99))
	var alpha := rho + deg_to_rad(limb_deg)
	planet_pivot.position = Vector3(x_off, -dist * sin(alpha), -dist * cos(alpha))
	altitude = 400000.0
	_apply_altitude(altitude)


func _apply_altitude(h: float) -> void:
	if sky_mat == null:
		return
	if _blend_dawn:
		# the sun climbs and the sky turns blue while the rocket leaves the pad
		var t := smoothstep(300.0, 9000.0, h)
		base_zenith = Color(0.07, 0.15, 0.40).lerp(Color(0.10, 0.28, 0.68), t)
		base_horizon = Color(1.0, 0.60, 0.34).lerp(Color(0.62, 0.78, 0.95), t)
		sun_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.88, 0.72), t)
		var st := Vector3(-0.62, 0.12, 0.78).lerp(Vector3(-0.55, 0.42, 0.72), t).normalized()
		if not st.is_equal_approx(sun_to):
			sun_to = st
			_push_sun()
	var a := (1.0 - smoothstep(26000.0, 95000.0, h)) * minf(haze, 1.0)
	var dark := smoothstep(4000.0, 55000.0, h)
	var zen := base_zenith.lerp(Color(0.01, 0.02, 0.07), dark)
	var hor := base_horizon.lerp(Color(0.10, 0.18, 0.38), dark)
	sky_mat.set_shader_parameter("atmo", a)
	sky_mat.set_shader_parameter("zenith_col", zen)
	sky_mat.set_shader_parameter("horizon_col", hor)
	sky_mat.set_shader_parameter("star_gain", 0.2 + 0.8 * smoothstep(12000.0, 70000.0, h) + (1.0 - minf(haze, 1.0)))
	env.fog_light_color = hor
	planet_mat.set_shader_parameter("haze", 0.000012 * a * haze)
	planet_mat.set_shader_parameter("haze_col", hor)
	env.fog_density = 0.00012 * a * haze
	env.ambient_light_energy = lerpf(0.35, 0.65, a)
	sun.light_energy = lerpf(2.8, 1.7, a)
	fill.light_energy = lerpf(0.25, 0.4, a)
	planet_mat.set_shader_parameter("ground_detail", 1.0 - smoothstep(2000.0, 45000.0, h))
	if ground_anchor != null:
		ground_anchor.visible = h < 60000.0


