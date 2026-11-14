class_name OffscreenArrow
extends Control
## 2D overlay: when a 3D target is off-screen, draws an arrow at the edge of a safe box
## pointing towards it, plus a distance label.

var camera: Camera3D
var target := Vector3.ZERO
var distance_text := ""
var color := Color("ff8a2b")
var margin := Rect2(70.0, 260.0, 0.0, 0.0)   # left, top (width/height filled from the viewport)
var bottom_margin := 130.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var s := size
	var box := Rect2(margin.position.x, margin.position.y, s.x - margin.position.x * 2.0,
		s.y - margin.position.y - bottom_margin)
	var behind := camera.is_position_behind(target)
	var sp := camera.unproject_position(target)
	if behind:
		sp = s - sp
	if box.has_point(sp) and not behind:
		return
	var c := box.get_center()
	var dv := (sp - c)
	if dv.length() < 0.001:
		dv = Vector2.UP
	dv = dv.normalized()
	var k := 1.0 / maxf(absf(dv.x) / (box.size.x * 0.5), absf(dv.y) / (box.size.y * 0.5))
	var p := c + dv * k
	var perp := dv.orthogonal()
	draw_colored_polygon(PackedVector2Array([p + dv * 17.0, p - dv * 10.0 + perp * 12.0, p - dv * 10.0 - perp * 12.0]), color)
	draw_string(ThemeDB.fallback_font, p - dv * 36.0 - Vector2(30, -5), distance_text,
		HORIZONTAL_ALIGNMENT_CENTER, 70.0, 15, color)
