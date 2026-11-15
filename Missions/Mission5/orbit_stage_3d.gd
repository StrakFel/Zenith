class_name OrbitStage3D
extends Node3D
## Mission 5 - 3D scenes of the stages around the Moon and the way home: the command / service ship in lunar orbit, the lander
## (as the ascent stage), astronauts, the Moon, and the Earth-return scene (re-entry capsule, plasma, parachutes, splashdown).
## This node only RENDERS; the choreography and the rules live in mission5_ops.gd.
##
## Axes of the orbit scene (same as the docking view): the ship's docking port is at the origin and the ship body extends
## towards +X; a chaser (the ascent stage) flies in along +X towards the port.

const MOON_R := 1_000_000.0

var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController

# ---- lunar orbit
var orbit_root: Node3D
var moon_body: MeshInstance3D
var csm: Node3D                  # whole ship; +X axis = ship axis, docking port at x = 0
var capsule: Node3D              # command module (conical)
var service: Node3D              # service module + engine
var csm_flame: Node3D
var lander: Node3D               # wrapper: position / rotation z = the world physics of the docking
var lander_model: Node3D
var lander_flame: Node3D
var astronauts: Array[Node3D] = []
var crate: MeshInstance3D
var port_ring: RingMarker3D

# ---- Earth return
var entry_root: Node3D
var cap: Node3D                  # the re-entry capsule (heat shield towards -Y)
var plasma: Node3D
var drogue: Node3D
var main_chute: Node3D
var _lines: MeshInstance3D
var ocean: MeshInstance3D
var _lines_mesh: ImmediateMesh
var _t := 0.0


func _ready() -> void:
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.place_planet_view(2_700_000.0, 13.0, 500_000.0)
	stage.spin = 0.0008
	camera = Camera3D.new()
	camera.far = 8_000_000.0
	camera.near = 0.3
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = false
	orbit.min_dist = 3.0
	orbit.max_dist = 3_000_000.0
	_build_orbit_scene()
	_build_entry_scene()
	show_orbit()


# ------------------------------------------------------------------ helpers --
static func mat(c: Color, metal: float = 0.3, rough: float = 0.5, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
	return m


static func _mesh(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _cyl(top_r: float, bot_r: float, h: float, seg: int = 28) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bot_r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Scales a model so that its visible height is `height` metres (the Blender models have no common unit).
static func fit_height(node: Node3D, height: float) -> void:
	var box := _aabb(node, Transform3D.IDENTITY)
	if box.size.y > 0.001:
		node.scale = Vector3.ONE * (height / box.size.y)


## Distance (m) from the model origin down to the soles of its feet, at the model's current scale (the astronaut origin is at the torso).
static func foot_offset(node: Node3D) -> float:
	var box := _aabb(node, Transform3D.IDENTITY)
	return -box.position.y * node.scale.y


static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[n, xf]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var t: Transform3D = it[1]
		if node is Node3D and node != n:
			t = t * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var b := t * (node as MeshInstance3D).mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in node.get_children():
			stack.append([c, t])
	return out


func make_flame(width: float, vac: float) -> Node3D:
	var pivot := Node3D.new()
	var fm := ShaderMaterial.new()
	fm.shader = load("res://Core3D/shaders/flame.gdshader")
	fm.set_shader_parameter("vac", vac)
	var mi := _mesh(pivot, _cyl(width, width * 0.1, 1.0, 16), fm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Cone"
	pivot.set_meta("mat", fm)
	pivot.visible = false
	return pivot


## The flame hangs along -Y of its pivot (rotate the pivot to aim it). k 0..1 = intensity, length in metres.
func set_flame(pivot: Node3D, k: float, length: float = 8.0) -> void:
	pivot.visible = k > 0.03
	var cone: MeshInstance3D = pivot.get_node("Cone")
	var len := maxf(length * k, 0.5)
	cone.scale = Vector3(1.0, len, 1.0)
	cone.position = Vector3(0, -len * 0.5, 0)
	(pivot.get_meta("mat") as ShaderMaterial).set_shader_parameter("intensity", k * 1.1)


# ------------------------------------------------------------- lunar orbit ---
func _build_orbit_scene() -> void:
	orbit_root = Node3D.new()
	add_child(orbit_root)
	# the Moon: a big grey sphere below the ship
	var sm := SphereMesh.new()
	sm.radius = MOON_R
	sm.height = MOON_R * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 1024
	nt.height = 512
	nt.seamless = true
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.62, 0.61, 0.6)
	mm.albedo_texture = nt
	mm.roughness = 1.0
	mm.uv1_scale = Vector3(2, 1, 1)
	moon_body = _mesh(orbit_root, sm, mm, Vector3(0, -(MOON_R + 110_000.0), 0))
	# the command + service ship (axis along +X, docking port at the origin)
	csm = Node3D.new()
	orbit_root.add_child(csm)
	var body := Node3D.new()
	body.rotation.z = -PI * 0.5            # builds along +Y, then turned to +X
	csm.add_child(body)
	capsule = Node3D.new()
	body.add_child(capsule)
	_mesh(capsule, _cyl(1.75, 0.45, 3.4), mat(Color(0.88, 0.9, 0.92), 0.4, 0.35), Vector3(0, 1.7, 0))
	_mesh(capsule, _cyl(0.5, 0.5, 0.5), mat(Color(0.35, 0.37, 0.42), 0.8, 0.3), Vector3(0, -0.15, 0))     # docking collar
	_mesh(capsule, _cyl(1.77, 1.77, 0.12), mat(Color(1.0, 0.5, 0.1), 0.2, 0.5), Vector3(0, 3.15, 0))        # orange band
	service = Node3D.new()
	body.add_child(service)
	_mesh(service, _cyl(1.75, 1.75, 4.4), mat(Color(0.55, 0.58, 0.64), 0.7, 0.4), Vector3(0, 5.6, 0))
	_mesh(service, _cyl(1.8, 1.8, 0.18), mat(Color(0.2, 0.25, 0.32), 0.5, 0.5), Vector3(0, 4.0, 0))
	_mesh(service, _cyl(1.8, 1.8, 0.18), mat(Color(0.2, 0.25, 0.32), 0.5, 0.5), Vector3(0, 7.2, 0))
	_mesh(service, _cyl(0.3, 1.0, 1.7), mat(Color(0.25, 0.26, 0.3), 0.9, 0.3), Vector3(0, 8.6, 0))          # engine bell
	for sgn in [-1.0, 1.0]:                                                                              # solar wings
		_mesh(service, BoxMesh.new(), mat(Color(0.1, 0.18, 0.45), 0.3, 0.3, Color(0.02, 0.05, 0.14)), Vector3(0, 5.6, 3.6 * sgn)).scale = Vector3(0.1, 3.4, 3.6)
	csm_flame = make_flame(1.2, 1.0)
	csm_flame.position = Vector3(9.5, 0, 0)
	csm_flame.rotation.z = PI * 0.5
	csm.add_child(csm_flame)
	# lander: used as the ascent stage; wrapper = physics frame (nose along +X)
	lander = Node3D.new()
	orbit_root.add_child(lander)
	lander_model = (load("res://Assets/Models/lander.glb") as PackedScene).instantiate()
	lander_model.rotation.z = -PI * 0.5
	lander.add_child(lander_model)
	fit_height(lander_model, 5.0)
	lander_flame = make_flame(0.8, 1.0)
	lander_flame.position = Vector3(-3.0, 0, 0)
	lander_flame.rotation.z = -PI * 0.5
	lander.add_child(lander_flame)
	# astronauts + sample container for the crew transfer
	for i in 2:
		var a := (load("res://Assets/Models/astronaut.glb") as PackedScene).instantiate() as Node3D
		orbit_root.add_child(a)
		fit_height(a, 1.8)
		a.visible = false
		astronauts.append(a)
	crate = _mesh(orbit_root, BoxMesh.new(), mat(Color(0.85, 0.55, 0.15), 0.2, 0.5, Color(0.25, 0.12, 0.0)))
	crate.scale = Vector3(0.7, 0.5, 0.5)
	crate.visible = false
	port_ring = RingMarker3D.new()
	port_ring.set_size(7.0)
	port_ring.set_color(Color(1.0, 0.7, 0.2))
	port_ring.position = Vector3(-0.2, 0, 0)
	port_ring.rotation.y = PI * 0.5
	orbit_root.add_child(port_ring)
	port_ring.visible = false
	set_docked(true)


## Puts the lander on the docking port (docked) - physics frame: centre at x = -4.6.
func set_docked(_on: bool) -> void:
	lander.position = Vector3(-4.6, 0, 0)
	lander.rotation = Vector3.ZERO


## Chaser (lander) from the 2-D docking world: x along the axis, y up.
func set_chaser(pos: Vector2, angle: float) -> void:
	lander.position = Vector3(pos.x, -pos.y, 0)
	lander.rotation = Vector3(0, 0, -angle)


func set_moon_altitude(alt_m: float) -> void:
	moon_body.position = Vector3(0, -(MOON_R + alt_m), 0)


func show_orbit() -> void:
	orbit_root.visible = true
	entry_root.visible = false
	stage.set_look("space")
	stage.place_planet_view(2_700_000.0, 13.0, 500_000.0)


# ------------------------------------------------------------- Earth return ---
func _build_entry_scene() -> void:
	entry_root = Node3D.new()
	add_child(entry_root)
	cap = Node3D.new()
	entry_root.add_child(cap)
	# capsule: cone (nose up), heat shield disc below (-Y)
	_mesh(cap, _cyl(0.55, 1.9, 3.4), mat(Color(0.88, 0.9, 0.92), 0.4, 0.35), Vector3(0, 1.7, 0))
	_mesh(cap, _cyl(1.95, 1.7, 0.45), mat(Color(0.22, 0.14, 0.1), 0.1, 0.95), Vector3(0, -0.2, 0))     # ablative heat shield
	_mesh(cap, _cyl(0.5, 0.5, 0.35), mat(Color(0.3, 0.32, 0.38), 0.8, 0.3), Vector3(0, 3.5, 0))         # chute compartment
	plasma = make_flame(2.6, 0.0)
	plasma.name = "Plasma"
	plasma.position = Vector3(0, -0.4, 0)
	cap.add_child(plasma)
	# parachutes: canopies are hemispheres with stripes, hung on thin lines
	drogue = _make_canopy(3.0, Color(1.0, 0.45, 0.1))
	drogue.position = Vector3(0, 16.0, 0)
	entry_root.add_child(drogue)
	main_chute = _make_canopy(13.0, Color(1.0, 0.45, 0.1))
	main_chute.position = Vector3(0, 38.0, 0)
	entry_root.add_child(main_chute)
	_lines_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _lines_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.9, 0.9, 0.85)
	_lines.material_override = lm
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	entry_root.add_child(_lines)
	drogue.visible = false
	main_chute.visible = false
	# the sea seen from low altitude (the planet shader is only good from high up): a big wavy ocean plane
	var wn := FastNoiseLite.new()
	wn.frequency = 0.02
	wn.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.noise = wn
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	var om := StandardMaterial3D.new()
	om.albedo_color = Color(0.02, 0.16, 0.34)
	om.roughness = 0.34
	om.metallic = 0.0
	om.metallic_specular = 0.35
	om.normal_enabled = true
	om.normal_texture = nt
	om.normal_scale = 0.8
	om.uv1_scale = Vector3(3000, 3000, 1)
	var pm := PlaneMesh.new()
	pm.size = Vector2(900_000.0, 900_000.0)
	ocean = _mesh(entry_root, pm, om)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.visible = false


func _make_canopy(r: float, col: Color) -> Node3D:
	var n := Node3D.new()
	for i in 2:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * (1.0 if i == 0 else 0.97)
		sm.is_hemisphere = true
		sm.radial_segments = 24
		sm.rings = 8
		var m := mat(col if i == 0 else Color(0.97, 0.97, 0.95), 0.0, 0.8)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := _mesh(n, sm, m)
		mi.scale = Vector3(1.0, 0.62, 1.0)
		if i == 1:
			mi.scale = Vector3(1.002, 0.622, 1.002)
			mi.rotation.y = PI / 6.0
			(mi.material_override as StandardMaterial3D).albedo_color = Color(0.97, 0.97, 0.95, 1.0)
	return n


## Draws the suspension lines of the deployed chutes (capsule at the origin of `entry_root`).
func update_lines() -> void:
	_lines_mesh.clear_surfaces()
	var any := drogue.visible or main_chute.visible
	if not any:
		return
	_lines_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for c in [[drogue, 3.0], [main_chute, 13.0]]:
		var node: Node3D = c[0]
		if not node.visible:
			continue
		var r: float = c[1]
		for k in 8:
			var a := TAU * k / 8.0
			_lines_mesh.surface_add_vertex(Vector3(0, 3.6, 0))
			_lines_mesh.surface_add_vertex(node.position + Vector3(cos(a) * r, 0.1, sin(a) * r) * Vector3(1, 1, 1))
	_lines_mesh.surface_end()


func show_entry() -> void:
	orbit_root.visible = false
	entry_root.visible = true
	stage.set_look("day")
	stage.planet_mat.set_shader_parameter("ground_detail", 0.0)      # the sea, not the launch-site ground
	stage.set_flight(120_000.0, 0.0)


## Sets the capsule altitude over the sea (m).
func set_altitude(h: float, theta: float = 0.0) -> void:
	stage.set_flight(h, theta)
	var low := h < 40_000.0                       # below ~40 km the sea is a real water surface, above it the globe is shown
	ocean.visible = low
	stage.planet_pivot.visible = not low
	ocean.position = Vector3(0, -h - 0.45, 0)


func cam(delta: float, pos: Vector3, look: Vector3, fov: float = 42.0) -> void:
	orbit.update(delta, pos, look, fov)


func _process(delta: float) -> void:
	_t += delta
	if entry_root != null and entry_root.visible:
		update_lines()
