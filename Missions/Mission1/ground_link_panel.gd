class_name GroundLinkPanel
extends PanelContainer
## Ground segment: animated data downlink. Data that does not fit into the contact window
## (slow antenna vs fast instrument) is lost - the bar shows both.

signal finished

var _bar: ProgressBar
var _sent: Label
var _lost: Label
var _t := 0.0
var _dur := 7.0
var _ratio := 1.0
var _total_mbit := 0.0


func setup(total_mbit: float, sent_ratio: float, duration: float = 7.0) -> void:
	theme = UIKit.get_ui_theme()
	_total_mbit = total_mbit
	_ratio = sent_ratio
	_dur = duration
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -330
	offset_right = 330
	offset_top = -190
	offset_bottom = -90
	var v := UIKit.vbox(6)
	add_child(v)
	v.add_child(UIKit.label("GND_TITLE", 20, UIKit.C_ACCENT))
	v.add_child(UIKit.label("GND_CONTACT", 14, UIKit.C_MUTED))
	_bar = UIKit.progress_bar(UIKit.C_GOOD, Vector2(0, 16))
	v.add_child(_bar)
	var h := UIKit.hbox(12)
	v.add_child(h)
	_sent = UIKit.label("", 15, UIKit.C_GOOD)
	_sent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_sent)
	_lost = UIKit.label("", 15, UIKit.C_BAD, HORIZONTAL_ALIGNMENT_RIGHT)
	h.add_child(_lost)
	Sfx.loop("hiss", -22.0, 0.6)


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _dur, 0.0, 1.0)
	_bar.value = k * _ratio * 100.0
	var sent := _total_mbit * _ratio * k
	_sent.text = "%s: %d %s" % [tr("GND_SENT"), int(sent), tr("UNIT_MBIT")]
	var lost := _total_mbit * (1.0 - _ratio) * k
	_lost.text = ("%s: %d %s" % [tr("GND_LOST"), int(lost), tr("UNIT_MBIT")]) if _ratio < 0.999 else ""
	if k >= 1.0:
		set_process(false)
		Sfx.loop_stop("hiss")
		Sfx.play("beep")
		finished.emit()
