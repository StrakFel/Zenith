class_name MoonScene3D
extends Node3D
## The lunar surface: procedural terrain patch (flat landing zone in the middle, craters, boulders),
## black sky with the Earth, a low sun, landing pad and three points of interest (science targets).
## ground_y(x, z) is the single source of truth for height (lander, rover, boulders all use it).

const SIZE := 1100.0
const CELLS := 180
const PAD_RADIUS := 16.0

var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var noise: FastNoiseLite
var rough := 0.4
var boulders: Array = []                 # {pos: Vector2, r: float}
var craters: Array = []                  # {pos: Vector2, r: float, d: float}
var pois: Array[Vector2] = []
var poi_rings: Array[RingMarker3D] = []
var poi_beams: Array[MeshInstance3D] = []
var _t := 0.0


func setup(roughness: float, seed_value: int) -> void:
	rough = roughness
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.place_planet_view(7_500_000.0, 18.0)
	stage.planet_pivot.position = Vector3(-3_400_000.0, 4_300_000.0, -5_700_000.0)
	stage.sun_to = Vector3(-0.78, 0.22, 0.58).normalized()
	stage.apply_look()
	stage.spin = 0.00012
	camera = Camera3D.new()
	camera.far = 16_000_000.0         # far / near must stay below ~2e7 or the light culler cannot build the view frustum
	camera.near = 0.8
	camera.fov = 45.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = false
	orbit.min_dist = 3.0
	orbit.max_dist = 900.0
	noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(90.0, SIZE * 0.45)
		craters.append({"pos": Vector2(cos(a), sin(a)) * d, "r": rng.randf_range(14.0, 60.0), "d": rng.randf_range(1.5, 9.0)})
	_make_pois(rng)
	_build_terrain()
	_build_boulders(rng)
	_build_pad()
	_build_pois()
	_build_ground_light()


func ground_y(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var flat := smoothstep(48.0, 150.0, d)
	var h := noise.get_noise_2d(x, z) * (5.0 + 28.0 * rough) + noise.get_noise_2d(x * 3.3 + 100.0, z * 3.3) * (0.8 + 3.2 * rough)
	for c in craters:
		var dd := Vector2(x, z).distance_to(c["pos"])
		var k := dd / float(c["r"])
		if k < 1.4:
			h -= float(c["d"]) * (1.0 - k * k) if k < 1.0 else -0.35 * float(c["d"]) * exp(-pow((k - 1.0) * 4.0, 2.0))
	return h * flat


func ground_normal(x: float, z: float) -> Vector3:
	var e := 1.5
	var dx := ground_y(x + e, z) - ground_y(x - e, z)
	var dz := ground_y(x, z + e) - ground_y(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func _make_pois(rng: RandomNumberGenerator) -> void:
	var angles := [rng.randf_range(0.2, 1.1), rng.randf_range(2.1, 3.2), rng.randf_range(4.1, 5.4)]
	var dists := [rng.randf_range(70.0, 110.0), rng.randf_range(110.0, 160.0), rng.randf_range(85.0, 140.0)]
	for i in 3:
		pois.append(Vector2(cos(float(angles[i])), sin(float(angles[i]))) * float(dists[i]))


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := SIZE / float(CELLS)
	var half := SIZE * 0.5
	var heights := PackedFloat32Array()
	heights.resize((CELLS + 1) * (CELLS + 1))
	for iz in CELLS + 1:
		for ix in CELLS + 1:
			heights[iz * (CELLS + 1) + ix] = ground_y(-half + ix * step, -half + iz * step)
	for iz in CELLS:
		for ix in CELLS:
			var x0 := -half + ix * step
			var z0 := -half + iz * step
			var h00 := heights[iz * (CELLS + 1) + ix]
			var h10 := heights[iz * (CELLS + 1) + ix + 1]
			var h01 := heights[(iz + 1) * (CELLS + 1) + ix]
			var h11 := heights[(iz + 1) * (CELLS + 1) + ix + 1]
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x0 + step, h10, z0)
			var p01 := Vector3(x0, h01, z0 + step)
			var p11 := Vector3(x0 + step, h11, z0 + step)
			for tri in [[p00, p10, p01], [p10, p11, p01]]:
				for v in tri:
					st.add_vertex(v)
	st.generate_normals()
	var mesh := st.commit()
	terrain = MeshInstance3D.new()
	terrain.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://Core3D/shaders/moon_surface.gdshader")
	terrain.material_override = mat
	add_child(terrain)
	# a big dark skirt so the patch edge is never visible against the sky
	var skirt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	skirt.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://Core3D/shaders/moon_surface.gdshader")
	sm.set_shader_parameter("base_col", Color(0.32, 0.31, 0.30))
	skirt.material_override = sm
	skirt.position = Vector3(0, -3.5, 0)
	add_child(skirt)


var terrain: MeshInstance3D


func _build_boulders(rng: RandomNumberGenerator) -> void:
	var count := int(40 + 360 * rough)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.7
	sphere.radial_segments = 10
	sphere.rings = 6
	mm.mesh = sphere
	mm.instance_count = count
	var n := 0
	var tries := 0
	while n < count and tries < count * 6:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(34.0, SIZE * 0.47)
		var p := Vector2(cos(a), sin(a)) * d
		var r := rng.randf_range(0.5, 1.6) * (1.0 + rough * 1.6) * (1.0 if rng.randf() > 0.1 else 2.2)
		var blocked := false
		for q in pois:
			if p.distance_to(q) < r + 7.0:
				blocked = true
		if blocked:
			continue
		var y := ground_y(p.x, p.y)
		var tf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.6, 1.0), r)), Vector3(p.x, y + r * 0.25, p.y))
		mm.set_instance_transform(n, tf)
		boulders.append({"pos": p, "r": r})
		n += 1
	mm.visible_instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.33, 0.32)
	mat.roughness = 1.0
	mmi.material_override = mat
	add_child(mmi)


func _build_pad() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = PAD_RADIUS
	cm.bottom_radius = PAD_RADIUS
	cm.height = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.72, 0.75)
	mat.roughness = 0.9
	mi.material_override = mat
	mi.position = Vector3(0, 0.06, 0)
	add_child(mi)
	var ring := RingMarker3D.new()
	ring.set_size(PAD_RADIUS * 2.4)
	ring.set_color(Color(0.3, 0.8, 1.0))
	ring.rotation.x = -PI * 0.5
	ring.position = Vector3(0, 0.4, 0)
	add_child(ring)
	for k in 4:
		var a := k * PI * 0.5
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(cos(a) * PAD_RADIUS, 1.2, sin(a) * PAD_RADIUS)
		lamp.light_color = Color(0.5, 0.8, 1.0)
		lamp.light_energy = 1.2
		lamp.omni_range = 16.0
		add_child(lamp)


func _build_pois() -> void:
	for i in pois.size():
		var p := pois[i]
		var y := ground_y(p.x, p.y)
		var ring := RingMarker3D.new()
		ring.set_size(16.0)
		ring.set_color(Color(1.0, 0.7, 0.2))
		ring.rotation.x = -PI * 0.5
		ring.position = Vector3(p.x, y + 0.5, p.y)
		add_child(ring)
		poi_rings.append(ring)
		var beam := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.25
		bm.bottom_radius = 0.25
		bm.height = 40.0
		beam.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color(1.0, 0.7, 0.25, 0.5)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam.material_override = bmat
		beam.position = Vector3(p.x, y + 20.0, p.y)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
		poi_beams.append(beam)


func _build_ground_light() -> void:
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 80, 0)
	fill.light_energy = 0.0
	add_child(fill)


func mark_poi_done(i: int) -> void:
	poi_rings[i].set_color(Color(0.3, 1.0, 0.6))
	(poi_beams[i].material_override as StandardMaterial3D).albedo_color = Color(0.3, 1.0, 0.6, 0.5)


func nearest_obstacle_push(p: Vector2, radius: float) -> Vector2:
	## Returns a displacement that moves a circle of `radius` at p out of every boulder.
	var push := Vector2.ZERO
	for b in boulders:
		var d := p.distance_to(b["pos"])
		var min_d := float(b["r"]) + radius
		if d < min_d and d > 0.001:
			push += (p - (b["pos"] as Vector2)).normalized() * (min_d - d)
	return push


func _process(delta: float) -> void:
	_t += delta
	for r in poi_rings:
		r.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 3.0))
