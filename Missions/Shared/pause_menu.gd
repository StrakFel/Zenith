class_name PauseMenu
extends Control
## Pause overlay. Must keep running while the tree is paused.

signal resumed
signal restart_requested
signal missions_requested
signal menu_requested

var enabled := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	theme = UIKit.get_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UIKit.panel()
	center.add_child(p)
	var v := UIKit.vbox(12)
	p.add_child(v)
	v.add_child(UIKit.label("PAUSE_TITLE", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var b1 := UIKit.button("BTN_RESUME")
	var b2 := UIKit.button("BTN_RESTART")
	var b3 := UIKit.button("BTN_MISSIONS")
	var b4 := UIKit.button("BTN_MAIN_MENU")
	for b in [b1, b2, b3, b4]:
		v.add_child(b)
	b1.pressed.connect(close)
	b2.pressed.connect(func(): restart_requested.emit())
	b3.pressed.connect(func(): missions_requested.emit())
	b4.pressed.connect(func(): menu_requested.emit())


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	resumed.emit()
