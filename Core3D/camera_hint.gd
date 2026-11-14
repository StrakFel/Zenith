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
		_panel.offset_left = -452
		_panel.offset_right = -16
		_panel.offset_bottom = -16
		_panel.offset_top = -62
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_panel.offset_left = 16
		_panel.offset_bottom = -16
		_panel.offset_top = -62
		_panel.offset_right = 452
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
