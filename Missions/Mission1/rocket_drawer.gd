class_name RocketDrawer
extends RefCounted
## Procedural rocket art. Local coordinates: origin = bottom centre of the engine,
## the rocket grows towards -Y. Callers set draw_set_transform() before calling.

const W := 56.0
const WHITE := Color("e9f0ff")
const SHADE := Color("aebbd6")
const DARK := Color("2a3142")
const ORANGE := Color("ff7a1f")
const BLUE := Color("3da5ff")


static func _id(build: Dictionary, slot: String) -> String:
	return str(build.get(slot, ""))


static func layout(build: Dictionary) -> Dictionary:
	var n := _id(build, "nose")
	var t := _id(build, "tank")
	var e := _id(build, "engine")
	var nd: String = n if n != "" else "std"
	var td: String = t if t != "" else "m"
	var ed: String = e if e != "" else "kestrel"
	var eh: float = float(M1Parts.ENGINES[ed]["h"])
	var ew: float = float(M1Parts.ENGINES[ed]["w"])
	var th: float = float(M1Parts.TANKS[td]["h"])
	var nh: float = float(M1Parts.NOSES[nd]["h"])
	return {
		"engine": Rect2(-ew * 0.5, -eh, ew, eh),
		"tank": Rect2(-W * 0.5, -eh - th + 2.0, W, th),
		"nose": Rect2(-W * 0.5, -eh - th - nh + 4.0, W, nh),
		"height": eh + th + nh - 4.0,
	}


static func height_of(build: Dictionary) -> float:
	return float(layout(build)["height"])


static func _c(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func draw_rocket(ci: CanvasItem, build: Dictionary, alpha: float = 1.0, with_nose: bool = true) -> void:
	var lay := layout(build)
	if _id(build, "tank") != "":
		draw_tank(ci, _id(build, "tank"), lay["tank"], alpha)
	if _id(build, "engine") != "":
		draw_engine(ci, _id(build, "engine"), lay["engine"], alpha)
	if with_nose and _id(build, "nose") != "":
		draw_nose(ci, _id(build, "nose"), lay["nose"], alpha)


static func draw_engine(ci: CanvasItem, id: String, r: Rect2, a: float) -> void:
	var cx := r.position.x + r.size.x * 0.5
	var top_w := r.size.x * 0.46
	var bot_w := r.size.x * 0.5
	var y0 := r.position.y
	var y1 := r.position.y + r.size.y
	# mount
	ci.draw_rect(Rect2(cx - top_w * 0.5, y0 - 1.0, top_w, r.size.y * 0.28), _c(DARK, a))
	# bell
	var bell := PackedVector2Array([
		Vector2(cx - top_w * 0.42, y0 + r.size.y * 0.22), Vector2(cx + top_w * 0.42, y0 + r.size.y * 0.22),
		Vector2(cx + bot_w, y1), Vector2(cx - bot_w, y1)])
	ci.draw_colored_polygon(bell, _c(Color("4b5368"), a))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - top_w * 0.42, y0 + r.size.y * 0.22), Vector2(cx - top_w * 0.1, y0 + r.size.y * 0.22),
		Vector2(cx - bot_w * 0.35, y1), Vector2(cx - bot_w, y1)]), _c(Color("7a859e"), a))
	ci.draw_rect(Rect2(cx - bot_w, y1 - 3.0, bot_w * 2.0, 3.0), _c(Color("2a3142"), a))
	if id == "phoenix":
		pass


static func draw_tank(ci: CanvasItem, id: String, r: Rect2, a: float) -> void:
	# fins first (behind body)
	var yb := r.position.y + r.size.y
	for sgn in [-1.0, 1.0]:
		var x0: float = r.position.x + (r.size.x if sgn > 0.0 else 0.0)
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x0, yb - 38.0), Vector2(x0 + sgn * 22.0, yb + 6.0), Vector2(x0, yb - 4.0)]), _c(DARK, a))
	ci.draw_rect(r, _c(WHITE, a))
	ci.draw_rect(Rect2(r.position.x + r.size.x * 0.68, r.position.y, r.size.x * 0.32, r.size.y), _c(SHADE, a))
	ci.draw_rect(Rect2(r.position.x + 5.0, r.position.y, 4.0, r.size.y), _c(Color.WHITE, a * 0.7))
	# bands
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 7.0), _c(DARK, a))
	ci.draw_rect(Rect2(r.position.x, yb - 7.0, r.size.x, 7.0), _c(DARK, a))
	var y := r.position.y + 30.0
	while y < yb - 14.0:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x + r.size.x, y), _c(Color("93a1c0"), a), 1.5)
		y += 28.0
	# emblem
	var mid := Vector2(r.position.x + r.size.x * 0.42, r.position.y + r.size.y * 0.5)
	ci.draw_circle(mid, 7.0, _c(BLUE, a))
	ci.draw_arc(mid, 7.0, 0.0, TAU, 20, _c(DARK, a), 1.5)
	ci.draw_rect(Rect2(r.position, r.size), _c(DARK, a * 0.55), false, 1.5)


static func draw_nose(ci: CanvasItem, id: String, r: Rect2, a: float) -> void:
	var pts := _nose_points(id, r, 1.0)
	ci.draw_colored_polygon(pts, _c(WHITE, a))
	var right := _nose_points(id, r, 0.0)
	ci.draw_colored_polygon(right, _c(SHADE, a))
	ci.draw_rect(Rect2(r.position.x, r.position.y + r.size.y - 7.0, r.size.x, 7.0), _c(DARK, a))
	ci.draw_polyline(pts, _c(DARK, a * 0.6), 1.5, true)
	var win := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.62)
	ci.draw_circle(win, 6.0, _c(Color("1b2a4a"), a))
	ci.draw_circle(win - Vector2(1.5, 1.5), 2.5, _c(Color("7fc4ff"), a))


## Closed outline of the ogive nose. side = 1 -> full shape; 0 -> only the (darker) right third.
static func _nose_points(id: String, r: Rect2, side: float) -> PackedVector2Array:
	var steps := 14
	var cx := r.position.x + r.size.x * 0.5
	var half := r.size.x * 0.5
	var expo := 0.8 if id == "std" else 1.25
	var left := PackedVector2Array()
	var rightp := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)  # 0 = base, 1 = tip
		var w := half * pow(maxf(0.0, 1.0 - pow(t, 2.0)), expo * 0.6)
		var y := r.position.y + r.size.y * (1.0 - t)
		left.append(Vector2(cx - w, y))
		rightp.append(Vector2(cx + w, y))
	var out := PackedVector2Array()
	if side > 0.5:
		out.append_array(left)
		rightp.reverse()
		out.append_array(rightp)
		return out
	# right third strip
	for i in rightp.size():
		var p: Vector2 = rightp[i]
		out.append(Vector2(cx + (p.x - cx) * 0.34, p.y))
	var back := PackedVector2Array()
	for i in rightp.size():
		back.append(rightp[rightp.size() - 1 - i])
	out.append_array(back)
	return out

