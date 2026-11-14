class_name DeployFx
extends Node2D
## Fairing separation + satellite release + solar panel unfolding.
## Add as a child of the RocketNode at the nose position; animate `t` from 0 to 1.

var nose_id := "std"
var t := 0.0:
	set(v):
		t = v
		queue_redraw()


func _draw() -> void:
	# local origin = centre of the nose section
	var r := Rect2(-RocketDrawer.W * 0.5, -float(M1Parts.NOSES[nose_id]["h"]) * 0.5, RocketDrawer.W,
		float(M1Parts.NOSES[nose_id]["h"]))
	var split := clampf(t * 3.0, 0.0, 1.0)
	var fade := 1.0 - clampf((t - 0.4) * 1.6, 0.0, 1.0)
	# fairing halves (left / right), drifting apart and tumbling
	for side in [-1.0, 1.0]:
		var off := Vector2(side * (split * 46.0 + t * 20.0), -t * 10.0 - split * 6.0)
		draw_set_transform(off, side * split * 0.5 * (1.0 + t), Vector2.ONE)
		var pts := PackedVector2Array()
		var steps := 12
		var half := r.size.x * 0.5
		for i in steps + 1:
			var k := float(i) / float(steps)
			var w := half * pow(maxf(0.0, 1.0 - pow(k, 2.0)), 0.6 * (0.8 if nose_id == "std" else 1.25))
			pts.append(Vector2(side * w, r.position.y + r.size.y * (1.0 - k)))
		pts.append(Vector2(0, r.position.y))
		pts.append(Vector2(0, r.position.y + r.size.y))
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(0.91, 0.94, 1.0, fade))
			draw_polyline(pts, Color(0.16, 0.19, 0.26, fade), 1.5)
	# satellite
	draw_set_transform(Vector2(0, -t * t * 260.0 - 4.0), t * 0.4, Vector2.ONE)
	var unfold := clampf((t - 0.35) * 1.8, 0.0, 1.0)
	var body := Rect2(-9, -12, 18, 24)
	for side in [-1.0, 1.0]:
		var pw := 6.0 + 30.0 * unfold
		var rect := Rect2(0.0 if side > 0.0 else -pw, -5.0, pw, 10.0)
		rect.position.x += side * 9.0
		draw_rect(rect, Color(0.18, 0.5, 0.95))
		draw_rect(rect, Color(0.7, 0.88, 1.0), false, 1.0)
		if unfold > 0.5:
			for g in 3:
				var gx := rect.position.x + rect.size.x * (g + 1) / 4.0
				draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(0.7, 0.88, 1.0, 0.7), 1.0)
	draw_rect(body, Color(0.95, 0.78, 0.35))
	draw_rect(body, Color(0.4, 0.3, 0.1), false, 1.5)
	draw_circle(Vector2(0, -2), 3.5, Color(0.2, 0.3, 0.5))
	var blink := 0.5 + 0.5 * sin(t * 40.0)
	draw_circle(Vector2(0, -16), 2.0, Color(1.0, 0.3, 0.3, blink if unfold > 0.8 else 0.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
