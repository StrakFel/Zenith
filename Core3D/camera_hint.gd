class_name CameraHint
extends Control
## Small on-screen reminder of the camera controls (+ an INSPECT MODE banner for missions).

var _panel: PanelContainer
var _banner: PanelContainer
var _label: Label
var _mission_mode := false
var _top := -1.0
var _right := false
var _compact := false
var _hud_corner := false
var _bottom := false
var _user_hidden := false
var _bottom_mid := false
var _fade: Tween


## top >= 0: centred at that y. top < 0: bottom corner (left, or right when `right`).
func setup(mission_mode: bool, top: float = -1.0, right: bool = false) -> void:
	_mission_mode = mission_mode
	_top = top
	_right = right
	theme = UIKit.get_ui_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = UIKit.panel()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UIKit.box(Color(0.03, 0.07, 0.14, 0.72), UIKit.C_BORDER, 8, 1, 8))
	_label = UIKit.label("CAM_HINT_MISSION" if mission_mode else "CAM_HINT_MENU", 12, UIKit.C_MUTED)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 420
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)
	_banner = UIKit.panel()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", UIKit.box(Color(0.25, 0.12, 0.02, 0.88), UIKit.C_ORANGE, 10, 2, 10))
	var b := UIKit.label("CAM_INSPECT", 17, UIKit.C_ORANGE, HORIZONTAL_ALIGNMENT_CENTER)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 640
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(b)
	_banner.visible = false
	add_child(_banner)
	_layout()


func _layout() -> void:
	if _bottom:
		# assembly screens: between the side panels at the bottom, never over the part tabs / cards
		if _bottom_mid:      # between the two side panels of the design screen
			_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			_panel.offset_left = -136
			_panel.offset_right = 136
		else:                # left, in the free 3D area next to the designer panel
			_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
			_panel.offset_left = 16
			_panel.offset_right = 330
		_panel.offset_bottom = -12
		_panel.offset_top = -12
		_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_banner.offset_left = -300
		_banner.offset_right = 300
		_banner.offset_bottom = -64
		_banner.offset_top = -64
		_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		return
	if _hud_corner:
		# flight HUD: the hint sits at the top-right under the clock, the inspect banner at the bottom-centre
		_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_panel.offset_left = -246
		_panel.offset_right = -16
		_panel.offset_top = 118
		_panel.offset_bottom = 118
		_panel.grow_vertical = Control.GROW_DIRECTION_END
		_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_banner.offset_left = -300
		_banner.offset_right = 300
		_banner.offset_bottom = -64
		_banner.offset_top = -64
		_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		return
	if _top >= 0.0:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_panel.offset_top = _top
		_panel.offset_left = -165 if _compact else -215
		_panel.offset_right = 165 if _compact else 215
	elif _right:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_panel.offset_left = -440
		_panel.offset_right = -40
		_panel.offset_bottom = -44
		_panel.offset_top = -92
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_panel.offset_left = 40
		_panel.offset_bottom = -44
		_panel.offset_top = -92
		_panel.offset_right = 440
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = (_top if _top >= 0.0 else 16.0) + 4.0
	_banner.offset_left = -330
	_banner.offset_right = 330


func set_mission_mode(on: bool, top: float = -2.0) -> void:
	_mission_mode = on
	_label.text = "CAM_HINT_MISSION" if on else "CAM_HINT_MENU"
	if top > -1.5:
		_top = top
	_layout()


## Bottom-centre placement + fade-out after `seconds` (F1 shows it again). Used on the assembly screens.
func set_bottom(on: bool, seconds: float = 0.0, middle: bool = false) -> void:
	_bottom = on
	_bottom_mid = middle
	if on:
		_label.custom_minimum_size.x = 250.0 if middle else 292.0
		_label.text = "CAM_HINT_SHORT"
	else:
		_label.text = "CAM_HINT_MISSION" if _mission_mode else "CAM_HINT_MENU"
	_layout()
	_panel.modulate.a = 1.0
	_user_hidden = false
	if _fade != null:
		_fade.kill()
	if on and seconds > 0.0:
		_fade = create_tween()
		_fade.tween_interval(seconds)
		_fade.tween_property(_panel, "modulate:a", 0.0, 0.8)
	_panel.visible = true


## F1: show / hide the camera help by hand.
func toggle_help() -> void:
	if _fade != null:
		_fade.kill()
	_user_hidden = not _user_hidden and _panel.modulate.a > 0.5
	_panel.modulate.a = 0.0 if _user_hidden else 1.0


## F1 works on every screen that has a camera hint (the hint owns its key, screens do not need to forward it).
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F1 and is_visible_in_tree() and not _banner.visible:
		toggle_help()


## Flight-HUD placement (top-right under the clock / bottom-centre banner) - no overlap with the task panel.
func set_hud_corner(on: bool) -> void:
	_hud_corner = on
	_label.custom_minimum_size.x = 214.0 if on else (320.0 if _compact else 420.0)
	_layout()


## Narrow variant for screens with side panels (assembly): wraps into 3 lines between the panels.
func set_compact(on: bool) -> void:
	_compact = on
	_label.custom_minimum_size.x = 320.0 if on else 420.0
	_layout()


func set_inspect(on: bool) -> void:
	_banner.visible = on
	_panel.visible = not on
