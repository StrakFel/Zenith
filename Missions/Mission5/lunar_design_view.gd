class_name LunarDesignView
extends Control
## Mission Design Lab for the lunar expedition: pick the landing site (scientific objective), the launcher,
## lander propellant / engine and the rover payload. Live trade-off panel (mass, delta-v, thrust-to-weight,
## rover energy, downlink, cost) makes every choice matter.

signal design_done(design: Dictionary)

var design: Dictionary = LunarDesign.default_design()

var _site_desc: Label
var _site_facts: Label
var _opts_box: VBoxContainer
var _stat: Dictionary = {}
var _bars: Dictionary = {}


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left := _build_left()
	left.position = Vector2(16, 16)
	left.custom_minimum_size = Vector2(430, 0)
	add_child(left)
	var right := _build_right()
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -520
	right.offset_right = -16
	right.offset_top = 16
	right.offset_bottom = -16
	add_child(right)
	_rebuild_options()
	_refresh()


func _build_left() -> Control:
	var p := UIKit.panel()
	var v := UIKit.vbox(8)
	p.add_child(v)
	v.add_child(UIKit.label("LUN_LAB_TITLE", 28, Color.WHITE))
	var pipe := UIKit.label("LUN_PIPELINE", 12, UIKit.C_ORANGE)
	pipe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pipe.custom_minimum_size.x = 400
	v.add_child(pipe)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("LUN_STEP_SITE", 18, UIKit.C_ACCENT))
	var group := ButtonGroup.new()
	for sid in LunarDesign.SITES:
		var b := MissionDesignView.OptionCard.new()
		b.setup(str(LunarDesign.SITES[sid]["name"]), "", group)
		b.button_pressed = (design["site"] == sid)
		b.pressed.connect(_on_site.bind(sid))
		v.add_child(b)
	_site_desc = UIKit.label("", 14, UIKit.C_TEXT)
	_site_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_site_desc.custom_minimum_size = Vector2(400, 70)
	v.add_child(_site_desc)
	_site_facts = UIKit.label("", 13, UIKit.C_GOOD)
	_site_facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_site_facts)
	v.add_child(HSeparator.new())
	var rules := UIKit.label("LUN_RULES", 12, UIKit.C_MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size.x = 400
	v.add_child(rules)
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
	outer.add_child(UIKit.label("LUN_STEP_CRAFT", 22, UIKit.C_ACCENT))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_opts_box = UIKit.vbox(6)
	_opts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_opts_box)
	outer.add_child(HSeparator.new())
	for r in [["LUN_ST_MASS", "mass"], ["LUN_ST_DV", "dv"], ["LUN_ST_TWR", "twr"], ["LUN_ST_POWER", "power"], ["LUN_ST_DATA", "data"]]:
		var row := UIKit.hbox(8)
		var k := UIKit.label(r[0], 13, UIKit.C_MUTED)
		k.custom_minimum_size.x = 170
		row.add_child(k)
		var bar := UIKit.progress_bar(UIKit.C_GOOD, Vector2(110, 10))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_bars[r[1]] = bar
		var val := UIKit.label("", 13, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_stat[r[1]] = val
		outer.add_child(row)
	var crow := UIKit.hbox(8)
	crow.add_child(UIKit.label("LUN_ST_COST", 14, UIKit.C_MUTED))
	var cval := UIKit.label("", 16, UIKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	cval.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(cval)
	_stat["cost"] = cval
	outer.add_child(crow)
	var go := UIKit.button("LUN_CONTINUE", Vector2(0, 52))
	go.name = "ContinueButton"
	go.pressed.connect(func(): design_done.emit(design.duplicate()))
	outer.add_child(go)
	return p


func _on_site(sid: String) -> void:
	design["site"] = sid
	_refresh()


func _rebuild_options() -> void:
	for c in _opts_box.get_children():
		c.queue_free()
	var o: Array = []
	for id in LunarDesign.LAUNCHERS:
		var d: Dictionary = LunarDesign.LAUNCHERS[id]
		o.append([id, d["name"], "%s %s | %s" % [Units.kg(float(d["tli_mass"])), tr("LUN_TO_TLI"), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_LAUNCHER", "launcher", o)
	o = []
	for id in LunarDesign.ENGINES:
		var d: Dictionary = LunarDesign.ENGINES[id]
		o.append([id, d["name"], "Isp %d %s | %s | %s | %s" % [int(d["isp"]), tr("UNIT_S"), Units.kn(float(d["thrust"])), Units.kg(float(d["mass"])), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_ENGINE", "engine", o)
	o = []
	for id in LunarDesign.TANKS:
		var d: Dictionary = LunarDesign.TANKS[id]
		o.append([id, d["name"], "%s %s | %s" % [Units.kg(float(d["prop"])), tr("LUN_PROP"), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_TANK", "tank", o)
	o = []
	for id in LunarDesign.ROVERS:
		var d: Dictionary = LunarDesign.ROVERS[id]
		o.append([id, d["name"], "%s | %.1f %s | %s" % [Units.kg(float(d["mass"])), float(d["speed"]), tr("UNIT_MS"), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_ROVER", "rover", o)
	o = []
	for id in LunarDesign.INSTRUMENTS:
		var d: Dictionary = LunarDesign.INSTRUMENTS[id]
		o.append([id, d["name"], "%s | %d %s | %.1f %s | %s" % [Units.kg(float(d["mass"])), int(d["power"]), tr("UNIT_W"), float(d["data"]), tr("UNIT_MBPS"), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_INSTR", "instrument", o)
	o = []
	for id in LunarDesign.SOLAR:
		var d: Dictionary = LunarDesign.SOLAR[id]
		o.append([id, d["name"], "%d %s | %s | %s" % [int(d["watts"]), tr("UNIT_W"), Units.kg(float(d["mass"])), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_SOLAR", "solar", o)
	o = []
	for id in LunarDesign.BATTERY:
		var d: Dictionary = LunarDesign.BATTERY[id]
		o.append([id, d["name"], "%d %s | %s | %s" % [int(d["wh"]), tr("UNIT_WH"), Units.kg(float(d["mass"])), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_BATT", "battery", o)
	o = []
	for id in LunarDesign.COMM:
		var d: Dictionary = LunarDesign.COMM[id]
		o.append([id, d["name"], "%.1f %s | %d %s | %s | %s" % [float(d["mbps"]), tr("UNIT_MBPS"), int(d["power"]), tr("UNIT_W"), Units.kg(float(d["mass"])), Units.money(int(d["cost"]))]])
	_choice("LUN_OPT_COMM", "comm", o)


func _choice(title_key: String, field: String, options: Array) -> void:
	_opts_box.add_child(UIKit.label(title_key, 15, UIKit.C_ORANGE))
	var group := ButtonGroup.new()
	for opt in options:
		var b := MissionDesignView.OptionCard.new()
		b.setup(str(opt[1]), str(opt[2]), group)
		b.button_pressed = (design[field] == opt[0])
		b.pressed.connect(func():
			design[field] = opt[0]
			_refresh())
		_opts_box.add_child(b)


func _color(level: int) -> Color:
	return [UIKit.C_GOOD, UIKit.C_WARN, UIKit.C_BAD][level]


func _refresh() -> void:
	var site: Dictionary = LunarDesign.SITES[design["site"]]
	_site_desc.text = str(site["desc"])
	_site_facts.text = "%s %.0f%% | %s %d%% | %s x%.1f" % [tr("LUN_F_ROUGH"), float(site["rough"]) * 100.0, tr("LUN_F_SUN"),
		int(float(site["sun"]) * 100.0), tr("LUN_F_SCI"), float(site["sci"])]
	var s := LunarDesign.stats(design)
	var reqs := LunarDesign.requirements(design)
	var lvl := {}
	for r in reqs:
		lvl[r["id"]] = int(r["level"])
	(_stat["mass"] as Label).text = "%d / %d kg" % [int(s["mass_tli"]), int(s["tli_cap"])]
	(_bars["mass"] as ProgressBar).value = minf(float(s["mass_tli"]) / float(s["tli_cap"]), 1.2) / 1.2 * 100.0
	(_stat["dv"] as Label).text = "%d %s" % [int(s["dv_descent"]), tr("UNIT_MS")]
	(_bars["dv"] as ProgressBar).value = minf(float(s["dv_descent"]) / (LunarDesign.DESCENT_DV_OK * 2.0), 1.0) * 100.0
	(_stat["twr"] as Label).text = "%.2f" % float(s["twr"])
	(_bars["twr"] as ProgressBar).value = minf(float(s["twr"]) / 3.0, 1.0) * 100.0
	(_stat["power"] as Label).text = "%d / %d %s" % [int(s["supply_wh"]), int(s["need_wh"]), tr("UNIT_WH")]
	(_bars["power"] as ProgressBar).value = minf(float(s["power_ratio"]), 1.0) * 100.0
	(_stat["data"] as Label).text = "%d / %d %s" % [int(s["uplink"]), int(s["data_total"]), tr("UNIT_MBIT")]
	(_bars["data"] as ProgressBar).value = minf(float(s["data_ratio"]), 1.0) * 100.0
	for key in ["mass", "dv", "twr", "power", "data"]:
		var l: int = lvl.get(key, 0)
		UIKit.set_bar_color(_bars[key], _color(l))
		(_stat[key] as Label).add_theme_color_override("font_color", _color(l))
	(_stat["cost"] as Label).text = "%s / %s" % [Units.money(int(s["cost"])), Units.money(LunarDesign.BUDGET)]
	(_stat["cost"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if int(s["cost"]) > LunarDesign.BUDGET else UIKit.C_WARN)
