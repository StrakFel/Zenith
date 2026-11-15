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
	_build_site()
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


## Spaceport dressing: a wider apron, a crawler road to the assembly building, painted markings, a blockhouse and small
## technical buildings, all standing on the ground (nothing floats).
func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rough: float = 0.9, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	parent.add_child(mi)
	return mi


func _build_site() -> void:
	var apron := model.find_child("apron", true, false)
	if apron is Node3D:
		(apron as Node3D).scale = Vector3(1.8, 1.0, 1.8)          # 150 m -> 270 m concrete apron
		# warm, matte concrete: no violet sheen from the sky reflection
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(0.56, 0.5, 0.45)
		am.roughness = 1.0
		am.metallic_specular = 0.1
		for ch in (apron as Node3D).find_children("*", "MeshInstance3D", true, false):
			(ch as MeshInstance3D).material_override = am
		if apron is MeshInstance3D:
			(apron as MeshInstance3D).material_override = am
	var site := Node3D.new()
	add_child(site)
	var concrete := Color(0.62, 0.6, 0.57)
	var dark := Color(0.2, 0.21, 0.24)
	var paint := Color(0.92, 0.92, 0.88)
	var warn := Color(0.95, 0.7, 0.15)
	# crawler road from the apron to the assembly building (direction of the VAB: -x, -z)
	var road_dir := Vector3(-330.0, 0.0, 220.0).normalized()
	var road := Node3D.new()
	site.add_child(road)
	road.position = Vector3(0, -0.5, 0)
	var ang := atan2(road_dir.x, road_dir.z)
	road.rotation.y = ang
	_box(road, Vector3(16.0, 0.35, 300.0), Vector3(0, -0.2, 280.0), dark, 0.8)
	for k in 20:
		_box(road, Vector3(0.5, 0.05, 6.0), Vector3(0, 0.0, 135.0 + k * 11.0), paint, 0.7)        # centre dashes
	for sx in [-1.0, 1.0]:
		_box(road, Vector3(0.35, 0.05, 300.0), Vector3(sx * 7.6, 0.0, 280.0), warn, 0.7)              # edge lines
	# painted markings on the apron: square guide line + landing-style numerals bars
	for i in 4:
		var r := Node3D.new()
		site.add_child(r)
		r.rotation.y = PI * 0.5 * float(i)
		_box(r, Vector3(150.0, 0.06, 0.8), Vector3(0, 0.02, 52.0), paint, 0.6)
		_box(r, Vector3(0.8, 0.06, 30.0), Vector3(40.0, 0.02, 36.0), warn, 0.6)
	# blockhouse (control bunker) with a lit window, a service building and a generator shed
	_box(site, Vector3(26.0, 8.0, 16.0), Vector3(-120.0, -0.5, 95.0), concrete, 0.95)
	_box(site, Vector3(30.0, 0.8, 18.0), Vector3(-120.0, 7.5, 95.0), Color(0.45, 0.45, 0.47), 0.9)
	_box(site, Vector3(14.0, 6.0, 10.0), Vector3(-30.0, -0.5, 96.0), Color(0.82, 0.83, 0.86), 0.8)
	_box(site, Vector3(14.2, 0.8, 10.2), Vector3(-30.0, 4.6, 96.0), Color(0.15, 0.3, 0.55), 0.6)
	_box(site, Vector3(10.0, 4.0, 7.0), Vector3(20.0, -0.5, 100.0), Color(0.7, 0.72, 0.75), 0.8)
	# a few vehicles / crates and cable runs
	for p in [Vector3(30, -0.5, 70), Vector3(36, -0.5, 74), Vector3(-4, -0.5, 84)]:
		_box(site, Vector3(5.0, 2.2, 2.4), p, Color(0.9, 0.9, 0.92), 0.7)
	for k in 6:
		_box(site, Vector3(0.8, 0.5, 30.0), Vector3(14.0 + k * 1.6, -0.45, 70.0), Color(0.12, 0.12, 0.14), 0.9)
	# the old assembly-building box is removed for good (it read as a floating cube from many camera angles)
	for nm in ["vab", "vab_door", "vab_stripe"]:
		var vn := model.find_child(nm, true, false)
		if vn != null:
			vn.queue_free()
	_build_details(site)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, col: Color, horizontal := false, rough := 0.7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.2
	mi.material_override = m
	if horizontal:
		mi.rotation_degrees = Vector3(0, 0, 90)
		mi.position = pos + Vector3(0, radius, 0)
	else:
		mi.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(mi)
	return mi


## Variety for the launch site: tank farm, radar, water tower, hangars, container stacks, helipad, trucks, light posts.
func _build_details(site: Node3D) -> void:
	var white := Color(0.9, 0.9, 0.92)
	var steel := Color(0.55, 0.58, 0.63)
	var y0 := -0.5
	# horizontal fuel tanks on cradles
	for k in 3:
		var base := Vector3(88.0, y0, -70.0 + k * 11.0)
		_cyl(site, 3.2, 20.0, base + Vector3(0, 1.0, 0), white, true)
		_box(site, Vector3(3.0, 1.2, 2.0), base + Vector3(-6.0, 0, 0), steel)
		_box(site, Vector3(3.0, 1.2, 2.0), base + Vector3(6.0, 0, 0), steel)
	# radar / comms mast with a dish
	var rp := Vector3(-95.0, y0, -75.0)
	_cyl(site, 0.5, 26.0, rp, steel)
	var dish := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 5.0
	sm.height = 2.6
	sm.radial_segments = 24
	dish.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = white
	dm.roughness = 0.5
	dish.material_override = dm
	dish.position = rp + Vector3(0, 27.0, 0)
	dish.rotation_degrees = Vector3(-60, 40, 0)
	site.add_child(dish)
	_cyl(site, 0.18, 8.0, rp + Vector3(0, 26.0, 0), steel)
	# water tower
	var wt := Vector3(110.0, y0, 60.0)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_cyl(site, 0.4, 14.0, wt + Vector3(sx * 3.0, 0, sz * 3.0), steel)
	_cyl(site, 5.0, 7.0, wt + Vector3(0, 14.0, 0), Color(0.82, 0.84, 0.88))
	_box(site, Vector3(10.4, 0.5, 10.4), wt + Vector3(0, 21.0, 0), steel)
	# hangars in a row
	for k in 3:
		var hp := Vector3(-60.0 + k * 34.0, y0, 118.0)
		_box(site, Vector3(28.0, 11.0, 18.0), hp, Color(0.74, 0.76, 0.8), 0.8)
		_box(site, Vector3(28.4, 1.0, 18.4), hp + Vector3(0, 11.0, 0), Color(0.2, 0.32, 0.55), 0.7)
		_box(site, Vector3(14.0, 8.0, 0.4), hp + Vector3(0, 0, -9.1), Color(0.35, 0.37, 0.4), 0.8)
	# container stacks
	var cols := [Color(0.2, 0.4, 0.75), Color(0.85, 0.45, 0.12), Color(0.88, 0.88, 0.9), Color(0.3, 0.55, 0.4)]
	for i in 8:
		var cp := Vector3(48.0 + (i % 4) * 7.0, y0, 100.0 + (i / 4) * 3.4)
		_box(site, Vector3(6.4, 2.6, 2.5), cp, cols[i % 4], 0.7)
		if i % 3 == 0:
			_box(site, Vector3(6.4, 2.6, 2.5), cp + Vector3(0, 2.6, 0), cols[(i + 1) % 4], 0.7)
	# helipad
	var hpad := Vector3(-118.0, y0, 20.0)
	_cyl(site, 9.0, 0.3, hpad, Color(0.3, 0.31, 0.34))
	_box(site, Vector3(1.0, 0.06, 7.0), hpad + Vector3(-2.5, 0.3, 0), white)
	_box(site, Vector3(1.0, 0.06, 7.0), hpad + Vector3(2.5, 0.3, 0), white)
	_box(site, Vector3(6.0, 0.06, 1.0), hpad + Vector3(0, 0.3, 0), white)
	# service trucks
	for p in [Vector3(-20, y0, 60), Vector3(-14, y0, 63), Vector3(40, y0, 48)]:
		_box(site, Vector3(6.0, 2.6, 2.6), p, Color(0.92, 0.92, 0.94), 0.7)
		_box(site, Vector3(2.2, 2.0, 2.6), p + Vector3(4.0, 0, 0), Color(0.9, 0.55, 0.12), 0.7)
	# light posts along the road and the apron
	for k in 10:
		var lp := Vector3(-22.0 - k * 16.0, y0, 18.0 + k * 11.0)
		_cyl(site, 0.18, 10.0, lp, steel)
		_box(site, Vector3(1.6, 0.4, 0.8), lp + Vector3(0, 10.0, 0), Color(1.0, 0.9, 0.7), 0.4, 1.0)
	# perimeter fence posts
	for k in 28:
		var fp := Vector3(-130.0 + k * 9.3, y0, -128.0)
		_cyl(site, 0.12, 2.4, fp, steel)


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
