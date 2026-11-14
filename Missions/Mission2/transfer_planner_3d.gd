class_name TransferPlanner3D
extends Node3D
## Earth-Moon trajectory planner (1 unit = 1000 km). Shows the transfer ellipse produced by the chosen
## trans-lunar-injection delta-v (real Earth/Moon constants, simplified two-body arc) next to the Moon's
## sphere of influence, and animates the coast of the spacecraft. The Moon is not advanced in its orbit
## (the player is assumed to time the burn correctly) - a stated simplification.

const U := 1.0e6

var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var dv := 3100.0
var progress := -1.0
var _path: MeshInstance3D
var _path_mesh: ImmediateMesh
var _path_mat: StandardMaterial3D
var _ship: Node3D
var _moon: MeshInstance3D
var _t := 0.0
var _points := PackedVector3Array()


func _ready() -> void:
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.planet_pivot.visible = false
	stage.sun_to = Vector3(-0.2, 0.25, 0.95).normalized()
	stage.apply_look()
	camera = Camera3D.new()
	camera.far = 6000.0
	camera.near = 0.5
	camera.fov = 40.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = true
	orbit.min_dist = 8.0
	orbit.max_dist = 2500.0
	# Earth
	var earth := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 6.371
	es.height = 12.742
	es.radial_segments = 96
	es.rings = 48
	earth.mesh = es
	var pm := ShaderMaterial.new()
	pm.shader = load("res://Core3D/shaders/planet.gdshader")
	pm.set_shader_parameter("sun_dir", stage.sun_to)
	earth.material_override = pm
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)
	var atm := MeshInstance3D.new()
	var asph := SphereMesh.new()
	asph.radius = 6.75
	asph.height = 13.5
	asph.radial_segments = 64
	asph.rings = 32
	atm.mesh = asph
	var am := ShaderMaterial.new()
	am.shader = load("res://Core3D/shaders/atmosphere.gdshader")
	am.set_shader_parameter("sun_dir", stage.sun_to)
	atm.material_override = am
	atm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atm)
	# Moon + sphere of influence
	_moon = MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = 1.737
	ms.height = 3.474
	ms.radial_segments = 64
	ms.rings = 32
	_moon.mesh = ms
	var mm := ShaderMaterial.new()
	mm.shader = load("res://Core3D/shaders/moon_globe.gdshader")
	_moon.material_override = mm
	_moon.position = Vector3(LunarDesign.MOON_DIST / U, 0, 0)
	add_child(_moon)
	var soi := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = LunarDesign.MOON_SOI / U
	ss.height = LunarDesign.MOON_SOI / U * 2.0
	ss.radial_segments = 48
	ss.rings = 24
	soi.mesh = ss
	var hm := ShaderMaterial.new()
	hm.shader = load("res://Core3D/shaders/hologram.gdshader")
	soi.material_override = hm
	soi.position = _moon.position
	soi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(soi)
	# LEO ring + labels
	_add_label("LUN_LBL_EARTH", Vector3(0, 11.0, 0))
	_add_label("LUN_LBL_MOON", _moon.position + Vector3(0, 6.0, 0))
	_add_label("LUN_LBL_SOI", _moon.position + Vector3(0, LunarDesign.MOON_SOI / U + 4.0, 0))
	# trajectory line + spacecraft marker
	_path_mesh = ImmediateMesh.new()
	_path = MeshInstance3D.new()
	_path.mesh = _path_mesh
	_path_mat = StandardMaterial3D.new()
	_path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_path_mat.vertex_color_use_as_albedo = true
	_path_mat.no_depth_test = false
	_path.material_override = _path_mat
	_path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path)
	_ship = Node3D.new()
	var ship_mesh := MeshInstance3D.new()
	var ssp := SphereMesh.new()
	ssp.radius = 1.4
	ssp.height = 2.8
	ship_mesh.mesh = ssp
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.9, 0.6)
	ship_mesh.material_override = sm
	_ship.add_child(ship_mesh)
	var sl := OmniLight3D.new()
	sl.light_color = Color(1.0, 0.8, 0.5)
	sl.omni_range = 30.0
	_ship.add_child(sl)
	_ship.visible = false
	add_child(_ship)
	set_dv(dv)


func _add_label(key: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = tr(key)
	l.font_size = 40
	l.pixel_size = 0.0009
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.7, 0.9, 1.0, 0.9)
	l.no_depth_test = true
	l.position = pos
	add_child(l)


func trajectory_color() -> Color:
	match LunarDesign.tli_outcome(dv):
		0:
			return Color(0.3, 1.0, 0.6)
		1:
			return Color(1.0, 0.8, 0.3)
	return Color(1.0, 0.3, 0.25)


func set_dv(value: float) -> void:
	dv = value
	_points.clear()
	var r1 := (LunarDesign.R_EARTH + LunarDesign.LEO_ALT)
	var ra := minf(LunarDesign.tli_apogee(dv), 900.0e6)
	if ra == INF:
		ra = 900.0e6
	var a := (r1 + ra) * 0.5
	var e := (ra - r1) / (ra + r1)
	var p := a * (1.0 - e * e)
	var col := trajectory_color()
	_path_mesh.clear_surfaces()
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := 160
	for i in n + 1:
		var nu := PI * float(i) / float(n)
		var r := p / (1.0 + e * cos(nu))
		var v := Vector3(-r * cos(nu), 0.0, -r * sin(nu)) / U
		_points.append(v)
		_path_mesh.surface_set_color(col)
		_path_mesh.surface_add_vertex(v)
	_path_mesh.surface_end()


func ship_at(k: float) -> void:
	if _points.is_empty():
		return
	var idx := clampf(k, 0.0, 1.0) * float(_points.size() - 1)
	var i0 := int(floor(idx))
	var i1 := mini(i0 + 1, _points.size() - 1)
	_ship.visible = true
	_ship.scale = Vector3.ONE
	_ship.position = _points[i0].lerp(_points[i1], idx - float(i0))


func hide_ship() -> void:
	_ship.visible = false


## Launch cinematic: the camera is driven from outside and the marker is shown small.
var override_cam := false
var o_pos := Vector3.ZERO
var o_look := Vector3.ZERO


func ship_to(p: Vector3, marker_scale: float = 0.15) -> void:
	_ship.visible = true
	_ship.scale = Vector3.ONE * marker_scale
	_ship.position = p


func _process(delta: float) -> void:
	_t += delta
	_moon.rotation.y += delta * 0.02
	if override_cam:
		orbit.update(delta, o_pos, o_look, 40.0)
		return
	# auto camera: slow sweep over the Earth-Moon line until the player grabs the camera
	var focus := Vector3(190.0, 0.0, -20.0)
	var az := deg_to_rad(18.0 + 8.0 * sin(_t * 0.1))
	var pos := focus + Vector3(sin(az) * 0.4, 0.55, cos(az)).normalized() * 520.0
	orbit.update(delta, pos, focus, 40.0)
