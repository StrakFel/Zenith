extends MissionBase
## Mission 4, phase 2 - deploy the constellation. The carrier circles the Earth in a slightly lower (faster) orbit than the
## satellites it has already released, so it drifts around the ring relative to them (phasing). Release each new satellite
## when the carrier is exactly one slot (360 / N degrees) further on. Changing the drift speed burns the propellant that the
## launch left over; the dispenser's tolerance and the satellites' condition (launch damage) decide how good the result is.

const RING_R := 52.0
const PLANET_R := 30.0
const LEVELS := [0.0, 5.0, 10.0, 17.0]          # drift speed (deg/s) relative to the released satellites
const DV_STEP := 40.0                           # m/s per drift-speed step
const TIME_LIMIT := 260.0

var launch: Dictionary = {}
var design: Dictionary = {}
var n := 4
var tol := 5.0                                  # release tolerance (deg)
var cap_each := 1.0
var phi := 0.0                                  # carrier angle relative to the first satellite (deg, 0..360)
var level := 1
var dv_left := 0.0
var dv_used := 0.0
var elapsed := 0.0
var released: Array[float] = []                 # angles of the released satellites (deg)
var errors: Array[float] = []                   # placement errors (deg)
var started := false
var dev_autopilot := false
var inspecting := false

var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var carrier: Node3D
var _slot_nodes: Array = []
var _sat_nodes: Array = []
var _hud_root: Control
var _lbl: Dictionary = {}
var _hint: Label
var _hint_panel: PanelContainer
var cam_hint: CameraHint
var _t := 0.0
var _done := false


func _init() -> void:
	mission_id = "m4_constellation"
	launch = GameState.session.get("launch", {})
	design = GameState.session.get("design", {"sat": "small", "count": "4", "disp": "simple"})
	if launch.is_empty():
		launch = {"hull": 100.0, "orbit_q": 1.0, "dv_left": 300.0, "fuel_frac": 0.3, "cost": 200, "budget": 330, "waste": 0.0,
			"booster_waste": 0.0, "fairing_early": false, "mean_km": 320.0}
	var cls: Dictionary = LaunchProfiles.CON_SAT[design["sat"]]
	n = int(LaunchProfiles.CON_COUNT[design["count"]]["n"])
	tol = 5.0 * float(LaunchProfiles.CON_DISP[design["disp"]]["tol"])
	cap_each = float(cls["cap"])
	dv_left = float(launch["dv_left"])


func _briefing_data() -> Dictionary:
	return {
		"title": "M4_TITLE",
		"objectives": ["CON_OPS_1", "CON_OPS_2", "CON_OPS_3", "CON_OPS_4"],
		"controls": [["MOUSE", "M1_CTRL_DRAG"], ["W S", "CON_CTRL_SPEED"], ["SPACE", "CON_CTRL_RELEASE"], ["ESC", "M1_CTRL_PAUSE"]],
	}


func _build_mission() -> void:
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.planet_pivot.visible = false
	stage.sun_to = Vector3(0.6, 0.35, 0.7).normalized()
	stage.apply_look()
	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 45.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.user_can_engage = true
	orbit.min_dist = 25.0
	orbit.max_dist = 400.0
	var earth := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PLANET_R
	sm.height = PLANET_R * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	earth.mesh = sm
	var pm := ShaderMaterial.new()
	pm.shader = load("res://Core3D/shaders/planet.gdshader")
	pm.set_shader_parameter("sun_dir", stage.sun_to)
	earth.material_override = pm
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)
	var atm := MeshInstance3D.new()
	var asp := SphereMesh.new()
	asp.radius = PLANET_R * 1.06
	asp.height = PLANET_R * 2.12
	asp.radial_segments = 64
	asp.rings = 32
	atm.mesh = asp
	var am := ShaderMaterial.new()
	am.shader = load("res://Core3D/shaders/atmosphere.gdshader")
	am.set_shader_parameter("sun_dir", stage.sun_to)
	atm.material_override = am
	atm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(atm)
	_build_ring()
	_build_carrier()
	orbit.add_obstacle(earth, PLANET_R * 1.05)
	var hl := CanvasLayer.new()
	hl.layer = 5
	add_child(hl)
	_hud_root = Control.new()
	_hud_root.theme = UIKit.get_ui_theme()
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hl.add_child(_hud_root)
	_build_hud()
	orbit.engaged_changed.connect(func(on: bool):
		inspecting = on
		cam_hint.set_inspect(on))


func _build_ring() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in 129:
		var a := TAU * float(i) / 128.0
		im.surface_set_color(Color(0.3, 0.8, 1.0, 0.8))
		im.surface_add_vertex(Vector3(cos(a), 0.0, sin(a)) * RING_R)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_carrier() -> void:
	carrier = Node3D.new()
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.1
	cm.bottom_radius = 1.4
	cm.height = 4.0
	cm.radial_segments = 24
	body.mesh = cm
	body.rotation_degrees = Vector3(0, 0, 90)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.9, 0.92, 0.96)
	bm.metallic = 0.4
	bm.roughness = 0.35
	body.material_override = bm
	carrier.add_child(body)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 0.8, 1.0)
	glow.omni_range = 14.0
	glow.light_energy = 1.4
	carrier.add_child(glow)
	var tip := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	tip.mesh = sp
	tip.position = Vector3(2.4, 0, 0)
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.65, 0.2)
	tip.material_override = tm
	carrier.add_child(tip)
	add_child(carrier)
	for k in range(1, n):
		var a := deg_to_rad(360.0 * float(k) / float(n))
		var slot := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 1.6
		ss.height = 3.2
		slot.mesh = ss
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
		slot.material_override = smat
		slot.position = _pos(a)
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
		var lab := Label3D.new()
		lab.text = str(k + 1)
		lab.font_size = 48
		lab.pixel_size = 0.03
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.position = Vector3(0, 3.2, 0)
		slot.add_child(lab)
		_slot_nodes.append(slot)


func _pos(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, sin(a)) * RING_R


func _build_hud() -> void:
	var p := UIKit.panel()
	p.position = Vector2(16, 16)
	_hud_root.add_child(p)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 3)
	p.add_child(g)
	for r in [["CON_H_DEPLOYED", "dep"], ["CON_H_NEXT", "next"], ["CON_H_ERR", "err"], ["CON_H_SPEED", "speed"], ["CON_H_DV", "dv"], ["CON_H_TIME", "time"]]:
		g.add_child(UIKit.label(r[0], 15, UIKit.C_MUTED))
		var v := UIKit.label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size.x = 120
		g.add_child(v)
		_lbl[r[1]] = v
	_hint_panel = UIKit.panel()
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_panel.offset_left = -330
	_hint_panel.offset_right = 330
	_hint_panel.offset_top = -92
	_hint_panel.offset_bottom = -18
	_hud_root.add_child(_hint_panel)
	_hint = UIKit.label("", 17, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_panel.add_child(_hint)
	cam_hint = CameraHint.new()
	_hud_root.add_child(cam_hint)
	cam_hint.setup(false, -1.0, true)


func _on_mission_start() -> void:
	started = true
	released.clear()
	errors.clear()
	phi = 0.0
	level = 1


func _wrap(d: float) -> float:
	return wrapf(d, -180.0, 180.0)


func _target() -> float:
	return 360.0 * float(released.size()) / float(n)


func _process(delta: float) -> void:
	_t += delta
	var az := 0.35 + 0.12 * sin(_t * 0.1)
	orbit.update(delta, Vector3(sin(az) * 40.0, 72.0, cos(az) * 118.0), Vector3(0, 0, 0), 45.0)
	if not started or ended or _done:
		return
	if inspecting:
		return
	elapsed += delta
	if dev_autopilot:
		_autopilot()
	phi = fposmod(phi + float(LEVELS[level]) * delta, 360.0)
	carrier.position = _pos(deg_to_rad(phi))
	carrier.rotation.y = -deg_to_rad(phi) - PI * 0.5
	for i in _slot_nodes.size():
		var sl := _slot_nodes[i] as MeshInstance3D
		var is_next := (i + 1) == released.size()
		var m := sl.material_override as StandardMaterial3D
		var close := absf(_wrap(phi - 360.0 * float(i + 1) / float(n))) <= tol
		m.albedo_color = Color(0.3, 1.0, 0.5, 0.6) if (is_next and close) else (Color(1.0, 0.7, 0.2, 0.5) if is_next else Color(0.3, 0.9, 1.0, 0.25))
		sl.visible = (i + 1) >= released.size()
	_update_hud()
	if elapsed >= TIME_LIMIT:
		_finish(true)


func _unhandled_input(event: InputEvent) -> void:
	if not started or ended or _done or inspecting or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_release()
		KEY_W, KEY_UP:
			_set_level(level + 1)
		KEY_S, KEY_DOWN:
			_set_level(level - 1)


func _set_level(l: int) -> void:
	l = clampi(l, 0, LEVELS.size() - 1)
	if l == level:
		return
	var cost := absf(float(l - level)) * DV_STEP
	if cost > dv_left:
		_hint.text = "CON_HINT_NODV"
		return
	dv_left -= cost
	dv_used += cost
	level = l
	Sfx.play("whoosh", -12.0)


func _release() -> void:
	if released.size() >= n:
		return
	var tgt := _target()
	var err := absf(_wrap(phi - tgt))
	var ang := phi
	if released.is_empty():
		phi = 0.0
		ang = 0.0
		err = 0.0
	released.append(ang)
	errors.append(err)
	var sat := (load("res://Assets/Models/satellite.glb") as PackedScene).instantiate() as Node3D
	sat.scale = Vector3.ONE * 0.45
	add_child(sat)
	sat.position = _pos(deg_to_rad(ang))
	sat.rotation.y = -deg_to_rad(ang)
	_sat_nodes.append(sat)
	Fx3D.burst(self, sat.global_position, Color(0.6, 0.9, 1.0), 40, 10.0, 1.2, 0.9)
	Sfx.play("beep")
	if released.size() >= n:
		_finish(false)


func _autopilot() -> void:
	# test pilot: fast drift towards the next slot, slow down near it, release inside the tolerance
	if released.is_empty():
		_release()
		return
	var diff := fposmod(_target() - phi, 360.0)
	if diff > 40.0 and level != 3 and dv_left > DV_STEP * 3.0:
		_set_level(3)
	elif diff <= 40.0 and diff > 14.0 and level != 2:
		_set_level(2)
	elif diff <= 14.0 and level != 1:
		_set_level(1)
	if absf(_wrap(phi - _target())) <= tol * 0.35:
		_release()


func _update_hud() -> void:
	var tgt := _target()
	(_lbl["dep"] as Label).text = "%d / %d" % [released.size(), n]
	(_lbl["next"] as Label).text = ("%d deg" % int(round(tgt))) if released.size() < n else "-"
	var err := absf(_wrap(phi - tgt))
	var el := _lbl["err"] as Label
	el.text = "%.1f deg (+-%.0f)" % [err, tol]
	el.add_theme_color_override("font_color", UIKit.C_GOOD if err <= tol else (UIKit.C_WARN if err <= tol * 3.0 else Color.WHITE))
	(_lbl["speed"] as Label).text = "%d / 3" % level
	(_lbl["dv"] as Label).text = "%d %s" % [int(dv_left), tr("UNIT_MS")]
	(_lbl["dv"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if dv_left < DV_STEP else Color.WHITE)
	(_lbl["time"] as Label).text = "%d s" % int(maxf(TIME_LIMIT - elapsed, 0.0))
	_hint.text = "CON_HINT_FIRST" if released.is_empty() else ("CON_HINT_RELEASE" if err <= tol else "CON_HINT_DRIFT")


# ----------------------------------------------------------------------------- result
func _finish(timeout: bool) -> void:
	if _done:
		return
	_done = true
	Sfx.stop_all_loops()
	var count := released.size()
	if count == 0:
		finish(false, 0, 0, [["R_SATS", "0 / %d" % n]], "CON_FAIL_NONE", 1.0, {"tips": ["CON_TIP_NONE"]})
		return
	var angs := released.duplicate()
	angs.sort()
	var ideal := 360.0 / float(n)
	var gap_err := 0.0
	for i in angs.size():
		var nxt: float = angs[(i + 1) % angs.size()] + (360.0 if i == angs.size() - 1 else 0.0)
		gap_err += absf((nxt - angs[i]) - 360.0 / float(angs.size()))
	var uniformity := clampf(1.0 - gap_err / float(angs.size()) / ideal, 0.0, 1.0)
	if count < n:
		uniformity *= float(count) / float(n)
	var hull := clampf(float(launch["hull"]) / 100.0, 0.0, 1.0)
	var working := float(count) * lerpf(0.7, 1.0, hull)
	var oq := float(launch["orbit_q"])
	var coverage := 1.0 - exp(-0.42 * cap_each * working * lerpf(0.5, 1.0, uniformity) * lerpf(0.7, 1.0, oq))
	var stars := 0
	if coverage >= 0.35:
		stars = 1
	if coverage >= 0.60:
		stars = 2
	if coverage >= 0.85 and hull >= 0.8:
		stars = 3
	var prop_margin := clampf(dv_left / maxf(float(launch["dv_left"]), 1.0), 0.0, 1.0)
	var score := stars * 1000 + int(coverage * 1500.0) + int(uniformity * 500.0) + int(prop_margin * 200.0)
	var launch_r := clampf(hull * 0.6 + oq * 0.25 + (0.15 if not bool(launch["fairing_early"]) else 0.0), 0.0, 1.0)
	launch_r *= 1.0 - clampf(float(launch["waste"]) * 0.3 + float(launch["booster_waste"]) * 0.2, 0.0, 0.3)
	var res: Array = [
		["R_SATS", "%d / %d" % [count, n]],
		["R_UNIFORM", "%d%%" % int(uniformity * 100.0)],
		["R_COVERAGE", "%d%%" % int(coverage * 100.0)],
		["R_PHASING_DV", "%d %s" % [int(dv_used), tr("UNIT_MS")]],
		["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])],
		["R_BUDGET_USED", "%s / %s" % [Units.money(int(launch["cost"])), Units.money(int(launch["budget"]))]],
		["R_SCORE", str(score)],
	]
	var tips: Array = []
	if uniformity < 0.8:
		tips.append("CON_TIP_SPACING")
	if hull < 0.85:
		tips.append("CON_TIP_HULL")
	if cap_each * float(n) < 5.0:
		tips.append("CON_TIP_COUNT")
	if oq < 0.8:
		tips.append("CON_TIP_ORBIT")
	if timeout and count < n:
		tips.append("CON_TIP_TIME")
	if tips.is_empty():
		tips.append("CON_TIP_GOOD")
	var extra := {"segments": [["SEG_LAUNCH", launch_r], ["SEG_SPACE", uniformity], ["SEG_GROUND", clampf(coverage, 0.0, 1.0)], ["SEG_USER", clampf(coverage, 0.0, 1.0)]],
		"science": coverage, "science_note": "CON_NOTE", "tips": tips, "user": "CON_USER_%d" % M1Design.science_tier(coverage)}
	finish(stars > 0, stars, score, res, "CON_WIN" if stars > 0 else "CON_FAIL_COVER", 1.0, extra)
