class_name FlightDirector3D
extends Node
## Cinematography + effects for the 3D ascent: countdown orbit camera, "tower cam" at lift-off,
## smooth hand-over to a chase camera, camera shake, speed streaks, explosion and the
## satellite deployment sequence. Reads the FlightModel, never writes it.

var scene: PadScene3D
var model: FlightModel
var build: Dictionary = {}
var shake_amp := 0.0
var rocket_hidden := false

var _t := 0.0
var _t_lift := -1.0
var _t_switch := -1.0
var _ignition := 0.0
var _streaks: GPUParticles3D
var _boom: Array[GPUParticles3D] = []
var _flash: OmniLight3D
var _debris: Array = []
var _sat: Node3D
var _nose: Node3D
var _nose_vel := Vector3.ZERO
var _deploy_t := -1.0
var _cam_look := Vector3.ZERO
var _cam_pos := Vector3.ZERO
var _first := true
var _orbit_az := 0.0
var _wing_scale := 1.0
var _dish_scale := 1.0


func setup(s: PadScene3D, m: FlightModel, b: Dictionary) -> void:
	scene = s
	model = m
	build = b
	scene.set_build(b, false)
	scene.pad.reset_arms()
	_streaks = Fx3D.particles(110, 1.4, 1.0, true, false)
	var mat := (_streaks.draw_pass_1 as QuadMesh)
	mat.size = Vector2(0.12, 7.0)
	var pm := Fx3D.pmat(_streaks)
	pm.particle_flag_align_y = true
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 0.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 200.0
	pm.initial_velocity_max = 260.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90, 90, 90)
	pm.color = Color(0.9, 0.95, 1.0, 0.35)
	_streaks.emitting = false
	scene.add_child(_streaks)
	_flash = OmniLight3D.new()
	_flash.omni_range = 600.0
	_flash.light_energy = 0.0
	_flash.light_color = Color(1.0, 0.7, 0.4)
	scene.add_child(_flash)
	sync()


## Test helper: jump straight to the chase camera.
func skip_intro() -> void:
	_t_lift = 100.0
	_t_switch = 0.0
	_first = true


func set_ignition(level: float) -> void:
	_ignition = level


func liftoff() -> void:
	_t_lift = 0.0
	scene.pad.retract_arms(2.4)


## Push the model state into the 3D world.
func sync() -> void:
	scene.set_flight(model.altitude(), model.theta, model.pitch)


func update_fx(thr: float, ambient: float, drift: Vector3) -> void:
	if rocket_hidden:
		return
	scene.rocket.set_thrust(thr, ambient, drift)
	var pad_level := thr * (1.0 - smoothstep(0.0, 220.0, model.altitude()))
	scene.pad.set_blast(pad_level)
	# speed streaks (only meaningful in air)
	var speed := model.speed()
	var rho_f := clampf(model.air_density() / 0.6, 0.0, 1.0)
	_streaks.emitting = speed > 60.0 and rho_f > 0.02 and not rocket_hidden
	_streaks.amount_ratio = clampf(rho_f, 0.05, 1.0)
	var vdir := Vector3(model.vt, model.vr, 0.0)
	if vdir.length() > 0.1:
		vdir = vdir.normalized()
		var pm := Fx3D.pmat(_streaks)
		pm.direction = -vdir
		pm.initial_velocity_min = clampf(speed * 0.55, 60.0, 520.0)
		pm.initial_velocity_max = clampf(speed * 0.7, 80.0, 620.0)
		_streaks.global_position = scene.rocket_pivot.global_position


func explode() -> void:
	rocket_hidden = true
	scene.rocket.visible = false
	scene.rocket.set_thrust(0.0, 0.0, Vector3.ZERO)
	_streaks.emitting = false
	var pos := scene.rocket_pivot.global_position
	var fire := Fx3D.particles(260, 2.2, 20.0, true, false)
	var pm := Fx3D.pmat(fire)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 90.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = 0.6
	pm.scale_max = 1.8
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.5, 0.1, 0.85), Color(0.25, 0.1, 0.05, 0.0)], [0.0, 0.3, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.6), Vector2(1, 1.6)])
	fire.one_shot = true
	fire.explosiveness = 1.0
	scene.add_child(fire)
	fire.global_position = pos
	fire.emitting = true
	var smoke := Fx3D.particles(70, 5.0, 14.0, false, false)
	var sm := Fx3D.pmat(smoke)
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 150.0
	sm.initial_velocity_min = 8.0
	sm.initial_velocity_max = 40.0
	sm.gravity = Vector3(0, 2.0, 0)
	sm.damping_min = 1.0
	sm.damping_max = 3.0
	sm.scale_min = 0.8
	sm.scale_max = 2.0
	sm.color_ramp = Fx3D.gradient_tex(
		[Color(0.2, 0.2, 0.22, 0.0), Color(0.18, 0.18, 0.2, 0.7), Color(0.1, 0.1, 0.12, 0.0)], [0.0, 0.15, 1.0])
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	scene.add_child(smoke)
	smoke.global_position = pos
	smoke.emitting = true
	_boom = [fire, smoke]
	_flash.global_position = pos
	_flash.light_energy = 40.0
	create_tween().tween_property(_flash, "light_energy", 0.0, 1.6)
	# tumbling debris (cheap fake physics)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.82, 0.86)
	mat.metallic = 0.6
	mat.roughness = 0.4
	for i in 18:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.5, 2.2), randf_range(0.3, 3.5), randf_range(0.4, 1.4))
		mi.mesh = bm
		mi.material_override = mat
		scene.add_child(mi)
		mi.global_position = pos + Vector3(randf_range(-2, 2), randf_range(-12, 12), randf_range(-2, 2))
		_debris.append({"n": mi, "v": Vector3(randf_range(-40, 40), randf_range(-10, 60), randf_range(-40, 40)),
			"w": Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))})
	shake_amp = 12.0


## Fairing separation + satellite release + panel unfolding. Await it.
func deploy_satellite(duration: float = 4.5, design: Dictionary = {}) -> void:
	var rk := scene.rocket
	rk.set_thrust(0.0, 0.0, Vector3.ZERO)
	var base := rk.nose_base_world()
	_nose = rk.detach_nose(scene)
	var axis := scene.rocket_pivot.global_transform.basis.y.normalized()
	_nose_vel = axis * 4.0
	var packed: PackedScene = load("res://Assets/Models/satellite.glb")
	_sat = packed.instantiate()
	_sat.scale = Vector3.ONE * 0.2
	_apply_design(_sat, design)
	scene.add_child(_sat)
	_sat.global_position = base + axis * 4.0
	_sat.global_transform.basis = scene.rocket_pivot.global_transform.basis * Basis(Vector3.RIGHT, PI * 0.5) * 0.2
	for w in ["wing_R", "wing_L", "dish"]:
		var n := _sat.find_child(w, true, false)
		if n is Node3D:
			(n as Node3D).scale = Vector3(0.02, 1.0, 1.0)
	_deploy_t = 0.0
	var tw := create_tween()
	tw.tween_method(_deploy_step.bind(axis), 0.0, 1.0, duration)
	await tw.finished


func _deploy_step(k: float, axis: Vector3) -> void:
	_deploy_t = k
	if _sat == null:
		return
	var rk := scene.rocket
	var base := rk.nose_base_world()
	_sat.global_position = base + axis * (4.0 + k * k * 55.0)
	var unfold := smoothstep(0.25, 0.8, k)
	for w in ["wing_R", "wing_L"]:
		var n := _sat.find_child(w, true, false)
		if n is Node3D:
			(n as Node3D).scale = Vector3(maxf(0.02, unfold) * _wing_scale, 1.0, 1.0)
	var dish := _sat.find_child("dish", true, false)
	if dish is Node3D:
		(dish as Node3D).scale = Vector3.ONE * maxf(0.02, smoothstep(0.5, 0.9, k)) * _dish_scale


func _process(delta: float) -> void:
	_t += delta
	if model == null:
		return
	if _t_lift >= 0.0:
		_t_lift += delta
	_update_debris(delta)
	_update_camera(delta)


func _update_debris(delta: float) -> void:
	for d in _debris:
		var n: Node3D = d["n"]
		d["v"] += Vector3(0, -9.8, 0) * delta
		n.global_position += (d["v"] as Vector3) * delta
		n.rotation += (d["w"] as Vector3) * delta
	if _nose != null:
		_nose.global_position += _nose_vel * delta
		_nose_vel = _nose_vel.lerp(_nose_vel * 1.2, delta)
		_nose.rotation += Vector3(0.25, 0.1, 0.6) * delta


func _update_camera(delta: float) -> void:
	var cam := scene.camera
	var pivot := scene.rocket_pivot.global_position
	var h := model.altitude()
	var speed := model.speed()
	if _t_lift >= 0.0 and _t_switch < 0.0 and (h > 380.0 or _t_lift > 9.0):
		_t_switch = _t_lift
	var w := 0.0
	if _t_switch >= 0.0:
		w = smoothstep(0.0, 1.0, (_t_lift - _t_switch) / 3.5)
	# --- candidate 1: orbiting pad camera (countdown) / fixed tower camera (lift-off)
	var pos_a: Vector3
	var look_a: Vector3
	if _t_lift < 0.0:
		var az := deg_to_rad(32.0 + 8.0 * sin(_t * 0.12) - _t * 1.4)
		var rr := 118.0 - minf(_t * 0.9, 18.0)
		pos_a = pivot + Vector3(sin(az) * rr, 5.0 + _t * 0.15, cos(az) * rr)
		look_a = pivot + Vector3(0, 6.0 + _t * 0.3, 0)
		_orbit_az = az
	else:
		pos_a = scene.stage.ground_anchor.to_global(Vector3(78.0, 14.0, 98.0))
		look_a = pivot + Vector3(0, 5.0 + clampf(h * 0.04, 0.0, 12.0), 0)
	# --- candidate 2: chase camera
	var f := Vector3(model.vt, model.vr, 0.0)
	if f.length() < 25.0:
		f = Vector3(0, 1, 0)
	f = f.normalized()
	var dist := lerpf(115.0, 165.0, smoothstep(0.0, 80000.0, h))
	var elev := lerpf(0.2, 0.05, smoothstep(20000.0, 90000.0, h))
	var a2 := 0.55 + _t_lift * 0.045 + (_deploy_t if _deploy_t > 0 else 0.0) * 1.2
	var side := Vector3(0, 0, 1).rotated(f, a2)
	var pos_b := pivot - f * dist * 0.12 + side * dist * 0.92 + Vector3(0, dist * elev, 0)
	var look_b := pivot + f * 14.0 - Vector3(0, dist * 0.06, 0)
	if _deploy_t > 0.0:
		look_b = pivot + f * (6.0 + _deploy_t * 28.0) - Vector3(0, dist * 0.05, 0)
	var target_pos := pos_a.lerp(pos_b, w)
	var target_look := look_a.lerp(look_b, w)
	if _first:
		_cam_pos = target_pos
		_cam_look = target_look
		_first = false
	var k := 1.0 - exp(-delta * (3.0 + 5.0 * w))
	_cam_pos = _cam_pos.lerp(target_pos, k)
	_cam_look = _cam_look.lerp(target_look, 1.0 - exp(-delta * 6.0))
	# the orbit controller owns the final camera pose: it follows this cinematic pose until the
	# player enters inspect mode (the pose keeps being computed so the hand-back is seamless)
	scene.orbit.update(delta, _cam_pos, _cam_look, lerpf(40.0, 44.0 + 11.0 * clampf(speed / 3000.0, 0.0, 1.0), w))
	# --- shake (never while the player is inspecting)
	if scene.orbit.engaged:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	elif shake_amp > 0.01:
		cam.h_offset = randf_range(-1.0, 1.0) * shake_amp * 0.1
		cam.v_offset = randf_range(-1.0, 1.0) * shake_amp * 0.1
		shake_amp = lerpf(shake_amp, 0.0, minf(1.0, delta * 3.0))
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0






## Shows only the chosen science instrument and sizes the solar wings / antenna from the design.
func _apply_design(sat_node: Node, design: Dictionary) -> void:
	for n in ["inst_imager", "inst_mag", "inst_spec"]:
		var node := sat_node.find_child(n, true, false)
		if node is Node3D:
			(node as Node3D).visible = false
	if design.is_empty():
		return
	var ins: Dictionary = M1Design.INSTRUMENTS[design["instrument"]]
	var chosen := sat_node.find_child(str(ins["node"]), true, false)
	if chosen is Node3D:
		(chosen as Node3D).visible = true
	_wing_scale = float(M1Design.SOLAR[design["solar"]]["scale"])
	_dish_scale = float(M1Design.COMM[design["comm"]]["scale"])

