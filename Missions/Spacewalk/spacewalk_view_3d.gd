class_name SpacewalkView3D
extends Node3D
## 3D presentation of the spacewalk. The gameplay (inertia, fuel, repairs, collisions) is
## simulated by SpacewalkWorld in the XY plane; this node renders it: Blender-built station,
## damaged satellite, astronaut, thruster puffs, repair rings, Earth and a drifting camera.

var world: SpacewalkWorld
var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var astro: Node3D
var sat: Node3D
var station: Node3D
var rings: Array[RingMarker3D] = []
var hatch_ring: RingMarker3D
var _puffs: GPUParticles3D
var _wing: Node3D
var _dish: Node3D
var _led: MeshInstance3D
var _led_mat: StandardMaterial3D
var _t := 0.0
var _dist := 30.0
var _look := Vector3.ZERO
var _yaw := 0.0
var _shake := 0.0
var _spark_t := 0.0
var _first := true


static func p3(v: Vector2, z: float = 0.0) -> Vector3:
	return Vector3(v.x, -v.y, z)


func setup(w: SpacewalkWorld) -> void:
	world = w
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.place_planet_view(2_600_000.0, 15.0, 400_000.0)
	stage.spin = 0.0006
	camera = Camera3D.new()
	camera.far = 6_000_000.0
	camera.near = 0.3
	camera.fov = 46.0
	add_child(camera)
	camera.make_current()
	# --- models
	station = (load("res://Assets/Models/zenith_station.glb") as PackedScene).instantiate()
	add_child(station)
	sat = (load("res://Assets/Models/satellite.glb") as PackedScene).instantiate()
	sat.position = p3(SpacewalkWorld.SAT)
	add_child(sat)
	# the solar wings are shortened to 40 % so that the astronaut can fly round them (the collision boxes match)
	for wn in ["wing_L", "wing_R"]:
		var wm := sat.find_child(wn, true, false) as MeshInstance3D
		if wm != null and wm.mesh != null:
			var bb := wm.mesh.get_aabb()
			var hinge := bb.end.x if wn == "wing_L" else bb.position.x
			wm.scale.x = 0.4
			wm.position.x += hinge * 0.6
	_wing = sat.find_child("wing_L", true, false)
	_dish = sat.find_child("dish", true, false)
	_led = sat.find_child("battery_led", true, false) as MeshInstance3D
	if _led != null:
		_led_mat = StandardMaterial3D.new()
		_led_mat.emission_enabled = true
		_led_mat.albedo_color = Color(0.2, 0.05, 0.02)
		_led_mat.emission = Color(1.0, 0.2, 0.1)
		_led_mat.emission_energy_multiplier = 4.0
		_led.material_override = _led_mat
	astro = (load("res://Assets/Models/astronaut.glb") as PackedScene).instantiate()
	astro.scale = Vector3.ONE * 1.5
	add_child(astro)
	# --- repair rings
	for i in 3:
		var r := RingMarker3D.new()
		r.set_size(SpacewalkWorld.TARGET_R * 2.4)
		r.set_color(Color(1.0, 0.65, 0.2))
		r.position = p3(world.target_world(i), 3.0)
		add_child(r)
		rings.append(r)
	hatch_ring = RingMarker3D.new()
	hatch_ring.set_size(8.0)
	hatch_ring.set_color(Color(0.3, 0.7, 1.0))
	hatch_ring.position = p3(SpacewalkWorld.HATCH, 3.0)
	add_child(hatch_ring)
	# --- thruster puffs
	_puffs = Fx3D.particles(80, 0.6, 0.5, true, false)
	var pm := Fx3D.pmat(_puffs)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(0.8, 0.95, 1.0, 0.9), Color(0.7, 0.9, 1.0, 0.5), Color(0.6, 0.85, 1.0, 0.0)], [0.0, 0.3, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.6), Vector2(1, 2.0)])
	add_child(_puffs)
	_setup_orbit()
	_update(0.0)


## Free camera (inspect mode, C key): look at the astronaut, satellite, station and Earth.
func _setup_orbit() -> void:
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = false
	orbit.min_dist = 3.0
	orbit.max_dist = 4_000_000.0
	orbit.add_focusable(astro, 3.0, 13.0)
	orbit.add_focusable(sat, 16.0, 60.0)
	var station_mid := Marker3D.new()
	station_mid.position = Vector3(-26, 0, 0)
	add_child(station_mid)
	orbit.add_focusable(station_mid, 34.0, 95.0)
	orbit.add_focusable(stage.planet_pivot, SpaceStage.R, 3_600_000.0)
	orbit.add_obstacle(astro, 2.2)
	orbit.add_obstacle(sat, 9.5)
	for x in [-50.0, -42.0, -30.0, -18.0, -8.0]:
		var m := Marker3D.new()
		m.position = Vector3(x, 0, 0)
		add_child(m)
		orbit.add_obstacle(m, 8.5)
	for sgn in [-1.0, 1.0]:
		var a := Marker3D.new()
		a.position = Vector3(-26, 20.0 * sgn, 0)
		add_child(a)
		orbit.add_obstacle(a, 13.0)
	orbit.add_obstacle(stage.planet_pivot, SpaceStage.R)


func repair_fx(i: int) -> void:
	Fx3D.burst(self, p3(world.target_world(i), 1.0), Color(0.4, 1.0, 0.7), 90, 16.0, 1.4, 1.4)
	rings[i].visible = false


func hit_fx() -> void:
	Fx3D.burst(self, astro.global_position, Color(1.0, 0.55, 0.3), 40, 10.0, 0.9, 0.8)
	_shake = 1.0


func _process(delta: float) -> void:
	_t += delta
	_update(delta)


func _update(delta: float) -> void:
	if world == null:
		return
	# astronaut
	var ap := p3(world.pos)
	astro.position = ap
	var want_yaw := _yaw
	if absf(world.vel.x) > 0.25:
		want_yaw = 0.0 if world.vel.x > 0.0 else PI
	_yaw = lerp_angle(_yaw, want_yaw, minf(1.0, delta * 2.5))
	astro.rotation = Vector3(0.12 * sin(_t * 0.9), _yaw, -world.facing + 0.08 * sin(_t * 0.7))
	# thruster puffs (opposite to the acceleration)
	var a := world.last_acc
	_puffs.emitting = world.thrusting and a.length() > 0.01
	if _puffs.emitting:
		var d := -p3(a).normalized()
		Fx3D.pmat(_puffs).direction = d
		_puffs.global_position = ap + d * 1.3
	# satellite repairs
	if _wing != null:
		_wing.rotation.z = 0.55 * (1.0 - clampf(world.panel_fix, 0.0, 1.0))
	if _dish != null:
		_dish.rotation.z = -0.75 * (1.0 - clampf(world.antenna_fix, 0.0, 1.0))
	if _led_mat != null:
		if world.done[2]:
			_led_mat.emission = Color(0.2, 1.0, 0.5)
			_led_mat.albedo_color = Color(0.05, 0.3, 0.1)
		else:
			_led_mat.emission_energy_multiplier = 1.5 + 4.0 * (0.5 + 0.5 * sin(_t * 6.0))
	for i in 3:
		rings[i].set_progress(world.progress[i])
		if world.done[i]:
			rings[i].visible = false
	hatch_ring.set_color(Color(0.3, 1.0, 0.6) if world.all_repaired else Color(0.3, 0.7, 1.0))
	# sparks from the broken wing joint
	if not world.done[0]:
		_spark_t -= delta
		if _spark_t <= 0.0:
			_spark_t = randf_range(0.6, 1.4)
			Fx3D.burst(self, p3(SpacewalkWorld.SAT + Vector2(-9.0, 0.0), 1.0), Color(1.0, 0.8, 0.4), 18, 7.0, 0.5, 0.6)
	_update_camera(delta, ap)


func _update_camera(delta: float, ap: Vector3) -> void:
	var tgt := p3(world.next_target())
	var d := ap.distance_to(tgt)
	var want := lerpf(26.0, 66.0, smoothstep(10.0, 80.0, d))
	_dist = lerpf(_dist, want, 1.0 - exp(-delta * 1.4))
	var bias := (tgt - ap).limit_length(minf(d * 0.2, 9.0))
	var look := ap + bias
	if _first:
		_look = look
		_first = false
	_look = _look.lerp(look, 1.0 - exp(-delta * 3.5))
	var az := deg_to_rad(9.0 * sin(_t * 0.11) + 4.0 * sin(_t * 0.27) + 6.0)
	var el := deg_to_rad(7.0 + 3.0 * sin(_t * 0.17))
	orbit.update(delta, _look + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * _dist, _look, 46.0)
	if orbit.engaged:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	elif _shake > 0.01 and bool(GameState.settings["shake"]):
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.5
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.5
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 4.0))
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

