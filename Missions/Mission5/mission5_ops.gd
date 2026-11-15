extends "res://Missions/Mission5/moon_mission.gd"
## Mission 5, phase 2 - Moon & Return. Reuses the lunar expedition (trans-lunar burn, powered landing, rover science, data
## uplink) with the expedition designed in the payload lab, then adds the way home: ASCENT from the surface, TRANS-EARTH
## INJECTION and RE-ENTRY. The three return legs are a PROTOTYPE: each is a decision with real numbers (propellant, corridor,
## heat shield) rather than a full flight simulation.
##
## Launcher -> Moon: the delta-v that the launch left in the trans-lunar stage caps the trans-lunar burn.

const ASCENT_NEED := 1700.0         # m/s to reach lunar orbit from the surface (simplified)
const TEI_IDEAL := 1000.0           # m/s trans-Earth injection (simplified)
const TEI_BAND := 80.0              # corridor half-width (m/s)
const TEI_BASE := 850.0             # service-module propellant, m/s
const ENTRY_CENTER := -6.0          # deg flight-path angle at entry interface
const ENTRY_SHALLOW := -4.8         # shallower than this the capsule skips out of the atmosphere
const ENTRY_G_LIMIT := 9.5
const ENTRY_HEAT_LIMIT := 100.0

var launch: Dictionary = {}
var lunar: Dictionary = {}
var ret: Dictionary = {}
var _ret_started := false
var _ret_panel: PanelContainer
var _ret_slider: HSlider
var _ret_info: Label
var _ret_btn: Button
var _ret_step := 0
var _ret_lines: VBoxContainer
var _ret_title: Label


func _init() -> void:
	super._init()
	mission_id = "m5_moon"
	launch = GameState.session.get("launch", {})
	var d: Dictionary = GameState.session.get("design", LaunchProfiles.default_design("m5"))
	design = LaunchProfiles._as_lunar(d)
	design["capsule"] = d.get("capsule", "light")
	design["ascent"] = d.get("ascent", "s")
	if launch.is_empty():
		launch = {"hull": 100.0, "orbit_q": 1.0, "dv_left": 3300.0, "cost": 300, "budget": 560, "waste": 0.0, "booster_waste": 0.0, "fairing_early": false}


func _briefing_data() -> Dictionary:
	return {
		"title": "M5_TITLE",
		"objectives": ["M5_OPS_1", "M5_OPS_2", "M5_OPS_3", "M5_OPS_4", "M5_OPS_5"],
		"controls": [["MOUSE", "M1_CTRL_DRAG"], ["< >", "LUN_CTRL_SLIDER"], ["W S", "LUN_CTRL_THROTTLE"], ["A D", "LUN_CTRL_ROTATE"],
			["W A S D", "LUN_CTRL_ROVER"], ["E", "LUN_CTRL_SAMPLE"], ["C", "CAM_INSPECT_SHORT"], ["ESC", "M1_CTRL_PAUSE"]],
	}


func _on_mission_start() -> void:
	st = LunarDesign.stats(design)
	state = S.LAUNCH
	_begin_transfer()
	# the propellant the launch left in the trans-lunar stage limits the burn
	var avail := float(launch["dv_left"])
	_tli_slider.max_value = clampf(avail, TLI_MIN + 1.0, TLI_MAX)
	_tli_slider.min_value = minf(TLI_MIN, _tli_slider.max_value - 1.0)
	_tli_slider.value = clampf(tli_dv, _tli_slider.min_value, _tli_slider.max_value)
	_set_hint(tr("MOON_TLI_AVAIL") % [int(avail), int(LunarDesign.ideal_tli_dv())], UIKit.C_ACCENT if avail >= LunarDesign.ideal_tli_dv() - 40.0 else UIKit.C_BAD)


func _fail_transfer() -> void:
	if float(launch["dv_left"]) < LunarDesign.ideal_tli_dv() - 70.0:
		state = S.ENDED
		Sfx.play("fail", -6.0)
		var res: Array = [["R_TLI", Units.ms(exec_dv)], ["R_TLI_AVAIL", Units.ms(float(launch["dv_left"]))], ["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])]]
		finish(false, 0, 0, res, "MOON_FAIL_TLI_FUEL", 1.2, {"tips": ["MOON_TIP_TLI_FUEL"]})
		return
	super._fail_transfer()


# ------------------------------------------------------------------ return legs (prototype)
func _finish_mission() -> void:
	if r_samples == 0 or _ret_started:
		super._finish_mission()
		return
	_ret_started = true
	state = S.UPLINK
	_clear_hud_panel()
	_set_hint("", UIKit.C_TEXT)
	_ret_step = 0
	_build_ret_panel()
	_show_ascent()


func _build_ret_panel() -> void:
	_ret_panel = UIKit.panel()
	_ret_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_ret_panel.offset_left = -430
	_ret_panel.offset_right = -16
	_ret_panel.offset_top = -190
	_ret_panel.offset_bottom = 190
	_ret_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_root.add_child(_ret_panel)
	var v := UIKit.vbox(8)
	_ret_panel.add_child(v)
	_ret_title = UIKit.label("", 22, Color.WHITE)
	v.add_child(_ret_title)
	_ret_info = UIKit.label("", 13, UIKit.C_MUTED)
	_ret_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ret_info.custom_minimum_size.x = 380
	v.add_child(_ret_info)
	_ret_lines = UIKit.vbox(2)
	v.add_child(_ret_lines)
	_ret_slider = HSlider.new()
	_ret_slider.name = "ReturnSlider"
	_ret_slider.custom_minimum_size = Vector2(380, 26)
	v.add_child(_ret_slider)
	_ret_btn = UIKit.button("MOON_EXEC", Vector2(0, 48))
	_ret_btn.name = "ReturnButton"
	_ret_btn.pressed.connect(_ret_execute)
	v.add_child(_ret_btn)


func _set_lines(rows: Array) -> void:
	for c in _ret_lines.get_children():
		c.queue_free()
	for r in rows:
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(str(r[0]), 14, UIKit.C_MUTED))
		var val := UIKit.label(str(r[1]), 15, r[2] if r.size() > 2 else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_ret_lines.add_child(row)


func _asc_dv() -> float:
	return float(LaunchProfiles.MOON_ASCENT[design["ascent"]]["dv"])


func _show_ascent() -> void:
	_ret_title.text = "MOON_ASC_TITLE"
	_ret_info.text = "MOON_ASC_INFO"
	_ret_slider.visible = false
	_ret_btn.text = "MOON_ASC_BTN"
	var ok := _asc_dv() >= ASCENT_NEED
	_set_lines([["MOON_L_ASC_DV", "%d %s" % [int(_asc_dv()), tr("UNIT_MS")], UIKit.C_GOOD if ok else UIKit.C_BAD],
		["MOON_L_ASC_NEED", "%d %s" % [int(ASCENT_NEED), tr("UNIT_MS")]]])


func _show_tei() -> void:
	_ret_title.text = "MOON_TEI_TITLE"
	_ret_info.text = "MOON_TEI_INFO"
	var avail := TEI_BASE + maxf(_asc_dv() - ASCENT_NEED, 0.0)
	ret["tei_avail"] = avail
	_ret_slider.visible = true
	_ret_slider.min_value = 700.0
	_ret_slider.max_value = maxf(avail, 701.0)
	_ret_slider.step = 5.0
	_ret_slider.value = minf(900.0, _ret_slider.max_value)
	_ret_slider.value_changed.connect(func(_x): _refresh_ret())
	_ret_btn.text = "MOON_EXEC"
	_refresh_ret()


func _show_entry() -> void:
	_ret_title.text = "MOON_ENT_TITLE"
	_ret_info.text = "MOON_ENT_INFO"
	_ret_slider.visible = true
	_ret_slider.min_value = -9.0
	_ret_slider.max_value = -3.0
	_ret_slider.step = 0.1
	_ret_slider.value = -4.0
	_ret_btn.text = "MOON_ENT_BTN"
	_refresh_ret()


func _shield() -> float:
	return float(LaunchProfiles.MOON_CAPSULE[design["capsule"]]["shield"])


func _entry_numbers(a: float) -> Dictionary:
	var g := 3.0 + (absf(a) - 3.0) * 1.5
	var heat := 70.0 * pow(absf(a) / 6.0, 2.2) / _shield()
	return {"g": g, "heat": heat}


func _refresh_ret() -> void:
	if _ret_step == 1:
		var dv := _ret_slider.value
		var err := absf(dv - TEI_IDEAL)
		var col := UIKit.C_GOOD if err <= TEI_BAND * 0.4 else (UIKit.C_WARN if err <= TEI_BAND else UIKit.C_BAD)
		_set_lines([["MOON_L_TEI_DV", "%d %s" % [int(dv), tr("UNIT_MS")], col], ["MOON_L_TEI_AVAIL", "%d %s" % [int(ret["tei_avail"]), tr("UNIT_MS")]],
			["MOON_L_TEI_OUT", "MOON_TEI_OUT_%d" % (0 if err <= TEI_BAND * 0.4 else (1 if err <= TEI_BAND else 2)), col]])
	elif _ret_step == 2:
		var a := _ret_slider.value
		var n := _entry_numbers(a)
		var shallow := a > ENTRY_SHALLOW
		var good := not shallow and float(n["g"]) <= ENTRY_G_LIMIT and float(n["heat"]) <= ENTRY_HEAT_LIMIT
		_set_lines([["MOON_L_ANGLE", "%.1f deg" % a, UIKit.C_GOOD if good else UIKit.C_BAD],
			["MOON_L_G", "%.1f g (<= %.1f)" % [float(n["g"]), ENTRY_G_LIMIT], UIKit.C_GOOD if float(n["g"]) <= ENTRY_G_LIMIT else UIKit.C_BAD],
			["MOON_L_HEAT", "%d%% (<= %d%%)" % [int(n["heat"]), int(ENTRY_HEAT_LIMIT)], UIKit.C_GOOD if float(n["heat"]) <= ENTRY_HEAT_LIMIT else UIKit.C_BAD],
			["MOON_L_CORR", "MOON_ENT_SKIP" if shallow else ("MOON_ENT_OK" if good else "MOON_ENT_STEEP"), UIKit.C_GOOD if good else UIKit.C_BAD]])


func _ret_execute() -> void:
	match _ret_step:
		0:
			# ascent stage lifts off the descent stage
			_ret_btn.disabled = true
			Sfx.play("ignite", -4.0)
			Sfx.loop("rumble", -16.0)
			var tw := create_tween()
			var y0 := lander_view.position.y
			tw.tween_method(func(k: float):
				lander_view.position.y = y0 + k * k * 500.0
				lander_view.update_view(1.0, 60.0 + k * 400.0, y0), 0.0, 1.0, 2.0)
			await tw.finished
			Sfx.loop_stop("rumble")
			lander_view.update_view(0.0, 400.0, y0)
			var ok := _asc_dv() >= ASCENT_NEED
			ret["asc_ok"] = ok
			if not ok:
				_end_return("MOON_FAIL_ASCENT", ["MOON_TIP_ASCENT"])
				return
			_ret_btn.disabled = false
			_ret_step = 1
			_show_tei()
		1:
			var dv := _ret_slider.value
			var err := absf(dv - TEI_IDEAL)
			ret["tei_dv"] = dv
			ret["tei_q"] = clampf(1.0 - err / (TEI_BAND * 2.0), 0.0, 1.0)
			if err > TEI_BAND:
				_end_return("MOON_FAIL_TEI", ["MOON_TIP_TEI"])
				return
			_ret_step = 2
			_ret_slider.visible = true
			_show_entry()
		2:
			var a := _ret_slider.value
			var n := _entry_numbers(a)
			ret["angle"] = a
			ret["g"] = float(n["g"])
			ret["heat"] = float(n["heat"])
			if a > ENTRY_SHALLOW:
				_end_return("MOON_FAIL_SKIP", ["MOON_TIP_ENTRY"])
				return
			if float(n["g"]) > ENTRY_G_LIMIT or float(n["heat"]) > ENTRY_HEAT_LIMIT:
				_end_return("MOON_FAIL_BURN", ["MOON_TIP_ENTRY_STEEP"])
				return
			ret["ok"] = true
			ret["quality"] = clampf(1.0 - absf(a - ENTRY_CENTER) / 1.6, 0.3, 1.0)
			if _ret_panel != null:
				_ret_panel.queue_free()
				_ret_panel = null
			super._finish_mission()


## The crew did not make it home: the science is returned (it was sent by radio) but the mission is a failure.
func _end_return(reason: String, tips: Array) -> void:
	ret["ok"] = false
	ret["fail_key"] = reason
	ret["fail_tips"] = tips
	if _ret_panel != null:
		_ret_panel.queue_free()
		_ret_panel = null
	super._finish_mission()


func finish(success: bool, stars: int, score: int, stats: Array, reason_key: String, delay: float = 1.2, extra: Dictionary = {}) -> void:
	if ret.is_empty() or not ret.has("ok"):
		super.finish(success, stars, score, stats, reason_key, delay, extra)
		return
	var tips: Array = extra.get("tips", [])
	var segs: Array = extra.get("segments", [])
	var rating := 0.0
	if bool(ret["ok"]):
		rating = 0.55 * float(ret.get("tei_q", 0.0)) + 0.45 * float(ret.get("quality", 0.0))
		stats.append(["R_TEI", Units.ms(float(ret["tei_dv"]))])
		stats.append(["R_ENTRY", "%.1f deg | %.1f g | %d%%" % [float(ret["angle"]), float(ret["g"]), int(ret["heat"])]])
		if rating >= 0.85 and stars < 3 and success:
			stars += 1
		score += int(rating * 800.0)
	else:
		success = false
		stars = 0
		reason_key = str(ret["fail_key"])
		for t in ret.get("fail_tips", []):
			tips.append(t)
		stats.append(["R_TEI", "-"])
	segs = segs.filter(func(r): return r[0] != "SEG_LAUNCH")
	segs.append(["SEG_RETURN", rating])
	segs.insert(0, ["SEG_LAUNCH", _launch_rating()])
	extra["segments"] = segs
	extra["tips"] = tips
	stats = stats.filter(func(r): return r[0] != "R_BUDGET_USED")
	stats.append(["R_BUDGET_USED", "%s / %s" % [Units.money(int(launch["cost"])), Units.money(int(launch["budget"]))]])
	stats.append(["R_LAUNCH_HULL", "%d%%" % int(launch["hull"])])
	super.finish(success, stars, score, stats, reason_key, delay, extra)


func _launch_rating() -> float:
	var l := launch
	var r := float(l["hull"]) / 100.0 * 0.6 + float(l.get("orbit_q", 1.0)) * 0.25 + (0.15 if not bool(l["fairing_early"]) else 0.0)
	r *= 1.0 - clampf(float(l["waste"]) * 0.3 + float(l["booster_waste"]) * 0.2, 0.0, 0.3)
	return clampf(r, 0.0, 1.0)
