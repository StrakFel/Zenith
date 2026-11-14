class_name OverlayFrame
extends Control
## Responsive modal window used by briefing / review / result screens.
##   header  - fixed block at the top (titles)
##   body    - inside a ScrollContainer: long text scrolls instead of growing off-screen
##   footer  - fixed row of buttons OUTSIDE the scroll area, so it is always visible
## The window is as tall as its content but never taller than the screen (margins included).
## It re-fits itself whenever the viewport size changes.

var max_width := 900.0
var panel: PanelContainer
var header: VBoxContainer
var scroll: ScrollContainer
var body: VBoxContainer
var footer: HBoxContainer

var _fit_queued := false


func build(width: float = 900.0, dim_alpha: float = 0.88) -> void:
	max_width = width
	theme = UIKit.get_ui_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, dim_alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = UIKit.panel()
	center.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	header = UIKit.vbox(6)
	v.add_child(header)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	body = UIKit.vbox(10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	v.add_child(HSeparator.new())
	footer = UIKit.hbox(12)
	footer.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(footer)
	resized.connect(request_fit)
	request_fit()


func request_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


func _fit() -> void:
	_fit_queued = false
	if not is_inside_tree() or size.x < 10.0:
		return
	var w := minf(max_width, size.x - 24.0)
	panel.custom_minimum_size.x = w
	scroll.custom_minimum_size.x = w - 34.0
	# two passes: labels re-wrap after the first width change
	for pass_i in 2:
		var avail := size.y - 24.0 - header.get_combined_minimum_size().y - footer.get_combined_minimum_size().y - 70.0
		var need := body.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = clampf(need, 60.0, maxf(avail, 60.0))
		if pass_i == 0:
			await get_tree().process_frame
			if not is_inside_tree():
				return
