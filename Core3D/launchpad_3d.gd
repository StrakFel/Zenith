class_name LaunchPad3D
extends Node3D
## Launch complex: Blender-built pad + service tower with swing arms, procedural ground,
## floodlights, steam vents and a dust blast at ignition. Origin = centre of the pad.

const MOUNT_H := 4.3

var model: Node3D
var arms: Array[Node3D] = []
var _blast: GPUParticles3D
var _steam: GPUParticles3D
var _trench_light: OmniLight3D
var _lamps: Array[OmniLight3D] = []
var _t := 0.0
var blast_level := 0.0


func _ready() -> void:
	var scene: PackedScene = load("res://Assets/Models/launchpad.glb")
	model = scene.instantiate()
	add_child(model)
	for i in range(1, 5):
		var a := model.find_child("arm_%d" % i, true, false)
		if a is Node3D:
			arms.append(a)
	# procedural ground disc under and around the pad
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4800, 4800)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = load("res://Core3D/shaders/ground.gdshader")
	ground.material_override = gm
	ground.position = Vector3(0, -1.05, 0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# floodlights (positions mirror the Blender model: x, z -> -y)
	for p in [Vector3(16, 22.3, -24), Vector3(-16, 22.3, -24), Vector3(22, 22.3, 22), Vector3(-22, 22.3, 22), Vector3(40, 22.3, 0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.88, 0.68)
		l.light_energy = 2.2
		l.omni_range = 70.0
		l.shadow_enabled = false
		add_child(l)
		_lamps.append(l)
	_trench_light = OmniLight3D.new()
	_trench_light.position = Vector3(0, 1.5, 0)
	_trench_light.light_color = Color(1.0, 0.55, 0.2)
	_trench_light.light_energy = 0.0
	_trench_light.omni_range = 90.0
	add_child(_trench_light)
	_build_particles()


func _build_particles() -> void:
	# exhaust dust ring that rolls outwards over the ground
	_blast = Fx3D.particles(180, 5.0, 26.0, false, false)
	var pm := Fx3D.pmat(_blast)
	pm.direction = Vector3(0, 0.08, 0)
	pm.spread = 180.0
	pm.flatness = 0.92
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 60.0
	pm.gravity = Vector3(0, 0.5, 0)
	pm.damping_min = 4.0
	pm.damping_max = 9.0
	pm.scale_min = 0.9
	pm.scale_max = 1.8
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 4.0
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(0.85, 0.78, 0.68, 0.0), Color(0.82, 0.76, 0.68, 0.6), Color(0.6, 0.57, 0.55, 0.0)], [0.0, 0.15, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.5), Vector2(1, 2.4)])
	_blast.position = Vector3(0, 2.0, 0)
	add_child(_blast)
	# cryogenic vapour from the tower base
	_steam = Fx3D.particles(60, 5.0, 6.0, false, true)
	var sm := Fx3D.pmat(_steam)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 25.0
	sm.initial_velocity_min = 2.0
	sm.initial_velocity_max = 5.0
	sm.gravity = Vector3(1.2, 0.3, 0)
	sm.scale_min = 0.6
	sm.scale_max = 1.2
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.color_ramp = Fx3D.gradient_tex(
		[Color(1, 1, 1, 0.0), Color(0.9, 0.95, 1.0, 0.35), Color(1, 1, 1, 0.0)], [0.0, 0.3, 1.0])
	sm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.5), Vector2(1, 2.0)])
	_steam.position = Vector3(6, 6, 6)
	_steam.emitting = true
	add_child(_steam)


## level 0..1 while the engines run on the pad.
func set_blast(level: float) -> void:
	blast_level = level
	_blast.emitting = level > 0.05
	_blast.amount_ratio = clampf(level, 0.1, 1.0)
	_trench_light.light_energy = level * 12.0


func retract_arms(duration: float = 2.2) -> void:
	var i := 0
	for a in arms:
		var tw := create_tween()
		tw.tween_interval(0.25 * i)
		tw.tween_property(a, "rotation:y", -1.3 - 0.05 * i, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		i += 1


func reset_arms() -> void:
	for a in arms:
		a.rotation.y = 0.0


func _process(delta: float) -> void:
	_t += delta
	for i in _lamps.size():
		_lamps[i].light_energy = 2.0 + 0.15 * sin(_t * 3.0 + i * 1.7)
