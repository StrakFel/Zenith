class_name StagePanel
extends PanelContainer
## In-flight STAGE SEPARATION interface: shows the active stage and its propellant, a button to drop the spent first
## stage (G) and one to jettison the payload fairing (F), plus short beginner hints that react to the flight state.

signal separate_requested
signal fairing_requested

var _stage_lbl: Label
var _fuel: ProgressBar
var _sep_btn: Button
var _fair_btn: Button
var _hint: Label
var _t := 0.0
var _model: FlightModel


func setup(m: FlightModel) -> void:
	_model = m
	theme = UIKit.get_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -292
	offset_right = -16
	offset_top = -110
	offset_bottom = 150
	add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.07, 0.14, 0.82), UIKit.C_BORDER, 10, 1, 10))
	var v := UIKit.vbox(6)
	add_child(v)
	v.add_child(UIKit.label("STG_TITLE", 17, UIKit.C_ACCENT))
	_stage_lbl = UIKit.label("", 15, Color.WHITE)
	v.add_child(_stage_lbl)
	_fuel = UIKit.progress_bar(UIKit.C_ORANGE, Vector2(0, 12))
	v.add_child(_fuel)
	_sep_btn = UIKit.button("STG_SEPARATE", Vector2(0, 40))
	_sep_btn.name = "SeparateButton"
	_sep_btn.add_theme_font_size_override("font_size", 15)
	_sep_btn.focus_mode = Control.FOCUS_NONE
	_sep_btn.pressed.connect(func(): separate_requested.emit())
	v.add_child(_sep_btn)
	_fair_btn = UIKit.button("STG_FAIRING", Vector2(0, 40))
	_fair_btn.name = "FairingButton"
	_fair_btn.add_theme_font_size_override("font_size", 15)
	_fair_btn.focus_mode = Control.FOCUS_NONE
	_fair_btn.pressed.connect(func(): fairing_requested.emit())
	v.add_child(_fair_btn)
	_hint = UIKit.label("", 12, UIKit.C_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 250
	v.add_child(_hint)


func refresh(delta: float) -> void:
	_t += delta
	var m := _model
	var pulse := 0.65 + 0.35 * sin(_t * 7.0)
	var alt := m.altitude()
	if m.has_upper:
		_stage_lbl.text = "%s %d / 2" % [tr("STG_ACTIVE"), m.stage]
	else:
		_stage_lbl.text = tr("STG_SINGLE")
	_fuel.value = m.fuel_fraction() * 100.0
	UIKit.set_bar_color(_fuel, UIKit.C_BAD if m.fuel_fraction() < 0.1 else UIKit.C_ORANGE)
	# separation button
	var can_sep := m.has_upper and m.stage == 1
	_sep_btn.disabled = not can_sep
	var sep_now := can_sep and m.fuel_fraction() < 0.1
	_sep_btn.modulate = Color(1.0, 0.75 + 0.25 * pulse, 0.5, 1.0) if sep_now else Color.WHITE
	_sep_btn.visible = m.has_upper
	# fairing button
	_fair_btn.disabled = not m.fairing_on
	var fair_ok := m.fairing_on and alt >= 85_000.0
	_fair_btn.modulate = Color(0.6, 1.0, 0.7, 1.0) if fair_ok else Color.WHITE
	_fair_btn.text = "STG_FAIRING" if m.fairing_on else "STG_FAIRING_OFF"
	# beginner hint
	var key := "STG_HINT_IDLE"
	var col := UIKit.C_MUTED
	if m.has_upper and m.stage == 1 and m.fuel <= 0.0:
		key = "STG_HINT_EMPTY"
		col = UIKit.C_BAD
	elif sep_now:
		key = "STG_HINT_SEP"
		col = UIKit.C_ORANGE
	elif m.has_upper and m.stage == 1:
		key = "STG_HINT_STAGE1"
	elif m.fairing_on and fair_ok:
		key = "STG_HINT_FAIRING_OK"
		col = UIKit.C_GOOD
	elif m.fairing_on and alt < 85_000.0 and m.stage == 1 and not m.has_upper:
		key = "STG_HINT_FAIRING_WAIT"
	elif m.has_upper and m.stage == 2 and m.ignite_in > 0.0:
		key = "STG_HINT_IGNITE"
		col = UIKit.C_ACCENT
	elif m.fairing_on:
		key = "STG_HINT_FAIRING_WAIT"
	_hint.text = key
	_hint.add_theme_color_override("font_color", col)
