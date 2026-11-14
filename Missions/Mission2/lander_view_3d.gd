class_name LanderView3D
extends Node3D
## 3D lander: Blender model, engine flame + plume, dust kicked up near the ground, legs animation.
## World mapping: model x -> world x, model y (altitude) -> world y, depth axis z stays 0.

var model_node: Node3D
var _flame: MeshInstance3D
var _flame_mat: ShaderMaterial
var _plume: GPUParticles3D
var _dust: GPUParticles3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	model_node = (load("res://Assets/Models/lander.glb") as PackedScene).instantiate()
	add_child(model_node)
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = load("res://Core3D/shaders/flame.gdshader")
	var cone := CylinderMesh.new()
	cone.top_radius = 0.7
	cone.bottom_radius = 0.08
	cone.height = 1.0
	cone.radial_segments = 16
	cone.rings = 1
	_flame = MeshInstance3D.new()
	_flame.mesh = cone
	_flame.material_override = _flame_mat
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0, 0.3, 0)
	add_child(_flame)
	_plume = Fx3D.particles(70, 0.5, 1.6, true, true)
	var pm := Fx3D.pmat(_plume)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 26.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(1.0, 0.95, 0.8, 0.9), Color(1.0, 0.6, 0.2, 0.6), Color(0.9, 0.3, 0.05, 0.0)], [0.0, 0.35, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 1), Vector2(1, 0.2)])
	_plume.position = Vector3(0, 0.3, 0)
	add_child(_plume)
	_dust = Fx3D.particles(120, 3.5, 4.0, false, false)
	var dm := Fx3D.pmat(_dust)
	dm.direction = Vector3(0, 0.1, 0)
	dm.spread = 180.0
	dm.flatness = 0.95
	dm.initial_velocity_min = 8.0
	dm.initial_velocity_max = 30.0
	dm.gravity = Vector3(0, -1.2, 0)
	dm.damping_min = 3.0
	dm.damping_max = 6.0
	dm.scale_min = 0.8
	dm.scale_max = 2.0
	dm.color_ramp = Fx3D.gradient_tex(
		[Color(0.6, 0.58, 0.55, 0.0), Color(0.62, 0.6, 0.57, 0.5), Color(0.5, 0.48, 0.46, 0.0)], [0.0, 0.15, 1.0])
	dm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.5), Vector2(1, 2.2)])
	add_child(_dust)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.7, 0.4)
	_light.omni_range = 40.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, -2, 0)
	add_child(_light)


## altitude above ground (m) drives the dust; ground_y = terrain height under the lander.
func update_view(throttle: float, altitude: float, ground_y: float) -> void:
	var on := throttle > 0.03
	var len := 2.0 + 9.0 * throttle
	_flame.visible = on
	_flame.scale = Vector3(1.0, len, 1.0)
	_flame.position = Vector3(0, 0.3 - len * 0.5, 0)
	_flame_mat.set_shader_parameter("intensity", throttle * 1.1)
	_plume.emitting = on
	_light.light_energy = throttle * 3.0
	var dust_on := on and altitude < 45.0
	_dust.emitting = dust_on
	if dust_on:
		_dust.global_position = Vector3(global_position.x, ground_y + 0.6, global_position.z)
		_dust.amount_ratio = clampf(1.0 - altitude / 45.0, 0.1, 1.0)


func _process(delta: float) -> void:
	_t += delta
