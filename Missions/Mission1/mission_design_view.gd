class_name MissionDesignView
extends Control
## Step 1-2 of the mission-design loop: choose the scientific goal (-> requirements) and design
## the satellite. Live trade-off panel: mass, power, eclipse battery, downlink, cost.

signal design_done(design: Dictionary)
signal back_requested

var design: Dictionary = M1Design.default_design()

var _goal_buttons: Dictionary = {}
var _sat_box: VBoxContainer
var _goal_desc: Label
var _req_orbit: Label
var _stat: Dictionary = {}
var _bars: Dictionary = {}


## A toggle button that shows a title (translation key) and a detail line.
class OptionCard extends Button:
	var detail: Label

	func setup(title_key: String, detail_text: String, group: ButtonGroup) -> void:
		toggle_mode = true
		button_group = group
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 54)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 10
		v.offset_right = -10
		v.offset_top = 4
		v.add_theme_constant_override("separation", 0)
		add_child(v)
		var t := UIKit.label(title_key, 16, Color.WHITE)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		detail = UIKit.label("", 12, UIKit.C_MUTED)
		detail.text = detail_text
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(detail)
		pressed.connect(func(): Sfx.play("click"))


const PANEL_W := 500.0


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # only its two panels take the mouse; the rest is the 3D camera's
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := _build_left()
	# two panels of the same size and height; the strip under them holds the camera hint
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 16
	left.offset_right = 16 + PANEL_W
	left.offset_top = 16
	left.offset_bottom = -68
	add_child(left)
	var right := _build_right()
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -16 - PANEL_W
	right.offset_right = -16
	right.offset_top = 16
	right.offset_bottom = -68
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN     # if the content is wider it grows to the left, never off-screen
	add_child(right)
	_rebuild_sat()
	_refresh()


func _build_left() -> Control:
	var p := UIKit.panel()
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label("M1D_TITLE", 28, Color.WHITE))
	var pipe := UIKit.label("M1D_PIPELINE", 12, UIKit.C_ORANGE)
	pipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pipe.custom_minimum_size.x = 430
	v.add_child(pipe)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("M1D_STEP_GOAL", 18, UIKit.C_ACCENT))
	var group := ButtonGroup.new()
	for gid in M1Design.GOALS:
		var g: Dictionary = M1Design.GOALS[gid]
		var b := OptionCard.new()
		b.setup(str(g["name"]), "", group)
		b.detail.text = ""
		b.button_pressed = (design["goal"] == gid)
		b.pressed.connect(_on_goal.bind(gid))
		v.add_child(b)
		_goal_buttons[gid] = b
	_goal_desc = UIKit.label("", 14, UIKit.C_TEXT)
	_goal_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_desc.custom_minimum_size = Vector2(430, 50)
	v.add_child(_goal_desc)
	v.add_child(UIKit.label("M1D_REQ_TITLE", 16, UIKit.C_ACCENT))
	_req_orbit = UIKit.label("", 15, UIKit.C_GOOD)
	v.add_child(_req_orbit)
	var rules := UIKit.label("M1D_REQ_RULES", 12, UIKit.C_MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size.x = 430
	v.add_child(rules)
	v.add_child(HSeparator.new())
	# segments
	var seg := UIKit.hbox(6)
	for s in [["SEG_LAUNCH", "SEG_LAUNCH_D"], ["SEG_SPACE", "SEG_SPACE_D"], ["SEG_GROUND", "SEG_GROUND_D"], ["SEG_USER", "SEG_USER_D"]]:
		var c := UIKit.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(UIKit.label(s[0], 14, UIKit.C_ORANGE))
		var d := UIKit.label(s[1], 10, UIKit.C_MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 92
		c.add_child(d)
		seg.add_child(c)
	v.add_child(seg)
	return p


func _build_right() -> Control:
	var p := UIKit.panel()
	var outer := UIKit.vbox(8)
	p.add_child(outer)
	outer.add_child(UIKit.label("M1D_STEP_SAT", 22, UIKit.C_ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_sat_box = UIKit.vbox(6)
	_sat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sat_box)
	outer.add_child(HSeparator.new())
	# live trade-off panel
	for r in [["M1D_MASS", "mass"], ["M1D_POWER", "power"], ["M1D_BATT", "batt"], ["M1D_DATA", "data"]]:
		var row := UIKit.hbox(8)
		var k := UIKit.label(r[0], 13, UIKit.C_MUTED)
		k.custom_minimum_size.x = 190
		row.add_child(k)
		var bar := UIKit.progress_bar(UIKit.C_GOOD, Vector2(120, 10))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_bars[r[1]] = bar
		var val := UIKit.label("", 13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_stat[r[1]] = val
		outer.add_child(row)
	var crow := UIKit.hbox(8)
	crow.add_child(UIKit.label("M1D_COST", 14, UIKit.C_MUTED))
	var cval := UIKit.label("", 16, UIKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	cval.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(cval)
	_stat["cost"] = cval
	outer.add_child(crow)
	var go := UIKit.button("M1D_CONTINUE", Vector2(0, 52))
	go.pressed.connect(func(): design_done.emit(design.duplicate()))
	outer.add_child(go)
	var back := UIKit.button("BTN_BACK_MISSIONS", Vector2(0, 38))
	back.name = "BackButton"
	back.add_theme_font_size_override("font_size", 15)
	back.pressed.connect(func(): back_requested.emit())
	outer.add_child(back)
	return p


func _on_goal(gid: String) -> void:
	M1Design.set_goal(design, gid)
	_rebuild_sat()
	_refresh()


func _rebuild_sat() -> void:
	for c in _sat_box.get_children():
		c.queue_free()
	var goal: Dictionary = M1Design.GOALS[design["goal"]]
	# instrument
	var opts: Array = []
	for iid in goal["instruments"]:
		var i: Dictionary = M1Design.INSTRUMENTS[iid]
		opts.append([iid, i["name"], "%s | %d %s | %.1f %s | %s" % [Units.kg(float(i["mass"])), int(i["power"]), tr("UNIT_W"),
			float(i["data"]), tr("UNIT_MBPS"), Units.money(int(i["cost"]))]])
	_choice("M1D_INSTRUMENT", "instrument", opts)
	var so: Array = []
	for sid in M1Design.SOLAR:
		var s: Dictionary = M1Design.SOLAR[sid]
		so.append([sid, s["name"], "%d %s | %s | %s" % [int(s["watts"]), tr("UNIT_W"), Units.kg(float(s["mass"])), Units.money(int(s["cost"]))]])
	_choice("M1D_SOLAR", "solar", so)
	var bo: Array = []
	for bid in M1Design.BATTERY:
		var b: Dictionary = M1Design.BATTERY[bid]
		bo.append([bid, b["name"], "%d %s | %s | %s" % [int(b["wh"]), tr("UNIT_WH"), Units.kg(float(b["mass"])), Units.money(int(b["cost"]))]])
	_choice("M1D_BATTERY", "battery", bo)
	var co: Array = []
	for cid in M1Design.COMM:
		var c: Dictionary = M1Design.COMM[cid]
		co.append([cid, c["name"], "%.1f %s | %d %s | %s | %s" % [float(c["mbps"]), tr("UNIT_MBPS"), int(c["power"]), tr("UNIT_W"),
			Units.kg(float(c["mass"])), Units.money(int(c["cost"]))]])
	_choice("M1D_COMM", "comm", co)


func _choice(title_key: String, field: String, options: Array) -> void:
	_sat_box.add_child(UIKit.label(title_key, 15, UIKit.C_ORANGE))
	var group := ButtonGroup.new()
	for o in options:
		var b := OptionCard.new()
		b.setup(str(o[1]), str(o[2]), group)
		b.button_pressed = (design[field] == o[0])
		b.pressed.connect(func():
			design[field] = o[0]
			_refresh())
		_sat_box.add_child(b)


func _color(level: int) -> Color:
	return [UIKit.C_GOOD, UIKit.C_WARN, UIKit.C_BAD][level]


func _refresh() -> void:
	var goal: Dictionary = M1Design.GOALS[design["goal"]]
	var gd: Label = _goal_desc
	gd.text = str(goal["desc"])
	_req_orbit.text = "%s: %d-%d km" % [tr("M1D_REQ_ORBIT"), int(goal["best"][0]), int(goal["best"][1])]
	var s := M1Design.sat_stats(design)
	var reqs := M1Design.requirements(design, {})
	var lvl := {}
	for r in reqs:
		lvl[r["id"]] = int(r["level"])
	(_stat["mass"] as Label).text = Units.kg(float(s["mass"]))
	(_bars["mass"] as ProgressBar).value = float(s["mass"]) / 1100.0 * 100.0
	(_stat["power"] as Label).text = "%d / %d %s" % [int(s["gen"]), int(s["demand"]), tr("UNIT_W")]
	(_bars["power"] as ProgressBar).value = minf(float(s["power_ratio"]), 1.0) * 100.0
	UIKit.set_bar_color(_bars["power"], _color(int(lvl["power"])))
	(_stat["power"] as Label).add_theme_color_override("font_color", _color(int(lvl["power"])))
	(_stat["batt"] as Label).text = "%d / %d %s" % [int(s["batt_wh"]), int(s["batt_need"]), tr("UNIT_WH")]
	(_bars["batt"] as ProgressBar).value = minf(float(s["batt_ratio"]), 1.0) * 100.0
	UIKit.set_bar_color(_bars["batt"], _color(int(lvl["batt"])))
	(_stat["batt"] as Label).add_theme_color_override("font_color", _color(int(lvl["batt"])))
	(_stat["data"] as Label).text = "%d / %d %s" % [int(s["data_downlink"]), int(s["data_produced"]), tr("UNIT_MBIT")]
	(_bars["data"] as ProgressBar).value = minf(float(s["data_ratio"]), 1.0) * 100.0
	UIKit.set_bar_color(_bars["data"], _color(int(lvl["data"])))
	(_stat["data"] as Label).add_theme_color_override("font_color", _color(int(lvl["data"])))
	(_stat["cost"] as Label).text = "%s / %s" % [Units.money(int(s["cost"])), Units.money(M1Design.BUDGET)]
