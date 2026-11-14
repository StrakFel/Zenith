extends MissionBase
## Mission 2 - Lunar Expedition. NASA loop: scientific objective -> mission design (site, launcher, lander,
## rover, instrument, power, antenna) -> verification -> launch -> trans-lunar injection -> powered landing ->
## surface science with a rover -> data uplink -> results (4 segments Launch / Space / Ground / User).
## Maths in LunarDesign, landing physics in LanderModel, presentation in TransferPlanner3D / MoonScene3D.
## Simplified on purpose (see LunarDesign header) - it teaches trade-offs, it is not a trajectory tool.

enum S { DESIGN, REVIEW, LAUNCH, TRANSFER, DESCENT, SURFACE, UPLINK, ENDED }

const STEP := 0.02
const TLI_MIN := 3000.0
const TLI_MAX := 3300.0
const BURN_ERROR := 5.0                   # random engine cut-off error (m/s)
const LAUNCH_COUNTDOWN := 3.0
const LAUNCH_ASCENT := 8.0
const COAST_SECONDS := 8.0
const SURFACE_SECONDS := 240.0
const SURFACE_SCALE := LunarDesign.EXPLORE_HOURS * 3600.0 / SURFACE_SECONDS
const POI_RADIUS := 7.0
const SAMPLE_TIME := 5.0
const HEATER_W := 30.0
const DRIVE_W := 90.0

var state: int = S.DESIGN
var design: Dictionary = {}
var st: Dictionary = {}
var dev_autopilot := false
var inspecting := false

var design_view: LunarDesignView
var review: DesignReview
var world_layer: CanvasLayer
var hud_layer: CanvasLayer
var hud_root: Control
var cam_hint: CameraHint
var planner: TransferPlanner3D
var moon: MoonScene3D
var lm: LanderModel
var lander_view: LanderView3D
var ground_panel: GroundLinkPanel

# transfer
var tli_dv := 3060.0
var exec_dv := 0.0
var corr_dv := 0.0
var _tli_panel: PanelContainer
var _tli_slider: HSlider
var _tli_labels: Dictionary = {}
var _exec_btn: Button
var _coast_t := 0.0
var _coasting := false
# launch
var _lt := 0.0
var _last_cd := -1
# descent
var start_fuel := 0.0
var _acc := 0.0
var _hint_t := 0.0
var _touch_t := 0.0
# surface
var rover: Node3D
var r_pos := Vector2(14.0, 8.0)
var r_head := 0.0
var r_speed := 0.0
var r_energy := 0.0
var r_time := 0.0
var r_samples := 0
var poi_done: Array[bool] = [false, false, false]
var _sampling := -1
var _sample_t := 0.0
var _data_mbit := 0.0
var _battery_dead := false
var _surf_hint_t := 0.0
var _turn_s := 0.0
var _steer_s := 0.0

var _big: Label
var _hint: Label
var _vals: Dictionary = {}
var _bars: Dictionary = {}
var _hud_panel: PanelContainer


func _init() -> void:
	mission_id = "m2_lunar"


func _briefing_data() -> Dictionary:
	return {
		"title": "M2_TITLE",
		"objectives": ["M2_OBJ_1", "M2_OBJ_L2", "M2_OBJ_L3", "M2_OBJ_L4", "M2_OBJ_L5"],
		"controls": [
			["MOUSE", "M1_CTRL_DRAG"],
			["< >", "LUN_CTRL_SLIDER"],
			["W S", "LUN_CTRL_THROTTLE"],
			["A D", "LUN_CTRL_ROTATE"],
			["W A S D", "LUN_CTRL_ROVER"],
			["E", "LUN_CTRL_SAMPLE"],
			["C", "CAM_INSPECT_SHORT"],
			["ESC", "M1_CTRL_PAUSE"],
		],
	}


# ------------------------------------------------------------------ build --
func _build_mission() -> void:
	planner = TransferPlanner3D.new()
	add_child(planner)
	world_layer = CanvasLayer.new()
	world_layer.layer = 0
	add_child(world_layer)
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud_root = Control.new()
	hud_root.theme = UIKit.get_ui_theme()
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud_root)
	cam_hint = CameraHint.new()
	hud_root.add_child(cam_hint)
	cam_hint.setup(false, 16.0)
	_big = UIKit.label("", 64, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.offset_left = -300
	_big.offset_right = 300
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_big)
	var hp := UIKit.panel()
	hp.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hp.offset_left = -360
	hp.offset_right = 360
	hp.offset_top = -92
	hp.offset_bottom = -18
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.visible = false
	hud_root.add_child(hp)
	_hint = UIKit.label("", 17, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.add_child(_hint)
	_hint.set_meta("panel", hp)
	planner.orbit.engaged_changed.connect(_on_orbit_engaged)


func _on_orbit_engaged(on: bool) -> void:
	_set_inspect(on and state >= S.LAUNCH and state != S.TRANSFER)


func _set_inspect(on: bool) -> void:
	inspecting = on
	cam_hint.set_inspect(on)
	if on:
		Sfx.stop_all_loops()


func _cur_orbit() -> OrbitCameraController:
	return moon.orbit if moon != null else planner.orbit


func _on_mission_start() -> void:
	_open_design(LunarDesign.default_design())


func _open_design(d: Dictionary) -> void:
	state = S.DESIGN
	design_view = LunarDesignView.new()
	design_view.design = d.duplicate()
	world_layer.add_child(design_view)
	design_view.design_done.connect(_on_design_done)


func _set_hint(key: String, col: Color = UIKit.C_TEXT) -> void:
	_hint.text = key
	_hint.add_theme_color_override("font_color", col)
	(_hint.get_meta("panel") as Control).visible = key != ""


func _big_text(text: String, col: Color = Color.WHITE) -> void:
	_big.text = text
	_big.add_theme_color_override("font_color", col)


# ----------------------------------------------------------------- design --
func _on_design_done(d: Dictionary) -> void:
	design = d
	st = LunarDesign.stats(design)
	if design_view != null:
		design_view.queue_free()
		design_view = null
	state = S.REVIEW
	review = DesignReview.new()
	world_layer.add_child(review)
	review.setup_reqs(LunarDesign.requirements(design), LunarDesign.can_launch(design))
	review.back_requested.connect(func():
		review.queue_free()
		_open_design(design))
	review.launch_approved.connect(func():
		review.queue_free()
		_on_launch())


func dev_auto_design(d: Dictionary = {}) -> void:
	## Test helper: accept (or set) a design and go through the review.
	if state == S.DESIGN and design_view == null:
		dev_skip_briefing()
	_on_design_done(LunarDesign.default_design() if d.is_empty() else d)


# ----------------------------------------------------------------- launch --
func _on_launch() -> void:
	if state != S.REVIEW and state != S.DESIGN:
		return
	if not LunarDesign.can_launch(design):
		return
	if review != null and is_instance_valid(review):
		review.queue_free()
		review = null
	state = S.LAUNCH
	_lt = 0.0
	_last_cd = -1
	planner.orbit.disengage()
	planner.orbit.user_can_engage = false
	planner.override_cam = true
	planner.hide_ship()
	cam_hint.set_mission_mode(true, 16.0)
	_set_hint("LUN_LAUNCH_T", UIKit.C_ACCENT)


func _launch_pos(t: float) -> Vector3:
	var k := clampf(t / LAUNCH_ASCENT, 0.0, 1.0)
	var r := 6.371 + 0.2 * (1.0 - pow(1.0 - k, 2.5))
	var phi := -0.45 * (1.0 - k * k)
	return Vector3(-cos(phi), 0.0, -sin(phi)) * r


func _update_launch(delta: float) -> void:
	_lt += delta
	var tleft := LAUNCH_COUNTDOWN - _lt
	if tleft > 0.0:
		var n := int(ceil(tleft))
		if n != _last_cd:
			_last_cd = n
			_big_text(str(n), UIKit.C_ACCENT)
			Sfx.play("tick")
		planner.ship_to(_launch_pos(0.0))
		planner.o_pos = _launch_pos(0.0) + Vector3(-1.5, 1.2, 9.0)
		planner.o_look = _launch_pos(0.0)
		return
	var t := _lt - LAUNCH_COUNTDOWN
	if _last_cd != 0:
		_last_cd = 0
		_big_text(tr("M1_LIFTOFF"), UIKit.C_ORANGE)
		Sfx.play("go")
	if t > 1.6:
		_big_text("")
	var p := _launch_pos(t)
	planner.ship_to(p)
	planner.o_pos = planner.o_pos.lerp(p + Vector3(-2.0 - t * 0.2, 1.6 + t * 0.15, 10.0 + t * 0.4), clampf(delta * 3.0, 0.0, 1.0))
	planner.o_look = p
	Sfx.loop("rumble", -14.0 if t < LAUNCH_ASCENT - 1.0 else -30.0, 1.0)
	if t >= LAUNCH_ASCENT:
		Sfx.loop_stop("rumble")
		_big_text("")
		_set_hint("LUN_LAUNCH_OK", UIKit.C_GOOD)
		_begin_transfer()


# --------------------------------------------------------------- transfer --
func _begin_transfer() -> void:
	state = S.TRANSFER
	planner.override_cam = false
	planner.orbit.user_can_engage = true
	planner.hide_ship()
	tli_dv = clampf(tli_dv, TLI_MIN, TLI_MAX)
	planner.set_dv(tli_dv)
	_build_tli_panel()
	_refresh_tli()


func _build_tli_panel() -> void:
	_tli_panel = UIKit.panel()
	_tli_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tli_panel.offset_left = -430
	_tli_panel.offset_right = -16
	_tli_panel.offset_top = 16
	hud_root.add_child(_tli_panel)
	var v := UIKit.vbox(8)
	_tli_panel.add_child(v)
	v.add_child(UIKit.label("LUN_TLI_TITLE", 24, Color.WHITE))
	var help := UIKit.label("LUN_TLI_HELP", 13, UIKit.C_MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 380
	v.add_child(help)
	for r in [["LUN_TLI_DV", "dv"], ["LUN_TLI_APO", "apo"]]:
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(r[0], 15, UIKit.C_MUTED))
		var val := UIKit.label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_tli_labels[r[1]] = val
		v.add_child(row)
	_tli_slider = HSlider.new()
	_tli_slider.name = "TliSlider"
	_tli_slider.min_value = TLI_MIN
	_tli_slider.max_value = TLI_MAX
	_tli_slider.step = 1.0
	_tli_slider.value = tli_dv
	_tli_slider.custom_minimum_size = Vector2(380, 28)
	_tli_slider.value_changed.connect(func(x: float):
		tli_dv = x
		planner.set_dv(x)
		_refresh_tli())
	v.add_child(_tli_slider)
	var out := UIKit.label("", 16, UIKit.C_GOOD)
	out.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	out.custom_minimum_size.x = 380
	v.add_child(out)
	_tli_labels["out"] = out
	_exec_btn = UIKit.button("LUN_TLI_EXEC", Vector2(0, 50))
	_exec_btn.name = "ExecuteButton"
	_exec_btn.pressed.connect(_execute_burn)
	v.add_child(_exec_btn)


func _refresh_tli() -> void:
	var o := LunarDesign.tli_outcome(tli_dv)
	var col: Color = [UIKit.C_GOOD, UIKit.C_WARN, UIKit.C_BAD][o]
	(_tli_labels["dv"] as Label).text = Units.ms(tli_dv)
	var ra := LunarDesign.tli_apogee(tli_dv)
	(_tli_labels["apo"] as Label).text = ("%d %s" % [int((ra - LunarDesign.R_EARTH) / 1000.0), tr("UNIT_KM")]) if ra != INF else "INF"
	var out := _tli_labels["out"] as Label
	out.text = "LUN_TLI_OUT%d" % o
	out.add_theme_color_override("font_color", col)


func _execute_burn() -> void:
	if state != S.TRANSFER or _coasting:
		return
	exec_dv = tli_dv + randf_range(-BURN_ERROR, BURN_ERROR)
	planner.set_dv(exec_dv)
	_exec_btn.disabled = true
	_tli_slider.editable = false
	_coasting = true
	_coast_t = 0.0
	planner.orbit.disengage()
	Sfx.play("ignite", -6.0)
	_set_hint("LUN_COAST", UIKit.C_ACCENT)


func _update_coast(delta: float) -> void:
	_coast_t += delta
	var k := clampf(_coast_t / COAST_SECONDS, 0.0, 1.0)
	planner.ship_at(k)
	if k < 1.0:
		return
	_coasting = false
	var o := LunarDesign.tli_outcome(exec_dv)
	if o == 2:
		_fail_transfer()
		return
	corr_dv = LunarDesign.correction_dv(exec_dv)
	var isp := float(st["isp"])
	var corr_prop := float(st["mass_descent"]) * (1.0 - exp(-corr_dv / (isp * LunarDesign.G0)))
	start_fuel = maxf(float(st["prop_descent"]) - corr_prop, 0.0)
	if _tli_panel != null:
		_tli_panel.queue_free()
		_tli_panel = null
	if corr_dv > 0.0:
		_set_hint(tr("LUN_CORR_USED") % int(corr_dv), UIKit.C_WARN)
	_begin_descent()


func _fail_transfer() -> void:
	state = S.ENDED
	var res: Array = [
		["R_SITE", tr(str(LunarDesign.SITES[design["site"]]["name"]))],
		["R_TLI", Units.ms(exec_dv)],
		["R_UPLINK", "0"],
	]
	Sfx.play("fail", -6.0)
	finish(false, 0, 0, res, "LUN_FAIL_MISS", 1.2, {"tips": ["TIP_LUN_TLI"]})


# ---------------------------------------------------------------- descent --
func _begin_descent() -> void:
	state = S.DESCENT
	moon = MoonScene3D.new()
	add_child(moon)
	moon.setup(float(st["rough"]), hash(str(design["site"])))
	moon.orbit.engaged_changed.connect(_on_orbit_engaged)
	planner.queue_free()
	planner = null
	lm = LanderModel.new()
	lm.setup(st, start_fuel)
	lander_view = LanderView3D.new()
	moon.add_child(lander_view)
	moon.orbit.add_obstacle(lander_view, 2.5)
	_build_descent_hud()
	cam_hint.set_mission_mode(true, 16.0)
	_update_descent_view(0.0)
	_snap_camera()


func _clear_hud_panel() -> void:
	if _hud_panel != null:
		_hud_panel.queue_free()
		_hud_panel = null
	_vals.clear()
	_bars.clear()


func _hud_table(rows: Array, bars: Array) -> VBoxContainer:
	_clear_hud_panel()
	_hud_panel = UIKit.panel()
	_hud_panel.position = Vector2(16, 70)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(_hud_panel)
	var v := UIKit.vbox(5)
	_hud_panel.add_child(v)
	for r in rows:
		var row := UIKit.hbox(10)
		var k := UIKit.label(r[0], 14, UIKit.C_MUTED)
		k.custom_minimum_size.x = 150
		row.add_child(k)
		var val := UIKit.label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		val.custom_minimum_size.x = 100
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_vals[r[1]] = val
		v.add_child(row)
	for b in bars:
		var row := UIKit.hbox(10)
		var k := UIKit.label(b[0], 14, UIKit.C_MUTED)
		k.custom_minimum_size.x = 150
		row.add_child(k)
		var bar := UIKit.progress_bar(b[2], Vector2(110, 12))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_bars[b[1]] = bar
		v.add_child(row)
	return v


func _build_descent_hud() -> void:
	_hud_table([["LUN_HUD_ALT", "alt"], ["LUN_HUD_VY", "vy"], ["LUN_HUD_VX", "vx"], ["LUN_HUD_ANGLE", "ang"],
		["LUN_HUD_PAD", "pad"]], [["LUN_HUD_FUEL", "fuel", UIKit.C_ORANGE], ["LUN_HUD_THR", "thr", UIKit.C_ACCENT]])
	_set_hint("LUN_HINT_DESCENT", UIKit.C_TEXT)


func _snap_camera() -> void:
	var o := moon.orbit
	var p := lander_view.global_position
	moon.camera.global_position = p + Vector3(10.0, 20.0, 160.0)
	moon.camera.look_at(p, Vector3.UP)


func _descent_input() -> Vector2:
	var thr := lm.throttle
	var turn := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		thr += 0.8 * get_process_delta_time()
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		thr -= 0.8 * get_process_delta_time()
	if Input.is_physical_key_pressed(KEY_Z):
		thr = 1.0
	if Input.is_physical_key_pressed(KEY_X):
		thr = 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		turn += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		turn -= 1.0
	_turn_s = move_toward(_turn_s, turn * float(GameState.settings["sens"]), 5.0 * get_process_delta_time())
	return Vector2(clampf(thr, 0.0, 1.0), clampf(_turn_s, -1.0, 1.0))


## Test autopilot: cancel horizontal speed toward the pad, then hold a descent-rate profile.
func _lander_autopilot() -> Vector2:
	var h := lm.pos.y
	var tx := clampf(-lm.pos.x * 0.05, -30.0, 30.0)
	if h < 25.0:
		tx = 0.0
	var ex := tx - lm.vel.x
	var target_angle := clampf(ex * 0.08, -0.45, 0.45)
	if h < 25.0:
		target_angle = clampf(ex * 0.08, -0.1, 0.1)
	var turn := clampf((target_angle - lm.angle) * 3.0 - lm.omega * 3.5, -1.0, 1.0)
	var vy_t := -clampf(h * 0.07, 0.9, 38.0)
	var acc_max := lm.thrust_max / lm.mass()
	var want := (LanderModel.G + (vy_t - lm.vel.y) * 1.3) / maxf(cos(lm.angle), 0.5)
	return Vector2(clampf(want / acc_max, 0.0, 1.0), turn)


func _update_descent(delta: float) -> void:
	var inp := _lander_autopilot() if dev_autopilot else _descent_input()
	var thr_cmd := inp.x
	_acc += delta
	var steps := 0
	while _acc >= STEP and steps < 12:
		lm.step(STEP, thr_cmd, inp.y)
		_acc -= STEP
		steps += 1
		if lm.landed or lm.crashed:
			break
	_update_descent_view(delta)
	_update_descent_hud()
	if lm.fuel <= 0.0 and not (lm.landed or lm.crashed):
		_set_hint("LUN_HINT_FUEL", UIKit.C_BAD)
	if lm.landed:
		_on_landed()
	elif lm.crashed:
		_on_crashed()


func _update_descent_view(delta: float) -> void:
	var gy := moon.ground_y(lm.pos.x, 0.0)
	lander_view.position = Vector3(lm.pos.x, gy + lm.pos.y, 0.0)
	lander_view.rotation.z = -lm.angle
	lander_view.update_view(lm.throttle if lm.fuel > 0.0 else 0.0, lm.pos.y, gy)
	var h := lm.pos.y
	var dist := lerpf(34.0, 170.0, clampf(h / 900.0, 0.0, 1.0))
	var p := lander_view.position
	var cam_pos := p + Vector3(6.0 + h * 0.01, 6.0 + h * 0.07 + 4.0, dist)
	moon.orbit.update(delta, cam_pos, p + Vector3(0, 3, 0), 45.0)


func _update_descent_hud() -> void:
	(_vals["alt"] as Label).text = Units.m(lm.pos.y)
	var vy := lm.vel.y
	(_vals["vy"] as Label).text = Units.ms(vy, 1, true)
	(_vals["vx"] as Label).text = Units.ms(lm.vel.x, 1, true)
	(_vals["ang"] as Label).text = Units.deg(rad_to_deg(lm.angle))
	(_vals["pad"] as Label).text = Units.m(lm.pos.x)
	(_vals["vy"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if vy < -3.2 and lm.pos.y < 60.0 else Color.WHITE)
	(_vals["vx"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if absf(lm.vel.x) > 1.8 and lm.pos.y < 40.0 else Color.WHITE)
	(_vals["ang"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if absf(lm.angle) > deg_to_rad(11.0) and lm.pos.y < 40.0 else Color.WHITE)
	(_bars["fuel"] as ProgressBar).value = lm.fuel_fraction(maxf(start_fuel, 1.0)) * 100.0
	(_bars["thr"] as ProgressBar).value = lm.throttle * 100.0
	_hint_t -= get_process_delta_time()
	if _hint_t > 0.0 or lm.fuel <= 0.0:
		return
	_hint_t = 0.25
	var h := lm.pos.y
	if h < 400.0 and lm.vel.y < -22.0 and h / maxf(-lm.vel.y, 0.1) < 6.0:
		_set_hint("LUN_HINT_FAST", UIKit.C_BAD)
	elif h < 600.0 and absf(lm.vel.x) > 6.0:
		_set_hint("LUN_HINT_DRIFT", UIKit.C_WARN)
	elif lm.fuel_fraction(maxf(start_fuel, 1.0)) < 0.12:
		_set_hint("LUN_HINT_FUEL", UIKit.C_WARN)
	elif h < 120.0 and lm.vel.y > -4.0 and absf(lm.vel.x) < 2.0:
		_set_hint("LUN_HINT_GOOD", UIKit.C_GOOD)
	else:
		_set_hint("LUN_HINT_DESCENT", UIKit.C_TEXT)


func _on_crashed() -> void:
	state = S.ENDED
	Sfx.stop_all_loops()
	Sfx.play("hit", 2.0)
	var reason := lm.outcome
	if lm.fuel <= 0.01 and reason == "LUN_FAIL_SPEED":
		reason = "LUN_FAIL_FUEL"
	lander_view.update_view(0.0, 0.0, 0.0)
	lander_view.rotation.z = -lm.touch_angle - 0.9 * signf(lm.touch_angle if lm.touch_angle != 0.0 else 1.0)
	Fx3D.burst(moon, lander_view.position + Vector3(0, 1.5, 0), Color(1.0, 0.7, 0.3), 80, 14.0)
	_set_hint("", UIKit.C_TEXT)
	var res: Array = [
		["R_SITE", tr(str(LunarDesign.SITES[design["site"]]["name"]))],
		["R_TLI", Units.ms(exec_dv)],
		["R_LAND_SPEED", Units.ms(absf(lm.touch_speed.y), 1)],
		["R_LAND_OFFSET", Units.m(absf(lm.pos.x))],
		["R_PROP_LEFT", "%d%%" % int(lm.fuel_fraction(maxf(start_fuel, 1.0)) * 100.0)],
		["R_BUDGET_USED", "$%d / $%d" % [int(st["cost"]), LunarDesign.BUDGET]],
	]
	var tips: Array = ["TIP_LUN_LAND"]
	if reason == "LUN_FAIL_FUEL":
		tips.append("TIP_LUN_FUEL")
	finish(false, 0, 0, res, reason, 1.8, {"tips": tips})


func _on_landed() -> void:
	state = S.SURFACE
	Sfx.stop_all_loops()
	Sfx.play("beep")
	lander_view.update_view(0.0, 0.0, 0.0)
	lander_view.rotation.z = -lm.angle
	_touch_t = 0.0
	# rover rolls out
	rover = (load("res://Assets/Models/rover.glb") as PackedScene).instantiate()
	rover.scale = Vector3.ONE * 1.6
	moon.add_child(rover)
	r_pos = Vector2(lm.pos.x + 12.0, 8.0)
	r_head = 0.0
	r_speed = 0.0
	r_energy = float(LunarDesign.BATTERY[design["battery"]]["wh"])
	r_time = 0.0
	moon.orbit.user_can_engage = false
	_hud_table([["LUN_SURF_DATA", "data"], ["LUN_SURF_TASKS", "poi"]], [["LUN_SURF_BATT", "batt", UIKit.C_GOOD]])
	_set_hint("LUN_SURF_HINT", UIKit.C_TEXT)
	_place_rover()


# ---------------------------------------------------------------- surface --
func _rover_input() -> Vector2:
	var drive := 0.0
	var steer := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		drive += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		drive -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		steer += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		steer -= 1.0
	_steer_s = move_toward(_steer_s, steer * float(GameState.settings["sens"]), 5.0 * get_process_delta_time())
	return Vector2(drive, clampf(_steer_s, -1.0, 1.0))


func _next_poi() -> int:
	var best := -1
	var bd := INF
	for i in 3:
		if poi_done[i]:
			continue
		var d := r_pos.distance_to(moon.pois[i])
		if d < bd:
			bd = d
			best = i
	return best


func _rover_autopilot(auto_sample: bool = true) -> Vector2:
	var i := _next_poi()
	if i < 0:
		return Vector2.ZERO
	var to := moon.pois[i] - r_pos
	var want := atan2(to.y, to.x)
	var diff := wrapf(want - r_head, -PI, PI)
	var steer := clampf(diff * 2.0, -1.0, 1.0)
	var drive := 1.0 if to.length() > 3.0 else 0.0
	if absf(diff) > 0.6:
		drive *= 0.3
	if auto_sample and to.length() < POI_RADIUS * 0.6 and absf(r_speed) < 0.4 and _sampling < 0:
		_start_sample(i)
	return Vector2(drive, steer)


func _start_sample(i: int) -> void:
	_sampling = i
	_sample_t = 0.0
	Sfx.play("whoosh", -12.0)


func _update_surface(delta: float) -> void:
	r_time += delta
	var vmax := float(st["rover_speed"])
	var inp := Vector2.ZERO
	if not _battery_dead and _sampling < 0:
		inp = _rover_autopilot() if dev_autopilot else _rover_input()
	elif dev_autopilot and _sampling < 0:
		inp = Vector2.ZERO
	var target := inp.x * vmax
	r_speed = move_toward(r_speed, target, 4.0 * delta)
	if absf(r_speed) > 0.05:
		r_head += inp.y * 1.1 * delta * signf(r_speed)
	var dir := Vector2(cos(r_head), sin(r_head))
	r_pos += dir * r_speed * delta
	r_pos += moon.nearest_obstacle_push(r_pos, 1.4)
	r_pos = r_pos.clamp(Vector2(-450, -450), Vector2(450, 450))
	# sampling
	var load_w := HEATER_W + float(LunarDesign.COMM[design["comm"]]["power"]) * 0.2 + DRIVE_W * absf(r_speed) / vmax
	if _sampling >= 0:
		_sample_t += delta
		load_w += float(LunarDesign.INSTRUMENTS[design["instrument"]]["power"]) * 3.0
		if _sample_t >= SAMPLE_TIME:
			poi_done[_sampling] = true
			moon.mark_poi_done(_sampling)
			r_samples += 1
			_data_mbit += float(st["data_total"]) / 3.0
			_sampling = -1
			Sfx.play("beep")
	# energy: dusk lowers the sun over the (shortened) lunar day
	var sun := float(st["sun"]) * lerpf(1.0, 0.35, clampf(r_time / SURFACE_SECONDS, 0.0, 1.0))
	var gain := float(LunarDesign.SOLAR[design["solar"]]["watts"]) * sun
	var cap := float(LunarDesign.BATTERY[design["battery"]]["wh"])
	r_energy = clampf(r_energy + (gain - load_w) * delta * SURFACE_SCALE / 3600.0, 0.0, cap)
	if r_energy <= 0.0 and not _battery_dead:
		_battery_dead = true
		r_speed = 0.0
		Sfx.play("fail", -8.0)
	_place_rover()
	_update_surface_hud(cap)
	var all_done := r_samples >= 3
	if dev_autopilot and (all_done or _battery_dead or r_time >= SURFACE_SECONDS):
		_start_uplink()
	elif not dev_autopilot and (_battery_dead or r_time >= SURFACE_SECONDS) and _sampling < 0:
		_start_uplink()


func _place_rover() -> void:
	var gy := moon.ground_y(r_pos.x, r_pos.y)
	var n := moon.ground_normal(r_pos.x, r_pos.y)
	var fwd := Vector3(cos(r_head), 0.0, sin(r_head))
	var xa := (fwd - n * fwd.dot(n)).normalized()
	var za := xa.cross(n).normalized()
	rover.global_transform = Transform3D(Basis(xa, n, za).scaled(Vector3.ONE * 1.6), Vector3(r_pos.x, gy, r_pos.y))
	var p := rover.global_position
	var cam_pos := p + Vector3(-cos(r_head) * 12.0, 5.5, -sin(r_head) * 12.0)
	moon.orbit.update(get_process_delta_time(), cam_pos, p + Vector3(0, 1.0, 0), 50.0)


func _update_surface_hud(cap: float) -> void:
	(_vals["data"] as Label).text = "%d %s" % [int(_data_mbit), tr("UNIT_MBIT")]
	(_vals["poi"] as Label).text = "%d / 3" % r_samples
	var bar := _bars["batt"] as ProgressBar
	bar.value = r_energy / cap * 100.0
	UIKit.set_bar_color(bar, UIKit.C_GOOD if r_energy / cap > 0.35 else (UIKit.C_WARN if r_energy / cap > 0.15 else UIKit.C_BAD))
	_surf_hint_t -= get_process_delta_time()
	if _surf_hint_t > 0.0:
		return
	_surf_hint_t = 0.2
	var i := _next_poi()
	if _sampling >= 0:
		_set_hint("LUN_SURF_SAMPLING", UIKit.C_ACCENT)
	elif r_samples >= 3:
		_set_hint("LUN_SURF_DONE", UIKit.C_GOOD)
	elif _battery_dead or r_time >= SURFACE_SECONDS or r_energy / cap < 0.1:
		_set_hint("LUN_SURF_RETURN", UIKit.C_WARN)
	elif i >= 0 and r_pos.distance_to(moon.pois[i]) < POI_RADIUS and absf(r_speed) < 0.6:
		_set_hint("LUN_SURF_SAMPLE_HINT", UIKit.C_ORANGE)
	else:
		_set_hint("LUN_SURF_HINT", UIKit.C_TEXT)


func _try_sample() -> void:
	if state != S.SURFACE or _sampling >= 0 or _battery_dead or absf(r_speed) > 0.6:
		return
	for i in 3:
		if not poi_done[i] and r_pos.distance_to(moon.pois[i]) < POI_RADIUS:
			_start_sample(i)
			return


# ----------------------------------------------------------------- uplink --
func _start_uplink() -> void:
	if state != S.SURFACE:
		return
	state = S.UPLINK
	_set_hint("LUN_UPLINK_DELAY", UIKit.C_ACCENT)
	if r_samples == 0:
		_finish_mission()
		return
	var capacity := float(st["uplink"])
	var ratio := minf(capacity / maxf(_data_mbit, 0.001), 1.0)
	ground_panel = GroundLinkPanel.new()
	hud_layer.add_child(ground_panel)
	ground_panel.setup(_data_mbit, ratio, 6.0)
	await ground_panel.finished
	await get_tree().create_timer(0.8).timeout
	ground_panel.queue_free()
	_finish_mission()


func _finish_mission() -> void:
	state = S.ENDED
	Sfx.stop_all_loops()
	var site_id := str(design["site"])
	var capacity := float(st["uplink"])
	var delivered := minf(_data_mbit, capacity)
	var data_total := float(st["data_total"])
	var frac := clampf(delivered / maxf(data_total, 0.001), 0.0, 1.0)
	var science := frac * clampf(float(st["sci_mult"]) / 1.6, 0.4, 1.25)
	var cap_e := float(LunarDesign.BATTERY[design["battery"]]["wh"])
	var prop_left := lm.fuel_fraction(maxf(start_fuel, 1.0))
	var cost := int(st["cost"])
	var success := r_samples >= 1
	var stars := 0
	if success:
		stars = 1
		if science >= 0.7:
			stars += 1
		if science >= 0.95 and cost <= int(LunarDesign.BUDGET * 0.9):
			stars += 1
	var score := stars * 1000 + int(science * 1500.0) + int(prop_left * 300.0) + maxi(LunarDesign.BUDGET - cost, 0) * 4
	# four segments
	var ratio := float(st["mass_tli"]) / float(st["tli_cap"])
	var launch_r := clampf(1.0 - maxf(ratio - 0.75, 0.0) * 1.6, 0.4, 1.0)
	var land_q := clampf(1.0 - absf(lm.touch_speed.y) / 3.2 * 0.45 - absf(lm.pos.x) / maxf(lm.safe_half_width, 1.0) * 0.35, 0.2, 1.0)
	var space_r := (1.0 if corr_dv <= 0.0 else clampf(1.0 - corr_dv / 200.0, 0.5, 0.9)) * 0.5 + land_q * 0.5
	var ground_r := clampf(capacity / maxf(_data_mbit, 0.001), 0.0, 1.0) if r_samples > 0 else 0.0
	var segments: Array = [["SEG_LAUNCH", launch_r], ["SEG_SPACE", space_r], ["SEG_GROUND", ground_r],
		["SEG_USER", clampf(science, 0.0, 1.0)]]
	var res: Array = [
		["R_SITE", tr(str(LunarDesign.SITES[site_id]["name"]))],
		["R_TLI", Units.ms(exec_dv)],
	]
	if corr_dv > 0.0:
		res.append(["R_CORR", Units.ms(corr_dv)])
	res.append_array([
		["R_LAND_SPEED", Units.ms(absf(lm.touch_speed.y), 1)],
		["R_LAND_OFFSET", Units.m(absf(lm.pos.x))],
		["R_PROP_LEFT", "%d%%" % int(prop_left * 100.0)],
		["R_SAMPLES", "%d / 3" % r_samples],
		["R_ROVER_BATT", "%d%%" % int(r_energy / cap_e * 100.0)],
		["R_UPLINK", "%d / %d %s" % [int(delivered), int(_data_mbit), tr("UNIT_MBIT")]],
		["R_BUDGET_USED", "$%d / $%d" % [cost, LunarDesign.BUDGET]],
		["R_SCORE", str(score)],
	])
	var tips: Array = []
	if _battery_dead and r_samples < 3:
		tips.append("TIP_LUN_POWER")
	if ground_r < 0.9 and r_samples > 0:
		tips.append("TIP_LUN_DATA")
	if float(st["bonus"]) <= 1.0:
		tips.append("TIP_LUN_SYNERGY")
	if corr_dv > 0.0:
		tips.append("TIP_LUN_TLI")
	if prop_left < 0.08:
		tips.append("TIP_LUN_FUEL")
	if tips.is_empty():
		tips.append("TIP_LUN_GOOD")
	var tier := 2 if science >= 0.85 else (1 if science >= 0.45 else 0)
	var extra := {"segments": segments, "science": science, "tips": tips, "user": "USER_LUN_%d" % tier,
		"science_note": "RES_LUN_NOTE"}
	_set_hint("", UIKit.C_TEXT)
	var reason := "LUN_WIN"
	if not success:
		reason = "LUN_FAIL_POWER"
	finish(success, stars, score, res, reason, 1.0, extra)


# ------------------------------------------------------------------ loop ---
func _process(delta: float) -> void:
	if ended:
		return
	if planner != null and state < S.DESCENT:
		planner.orbit.user_can_engage = state == S.DESIGN or state == S.REVIEW or (state == S.TRANSFER and not _coasting)
	if inspecting:
		# frozen simulation, but the orbit controller still needs its per-frame update
		if state == S.DESCENT:
			_update_descent_view(delta)
		elif state == S.SURFACE:
			_place_rover()
		return
	match state:
		S.LAUNCH:
			_update_launch(delta)
		S.TRANSFER:
			if _coasting:
				_update_coast(delta)
			elif dev_autopilot and _exec_btn != null and not _exec_btn.disabled:
				_tli_slider.value = clampf(LunarDesign.ideal_tli_dv(), TLI_MIN, TLI_MAX)
				_execute_burn()
		S.DESCENT:
			_update_descent(delta)
		S.SURFACE:
			_update_surface(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_C and state >= S.LAUNCH and state != S.TRANSFER and state != S.ENDED:
		_cur_orbit().toggle_sticky()
		return
	if inspecting:
		return
	if state == S.SURFACE:
		if key == KEY_E:
			_try_sample()
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			_start_uplink()
