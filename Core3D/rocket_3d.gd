class_name Rocket3D
extends Node3D
## Modular 3D rocket built from the Blender-generated parts (nose + tank + engine),
## with hologram "ghosts" for empty slots, engine flame/plume/smoke and a light.
## Origin = centre of the stack. Local +Y is the nose direction.

const RADIUS := 2.0
const NOSE_H := {"std": 12.0, "aero": 18.0}
const TANK_H := {"s": 14.0, "m": 22.0, "l": 32.0}
const ENGINE_H := {"spark": 5.5, "kestrel": 7.0, "phoenix": 8.5}
const ENGINE_R := {"spark": 1.25, "kestrel": 1.75, "phoenix": 1.9}
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
		_:
			return float(ENGINE_H[id])


func _id_or_default(slot: String) -> String:
	var id := str(build.get(slot, ""))
	return id if id != "" else str(DEFAULTS[slot])


func total_height() -> float:
	return _slot_h("engine", _id_or_default("engine")) + _slot_h("tank", _id_or_default("tank")) \
		+ _slot_h("nose", _id_or_default("nose"))


## y range (bottom, top) of a slot in the stack frame (origin at the bottom).
func slot_span(slot: String) -> Vector2:
	var eh := _slot_h("engine", _id_or_default("engine"))
	var th := _slot_h("tank", _id_or_default("tank"))
	var nh := _slot_h("nose", _id_or_default("nose"))
	match slot:
		"engine":
			return Vector2(0.0, eh)
		"tank":
			return Vector2(eh, eh + th)
		_:
			return Vector2(eh + th, eh + th + nh)


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
	var ys := {"engine": 0.0, "tank": eh, "nose": eh + th}
	for slot in ["engine", "tank", "nose"]:
		var id := str(build.get(slot, ""))
		if id != "":
			var scene: PackedScene = load("res://Assets/Models/rocket_%s_%s.glb" % [slot, id])
			var inst: Node3D = scene.instantiate()
			inst.position = Vector3(0, ys[slot], 0)
			_stack.add_child(inst)
			_parts[slot] = inst
		elif ghosts_visible:
			var g := _make_ghost(slot)
			g.position = Vector3(0, ys[slot], 0)
			_stack.add_child(g)
			_ghosts[slot] = g
	if str(build.get("tank", "")) != "":
		_add_branding(eh, th)
	if _parts.has("nose"):
		(_parts["nose"] as Node3D).visible = nose_visible
	_stack.position = Vector3(0, -total_height() * 0.5, 0)
	var er := float(ENGINE_R[_id_or_default("engine")])
	_fx_root.position = Vector3(0, -total_height() * 0.5 + 0.2, 0)
	_flame.scale = Vector3(er * 1.15, 1.0, er * 1.15)
	_core.scale = Vector3(er * 0.7, 1.0, er * 0.7)


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
	_smoke = Fx3D.particles(160, 6.0, 9.0, false, false)
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
		[Color(0.95, 0.93, 0.9, 0.0), Color(0.88, 0.88, 0.9, 0.55), Color(0.55, 0.57, 0.62, 0.0)],
		[0.0, 0.12, 1.0])
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
	var er := float(ENGINE_R[_id_or_default("engine")])
	var vac := 1.0 - clampf(ambient, 0.0, 1.0)
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
	_plume.emitting = on
	Fx3D.pmat(_plume).initial_velocity_min = 40.0 + 40.0 * t
	Fx3D.pmat(_plume).initial_velocity_max = 70.0 + 55.0 * t
	_smoke.emitting = on and ambient > 0.03
	Fx3D.pmat(_smoke).gravity = drift
	_smoke.amount_ratio = clampf(ambient * 1.2, 0.05, 1.0)
	_light.light_energy = t * 9.0 * (0.6 + 0.4 * ambient + 0.3)


func _process(delta: float) -> void:
	_t += delta
	if _light != null and _thrust > 0.02:
		_light.light_energy = _thrust * 9.0 * (0.85 + 0.15 * sin(_t * 41.0))
	if _holo != null:
		_holo.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 3.0))
