class_name PayloadLab
extends Control
## Generic "what are we delivering?" lab for missions 2-5 (step 1 of the design loop, before the rocket designer).
## Option groups and the live mass / cost readout come from LaunchProfiles.

signal design_done(design: Dictionary)
signal back_requested

var profile_id := "m2"
var design: Dictionary = {}
var _opts: VBoxContainer
var _mass: Label
var _cost: Label
var _lines: VBoxContainer


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pf := LaunchProfiles.get_profile(profile_id)
	if design.is_empty():
		design = LaunchProfiles.default_design(profile_id)
	var p := UIKit.panel()
	p.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	p.offset_left = 16
	p.offset_top = 16
	p.offset_bottom = -16
	p.offset_right = 560
	add_child(p)
	var outer := UIKit.vbox(8)
	p.add_child(outer)
	outer.add_child(UIKit.label(str(pf["lab_title"]), 26, Color.WHITE))
	var sub := UIKit.label(str(pf["lab_sub"]), 13, UIKit.C_MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size.x = 500
	outer.add_child(sub)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_opts = UIKit.vbox(6)
	_opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_opts)
	outer.add_child(HSeparator.new())
	var r1 := UIKit.hbox(8)
	r1.add_child(UIKit.label("PL_PAYLOAD_MASS", 14, UIKit.C_MUTED))
	_mass = UIKit.label("", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_mass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_mass)
	outer.add_child(r1)
	var r2 := UIKit.hbox(8)
	r2.add_child(UIKit.label("PL_PAYLOAD_COST", 14, UIKit.C_MUTED))
	_cost = UIKit.label("", 15, UIKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(_cost)
	outer.add_child(r2)
	_lines = UIKit.vbox(2)
	outer.add_child(_lines)
	var go := UIKit.button("PL_CONTINUE", Vector2(0, 50))
	go.name = "ContinueButton"
	go.pressed.connect(func(): design_done.emit(design.duplicate()))
	outer.add_child(go)
	var back := UIKit.button("BTN_BACK_MISSIONS", Vector2(0, 38))
	back.name = "BackButton"
	back.add_theme_font_size_override("font_size", 15)
	back.pressed.connect(func(): back_requested.emit())
	outer.add_child(back)
	_build()
	_refresh()


func _build() -> void:
	for g in LaunchProfiles.groups(profile_id):
		_opts.add_child(UIKit.label(str(g["title"]), 15, UIKit.C_ORANGE))
		var group := ButtonGroup.new()
		for o in g["options"]:
			var b := MissionDesignView.OptionCard.new()
			var info := str(o["info"])
			if int(o["cost"]) > 0:
				info = "%s | %s" % [info, Units.money(int(o["cost"]))] if info != "" else Units.money(int(o["cost"]))
			b.setup(str(o["name"]), info, group)
			b.button_pressed = str(design.get(g["id"], "")) == str(o["id"])
			var gid: String = g["id"]
			var oid: String = o["id"]
			b.pressed.connect(func():
				design[gid] = oid
				_refresh())
			_opts.add_child(b)


func _refresh() -> void:
	var st := LaunchProfiles.payload_stats(profile_id, design)
	_mass.text = Units.kg(float(st["mass"]))
	_cost.text = Units.money(int(st["cost"]))
	for c in _lines.get_children():
		c.queue_free()
	for l in st["lines"]:
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(str(l[0]), 13, UIKit.C_MUTED))
		var v := UIKit.label(str(l[1]), 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		_lines.add_child(row)
