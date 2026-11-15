extends MissionBase
## Mission 3 - ISS Docking. Rotate, translate and brake with RCS thrusters; line the
## nose up with the port and touch it slowly enough, straight enough and centred enough.

var world: DockingWorld
var view: DockingView3D
var hud_layer: CanvasLayer
var started := false
var dev_autopilot := false

var _vals: Dictionary = {}
var _fuel_bar: ProgressBar
var _hint: Label
var _hint_panel: PanelContainer
var _hint_key := ""
var _warp_lbl: Label
var inspecting := false
var cam_hint: CameraHint
var _stranded_t := 0.0
var _done := false
var design: Dictionary = {}
var st: Dictionary = {}
var design_view: IssDesignView
var review: DesignReview
var _hud_root: Control
var _big: Label
var _launching := false
var launch: Dictionary = {}     # hand-off from the launch segment (empty when played stand-alone)
var _sm := Vector3.ZERO
var _lt := 0.0
var _last_cd := -1
const LAUNCH_COUNTDOWN := 3.0
const LAUNCH_ASCENT := 5.0


func _init() -> void:
	mission_id = "m3_iss"


func _briefing_data() -> Dictionary:
	return {
		"title": "M3_TITLE",
		"objectives": ["ISS_OBJ_0", "M3_OBJ_1", "M3_OBJ_2", "M3_OBJ_3", "M3_OBJ_4", "M3_SCI_NOTE"],
		"controls": [
			["A D", "M3_CTRL_ROT"],
			["W S", "M3_CTRL_FWD"],
			["Q E", "M3_CTRL_STRAFE"],
			["X", "M3_CTRL_KILLROT"],
			["SHIFT", "M2_CTRL_FINE"],
			["1 2 3", "M3_CTRL_WARP"],
			["ESC", "M1_CTRL_PAUSE"],
		],
	}


func music_mood() -> String:
	return "action" if ((started or _launching) and not ended) else "calm"


func _build_mission() -> void:
	var wl := CanvasLayer.new()
	wl.layer = 0
	add_child(wl)
	world = DockingWorld.new()
	world.draw_2d = false
	wl.add_child(world)
	world.visible = false
	view = DockingView3D.new()
	add_child(view)
	view.setup(world)
	world.docked.connect(_on_docked)
	world.docking_failed.connect(_on_failed)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	_build_hud()


func _build_hud() -> void:
	var root := Control.new()
	root.theme = UIKit.get_ui_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(root)
	_hud_root = root
	_big = UIKit.label("", 64, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.offset_left = -300
	_big.offset_right = 300
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_big)
	var p := UIKit.panel()
	p.position = Vector2(16, 16)
	root.add_child(p)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	p.add_child(g)
	var rows := [["M3_RANGE", "range"], ["M3_CLOSING", "speed"], ["M3_OFFSET", "lat"],
		["M3_LATRATE", "latv"], ["M3_ANGLE", "ang"], ["M3_ROTRATE", "rot"]]
	for r in rows:
		g.add_child(UIKit.label(r[0], 15, UIKit.C_MUTED))
		var v := UIKit.label("0", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size.x = 110
		g.add_child(v)
		var chip := UIKit.label("", 16, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		chip.custom_minimum_size.x = 24
		g.add_child(chip)
		_vals[r[1]] = [v, chip]
	# fuel + warp (top-right)
	var fp := UIKit.panel()
	fp.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fp.offset_left = -270
	fp.offset_right = -16
	fp.offset_top = 16
	root.add_child(fp)
	var fv := UIKit.vbox(6)
	fp.add_child(fv)
	var fh := UIKit.hbox(8)
	fh.add_child(UIKit.label("HUD_FUEL", 15, UIKit.C_MUTED))
	_fuel_bar = UIKit.progress_bar(UIKit.C_ORANGE, Vector2(130, 12))
	_fuel_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fh.add_child(_fuel_bar)
	fv.add_child(fh)
	_warp_lbl = UIKit.label("x1", 16, UIKit.C_ACCENT)
	fv.add_child(_warp_lbl)
	fv.add_child(UIKit.label("M3_LEGEND", 13, UIKit.C_MUTED))
	var cargo := UIKit.label("M3_CARGO", 12, UIKit.C_ORANGE)
	cargo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cargo.custom_minimum_size.x = 220
	fv.add_child(cargo)
	# hint
	cam_hint = CameraHint.new()
	root.add_child(cam_hint)
	cam_hint.setup(true, 16.0)
	_hint_panel = UIKit.panel()
	_hint_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_panel.offset_left = -340
	_hint_panel.offset_right = 340
	_hint_panel.offset_top = -100
	_hint_panel.offset_bottom = -18
	root.add_child(_hint_panel)
	_hint = UIKit.label("", 18, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_panel.add_child(_hint)


func _on_mission_start() -> void:
	view.orbit.engaged_changed.connect(func(on: bool):
		inspecting = on and started
		cam_hint.set_inspect(inspecting)
		if inspecting:
			Sfx.stop_all_loops())
	if str(GameState.session.get("profile", "")) == "m3":
		# the launch segment already designed the cargo + rocket: the damage / fuel it left shapes the docking
		launch = GameState.session["launch"]
		var d: Dictionary = GameState.session["design"]
		design = d
		st = IssDesign.stats(d)
		var q := clampf(float(launch["hull"]) / 100.0, 0.0, 1.0)
		st["fragile"] = float(st["fragile"]) * lerpf(1.5, 1.0, q)      # a battered cargo is more fragile
		_begin_docking()
		return
	_open_design(IssDesign.default_design())


func _open_design(d: Dictionary) -> void:
	design_view = IssDesignView.new()
	design_view.design = d.duplicate()
	hud_layer.add_child(design_view)
	design_view.design_done.connect(_on_design_done)


func _on_design_done(d: Dictionary) -> void:
	design = d
	st = IssDesign.stats(design)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	review = DesignReview.new()
	hud_layer.add_child(review)
	review.setup_reqs(IssDesign.requirements(design), IssDesign.can_launch(design))
	review.back_requested.connect(func():
		review.queue_free()
		_open_design(design))
	review.launch_approved.connect(func():
		review.queue_free()
		_start_launch())


func _start_launch() -> void:
	if not IssDesign.can_launch(design):
		return
	_launching = true
	_lt = 0.0
	_last_cd = -1


func _update_launch(delta: float) -> void:
	_lt += delta
	var tleft := LAUNCH_COUNTDOWN - _lt
	if tleft > 0.0:
		var n := int(ceil(tleft))
		if n != _last_cd:
			_last_cd = n
			_big.text = str(n)
			Sfx.play("tick")
		return
	if _last_cd != 0:
		_last_cd = 0
		_big.text = tr("M1_LIFTOFF")
		Sfx.play("go")
	Sfx.loop("rumble", -16.0)
	if _lt - LAUNCH_COUNTDOWN >= LAUNCH_ASCENT:
		Sfx.loop_stop("rumble")
		_big.text = ""
		_begin_docking()


func _begin_docking() -> void:
	_launching = false
	world.fuel = DockingWorld.FUEL_MAX * float(st["fuel"])
	started = true


## Test helper: skip the lab (default or given design) and go straight to the docking phase.
func dev_quick_start(d: Dictionary = {}) -> void:
	design = IssDesign.default_design() if d.is_empty() else d
	st = IssDesign.stats(design)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	_begin_docking()


func _launch_rating() -> float:
	var l := launch
	var r := float(l["hull"]) / 100.0 * 0.6 + float(l["orbit_q"]) * 0.25 + (0.15 if not bool(l["fairing_early"]) else 0.0)
	r *= 1.0 - clampf(float(l["waste"]) * 0.3 + float(l["booster_waste"]) * 0.2, 0.0, 0.3)
	return clampf(r, 0.0, 1.0)


func _fuel_r() -> float:
	return world.fuel / (DockingWorld.FUEL_MAX * maxf(float(st.get("fuel", 1.0)), 0.01))


func _process(delta: float) -> void:
	if _launching and not ended:
		_update_launch(delta)
		return
	if not started or ended:
		return
	if inspecting:
		# INSPECT MODE: the world is frozen, only the camera moves
		_update_hud()
		return
	var fwd := 0.0
	var strafe := 0.0
	var rot := 0.0
	var fine := false
	var kill := false
	if dev_autopilot:
		var a := _autopilot()
		fwd = a[0]
		strafe = a[1]
		rot = a[2]
		fine = world.axial_distance() < 40.0
	else:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			fwd += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			fwd -= 1.0
		if Input.is_physical_key_pressed(KEY_E):
			strafe += 1.0
		if Input.is_physical_key_pressed(KEY_Q):
			strafe -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			rot += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			rot -= 1.0
		fine = Input.is_physical_key_pressed(KEY_SHIFT)
		kill = Input.is_physical_key_pressed(KEY_X)
		# smoothing: thrust ramps in/out over ~0.15 s (less jerky, finer control)
		var k := 7.0 * delta
		var sens := float(GameState.settings["sens"])
		_sm = Vector3(move_toward(_sm.x, fwd, k), move_toward(_sm.y, strafe, k), move_toward(_sm.z, rot * sens, k))
		fwd = _sm.x
		strafe = _sm.y
		rot = _sm.z
	world.step(delta, fwd, strafe, rot, fine, kill)
	if (absf(world.thrust_fx.x) + absf(world.thrust_fx.y) > 0.1 or absf(world.rot_fx) > 0.1) and not world.finished:
		Sfx.loop("hiss", -17.0 if not fine else -25.0)
	else:
		Sfx.loop_stop("hiss")
	_update_hud()
	_check_end(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not started or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_C and not ended and not _done:
		view.orbit.toggle_sticky()
		return
	match event.keycode:
		KEY_1:
			world.warp = 1
		KEY_2:
			world.warp = 4
		KEY_3:
			world.warp = 10


## Test pilot (Tools/e2e_m3.gd): PD attitude hold + velocity-shaping approach.
func _autopilot() -> Array:
	var rot := clampf(-(world.angle_error() * 3.0 + world.omega * 4.0), -1.0, 1.0)
	if absf(rot) < 0.05:
		rot = 0.0
	var tip := world.nose_tip()
	var ax := world.axial_distance()
	var vx_t := clampf(ax * 0.09, 0.15, 8.0) if ax > 6.0 else 0.1
	var vy_t := clampf(-tip.y * 0.12, -0.6, 0.6)
	var fwd := clampf((vx_t - world.vel.x) * 4.0, -1.0, 1.0)
	var strafe := clampf((vy_t - world.vel.y) * 5.0, -1.0, 1.0)
	if absf(fwd) < 0.06:
		fwd = 0.0
	if absf(strafe) < 0.06:
		strafe = 0.0
	var calm := absf(tip.y) < 1.5 and absf(world.vel.y) < 0.06 and absf(world.angle_error()) < 0.05
	world.warp = 10 if (ax > 100.0 and calm) else 1
	return [fwd, strafe, rot]


func _tol_color(ok: bool, near: bool) -> Color:
	if not near:
		return Color.WHITE
	return UIKit.C_GOOD if ok else UIKit.C_BAD


func _set_row(id: String, text: String, ok: bool, near: bool) -> void:
	var pair: Array = _vals[id]
	(pair[0] as Label).text = text
	(pair[0] as Label).add_theme_color_override("font_color", _tol_color(ok, near))
	(pair[1] as Label).text = ("OK" if ok else "!") if near else ""
	(pair[1] as Label).add_theme_color_override("font_color", UIKit.C_GOOD if ok else UIKit.C_BAD)


func _update_hud() -> void:
	var near := world.axial_distance() < 60.0
	var tip := world.nose_tip()
	var spd := world.vel.x
	_set_row("range", Units.m1(world.range_to_port()), true, false)
	_set_row("speed", Units.ms(spd, 2), spd <= DockingWorld.TOL_SPEED and spd > -0.01, near)
	_set_row("lat", Units.m1(tip.y, true), absf(tip.y) <= DockingWorld.TOL_LAT, near)
	_set_row("latv", Units.ms(world.vel.y, 2, true), absf(world.vel.y) <= DockingWorld.TOL_LAT_RATE, near)
	_set_row("ang", Units.deg(rad_to_deg(world.angle_error())), absf(world.angle_error()) <= DockingWorld.TOL_ANGLE, near)
	_set_row("rot", Units.deg_s(rad_to_deg(world.omega)), absf(world.omega) <= DockingWorld.TOL_OMEGA, near)
	_fuel_bar.value = world.fuel / DockingWorld.FUEL_MAX * 100.0
	UIKit.set_bar_color(_fuel_bar, UIKit.C_BAD if world.fuel < 8.0 else UIKit.C_ORANGE)
	_warp_lbl.text = "x%d" % world.warp
	var key := "M3_HINT_ALIGN"
	var ax := world.axial_distance()
	if world.fuel <= 0.0:
		key = "M3_HINT_NOFUEL"
	elif absf(world.angle_error()) > 0.17 and ax < 200.0:
		key = "M3_HINT_ROTATE"
	elif spd > 1.0 and ax < 90.0:
		key = "M3_HINT_BRAKE"
	elif absf(tip.y) > 2.0 and ax < 120.0:
		key = "M3_HINT_LATERAL"
	elif ax < 40.0:
		key = "M3_HINT_FINAL"
	else:
		key = "M3_HINT_ALIGN"
	if key != _hint_key:
		_hint_key = key
		_hint.text = key
		_hint.add_theme_color_override("font_color", UIKit.C_BAD if key == "M3_HINT_NOFUEL" else UIKit.C_TEXT)


func _check_end(delta: float) -> void:
	if _done:
		return
	if world.pos.length() > 700.0:
		_done = true
		_end(false, "M3_FAIL_LOST")
	elif world.fuel <= 0.0 and not world.finished and world.vel.x < 0.03:
		_stranded_t += delta
		if _stranded_t > 3.0:
			_done = true
			_end(false, "M3_FAIL_FUEL")
	else:
		_stranded_t = 0.0


func _on_docked() -> void:
	if _done:
		return
	Sfx.stop_all_loops()
	Sfx.play("clang")
	_done = true
	var tip := world.nose_tip()
	var stars := 1
	if _fuel_r() >= 0.4:
		stars += 1
	if _viability(tip) >= 0.9:
		stars += 1
	_end(true, "M3_WIN_REASON", stars, tip)


## The cargo (crystal-growth experiment) is fragile: fast or off-centre contact damages it.
func _viability(tip: Vector2) -> float:
	var shock := clampf(1.0 - maxf(0.0, world.contact_speed - 0.1) / (0.4 / maxf(float(st.get("fragile", 1.0)), 0.1)), 0.2, 1.0)
	var centre := 1.0 - clampf(absf(tip.y) / DockingWorld.TOL_LAT, 0.0, 1.0) * 0.2
	return shock * centre


func _on_failed(reason: String) -> void:
	if _done:
		return
	Sfx.stop_all_loops()
	Sfx.play("hit", 2.0)
	_done = true
	_end(false, reason)


func _end(success: bool, reason: String, stars: int = 0, tip: Vector2 = Vector2.ZERO) -> void:
	var stats: Array = [
		["R_FUEL_LEFT", "%d%%" % int(clampf(_fuel_r(), 0.0, 1.0) * 100.0)],
		["M3_CLOSING", Units.ms(world.contact_speed, 2)],
		["M3_OFFSET", Units.m1(tip.y, true) if success else "-"],
		["M3_ANGLE", Units.deg(rad_to_deg(world.angle_error()))],
	]
	var score := 0
	var extra: Dictionary = {}
	if success:
		var via := _viability(tip)
		stats.append(["R_EXPERIMENT", "%d%%" % int(via * 100.0)])
		stats.append(["R_SHOCK", Units.ms(world.contact_speed, 2)])
		score = stars * 1000 + int(world.fuel * 12.0) + int(via * 800.0)
		stats.append(["R_SCORE", str(score)])
		var fuel_r := _fuel_r()
		var sci := clampf(via * float(st.get("sci", 1.0)), 0.0, 1.3)
		if launch.is_empty():
			stats.append(["R_BUDGET_USED", "%s / %s" % [Units.money(int(st.get("cost", 0))), Units.money(IssDesign.BUDGET)]])
		else:
			stats.append(["R_BUDGET_USED", "%s / %s" % [Units.money(int(launch["cost"])), Units.money(int(launch["budget"]))]])
			stats.append(["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])])
		var launch_r := clampf(1.0 - maxf(float(st.get("mass", 0.0)) / maxf(float(st.get("cap", 1.0)), 1.0) - 0.75, 0.0) * 1.6, 0.4, 1.0)
		var tips: Array = []
		if world.contact_speed > 0.15:
			tips.append("M3_TIP_FAST")
		if absf(tip.y) > 0.5:
			tips.append("M3_TIP_OFFSET")
		if fuel_r < 0.25:
			tips.append("M3_TIP_FUEL")
		if float(st.get("fragile", 1.0)) > 1.0 and world.contact_speed > 0.1:
			tips.append("ISS_TIP_FRAGILE")
		if float(st.get("fuel", 1.0)) < 0.75 and fuel_r < 0.3:
			tips.append("ISS_TIP_RCS")
		if tips.is_empty():
			tips.append("M3_TIP_GOOD")
		extra = {
			"segments": [["SEG_LAUNCH", launch_r if launch.is_empty() else _launch_rating()], ["SEG_SPACE", clampf(0.4 + fuel_r, 0.0, 1.0)],
				["SEG_GROUND", clampf(1.0 - absf(tip.y) / DockingWorld.TOL_LAT * 0.5, 0.0, 1.0)],
				["SEG_USER", via]],
			"science": sci, "science_note": "M3_SCI_NOTE", "tips": tips,
			"user": "M3_USER_%d" % M1Design.science_tier(sci),
		}
	finish(success, stars, score, stats, reason, 1.4, extra)



