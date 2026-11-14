class_name SpaceBackdrop
extends Control
## Animated space background: gradient, nebula, twinkling parallax stars and a
## slowly rotating Earth. Also provides static helpers to draw the Earth anywhere.

@export var show_earth: bool = true
@export var earth_visible: float = 0.30

var _stars: Array[Vector4] = []
var _phase := PackedFloat32Array()
var _t := 0.0

static var _land: Array = []
static var _clouds: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 280:
		_stars.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(0.5, 2.0), float(rng.randi_range(0, 2))))
		_phase.append(rng.randf() * TAU)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	var top := Color("01030a")
	var bot := Color("06142c")
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([top, top, bot, bot]))
	for i in 6:
		var f := float(i) / 6.0
		draw_circle(Vector2(s.x * 0.18, s.y * 0.30), s.x * (0.30 - 0.04 * i), Color(0.18, 0.25, 0.65, 0.012))
		draw_circle(Vector2(s.x * 0.78, s.y * 0.18), s.x * (0.24 - 0.035 * i), Color(0.45, 0.15, 0.55, 0.011))
		draw_circle(Vector2(s.x * 0.55, s.y * 0.45), s.x * (0.2 - 0.03 * i), Color(0.1, 0.35, 0.6, 0.01 + f * 0.0))
	for i in _stars.size():
		var st := _stars[i]
		var layer := int(st.w)
		var speed := 3.0 + layer * 6.0
		var x := fposmod(st.x * s.x + _t * speed, s.x)
		var tw := 0.6 + 0.4 * sin(_t * (1.2 + layer * 0.6) + _phase[i])
		draw_circle(Vector2(x, st.y * s.y), st.z * (0.7 + layer * 0.25),
			Color(0.8, 0.9, 1.0, tw * (0.4 + 0.2 * layer)))
	# shooting star
	var ph := fposmod(_t, 7.0)
	if ph < 0.7:
		var k := ph / 0.7
		var p0 := Vector2(s.x * 0.8 - k * s.x * 0.35, s.y * 0.08 + k * s.y * 0.22)
		draw_line(p0, p0 + Vector2(70, -26) * (1.0 - k), Color(1, 1, 1, 0.8 * (1.0 - k)), 2.0, true)
	if show_earth:
		var r := s.x * 0.95
		var c := Vector2(s.x * 0.5, s.y + r - s.y * earth_visible)
		draw_earth(self, c, r, _t)
		# tiny orbiting satellite
		var a := -PI * 0.5 + (fposmod(_t * 0.04, 1.0) - 0.5) * 1.3
		var sp := c + Vector2.from_angle(a) * (r + 34.0)
		draw_circle(sp, 6.0, Color(1, 0.75, 0.4, 0.15))
		draw_rect(Rect2(sp - Vector2(3, 2), Vector2(6, 4)), Color("dfe9ff"))
		draw_rect(Rect2(sp - Vector2(11, 1.5), Vector2(7, 3)), Color("4aa0ff"))
		draw_rect(Rect2(sp + Vector2(4, -1.5), Vector2(7, 3)), Color("4aa0ff"))


# ----------------------------------------------------------- shared Earth ---
static func _make_blob(rng: RandomNumberGenerator, rho: float, ang: float, rad: float, n: int) -> Dictionary:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		pts.append(Vector2.from_angle(a) * rad * rng.randf_range(0.55, 1.0))
	return {"c": Vector2.from_angle(ang) * rho, "pts": pts}


static func _ensure_blobs() -> void:
	if not _land.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		_land.append(_make_blob(rng, rng.randf_range(0.5, 0.86), rng.randf() * TAU, rng.randf_range(0.04, 0.10), 14))
	rng.seed = 99
	for i in 44:
		_clouds.append(_make_blob(rng, rng.randf_range(0.4, 0.88), rng.randf() * TAU, rng.randf_range(0.025, 0.06), 10))


## Draws a stylised Earth disc (ocean, rotating continents and clouds, glowing atmosphere).
static func draw_earth(ci: CanvasItem, c: Vector2, r: float, t: float, alpha: float = 1.0) -> void:
	_ensure_blobs()
	for i in 10:
		var f := float(i) / 10.0
		ci.draw_circle(c, r * (1.0 + 0.05 * (1.0 - f)), Color(0.25, 0.55, 1.0, (0.02 + 0.012 * f) * alpha))
	ci.draw_circle(c, r, Color(0.04, 0.14, 0.33, alpha))
	ci.draw_circle(c, r * 0.96, Color(0.06, 0.23, 0.48, alpha))
	ci.draw_circle(c, r * 0.80, Color(0.07, 0.28, 0.56, alpha))
	var a := t * 0.03
	for b in _land:
		var cc: Vector2 = (b["c"] as Vector2).rotated(a) * r
		var poly := PackedVector2Array()
		for p in (b["pts"] as PackedVector2Array):
			poly.append(c + cc + p.rotated(a) * r)
		ci.draw_colored_polygon(poly, Color(0.15, 0.42, 0.26, 0.95 * alpha))
	var a2 := t * 0.045 + 1.0
	for b in _clouds:
		var cc2: Vector2 = (b["c"] as Vector2).rotated(a2) * r
		var poly2 := PackedVector2Array()
		for p in (b["pts"] as PackedVector2Array):
			poly2.append(c + cc2 + p.rotated(a2) * r)
		ci.draw_colored_polygon(poly2, Color(1, 1, 1, 0.32 * alpha))
	ci.draw_arc(c, r, 0.0, TAU, 180, Color(0.5, 0.78, 1.0, 0.85 * alpha), maxf(2.0, r * 0.004), true)
