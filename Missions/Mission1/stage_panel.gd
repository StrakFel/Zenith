class_name StagePanel
extends PanelContainer
## In-flight STAGE SEPARATION panel (right, vertically centred): which stage is active, its propellant, a button to drop
## the spent first stage (G) and one to jettison the fairing (F). Unavailable actions are greyed out. A short beginner
## hint reacts to the flight state. Compact on purpose: it must never overlap the rest of the HUD.

signal separate_requested
signal fairing_requested

const W := 236.0

var _chip1: Label
var _chip2: Label
var _fuel: ProgressBar
var _fuel_lbl: Label
var _sep_btn: Button
var _fair_btn: Button
var _hint: Label
var _t := 0.0
var _model: FlightModel
var _last_stage := 1
var _last_fairing := true


func setup(m: FlightModel) -> void:
	_model = m
	theme = UIKit.get_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -W - 16.0
	offset_right = -16.0
	offset_top = -104.0
	offset_bottom = 112.0
	grow_vertical = Control.GROW_DIRECTION_BOTH
	add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.07, 0.14, 0.82), UIKit.C_BORDER, 10, 1, 8))
	var v := UIKit.vbox(5)
	add_child(v)
	v.add_child(UIKit.label("STG_TITLE", 14, UIKit.C_ACCENT))
	var chips := UIKit.hbox(6)
	_chip1 = _chip("STG_CHIP1")
	_chip2 = _chip("STG_CHIP2")
	chips.add_child(_chip1)
	if m.has_upper:
		chips.add_child(_chip2)
	v.add_child(chips)
	var fr := UIKit.hbox(6)
	_fuel = UIKit.progress_bar(UIKit.C_ORANGE, Vector2(0, 10))
	_fuel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fr.add_child(_fuel)
	_fuel_lbl = UIKit.label("100%", 12, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_fuel_lbl.custom_minimum_size.x = 38
	fr.add_child(_fuel_lbl)
	v.add_child(fr)
	_sep_btn = _button("STG_SEPARATE", "SeparateButton")
	_sep_btn.pressed.connect(func(): separate_requested.emit())
	v.add_child(_sep_btn)
	_fair_btn = _button("STG_FAIRING", "FairingButton")
	_fair_btn.pressed.connect(func(): fairing_requested.emit())
	v.add_child(_fair_btn)
	_hint = UIKit.label("", 11, UIKit.C_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(W - 20.0, 44)
	v.add_child(_hint)
	_last_stage = m.stage
	_last_fairing = m.fairing_on


func _chip(key: String) -> Label:
	var l := UIKit.label(key, 12, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l.custom_minimum_size = Vector2(70, 22)
	l.add_theme_stylebox_override("normal", UIKit.box(Color(0.06, 0.1, 0.18, 0.9), UIKit.C_BORDER, 6, 1, 3))
	return l


func _button(key: String, nm: String) -> Button:
	var b := UIKit.button(key, Vector2(0, 32))
	b.name = nm
	b.add_theme_font_size_override("font_size", 13)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	return b


func _set_chip(l: Label, active: bool, done: bool) -> void:
	var border := UIKit.C_ORANGE if active else UIKit.C_BORDER
	l.add_theme_stylebox_override("normal", UIKit.box(Color(0.25, 0.12, 0.02, 0.9) if active else Color(0.06, 0.1, 0.18, 0.9), border, 6, 2 if active else 1, 3))
	l.add_theme_color_override("font_color", Color.WHITE if active else (UIKit.C_MUTED if not done else Color(0.4, 0.45, 0.55)))


## Small animation: the panel flashes when the stage / fairing state changes.
func _flash() -> void:
	modulate = Color(1.6, 1.4, 1.1)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.7)


func refresh(delta: float) -> void:
	_t += delta
	var m := _model
	var pulse := 0.65 + 0.35 * sin(_t * 7.0)
	var alt := m.altitude()
	if m.stage != _last_stage or m.fairing_on != _last_fairing:
		_last_stage = m.stage
		_last_fairing = m.fairing_on
		_flash()
	_set_chip(_chip1, m.stage == 1, m.stage > 1)
	_set_chip(_chip2, m.stage == 2, false)
	_fuel.value = m.fuel_fraction() * 100.0
	_fuel_lbl.text = "%d%%" % int(m.fuel_fraction() * 100.0)
	UIKit.set_bar_color(_fuel, UIKit.C_BAD if m.fuel_fraction() < 0.1 else UIKit.C_ORANGE)
	var can_sep := m.has_upper and m.stage == 1
	_sep_btn.disabled = not can_sep
	_sep_btn.visible = m.has_upper
	var sep_now := can_sep and m.fuel_fraction() < 0.1
	_sep_btn.modulate = Color(1.0, 0.7 + 0.3 * pulse, 0.45, 1.0) if sep_now else Color.WHITE
	_sep_btn.text = "STG_SEPARATE" if can_sep else "STG_SEPARATED"
	_fair_btn.disabled = not m.fairing_on
	var fair_ok := m.fairing_on and alt >= 85_000.0
	_fair_btn.modulate = Color(0.6, 1.0, 0.7, 1.0) if fair_ok else Color.WHITE
	_fair_btn.text = "STG_FAIRING" if m.fairing_on else "STG_FAIRING_OFF"
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
	elif m.has_upper and m.stage == 2 and m.ignite_in > 0.0:
		key = "STG_HINT_IGNITE"
		col = UIKit.C_ACCENT
	elif m.fairing_on and fair_ok:
		key = "STG_HINT_FAIRING_OK"
		col = UIKit.C_GOOD
	elif m.fairing_on:
		key = "STG_HINT_FAIRING_WAIT"
	elif not m.has_upper:
		key = "STG_SINGLE"
	_hint.text = key
	_hint.add_theme_color_override("font_color", col)
