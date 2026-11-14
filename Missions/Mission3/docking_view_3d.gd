class_name DockingView3D
extends Node3D
## 3D presentation of the ISS docking. DockingWorld simulates the XY-plane physics; this node
## renders the Blender station and spacecraft, the approach corridor, range marks, the
## docking-port ring, RCS puffs, velocity vector, Earth and a cinematic camera.

var world: DockingWorld
var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var ship: Node3D
var station: Node3D
var port_ring: RingMarker3D
var locator: RingMarker3D
var _puffs: GPUParticles3D
var _vel_line: MeshInstance3D
var _vel_mesh: ImmediateMesh
var _t := 0.0
var _look := Vector3.ZERO
var _dist := 200.0
var _shake := 0.0
var _first := true
var _celebrate := 0.0
var _boom_done := false


static func p3(v: Vector2) -> Vector3:
	return Vector3(v.x, -v.y, 0.0)


func setup(w: DockingWorld) -> void:
	world = w
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.place_planet_view(2_700_000.0, 13.0, 300_000.0)
	stage.spin = 0.0009
	camera = Camera3D.new()
	camera.far = 6_000_000.0
	camera.near = 0.3
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()
	station = (load("res://Assets/Models/station.glb") as PackedScene).instantiate()
	add_child(station)
	ship = (load("res://Assets/Models/ship.glb") as PackedScene).instantiate()
	add_child(ship)
	port_ring = RingMarker3D.new()
	port_ring.set_size(7.0)
	port_ring.set_color(Color(1.0, 0.7, 0.2))
	port_ring.position = Vector3(-0.2, 0, 3.5)
	add_child(port_ring)
	locator = RingMarker3D.new()
	locator.set_size(1.0)
	locator.set_color(Color(0.4, 0.85, 1.0))
	add_child(locator)
	_build_corridor()
	_vel_mesh = ImmediateMesh.new()
	_vel_line = MeshInstance3D.new()
	_vel_line.mesh = _vel_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.3, 1.0, 0.7)
	lm.no_depth_test = true
	_vel_line.material_override = lm
	_vel_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_vel_line)
	_puffs = Fx3D.particles(90, 0.7, 0.6, true, false)
	var pm := Fx3D.pmat(_puffs)
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(0.9, 0.97, 1.0, 0.9), Color(0.7, 0.9, 1.0, 0.45), Color(0.6, 0.85, 1.0, 0.0)], [0.0, 0.3, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.6), Vector2(1, 2.2)])
	add_child(_puffs)
	_setup_orbit()
	_update(0.0)


## Free camera (inspect mode, C key): look at the spacecraft, the ISS, the docking port and Earth.
func _setup_orbit() -> void:
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = false
	orbit.min_dist = 3.0
	orbit.max_dist = 4_000_000.0
	orbit.add_focusable(ship, 6.0, 24.0)
	var port := Marker3D.new()
	add_child(port)
	orbit.add_focusable(port, 4.0, 16.0)
	var mid := Marker3D.new()
	mid.position = Vector3(62, 0, 0)
	add_child(mid)
	orbit.add_focusable(mid, 70.0, 230.0)
	orbit.add_focusable(stage.planet_pivot, SpaceStage.R, 3_600_000.0)
	orbit.add_obstacle(ship, 4.2)
	for pair in [[7.0, 0.0, 5.5], [26.0, 0.0, 14.0], [63.0, 0.0, 11.5], [44.0, 39.0, 26.0], [44.0, -39.0, 26.0],
			[94.0, 39.0, 26.0], [94.0, -39.0, 26.0], [40.0, 0.0, 5.0], [80.0, 0.0, 5.0], [110.0, 0.0, 12.0]]:
		var m := Marker3D.new()
		m.position = Vector3(pair[0], pair[1], 0)
		add_child(m)
		orbit.add_obstacle(m, pair[2])
	orbit.add_obstacle(stage.planet_pivot, SpaceStage.R)


func _build_corridor() -> void:
	var reach := 330.0
	var half := tan(deg_to_rad(8.0)) * reach
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = half
	cone.height = reach
	cone.radial_segments = 40
	cone.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	var sm := ShaderMaterial.new()
	sm.shader = load("res://Core3D/shaders/corridor.gdshader")
	mi.material_override = sm
	mi.rotation.z = -PI * 0.5       # apex (top) -> +X, wide end -> -X
	mi.position = Vector3(-reach * 0.5, 0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for m in [10, 25, 50, 100, 200, 300]:
		var l := Label3D.new()
		l.text = "%d" % m
		l.font_size = 40
		l.pixel_size = 0.0007
		l.fixed_size = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.modulate = Color(0.5, 1.0, 0.8, 0.85)
		l.no_depth_test = true
		l.position = Vector3(-float(m), tan(deg_to_rad(8.0)) * float(m) + 1.2, 0.0)
		add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_update(delta)


func _update(delta: float) -> void:
	if world == null:
		return
	var sp := p3(world.pos)
	ship.position = sp
	ship.rotation = Vector3(0, 0, -world.angle)
	ship.visible = not (world.finished and world.contact_result != "")
	# docking-port ring colour / state
	if world.finished and world.contact_result == "":
		port_ring.set_color(Color(0.3, 1.0, 0.6))
		_celebrate += delta
	elif world.finished:
		port_ring.set_color(Color(1.0, 0.3, 0.2))
	else:
		port_ring.set_color(Color(1.0, 0.7, 0.2))
	# locator ring keeps a constant on-screen size so the ship is never lost
	var cd := camera.global_position.distance_to(sp)
	locator.visible = cd > 70.0 and not world.finished
	locator.position = sp + Vector3(0, 0, 4.0)
	locator.set_size(maxf(cd * 0.075, 6.0))
	# RCS puffs
	var n := Vector3(cos(world.angle), -sin(world.angle), 0.0)
	var side := Vector3(-sin(world.angle), -cos(world.angle), 0.0)
	var push := n * world.thrust_fx.x + side * world.thrust_fx.y
	var firing := push.length() > 0.1 or absf(world.rot_fx) > 0.1
	_puffs.emitting = firing and not world.finished
	if firing:
		var dir := (-push).normalized() if push.length() > 0.1 else (side * -signf(world.rot_fx))
		Fx3D.pmat(_puffs).direction = dir
		_puffs.global_position = sp + dir * 3.2
	# velocity vector from the nose tip
	_vel_mesh.clear_surfaces()
	if not world.finished:
		var tip := p3(world.nose_tip())
		var vv := Vector3(world.vel.x, -world.vel.y, 0.0) * 10.0
		_vel_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_vel_mesh.surface_add_vertex(tip)
		_vel_mesh.surface_add_vertex(tip + vv)
		_vel_mesh.surface_end()
	if world.finished and world.contact_result != "" and not _boom_done:
		_boom_done = true
		Fx3D.burst(self, p3(world.nose_tip()), Color(1.0, 0.6, 0.25), 140, 26.0, 2.6, 1.8)
		Fx3D.burst(self, p3(world.nose_tip()), Color(1.0, 0.95, 0.8), 60, 40.0, 1.0, 1.2)
		_shake = 1.0
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var tip := p3(world.nose_tip())
	var d := tip.distance_to(Vector3.ZERO)
	var focus := p3(world.pos).lerp(Vector3.ZERO, 0.5)
	var near_w := smoothstep(110.0, 10.0, d)
	focus = focus.lerp(tip.lerp(Vector3.ZERO, 0.5), near_w)
	var want := clampf(d * 0.95 + 30.0, 30.0, 430.0)
	_dist = lerpf(_dist, want, 1.0 - exp(-delta * 1.6))
	if _first:
		_look = focus
		_first = false
	_look = _look.lerp(focus, 1.0 - exp(-delta * 3.0))
	var az := deg_to_rad(10.0 + 8.0 * sin(_t * 0.1) + 3.0 * sin(_t * 0.29) + _celebrate * 18.0)
	var el := deg_to_rad(8.0 + 2.0 * sin(_t * 0.15))
	orbit.update(delta, _look + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * _dist, _look, 42.0)
	if orbit.engaged:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	elif _shake > 0.01 and bool(GameState.settings["shake"]):
		camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.8
		camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.8
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 3.0))
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

