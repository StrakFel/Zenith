class_name FlightHud
extends Control
## Flight HUD: telemetry, gauges, attitude indicator, hints, big countdown text.

class Attitude extends Control:
	var pitch := 0.0
	var prograde := 0.0
	var show_prograde := false
	var target_pitch := NAN        # guided launch: where the guide wants the nose (rad from vertical)

	func _init() -> void:
		custom_minimum_size = Vector2(120, 120)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		draw_circle(c, r, Color(0.03, 0.07, 0.14, 0.85))
		# sky/ground split follows pitch (0 = nose up -> mostly "ground" below)
		draw_arc(c, r, 0.0, TAU, 48, UIKit.C_BORDER, 2.0, true)
		for i in 12:
			var a := TAU * float(i) / 12.0
			var l := 8.0 if i % 3 == 0 else 4.0
			draw_line(c + Vector2.from_angle(a) * (r - l), c + Vector2.from_angle(a) * r, UIKit.C_MUTED, 1.5)
		# horizon bar: horizontal flight (pitch 90deg) = bar horizontal through the dial
		var ang := pitch  # rotation of the rocket against local vertical
		var up := Vector2(sin(ang), -cos(ang))
		var nose := c + up * r * 0.82
		draw_line(c - up * r * 0.5, nose, UIKit.C_ORANGE, 4.0, true)
		draw_colored_polygon(PackedVector2Array([nose, nose - up * 12.0 + up.orthogonal() * 7.0,
			nose - up * 12.0 - up.orthogonal() * 7.0]), UIKit.C_ORANGE)
		if show_prograde:
			var pu := Vector2(sin(prograde), -cos(prograde))
			var pp := c + pu * r * 0.62
			draw_arc(pp, 7.0, 0.0, TAU, 20, UIKit.C_GOOD, 2.0, true)
			draw_line(pp + Vector2(0, -12), pp + Vector2(0, -7), UIKit.C_GOOD, 2.0)
			draw_line(pp + Vector2(-12, 0), pp + Vector2(-7, 0), UIKit.C_GOOD, 2.0)
			draw_line(pp + Vector2(12, 0), pp + Vector2(7, 0), UIKit.C_GOOD, 2.0)
		if not is_nan(target_pitch):
			var tu := Vector2(sin(target_pitch), -cos(target_pitch))
			var tp := c + tu * r * 0.82
			draw_arc(tp, 9.0, 0.0, TAU, 24, UIKit.C_ACCENT, 2.5, true)       # steer the orange nose into this ring
			draw_arc(tp, 3.0, 0.0, TAU, 12, UIKit.C_ACCENT, 2.0, true)
		draw_circle(c, 3.0, Color.WHITE)
		# local vertical mark
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 1), c + Vector2(-5, -r + 8), c + Vector2(5, -r + 8)]),
			Color(0.6, 0.8, 1.0, 0.7))


var _vals: Dictionary = {}
var _fuel: ProgressBar
var _thr: ProgressBar
var _integ: ProgressBar
var _qbar: ProgressBar
var _hint: Label
var _hint_panel: PanelContainer
var _hint_key := ""
var _toast: Label
var _toast_panel: PanelContainer
var _toast_tw: Tween
var _warp: Label
var _clock: Label
var _att: Attitude
var _assist: Label
var _guide_lbl: Label


func build() -> void:
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ---- telemetry (top-left)
	var tl := UIKit.panel()
	tl.position = Vector2(16, 16)
	add_child(tl)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 3)
	tl.add_child(g)
	for row in [["HUD_ALT", "alt"], ["HUD_SPEED", "spd"], ["HUD_VERT", "vr"], ["HUD_HORIZ", "vt"],
			["HUD_AP", "ap"], ["HUD_PE", "pe"]]:
		g.add_child(UIKit.label(row[0], 16, UIKit.C_MUTED))
		var v := UIKit.label("0", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		v.custom_minimum_size.x = 118
		g.add_child(v)
		_vals[row[1]] = v

	# ---- gauges (bottom-left)
	var bl := UIKit.panel()
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.offset_left = 16
	bl.offset_bottom = -16
	bl.offset_top = -190
	bl.offset_right = 290
	add_child(bl)
	var gv := UIKit.vbox(6)
	bl.add_child(gv)
	_fuel = _gauge(gv, "HUD_FUEL", UIKit.C_ORANGE)
	_thr = _gauge(gv, "HUD_THROTTLE", UIKit.C_ACCENT)
	_qbar = _gauge(gv, "HUD_MAXQ", UIKit.C_GOOD)
	_integ = _gauge(gv, "HUD_INTEGRITY", UIKit.C_GOOD)

	# ---- attitude (bottom-right)
	var br := UIKit.panel()
	br.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	br.offset_right = -16
	br.offset_bottom = -16
	br.offset_left = -190
	br.offset_top = -214
	add_child(br)
	var av := UIKit.vbox(4)
	br.add_child(av)
	_att = Attitude.new()
	av.add_child(_att)
	_assist = UIKit.label("HUD_ASSIST_OFF", 14, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_assist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_assist.custom_minimum_size.x = 150
	av.add_child(_assist)
	_guide_lbl = UIKit.label("HUD_GUIDE_ON", 13, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_guide_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_lbl.custom_minimum_size.x = 150
	av.add_child(_guide_lbl)

	# ---- clock / warp (top-right)
	var tr_p := UIKit.panel()
	tr_p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tr_p.offset_right = -16
	tr_p.offset_top = 16
	tr_p.offset_left = -190
	add_child(tr_p)
	var tv := UIKit.vbox(2)
	tr_p.add_child(tv)
	_clock = UIKit.label("T+ 00:00", 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_clock)
	_warp = UIKit.label("x1", 16, UIKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_warp)

	# ---- top-centre: current task (hint) with compact notifications stacked under it - never over the rocket
	var tc := VBoxContainer.new()
	tc.add_theme_constant_override("separation", 6)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tc.offset_left = -300
	tc.offset_right = 300
	tc.offset_top = 16
	tc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(tc)
	_hint_panel = UIKit.panel()
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	tc.add_child(_hint_panel)
	_hint = UIKit.label("", 17, UIKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 560
	_hint_panel.add_child(_hint)
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", UIKit.box(Color(0.04, 0.09, 0.18, 0.9), UIKit.C_ACCENT, 8, 1, 8))
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_panel.visible = false
	tc.add_child(_toast_panel)
	_toast = UIKit.label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size.x = 420
	_toast_panel.add_child(_toast)

	# ---- controls reminder (bottom-centre, between the gauges and the attitude panel)
	var ctl := UIKit.label("HUD_CONTROLS_HINT", 13, UIKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	ctl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	ctl.offset_left = -330
	ctl.offset_right = 330
	ctl.offset_top = -46
	ctl.offset_bottom = -8
	ctl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(ctl)


func _gauge(parent: Control, key: String, color: Color) -> ProgressBar:
	var h := UIKit.hbox(8)
	var l := UIKit.label(key, 14, UIKit.C_MUTED)
	l.custom_minimum_size.x = 92
	h.add_child(l)
	var b := UIKit.progress_bar(color, Vector2(150, 12))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	parent.add_child(h)
	return b


func fmt_dist(m: float) -> String:
	if absf(m) >= 10000.0:
		return "%.1f %s" % [m / 1000.0, tr("UNIT_KM")]
	if absf(m) >= 1000.0:
		return "%.2f %s" % [m / 1000.0, tr("UNIT_KM")]
	return Units.m(m)


func refresh(m: FlightModel, warp: int, assist: bool, mission_time: float) -> void:
	(_vals["alt"] as Label).text = fmt_dist(m.altitude())
	(_vals["spd"] as Label).text = "%d %s" % [int(m.speed()), tr("UNIT_MS")]
	(_vals["vr"] as Label).text = "%d %s" % [int(m.vr), tr("UNIT_MS")]
	(_vals["vt"] as Label).text = "%d %s" % [int(m.vt), tr("UNIT_MS")]
	var o := m.orbit()
	var ap_l: Label = _vals["ap"]
	var pe_l: Label = _vals["pe"]
	ap_l.text = fmt_dist(minf(float(o["ap"]), 99_999_000.0)) if bool(o["bound"]) else "---"
	pe_l.text = fmt_dist(float(o["pe"])) if bool(o["bound"]) else "---"
	var pe_ok := bool(o["bound"]) and float(o["pe"]) >= FlightModel.SAFE_PE
	pe_l.add_theme_color_override("font_color", UIKit.C_GOOD if pe_ok else Color.WHITE)
	_fuel.value = m.fuel_fraction() * 100.0
	UIKit.set_bar_color(_fuel, UIKit.C_BAD if m.fuel_fraction() < 0.1 else UIKit.C_ORANGE)
	_thr.value = m.throttle * 100.0
	var qf := m.q / FlightModel.Q_LIMIT
	_qbar.value = clampf(qf * 100.0, 0.0, 100.0)
	UIKit.set_bar_color(_qbar, UIKit.C_BAD if qf > 1.0 else (UIKit.C_WARN if qf > 0.75 else UIKit.C_GOOD))
	_integ.value = m.integrity
	UIKit.set_bar_color(_integ, UIKit.C_BAD if m.integrity < 40.0 else (UIKit.C_WARN if m.integrity < 75.0 else UIKit.C_GOOD))
	_att.pitch = m.pitch
	_att.prograde = m.prograde_pitch()
	_att.show_prograde = m.speed() > 20.0
	_att.queue_redraw()
	_assist.text = "HUD_ASSIST_ON" if assist else "HUD_ASSIST_OFF"
	_assist.add_theme_color_override("font_color", UIKit.C_GOOD if assist else UIKit.C_MUTED)
	_warp.text = "x%d" % warp
	var sec := int(maxf(mission_time, 0.0))
	_clock.text = "T+ %02d:%02d" % [sec / 60, sec % 60]


## Guided launch indicator and the target-pitch ring on the attitude dial (NAN = no target).
func set_guided(on: bool, target_pitch: float = NAN) -> void:
	_guide_lbl.text = "HUD_GUIDE_ON" if on else "HUD_GUIDE_OFF"
	_guide_lbl.add_theme_color_override("font_color", UIKit.C_ACCENT if on else UIKit.C_MUTED)
	_att.target_pitch = target_pitch if on else NAN


func set_hint(key: String, color: Color = UIKit.C_TEXT) -> void:
	if key == _hint_key:
		return
	_hint_key = key
	if key == "":
		_hint_panel.visible = false
		return
	_hint.text = key
	_hint.add_theme_color_override("font_color", color)
	_hint_panel.visible = true
	_hint_panel.modulate.a = 0.0
	create_tween().tween_property(_hint_panel, "modulate:a", 1.0, 0.3)


## Compact game notification (top-centre, under the task hint): fades in, stays ~2 s, fades out. Replaces the old
## giant centre text. Countdown digits are shown a bit larger but in the same place.
func notify(text: String, color: Color = Color.WHITE) -> void:
	_toast.text = text
	var digits := text.length() <= 2
	_toast.add_theme_font_size_override("font_size", 40 if digits else 16)
	_toast.add_theme_color_override("font_color", color)
	_toast.custom_minimum_size.x = 80 if digits else 420
	_toast_panel.add_theme_stylebox_override("panel", UIKit.box(Color(0.04, 0.09, 0.18, 0.9), color, 8, 1, 8))
	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	if _toast_tw != null:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_property(_toast_panel, "modulate:a", 1.0, 0.3)
	_toast_tw.tween_interval(1.0 if digits else 1.9)
	_toast_tw.tween_property(_toast_panel, "modulate:a", 0.0, 0.5)
	_toast_tw.tween_callback(func(): _toast_panel.visible = false)


func big(text: String, color: Color = Color.WHITE) -> void:
	notify(text, color)
