extends Node3D
## Mission selection: a 3D "mission map". Each mission has its own 3D preview floating above the
## Earth (rocket / satellite + astronaut / station + spacecraft / classified bodies). Pick a
## mission on the left, read its description, difficulty and progress on the right, and look
## around freely with the orbit camera (LMB rotate, wheel zoom, RMB pan, R reset, double-click focus).

const SPACING := 140.0
const VIEW_DIST := [118.0, 66.0, 96.0, 100.0, 108.0]

var stage: SpaceStage
var camera: Camera3D
var orbit: OrbitCameraController
var _groups: Array[Node3D] = []
var _tabs: Array[Button] = []
var _detail: Dictionary = {}
var _sel := 0
var _t := 0.0
var _cur_focus := Vector3.ZERO
var _astro: Node3D
var _holos: Array[Node3D] = []
var _first := true


class MissionTab extends Button:
	var mission: Dictionary
	var index := 0

	func setup(i: int, m: Dictionary, group: ButtonGroup) -> void:
		index = i
		mission = m
		toggle_mode = true
		button_group = group
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(340, 64)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var id: String = m["id"]
		var unlocked := MissionRegistry.is_unlocked(id)
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		h.add_theme_constant_override("separation", 12)
		add_child(h)
		var num := UIKit.label(str(i + 1), 28, UIKit.C_ORANGE if unlocked else UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		num.custom_minimum_size.x = 26
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(num)
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		var t := UIKit.label(str(m["title"]), 17, Color.WHITE if unlocked else UIKit.C_MUTED)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var st_key := "MS_STATUS_READY"
		if not MissionRegistry.is_available(id):
			st_key = "COMING_SOON"
		elif not unlocked:
			st_key = "LOCKED"
		elif GameState.is_completed(id):
			st_key = "MS_STATUS_DONE_SHORT"
		var sub := UIKit.label(st_key, 12, UIKit.C_MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if st_key == "MS_STATUS_DONE_SHORT":
			sub.text = "★".repeat(GameState.get_stars(id)) + "☆".repeat(3 - GameState.get_stars(id))
			sub.add_theme_color_override("font_color", UIKit.C_ORANGE)
		v.add_child(sub)
		if not unlocked:
			modulate = Color(1, 1, 1, 0.75)


func _ready() -> void:
	Sfx.music(true)
	stage = SpaceStage.new()
	add_child(stage)
	stage.set_look("space")
	stage.place_planet_view(2_400_000.0, 15.0, 0.0)
	stage.spin = 0.0007
	camera = Camera3D.new()
	camera.far = 6_000_000.0
	camera.near = 0.3
	camera.fov = 42.0
	add_child(camera)
	camera.make_current()
	orbit = OrbitCameraController.new()
	add_child(orbit)
	orbit.setup(camera)
	orbit.max_dist = 700.0
	orbit.min_dist = 4.0
	_build_groups()
	_build_ui()
	_select(_default_selection(), true)


func _default_selection() -> int:
	var id := GameState.next_mission_id()
	if id == "":
		id = MissionRegistry.last_playable_id()
	return maxi(MissionRegistry.index_of(id), 0)


# ------------------------------------------------------------- 3D previews ----
func _holo_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://Core3D/shaders/hologram.gdshader")
	return m


func _build_groups() -> void:
	for i in 5:
		var g := Node3D.new()
		g.position = Vector3((i - 2) * SPACING, 0, 0)
		add_child(g)
		_groups.append(g)
	# --- 1: rocket
	var rk := Rocket3D.new()
	_groups[0].add_child(rk)
	rk.set_build({"nose": "aero", "tank": "l", "engine": "kestrel"}, false)
	rk.set_thrust(0.55, 0.0, Vector3.ZERO)
	orbit.add_focusable(rk, 30.0, 95.0)
	orbit.add_obstacle(rk, 5.0, 28.0)
	# --- 2: damaged satellite + astronaut
	var sat := (load("res://Assets/Models/satellite.glb") as PackedScene).instantiate() as Node3D
	_groups[1].add_child(sat)
	var wing := sat.find_child("wing_L", true, false)
	if wing is Node3D:
		(wing as Node3D).rotation.z = 0.55
	var dish := sat.find_child("dish", true, false)
	if dish is Node3D:
		(dish as Node3D).rotation.z = -0.75
	for n in ["inst_mag", "inst_spec"]:
		var nn := sat.find_child(n, true, false)
		if nn is Node3D:
			(nn as Node3D).visible = false
	_astro = (load("res://Assets/Models/astronaut.glb") as PackedScene).instantiate() as Node3D
	_astro.scale = Vector3.ONE * 1.6
	_astro.position = Vector3(-17, -5, 12)
	_groups[1].add_child(_astro)
	orbit.add_focusable(sat, 16.0, 62.0)
	orbit.add_focusable(_astro, 3.0, 12.0)
	orbit.add_obstacle(sat, 9.0)
	orbit.add_obstacle(_astro, 2.0)
	# --- 3: station + spacecraft
	var st := (load("res://Assets/Models/station.glb") as PackedScene).instantiate() as Node3D
	st.scale = Vector3.ONE * 0.5
	st.position = Vector3(-30, 0, 0)
	_groups[2].add_child(st)
	var ship := (load("res://Assets/Models/ship.glb") as PackedScene).instantiate() as Node3D
	ship.position = Vector3(-48, 3, 10)
	ship.rotation.z = -0.1
	_groups[2].add_child(ship)
	var center := Marker3D.new()
	_groups[2].add_child(center)
	orbit.add_focusable(center, 40.0, 100.0)
	orbit.add_focusable(ship, 6.0, 26.0)
	orbit.add_obstacle(center, 24.0)
	orbit.add_obstacle(ship, 5.0)
	# --- 4 & 5: classified (hologram) bodies - missions still being designed
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 26.0
	sm.height = 52.0
	sm.radial_segments = 48
	sm.rings = 24
	moon.mesh = sm
	moon.material_override = _holo_mat()
	_groups[3].add_child(moon)
	_holos.append(moon)
	var giant := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 22.0
	gm.height = 44.0
	gm.radial_segments = 48
	gm.rings = 24
	giant.mesh = gm
	giant.material_override = _holo_mat()
	_groups[4].add_child(giant)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 34.0
	tm.outer_radius = 44.0
	ring.mesh = tm
	ring.scale = Vector3(1, 0.04, 1)
	ring.rotation.x = 0.35
	ring.material_override = _holo_mat()
	_groups[4].add_child(ring)
	_holos.append(giant)
	for g in [_groups[3], _groups[4]]:
		var lab := Label3D.new()
		lab.text = tr("MS_SECRET")
		lab.font_size = 64
		lab.pixel_size = 0.07
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(0.5, 0.85, 1.0, 0.9)
		lab.no_depth_test = true
		lab.position = Vector3(0, 44, 0)
		g.add_child(lab)
	orbit.add_focusable(moon, 26.0, 90.0)
	orbit.add_focusable(giant, 22.0, 90.0)
	orbit.add_obstacle(moon, 27.0)
	orbit.add_obstacle(giant, 23.0)
	orbit.add_obstacle(stage.planet_pivot, SpaceStage.R * 1.01)


# --------------------------------------------------------------------- UI -----
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var screen := Control.new()
	screen.theme = UIKit.get_ui_theme()
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(screen)

	var left := VBoxContainer.new()
	left.position = Vector2(30, 26)
	left.add_theme_constant_override("separation", 8)
	screen.add_child(left)
	var head := UIKit.label("MISSIONS_TITLE", 38, Color.WHITE)
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	head.add_theme_constant_override("shadow_offset_y", 4)
	left.add_child(head)
	var group := ButtonGroup.new()
	var ms := MissionRegistry.all()
	for i in ms.size():
		var tab := MissionTab.new()
		tab.setup(i, ms[i], group)
		tab.pressed.connect(_select.bind(i, false))
		left.add_child(tab)
		_tabs.append(tab)
		tab.modulate.a = 0.0
		create_tween().tween_property(tab, "modulate:a", tab.modulate.a if false else (1.0 if MissionRegistry.is_unlocked(str(ms[i]["id"])) else 0.78), 0.4).set_delay(0.08 * i)
	var back := UIKit.button("BTN_BACK", Vector2(340, 46))
	back.pressed.connect(func(): Router.go_to(Router.MAIN_MENU))
	left.add_child(back)

	# ---- detail panel (right)
	var p := UIKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -470
	p.offset_right = -26
	p.offset_top = 26
	p.offset_bottom = -26
	screen.add_child(p)
	var v := UIKit.vbox(10)
	p.add_child(v)
	_detail["num"] = UIKit.label("", 15, UIKit.C_ORANGE)
	v.add_child(_detail["num"])
	_detail["title"] = UIKit.label("", 30, Color.WHITE)
	(_detail["title"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_detail["title"] as Label).custom_minimum_size.x = 400
	v.add_child(_detail["title"])
	_detail["desc"] = UIKit.label("", 16, UIKit.C_TEXT)
	(_detail["desc"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail["desc"])
	v.add_child(UIKit.label("MS_LEARN", 15, UIKit.C_ACCENT))
	_detail["skill"] = UIKit.label("", 14, UIKit.C_MUTED)
	(_detail["skill"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail["skill"])
	v.add_child(HSeparator.new())
	var drow := UIKit.hbox(10)
	drow.add_child(UIKit.label("MS_DIFFICULTY", 16, UIKit.C_ACCENT))
	_detail["diff"] = UIKit.label("", 20, UIKit.C_ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
	(_detail["diff"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drow.add_child(_detail["diff"])
	v.add_child(drow)
	_detail["diff_word"] = UIKit.label("", 14, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(_detail["diff_word"])
	var prow := UIKit.hbox(10)
	prow.add_child(UIKit.label("MS_PROGRESS", 16, UIKit.C_ACCENT))
	_detail["stars"] = UIKit.label("", 26, UIKit.C_ORANGE, HORIZONTAL_ALIGNMENT_RIGHT)
	(_detail["stars"] as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(_detail["stars"])
	v.add_child(prow)
	_detail["best"] = UIKit.label("", 14, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(_detail["best"])
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_detail["status"] = UIKit.label("", 15, UIKit.C_TEXT)
	(_detail["status"] as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail["status"])
	_detail["go"] = UIKit.button("MS_LAUNCH", Vector2(0, 58))
	(_detail["go"] as Button).add_theme_font_size_override("font_size", 22)
	(_detail["go"] as Button).pressed.connect(_launch)
	v.add_child(_detail["go"])
	var keys := UIKit.label("MS_HINT_KEYS", 12, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(keys)

	var hint := CameraHint.new()
	screen.add_child(hint)
	hint.setup(false)


func _select(i: int, instant: bool) -> void:
	_sel = clampi(i, 0, 4)
	if not instant:
		Sfx.play("beep", -12.0)
	(_tabs[_sel] as Button).button_pressed = true
	var m := MissionRegistry.all()[_sel]
	var id: String = m["id"]
	var unlocked := MissionRegistry.is_unlocked(id)
	var available := MissionRegistry.is_available(id)
	(_detail["num"] as Label).text = tr("MISSION_NUM") % (_sel + 1)
	(_detail["title"] as Label).text = str(m["title"])
	(_detail["desc"] as Label).text = str(m["desc"])
	(_detail["skill"] as Label).text = str(m["skill"])
	var d := int(m["difficulty"])
	(_detail["diff"] as Label).text = "●".repeat(d) + "○".repeat(5 - d)
	(_detail["diff_word"] as Label).text = "DIFF_%d" % d
	var stars := GameState.get_stars(id)
	var done := GameState.is_completed(id)
	(_detail["stars"] as Label).text = ("★".repeat(stars) + "☆".repeat(3 - stars)) if available else "- - -"
	var best := 0
	if GameState.progress.has(id):
		best = int((GameState.progress[id] as Dictionary).get("score", 0))
	(_detail["best"] as Label).text = ("%s: %d" % [tr("MS_BEST"), best]) if done else ""
	var status := "MS_STATUS_SOON"
	var col := UIKit.C_MUTED
	if available and not unlocked:
		status = "MS_STATUS_LOCKED"
		col = UIKit.C_WARN
	elif available and done:
		status = "MS_STATUS_DONE"
		col = UIKit.C_GOOD
	elif available:
		status = "MS_STATUS_NEW" if not done else "MS_STATUS_READY"
		col = UIKit.C_ACCENT
	(_detail["status"] as Label).text = status
	(_detail["status"] as Label).add_theme_color_override("font_color", col)
	var go: Button = _detail["go"]
	go.disabled = not unlocked
	go.text = "MS_REPLAY" if done else ("MS_LAUNCH" if unlocked else ("LOCKED" if available else "COMING_SOON"))
	var gp := _groups[_sel].position
	if orbit.engaged:
		orbit.fly_to(gp, VIEW_DIST[_sel])


func _launch() -> void:
	var id: String = MissionRegistry.all()[_sel]["id"]
	if MissionRegistry.is_unlocked(id):
		Sfx.play("go", -8.0)
		Router.start_mission(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_UP:
			_select(_sel - 1, false)
		KEY_DOWN:
			_select(_sel + 1, false)
		KEY_ENTER, KEY_KP_ENTER:
			_launch()
		KEY_ESCAPE:
			Router.go_to(Router.MAIN_MENU)


func _process(delta: float) -> void:
	_t += delta
	_groups[0].rotation.y += delta * 0.18
	_groups[1].rotation.y = sin(_t * 0.18) * 0.5
	if _astro != null:
		_astro.position.y = -5.0 + 0.9 * sin(_t * 0.8)
		_astro.rotation = Vector3(0.1 * sin(_t * 0.6), 0.0, 0.08 * sin(_t * 0.5))
	for h in _holos:
		h.rotation.y += delta * 0.2
	# auto cinematic camera (used until the player grabs the camera)
	var gp := _groups[_sel].position
	if _first:
		_cur_focus = gp
		_first = false
	_cur_focus = _cur_focus.lerp(gp, 1.0 - exp(-delta * 2.4))
	var az := deg_to_rad(-26.0 + 11.0 * sin(_t * 0.15))
	var el := deg_to_rad(9.0 + 2.0 * sin(_t * 0.2))
	var dist: float = VIEW_DIST[_sel]
	var pos := _cur_focus + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * dist
	orbit.update(delta, pos, _cur_focus + Vector3(0, 2, 0), 42.0)
