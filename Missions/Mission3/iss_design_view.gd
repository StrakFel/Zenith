class_name IssDesignView
extends Control
## Cargo / experiment design lab for the ISS expedition (see IssDesign).

signal design_done(design: Dictionary)

var design: Dictionary = IssDesign.default_design()
var _opts: VBoxContainer
var _vals: Dictionary = {}


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var p := UIKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 16
	p.offset_top = 16
	p.offset_bottom = -16
	p.offset_right = 520
	add_child(p)
	var outer := UIKit.vbox(8)
	p.add_child(outer)
	outer.add_child(UIKit.label("ISS_LAB_TITLE", 26, Color.WHITE))
	var sub := UIKit.label("ISS_LAB_SUB", 13, UIKit.C_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 470
	outer.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_opts = UIKit.vbox(6)
	_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_opts)
	outer.add_child(HSeparator.new())
	for r in [["ISS_ST_MASS", "mass"], ["ISS_ST_FUEL", "fuel"], ["ISS_ST_FRAG", "frag"], ["LUN_ST_COST", "cost"]]:
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(r[0], 14, UIKit.C_MUTED))
		var v := UIKit.label("", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		_vals[r[1]] = v
		outer.add_child(row)
	var go := UIKit.button("LUN_CONTINUE", Vector2(0, 50))
	go.name = "ContinueButton"
	go.pressed.connect(func(): design_done.emit(design.duplicate()))
	outer.add_child(go)
	_build_options()
	_refresh()


func _build_options() -> void:
	var o: Array = []
	for id in IssDesign.EXPERIMENTS:
		var d: Dictionary = IssDesign.EXPERIMENTS[id]
		o.append([id, d["name"], "%s | x%.1f %s | x%.1f %s | $%d" % [Units.kg(float(d["mass"])), float(d["sci"]), tr("LUN_F_SCI"),
			float(d["fragile"]), tr("ISS_ST_FRAG"), int(d["cost"])]])
	_choice("ISS_OPT_EXP", "experiment", o)
	o = []
	for id in IssDesign.LAUNCHERS:
		var d: Dictionary = IssDesign.LAUNCHERS[id]
		o.append([id, d["name"], "%s | $%d" % [Units.kg(float(d["cap"])), int(d["cost"])]])
	_choice("LUN_OPT_LAUNCHER", "launcher", o)
	o = []
	for id in IssDesign.RCS:
		var d: Dictionary = IssDesign.RCS[id]
		o.append([id, d["name"], "%s | %d%% | $%d" % [Units.kg(float(d["mass"])), int(float(d["fuel"]) * 100.0), int(d["cost"])]])
	_choice("ISS_OPT_RCS", "rcs", o)


func _choice(title_key: String, field: String, options: Array) -> void:
	_opts.add_child(UIKit.label(title_key, 15, UIKit.C_ORANGE))
	var group := ButtonGroup.new()
	for opt in options:
		var b := MissionDesignView.OptionCard.new()
		b.setup(str(opt[1]), str(opt[2]), group)
		b.button_pressed = (design[field] == opt[0])
		b.pressed.connect(func():
			design[field] = opt[0]
			_refresh())
		_opts.add_child(b)


func _refresh() -> void:
	var s := IssDesign.stats(design)
	(_vals["mass"] as Label).text = "%d / %d kg" % [int(s["mass"]), int(s["cap"])]
	(_vals["mass"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if float(s["mass"]) > float(s["cap"]) else Color.WHITE)
	(_vals["fuel"] as Label).text = "%d%%" % int(float(s["fuel"]) * 100.0)
	(_vals["frag"] as Label).text = "x%.1f" % float(s["fragile"])
	(_vals["cost"] as Label).text = "$%d / $%d" % [int(s["cost"]), IssDesign.BUDGET]
	(_vals["cost"] as Label).add_theme_color_override("font_color", UIKit.C_BAD if int(s["cost"]) > IssDesign.BUDGET else UIKit.C_WARN)
