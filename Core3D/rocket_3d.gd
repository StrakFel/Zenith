class_name Rocket3D
extends Node3D
## Modular 3D rocket built from the Blender-generated parts (nose + tank + engine),
## with hologram "ghosts" for empty slots, engine flame/plume/smoke and a light.
## Origin = centre of the stack. Local +Y is the nose direction.

const RADIUS := 2.0
const NOSE_H := {"std": 12.0, "aero": 18.0}
const TANK_H := {"s": 14.0, "m": 22.0, "l": 32.0, "xl": 42.0}
const ENGINE_H := {"spark": 5.5, "kestrel": 7.0, "phoenix": 8.5, "titan": 10.0}
const ENGINE_R := {"spark": 1.25, "kestrel": 1.75, "phoenix": 1.9, "titan": 2.4}
const BOOSTER_H := {"b_s": 28.0, "b_l": 34.0}
const BOOSTER_N := {"b_s": 2, "b_l": 4}
const UPPER_H := {"u_s": 12.0, "u_m": 17.0, "u_h": 20.0, "u_t": 26.0}     # interstage (3 m) + upper tank
const DEFAULTS := {"nose": "std", "tank": "m", "engine": "kestrel"}

var build: Dictionary = {}
var ghosts_visible := false
var nose_visible := true

var _stack: Node3D                 # origin at the bottom of the stack
var _parts: Dictionary = {}
var _ghosts: Dictionary = {}
var _brand: Array[Label3D] = []
var _fx_root: Node3D               # sits at the nozzle exit
var _plume: GPUParticles3D
var _smoke: GPUParticles3D
var _flame: MeshInstance3D
var _core: MeshInstance3D
var _flame_mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _light: OmniLight3D
var _holo: ShaderMaterial
var _t := 0.0
var _thrust := 0.0
var stage2_active := false
var booster_level := 0.0              # 0..1: how hard the strap-on boosters burn (set by the mission every frame)
var _booster_root: Node3D
var _b_flames: Array = []             # [{"mesh": MeshInstance3D, "mat": ShaderMaterial}]
var _vac := 0.0
var _er_override := -1.0


func _ready() -> void:
	_stack = Node3D.new()
	add_child(_stack)
	_holo = ShaderMaterial.new()
	_holo.shader = load("res://Core3D/shaders/hologram.gdshader")
	_build_fx()
	set_build(build, ghosts_visible)


func _slot_h(slot: String, id: String) -> float:
	match slot:
		"nose":
			return float(NOSE_H[id])
		"tank":
			return float(TANK_H[id])
		"upper":
			return float(UPPER_H.get(id, 0.0))
		"booster":
			return 0.0
		_:
			return float(ENGINE_H[id])


func _id_or_default(slot: String) -> String:
	var id := str(build.get(slot, ""))
	return id if id != "" else str(DEFAULTS[slot])


func _upper_h() -> float:
	return _slot_h("upper", str(build.get("upper", "")))


func total_height() -> float:
	return _slot_h("engine", _id_or_default("engine")) + _slot_h("tank", _id_or_default("tank")) \
		+ _upper_h() + _slot_h("nose", _id_or_default("nose"))


## y range (bottom, top) of a slot in the stack frame (origin at the bottom).
func slot_span(slot: String) -> Vector2:
	var eh := _slot_h("engine", _id_or_default("engine"))
	var th := _slot_h("tank", _id_or_default("tank"))
	var nh := _slot_h("nose", _id_or_default("nose"))
	var uh := _upper_h()
	match slot:
		"engine":
			return Vector2(0.0, eh)
		"tank":
			return Vector2(eh, eh + th)
		"upper":
			return Vector2(eh + th, eh + th + uh)
		_:
			return Vector2(eh + th + uh, eh + th + uh + nh)


## World position of the centre of a slot.
func slot_world_pos(slot: String) -> Vector3:
	var sp := slot_span(slot)
	return _stack.to_global(Vector3(0, (sp.x + sp.y) * 0.5, 0))


func slot_world_span(slot: String) -> Array[Vector3]:
	var sp := slot_span(slot)
	return [_stack.to_global(Vector3(0, sp.x, 0)), _stack.to_global(Vector3(0, sp.y, 0))]


func set_build(b: Dictionary, with_ghosts: bool = false) -> void:
	build = b
	ghosts_visible = with_ghosts
	if _stack == null:
		return
	for k in _parts:
		(_parts[k] as Node).queue_free()
	for k in _ghosts:
		(_ghosts[k] as Node).queue_free()
	for l in _brand:
		l.queue_free()
	_parts.clear()
	_ghosts.clear()
	_brand.clear()
	var eh := _slot_h("engine", _id_or_default("engine"))
	var th := _slot_h("tank", _id_or_default("tank"))
	var uh := _upper_h()
	var ys := {"engine": 0.0, "tank": eh, "upper": eh + th, "nose": eh + th + uh}
	stage2_active = false
	_er_override = -1.0
	for slot in ["engine", "tank", "upper", "nose"]:
		var id := str(build.get(slot, ""))
		if slot == "upper":
			if id != "":
				var up := _make_upper(uh)
				up.position = Vector3(0, ys[slot], 0)
				_stack.add_child(up)
				_parts["upper"] = up
			continue
		if id != "":
			var path := "res://Assets/Models/rocket_%s_%s.glb" % [slot, id]
			var inst: Node3D = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else _make_proc_part(slot, id)
			inst.position = Vector3(0, ys[slot], 0)
			_stack.add_child(inst)
			_parts[slot] = inst
		elif ghosts_visible:
			var g := _make_ghost(slot)
			g.position = Vector3(0, ys[slot], 0)
			_stack.add_child(g)
			_ghosts[slot] = g
	if _booster_root != null:
		_booster_root.queue_free()
		_booster_root = null
	_b_flames.clear()
	var bid := str(build.get("booster", ""))
	if bid != "":
		_booster_root = _make_boosters(bid, eh)
		_stack.add_child(_booster_root)
	if str(build.get("tank", "")) != "":
		_add_branding(eh, th)
	if _parts.has("nose"):
		(_parts["nose"] as Node3D).visible = nose_visible
	_stack.position = Vector3(0, -total_height() * 0.5, 0)
	var er := float(ENGINE_R[_id_or_default("engine")])
	_fx_root.position = Vector3(0, -total_height() * 0.5 + 0.2, 0)
	_flame.scale = Vector3(er * 1.15, 1.0, er * 1.15)
	_core.scale = Vector3(er * 0.7, 1.0, er * 0.7)


## Procedural stand-in for parts that have no Blender model yet (extra-large tank, Titan engine).
func _make_proc_part(slot: String, id: String) -> Node3D:
	var root := Node3D.new()
	if slot == "tank":
		var h := float(TANK_H[id])
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.height = h
		c.top_radius = RADIUS
		c.bottom_radius = RADIUS
		c.radial_segments = 48
		m.mesh = c
		m.position = Vector3(0, h * 0.5, 0)
		m.material_override = _mat(Color(0.92, 0.94, 0.97), 0.25, 0.4)
		root.add_child(m)
		for k in 3:
			var band := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.height = 0.7
			bm.top_radius = RADIUS + 0.03
			bm.bottom_radius = RADIUS + 0.03
			bm.radial_segments = 48
			band.mesh = bm
			band.position = Vector3(0, h * (0.2 + 0.3 * k), 0)
			band.material_override = _mat(Color(0.16, 0.18, 0.23), 0.4, 0.5)
			root.add_child(band)
	else:
		var h := float(ENGINE_H[id])
		var er := float(ENGINE_R[id])
		var mount := MeshInstance3D.new()
		var mc := CylinderMesh.new()
		mc.height = h * 0.3
		mc.top_radius = RADIUS
		mc.bottom_radius = RADIUS * 0.8
		mc.radial_segments = 40
		mount.mesh = mc
		mount.position = Vector3(0, h * 0.85, 0)
		mount.material_override = _mat(Color(0.16, 0.18, 0.23), 0.5, 0.45)
		root.add_child(mount)
		for k in 3:
			var bell := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.height = h * 0.8
			bc.top_radius = er * 0.3
			bc.bottom_radius = er * 0.55
			bc.radial_segments = 24
			bell.mesh = bc
			var a := TAU * float(k) / 3.0
			bell.position = Vector3(cos(a) * er * 0.75, h * 0.4, sin(a) * er * 0.75)
			bell.material_override = _mat(Color(0.35, 0.37, 0.43), 0.8, 0.35)
			root.add_child(bell)
	return root


## Strap-on boosters: n white cylinders around the core with a nose cone, a bell and their own exhaust.
func _make_boosters(id: String, engine_h: float) -> Node3D:
	var root := Node3D.new()
	var n: int = int(BOOSTER_N[id])
	var h: float = float(BOOSTER_H[id])
	for i in n:
		var b := Node3D.new()
		var ang := TAU * float(i) / float(n) - deg_to_rad(40.0)
		b.position = Vector3(cos(ang) * (RADIUS + 1.15), engine_h * 0.4, sin(ang) * (RADIUS + 1.15))
		b.name = "booster_%d" % i
		var body := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.height = h - 5.0
		bc.top_radius = 1.0
		bc.bottom_radius = 1.0
		bc.radial_segments = 32
		body.mesh = bc
		body.position = Vector3(0, 1.5 + (h - 5.0) * 0.5, 0)
		body.material_override = _mat(Color(0.93, 0.94, 0.96), 0.25, 0.4)
		b.add_child(body)
		var cone := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.height = 4.0
		cc.top_radius = 0.08
		cc.bottom_radius = 1.0
		cc.radial_segments = 32
		cone.mesh = cc
		cone.position = Vector3(0, h - 3.5, 0)
		cone.material_override = _mat(Color(0.14, 0.16, 0.2), 0.4, 0.5)
		b.add_child(cone)
		var bell := MeshInstance3D.new()
		var bl := CylinderMesh.new()
		bl.height = 2.0
		bl.top_radius = 0.45
		bl.bottom_radius = 0.85
		bl.radial_segments = 24
		bell.mesh = bl
		bell.position = Vector3(0, 0.6, 0)
		bell.material_override = _mat(Color(0.35, 0.37, 0.43), 0.8, 0.35)
		b.add_child(bell)
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.height = 0.5
		bm.top_radius = 1.03
		bm.bottom_radius = 1.03
		bm.radial_segments = 32
		band.mesh = bm
		band.position = Vector3(0, h * 0.6, 0)
		var om := _mat(Color(1.0, 0.45, 0.1), 0.2, 0.5)
		om.emission_enabled = true
		om.emission = Color(1.0, 0.4, 0.08)
		om.emission_energy_multiplier = 0.3
		band.material_override = om
		b.add_child(band)
		# exhaust
		var fm := ShaderMaterial.new()
		fm.shader = load("res://Core3D/shaders/flame.gdshader")
		var fc := CylinderMesh.new()
		fc.top_radius = 0.9
		fc.bottom_radius = 0.1
		fc.height = 1.0
		fc.radial_segments = 20
		var fmesh := MeshInstance3D.new()
		fmesh.mesh = fc
		fmesh.material_override = fm
		fmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fmesh.visible = false
		b.add_child(fmesh)
		_b_flames.append({"mesh": fmesh, "mat": fm})
		root.add_child(b)
	return root


## Throws the boosters off the stack: they keep their world transform under a new holder (returned) which the director
## animates outwards. Their exhaust is switched off.
func separate_boosters(new_parent: Node) -> Node3D:
	if _booster_root == null:
		return null
	var holder := Node3D.new()
	new_parent.add_child(holder)
	holder.global_transform = _stack.global_transform
	var kids: Array = _booster_root.get_children()
	for k in kids:
		var xf: Transform3D = (k as Node3D).global_transform
		_booster_root.remove_child(k)
		holder.add_child(k)
		(k as Node3D).global_transform = xf
	for f in _b_flames:
		(f["mesh"] as MeshInstance3D).visible = false
	_b_flames.clear()
	_booster_root.queue_free()
	_booster_root = null
	booster_level = 0.0
	return holder


func has_boosters_attached() -> bool:
	return _booster_root != null


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


## Procedural second stage: dark interstage frustum (leaves with stage 1) + white upper tank + engine bell.
func _make_upper(h: float) -> Node3D:
	var root := Node3D.new()
	var inter := Node3D.new()
	inter.name = "interstage"
	root.add_child(inter)
	var fm := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.height = 3.0
	fc.bottom_radius = RADIUS
	fc.top_radius = 1.9
	fc.radial_segments = 40
	fm.mesh = fc
	fm.position = Vector3(0, 1.5, 0)
	fm.material_override = _mat(Color(0.16, 0.18, 0.23), 0.5, 0.45)
	inter.add_child(fm)
	var bell := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.height = 2.4
	bc.top_radius = 0.35
	bc.bottom_radius = 0.95
	bc.radial_segments = 24
	bell.mesh = bc
	bell.position = Vector3(0, 1.4, 0)
	bell.material_override = _mat(Color(0.35, 0.37, 0.43), 0.8, 0.35)
	root.add_child(bell)
	var th := h - 3.0
	var tm := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.height = th
	tc.top_radius = 1.9
	tc.bottom_radius = 1.9
	tc.radial_segments = 40
	tm.mesh = tc
	tm.position = Vector3(0, 3.0 + th * 0.5, 0)
	tm.material_override = _mat(Color(0.92, 0.94, 0.97), 0.25, 0.4)
	root.add_child(tm)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.height = 0.5
	bm.top_radius = 1.93
	bm.bottom_radius = 1.93
	bm.radial_segments = 40
	band.mesh = bm
	band.position = Vector3(0, 3.0 + th * 0.8, 0)
	var bmat := _mat(Color(1.0, 0.45, 0.1), 0.2, 0.5)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.4, 0.08)
	bmat.emission_energy_multiplier = 0.35
	band.material_override = bmat
	root.add_child(band)
	return root


## Throws stage 1 (engine, tank, interstage, branding) off the stack. The parts keep their world transform and are
## re-parented under a new holder (returned) so the director can animate their drift. Stage 2 becomes the thrusting stage.
func separate_stage1(new_parent: Node) -> Node3D:
	var holder := Node3D.new()
	new_parent.add_child(holder)
	holder.global_transform = _stack.global_transform
	var movers: Array[Node3D] = []
	for k in ["engine", "tank"]:
		if _parts.has(k):
			movers.append(_parts[k])
			_parts.erase(k)
	if _parts.has("upper"):
		var inter := (_parts["upper"] as Node3D).get_node_or_null("interstage")
		if inter != null:
			movers.append(inter)
	for l in _brand:
		movers.append(l)
	_brand.clear()
	for n in movers:
		var xf := n.global_transform
		n.get_parent().remove_child(n)
		holder.add_child(n)
		n.global_transform = xf
	stage2_active = true
	_er_override = 1.0
	var eh := _slot_h("engine", _id_or_default("engine"))
	var th := _slot_h("tank", _id_or_default("tank"))
	_fx_root.position = Vector3(0, -total_height() * 0.5 + eh + th + 0.5, 0)
	return holder


## World position of the interface between stage 1 and stage 2 (separation effects).
func stage_interface_world() -> Vector3:
	var eh := _slot_h("engine", _id_or_default("engine"))
	var th := _slot_h("tank", _id_or_default("tank"))
	return _stack.to_global(Vector3(0, eh + th + 1.5, 0))


func _make_ghost(slot: String) -> Node3D:
	var id := str(DEFAULTS[slot])
	var h := _slot_h(slot, id)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.height = h
	cm.radial_segments = 40
	match slot:
		"nose":
			cm.top_radius = 0.2
			cm.bottom_radius = RADIUS
		"engine":
			cm.top_radius = RADIUS
			cm.bottom_radius = 1.3
		_:
			cm.top_radius = RADIUS
			cm.bottom_radius = RADIUS
	mi.mesh = cm
	mi.position = Vector3.ZERO
	mi.material_override = _holo
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	mi.position = Vector3(0, h * 0.5, 0)
	holder.add_child(mi)
	return holder


func _add_branding(eh: float, th: float) -> void:
	for side in [0, 1]:
		var l := Label3D.new()
		l.text = "ZENITH"
		l.font_size = 180
		l.pixel_size = 0.0135
		l.modulate = Color(0.12, 0.14, 0.19)
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(0, eh + th * 0.5, RADIUS + 0.05) if side == 0 else Vector3(0, eh + th * 0.5, -RADIUS - 0.05)
		l.rotation_degrees = Vector3(0, 0 if side == 0 else 180, 90)
		_stack.add_child(l)
		_brand.append(l)


## Takes the nose cone off the stack (keeps its world transform) and returns it.
func detach_nose(new_parent: Node) -> Node3D:
	if not _parts.has("nose"):
		return null
	var n: Node3D = _parts["nose"]
	var xf := n.global_transform
	_parts.erase("nose")
	n.get_parent().remove_child(n)
	new_parent.add_child(n)
	n.global_transform = xf
	return n


func nose_base_world() -> Vector3:
	var sp := slot_span("nose")
	return _stack.to_global(Vector3(0, sp.x, 0))


func set_nose_visible(v: bool) -> void:
	nose_visible = v
	if _parts.has("nose"):
		(_parts["nose"] as Node3D).visible = v


# ------------------------------------------------------------------- engine FX --
func _build_fx() -> void:
	_fx_root = Node3D.new()
	add_child(_fx_root)
	# flame cones (shader-animated)
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = load("res://Core3D/shaders/flame.gdshader")
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = load("res://Core3D/shaders/flame.gdshader")
	_core_mat.set_shader_parameter("edge_col", Vector3(1.0, 0.8, 0.5))
	var cone := CylinderMesh.new()
	cone.top_radius = 1.0
	cone.bottom_radius = 0.12
	cone.height = 1.0
	cone.radial_segments = 24
	cone.rings = 1
	_flame = MeshInstance3D.new()
	_flame.mesh = cone
	_flame.material_override = _flame_mat
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(_flame)
	_core = MeshInstance3D.new()
	_core.mesh = cone
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(_core)
	# glowing plume particles
	_plume = Fx3D.particles(170, 0.55, 5.0, true, true)
	var pm := Fx3D.pmat(_plume)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 5.0
	pm.initial_velocity_min = 55.0
	pm.initial_velocity_max = 95.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.color_ramp = Fx3D.gradient_tex(
		[Color(1.0, 0.95, 0.75, 0.95), Color(1.0, 0.55, 0.15, 0.75), Color(0.9, 0.25, 0.05, 0.0)],
		[0.0, 0.35, 1.0])
	pm.scale_curve = Fx3D.curve_tex([Vector2(0, 1), Vector2(1, 0.25)])
	_fx_root.add_child(_plume)
	# smoke trail in world space
	_smoke = Fx3D.particles(260, 7.0, 11.0, false, false)
	var sm := Fx3D.pmat(_smoke)
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 22.0
	sm.initial_velocity_min = 8.0
	sm.initial_velocity_max = 22.0
	sm.gravity = Vector3.ZERO
	sm.damping_min = 1.0
	sm.damping_max = 2.5
	sm.scale_min = 0.8
	sm.scale_max = 1.8
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 1.8
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.color_ramp = Fx3D.gradient_tex(
		[Color(1.0, 0.82, 0.6, 0.0), Color(0.93, 0.9, 0.86, 0.5), Color(0.62, 0.63, 0.67, 0.3), Color(0.5, 0.52, 0.57, 0.0)],
		[0.0, 0.08, 0.45, 1.0])
	sm.scale_curve = Fx3D.curve_tex([Vector2(0, 0.4), Vector2(1, 2.6)])
	_fx_root.add_child(_smoke)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.omni_range = 140.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_fx_root.add_child(_light)
	_fx_root.position.y = 0.0
	set_thrust(0.0, 1.0, Vector3.ZERO)


## thrust 0..1, ambient = air density factor 0..1 (smoke + flame shape), drift = smoke wind (m/s).
func set_thrust(t: float, ambient: float, drift: Vector3) -> void:
	_thrust = t
	var on := t > 0.02
	var er := float(ENGINE_R[_id_or_default("engine")]) if _er_override < 0.0 else _er_override
	var vac := 1.0 - clampf(ambient, 0.0, 1.0)
	_vac = vac
	var length := (16.0 + 34.0 * t) * (0.7 + er * 0.35) * (1.0 + vac * 0.8)
	var width := 1.0 + vac * 1.1
	_flame.visible = on
	_core.visible = on
	_flame.scale = Vector3(er * 1.15 * width, length, er * 1.15 * width)
	_flame.position = Vector3(0, -length * 0.5, 0)
	_core.scale = Vector3(er * 0.62 * width, length * 0.55, er * 0.62 * width)
	_core.position = Vector3(0, -length * 0.275, 0)
	_flame_mat.set_shader_parameter("intensity", t * 1.1)
	_core_mat.set_shader_parameter("intensity", t * 1.25)
	_flame_mat.set_shader_parameter("vac", vac)
	_core_mat.set_shader_parameter("vac", vac)
	# in vacuum the plume spreads and gets thinner; near the ground it is hot and dense
	Fx3D.pmat(_plume).spread = 4.0 + 16.0 * vac
	_plume.amount_ratio = lerpf(1.0, 0.45, vac)
	_plume.emitting = on
	Fx3D.pmat(_plume).initial_velocity_min = 40.0 + 40.0 * t
	Fx3D.pmat(_plume).initial_velocity_max = 70.0 + 55.0 * t
	_smoke.emitting = on and ambient > 0.03
	Fx3D.pmat(_smoke).gravity = drift
	_smoke.amount_ratio = clampf(ambient * 1.4, 0.05, 1.0)
	_light.light_energy = t * 9.0 * (0.6 + 0.4 * ambient + 0.3)


func _process(delta: float) -> void:
	_t += delta
	# booster exhausts follow booster_level
	for f in _b_flames:
		var fm: MeshInstance3D = f["mesh"]
		var on := booster_level > 0.02
		fm.visible = on
		if on:
			var len := (9.0 + 18.0 * booster_level) * (1.0 + _vac * 0.6)
			fm.scale = Vector3(1.0 + _vac * 0.8, len, 1.0 + _vac * 0.8)
			fm.position = Vector3(0, -len * 0.5 + 0.2, 0)
			(f["mat"] as ShaderMaterial).set_shader_parameter("intensity", booster_level * 1.1)
			(f["mat"] as ShaderMaterial).set_shader_parameter("vac", _vac)
	if _light != null and _thrust > 0.02:
		_light.light_energy = _thrust * 9.0 * (0.85 + 0.15 * sin(_t * 41.0))
	if _holo != null:
		_holo.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 3.0))
